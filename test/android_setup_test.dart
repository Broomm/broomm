import 'dart:async';
import 'dart:io';

import 'package:broomm/src/android/armsx2_root.dart';
import 'package:broomm/src/android/azahar.dart';
import 'package:broomm/src/android/citra_mmj.dart';
import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/android/setup.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Ps2Firmware extends RommClient {
  _Ps2Firmware() : super(Uri.parse('https://example.invalid'));

  final bytes = Uint8List(4 * 1024 * 1024)
    ..setAll(0, 'ROMDIR ROMVER'.codeUnits);
  bool badChecksum = false;

  @override
  Future<List<RommFirmware>> firmware(int platformId) async => [
    RommFirmware(
      1,
      platformId,
      'bios.bin',
      bytes.length,
      badChecksum ? '0' * 32 : (ProgressDigest.md5()..add(bytes)).finish(),
    ),
  ];

  @override
  Future<void> downloadFirmware(
    RommFirmware firmware,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    cancellation.check();
    await destination.writeAsBytes(bytes);
    onProgress(bytes.length);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final root in [true, false]) {
    test(
      'ARMSX2 prepares its BIOS before opening the APK installer (root: $root)',
      () async {
        const channel = MethodChannel('app.broomm/armsx2-preinstall-test');
        const tree =
            'content://com.android.externalstorage.documents/tree/primary%3ABroomm%2FARMSX2';
        final emulator = androidEmulators.singleWhere((e) => e.id == 'armsx2');
        final data = await Directory.systemTemp.createTemp(
          'broomm-preinstall-',
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final client = _Ps2Firmware();
        var installed = false,
            initialized = false,
            prepared = false,
            installer = 0,
            picks = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'installed':
              return [
                if (installed)
                  {
                    'package': androidArmsx2RootPackage,
                    'build': 'a' * 64,
                    'version': androidArmsx2RootVersion,
                  },
              ];
            case 'canInstallPackages':
              return true;
            case 'ioBusy':
              return false;
            case 'canPrepareSharedFolder':
              return root;
            case 'sharedPick':
              expect(root, isFalse);
              expect(installed, isFalse);
              picks++;
              return tree;
            case 'rootPrepareEmulatorInstall':
            case 'sharedReplace':
              expect(installed, isFalse);
              expect(call.method == 'rootPrepareEmulatorInstall', root);
              expect(call.arguments['package'], androidArmsx2RootPackage);
              expect(
                call.arguments['after'],
                await progressFileHash(
                  File(call.arguments['source'] as String),
                ),
              );
              prepared = true;
              return root ? true : null;
            case 'installApk':
              expect(prepared, isTrue);
              installer++;
              return null;
            case 'sharedCheck':
              expect(call.arguments['tree'], tree);
              if (root)
                expect(call.arguments['access'], androidPreparedFolderAccess);
              if (!initialized)
                throw PlatformException(code: 'first-open-required');
              return null;
            case 'sharedStat':
              expect(root, isFalse);
              return initialized ? {'bytes': 42} : null;
            case 'open':
              return null;
            default:
              throw StateError(call.method);
          }
        });
        final manager = AndroidEmulators(data, channel: channel, enabled: true);
        final setup = AndroidEmulatorSetup(
          manager,
          emulator,
          'ps2',
          'a' * 32,
          client: client,
          platformId: 1,
        );
        try {
          await manager.load();
          client.badChecksum = true;
          await setup.install(imported: true);
          expect(setup.step, AndroidSetupStep.install);
          expect(setup.problem, contains('checksum'));
          expect(installer, 0);
          client.badChecksum = false;
          await setup.install(imported: true);
          expect(installer, 1);
          expect(setup.step, AndroidSetupStep.waitingInstall);
          installed = true;
          final verified = Completer<void>();
          setup.addListener(() {
            if (!setup.busy &&
                setup.step != AndroidSetupStep.waitingInstall &&
                setup.step != AndroidSetupStep.install &&
                !verified.isCompleted)
              verified.complete();
          });
          await setup.refresh();
          await verified.future;
          if (root) {
            expect(setup.step, AndroidSetupStep.initialize);
            expect(setup.checkingPreparedFolder, isTrue);
            expect(manager.folder(emulator), isNull);
          } else {
            expect(setup.hasPendingFolder, isTrue);
            expect(setup.sharedBiosPrepared, isTrue);
          }
          await setup.open();
          initialized = true;
          await setup.resumed();
          expect(setup.step, AndroidSetupStep.ready, reason: setup.problem);
          expect(manager.folder(emulator)?['tree'], tree);
          await manager.load();
          expect(
            manager.folder(emulator)?['access'],
            root ? androidPreparedFolderAccess : null,
          );
          expect(picks, root ? 0 : 1);
        } finally {
          setup.dispose();
          manager.dispose();
          messenger.setMockMethodCallHandler(channel, null);
          await data.delete(recursive: true);
        }
      },
    );
  }
  for (final rooted in [true, false]) {
    test('ARMSX2 first-run BIOS via a shared grant (root available: $rooted)', () async {
      const channel = MethodChannel('app.broomm/armsx2-setup-test');
      const tree =
          'content://com.android.externalstorage.documents/tree/primary%3ABroom%2FARMSX2';
      final package = rooted ? androidArmsx2RootPackage : 'com.armsx2.nightly';
      final emulator = androidEmulators.singleWhere((e) => e.id == 'armsx2');
      final data = await Directory.systemTemp.createTemp('broomm-armsx2-');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final client = _Ps2Firmware();
      var initialized = false, picks = 0, writes = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'installed':
            return [
              {
                'package': package,
                'build': 'a' * 64,
                'version': androidArmsx2RootVersion,
              },
            ];
          case 'rootArmsx2BiosStatus':
            expect(rooted, isTrue);
            throw PlatformException(code: 'unverified-root-storage');
          case 'rootPreparedArmsx2ImportReady':
            return false;
          case 'ioBusy':
            return false;
          case 'canPrepareSharedFolder':
            return rooted;
          case 'rootPrepareSharedFolder':
            expect(rooted, isTrue);
            expect(call.arguments['package'], package);
            return true;
          case 'sharedPick':
            expect(call.arguments['prepared'], rooted ? true : null);
            picks++;
            return tree;
          case 'sharedStat':
            expect(call.arguments['tree'], tree);
            expect(call.arguments['path'], 'PCSX2-Android.ini');
            return initialized ? {'bytes': 42} : null;
          case 'sharedReplace':
            writes++;
            expect(call.arguments['tree'], tree);
            expect(call.arguments['path'], 'Broomm BIOS/broomm-ps2-bios.bin');
            expect(call.arguments['before'], isNull);
            expect(
              call.arguments['after'],
              await progressFileHash(File(call.arguments['source'] as String)),
            );
            return null;
          case 'sharedCheck':
            expect(initialized, isTrue);
            return null;
          default:
            throw StateError(call.method);
        }
      });
      final manager = AndroidEmulators(data, channel: channel, enabled: true);
      final setup = AndroidEmulatorSetup(
        manager,
        emulator,
        'ps2',
        'a' * 32,
        client: client,
        platformId: 1,
      );
      try {
        await manager.load();
        await setup.verify();
        if (rooted) {
          expect(setup.problem, contains('unverified-root-storage'));
          await setup.useSharedFolder();
        }
        expect(setup.preparedFolder, rooted);
        await setup.selectFolder();
        expect(setup.hasPendingFolder, isTrue);
        expect(manager.folder(emulator), isNull);
        client.badChecksum = true;
        await setup.prepareSharedBios();
        expect(setup.problem, contains('checksum'));
        expect(writes, 0);
        expect(setup.hasPendingFolder, isTrue);

        client.badChecksum = false;
        await setup.prepareSharedBios();
        expect(setup.problem, isNull);
        expect(setup.sharedBiosPrepared, isTrue);
        expect(writes, 1);
        expect(manager.folder(emulator), isNull);

        await setup.selectFolder();
        expect(setup.problem, contains('has not initialized this folder'));
        expect(setup.hasPendingFolder, isTrue);

        initialized = true;
        await setup.selectFolder();
        expect(picks, 1);
        expect(setup.step, AndroidSetupStep.ready);
        expect(manager.folder(emulator)?['tree'], tree);
      } finally {
        setup.dispose();
        manager.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        await data.delete(recursive: true);
      }
    });
  }
  for (final useFallback in [false, true]) {
    test(
      'Azahar ${useFallback ? 'requires explicit shared fallback after failed verification' : 'persists the verified scoped package and folder'}',
      () async {
        const channel = MethodChannel('app.broomm/azahar-setup-test');
        final tree = useFallback
            ? 'content://com.android.externalstorage.documents/tree/primary%3ADocuments%2FAzahar'
            : 'content://com.android.externalstorage.documents/tree/primary%3ABroomm%2FAzahar';
        final emulator = androidEmulators.singleWhere((e) => e.id == 'azahar');
        final data = await Directory.systemTemp.createTemp('broomm-azahar-');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final checks = <Map>[];
        var folderPreparations = 0;
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
            case 'canPrepareSharedFolder':
              return true;
            case 'rootPrepareSharedFolder':
              folderPreparations++;
              expect(call.arguments['package'], androidAzaharScopedPackage);
              expect(call.arguments['build'], 'a' * 64);
              return true;
            case 'sharedPick':
              expect(call.arguments['package'], androidAzaharScopedPackage);
              expect(call.arguments['prepared'], true);
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
          expect(setup.preparedFolder, isTrue);
          expect(
            androidSetupInstructions(emulator, prepared: true),
            contains('Internal storage → Broomm → Azahar'),
          );
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
          await setup.verify();
          expect(setup.step, AndroidSetupStep.ready);
          expect(manager.folder(emulator)?['tree'], tree);
          expect(folderPreparations, 1);
        } finally {
          setup.dispose();
          manager.dispose();
          messenger.setMockMethodCallHandler(channel, null);
          await data.delete(recursive: true);
        }
      },
    );
  }
  for (final repick in [false, true]) {
    test(repick ? 'Citra MMJ can replace a pending folder selection' : 'Citra MMJ retries a granted folder without reopening the picker', () async {
      const channel = MethodChannel('app.broomm/mmj-setup-test');
      const tree =
          'content://com.android.externalstorage.documents/tree/primary%3Acitra-emu';
      final emulator = androidEmulators.singleWhere((e) => e.id == 'citra-mmj');
      final data = await Directory.systemTemp.createTemp('broomm-mmj-');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var picks = 0;
      final checks = <Map>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'installed':
            return [
              {
                'package': androidMmjSharedPackage,
                'build': 'a' * 64,
                'version': androidMmjSharedVersion,
              },
            ];
          case 'canPrepareSharedFolder':
            return !repick;
          case 'rootPrepareSharedFolder':
            throw PlatformException(code: 'folder-unavailable');
          case 'sharedPick':
            expect(call.arguments['prepared'], isNull);
            picks++;
            return tree;
          case 'sharedCheck':
            checks.add(call.arguments as Map);
            if (checks.length == 1)
              throw PlatformException(code: 'emulator-running');
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
        expect(setup.preparedFolder, isFalse);
        expect(
          setup.folderProblem,
          repick ? isNull : contains('could not prepare'),
        );
        await setup.selectFolder();
        expect(setup.problem, contains('emulator-running'));
        expect(setup.hasPendingFolder, isTrue);
        expect(setup.step, AndroidSetupStep.folder);
        expect(manager.folder(emulator), isNull);

        await setup.selectFolder(change: repick);
        expect(picks, repick ? 2 : 1);
        expect(checks, hasLength(2));
        expect(checks.last, checks.first);
        expect(setup.hasPendingFolder, isFalse);
        expect(setup.step, AndroidSetupStep.ready);
        await manager.load();
        expect(manager.folder(emulator)?['tree'], tree);
        expect(manager.folder(emulator)?['access'], androidMmjRootFolderAccess);
      } finally {
        setup.dispose();
        manager.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        await data.delete(recursive: true);
      }
    });
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
            'installApk' || 'sharedCheck' || 'emulatorAppInfo' => null,
            'canPrepareSharedFolder' ||
            'rootPrepareSharedFolder' ||
            'rootPrepareEmulatorInstall' => true,
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
      expect(
        calls.indexOf('rootPrepareEmulatorInstall'),
        lessThan(calls.indexOf('installApk')),
      );
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
      expect(calls, isNot(contains('rootPrepareSharedFolder')));
      await setup.openAppInfo();
      expect(calls.last, 'emulatorAppInfo');
      await setup.useSharedFolder();
      expect(setup.problem, isNull);
      expect(setup.preparedFolder, isTrue);
      expect(
        androidSetupInstructions(emulator, prepared: true),
        contains('Internal storage → Broomm → PPSSPP'),
      );
      await setup.selectFolder();
      expect(setup.step, AndroidSetupStep.folder);
      expect(manager.folder(emulator), isNull);
      picked = 'content://com.android.externalstorage.documents/tree/primary%3ABroomm%2FPPSSPP';
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
