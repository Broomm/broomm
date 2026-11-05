@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:broomm/src/shell/controller_input.dart';
import 'package:flutter_test/flutter_test.dart';

// A real blocking kernel read models evdev's synchronous teardown wait. Only
// this worker owns the read descriptor; the test releases it from the UI side.
void Function(SendPort) heldInputWorker(int fd, bool beforeHandshake) =>
    (SendPort output) {
      final native = DynamicLibrary.process();
      final calloc = native
          .lookupFunction<
            Pointer<Uint8> Function(IntPtr, IntPtr),
            Pointer<Uint8> Function(int, int)
          >('calloc');
      final free = native
          .lookupFunction<
            Void Function(Pointer<Uint8>),
            void Function(Pointer<Uint8>)
          >('free');
      final read = native
          .lookupFunction<
            IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
            int Function(int, Pointer<Uint8>, int)
          >('read');
      final close = native
          .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
      final control = ReceivePort();
      if (!beforeHandshake) output.send(control.sendPort);
      output.send('accept');
      final buffer = calloc(1, 1);
      read(fd, buffer, 1);
      free(buffer);
      if (beforeHandshake) output.send(control.sendPort);
      output.send('back');
      control.listen((_) {
        close(fd);
        control.close();
      });
    };

void main() {
  test('kernel capability words select gamepads rather than touch, mouse or keyboard devices', () {
    expect(
      linuxHasGamepadButton('7cdb000000000000 0 0 0 0\n', wordBits: 64),
      isTrue,
    );
    expect(
      linuxHasGamepadButton('10000 0 0 0 0 0 0 0 0 0', wordBits: 32),
      isTrue,
    );
    for (final value in [
      '0',
      '10000000000000 0',
      '400 0 0 0 0 0',
      '40 0 0 0 0 30 400000000 0 c000000000000 0',
    ]) {
      expect(linuxHasGamepadButton(value, wordBits: 64), isFalse);
    }
    // A capability in a different word must not become BTN_GAMEPAD.
    expect(linuxHasGamepadButton('1000000000000 0 0 0', wordBits: 64), isFalse);
  });

  test('unknown capability observations retain ioctl fallback and are re-read after hotplug', () async {
    final root = await Directory.systemTemp.createTemp('broomm-input-sysfs-');
    addTearDown(() => root.delete(recursive: true));
    final path = File('${root.path}/event7/device/capabilities/key');
    expect(
      await linuxEvdevGamepadCandidate(
        '/dev/input/event7',
        sysfsRoot: root.path,
      ),
      isNull,
    );
    await path.parent.create(recursive: true);
    await path.writeAsString('0');
    expect(
      await linuxEvdevGamepadCandidate(
        '/dev/input/event7',
        sysfsRoot: root.path,
      ),
      isFalse,
    );
    await path.writeAsString('7cdb000000000000 0 0 0 0');
    expect(
      await linuxEvdevGamepadCandidate(
        '/dev/input/event7',
        sysfsRoot: root.path,
      ),
      isTrue,
    );
    await path.writeAsString('unavailable');
    expect(
      await linuxEvdevGamepadCandidate(
        '/dev/input/event7',
        sysfsRoot: root.path,
      ),
      isNull,
    );
    expect(linuxHasGamepadButton(''), isNull);
    expect(linuxHasGamepadButton('10000000000000000', wordBits: 64), isNull);
    expect(linuxHasGamepadButton('100000000', wordBits: 32), isNull);
  });

  for (final beforeHandshake in [false, true]) {
    test(
      beforeHandshake
          ? 'dispose before worker startup drains its descriptors without delivering late input'
          : 'a blocked native input worker leaves the UI responsive and ignores actions after dispose',
      () async {
        final native = DynamicLibrary.process();
        final calloc = native
            .lookupFunction<
              Pointer<Int32> Function(IntPtr, IntPtr),
              Pointer<Int32> Function(int, int)
            >('calloc');
        final free = native
            .lookupFunction<
              Void Function(Pointer<Int32>),
              void Function(Pointer<Int32>)
            >('free');
        final pipe = native
            .lookupFunction<
              Int32 Function(Pointer<Int32>),
              int Function(Pointer<Int32>)
            >('pipe');
        final write = native
            .lookupFunction<
              IntPtr Function(Int32, Pointer<Int32>, IntPtr),
              int Function(int, Pointer<Int32>, int)
            >('write');
        final close = native
            .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
        final fds = calloc(2, sizeOf<Int32>());
        expect(pipe(fds), 0);
        final writeFd = fds[1];
        final actions = <String>[], accepted = Completer<void>();
        final input = LinuxControllerInput(
          dispatch: (action) {
            actions.add(action);
            if (!accepted.isCompleted) accepted.complete();
          },
          entryPoint: heldInputWorker(fds[0], beforeHandshake),
        );
        var released = false, finished = false;
        unawaited(
          input.done.then<void>((_) {
            finished = true;
          }),
        );
        try {
          input.start();
          if (!beforeHandshake) {
            await accepted.future.timeout(const Duration(seconds: 5));
            // This UI-side event cannot execute if native scanning runs here.
            await Future<void>.delayed(Duration.zero);
            expect(finished, isFalse);
            expect(actions, ['accept']);
          }
          input.close();
          input.close();
          expect(write(writeFd, fds, 1), 1);
          released = true;
          await input.done.timeout(const Duration(seconds: 5));
          expect(actions, beforeHandshake ? isEmpty : ['accept']);
        } finally {
          if (!released) write(writeFd, fds, 1);
          input.close();
          await input.done.timeout(const Duration(seconds: 5));
          close(writeFd);
          free(fds);
        }
      },
    );
  }
}
