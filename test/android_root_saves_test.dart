import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/android/progress.dart';
import 'package:broomm/src/android/root_saves.dart';
import 'package:broomm/src/android/lynx_firmware.dart';
import 'package:broomm/src/android/opera.dart';
import 'package:broomm/src/android/saturn.dart';
import 'package:broomm/src/android/flycast.dart';
import 'package:broomm/src/android/save_plan.dart';
import 'package:broomm/src/android/session.dart';
import 'package:broomm/src/android/shared_saves.dart';
import 'package:broomm/src/android/setup.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/files.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/progress/zip.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';

import 'android_folder_sync_test.dart' show AndroidFolderFixture;
import 'android_apk_download_test.dart' show ApkClient, ApkReply;
import 'cloud_saves_test.dart' show SaveServer, profileId, serverId;

class _FixtureLynxBoot implements AndroidLynxBootImage {
  _FixtureLynxBoot(this.file, this.sha256);
  @override
  final File file;
  @override
  final String sha256;
}

class _FixtureOperaResource implements AndroidOperaResource {
  _FixtureOperaResource(this.name, this.file, this.sha256);
  @override
  final String name;
  @override
  final File file;
  @override
  final String sha256;
  @override
  int get bytes => androidOperaFirmware[name]!.$1;
}

class _FixtureSaturnResource implements AndroidSaturnResource {
  _FixtureSaturnResource(this.name, this.file, this.sha256);
  @override
  final String name;
  @override
  final File file;
  @override
  final String sha256;
  @override
  int get bytes => androidSaturnFirmware[name]!.$1;
}

class _FixtureFlycastResource implements AndroidFlycastResource {
  _FixtureFlycastResource(this.file, this.sha256);
  @override
  final File file;
  @override
  final String sha256;
  @override
  String get name => 'dc_boot.bin';
  @override
  int get bytes => 2097152;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.broomm/root-save-test');
  const pkg = 'com.retroarch.aarch64';
  const label = 'u:object_r:app_data_file:s0:c118,c256,c512,c768';
  const attributes = '10118 10118 600 $label';
  final emulator = androidEmulators.singleWhere((e) => e.id == 'retroarch');
  final platform = playablePlatforms.firstWhere((p) => p.slug == 'gba');
  late Directory temp, data, native;
  late AndroidEmulators manager;
  late AndroidFolderFixture fixture;
  late SaveServer api;
  late CloudSaves cloud;
  var denied = false;
  String? operaOptionsText;
  var missingCore = false;
  var refuseRomCleanup = false;
  var loseRomStagingReply = false;
  var loseConfigPublicationReply = false;
  var loseConfigCleanupReply = false;
  var loseFirmwarePublicationReply = false, loseFirmwareCleanupReply = false;
  var processState = 'idle', exitState = 'unknown';
  var reportsBeforeExit = 0;
  const process = {
    'pid': 1188,
    'startTicks': 25,
    'observedElapsed': 350,
    'observedWall': 123456,
  };
  final metadata = <String, String>{};
  final calls = <String>[];
  late Map<String, dynamic> observation;
  Future<AndroidSavePlan> plan([
    String profile = profileId,
    String content = '42',
  ]) async => await androidProgressLayout(
    manager,
    profile,
    emulator,
    platform,
    '/game/Minish Cap.gba',
    contentId: content,
  ) as AndroidSavePlan;
  Future<File> put(String relative, List<int> bytes) async {
    final file = File('${native.path}/$relative');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    metadata[relative] = attributes;
    return file;
  }

  Future<AndroidSavePlan> gameboyPlan(String slug, String rom) async =>
      await androidProgressLayout(
        manager,
        profileId,
        emulator,
        playablePlatforms.firstWhere((p) => p.slug == slug),
        rom,
        contentId: '42',
      ) as AndroidSavePlan;

  CloudGame game(AndroidSavePlan p) => CloudGame(
    server: serverId,
    profile: profileId,
    user: api.user,
    rom: 42,
    client: api,
    layout: p,
  );
  Future<void> launchRooted(
    AndroidGameSession session, {
    bool emulatorClosed = false,
  }) async {
    final rom = await File('${temp.path}/Minish Cap.gba').writeAsBytes([5, 6]);
    await session.start(
      server: serverId,
      profile: profileId,
      rom: 42,
      emulator: emulator,
      app: manager.app(emulator)!,
      files: [rom.path],
      selected: rom.path,
      core: 'mgba',
      rooted: true,
      emulatorClosed: emulatorClosed,
      prepare: (_, _) async => game(await plan()),
    );
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('broomm-root-');
    data = await Directory('${temp.path}/data').create();
    native = await Directory('${temp.path}/native').create();
    fixture = AndroidFolderFixture(temp)..trees['root-fixture'] = native;
    api = SaveServer();
    cloud = CloudSaves(data, notice: (_, _) {});
    denied = false;
    operaOptionsText = null;
    missingCore = false;
    refuseRomCleanup = false;
    loseRomStagingReply = false;
    loseConfigPublicationReply = false;
    loseConfigCleanupReply = false;
    loseFirmwarePublicationReply = false;
    loseFirmwareCleanupReply = false;
    processState = 'idle';
    exitState = 'unknown';
    reportsBeforeExit = 0;
    metadata.clear();
    calls.clear();
    observation = {
      'package': pkg,
      'build': 'a' * 64,
      'signer': 'b' * 64,
      'user': '0',
      'uid': '10118',
      'dataDir': '/data/user/0/$pkg',
      'label': label,
      'core': 'c' * 64,
      'abi': 'arm64-v8a',
      'config': Uint8List.fromList(
        utf8.encode(
          'savefile_directory = "/storage/emulated/0/RetroArch/saves"\nsort_savefiles_enable = "true"\nauto_overrides_enable = "true"\ninput_joypad_driver = "android"\n',
        ),
      ),
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'launch') processState = 'running';
          if (!call.method.startsWith('root')) return fixture.call(call);
          if (denied)
            throw PlatformException(
              code: 'android-root-save',
              message: 'Denied',
            );
          if (call.method == 'rootInspect') return observation;
          if (call.method == 'rootOptions')
            return operaOptionsText == null
                ? null
                : Uint8List.fromList(utf8.encode(operaOptionsText!));
          if (call.method == 'rootControllerProfiles') {
            observation['controllerProfilesReady'] = true;
            return null;
          }
          if ({'rootMgbaSetup', 'rootCoreSetup'}.contains(call.method))
            return {
              ...observation,
              'abi': 'arm64-v8a',
              if (missingCore) 'core': null,
            };
          if (call.method == 'rootLifecycle') {
            final args = call.arguments as Map;
            if (args['process'] != null) {
              expect(args['process'], process);
              if (reportsBeforeExit > 0) {
                reportsBeforeExit--;
                return {'state': 'running'};
              }
              return {
                'state': processState == 'running' ? 'running' : exitState,
              };
            }
            return {
              'state': processState,
              if (processState == 'idle') 'elapsed': 100,
              if (processState == 'running' && args['launchedAfter'] == 100)
                ...process,
            };
          }
          final args = Map<String, dynamic>.from(call.arguments as Map)
            ..['tree'] = 'root-fixture';
          if (call.method == 'rootFlycastList') {
            final config = args['configPath'] as String;
            final base = config.substring(0, config.lastIndexOf('/'));
            final nonce = config.split('/').last.substring(7, 39);
            final paths = [
              '$base/options-$nonce.opt',
              '$base/system-$nonce/dc/dc_boot.bin',
              '$base/system-$nonce/dc/dc_nvmem.bin',
              for (final port in ['A', 'B', 'C', 'D'])
                for (final slot in [1, 2])
                  '$base/system-$nonce/dc/vmu_save_$port$slot.bin',
            ];
            final result = <String, dynamic>{};
            for (final path in paths) {
              final file = File('${native.path}/$path');
              if (await file.exists())
                result[path] = {
                  'bytes': await file.length(),
                  'sha256': await progressFileHash(file),
                  'metadata': metadata[path] ?? attributes,
                };
            }
            return result;
          }
          if (call.method == 'rootFlycastRead')
            return fixture.call(MethodCall('sharedRead', args));
          if (call.method == 'rootStageRom') {
            final source = File(args['source'] as String);
            if (await progressFileHash(source) != args['sha256'])
              throw PlatformException(code: 'changed-native-rom-source');
            expect(
              source.uri.pathSegments.last,
              File(args['path'] as String).uri.pathSegments.last,
            );
            if (args['preparedCartridge'] == true) {
              final transaction = (args['path'] as String)
                  .split('/')[4]
                  .substring(4);
              expect(
                source.parent.parent.path,
                endsWith('/shared-session/$transaction'),
              );
            }
            final target = await put(
              args['path'] as String,
              await source.readAsBytes(),
            );
            if (loseRomStagingReply) {
              loseRomStagingReply = false;
              throw PlatformException(code: 'lost-rom-staging-reply');
            }
            return target.path;
          }
          if (call.method == 'rootRemoveRom') {
            final target = File('${native.path}/${args['path']}');
            if (await target.exists()) {
              if (args['sha256'] != await progressFileHash(target) ||
                  refuseRomCleanup)
                throw PlatformException(
                  code: 'android-root-save',
                  message: 'Staged ROM could not be removed',
                );
              await target.delete();
            }
            return null;
          }
          if ({
            'rootLynxFirmware',
            'rootOperaFirmware',
            'rootSaturnFirmware',
            'rootFlycastReplace',
          }.contains(call.method)) {
            final value = await fixture.call(MethodCall('sharedReplace', args));
            if (args['after'] == null) {
              metadata.remove(args['path']);
              if (loseFirmwareCleanupReply) {
                loseFirmwareCleanupReply = false;
                throw PlatformException(code: 'lost-firmware-cleanup-reply');
              }
            } else {
              metadata[args['path']] = attributes;
              if (loseFirmwarePublicationReply) {
                loseFirmwarePublicationReply = false;
                throw PlatformException(
                  code: 'lost-firmware-publication-reply',
                );
              }
            }
            return value;
          }
          if (call.method == 'rootList') {
            for (final area in (args['areas'] as List).cast<Map>()) {
              final driver = area.remove('driver');
              final opera = area.remove('operaStem');
              final saturn = area.remove('saturnStem');
              final flycast = area.remove('flycastVmus');
              if (flycast != null) {
                expect(args['coreName'], 'flycast');
                area['pattern'] = r'^[^/]+\.[A-D][12]\.bin$';
              }
              if (saturn != null) {
                expect(args['coreName'], 'mednafen_saturn');
                area['pattern'] =
                    '^(?:${RegExp.escape(saturn as String)}|mednafen_saturn_libretro_shared)\\.(?:srm|bkr|smpc|bcr|4mb\\.bcr)\$';
              }
              if (opera != null) {
                expect(args['coreName'], 'opera');
                area['pattern'] =
                    '^(?:opera/per_game/${RegExp.escape(opera as String)}\\.[0-9]\\.srm|opera/shared/nvram\\.[0-9]\\.srm|${RegExp.escape(opera)}\\.srm|3DO\\.nvram)\$';
              }
              if (driver != null) {
                expect(args['coreName'], 'fbneo');
                area['pattern'] =
                    '^fbneo/(?:${RegExp.escape(driver as String)}\\.(?:fs|nv|hi|memcard)|shared\\.memcard)\$';
              }
            }
          }
          final value = await fixture.call(
            MethodCall(call.method.replaceFirst('root', 'shared'), args),
          );
          if (call.method == 'rootReplace') {
            if (args['after'] == null) {
              metadata.remove(args['path']);
            } else {
              metadata[args['path']] =
                  args['metadata'] ?? metadata[args['path']] ?? attributes;
            }
            if ((args['path'] as String).endsWith('.cfg')) {
              if (args['after'] != null && loseConfigPublicationReply) {
                loseConfigPublicationReply = false;
                throw PlatformException(code: 'lost-config-publication-reply');
              }
              if (args['after'] == null && loseConfigCleanupReply) {
                loseConfigCleanupReply = false;
                throw PlatformException(code: 'lost-config-cleanup-reply');
              }
            }
          }
          if (call.method == 'rootList')
            return {
              for (final e in (value as Map).entries)
                e.key: {
                  ...e.value as Map,
                  'metadata': metadata[e.key] ?? attributes,
                },
            };
          return value;
        });
    manager = AndroidEmulators(data, channel: channel, enabled: true);
    await manager.load();
  });

  test('cold rooted launch prepares APK controller profiles before publishing its configuration', () async {
    observation['bundledControllerProfiles'] = true;
    observation['config'] = Uint8List(0);
    await manager.connectGbaRoot(emulator);
    final session = AndroidGameSession(manager, cloud);
    addTearDown(session.dispose);
    final cold = await plan();
    expect(
      androidIni(cold.launch['configText']!)['joypad_autoconfig_dir'],
      '/data/user/0/$pkg/files/Broomm/controller-profiles-${'a' * 64}',
    );
    await launchRooted(session);
    expect(calls.indexOf('rootControllerProfiles'), greaterThanOrEqualTo(0));
    expect(
      calls.indexOf('rootControllerProfiles'),
      lessThan(calls.indexOf('rootReplace')),
    );
    expect((await plan()).launch, isNot(contains('prepareControllerProfiles')));
  });

  test('rooted launch retains a custom controller profile directory', () async {
    observation['bundledControllerProfiles'] = true;
    observation['config'] = Uint8List.fromList(
      utf8.encode(
        'joypad_autoconfig_dir = "/storage/emulated/0/RetroArch/custom"\n',
      ),
    );
    await manager.connectGbaRoot(emulator);
    final p = await plan();
    expect(
      androidIni(p.launch['configText']!)['joypad_autoconfig_dir'],
      '/storage/emulated/0/RetroArch/custom',
    );
    expect(p.launch, isNot(contains('prepareControllerProfiles')));
  });

  test(
    'missing stock assets block direct play before any save journal',
    () async {
      await manager.connectGbaRoot(emulator);
      observation['frontendAssetsPending'] = true;
      observation['config'] = Uint8List(0);
      expect((await manager.connectGbaRoot(emulator))?.package, pkg);
      final session = AndroidGameSession(manager, cloud);
      addTearDown(session.dispose);
      calls.clear();
      await expectLater(
        launchRooted(session),
        throwsA(isA<AndroidRetroArchSetupRequired>()),
      );
      expect(await session.pending(), isNull);
      expect(session.active, isFalse);
      expect(calls, isNot(contains('rootReplace')));
      expect(calls, isNot(contains('launch')));

      observation['frontendAssetsPending'] = false;
      await launchRooted(session);
      expect(calls, contains('launch'));
    },
  );

  test('one setup operation prepares GBA and waits for the first open before connecting', () async {
    observation['frontendAssetsPending'] = true;
    final setup = AndroidEmulatorSetup(manager, emulator, 'gba', profileId);
    addTearDown(setup.dispose);
    await setup.verify();
    expect(setup.problem, isNull);
    expect(setup.step, AndroidSetupStep.initialize);
    expect(manager.gbaRoot(emulator), isNull);
    observation['frontendAssetsPending'] = false;
    await setup.verify();
    expect(setup.step, AndroidSetupStep.ready);
    expect(manager.hasCurrentGbaRoot(emulator), isTrue);
    expect(calls, isNot(contains('installDownloadedApk')));
  });

  test(
    'denied root setup remains retryable without publishing a connection',
    () async {
      denied = true;
      final setup = AndroidEmulatorSetup(manager, emulator, 'gba', profileId);
      addTearDown(setup.dispose);
      await setup.verify();
      expect(setup.problem, contains('Denied'));
      expect(setup.step, AndroidSetupStep.initialize);
      expect(manager.gbaRoot(emulator), isNull);
      denied = false;
      await setup.verify();
      expect(setup.problem, isNull);
      expect(setup.step, AndroidSetupStep.ready);
    },
  );

  test('rooted launch retains a configured custom assets directory', () async {
    observation['frontendAssetsPending'] = true;
    const custom = '/storage/emulated/0/RetroArch/custom-assets/';
    observation['config'] = Uint8List.fromList(
      utf8.encode('assets_directory = "$custom"\n'),
    );
    expect(await manager.connectGbaRoot(emulator), isNull);
    final p = await plan();
    expect(p.launch, isNot(contains('frontendSetup')));
    expect(androidIni(p.launch['configText']!)['assets_directory'], custom);
  });

  test(
    'root setup reuses mGBA and reconnects a newly installed RetroArch build',
    () async {
      await manager.connectGbaRoot(emulator);
      expect(calls, isNot(contains('rootInstallMgba')));
      const replacement = AndroidApp(
        pkg,
        '1.22.2',
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      manager.installed[pkg] = replacement;
      expect(manager.hasCurrentGbaRoot(emulator), isFalse);
      observation['build'] = replacement.build;
      observation['config'] = Uint8List(0);
      await manager.connectGbaRoot(emulator);
      expect(manager.hasCurrentGbaRoot(emulator), isTrue);
      expect(
        (await plan()).launch['configText'],
        contains('savefile_directory'),
      );
      expect(calls, isNot(contains('rootInstallMgba')));
    },
  );

  test(
    'a changed mGBA archive never reaches root publication or connects saves',
    () async {
      missingCore = true;
      final client = ApkClient((_) => ApkReply([1, 2, 3]));
      await HttpOverrides.runZoned(
        () => expectLater(
          manager.connectGbaRoot(emulator),
          throwsFormatException,
        ),
        createHttpClient: (_) => client,
      );
      expect(
        client.requests.single.path,
        endsWith('/arm64-v8a/mgba_libretro_android.so.zip'),
      );
      expect(client.closed, isTrue);
      expect(calls, isNot(contains('rootInstallMgba')));
      expect(manager.gbaRoot(emulator), isNull);
      expect(
        await Directory('${data.path}/android/mgba-stage').list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'rooted launch blocks a running writer and asks only on unknown closure',
    () async {
      await manager.connectGbaRoot(emulator);
      final session = AndroidGameSession(manager, cloud);
      addTearDown(session.dispose);
      processState = 'running';
      await expectLater(
        launchRooted(session, emulatorClosed: true),
        throwsStateError,
      );
      expect(await session.pending(), isNull);
      expect(calls, isNot(contains('rootReplace')));
      expect(calls, isNot(contains('launch')));
      processState = 'unknown';
      await expectLater(
        launchRooted(session),
        throwsA(isA<AndroidClosureUnverified>()),
      );
      expect(await session.pending(), isNull);
      await launchRooted(session, emulatorClosed: true);
      expect(await session.pending(), isNotNull);
      expect(calls, contains('launch'));
    },
  );

  for (final dispose in [false, true]) {
    test(
      'root preparation ${dispose ? 'disposal' : 'cancellation'} waits for its writer before releasing the lease',
      () async {
        await manager.connectGbaRoot(emulator);
        final p = await plan();
        final rom = await File('${temp.path}/Minish Cap.gba')
            .writeAsBytes([5, 6]);
        final session = AndroidGameSession(manager, cloud);
        if (!dispose) addTearDown(session.dispose);
        final ready = Completer<void>(),
            cancelled = Completer<void>(),
            stopped = Completer<void>();
        final result = expectLater(
          session.start(
            server: serverId,
            profile: profileId,
            rom: 42,
            emulator: emulator,
            app: manager.app(emulator)!,
            files: [rom.path],
            selected: rom.path,
            core: 'mgba',
            rooted: true,
            prepare: (cancellation, phase) async {
              ready.complete();
              await cancellation.whenCancelled;
              cancelled.complete();
              await stopped.future;
              return game(p);
            },
          ),
          throwsA(isA<DownloadCancelled>()),
        );
        await ready.future;
        expect(session.canCancelPreparation, true);
        await expectLater(SessionLease.acquire(data), throwsStateError);
        if (dispose)
          session.dispose();
        else
          session.cancelPreparation();
        await cancelled.future;
        await expectLater(SessionLease.acquire(data), throwsStateError);
        expect(await session.pending(), isNull);
        expect(api.records, isEmpty);
        expect(calls, isNot(contains('rootReplace')));
        stopped.complete();
        await result;
        expect(session.active, false);
        final lease = await SessionLease.acquire(data);
        await lease.release();
      },
    );
  }

  test('a live rooted session waits, then a verified normal exit syncs automatically', () async {
    await manager.connectGbaRoot(emulator);
    final p = await plan(), remote = p.remotePath('save/game.srm');
    final standalone = await put(remote, [7]);
    final session = AndroidGameSession(manager, cloud);
    addTearDown(session.dispose);
    await launchRooted(session);
    await put(remote, [2, 3]);
    expect(
      await session.finishIfRetroArchClosed(),
      AndroidRetroArchState.running,
    );
    await expectLater(session.finish(emulatorClosed: true), throwsStateError);
    expect(await standalone.readAsBytes(), [2, 3]);
    expect(api.records, isEmpty);
    expect(await session.pending(), isNotNull);
    processState = 'idle';
    exitState = 'closed';
    reportsBeforeExit = 1;
    expect(
      await session.finishIfRetroArchClosed(),
      AndroidRetroArchState.closed,
    );
    expect(await standalone.readAsBytes(), [7]);
    expect(api.contents[api.records.values.single.id], [2, 3]);
    expect(await session.pending(), isNull);
  });

  test(
    'missing exit evidence and a crash retain the rooted save for review',
    () async {
      await manager.connectGbaRoot(emulator);
      final p = await plan(), remote = p.remotePath('save/game.srm');
      final session = AndroidGameSession(manager, cloud);
      addTearDown(session.dispose);
      await launchRooted(session);
      final changed = await put(remote, [3, 4]);
      processState = 'idle';
      expect(
        await session.finishIfRetroArchClosed(),
        AndroidRetroArchState.unknown,
      );
      exitState = 'interrupted';
      expect(
        await session.finishIfRetroArchClosed(),
        AndroidRetroArchState.interrupted,
      );
      expect(await session.pending(), isNotNull);
      expect(await changed.readAsBytes(), [3, 4]);
      expect(api.records, isEmpty);
      await session.finish(emulatorClosed: true);
      expect(await (await p.target('save/game.srm')).readAsBytes(), [3, 4]);
      expect((await cloud.store(game(p)).state())['unclean'], isTrue);
      expect(api.records, isEmpty);
    },
  );
  tearDown(() async {
    manager.dispose();
    api.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temp.delete(recursive: true);
  });

  test(
    'explicit GBA connection isolates managed saves and compatible states',
    () async {
      expect(calls, isNot(contains('rootInspect')));
      await manager.connectGbaRoot(emulator);
      await manager.load();
      expect(manager.connected(profileId, emulator, platform: 'gba'), isTrue);
      expect(manager.connected(profileId, emulator, platform: 'snes'), isFalse);
      final p = await plan(), second = await plan('d' * 32);
      expect(p.areas.first.id, 'save');
      expect(p.areas.last.id, startsWith('states-'));
      expect(
        p.localKey('files/Broomm/$profileId/42/saves/Minish Cap.srm'),
        'save/game.srm',
      );
      expect(
        p.localKey('files/Broomm/$profileId/42/saves/Minish Cap 2.srm'),
        isNull,
      );
      expect(
        p.remoteAreas.first.remote,
        isNot(second.remoteAreas.first.remote),
      );
      final cfg = androidIni(p.launch['configText']!);
      expect(
        cfg['savefile_directory'],
        '/data/user/0/$pkg/files/Broomm/$profileId/42/saves',
      );
      expect(cfg['auto_overrides_enable'], 'false');
      expect(cfg['input_joypad_driver'], 'android');
      expect(calls.where((c) => c == 'rootReplace'), isEmpty);
      denied = true;
      await expectLater(
        manager.connectGbaRoot(emulator),
        throwsA(isA<PlatformException>()),
      );
      expect(manager.gbaRoot(emulator)!['build'], 'a' * 64);
      denied = false;
      observation['uid'] = '10119';
      await expectLater(plan(), throwsStateError);
    },
  );

  test('GBA root and shared RetroArch saves coexist across reloads', () async {
    final tree = 'content://$pkg.documents/tree/%2Fdata%2Fuser%2F0%2F$pkg';
    fixture.trees[tree] = native;
    await put(
      'files/retroarch.cfg',
      utf8.encode('input_joypad_driver = "android"\n'),
    );
    await put('cores/snes9x_libretro_android.so', [1]);
    await put('cores/mgba_libretro_android.so', [2]);
    await manager.confirmSharedStorage(emulator, tree);
    await manager.connectGbaRoot(emulator);
    await manager.load();
    expect((await plan()).rooted, isTrue);
    final snes = await androidProgressLayout(
      manager,
      profileId,
      emulator,
      playablePlatforms.firstWhere((p) => p.slug == 'snes'),
      '/game/SNES game.sfc',
      contentId: '43',
    ) as AndroidSavePlan;
    expect(snes.rooted, isFalse);
    expect(snes.binding['tree'], tree);
    expect(manager.connected(profileId, emulator, platform: 'snes'), isTrue);
    await manager.disconnectGbaRoot(emulator);
    await manager.load();
    expect((await plan()).binding['tree'], tree);
  });

  test('version 3 root connections survive adding a shared folder', () async {
    await manager.connectGbaRoot(emulator);
    final settings = File('${data.path}/android/emulators.json');
    await settings.writeAsString(
      jsonEncode({
        'version': 3,
        'trees': {},
        'folders': {'retroarch:$pkg': manager.gbaRoot(emulator)},
      }),
    );
    await manager.load();
    expect((await plan()).rooted, isTrue);
    expect(manager.folder(emulator), isNull);
    final tree = 'content://$pkg.documents/tree/%2Fdata%2Fuser%2F0%2F$pkg';
    fixture.trees[tree] = native;
    await manager.confirmSharedStorage(emulator, tree);
    await manager.load();
    expect((await plan()).rooted, isTrue);
    expect(manager.folder(emulator)?['tree'], tree);
  });

  test('root journal captures profile progress and restores originals with native metadata', () async {
    await manager.connectGbaRoot(emulator);
    final p = await plan(),
        g = game(await plan()),
        saves = SharedAndroidSaves(manager);
    final path = p.remotePath('save/game.srm');
    final original = await put(path, [7, 7]);
    final unrelated = await put('standalone/Minish Cap.srm', [9, 9]);
    final unrelatedConfig = await put(
      p.launch['configPath']!.replaceFirst(
        RegExp(r'config-[a-f0-9]{32}'),
        'config-${'9' * 32}',
      ),
      [8, 9],
    );
    final working = await p.target('save/game.srm');
    await working.parent.create(recursive: true);
    await working.writeAsBytes([1, 1]);
    final rom = await File('${temp.path}/Minish Cap.gba').writeAsBytes([5, 6]);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final staged = File(await saves.stageRootRom(g, p));
    expect(await staged.readAsBytes(), [5, 6]);
    expect(await original.readAsBytes(), [1, 1]);
    await put(path, [2, 2, 2]);
    expect(await saves.capture(g, cloud, p), isTrue);
    expect(await working.readAsBytes(), [2, 2, 2]);
    refuseRomCleanup = true;
    await expectLater(
      saves.restoreOriginal(g, p),
      throwsA(isA<PlatformException>()),
    );
    expect(await original.readAsBytes(), [7, 7]);
    expect(await staged.exists(), isTrue);
    expect(await saves.pending, isTrue);
    refuseRomCleanup = false;
    await saves.restoreOriginal(g, p);
    expect(await staged.exists(), isFalse);
    expect(await rom.readAsBytes(), [5, 6]);
    expect(await original.readAsBytes(), [7, 7]);
    expect(metadata[path], attributes);
    expect(await unrelated.readAsBytes(), [9, 9]);
    expect(
      await File('${native.path}/${p.launch['configPath']}').exists(),
      false,
    );
    expect(await unrelatedConfig.readAsBytes(), [8, 9]);
    expect(await saves.pending, isFalse);
  });

  test('changed session configuration retains recovery; lost cleanup replies retry safely', () async {
    await manager.connectGbaRoot(emulator);
    final p = await plan(), g = game(p), saves = SharedAndroidSaves(manager);
    final original = await put(p.remotePath('save/game.srm'), [7]);
    await saves.begin(g, p, 'a' * 64, selected: '/game/Minish Cap.gba');
    final config = File('${native.path}/${p.launch['configPath']}');
    final prepared = await config.readAsBytes();
    await config.writeAsString('user-edited configuration');
    await put(p.remotePath('save/game.srm'), [2, 3]);
    await saves.capture(g, cloud, p);
    await expectLater(
      saves.restoreOriginal(g, p),
      throwsA(isA<PlatformException>()),
    );
    expect(await saves.pending, true);
    expect(await original.readAsBytes(), [7]);
    expect(await config.readAsString(), 'user-edited configuration');
    expect(await (await p.target('save/game.srm')).readAsBytes(), [2, 3]);
    // Explicit resolution in the fixture restores the known prepared copy.
    await config.writeAsBytes(prepared);
    loseConfigCleanupReply = true;
    await expectLater(
      saves.restoreOriginal(g, p),
      throwsA(isA<PlatformException>()),
    );
    expect(await config.exists(), false);
    expect(await saves.pending, true);
    await saves.restoreOriginal(g, p);
    expect(await saves.pending, false);
    expect(await original.readAsBytes(), [7]);
  });

  test('a nested ZIP cartridge keeps its archive save identity and cleanup can retry', () async {
    await manager.connectGbaRoot(emulator);
    final contents = await Directory('${temp.path}/packed').create();
    await Directory('${contents.path}/regional').create();
    await File('${contents.path}/regional/Different Name.gba')
        .writeAsBytes([5, 6]);
    await File('${contents.path}/readme.txt').writeAsString('Game notes');
    final rom = File('${temp.path}/Minish Cap.zip');
    await ProgressZip.write(rom, contents, [
      'regional/Different Name.gba',
      'readme.txt',
    ]);
    final archiveHash = await progressFileHash(rom);
    final p = await gameboyPlan('gba', rom.path), g = game(p);
    final saves = SharedAndroidSaves(manager);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    loseRomStagingReply = true;
    await expectLater(
      saves.stageRootRom(g, p),
      throwsA(isA<PlatformException>()),
    );
    final stagedRecord = await saves.record(g, p);
    final staged = File('${native.path}/${stagedRecord['romStage']}');
    expect(staged.uri.pathSegments.last, 'Minish Cap.gba');
    expect(await staged.readAsBytes(), [5, 6]);
    expect(p.remotePath('save/game.srm'), endsWith('/Minish Cap.srm'));
    final r = await saves.record(g, p);
    expect(
      await saves
          .directory(r)
          .list()
          .any((e) => e.path.contains('/cartridge-')),
      false,
    );
    await put(p.remotePath('save/game.srm'), [3, 4]);
    await saves.capture(g, cloud, p);
    refuseRomCleanup = true;
    await expectLater(
      saves.restoreOriginal(g, p),
      throwsA(isA<PlatformException>()),
    );
    expect(await saves.pending, true);
    refuseRomCleanup = false;
    await saves.restoreOriginal(g, p);
    expect(await staged.exists(), false);
    expect(await progressFileHash(rom), archiveHash);
    expect(await (await p.target('save/game.srm')).readAsBytes(), [3, 4]);
  });

  test(
    'ambiguous or unsafe cartridge archives never reach native ROM staging',
    () async {
      await manager.connectGbaRoot(emulator);
      final contents = await Directory('${temp.path}/packed').create();
      await Directory('${contents.path}/ok').create();
      for (final name in ['ok/game.gba', 'another.gba'])
        await File('${contents.path}/$name').writeAsBytes([1, 2]);
      final rom = File('${temp.path}/Minish Cap.zip');
      await ProgressZip.write(rom, contents, ['ok/game.gba', 'another.gba']);
      final p = await gameboyPlan('gba', rom.path), g = game(p);
      final saves = SharedAndroidSaves(manager);
      await saves.begin(g, p, 'a' * 64, selected: rom.path);
      await expectLater(saves.stageRootRom(g, p), throwsStateError);
      await rom.delete();
      await ProgressZip.write(rom, contents, ['ok/game.gba']);
      final bytes = await rom.readAsBytes();
      final needle = utf8.encode('ok/game.gba');
      for (var i = 0; i <= bytes.length - needle.length; i++) {
        if (List.generate(needle.length, (n) => bytes[i + n]).join(',') ==
            needle.join(',')) {
          bytes[i] = 46;
          bytes[i + 1] = 46;
        }
      }
      await rom.writeAsBytes(bytes);
      await expectLater(saves.stageRootRom(g, p), throwsFormatException);
      expect(calls, isNot(contains('rootStageRom')));
      expect(await saves.pending, true);
    },
  );

  test('oversized and corrupt ZIP payloads keep recovery and remove partial extraction', () async {
    await manager.connectGbaRoot(emulator);
    final contents = await Directory('${temp.path}/packed').create();
    final cartridge = await File('${contents.path}/game.gba').create();
    final handle = await cartridge.open(mode: FileMode.writeOnly);
    await handle.truncate(32 * 1024 * 1024 + 1);
    await handle.close();
    final rom = File('${temp.path}/Minish Cap.zip');
    await ProgressZip.write(rom, contents, ['game.gba']);
    final p = await gameboyPlan('gba', rom.path), g = game(p);
    final saves = SharedAndroidSaves(manager);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    await expectLater(saves.stageRootRom(g, p), throwsFormatException);
    await rom.delete();
    await cartridge.writeAsBytes(List.generate(1024, (i) => i % 251));
    await ProgressZip.write(rom, contents, ['game.gba']);
    final zip = await ProgressZip.read(rom), bytes = await rom.readAsBytes();
    bytes[zip.entries.single.offset + 8] ^= 0xff;
    await rom.writeAsBytes(bytes);
    await expectLater(saves.stageRootRom(g, p), throwsA(isA<Exception>()));
    expect(calls, isNot(contains('rootStageRom')));
    final r = await saves.record(g, p);
    expect(
      await saves
          .directory(r)
          .list()
          .any((e) => e.path.contains('/cartridge-')),
      false,
    );
    expect(await saves.pending, true);
  });

  test('interrupted configuration publication keeps its ownership receipt before cleanup', () async {
    await manager.connectGbaRoot(emulator);
    final p = await plan(), g = game(p), saves = SharedAndroidSaves(manager);
    final original = await put(p.remotePath('save/game.srm'), [7]);
    await (await p.target('save/game.srm')).writeAsBytes([1]);
    loseConfigPublicationReply = true;
    await expectLater(
      saves.begin(g, p, 'a' * 64, selected: '/game/Minish Cap.gba'),
      throwsA(isA<PlatformException>()),
    );
    final config = File('${native.path}/${p.launch['configPath']}');
    expect(await config.exists(), true);
    expect(await saves.capture(g, cloud, p), false);
    final recovery = await saves.recoveryPlan(g, await plan());
    await saves.restoreOriginal(g, recovery);
    expect(await config.exists(), false);
    expect(await original.readAsBytes(), [7]);
    expect(await saves.pending, false);
    expect(api.records, isEmpty);
  });

  test('interrupted publication and revoked root retain recovery and refuse identity changes', () async {
    await manager.connectGbaRoot(emulator);
    final p = await plan(), g = game(p), saves = SharedAndroidSaves(manager);
    final original = await put(p.remotePath('save/game.srm'), [7]);
    final working = await p.target('save/game.srm');
    await working.parent.create(recursive: true);
    await working.writeAsBytes([1]);
    fixture.failAt = 1;
    await expectLater(
      saves.begin(g, p, 'a' * 64, selected: '/game/Minish Cap.gba'),
      throwsA(anything),
    );
    expect(await saves.pending, isTrue);
    denied = true;
    await expectLater(
      saves.capture(g, cloud, p),
      throwsA(isA<PlatformException>()),
    );
    expect(await saves.pending, isTrue);
    denied = false;
    await expectLater(manager.connectGbaRoot(emulator), throwsStateError);
    await expectLater(manager.disconnectGbaRoot(emulator), throwsStateError);
    final changed = AndroidSavePlan(p, emulator, {
      ...p.binding,
      'uid': '10119',
    }, p.remoteAreas);
    await expectLater(saves.record(g, changed), throwsFormatException);
    fixture.failAt = null;
    await saves.capture(g, cloud, p);
    await saves.restoreOriginal(g, p);
    expect(await original.readAsBytes(), [7]);
    expect(await working.readAsBytes(), [1]);
  });
  test(
    'a missing installed root save is damaged recovery, not an empty upload',
    () async {
      await manager.connectGbaRoot(emulator);
      final p = await plan(), g = game(p), saves = SharedAndroidSaves(manager);
      final working = await p.target('save/game.srm');
      await working.parent.create(recursive: true);
      await working.writeAsBytes([1, 2, 3]);
      await saves.begin(g, p, 'a' * 64, selected: '/game/Minish Cap.gba');
      await File('${native.path}/${p.remotePath('save/game.srm')}').delete();
      await expectLater(saves.capture(g, cloud, p), throwsStateError);
      expect(await saves.pending, isTrue);
      expect(await working.readAsBytes(), [1, 2, 3]);
      expect(api.records, isEmpty);
    },
  );
  test(
    'same-named games and other profiles retain separate local working saves',
    () async {
      await manager.connectGbaRoot(emulator);
      final a = await plan(),
          b = await plan(profileId, '43'),
          c = await plan('d' * 32);
      final files = [
        await a.target('save/game.srm'),
        await b.target('save/game.srm'),
        await c.target('save/game.srm'),
      ];
      for (var i = 0; i < files.length; i++) {
        await files[i].parent.create(recursive: true);
        await files[i].writeAsBytes([i + 1]);
      }
      for (var i = 0; i < files.length; i++) {
        expect(await files[i].readAsBytes(), [i + 1]);
      }
      expect({
        a.remotePath('save/game.srm'),
        b.remotePath('save/game.srm'),
        c.remotePath('save/game.srm'),
      }, hasLength(3));
    },
  );
  test('rooted states round trip with thumbnails, preserve standalone bytes and isolate core builds', () async {
    await manager.connectGbaRoot(emulator);
    final p = await plan(), g = game(p), saves = SharedAndroidSaves(manager);
    final group = p.areas.last.id;
    final key = '$group/game.state2';
    final path = p.remotePath(key);
    final original = await put(path, [9, 8]);
    final standalone = await put('standalone/Minish Cap.state2', [8]);
    final otherGame = await put(path.replaceFirst('/42/', '/43/'), [7]);
    final working = await p.target(key);
    final bytes = List<int>.generate(1024 * 1024 + 37, (i) => i % 251);
    await working.writeAsBytes(bytes);
    await (await p.target('$group/game.state2.png')).writeAsBytes([1, 2]);
    await saves.begin(g, p, 'a' * 64, selected: '/game/Minish Cap.gba');
    expect(await original.readAsBytes(), bytes);
    await put(path, [4, 5, 6]);
    expect(await saves.capture(g, cloud, p), true);
    expect(await working.readAsBytes(), [4, 5, 6]);
    expect(await (await p.target('$group/game.state2.png')).readAsBytes(), [
      1,
      2,
    ]);
    await saves.restoreOriginal(g, p);
    expect(await original.readAsBytes(), [9, 8]);
    expect(await standalone.readAsBytes(), [8]);
    expect(await otherGame.readAsBytes(), [7]);
    observation['core'] = 'e' * 64;
    final updated = await plan();
    expect(updated.areas.last.id, isNot(group));
    expect(
      updated.remotePath('${updated.areas.last.id}/game.state2'),
      isNot(path),
    );
    expect(await working.readAsBytes(), [4, 5, 6]);
    expect(
      p.localKey(
        path.replaceFirst('Minish Cap.state2', 'Minish Cap Extra.state2'),
      ),
      isNull,
    );
  });

  test('core changes during recovery retain original state provenance and restore its physical group', () async {
    await manager.connectGbaRoot(emulator);
    final p = await plan(), g = game(p), saves = SharedAndroidSaves(manager);
    final oldGroup = p.areas.last.id;
    final path = p.remotePath('$oldGroup/game.state');
    final original = await put(path, [8]);
    await saves.begin(g, p, 'a' * 64, selected: '/game/Minish Cap.gba');
    await put(path, [3, 4]);
    observation['core'] = 'f' * 64;
    final current = await plan(), currentGame = game(current);
    final recovery = await saves.recoveryPlan(currentGame, current);
    expect(recovery.launch['configPath'], p.launch['configPath']);
    expect(recovery.areas.last.id, oldGroup);
    await saves.capture(currentGame, cloud, recovery);
    expect(await current.files(), isEmpty);
    final journal = await saves.record(currentGame, recovery);
    final captured = File(
      '${saves.directory(journal).path}/${journal['capture']}/$path',
    );
    expect(await captured.readAsBytes(), [3, 4]);
    await saves.restoreOriginal(currentGame, recovery);
    expect(await original.readAsBytes(), [8]);
  });

  test('a surviving state cannot hide a missing working SRAM file', () async {
    await manager.connectGbaRoot(emulator);
    final p = await plan(), g = game(p), saves = SharedAndroidSaves(manager);
    await (await p.target('save/game.srm')).writeAsBytes([1]);
    final key = '${p.areas.last.id}/game.state';
    await (await p.target(key)).writeAsBytes([2]);
    await saves.begin(g, p, 'a' * 64, selected: '/game/Minish Cap.gba');
    await File('${native.path}/${p.remotePath('save/game.srm')}').delete();
    await expectLater(saves.capture(g, cloud, p), throwsStateError);
    expect(await saves.pending, true);
    expect(await (await p.target('save/game.srm')).readAsBytes(), [1]);
    expect(api.records, isEmpty);
  });

  test('SNES setup is independent of GBA and stages a Snes9x session with compatible states', () async {
    await manager.connectGbaRoot(emulator);
    final setup = AndroidEmulatorSetup(manager, emulator, 'snes', profileId);
    addTearDown(setup.dispose);
    await setup.verify();
    expect(setup.problem, isNull);
    expect(setup.step, AndroidSetupStep.ready);
    await manager.load();
    expect(manager.hasCurrentGbaRoot(emulator), true);
    expect(manager.hasCurrentRoot(emulator, 'snes'), true);
    final snes = playablePlatforms.firstWhere((p) => p.slug == 'snes');
    final rom = await File('${temp.path}/Super Mario World.sfc')
        .writeAsBytes([5, 6]);
    final p = await androidProgressLayout(
      manager,
      profileId,
      emulator,
      snes,
      rom.path,
      contentId: '42',
    ) as AndroidSavePlan;
    expect(p.rooted, true);
    expect(p.format, 'snes9x-sram-v1');
    expect(p.rawSaveKey, 'save/game.srm');
    final g = game(p), saves = SharedAndroidSaves(manager);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final staged = File(await saves.stageRootRom(g, p));
    expect(await staged.readAsBytes(), [5, 6]);
    await put(p.remotePath('save/game.srm'), [1, 2]);
    await put(p.remotePath('${p.areas.last.id}/game.state'), [3]);
    await saves.capture(g, cloud, p);
    expect(await (await p.target('save/game.srm')).readAsBytes(), [1, 2]);
    expect(
      await (await p.target('${p.areas.last.id}/game.state')).readAsBytes(),
      [3],
    );
    await saves.restoreOriginal(g, p);
    expect(await staged.exists(), false);
    await manager.disconnectGbaRoot(emulator, platform: 'snes');
    expect(manager.hasCurrentGbaRoot(emulator), true);
    expect(manager.hasCurrentRoot(emulator, 'snes'), false);
  });

  test('Game Boy setup migrates existing roots and keeps GB and GBC choices independent', () async {
    await manager.connectGbaRoot(emulator);
    await manager.connectGbaRoot(emulator, platform: 'snes');
    final settings = File('${data.path}/android/emulators.json');
    final legacy =
        jsonDecode(await settings.readAsString()) as Map<String, dynamic>;
    legacy['version'] = 5;
    legacy.remove('retroRoots');
    await settings.writeAsString(jsonEncode(legacy));
    await manager.load();
    expect(manager.hasCurrentRoot(emulator, 'gb'), false);
    expect(manager.hasCurrentRoot(emulator, 'gbc'), false);
    final setup = AndroidEmulatorSetup(manager, emulator, 'gb', profileId);
    addTearDown(setup.dispose);
    await setup.verify();
    expect(setup.problem, isNull);
    expect(setup.step, AndroidSetupStep.ready);
    await manager.load();
    expect(manager.hasCurrentRoot(emulator, 'gb'), true);
    expect(manager.hasCurrentRoot(emulator, 'gbc'), false);
    expect(manager.hasCurrentGbaRoot(emulator), true);
    expect(manager.hasCurrentRoot(emulator, 'snes'), true);
    await manager.connectGbaRoot(emulator, platform: 'gbc');
    await manager.disconnectGbaRoot(emulator, platform: 'gb');
    await manager.load();
    expect(manager.hasCurrentRoot(emulator, 'gb'), false);
    expect(manager.hasCurrentRoot(emulator, 'gbc'), true);
    expect(manager.hasCurrentGbaRoot(emulator), true);
    expect(manager.hasCurrentRoot(emulator, 'snes'), true);
  });

  test('cartridge setup migrates version 6 without losing GB, GBA or SNES bindings', () async {
    for (final slug in ['gba', 'snes', 'gbc']) {
      await manager.connectGbaRoot(emulator, platform: slug);
    }
    final file = File('${data.path}/android/emulators.json');
    final v6 = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    v6['version'] = 6;
    await file.writeAsString(jsonEncode(v6));
    await manager.load();
    for (final slug in ['atari2600', 'tg16']) {
      await manager.connectGbaRoot(emulator, platform: slug);
    }
    await manager.load();
    for (final slug in ['gba', 'snes', 'gbc', 'atari2600', 'tg16']) {
      expect(manager.hasCurrentRoot(emulator, slug), true);
    }
    await manager.disconnectGbaRoot(emulator, platform: 'tg16');
    await manager.load();
    expect(manager.hasCurrentRoot(emulator, 'tg16'), false);
    for (final slug in ['gba', 'snes', 'gbc', 'atari2600']) {
      expect(manager.hasCurrentRoot(emulator, slug), true);
    }
  });

  test('Sega setup migrates version 7 and keeps shared-core platform choices independent', () async {
    const previous = ['gba', 'snes', 'gb', 'gbc', 'atari2600', 'tg16'];
    for (final slug in previous) {
      await manager.connectGbaRoot(emulator, platform: slug);
    }
    final file = File('${data.path}/android/emulators.json');
    final v7 = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    v7['version'] = 7;
    await file.writeAsString(jsonEncode(v7));
    await manager.load();
    const sega = ['genesis', 'sms', 'gamegear', 'sega32'];
    for (final slug in sega) {
      await manager.connectGbaRoot(emulator, platform: slug);
    }
    await manager.load();
    for (final slug in [...previous, ...sega]) {
      expect(manager.hasCurrentRoot(emulator, slug), true);
    }
    await manager.disconnectGbaRoot(emulator, platform: 'gamegear');
    await manager.load();
    expect(manager.hasCurrentRoot(emulator, 'gamegear'), false);
    for (final slug in [...previous, 'genesis', 'sms', 'sega32']) {
      expect(manager.hasCurrentRoot(emulator, slug), true);
    }
  });

  test('N64 setup migrates version 8 while retaining every earlier platform binding', () async {
    const previous = [
      'gba',
      'snes',
      'gb',
      'gbc',
      'atari2600',
      'tg16',
      'genesis',
      'sms',
      'gamegear',
      'sega32',
    ];
    for (final slug in previous) {
      await manager.connectGbaRoot(emulator, platform: slug);
    }
    final file = File('${data.path}/android/emulators.json');
    final old = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    old['version'] = 8;
    await file.writeAsString(jsonEncode(old));
    await manager.load();
    await manager.connectGbaRoot(emulator, platform: 'n64');
    await manager.load();
    for (final slug in [...previous, 'n64']) {
      expect(manager.hasCurrentRoot(emulator, slug), true);
    }
    await manager.disconnectGbaRoot(emulator, platform: 'n64');
    await manager.load();
    expect(manager.hasCurrentRoot(emulator, 'n64'), false);
    for (final slug in previous) {
      expect(manager.hasCurrentRoot(emulator, slug), true);
    }
  });

  test('N64 full native SRAM and uncompressed states survive cloud restore and standalone recovery', () async {
    await manager.connectGbaRoot(emulator, platform: 'n64');
    final rom = await File('${temp.path}/Cartridge.z64')
        .writeAsBytes([0x80, 0x37, 0x12, 0x40]);
    final p = await gameboyPlan('n64', rom.path), g = game(p);
    expect(p.format, 'libretro-mupen64plus_next-v1');
    expect(p.arguments['coreName'], 'mupen64plus_next');
    final original = await put(p.remotePath('save/game.srm'), [8, 9]);
    final saves = SharedAndroidSaves(manager);
    await cloud.beforePlay(g);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final sram = Uint8List.fromList(List.generate(296960, (i) => i % 251));
    final state = Uint8List(16793412)..[0] = 3;
    state[state.length - 1] = 7;
    final stateKey = '${p.areas.last.id}/game.state';
    await put(p.remotePath('save/game.srm'), sram);
    await put(p.remotePath(stateKey), state);
    await saves.capture(g, cloud, p);
    await saves.restoreOriginal(g, p);
    expect(await original.readAsBytes(), [8, 9]);
    await cloud.afterPlay(g, 0);
    final next = ProgressLayout(
      '${temp.path}/other-device/profiles/$profileId/emulators/retroarch',
      p.format,
      p.game,
      p.areas,
    );
    final remote = CloudGame(
      server: serverId,
      profile: profileId,
      user: api.user,
      rom: 42,
      client: api,
      layout: next,
    );
    final otherCloud = CloudSaves(
      Directory('${temp.path}/other-device'),
      notice: (_, _) {},
    );
    await otherCloud.beforePlay(remote);
    expect(
      await progressFileHash(await next.target('save/game.srm')),
      await progressFileHash(await p.target('save/game.srm')),
    );
    expect(
      await progressFileHash(await next.target(stateKey)),
      await progressFileHash(await p.target(stateKey)),
    );
    expect(await (await next.target('save/game.srm')).length(), sram.length);
    expect(await (await next.target(stateKey)).length(), state.length);
    expect((await cloud.store(g).state())['pending'], false);
    expect(await saves.pending, false);
  });

  test('N64 resource limits accept its cartridge and refuse oversized progress without widening GBA', () async {
    await manager.connectGbaRoot(emulator, platform: 'n64');
    await manager.connectGbaRoot(emulator);
    final rom = File('${temp.path}/Large.n64');
    final handle = await rom.open(mode: FileMode.writeOnly);
    await handle.truncate(33 * 1024 * 1024);
    await handle.close();
    final p = await gameboyPlan('n64', rom.path), g = game(p);
    final saves = SharedAndroidSaves(manager);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final staged = await saves.stageRootRom(g, p);
    expect(await File(staged).length(), 33 * 1024 * 1024);
    await saves.capture(g, cloud, p);
    await saves.restoreOriginal(g, p);
    final oversized = await rom.open(mode: FileMode.writeOnly);
    await oversized.truncate(64 * 1024 * 1024 + 1);
    await oversized.close();
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    await expectLater(saves.stageRootRom(g, p), throwsStateError);
    await saves.capture(g, cloud, p);
    await saves.restoreOriginal(g, p);
    Map<String, dynamic> entry(AndroidSavePlan plan, String key, int bytes) => {
      plan.remotePath(key): {
        'bytes': bytes,
        'sha256': 'd' * 64,
        'metadata': attributes,
      },
    };
    expect(saves.inventory(entry(p, 'save/game.srm', 296960), p), isNotEmpty);
    expect(
      () => saves.inventory(entry(p, 'save/game.srm', 296961), p),
      throwsFormatException,
    );
    final state = '${p.areas.last.id}/game.state';
    expect(
      () => saves.inventory(entry(p, state, 32 * 1024 * 1024 + 1), p),
      throwsFormatException,
    );
    final gba = await plan();
    expect(
      () => saves.inventory(entry(gba, 'save/game.srm', 296960), gba),
      throwsFormatException,
    );
    expect(
      () => saves.inventory(
        entry(gba, '${gba.areas.last.id}/game.state', 16793412),
        gba,
      ),
      throwsFormatException,
    );
  });

  test('NES setup reads version 9 without claiming or removing earlier connections', () async {
    const previous = [
      'gba',
      'snes',
      'gb',
      'gbc',
      'atari2600',
      'tg16',
      'genesis',
      'sms',
      'gamegear',
      'sega32',
      'n64',
    ];
    for (final slug in previous) {
      await manager.connectGbaRoot(emulator, platform: slug);
    }
    final file = File('${data.path}/android/emulators.json');
    final old = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    old['version'] = 9;
    await file.writeAsString(jsonEncode(old));
    await manager.load();
    expect(manager.hasCurrentRoot(emulator, 'nes'), false);
    await manager.connectGbaRoot(emulator, platform: 'nes');
    await manager.load();
    for (final slug in [...previous, 'nes']) {
      expect(manager.hasCurrentRoot(emulator, slug), true);
    }
    await manager.disconnectGbaRoot(emulator, platform: 'nes');
    await manager.load();
    expect(manager.hasCurrentRoot(emulator, 'nes'), false);
    for (final slug in previous) {
      expect(manager.hasCurrentRoot(emulator, slug), true);
    }
    // An older record cannot assert a connection introduced by version 10.
    (old['retroRoots'] as Map)['nes:$pkg'] = {
      ...manager.rootConnection(emulator, 'n64')!,
    };
    await file.writeAsString(jsonEncode(old));
    await manager.load();
    expect(manager.settingsKnown, false);
    expect(manager.error, isNotNull);
  });

  test('Jaguar setup reads version 10 without claiming or removing earlier connections', () async {
    const previous = [
      'gba',
      'snes',
      'gb',
      'gbc',
      'atari2600',
      'tg16',
      'genesis',
      'sms',
      'gamegear',
      'sega32',
      'n64',
      'nes',
    ];
    for (final slug in previous) {
      await manager.connectGbaRoot(emulator, platform: slug);
    }
    final file = File('${data.path}/android/emulators.json');
    final old = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    old['version'] = 10;
    await file.writeAsString(jsonEncode(old));
    await manager.load();
    expect(manager.hasCurrentRoot(emulator, 'jaguar'), false);
    await manager.connectGbaRoot(emulator, platform: 'jaguar');
    await manager.load();
    for (final slug in [...previous, 'jaguar']) {
      expect(manager.hasCurrentRoot(emulator, slug), true);
    }
    await manager.disconnectGbaRoot(emulator, platform: 'jaguar');
    await manager.load();
    expect(manager.hasCurrentRoot(emulator, 'jaguar'), false);
    for (final slug in previous) {
      expect(manager.hasCurrentRoot(emulator, slug), true);
    }
    // An older record cannot assert a connection introduced by version 11.
    (old['retroRoots'] as Map)['jaguar:$pkg'] = {
      ...manager.rootConnection(emulator, 'n64')!,
    };
    await file.writeAsString(jsonEncode(old));
    await manager.load();
    expect(manager.settingsKnown, false);
    expect(manager.error, isNotNull);
  });

  test(
    'NES raw cartridge formats stage privately while FDS preserves recovery',
    () async {
      await manager.connectGbaRoot(emulator, platform: 'nes');
      for (final extension in ['nes', 'unf', 'unif', 'fds']) {
        final rom = await File('${temp.path}/Cartridge.$extension')
            .writeAsBytes([1, 2, 3]);
        final p = await gameboyPlan('nes', rom.path), g = game(p);
        final original = await put(p.remotePath('save/game.srm'), [8, 9]);
        final saves = SharedAndroidSaves(manager);
        await saves.begin(g, p, 'a' * 64, selected: rom.path);
        if (extension == 'fds') {
          await expectLater(saves.stageRootRom(g, p), throwsStateError);
          expect(await saves.pending, true);
        } else {
          final staged = await saves.stageRootRom(g, p);
          expect(await File(staged).readAsBytes(), [1, 2, 3]);
        }
        await saves.capture(g, cloud, p);
        await saves.restoreOriginal(g, p);
        expect(await original.readAsBytes(), [8, 9]);
        expect(await rom.readAsBytes(), [1, 2, 3]);
        expect(await saves.pending, false);
      }
    },
  );

  test(
    'Arcade setup migrates version 12 and preserves every earlier binding',
    () async {
      final previous = [
        'gba',
        'snes',
        'gb',
        'gbc',
        'atari2600',
        'tg16',
        'genesis',
        'sms',
        'gamegear',
        'sega32',
        'n64',
        'nes',
        'jaguar',
        'lynx',
      ];
      for (final slug in previous)
        await manager.connectGbaRoot(emulator, platform: slug);
      final file = File('${data.path}/android/emulators.json');
      final old = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      old['version'] = 12;
      await file.writeAsString(jsonEncode(old));
      await manager.load();
      expect(manager.hasCurrentRoot(emulator, 'arcade'), false);
      await manager.connectGbaRoot(emulator, platform: 'arcade');
      await manager.load();
      expect(manager.settingsKnown, true, reason: manager.error);
      for (final slug in [...previous, 'arcade'])
        expect(manager.hasCurrentRoot(emulator, slug), true, reason: slug);
      await manager.disconnectGbaRoot(emulator, platform: 'arcade');
      for (final slug in previous)
        expect(manager.hasCurrentRoot(emulator, slug), true);
      (old['retroRoots'] as Map)['arcade:$pkg'] = {
        ...manager.rootConnection(emulator, 'lynx')!,
      };
      await file.writeAsString(jsonEncode(old));
      await manager.load();
      expect(manager.settingsKnown, false);
    },
  );

  Future<AndroidSavePlan> operaPlan(
    String rom, {
    bool prepared = true,
    bool external = false,
  }) async {
    final current = await gameboyPlan('3do', rom);
    final resources = <AndroidOperaResource>[];
    if (external && prepared) {
      final file = await File('${temp.path}/fixture-opera-bios')
          .writeAsBytes(List.filled(1048576, 17));
      resources.add(
        _FixtureOperaResource(
          'panafz10.bin',
          file,
          await progressFileHash(file),
        ),
      );
    }
    return AndroidSavePlan(
      current,
      current.emulator,
      current.binding,
      current.remoteAreas,
      launch: current.launch,
      operaOptions: external
          ? {'opera_bios': 'panafz10.bin'}
          : current.operaOptions,
      operaDisc: prepared
          ? await inspectAndroidOperaDisc(
              File(rom),
              DownloadCancellation(),
              (_) {},
            )
          : null,
      operaResources: prepared ? resources : null,
    );
  }

  Future<File> saturnRom() async {
    final bytes = Uint8List(128)..setRange(0, 8, ascii.encode('MComprHD'));
    ByteData.sublistView(bytes)
      ..setUint32(8, 124)
      ..setUint32(12, 5)
      ..setUint64(32, 4096);
    return File('${temp.path}/Disc.chd').writeAsBytes(bytes);
  }

  Future<AndroidSavePlan> saturnPlan(String rom, {bool prepared = true}) async {
    final current = await gameboyPlan('saturn', rom);
    final resources = <AndroidSaturnResource>[];
    if (prepared) {
      for (final name in androidSaturnResourceNames(current.saturnOptions)) {
        final file = await File('${temp.path}/fixture-$name')
            .writeAsBytes(List.filled(androidSaturnFirmware[name]!.$1, 17));
        resources.add(
          _FixtureSaturnResource(name, file, await progressFileHash(file)),
        );
      }
    }
    return AndroidSavePlan(
      current,
      current.emulator,
      current.binding,
      current.remoteAreas,
      launch: current.launch,
      saturnOptions: current.saturnOptions,
      saturnDisc: prepared
          ? await inspectAndroidSaturnDisc(
              File(rom),
              DownloadCancellation(),
              (_) {},
            )
          : null,
      saturnResources: prepared ? resources : null,
    );
  }

  Future<AndroidSavePlan> flycastPlan(
    String rom, {
    bool prepared = true,
    bool hle = false,
  }) async {
    final current = await gameboyPlan('dc', rom);
    final file = prepared
        ? await File('${temp.path}/dc-boot-fixture.bin')
              .writeAsBytes(List.filled(2097152, 19))
        : null;
    return AndroidSavePlan(
      current,
      current.emulator,
      current.binding,
      current.remoteAreas,
      launch: current.launch,
      flycastNativeOptions: current.flycastNativeOptions,
      flycastOptions: {
        ...current.flycastNativeOptions,
        if (prepared)
          ...await readAndroidFlycastPreferences(
            Directory(current.root),
            current.game,
          ),
      },
      flycastDisc: prepared
          ? await inspectAndroidFlycastDisc(
              File(rom),
              DownloadCancellation(),
              (_) {},
            )
          : null,
      flycastResources: hle && prepared
          ? []
          : file == null
          ? null
          : [_FixtureFlycastResource(file, await progressFileHash(file))],
      flycastConsole: prepared
          ? await readAndroidFlycastConsole(Directory(current.root))
          : null,
    );
  }

  test('Dreamcast setup migrates version fifteen while retaining every prior root binding and refusing forged older entries', () async {
    const prior = [
      'gba',
      'snes',
      'gb',
      'gbc',
      'atari2600',
      'tg16',
      'genesis',
      'sms',
      'gamegear',
      'sega32',
      'n64',
      'nes',
      'jaguar',
      'lynx',
      'arcade',
      '3do',
      'saturn',
    ];
    for (final slug in prior)
      await manager.connectGbaRoot(emulator, platform: slug);
    final settings = File('${data.path}/android/emulators.json');
    final old = await progressJson(settings);
    old['version'] = 15;
    await progressWrite(settings, old);
    await manager.load();
    expect(manager.settingsKnown, true);
    for (final slug in prior)
      expect(manager.hasCurrentRoot(emulator, slug), true);
    expect(manager.hasCurrentRoot(emulator, 'dc'), false);
    await manager.connectGbaRoot(emulator, platform: 'dc');
    await manager.load();
    expect((await progressJson(settings))['version'], 18);
    for (final slug in [...prior, 'dc'])
      expect(manager.hasCurrentRoot(emulator, slug), true);
    (old['retroRoots'] as Map)['dc:$pkg'] = manager.rootConnection(
      emulator,
      'dc',
    );
    await progressWrite(settings, old);
    await manager.load();
    expect(manager.settingsKnown, false);
    expect(manager.error, isNotNull);
  });

  test('Dreamcast preparation detects external core, config and option changes before save effects', () async {
    await manager.connectGbaRoot(emulator, platform: 'dc');
    final rom = await saturnRom(),
        p = await flycastPlan((await saturnRom()).path);
    await verifyAndroidFlycastPreparation(manager, p, rom.path);
    final original = Map<String, dynamic>.from(observation);
    for (final change in ['core', 'config', 'options']) {
      if (change == 'core') observation['core'] = 'b' * 64;
      if (change == 'config')
        observation['config'] = Uint8List.fromList(
          utf8.encode('video_vsync = "false"'),
        );
      if (change == 'options')
        operaOptionsText = 'flycast_internal_resolution = "1280x960"';
      final start = calls.length;
      await expectLater(
        verifyAndroidFlycastPreparation(manager, p, rom.path),
        throwsStateError,
      );
      expect(calls.skip(start), isNot(contains('rootReplace')));
      observation = Map<String, dynamic>.from(original);
      operaOptionsText = null;
    }
  });

  test('Dreamcast native HLE captures VMUs and console flash, reuses the console on a fresh session and cleans up without a retail BIOS', () async {
    await manager.connectGbaRoot(emulator, platform: 'dc');
    final rom = await saturnRom(), saves = SharedAndroidSaves(manager);
    final p = await flycastPlan(rom.path, hle: true), g = game(p);
    await cloud.beforePlay(g);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    var r = await progressJson(saves.journal);
    expect(r['rootFlycastBoot'], 'hle-fallback');
    final resources = r['rootFlycastResources'] as Map;
    expect(resources.keys.where((p) => p.endsWith('/dc_boot.bin')), isEmpty);
    final config = r['rootConfigPath'] as String;
    final base = config.substring(0, config.lastIndexOf('/'));
    final console = '$base/system-${r['transaction']}/dc/dc_nvmem.bin';
    await put(console, List.filled(131072, 3));
    await put(p.remotePath('save/MK-51000.A1.bin'), List.filled(131072, 7));
    await saves.capture(g, cloud, p);
    final known = (await readAndroidFlycastConsole(Directory(p.root)))!;
    await saves.restoreOriginal(g, p);
    await cloud.afterPlay(g, 0);
    expect(await File('${native.path}/$console').exists(), false);
    expect((await p.files()).keys, contains('save/MK-51000.A1.bin'));
    final next = await flycastPlan(rom.path, hle: true), nextGame = game(next);
    await saves.begin(nextGame, next, 'a' * 64, selected: rom.path);
    r = await progressJson(saves.journal);
    final nextConsole = (r['rootFlycastResources'] as Map).keys
        .cast<String>()
        .singleWhere((p) => p.endsWith('/dc_nvmem.bin'));
    expect(
      await progressFileHash(File('${native.path}/$nextConsole')),
      known.sha256,
    );
    await saves.capture(nextGame, cloud, next);
    await saves.restoreOriginal(nextGame, next);
    expect(await saves.pending, false);
    expect(
      (await readAndroidFlycastConsole(Directory(p.root)))!.sha256,
      known.sha256,
    );
  });

  test('A legacy Flycast record missing its known BIOS is damaged recovery rather than implicit HLE', () async {
    await manager.connectGbaRoot(emulator, platform: 'dc');
    final rom = await saturnRom(),
        p = await flycastPlan((await saturnRom()).path);
    final saves = SharedAndroidSaves(manager), g = game(p);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final r = await progressJson(saves.journal);
    r.remove('rootFlycastBoot');
    final resources = r['rootFlycastResources'] as Map;
    resources.removeWhere((key, _) => key.endsWith('/dc_boot.bin'));
    await progressWrite(saves.journal, r);
    final start = calls.length;
    await expectLater(saves.capture(g, cloud, p), throwsFormatException);
    expect(await saves.pending, true);
    expect(calls.skip(start), isNot(contains('rootFlycastReplace')));
    expect(await rom.exists(), true);
  });

  test('Dreamcast missing known native flash retains console identity and cleanup reply loss retries without source firmware', () async {
    await manager.connectGbaRoot(emulator, platform: 'dc');
    final rom = await saturnRom(),
        initial = await gameboyPlan('dc', (await saturnRom()).path);
    final seed = await File('${temp.path}/console-seed.bin')
        .writeAsBytes(List.filled(131072, 4));
    final hash = await progressFileHash(seed);
    await publishAndroidFlycastConsole(
      Directory(initial.root),
      null,
      seed,
      hash,
    );
    final p = await flycastPlan(rom.path),
        g = game(p),
        saves = SharedAndroidSaves(manager);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final before = await progressJson(saves.journal);
    final flashPath = (before['rootFlycastResources'] as Map).keys
        .cast<String>()
        .singleWhere((p) => p.endsWith('/dc_nvmem.bin'));
    await File('${native.path}/$flashPath').delete();
    await expectLater(saves.capture(g, cloud, p), throwsStateError);
    expect(await saves.pending, true);
    expect((await readAndroidFlycastConsole(Directory(p.root)))!.sha256, hash);
    await put(flashPath, List.filled(131072, 4));
    await saves.capture(g, cloud, p);
    loseFirmwareCleanupReply = true;
    await expectLater(
      saves.restoreOriginal(g, p),
      throwsA(isA<PlatformException>()),
    );
    await p.flycastResources!.single.file.delete();
    expect(await saves.capture(g, cloud, p), false);
    await saves.restoreOriginal(g, p);
    expect(await saves.pending, false);
    expect((await readAndroidFlycastConsole(Directory(p.root)))!.sha256, hash);
  });

  test('Dreamcast round trip preserves VMUs, console identity and editable options independently of cloud game progress', () async {
    await manager.connectGbaRoot(emulator, platform: 'dc');
    final rom = await saturnRom(), saves = SharedAndroidSaves(manager);
    final p = await flycastPlan(rom.path), g = game(p);
    final original = await put(
      p.remotePath('save/MK-51000.A1.bin'),
      List.filled(131072, 8),
    );
    await cloud.beforePlay(g);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final staged = File(await saves.stageRootRom(g, p));
    final resources = await progressJson(saves.journal);
    final resourcePaths = (resources['rootFlycastResources'] as Map).keys
        .cast<String>();
    final optionPath = resourcePaths.singleWhere((p) => p.endsWith('.opt'));
    final system = resourcePaths
        .singleWhere((p) => p.endsWith('/dc_boot.bin'))
        .replaceFirst('/dc_boot.bin', '');
    await put('$system/dc_nvmem.bin', List.filled(131072, 3));
    await put(
      optionPath,
      utf8.encode(
        androidFlycastOptionsText({'flycast_internal_resolution': '1280x960'}),
      ),
    );
    await put(p.remotePath('save/MK-51000.A1.bin'), List.filled(131072, 7));
    await put(p.remotePath('${p.areas.last.id}/game.state'), [4, 5, 6]);
    await saves.capture(g, cloud, p);
    final console = (await readAndroidFlycastConsole(Directory(p.root)))!;
    await saves.restoreOriginal(g, p);
    await cloud.afterPlay(g, 0);
    expect(await original.readAsBytes(), List.filled(131072, 8));
    expect(await staged.exists(), false);
    expect((await p.files()).keys.toSet(), {
      'save/MK-51000.A1.bin',
      '${p.areas.last.id}/game.state',
    });
    expect(await readAndroidFlycastPreferences(Directory(p.root), '42'), {
      'flycast_internal_resolution': '1280x960',
    });
    final next = await flycastPlan(rom.path), nextGame = game(next);
    await saves.begin(nextGame, next, 'a' * 64, selected: rom.path);
    final nextRecord = await progressJson(saves.journal),
        nextPaths = (nextRecord['rootFlycastResources'] as Map).keys
            .cast<String>();
    final flash = File(
      '${native.path}/${nextPaths.singleWhere((p) => p.endsWith('/dc_nvmem.bin'))}',
    );
    expect(await progressFileHash(flash), console.sha256);
    final opts = await File(
      '${native.path}/${nextPaths.singleWhere((p) => p.endsWith('.opt'))}',
    ).readAsBytes();
    expect(
      parseAndroidFlycastOptions(opts)['flycast_internal_resolution'],
      '1280x960',
    );
    await saves.capture(nextGame, cloud, next);
    await saves.restoreOriginal(nextGame, next);
    expect(
      (await readAndroidFlycastConsole(Directory(p.root)))!.sha256,
      console.sha256,
    );
    expect(await console.file.exists(), true);
  });

  test('Flycast native legacy-to-game-ID VMU saves capture changed bytes on every port and restore original native cards', () async {
    await manager.connectGbaRoot(emulator, platform: 'dc');
    final rom = await saturnRom(), p = await flycastPlan(rom.path, hle: true);
    final saves = SharedAndroidSaves(manager), g = game(p);
    final original = await put(
      p.remotePath('save/ORIGINAL.A2.bin'),
      List.filled(131072, 8),
    );
    for (final slot in ['A1', 'B1', 'C1', 'D1']) {
      await (await p.target('save/Disc.$slot.bin'))
          .writeAsBytes(List.filled(131072, 4));
    }
    await cloud.beforePlay(g);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final r = await progressJson(saves.journal),
        resources = r['rootFlycastResources'] as Map;
    final config = r['rootConfigPath'] as String,
        base = config.substring(0, config.lastIndexOf('/'));
    await put(
      '$base/system-${r['transaction']}/dc/dc_nvmem.bin',
      List.filled(131072, 3),
    );
    for (final slot in ['A1', 'B1', 'C1', 'D1']) {
      await File('${native.path}/${p.remotePath('save/Disc.$slot.bin')}')
          .delete();
      await put(
        p.remotePath('save/MK-51000.$slot.bin'),
        List.filled(131072, 7),
      );
    }
    await put(
      resources.keys.cast<String>().singleWhere((p) => p.endsWith('.opt')),
      utf8.encode(androidFlycastOptionsText({'reicast_cable_type': 'VGA'})),
    );
    await saves.capture(g, cloud, p);
    final captured = await progressJson(saves.journal);
    expect((captured['captured'] as Map).length, 4);
    for (final slot in ['A1', 'B1', 'C1', 'D1']) {
      expect(
        await (await p.target('save/MK-51000.$slot.bin')).readAsBytes(),
        List.filled(131072, 7),
      );
      expect(
        await File(
          '${saves.directory(r).path}/working/${p.remotePath('save/Disc.$slot.bin')}',
        ).readAsBytes(),
        List.filled(131072, 4),
      );
    }
    expect(
      (await p.files()).keys.any((p) => p.startsWith('save/Disc.')),
      false,
    );
    await saves.restoreOriginal(g, p);
    await cloud.afterPlay(g, 0);
    expect(await original.readAsBytes(), List.filled(131072, 8));
    expect(await saves.pending, false);
    expect(await readAndroidFlycastPreferences(Directory(p.root), '42'), {
      'reicast_cable_type': 'VGA',
    });
    final next = await flycastPlan(rom.path, hle: true), nextGame = game(next);
    await saves.begin(nextGame, next, 'a' * 64, selected: rom.path);
    for (final slot in ['A1', 'B1', 'C1', 'D1']) {
      expect(
        await File(
          '${native.path}/${next.remotePath('save/MK-51000.$slot.bin')}',
        ).readAsBytes(),
        List.filled(131072, 7),
      );
    }
    await saves.capture(nextGame, cloud, next);
    await saves.restoreOriginal(nextGame, next);
    expect(await original.readAsBytes(), List.filled(131072, 8));
  });

  test('Competing native VMU destinations retain every candidate and legacy input without publishing a guessed migration', () async {
    await manager.connectGbaRoot(emulator, platform: 'dc');
    final rom = await saturnRom(), p = await flycastPlan(rom.path, hle: true);
    final saves = SharedAndroidSaves(manager), g = game(p);
    await (await p.target('save/Disc.A1.bin'))
        .writeAsBytes(List.filled(131072, 4));
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final r = await progressJson(saves.journal),
        config = r['rootConfigPath'] as String;
    final base = config.substring(0, config.lastIndexOf('/'));
    await put(
      '$base/system-${r['transaction']}/dc/dc_nvmem.bin',
      List.filled(131072, 3),
    );
    await File('${native.path}/${p.remotePath('save/Disc.A1.bin')}').delete();
    for (final id in ['FIRST', 'SECOND'])
      await put(p.remotePath('save/$id.A1.bin'), List.filled(131072, 7));
    await expectLater(saves.capture(g, cloud, p), throwsStateError);
    final failed = await progressJson(saves.journal),
        held = failed['rootFlycastHeldProgress'] as Map;
    for (final id in ['FIRST', 'SECOND']) {
      expect(
        await File(
          '${saves.directory(r).path}/${held['directory']}/${p.remotePath('save/$id.A1.bin')}',
        ).length(),
        131072,
      );
    }
    expect(
      await File(
        '${saves.directory(r).path}/working/${p.remotePath('save/Disc.A1.bin')}',
      ).readAsBytes(),
      List.filled(131072, 4),
    );
    expect(await saves.pending, true);
    expect(api.records, isEmpty);
    expect(await readAndroidFlycastConsole(Directory(p.root)), isNull);
  });

  test('Missing established native-ID cards and missing states cannot be explained by another VMU filename', () async {
    await manager.connectGbaRoot(emulator, platform: 'dc');
    final rom = await saturnRom(), p = await flycastPlan(rom.path, hle: true);
    final saves = SharedAndroidSaves(manager),
        g = game(p),
        stateKey = '${p.areas.last.id}/game.state';
    await (await p.target('save/MK-51000.A1.bin'))
        .writeAsBytes(List.filled(131072, 4));
    await (await p.target(stateKey)).writeAsBytes([1, 2, 3]);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final r = await progressJson(saves.journal),
        config = r['rootConfigPath'] as String;
    final base = config.substring(0, config.lastIndexOf('/'));
    await put(
      '$base/system-${r['transaction']}/dc/dc_nvmem.bin',
      List.filled(131072, 3),
    );
    final cardPath = p.remotePath('save/MK-51000.A1.bin');
    await File('${native.path}/$cardPath').delete();
    await put(p.remotePath('save/OTHER.A1.bin'), List.filled(131072, 7));
    await expectLater(saves.capture(g, cloud, p), throwsStateError);
    await put(cardPath, List.filled(131072, 4));
    await File('${native.path}/${p.remotePath(stateKey)}').delete();
    await expectLater(saves.capture(g, cloud, p), throwsStateError);
    final failed = await progressJson(saves.journal),
        held = failed['rootFlycastHeldProgress'] as Map;
    expect((held['files'] as Map).length, 2);
    expect(
      await File('${saves.directory(r).path}/working/${p.remotePath(stateKey)}')
          .readAsBytes(),
      [1, 2, 3],
    );
    expect(await saves.pending, true);
    expect(api.records, isEmpty);
    expect(await readAndroidFlycastConsole(Directory(p.root)), isNull);
  });

  test('Dreamcast fallback and damaged working VMUs retain private recovery instead of publishing incomplete game progress', () async {
    await manager.connectGbaRoot(emulator, platform: 'dc');
    final rom = await saturnRom(),
        p = await flycastPlan((await saturnRom()).path),
        saves = SharedAndroidSaves(manager);
    final g = game(p);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final r = await progressJson(saves.journal),
        paths = (r['rootFlycastResources'] as Map).keys.cast<String>();
    final system = paths
        .singleWhere((p) => p.endsWith('/dc_boot.bin'))
        .replaceFirst('/dc_boot.bin', '');
    await put('$system/dc_nvmem.bin', List.filled(131072, 3));
    final fallback = await put(
      '$system/vmu_save_A1.bin',
      List.filled(131072, 5),
    );
    final heldCardPath = p.remotePath('save/MK-51000.A1.bin');
    await put(heldCardPath, List.filled(131072, 6));
    await put(p.remotePath('${p.areas.last.id}/game.state'), [7, 8]);
    await expectLater(saves.capture(g, cloud, p), throwsStateError);
    final failed = await progressJson(saves.journal);
    final captured = failed['rootFlycastCapture'] as Map;
    final held = failed['rootFlycastHeldProgress'] as Map;
    expect((held['files'] as Map).length, 2);
    expect(
      await File(
        '${saves.directory(r).path}/${held['directory']}/$heldCardPath',
      ).length(),
      131072,
    );
    expect(
      (captured['files'] as Map).containsKey('$system/vmu_save_A1.bin'),
      true,
    );
    expect(
      await File(
        '${saves.directory(r).path}/flycast-captures/${captured['directory']}/vmu_save_A1.bin',
      ).length(),
      131072,
    );
    expect(await saves.pending, true);
    expect(api.records, isEmpty);
    await fallback.delete();
    final card = await put(p.remotePath('save/MK-51000.A1.bin'), [1]);
    await expectLater(saves.capture(g, cloud, p), throwsFormatException);
    expect(await card.readAsBytes(), [1]);
    expect(
      await File(
        '${saves.directory(r).path}/${held['directory']}/$heldCardPath',
      ).readAsBytes(),
      List.filled(131072, 6),
    );
    expect(await saves.pending, true);
    await card.writeAsBytes(List.filled(131072, 6));
    await saves.capture(g, cloud, p);
    await saves.restoreOriginal(g, p);
    expect((await p.files()).keys, contains('save/MK-51000.A1.bin'));
  });

  for (final prefix in ['reicast', 'flycast'])
    test(
      'Changing the active $prefix VMU mode retains ordinary and state recovery without publishing progress',
      () async {
        await manager.connectGbaRoot(emulator, platform: 'dc');
        final rom = await saturnRom(),
            p = await flycastPlan((await saturnRom()).path);
        final saves = SharedAndroidSaves(manager), g = game(p);
        await saves.begin(g, p, 'a' * 64, selected: rom.path);
        final r = await progressJson(saves.journal);
        final paths = (r['rootFlycastResources'] as Map).keys.cast<String>();
        final bios = paths.singleWhere((p) => p.endsWith('/dc_boot.bin'));
        await put(
          bios.replaceFirst('dc_boot.bin', 'dc_nvmem.bin'),
          List.filled(131072, 3),
        );
        final options = paths.singleWhere((p) => p.endsWith('.opt'));
        await put(
          options,
          utf8.encode(
            androidFlycastOptionsText({}).replaceFirst(
              '${prefix}_per_content_vmus = "All VMUs"',
              '${prefix}_per_content_vmus = "disabled"',
            ),
          ),
        );
        final card = p.remotePath('save/MK-51000.A1.bin');
        await put(card, List.filled(131072, 6));
        await put(p.remotePath('${p.areas.last.id}/game.state'), [7, 8]);
        await expectLater(saves.capture(g, cloud, p), throwsStateError);
        final failed = await progressJson(saves.journal),
            held = failed['rootFlycastHeldProgress'] as Map;
        expect((held['files'] as Map).length, 2);
        expect(
          await File('${saves.directory(r).path}/${held['directory']}/$card')
              .readAsBytes(),
          List.filled(131072, 6),
        );
        expect(api.records, isEmpty);
        expect(await saves.pending, true);
        expect(await readAndroidFlycastConsole(Directory(p.root)), isNull);
        expect(await rom.exists(), true);
      },
    );

  test('Dreamcast lost firmware reply recovers without source files and rejects foreign or incomplete version-five records', () async {
    await manager.connectGbaRoot(emulator, platform: 'dc');
    final rom = await saturnRom(),
        p = await flycastPlan((await saturnRom()).path),
        saves = SharedAndroidSaves(manager);
    final g = game(p);
    loseFirmwarePublicationReply = true;
    await expectLater(
      saves.begin(g, p, 'a' * 64, selected: rom.path),
      throwsA(isA<PlatformException>()),
    );
    final record = await progressJson(saves.journal);
    await p.flycastResources!.single.file.delete();
    await (await progressFile(
      saves.directory(record),
      'flycast-incoming/options.opt',
    )).delete();
    for (final change in [
      {'transaction': 'f' * 32},
      {'rootFirmware': <String, Object>{}},
      {'rootFlycastResources': <String, Object>{}},
    ]) {
      await progressWrite(saves.journal, {...record, ...change});
      await expectLater(saves.record(g, p), throwsFormatException);
    }
    await progressWrite(saves.journal, record);
    final session = AndroidGameSession(manager, cloud);
    addTearDown(session.dispose);
    expect((await session.pending())!['stateAreas'], [p.areas.last.id]);
    final current = await flycastPlan(rom.path, prepared: false);
    final recovery = await saves.recoveryPlan(game(current), current);
    expect(await saves.capture(g, cloud, recovery), false);
    await saves.restoreOriginal(g, recovery);
    expect(await session.pending(), isNull);
    expect(api.records, isEmpty);
  });

  test('Opera migration retains all version-13 bindings, persists its own Setup and refuses an old forged connection', () async {
    final previous = [
      'gba',
      'snes',
      'gb',
      'gbc',
      'atari2600',
      'tg16',
      'genesis',
      'sms',
      'gamegear',
      'sega32',
      'n64',
      'nes',
      'jaguar',
      'lynx',
      'arcade',
    ];
    for (final slug in previous)
      await manager.connectGbaRoot(emulator, platform: slug);
    final file = File('${data.path}/android/emulators.json');
    final old = await progressJson(file)
      ..['version'] = 13;
    await file.writeAsString(jsonEncode(old));
    await manager.load();
    expect(manager.settingsKnown, true);
    expect(manager.hasCurrentRoot(emulator, '3do'), false);
    await manager.connectGbaRoot(emulator, platform: '3do');
    await manager.load();
    expect(manager.settingsKnown, true, reason: manager.error);
    for (final slug in [...previous, '3do'])
      expect(manager.hasCurrentRoot(emulator, slug), true, reason: slug);
    await manager.disconnectGbaRoot(emulator, platform: '3do');
    await manager.load();
    for (final slug in previous)
      expect(manager.hasCurrentRoot(emulator, slug), true);
    expect(manager.hasCurrentRoot(emulator, '3do'), false);
    (old['retroRoots'] as Map)['3do:$pkg'] = manager.rootConnection(
      emulator,
      'arcade',
    );
    await file.writeAsString(jsonEncode(old));
    await manager.load();
    expect(manager.settingsKnown, false);
  });

  test('Saturn migration retains all version-14 bindings, persists its own Setup and refuses an old forged connection', () async {
    final previous = [
      'gba',
      'snes',
      'gb',
      'gbc',
      'atari2600',
      'tg16',
      'genesis',
      'sms',
      'gamegear',
      'sega32',
      'n64',
      'nes',
      'jaguar',
      'lynx',
      'arcade',
      '3do',
    ];
    for (final slug in previous)
      await manager.connectGbaRoot(emulator, platform: slug);
    final file = File('${data.path}/android/emulators.json');
    final old = await progressJson(file)
      ..['version'] = 14;
    await file.writeAsString(jsonEncode(old));
    await manager.load();
    expect(manager.settingsKnown, true);
    expect(manager.hasCurrentRoot(emulator, 'saturn'), false);
    await manager.connectGbaRoot(emulator, platform: 'saturn');
    await manager.load();
    expect(manager.settingsKnown, true, reason: manager.error);
    for (final slug in [...previous, 'saturn'])
      expect(manager.hasCurrentRoot(emulator, slug), true, reason: slug);
    await manager.disconnectGbaRoot(emulator, platform: 'saturn');
    await manager.load();
    for (final slug in previous)
      expect(manager.hasCurrentRoot(emulator, slug), true);
    expect(manager.hasCurrentRoot(emulator, 'saturn'), false);
    (old['retroRoots'] as Map)['saturn:$pkg'] = manager.rootConnection(
      emulator,
      '3do',
    );
    await file.writeAsString(jsonEncode(old));
    await manager.load();
    expect(manager.settingsKnown, false);
  });

  test('Opera captures native mode/version NVRAM and states while restoring original and foreign files', () async {
    await manager.connectGbaRoot(emulator, platform: '3do');
    final rom = await File('${temp.path}/Disc.iso').writeAsBytes([1, 2, 3]);
    final p = await operaPlan(rom.path), g = game(p);
    expect(p.rawSaveKey, 'save/opera/per_game/Disc.0.srm');
    expect(
      androidIni(p.launch['configText']!)['core_options_path'],
      '/storage/emulated/0/Android/data/$pkg/files/retroarch-core-options.cfg',
    );
    final original = await put(
      p.remotePath(p.rawSaveKey!),
      List.filled(32768, 8),
    );
    final foreign = await put(
      '${p.remoteAreas.first.remote}/opera/per_game/Other.2.srm',
      [7],
    );
    final saves = SharedAndroidSaves(manager);
    await cloud.beforePlay(g);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final staged = File(await saves.stageRootRom(g, p));
    expect(await staged.readAsBytes(), [1, 2, 3]);
    final keys = [
      p.rawSaveKey!,
      'save/opera/per_game/Disc.7.srm',
      'save/opera/shared/nvram.4.srm',
      '${p.areas.last.id}/game.state',
    ];
    for (var i = 0; i < keys.length; i++)
      await put(
        p.remotePath(keys[i]),
        i == keys.length - 1 ? [i, i + 1] : List.filled(32768, i),
      );
    await saves.capture(g, cloud, p);
    expect((await p.files()).keys.toSet(), keys.toSet());
    await saves.restoreOriginal(g, p);
    await cloud.afterPlay(g, 0);
    expect(api.records, isNotEmpty);
    expect(await original.readAsBytes(), List.filled(32768, 8));
    expect(await foreign.readAsBytes(), [7]);
    expect(await staged.exists(), false);
    expect(await saves.pending, false);
    final nextPlan = await operaPlan(rom.path), nextGame = game(nextPlan);
    final swapped = SharedAndroidSaves(manager);
    await swapped.begin(nextGame, nextPlan, 'a' * 64, selected: rom.path);
    await File(
      '${native.path}/${p.remotePath('save/opera/per_game/Disc.7.srm')}',
    ).delete();
    await expectLater(
      swapped.capture(nextGame, cloud, nextPlan),
      throwsStateError,
    );
    expect(await swapped.pending, true);
    expect(
      await (await p.target('save/opera/per_game/Disc.7.srm')).readAsBytes(),
      List.filled(32768, 1),
    );
    await put(
      p.remotePath('save/opera/per_game/Disc.7.srm'),
      List.filled(32768, 1),
    );
    await swapped.capture(nextGame, cloud, nextPlan);
    await swapped.restoreOriginal(nextGame, nextPlan);
  });

  test('Opera preparation rechecks core, frontend configuration and native options before save effects', () async {
    await manager.connectGbaRoot(emulator, platform: '3do');
    final rom = await File('${temp.path}/Disc.iso').writeAsBytes([1, 2, 3]);
    final p = await operaPlan(rom.path);
    await verifyAndroidOperaPreparation(manager, p, rom.path);
    final core = observation['core'], config = observation['config'];
    for (final change in ['core', 'config', 'options']) {
      observation['core'] = core;
      observation['config'] = config;
      operaOptionsText = null;
      if (change == 'core') observation['core'] = 'f' * 64;
      if (change == 'config')
        observation['config'] = Uint8List.fromList(
          utf8.encode('global_core_options = "true"'),
        );
      if (change == 'options') operaOptionsText = 'opera_nvram_version = "7"';
      await expectLater(
        verifyAndroidOperaPreparation(manager, p, rom.path),
        throwsStateError,
      );
      expect(await SharedAndroidSaves(manager).pending, false);
      expect(api.records, isEmpty);
    }
  });

  test('Saturn preparation rechecks core, frontend configuration and native options before save effects', () async {
    await manager.connectGbaRoot(emulator, platform: 'saturn');
    final rom = await saturnRom();
    final p = await saturnPlan(rom.path);
    await verifyAndroidSaturnPreparation(manager, p, rom.path);
    final core = observation['core'], config = observation['config'];
    for (final change in ['core', 'config', 'options']) {
      observation['core'] = core;
      observation['config'] = config;
      operaOptionsText = null;
      if (change == 'core') observation['core'] = 'f' * 64;
      if (change == 'config')
        observation['config'] = Uint8List.fromList(
          utf8.encode('global_core_options = "true"'),
        );
      if (change == 'options')
        operaOptionsText = 'beetle_saturn_save_method = "mednafen"';
      await expectLater(
        verifyAndroidSaturnPreparation(manager, p, rom.path),
        throwsStateError,
      );
      expect(await SharedAndroidSaves(manager).pending, false);
      expect(api.records, isEmpty);
    }
  });

  test(
    'Opera staging retains the inspected disc hash when its source changes',
    () async {
      await manager.connectGbaRoot(emulator, platform: '3do');
      final rom = await File('${temp.path}/Disc.iso').writeAsBytes([1, 2, 3]);
      final p = await operaPlan(rom.path),
          g = game(p),
          saves = SharedAndroidSaves(manager);
      await saves.begin(g, p, 'a' * 64, selected: rom.path);
      await rom.writeAsBytes([4, 5, 6]);
      await expectLater(
        saves.stageRootRom(g, p),
        throwsA(isA<PlatformException>()),
      );
      expect(await saves.pending, true);
      final record = await progressJson(saves.journal);
      expect(record['romStageSha256'], p.operaDisc!.sha256);
      expect(
        await File('${native.path}/${record['romStage']}').exists(),
        false,
      );
      await saves.capture(g, cloud, p);
      await saves.restoreOriginal(g, p);
      expect(await rom.readAsBytes(), [4, 5, 6]);
    },
  );

  test('Opera firmware publication loss recovers without cache, staged resource or general marker', () async {
    await manager.connectGbaRoot(emulator, platform: '3do');
    final rom = await File('${temp.path}/Disc.iso').writeAsBytes([1, 2, 3]);
    final p = await operaPlan(rom.path, external: true),
        g = game(p),
        saves = SharedAndroidSaves(manager);
    final key = '${p.areas.last.id}/game.state';
    await (await p.target(key)).writeAsBytes([7, 8]);
    loseFirmwarePublicationReply = true;
    await expectLater(
      saves.begin(g, p, 'a' * 64, selected: rom.path),
      throwsA(isA<PlatformException>()),
    );
    final record = await progressJson(saves.journal);
    await p.operaResources!.single.file.delete();
    await (await progressFile(
      saves.directory(record),
      'firmware/panafz10.bin',
    )).delete();
    for (final changed in [
      {'coreName': 'fbneo'},
      {'rootFirmware': <String, Object>{}},
      {'transaction': 'f' * 32},
    ]) {
      await progressWrite(saves.journal, {...record, ...changed});
      await expectLater(saves.record(g, p), throwsFormatException);
      expect(await (await p.target(key)).readAsBytes(), [7, 8]);
    }
    await progressWrite(saves.journal, record);
    final session = AndroidGameSession(manager, cloud);
    addTearDown(session.dispose);
    expect((await session.pending())!['stateAreas'], [p.areas.last.id]);
    final current = await operaPlan(rom.path, prepared: false);
    final recovered = await saves.recoveryPlan(game(current), current);
    expect(await saves.capture(g, cloud, recovered), false);
    await saves.restoreOriginal(g, recovered);
    expect(await session.pending(), isNull);
    expect(api.records, isEmpty);
    expect(await (await p.target(key)).readAsBytes(), [7, 8]);
    final resources = record['rootOperaFirmware'] as Map;
    expect(
      await File('${native.path}/${(resources.values.single as Map)['path']}')
          .exists(),
      false,
    );
  });

  test('Saturn firmware publication loss recovers without cache, staged resource or general marker', () async {
    await manager.connectGbaRoot(emulator, platform: 'saturn');
    final rom = await saturnRom();
    final p = await saturnPlan(rom.path),
        g = game(p),
        saves = SharedAndroidSaves(manager);
    final key = '${p.areas.last.id}/game.state';
    await (await p.target(key)).writeAsBytes([7, 8]);
    loseFirmwarePublicationReply = true;
    await expectLater(
      saves.begin(g, p, 'a' * 64, selected: rom.path),
      throwsA(isA<PlatformException>()),
    );
    final record = await progressJson(saves.journal);
    for (final image in p.saturnResources!) await image.file.delete();
    await (await progressFile(
      saves.directory(record),
      'firmware/sega_101.bin',
    )).delete();
    for (final changed in [
      {'coreName': 'fbneo'},
      {'rootFirmware': <String, Object>{}},
      {'transaction': 'f' * 32},
    ]) {
      await progressWrite(saves.journal, {...record, ...changed});
      await expectLater(saves.record(g, p), throwsFormatException);
      expect(await (await p.target(key)).readAsBytes(), [7, 8]);
    }
    await progressWrite(saves.journal, record);
    final session = AndroidGameSession(manager, cloud);
    addTearDown(session.dispose);
    expect((await session.pending())!['stateAreas'], [p.areas.last.id]);
    final current = await saturnPlan(rom.path, prepared: false);
    final recovered = await saves.recoveryPlan(game(current), current);
    expect(await saves.capture(g, cloud, recovered), false);
    await saves.restoreOriginal(g, recovered);
    expect(await session.pending(), isNull);
    expect(api.records, isEmpty);
    expect(await (await p.target(key)).readAsBytes(), [7, 8]);
    final resources = record['rootSaturnFirmware'] as Map;
    expect(
      await File('${native.path}/${(resources.values.first as Map)['path']}')
          .exists(),
      false,
    );
  });

  test('Saturn companions and matched states round trip, preserve originals and reject missing or truncated working memory', () async {
    await manager.connectGbaRoot(emulator, platform: 'saturn');
    final rom = await saturnRom();
    final p = await saturnPlan(rom.path);
    final g = game(p), saves = SharedAndroidSaves(manager);
    final sizes = {
      'save/Disc.srm': 32768,
      'save/Disc.smpc': 12,
      'save/Disc.bcr': 524288,
      'save/Disc.4mb.bcr': 4194304,
      '${p.areas.last.id}/game.state': 2,
    };
    final original = await put(
      p.remotePath('save/Disc.srm'),
      List.filled(32768, 8),
    );
    final foreign = await put('${p.remoteAreas.first.remote}/Other.smpc', [9]);
    await cloud.beforePlay(g);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final staged = File(await saves.stageRootRom(g, p));
    for (final e in sizes.entries)
      await put(p.remotePath(e.key), List.filled(e.value, 7));
    await saves.capture(g, cloud, p);
    await saves.restoreOriginal(g, p);
    await cloud.afterPlay(g, 0);
    expect((await p.files()).keys.toSet(), sizes.keys.toSet());
    expect(await original.readAsBytes(), List.filled(32768, 8));
    expect(await foreign.readAsBytes(), [9]);
    expect(await staged.exists(), false);
    final next = await saturnPlan(rom.path),
        nextGame = game(next),
        retry = SharedAndroidSaves(manager);
    await retry.begin(nextGame, next, 'a' * 64, selected: rom.path);
    final cart = File('${native.path}/${next.remotePath('save/Disc.4mb.bcr')}');
    await cart.delete();
    await expectLater(retry.capture(nextGame, cloud, next), throwsStateError);
    expect(await retry.pending, true);
    await put(next.remotePath('save/Disc.4mb.bcr'), [1]);
    await expectLater(
      retry.capture(nextGame, cloud, next),
      throwsFormatException,
    );
    await put(next.remotePath('save/Disc.4mb.bcr'), List.filled(4194304, 7));
    await retry.capture(nextGame, cloud, next);
    await retry.restoreOriginal(nextGame, next);
    expect(await (await p.target('save/Disc.4mb.bcr')).length(), 4194304);
  });
  test('Saturn native mode mismatch stops before publication and inspected media cannot be replaced during staging', () async {
    await manager.connectGbaRoot(emulator, platform: 'saturn');
    final rom = await saturnRom();
    final p = await saturnPlan(rom.path), saves = SharedAndroidSaves(manager);
    await (await p.target('save/Disc.bkr')).writeAsBytes(List.filled(32768, 4));
    final before = calls.length;
    await expectLater(
      saves.begin(game(p), p, 'a' * 64, selected: rom.path),
      throwsFormatException,
    );
    expect(calls.skip(before), isNot(contains('rootReplace')));
    expect(await saves.pending, false);
    await (await p.target('save/Disc.bkr')).delete();
    final next = await saturnPlan(rom.path), g = game(next);
    await saves.begin(g, next, 'a' * 64, selected: rom.path);
    final bytes = await rom.readAsBytes();
    bytes[127] = 3;
    await rom.writeAsBytes(bytes);
    await expectLater(
      saves.stageRootRom(g, next),
      throwsA(isA<PlatformException>()),
    );
    expect(
      (await progressJson(saves.journal))['romStageSha256'],
      next.saturnDisc!.sha256,
    );
    await saves.capture(g, cloud, next);
    await saves.restoreOriginal(g, next);
  });

  test('FBNeo stages the intact multi-chip ZIP and publishes native nested saves with matched states', () async {
    await manager.connectGbaRoot(emulator, platform: 'arcade');
    final chips = await Directory('${temp.path}/chips').create();
    await File('${chips.path}/chip-a.bin').writeAsBytes([1, 2]);
    await File('${chips.path}/chip-b.bin').writeAsBytes([3, 4]);
    final rom = File('${temp.path}/simpsons2p.zip');
    await ProgressZip.write(rom, chips, ['chip-a.bin', 'chip-b.bin']);
    final p = await gameboyPlan('arcade', rom.path), g = game(p);
    expect(p.format, 'libretro-fbneo-v1');
    expect(p.rawSaveKey, isNull);
    const ordinary = 'save/fbneo/simpsons2p.fs';
    final original = await put(p.remotePath(ordinary), [8, 9]);
    final foreign = await put(
      '${p.remoteAreas.first.remote}/fbneo/another.fs',
      [7],
    );
    final saves = SharedAndroidSaves(manager);
    await cloud.beforePlay(g);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    final staged = File(await saves.stageRootRom(g, p));
    expect(await staged.readAsBytes(), await rom.readAsBytes());
    expect(staged.uri.pathSegments.last, 'simpsons2p.zip');
    final keys = [
      ordinary,
      'save/fbneo/simpsons2p.nv',
      'save/fbneo/simpsons2p.hi',
      'save/fbneo/shared.memcard',
      '${p.areas.last.id}/game.state',
    ];
    for (var i = 0; i < keys.length; i++)
      await put(p.remotePath(keys[i]), [i, i + 1]);
    await saves.capture(g, cloud, p);
    expect((await p.files()).keys.toSet(), keys.toSet());
    await saves.restoreOriginal(g, p);
    await cloud.afterPlay(g, 0);
    expect(api.records, isNotEmpty);
    expect(await original.readAsBytes(), [8, 9]);
    expect(await foreign.readAsBytes(), [7]);
    expect(await staged.exists(), false);
    expect(await saves.pending, false);
  });

  test('FBNeo recovery keeps its original state group after marker loss and refuses missing working NVRAM', () async {
    await manager.connectGbaRoot(emulator, platform: 'arcade');
    final p = await gameboyPlan('arcade', '/game/simpsons2p.zip'), g = game(p);
    final saves = SharedAndroidSaves(manager);
    const key = 'save/fbneo/simpsons2p.fs';
    await (await p.target(key)).writeAsBytes([1]);
    final state = '${p.areas.last.id}/game.state';
    await (await p.target(state)).writeAsBytes([2]);
    await saves.begin(g, p, 'a' * 64, selected: '/game/simpsons2p.zip');
    final session = AndroidGameSession(manager, cloud);
    addTearDown(session.dispose);
    expect((await session.pending())!['stateAreas'], [p.areas.last.id]);
    observation['core'] = 'f' * 64;
    final current = await gameboyPlan('arcade', '/game/simpsons2p.zip');
    final recovered = await saves.recoveryPlan(game(current), current);
    expect(recovered.areas.last.id, p.areas.last.id);
    await File('${native.path}/${p.remotePath(key)}').delete();
    await expectLater(
      saves.capture(game(current), cloud, recovered),
      throwsStateError,
    );
    expect(await saves.pending, true);
    expect(await (await p.target(key)).readAsBytes(), [1]);
    expect(api.records, isEmpty);
    await put(p.remotePath(key), [3]);
    await saves.capture(game(current), cloud, recovered);
    await saves.restoreOriginal(game(current), recovered);
    expect(await saves.pending, false);
    expect(await (await p.target(key)).readAsBytes(), [3]);
    expect(await current.files(), contains(key));
    expect((await current.files()).containsKey(state), false);
  });

  test('FBNeo refuses ambiguous names, unsupported 7z and corrupt ZIPs without extracting them', () async {
    await manager.connectGbaRoot(emulator, platform: 'arcade');
    await expectLater(
      gameboyPlan('arcade', '/game/The Simpsons.zip'),
      throwsFormatException,
    );
    await expectLater(
      gameboyPlan('arcade', '/game/simpsons2p.7z'),
      throwsUnsupportedError,
    );
    final rom = await File('${temp.path}/simpsons2p.zip')
        .writeAsBytes([1, 2, 3]);
    final p = await gameboyPlan('arcade', rom.path), g = game(p);
    final saves = SharedAndroidSaves(manager);
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    await expectLater(saves.stageRootRom(g, p), throwsFormatException);
    expect(calls, isNot(contains('rootStageRom')));
    expect(await saves.pending, true);
    await saves.capture(g, cloud, p);
    await saves.restoreOriginal(g, p);
    expect(await rom.readAsBytes(), [1, 2, 3]);
  });

  test('a ROMset replacement during inspection cannot reach native staging or discard recovery', () async {
    await manager.connectGbaRoot(emulator, platform: 'arcade');
    final chips = await Directory('${temp.path}/changing-chips').create();
    final chip = await File('${chips.path}/chip.bin').writeAsBytes([1, 2, 3]);
    final rom = File('${temp.path}/simpsons2p.zip');
    await ProgressZip.write(rom, chips, ['chip.bin']);
    await chip.writeAsBytes([4, 5, 6]);
    final replacement = File('${temp.path}/replacement.zip');
    await ProgressZip.write(replacement, chips, ['chip.bin']);
    final next = await replacement.readAsBytes();
    final p = await gameboyPlan('arcade', rom.path), g = game(p);
    final original = await put(p.remotePath('save/fbneo/simpsons2p.fs'), [
      8,
      9,
    ]);
    var replaced = false;
    final saves = SharedAndroidSaves(
      manager,
      phase: (phase) {
        if (phase == 'Verifying the FBNeo ROMset…') {
          replaced = true;
          rom.writeAsBytesSync(next, flush: true);
        }
      },
    );
    await saves.begin(g, p, 'a' * 64, selected: rom.path);
    await expectLater(saves.stageRootRom(g, p), throwsStateError);
    expect(replaced, true);
    expect(calls, isNot(contains('rootStageRom')));
    expect(await saves.pending, true);
    await saves.capture(g, cloud, p);
    await saves.restoreOriginal(g, p);
    expect(await original.readAsBytes(), [8, 9]);
    expect(await rom.readAsBytes(), next);
  });

  Future<AndroidSavePlan> lynxPlan(String rom, {bool boot = true}) async {
    final p = await gameboyPlan('lynx', rom);
    if (!boot) return p;
    final file = await File('${temp.path}/fixture-boot.img')
        .writeAsBytes(List.generate(512, (i) => i % 251));
    return AndroidSavePlan(
      p,
      p.emulator,
      p.binding,
      p.remoteAreas,
      launch: p.launch,
      lynxBootImage: _FixtureLynxBoot(file, await progressFileHash(file)),
    );
  }

  test('Lynx setup migrates every version-11 connection and adds only its own route', () async {
    final previous = [
      'gba',
      'snes',
      'gb',
      'gbc',
      'atari2600',
      'tg16',
      'genesis',
      'sms',
      'gamegear',
      'sega32',
      'n64',
      'nes',
      'jaguar',
    ];
    for (final slug in previous)
      await manager.connectGbaRoot(emulator, platform: slug);
    final file = File('${data.path}/android/emulators.json');
    final old = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    old['version'] = 11;
    await file.writeAsString(jsonEncode(old));
    await manager.load();
    expect(manager.hasCurrentRoot(emulator, 'lynx'), false);
    await manager.connectGbaRoot(emulator, platform: 'lynx');
    await manager.load();
    for (final slug in [...previous, 'lynx'])
      expect(manager.hasCurrentRoot(emulator, slug), true);
    await manager.disconnectGbaRoot(emulator, platform: 'lynx');
    await manager.load();
    for (final slug in previous)
      expect(manager.hasCurrentRoot(emulator, slug), true);
    expect(manager.hasCurrentRoot(emulator, 'lynx'), false);
    (old['retroRoots'] as Map)['lynx:$pkg'] = {
      ...manager.rootConnection(emulator, 'jaguar')!,
    };
    await file.writeAsString(jsonEncode(old));
    await manager.load();
    expect(manager.settingsKnown, false);
  });

  test('Lynx Play keeps firmware out of progress, synchronizes a state and restores native originals', () async {
    await manager.connectGbaRoot(emulator, platform: 'lynx');
    final rom = await File('${temp.path}/Cartridge.lnx').writeAsBytes([5, 6]);
    final p = await lynxPlan(rom.path), g = game(p);
    final config = androidIni(p.launch['configText']!);
    expect(
      config['system_directory'],
      '/data/user/0/$pkg/${p.launch['lynxFirmwarePath']!.replaceFirst('/lynxboot.img', '')}',
    );
    expect(config['systemfiles_in_content_dir'], 'false');
    final original = await put(p.remotePath('save/game.srm'), [8, 9]);
    final session = AndroidGameSession(manager, cloud);
    addTearDown(session.dispose);
    await session.start(
      server: serverId,
      profile: profileId,
      rom: 42,
      emulator: emulator,
      app: manager.app(emulator)!,
      files: [rom.path],
      selected: rom.path,
      core: 'mednafen_lynx',
      rootPlatform: 'lynx',
      rooted: true,
      prepare: (_, _) async => g,
    );
    expect(await original.exists(), false);
    final firmware = File('${native.path}/${p.launch['lynxFirmwarePath']}');
    expect(await firmware.length(), 512);
    final key = '${p.areas.last.id}/game.state';
    await put(p.remotePath(key), [1, 2, 3]);
    processState = 'idle';
    exitState = 'closed';
    expect(
      await session.finishIfRetroArchClosed(),
      AndroidRetroArchState.closed,
    );
    expect(await original.readAsBytes(), [8, 9]);
    expect(await firmware.exists(), false);
    expect((await p.files()).keys, [key]);
    expect(await (await p.target(key)).readAsBytes(), [1, 2, 3]);
    expect((await cloud.store(g).state())['stateKnown'], {key: isA<String>()});
    expect(api.records, isNotEmpty);
    expect(await session.pending(), isNull);
  });

  test('a lost Lynx BIOS publication reply recovers without cache, staged BIOS or general marker', () async {
    await manager.connectGbaRoot(emulator, platform: 'lynx');
    final p = await lynxPlan('/game/Cartridge.lnx'), g = game(p);
    final key = '${p.areas.last.id}/game.state';
    await (await p.target(key)).writeAsBytes([7, 8]);
    final saves = SharedAndroidSaves(manager);
    loseFirmwarePublicationReply = true;
    await expectLater(
      saves.begin(g, p, 'a' * 64, selected: '/game/Cartridge.lnx'),
      throwsA(isA<PlatformException>()),
    );
    final record = await progressJson(saves.journal);
    await p.lynxBootImage!.file.delete();
    await (await progressFile(
      saves.directory(record),
      'firmware/lynxboot.img',
    )).delete();
    final session = AndroidGameSession(manager, cloud);
    addTearDown(session.dispose);
    final pending = await session.pending();
    expect(pending!['version'], 2);
    expect(pending['stateAreas'], [p.areas.last.id]);
    final recovered = await saves.recoveryPlan(
      g,
      await lynxPlan('/game/Cartridge.lnx', boot: false),
    );
    expect(await saves.capture(g, cloud, recovered), false);
    await saves.restoreOriginal(g, recovered);
    expect(
      await File('${native.path}/${p.launch['lynxFirmwarePath']}').exists(),
      false,
    );
    expect(await (await p.target(key)).readAsBytes(), [7, 8]);
    expect(api.records, isEmpty);
    expect(await session.pending(), isNull);
  });

  test('edited Lynx BIOS retains captured progress and lost cleanup replies retry without recapture', () async {
    await manager.connectGbaRoot(emulator, platform: 'lynx');
    final p = await lynxPlan('/game/Cartridge.lnx'), g = game(p);
    final saves = SharedAndroidSaves(manager);
    await saves.begin(g, p, 'a' * 64, selected: '/game/Cartridge.lnx');
    final key = '${p.areas.last.id}/game.state';
    await put(p.remotePath(key), [2, 4, 6]);
    await saves.capture(g, cloud, p);
    final firmware = File('${native.path}/${p.launch['lynxFirmwarePath']}');
    final original = await firmware.readAsBytes();
    await firmware.writeAsBytes(List.filled(512, 9));
    await expectLater(
      saves.restoreOriginal(g, p),
      throwsA(isA<PlatformException>()),
    );
    expect(await saves.pending, true);
    expect(await saves.capture(g, cloud, p), false);
    expect(await (await p.target(key)).readAsBytes(), [2, 4, 6]);
    await firmware.writeAsBytes(original);
    loseFirmwareCleanupReply = true;
    await expectLater(
      saves.restoreOriginal(g, p),
      throwsA(isA<PlatformException>()),
    );
    expect(await firmware.exists(), false);
    expect(await saves.pending, true);
    await saves.restoreOriginal(g, p);
    expect(await saves.pending, false);
    expect(await (await p.target(key)).readAsBytes(), [2, 4, 6]);
  });

  test(
    'reviewed Jaguar states remain available with stale frontend metadata',
    () async {
      await manager.connectGbaRoot(emulator, platform: 'jaguar');
      observation['config'] = Uint8List.fromList(
        utf8.encode(
          'core_info_savestate_bypass = "false"\n'
          'rewind_enable = "false"\nrun_ahead_enabled = "false"\n'
          'video_driver = "gl"\n',
        ),
      );
      for (final (abi, digest) in [
        (
          'arm64-v8a',
          '90446691d7f5b80f9ba98e4b311e6dab5bc8afd58431fb319b4e30933f891df6',
        ),
        (
          'armeabi-v7a',
          '3a173fbfaf62401c636591ba6a7ca16ef584481094f184c02519cffb093ec6cc',
        ),
        (
          'x86',
          '2303d1bee859c14c58507c4d4ad4aff7cc39d5e2a7e537b6fce519a99bacd47a',
        ),
        (
          'x86_64',
          'a72da2e64da709839db26daf0b387373d7a74122d5a53c687bfb4dcda1da7266',
        ),
      ]) {
        observation['abi'] = abi;
        observation['core'] = digest;
        final p = await gameboyPlan('jaguar', '/game/Tempest.j64');
        final cfg = androidIni(p.launch['configText']!);
        expect(cfg['core_info_savestate_bypass'], 'true');
        expect(cfg['rewind_enable'], 'false');
        expect(cfg['run_ahead_enabled'], 'false');
        expect(cfg['video_driver'], 'gl');
        expect(
          utf8.decode(observation['config']),
          contains('bypass = "false"'),
        );
      }
      expect(calls, isNot(contains('rootReplace')));
    },
  );

  test(
    'unreviewed Jaguar and other cores retain their metadata policy',
    () async {
      observation['config'] = Uint8List.fromList(
        utf8.encode('core_info_savestate_bypass = "false"\n'),
      );
      for (final slug in ['jaguar', 'nes']) {
        await manager.connectGbaRoot(emulator, platform: slug);
        observation['core'] = slug == 'nes'
            ? '90446691d7f5b80f9ba98e4b311e6dab5bc8afd58431fb319b4e30933f891df6'
            : 'c' * 64;
        final p = await gameboyPlan(
          slug,
          '/game/Test.${slug == 'nes' ? 'nes' : 'j64'}',
        );
        expect(
          androidIni(p.launch['configText']!)['core_info_savestate_bypass'],
          'false',
        );
      }
    },
  );

  test(
    'Jaguar cartridges stage privately while disc media preserves recovery',
    () async {
      expect(androidRootRetroCore('atari-jaguar-cd'), isNull);
      await manager.connectGbaRoot(emulator, platform: 'jaguar');
      for (final extension in [
        'j64',
        'jag',
        'rom',
        'abs',
        'cof',
        'bin',
        'prg',
        'cue',
        'chd',
        'cdi',
      ]) {
        final rom = await File('${temp.path}/Cartridge.$extension')
            .writeAsBytes([1, 2, 3]);
        final p = await gameboyPlan('jaguar', rom.path), g = game(p);
        final original = await put(p.remotePath('save/game.srm'), [8, 9]);
        final saves = SharedAndroidSaves(manager);
        await saves.begin(g, p, 'a' * 64, selected: rom.path);
        if ({'cue', 'chd', 'cdi'}.contains(extension)) {
          await expectLater(saves.stageRootRom(g, p), throwsStateError);
          expect(await saves.pending, true);
        } else {
          final staged = await saves.stageRootRom(g, p);
          expect(await File(staged).readAsBytes(), [1, 2, 3]);
        }
        await saves.capture(g, cloud, p);
        await saves.restoreOriginal(g, p);
        expect(await original.readAsBytes(), [8, 9]);
        expect(await rom.readAsBytes(), [1, 2, 3]);
        expect(await saves.pending, false);
      }
    },
  );

  for (final (slug, core, extension, sram) in [
    ('atari2600', 'stella', 'a26', false),
    ('tg16', 'mednafen_pce_fast', 'pce', true),
    ('genesis', 'genesis_plus_gx', 'md', true),
    ('sms', 'genesis_plus_gx', 'sms', true),
    ('gamegear', 'genesis_plus_gx', 'gg', true),
    ('sega32', 'picodrive', '32x', true),
    ('nes', 'mesen', 'nes', true),
    ('jaguar', 'virtualjaguar', 'j64', true),
  ]) {
    test(
      '$slug keeps its native save contract, state round trip and cleanup',
      () async {
        final saveSize = slug == 'nes'
            ? 8192
            : slug == 'jaguar'
            ? 128
            : 2048;
        await manager.connectGbaRoot(emulator, platform: slug);
        final rom = await File('${temp.path}/Cartridge.$extension')
            .writeAsBytes([5, 6]);
        final p = await gameboyPlan(slug, rom.path), g = game(p);
        expect(p.format, 'libretro-$core-v1');
        final unrelated = await put(
          p
              .remotePath('save/game.srm')
              .replaceFirst('Cartridge.srm', 'Another.srm'),
          [8],
        );
        final session = AndroidGameSession(manager, cloud);
        addTearDown(session.dispose);
        await session.start(
          server: serverId,
          profile: profileId,
          rom: 42,
          emulator: emulator,
          app: manager.app(emulator)!,
          files: [rom.path],
          selected: rom.path,
          core: core,
          rooted: true,
          rootPlatform: slug,
          prepare: (_, _) async => g,
        );
        if (sram)
          await put(p.remotePath('save/game.srm'), List.filled(saveSize, 7));
        final state = '${p.areas.last.id}/game.state';
        await put(p.remotePath(state), [1, 4, 9]);
        processState = 'idle';
        exitState = 'closed';
        expect(
          await session.finishIfRetroArchClosed(),
          AndroidRetroArchState.closed,
        );
        expect(await session.pending(), isNull);
        expect(await unrelated.readAsBytes(), [8]);
        expect(
          await File('${native.path}/${p.remotePath(state)}').exists(),
          false,
        );
        expect(await (await p.target(state)).readAsBytes(), [1, 4, 9]);
        expect(api.stateRecords, hasLength(sram ? 1 : 0));
        expect((await cloud.store(g).state())['pending'], false);
        if (sram) {
          expect(
            await (await p.target('save/game.srm')).readAsBytes(),
            List.filled(saveSize, 7),
          );
          final primary = api.records.values.single;
          expect(api.contents[primary.id], List.filled(saveSize, 7));
          expect(api.readIds, contains(primary.id));
        } else {
          expect(await (await p.target('save/game.srm')).exists(), false);
        }
        final restored = ProgressLayout(
          '${temp.path}/other-device/profiles/$profileId/emulators/retroarch',
          p.format,
          p.game,
          p.areas,
        );
        final nextGame = CloudGame(
          server: serverId,
          profile: profileId,
          user: api.user,
          rom: 42,
          client: api,
          layout: restored,
        );
        final newCloud = CloudSaves(
          Directory('${temp.path}/other-device'),
          notice: (_, _) {},
        );
        await newCloud.beforePlay(nextGame);
        expect(await (await restored.target(state)).readAsBytes(), [1, 4, 9]);
        if (sram)
          expect(
            await (await restored.target('save/game.srm')).readAsBytes(),
            List.filled(saveSize, 7),
          );
      },
    );
  }

  test('GBC native sessions upload SRAM and RTC together and restore standalone bytes', () async {
    await manager.connectGbaRoot(emulator, platform: 'gbc');
    final rom = await File('${temp.path}/Pokemon Crystal.gbc')
        .writeAsBytes([5, 6]);
    final p = await gameboyPlan('gbc', rom.path), g = game(p);
    final originalSave = await put(p.remotePath('save/game.srm'), [8, 9]);
    final originalClock = await put(p.remotePath('save/game.rtc'), [7, 8]);
    final unrelated = await put(
      p
          .remotePath('save/game.rtc')
          .replaceFirst('Pokemon Crystal.rtc', 'Another game.rtc'),
      [6],
    );
    final session = AndroidGameSession(manager, cloud);
    addTearDown(session.dispose);
    await session.start(
      server: serverId,
      profile: profileId,
      rom: 42,
      emulator: emulator,
      app: manager.app(emulator)!,
      files: [rom.path],
      selected: rom.path,
      core: 'gambatte',
      rooted: true,
      rootPlatform: 'gbc',
      prepare: (_, _) async => g,
    );
    expect((await session.pending())!['rootPlatform'], 'gbc');
    final sram = List<int>.filled(32768, 2),
        rtc = List<int>.generate(48, (i) => i);
    await put(p.remotePath('save/game.srm'), sram);
    await put(p.remotePath('save/game.rtc'), rtc);
    final group = p.areas.last.id;
    await put(p.remotePath('$group/game.state'), [4, 5, 6]);
    processState = 'idle';
    exitState = 'closed';
    expect(
      await session.finishIfRetroArchClosed(),
      AndroidRetroArchState.closed,
    );
    expect(await session.pending(), isNull);
    expect(await originalSave.readAsBytes(), [8, 9]);
    expect(await originalClock.readAsBytes(), [7, 8]);
    expect(await unrelated.readAsBytes(), [6]);
    expect(await (await p.target('save/game.srm')).readAsBytes(), sram);
    expect(await (await p.target('save/game.rtc')).readAsBytes(), rtc);
    final primary = api.records.values.single;
    expect(primary.name.endsWith('.zip'), true);
    final archive = await File('${temp.path}/downloaded.zip')
        .writeAsBytes(api.contents[primary.id]!);
    final zip = await ProgressZip.read(archive);
    expect(zip.entries.map((e) => e.name).toSet(), {'game.srm', 'game.rtc'});
    expect(api.readIds, contains(primary.id));
    expect(api.stateRecords, hasLength(1));
    expect((await cloud.store(g).state())['pending'], false);
  });

  test('a missing working Game Boy clock retains recovery and cannot publish deletion', () async {
    await manager.connectGbaRoot(emulator, platform: 'gb');
    final p = await gameboyPlan('gb', '/game/Pokemon.gb'),
        g = game(p),
        saves = SharedAndroidSaves(manager);
    await (await p.target('save/game.srm')).writeAsBytes([1, 2]);
    await (await p.target('save/game.rtc')).writeAsBytes([3, 4]);
    await cloud.beforePlay(g);
    final baselineContents = {
      for (final e in api.contents.entries) e.key: List<int>.from(e.value),
    };
    await saves.begin(g, p, 'a' * 64, selected: '/game/Pokemon.gb');
    final otherPlatform = AndroidSavePlan(
      p,
      emulator,
      p.binding,
      p.remoteAreas,
      launch: {...p.launch, 'platform': 'gbc'},
    );
    await expectLater(saves.record(g, otherPlatform), throwsFormatException);
    final recovered = AndroidGameSession(manager, cloud);
    addTearDown(recovered.dispose);
    expect((await recovered.pending())!['rootPlatform'], 'gb');
    await File('${native.path}/${p.remotePath('save/game.rtc')}').delete();
    await expectLater(
      recovered.finish(emulatorClosed: true, recovery: g),
      throwsStateError,
    );
    expect(await saves.pending, true);
    expect(await (await p.target('save/game.rtc')).readAsBytes(), [3, 4]);
    expect(api.contents, baselineContents);
    // Repair from the retained working clock; missing general-marker recovery
    // then queues the captured progress for explicit review rather than upload.
    await put(p.remotePath('save/game.rtc'), [3, 4]);
    await recovered.finish(emulatorClosed: true, recovery: g);
    expect(await recovered.pending(), isNull);
    expect((await cloud.store(g).state())['pending'], true);
    expect(api.contents, baselineContents);
  });
  test(
    'root state inventories enforce transfer limits before native publication',
    () async {
      await manager.connectGbaRoot(emulator);
      final p = await plan(),
          saves = SharedAndroidSaves(manager),
          group = p.areas.last.id;
      final path = p.remotePath('$group/game.state');
      Map<String, Object> entry(int size) => {
        'bytes': size,
        'sha256': 'a' * 64,
        'metadata': attributes,
      };
      expect(
        () => saves.inventory({path: entry(16 * 1024 * 1024 + 1)}, p),
        throwsFormatException,
      );
      expect(
        () =>
            saves.inventory({p.remotePath('save/game.srm'): entry(262145)}, p),
        throwsFormatException,
      );
      expect(
        () => saves.inventory({
          for (var i = 0; i < 129; i++) '$path$i': entry(1),
        }, p),
        throwsFormatException,
      );
      expect(
        () => saves.inventory({
          for (var i = 0; i < 5; i++) '$path$i': entry(16 * 1024 * 1024),
        }, p),
        throwsFormatException,
      );
      expect(saves.inventory({path: entry(16 * 1024 * 1024)}, p), hasLength(1));
    },
  );
}
