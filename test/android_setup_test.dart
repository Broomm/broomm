import 'dart:async';
import 'dart:io';

import 'package:broomm/src/android/azahar.dart';
import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/android/setup.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final useFallback in [false, true]) {
    test(
      'Azahar ${useFallback ? 'requires explicit shared fallback after failed verification' : 'persists the verified scoped package and folder'}',
      () async {
        const channel = MethodChannel('app.broomm/azahar-setup-test');
        const tree =
            'content://com.android.externalstorage.documents/tree/primary%3ADocuments%2FAzahar';
        final emulator = androidEmulators.singleWhere((e) => e.id == 'azahar');
        final data = await Directory.systemTemp.createTemp('broomm-azahar-');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final checks = <Map>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'installed':
              return [
                {
                  'package': androidAzaharScopedPackage,
                  'build': 'a' * 64,
                  'version': androidAzaharScopedVersion,
                },
                {
                  'package': 'org.azahar_emu.azahar',
                  'build': 'b' * 64,
                  'version': '2126.2-vanilla',
                },
              ];
            case 'sharedPick':
              expect(call.arguments['package'], androidAzaharScopedPackage);
              return tree;
            case 'sharedCheck':
              final binding = call.arguments as Map;
              checks.add(binding);
              if (useFallback && binding.containsKey('access'))
                throw PlatformException(code: 'folder-mismatch');
              return null;
            case 'ioBusy':
              return false;
            default:
              throw StateError(call.method);
          }
        });
        final manager = AndroidEmulators(data, channel: channel, enabled: true);
        final setup = AndroidEmulatorSetup(manager, emulator, '3ds', 'a' * 32);
        try {
          await manager.load();
          await setup.verify();
          await setup.selectFolder();
          expect(checks.single['access'], androidAzaharRootFolderAccess);
          expect(checks.single['azaharBuild'], 'a' * 64);
          if (useFallback) {
            expect(setup.problem, contains('folder-mismatch'));
            expect(setup.step, AndroidSetupStep.folder);
            expect(manager.folder(emulator), isNull);
            await setup.useSharedFolder();
            await setup.selectFolder();
            expect(checks.last['access'], isNull);
          }
          expect(setup.step, AndroidSetupStep.ready);
          await manager.load();
          expect(manager.folder(emulator)?['tree'], tree);
          expect(
            manager.folder(emulator)?['access'],
            useFallback ? null : androidAzaharRootFolderAccess,
          );
        } finally {
          setup.dispose();
          manager.dispose();
          messenger.setMockMethodCallHandler(channel, null);
          await data.delete(recursive: true);
        }
      },
    );
  }
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
