import 'dart:io';

import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/progress/files.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.broomm/removal-test');
  const package = 'org.ppsspp.ppsspp';
  final emulator = androidEmulators.singleWhere((e) => e.id == 'ppsspp');
  const tree =
      'content://com.android.externalstorage.documents/tree/primary%3APSP';
  late Directory data;
  late AndroidEmulators manager;
  var installed = true, cancel = false, unknown = false, failCleanup = false;
  final calls = <String>[];
  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-removal-');
    installed = true;
    cancel = unknown = failCleanup = false;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'installed':
              return [
                if (installed)
                  {'package': package, 'version': '1.20.4', 'build': 'a' * 64},
              ];
            case 'sharedCheck':
            case 'clearEmulatorSetup':
              return null;
            case 'ioBusy':
              return false;
            case 'uninstall':
              expect((call.arguments as Map)['package'], package);
              expect((call.arguments as Map)['build'], 'a' * 64);
              if (unknown) return null;
              if (!cancel) installed = false;
              return !cancel;
            default:
              throw StateError(call.method);
          }
        });
    manager = AndroidEmulators(data, channel: channel, enabled: true)
      ..onRemoved = (_) async {
        if (failCleanup) throw StateError('Preference storage unavailable');
      };
    await manager.load();
    await manager.confirmSharedStorage(emulator, tree);
  });
  tearDown(() async {
    manager.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await data.delete(recursive: true);
  });

  test(
    'confirmed uninstall clears connections and retains Broomm progress',
    () async {
      final save = File(
        '${data.path}/profiles/test/emulators/ppsspp/user/save.bin',
      );
      await save.parent.create(recursive: true);
      await save.writeAsBytes([1, 4, 9]);
      expect(
        await manager.remove(emulator, expected: manager.app(emulator)),
        isTrue,
      );
      expect(manager.app(emulator), isNull);
      expect(manager.folder(emulator), isNull);
      expect(await manager.pendingRemoval(), isNull);
      expect(await save.readAsBytes(), [1, 4, 9]);
      await manager.load();
      expect(manager.folder(emulator), isNull);
    },
  );

  test('cancelled or unverified uninstall keeps the configuration and pending recovery', () async {
    final settings = File('${data.path}/android/emulators.json');
    final before = await settings.readAsBytes();
    cancel = true;
    expect(
      await manager.remove(emulator, expected: manager.app(emulator)),
      isFalse,
    );
    expect(await settings.readAsBytes(), before);
    expect(await manager.pendingRemoval(), isNull);
    unknown = true;
    await expectLater(
      manager.remove(emulator, expected: manager.app(emulator)),
      throwsStateError,
    );
    expect(await settings.readAsBytes(), before);
    expect(await manager.pendingRemoval(), isNotNull);
    await expectLater(manager.ensureSetupAllowed(), throwsStateError);
    installed = false;
    await manager.load();
    expect(await manager.remove(emulator), isTrue);
    expect(await manager.pendingRemoval(), isNull);
    expect(calls.where((c) => c == 'uninstall').length, 2);
  });

  test(
    'a failed post-uninstall cleanup resumes without another uninstall',
    () async {
      failCleanup = true;
      await expectLater(
        manager.remove(emulator, expected: manager.app(emulator)),
        throwsStateError,
      );
      expect(installed, isFalse);
      expect(await manager.pendingRemoval(), isNotNull);
      await manager.load();
      failCleanup = false;
      expect(await manager.remove(emulator), isTrue);
      expect(await manager.pendingRemoval(), isNull);
      expect(calls.where((c) => c == 'uninstall').length, 1);
    },
  );

  test(
    'a held session lock and an unfinished save journal both exclude uninstall',
    () async {
      final lease = await SessionLease.acquire(data);
      await expectLater(
        manager.remove(emulator, expected: manager.app(emulator)),
        throwsStateError,
      );
      await lease.release();
      await progressWrite(
        await progressFile(
          data,
          'android/shared-swap.json',
          createParents: true,
        ),
        {'version': 1},
      );
      await expectLater(
        manager.remove(emulator, expected: manager.app(emulator)),
        throwsStateError,
      );
      expect(calls, isNot(contains('uninstall')));
      expect(manager.folder(emulator), isNotNull);
    },
  );
}
