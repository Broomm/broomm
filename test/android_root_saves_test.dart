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
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/service.dart';

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
          if (call.method == 'rootMgbaSetup')
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

  test('explicit GBA connection persists identity and redirects only managed ordinary saves', () async {
    expect(calls, isNot(contains('rootInspect')));
    await manager.connectGbaRoot(emulator);
    await manager.load();
    expect(manager.connected(profileId, emulator, platform: 'gba'), isTrue);
    expect(manager.connected(profileId, emulator, platform: 'snes'), isFalse);
    final p = await plan(), second = await plan('d' * 32);
    expect(p.areas.map((a) => a.id), ['save']);
    expect(
      p.localKey('files/Broomm/$profileId/42/saves/Minish Cap.srm'),
      'save/game.srm',
    );
    expect(
      p.localKey('files/Broomm/$profileId/42/saves/Minish Cap 2.srm'),
      isNull,
    );
    expect(
      p.remoteAreas.single.remote,
      isNot(second.remoteAreas.single.remote),
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
  });

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
    expect(await saves.pending, isFalse);
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
}
