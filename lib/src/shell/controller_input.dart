import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

// Launcher navigation only. Gameplay assignment still uses the emulator's own
// SDL bridge. macOS/Android forward their native APIs through the Flutter channel.
class ShellControllerInput {
  ShellControllerInput({required this.dispatch});
  final void Function(String) dispatch;
  Timer? _timer, _scan;
  _WindowsPads? _windows;
  _LinuxPads? _linux;
  void start() {
    try {
      if (Platform.isWindows) _windows = _WindowsPads(dispatch);
      if (Platform.isLinux) {
        _linux = _LinuxPads(dispatch);
        unawaited(_linux!.scan());
        _scan = Timer.periodic(
          const Duration(seconds: 2),
          (_) => unawaited(_linux!.scan()),
        );
      }
      if (_windows != null || _linux != null)
        _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
          _windows?.poll();
          _linux?.poll();
        });
    } on ArgumentError {
      /* Unsupported native API: keyboard/Steam key events remain available. */
    }
  }

  void dispose() {
    _timer?.cancel();
    _scan?.cancel();
    _windows?.close();
    _linux?.close();
  }
}

class NavigationRepeat {
  NavigationRepeat(this.dispatch);
  final void Function(String) dispatch;
  String? _direction;
  Duration _next = Duration.zero;
  final clock = Stopwatch()..start();
  void update(String? direction) {
    if (direction != _direction) {
      _direction = direction;
      if (direction != null) {
        dispatch(direction);
        _next = clock.elapsed + const Duration(milliseconds: 400);
      }
      return;
    }
    if (direction != null && clock.elapsed >= _next) {
      dispatch(direction);
      _next = clock.elapsed + const Duration(milliseconds: 120);
    }
  }
}

class _WindowsPads {
  _WindowsPads(this.dispatch) {
    DynamicLibrary? xinput;
    for (final name in ['xinput1_4.dll', 'xinput9_1_0.dll']) {
      try {
        xinput = DynamicLibrary.open(name);
        break;
      } on ArgumentError {
        continue;
      }
    }
    if (xinput == null) throw ArgumentError('XInput unavailable');
    get = xinput
        .lookupFunction<
          Uint32 Function(Uint32, Pointer<Uint8>),
          int Function(int, Pointer<Uint8>)
        >('XInputGetState');
    final crt = DynamicLibrary.open('msvcrt.dll');
    final calloc = crt
        .lookupFunction<
          Pointer<Uint8> Function(IntPtr, IntPtr),
          Pointer<Uint8> Function(int, int)
        >('calloc');
    free = crt
        .lookupFunction<
          Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)
        >('free');
    buffer = calloc(1, 16);
    if (buffer == nullptr) throw ArgumentError('Allocation failed');
    repeat = NavigationRepeat(dispatch);
  }
  final void Function(String) dispatch;
  late final int Function(int, Pointer<Uint8>) get;
  late final void Function(Pointer<Uint8>) free;
  late final Pointer<Uint8> buffer;
  late final NavigationRepeat repeat;
  final previous = <int, int>{};
  final enterHeld = <int, bool>{};
  bool shift = false;
  void poll() {
    String? direction;
    var shifted = false;
    final actions = <String>[];
    for (var i = 0; i < 4; i++) {
      if (get(i, buffer) != 0) {
        previous.remove(i);
        enterHeld.remove(i);
        continue;
      }
      final b = ByteData.sublistView(buffer.asTypedList(16)),
          buttons = b.getUint16(4, Endian.little);
      final edges = buttons & ~(previous[i] ?? buttons);
      previous[i] = buttons;
      shifted |= b.getUint8(6) > 140;
      final enter = b.getUint8(7) > 140;
      if (enter && enterHeld[i] == false) actions.add('keyboard-enter');
      enterHeld[i] = enter;
      for (final entry in {
        0x1000: 'accept',
        0x2000: 'back',
        0x4000: 'search',
        0x8000: 'space',
        0x40: 'caps',
        0x100: 'caret-left',
        0x200: 'caret-right',
        0x10: 'home',
        0x20: 'options',
      }.entries) {
        if (edges & entry.key != 0) actions.add(entry.value);
      }
      final x = b.getInt16(8, Endian.little), y = b.getInt16(10, Endian.little);
      direction ??= buttons & 1 != 0 || y > 18000
          ? 'up'
          : buttons & 2 != 0 || y < -18000
          ? 'down'
          : buttons & 4 != 0 || x < -18000
          ? 'left'
          : buttons & 8 != 0 || x > 18000
          ? 'right'
          : null;
    }
    if (shift != shifted) {
      shift = shifted;
      dispatch(shift ? 'shift-down' : 'shift-up');
    }
    for (final action in actions) dispatch(action);
    repeat.update(direction);
  }

  void close() {
    if (shift) dispatch('shift-up');
    free(buffer);
  }
}

class _LinuxDevice {
  _LinuxDevice(
    this.path,
    this.fd,
    this.xMin,
    this.xMax,
    this.yMin,
    this.yMax,
    this.ltMin,
    this.ltMax,
    this.rtMin,
    this.rtMax,
  ) : lt = ltMin,
      rt = rtMin;
  final String path;
  final int fd, xMin, xMax, yMin, yMax, ltMin, ltMax, rtMin, rtMax;
  int lt, rt;
  bool triggerButton = false, enterButton = false, enterHeld = false;
  bool get shift =>
      triggerButton || ltMax > ltMin && (lt - ltMin) / (ltMax - ltMin) > .55;
  bool get enter =>
      enterButton || rtMax > rtMin && (rt - rtMin) / (rtMax - rtMin) > .55;
  int x = 0, y = 0, hx = 0, hy = 0;
  bool dropping = false;
}

class _LinuxPads {
  _LinuxPads(this.dispatch) {
    final libc = DynamicLibrary.process();
    open = libc
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, Int32),
          int Function(Pointer<Uint8>, int)
        >('open');
    read = libc
        .lookupFunction<
          IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
          int Function(int, Pointer<Uint8>, int)
        >('read');
    ioctl = libc
        .lookupFunction<
          Int32 Function(Int32, UnsignedLong, Pointer<Uint8>),
          int Function(int, int, Pointer<Uint8>)
        >('ioctl');
    closeFd = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
      'close',
    );
    calloc = libc
        .lookupFunction<
          Pointer<Uint8> Function(IntPtr, IntPtr),
          Pointer<Uint8> Function(int, int)
        >('calloc');
    free = libc
        .lookupFunction<
          Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)
        >('free');
    buffer = calloc(1, 2048);
    if (buffer == nullptr) throw ArgumentError('Allocation failed');
    repeat = NavigationRepeat(dispatch);
  }
  final void Function(String) dispatch;
  late final int Function(Pointer<Uint8>, int) open;
  late final int Function(int, Pointer<Uint8>, int) read;
  late final int Function(int, int, Pointer<Uint8>) ioctl;
  late final int Function(int) closeFd;
  late final Pointer<Uint8> Function(int, int) calloc;
  late final void Function(Pointer<Uint8>) free;
  late final Pointer<Uint8> buffer;
  late final NavigationRepeat repeat;
  final devices = <String, _LinuxDevice>{};
  bool scanning = false, closed = false;
  bool shift = false;
  Future<void> scan() async {
    if (scanning || closed) return;
    scanning = true;
    try {
      final input = Directory('/dev/input');
      if (!await input.exists()) return;
      final paths = <String>{};
      await for (final entry in input.list(followLinks: false)) {
        if (!RegExp(r'/event\d+$').hasMatch(entry.path)) continue;
        paths.add(entry.path);
        final existing = devices[entry.path];
        if (existing != null) {
          if (ioctl(existing.fd, 0x80044501, buffer) >= 0)
            continue; // EVIOCGVERSION also detects a dead descriptor.
          closeFd(existing.fd);
          devices.remove(entry.path);
        }
        if (closed) continue;
        final path = calloc(entry.path.length + 1, 1);
        path
            .asTypedList(entry.path.length + 1)
            .setRange(0, entry.path.length, entry.path.codeUnits);
        final fd = open(path, 0x800 | 0x80000);
        free(path); // O_NONBLOCK | O_CLOEXEC, read-only
        if (fd < 0) continue;
        final caps = buffer.asTypedList(128);
        caps.fillRange(0, 128, 0);
        if (ioctl(fd, 0x80804521, buffer) < 0 ||
            caps[304 ~/ 8] & (1 << (304 % 8)) == 0) {
          closeFd(fd);
          continue;
        }
        List<int> range(int axis) {
          if (ioctl(fd, 0x80184540 + axis, buffer) < 0) return [-32768, 32767];
          final data = ByteData.sublistView(buffer.asTypedList(24));
          return [data.getInt32(4, Endian.host), data.getInt32(8, Endian.host)];
        }

        final x = range(0), y = range(1), lt = range(2), rt = range(5);
        devices[entry.path] =
            _LinuxDevice(
                entry.path,
                fd,
                x[0],
                x[1],
                y[0],
                y[1],
                lt[0],
                lt[1],
                rt[0],
                rt[1],
              )
              ..x = (x[0] + x[1]) ~/ 2
              ..y = (y[0] + y[1]) ~/ 2;
      }
      for (final path in devices.keys.toList()) {
        if (!paths.contains(path)) {
          closeFd(devices.remove(path)!.fd);
        }
      }
    } on FileSystemException {
      /* Input permission/absence must never block startup. */
    } finally {
      scanning = false;
    }
  }

  void poll() {
    String? direction;
    final actions = <String>[];
    final eventSize = sizeOf<IntPtr>() * 2 + 8;
    for (final device in devices.values) {
      // A bounded nonblocking read prevents a noisy device monopolizing a frame.
      final count = read(device.fd, buffer, eventSize * 32);
      if (count > 0) {
        final data = ByteData.sublistView(buffer.asTypedList(count));
        for (var offset = 0; offset + eventSize <= count; offset += eventSize) {
          final base = offset + sizeOf<IntPtr>() * 2,
              type = data.getUint16(base, Endian.host),
              code = data.getUint16(base + 2, Endian.host),
              value = data.getInt32(base + 4, Endian.host);
          if (type == 0 && code == 3) {
            device.dropping = true;
            device.hx = 0;
            device.hy = 0;
            device.rt = device.rtMin;
            device.lt = device.ltMin;
            device.triggerButton = false;
            device.enterButton = device.enterHeld = false;
            device.x = (device.xMin + device.xMax) ~/ 2;
            device.y = (device.yMin + device.yMax) ~/ 2;
            continue;
          }
          if (device.dropping) {
            if (type == 0 && code == 0) device.dropping = false;
            continue;
          }
          if (type == 1 && code == 312) device.triggerButton = value != 0;
          if (type == 1 && code == 313) device.enterButton = value != 0;
          if (type == 1 && value == 1) {
            final action = switch (code) {
              304 => 'accept',
              305 => 'back',
              308 => 'search',
              307 => 'space',
              317 => 'caps',
              310 => 'caret-left',
              311 => 'caret-right',
              315 => 'home',
              314 => 'options',
              _ => null,
            };
            if (action != null) actions.add(action);
          }
          if (type == 3) {
            switch (code) {
              case 0:
                device.x = value;
              case 1:
                device.y = value;
              case 16:
                device.hx = value;
              case 17:
                device.hy = value;
              case 5:
                device.rt = value;
              case 2:
                device.lt = value;
            }
          }
          final enter = device.enter;
          if (enter && !device.enterHeld) actions.add('keyboard-enter');
          device.enterHeld = enter;
        }
      }
      final xRange = device.xMax - device.xMin,
          yRange = device.yMax - device.yMin;
      final x = xRange <= 0
          ? 0
          : (device.x - (device.xMin + device.xMax) / 2) / xRange * 2;
      final y = yRange <= 0
          ? 0
          : (device.y - (device.yMin + device.yMax) / 2) / yRange * 2;
      direction ??= device.hy < 0 || y < -.55
          ? 'up'
          : device.hy > 0 || y > .55
          ? 'down'
          : device.hx < 0 || x < -.55
          ? 'left'
          : device.hx > 0 || x > .55
          ? 'right'
          : null;
    }
    final shifted = devices.values.any((d) => d.shift);
    if (shift != shifted) {
      shift = shifted;
      dispatch(shift ? 'shift-down' : 'shift-up');
    }
    for (final action in actions) dispatch(action);
    repeat.update(direction);
  }

  void close() {
    if (shift) dispatch('shift-up');
    closed = true;
    for (final d in devices.values) {
      closeFd(d.fd);
    }
    devices.clear();
    free(buffer);
  }
}
