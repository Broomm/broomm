import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../progress/files.dart';
import 'protocol.dart';

/// Cemu's native DSU controller/touch backend. This endpoint never leaves
/// loopback and does not create an operating-system controller device.
class CemuRemoteInput {
  CemuRemoteInput({int Function()? milliseconds, this.onProblem})
    : _milliseconds = milliseconds {
    _clock.start();
  }
  final int Function()? _milliseconds;
  final void Function(String)? onProblem;
  final _clock = Stopwatch();
  int get _now => _milliseconds?.call() ?? _clock.elapsedMilliseconds;
  final _identity = int.parse(progressNonce().substring(0, 8), radix: 16);
  final _clients = <String, (InternetAddress, int, int)>{};
  RawDatagramSocket? _socket;
  Completer<void>? _closedSocket;
  Future<void>? _stopping;
  Timer? _timer;
  RemotePad _pad = RemotePad.neutral;
  RemoteTouch _touch = RemoteTouch.released;
  bool _present = false, _releasePending = false;
  int _padAt = -1000, _touchAt = -1000, _pressedAt = 0, _sequence = 0;
  int _requestWindow = 0, _requests = 0;
  int _generation = 0;
  Future<void>? _starting;
  int? get port => _socket?.port;
  bool get hasReader => _clients.values.any((e) => _now - e.$3 <= 5000);

  Future<void> start() =>
      _starting ??= _start().whenComplete(() => _starting = null);
  Future<void> _start() async {
    await _stopping;
    if (_socket != null) throw StateError('Cemu input is already running.');
    final generation = ++_generation;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    if (generation != _generation) {
      socket.close();
      throw StateError('Cemu input startup was cancelled.');
    }
    _socket = socket;
    final closed = _closedSocket = Completer<void>();
    socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        for (var i = 0; i < 32; i++) {
          final packet = socket.receive();
          if (packet == null) break;
          if (_now - _requestWindow >= 1000) {
            _requestWindow = _now;
            _requests = 0;
          }
          if (++_requests <= 64) _request(packet);
        }
      },
      onDone: () {
        if (!closed.isCompleted) closed.complete();
      },
      onError: (Object error) {
        if (!identical(_socket, socket)) return;
        close();
        onProblem?.call(
          'Local Cemu input stopped. Restart Remote screen to reconnect it.',
        );
      },
    );
    _timer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _publish(),
    );
  }

  void pad(RemotePad value, bool present) {
    _pad = value;
    _present = present;
    _padAt = _now;
    if (!present) {
      _touch = RemoteTouch.released;
      _releasePending = false;
    }
  }

  void touch(RemoteTouch value) {
    RemoteTouch.read(value.json, size: RemoteScreenSize.wiiu);
    _touchAt = _now;
    if (!value.pressed && _touch.pressed && _now - _pressedAt < 20) {
      _releasePending = true;
      return;
    }
    if (value.pressed && !_touch.pressed) _pressedAt = _now;
    _touch = value;
    _releasePending = false;
  }

  void _expire() {
    if (_now - _padAt > 350) _present = false;
    if (!_present ||
        _now - _touchAt > 350 ||
        (_releasePending && _now - _pressedAt >= 20)) {
      _touch = RemoteTouch.released;
      _releasePending = false;
    }
    _clients.removeWhere((_, endpoint) => _now - endpoint.$3 > 5000);
  }

  void _request(Datagram packet) {
    final bytes = packet.data;
    if (!packet.address.isLoopback ||
        bytes.length < 20 ||
        bytes.length > 28 ||
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'DSUC')
      return;
    final view = ByteData.sublistView(bytes);
    if (view.getUint16(4, Endian.little) != 1001 ||
        view.getUint16(6, Endian.little) != bytes.length - 16)
      return;
    final expected = view.getUint32(8, Endian.little);
    final checked = Uint8List.fromList(bytes);
    ByteData.sublistView(checked).setUint32(8, 0, Endian.little);
    if (dsuCrc32(checked) != expected) return;
    _expire();
    final kind = view.getUint32(16, Endian.little);
    if (kind == 0x100000 && bytes.length == 20) {
      final reply = _packet(kind, 24);
      ByteData.sublistView(reply).setUint16(20, 1001, Endian.little);
      _send(reply, packet.address, packet.port);
    } else if (kind == 0x100001 && bytes.length >= 25) {
      final count = view.getUint32(20, Endian.little);
      if (count < 1 || count > 4 || bytes.length < 24 + count) return;
      for (var i = 0; i < count; i++) {
        if (bytes[24 + i] > 3) return;
      }
      for (var i = 0; i < count; i++) {
        final reply = _packet(kind, 32);
        _portInfo(reply, bytes[24 + i]);
        _send(reply, packet.address, packet.port);
      }
    } else if (kind == 0x100002 && bytes.length == 28) {
      final flags = bytes[20];
      if (flags > 3 ||
          ((flags & 1) != 0 && bytes[21] != 0) ||
          ((flags & 2) != 0 && !_sameMac(bytes, 22)))
        return;
      final key = '${packet.address.address}:${packet.port}';
      if (!_clients.containsKey(key) && _clients.length >= 4) return;
      _clients[key] = (packet.address, packet.port, _now);
      _send(_sample(), packet.address, packet.port);
    }
  }

  static const _mac = [0x02, 0x42, 0x52, 0x4d, 0x00, 0x01];
  bool _sameMac(Uint8List bytes, int offset) {
    for (var i = 0; i < 6; i++) {
      if (bytes[offset + i] != _mac[i]) return false;
    }
    return true;
  }

  Uint8List _packet(int kind, int length) {
    final packet = Uint8List(length)..setRange(0, 4, ascii.encode('DSUS'));
    final view = ByteData.sublistView(packet);
    view.setUint16(4, 1001, Endian.little);
    view.setUint16(6, length - 16, Endian.little);
    view.setUint32(12, _identity, Endian.little);
    view.setUint32(16, kind, Endian.little);
    return packet;
  }

  void _portInfo(Uint8List packet, int index) {
    packet[20] = index;
    final connected = index == 0 && _present;
    packet[21] = connected ? 2 : 0;
    packet[22] = 2; // DS4 protocol layout; Cemu maps this to its Wii U GamePad.
    packet[23] = 1;
    packet.setRange(24, 30, _mac);
    packet[30] = 5;
    packet[31] = connected ? 1 : 0;
  }

  Uint8List _sample() {
    _expire();
    final packet = _packet(0x100002, 100);
    final view = ByteData.sublistView(packet);
    _portInfo(packet, 0);
    view.setUint32(32, _sequence++ & 0xffffffff, Endian.little);
    final pad = _present ? _pad : RemotePad.neutral;
    bool down(int button) => (pad.buttons & (1 << button)) != 0;
    const first = [4, 7, 8, 6, 11, 14, 12, 13];
    const second = [9, 10, 3, 1, 0, 2];
    for (var bit = 0; bit < first.length; bit++) {
      if (down(first[bit])) packet[36] |= 1 << bit;
    }
    if (pad.axes[4] > 16383) packet[37] |= 1;
    if (pad.axes[5] > 16383) packet[37] |= 2;
    for (var bit = 0; bit < second.length; bit++) {
      if (down(second[bit])) packet[37] |= 1 << (bit + 2);
    }
    packet[38] = down(5) ? 1 : 0;
    int axis(int value) => ((value + 32768) * 255 ~/ 65535).clamp(0, 255);
    packet[40] = axis(pad.axes[0]);
    packet[41] = 255 - axis(pad.axes[1]);
    packet[42] = axis(pad.axes[2]);
    packet[43] = 255 - axis(pad.axes[3]);
    const pressure = [13, 12, 14, 11, 2, 0, 1, 3, 10, 9];
    for (var i = 0; i < pressure.length; i++) {
      packet[44 + i] = down(pressure[i]) ? 255 : 0;
    }
    packet[54] = pad.axes[5] * 255 ~/ 32767;
    packet[55] = pad.axes[4] * 255 ~/ 32767;
    if (_touch.pressed) {
      packet[56] = 1;
      view.setUint16(58, _touch.x * 1920 ~/ 853, Endian.little);
      view.setUint16(60, _touch.y * 942 ~/ 479, Endian.little);
    }
    view.setUint64(68, _now * 1000, Endian.little);
    view.setFloat32(80, 1.0, Endian.little); // Stationary +Y gravity, no gyro.
    return packet;
  }

  void _publish() {
    _expire();
    if (_clients.isEmpty) return;
    final packet = _sample();
    for (final endpoint in _clients.values) {
      _send(packet, endpoint.$1, endpoint.$2);
    }
  }

  void _send(Uint8List bytes, InternetAddress address, int port) {
    final view = ByteData.sublistView(bytes);
    view.setUint32(8, 0, Endian.little);
    view.setUint32(8, dsuCrc32(bytes), Endian.little);
    try {
      _socket?.send(bytes, address, port);
    } on SocketException {
      // A disappearing local reader does not interrupt the authenticated link.
    }
  }

  Future<void> close() {
    ++_generation;
    _timer?.cancel();
    _timer = null;
    final socket = _socket;
    socket?.close();
    _socket = null;
    if (socket != null) _stopping = _closedSocket!.future;
    _clients.clear();
    _present = false;
    _pad = RemotePad.neutral;
    _touch = RemoteTouch.released;
    return _stopping ?? Future<void>.value();
  }
}

int dsuCrc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
