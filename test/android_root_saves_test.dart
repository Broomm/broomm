import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/android/progress.dart';
import 'package:broomm/src/android/root_saves.dart';
import 'package:broomm/src/android/save_plan.dart';
import 'package:broomm/src/android/session.dart';
import 'package:broomm/src/android/shared_saves.dart';
import 'package:broomm/src/android/setup.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/progress/zip.dart';

import 'android_folder_sync_test.dart' show AndroidFolderFixture;
import 'android_apk_download_test.dart' show ApkClient, ApkReply;
import 'cloud_saves_test.dart' show SaveServer, profileId, serverId;

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
  var missingCore = false;
  var refuseRomCleanup = false;
  var loseConfigPublicationReply = false;
  var loseConfigCleanupReply = false;
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
      prepare: () async => game(await plan()),
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
    missingCore = false;
    refuseRomCleanup = false;
    loseConfigPublicationReply = false;
    loseConfigCleanupReply = false;
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
          if (call.method == 'rootStageRom') {
            final target = await put(
              args['path'] as String,
              await File(args['source'] as String).readAsBytes(),
            );
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
      prepare: () async => g,
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
