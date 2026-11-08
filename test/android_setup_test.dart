import 'dart:async';
import 'dart:io';

import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/android/setup.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('setup continues after package readback and retains a cancelled folder choice', () async {
    const channel = MethodChannel('app.broomm/setup-test');
    final emulator = androidEmulators.singleWhere((e) => e.id == 'ppsspp');
    final data = await Directory.systemTemp.createTemp('broomm-setup-');
    var installed = false;
    String? picked;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'installed' => [
              if (installed)
                {
                  'package': 'org.ppsspp.ppsspp',
                  'build': 'a' * 64,
                  'version': '1.20.4',
                },
            ],
            'canInstallPackages' => true,
            'installApk' || 'sharedCheck' => null,
            'sharedPick' => picked,
            'ioBusy' => false,
            _ => throw StateError(call.method),
          };
        });
    final manager = AndroidEmulators(data, channel: channel, enabled: true);
    final setup = AndroidEmulatorSetup(manager, emulator, 'psp', 'a' * 32);
    try {
      await manager.load();
      await setup.verify();
      expect(setup.step, AndroidSetupStep.install);
      await setup.install(imported: true);
      expect(setup.step, AndroidSetupStep.waitingInstall);
      expect(calls, isNot(contains('sharedPick')));
      final continued = Completer<void>();
      setup.addListener(() {
        if (setup.step == AndroidSetupStep.initialize &&
            setup.problem != null &&
            !setup.busy &&
            !continued.isCompleted)
          continued.complete();
      });
      installed = true;
      await manager.load();
      await continued.future;
      await setup.useSharedFolder();
      await setup.selectFolder();
      expect(setup.step, AndroidSetupStep.folder);
      expect(manager.folder(emulator), isNull);
      picked =
          'content://com.android.externalstorage.documents/tree/primary%3APSP';
      await setup.selectFolder();
      expect(setup.step, AndroidSetupStep.ready);
      expect(manager.folder(emulator)?['tree'], picked);
      expect(calls, isNot(contains('rootMgbaSetup')));
    } finally {
      setup.dispose();
      manager.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await data.delete(recursive: true);
    }
  });
}
