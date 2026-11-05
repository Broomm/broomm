import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/android/progress.dart';
import 'package:broomm/src/android/save_plan.dart';
import 'package:broomm/src/android/shared_saves.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/progress/service.dart';

import 'android_folder_sync_test.dart' show AndroidFolderFixture;
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
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('broomm-root-');
    data = await Directory('${temp.path}/data').create();
    native = await Directory('${temp.path}/native').create();
    fixture = AndroidFolderFixture(temp)..trees['root-fixture'] = native;
    api = SaveServer();
    cloud = CloudSaves(data, notice: (_, _) {});
    denied = false;
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
          if (!call.method.startsWith('root')) return fixture.call(call);
          if (denied)
            throw PlatformException(
              code: 'android-root-save',
              message: 'Denied',
            );
          if (call.method == 'rootInspect') return observation;
          final args = Map<String, dynamic>.from(call.arguments as Map)
            ..['tree'] = 'root-fixture';
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
    expect(manager.folder(emulator)!['build'], 'a' * 64);
    denied = false;
    observation['uid'] = '10119';
    await expectLater(plan(), throwsStateError);
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
    await saves.begin(g, p, 'a' * 64, selected: '/game/Minish Cap.gba');
    expect(await original.readAsBytes(), [1, 1]);
    await put(path, [2, 2, 2]);
    expect(await saves.capture(g, cloud, p), isTrue);
    expect(await working.readAsBytes(), [2, 2, 2]);
    await saves.restoreOriginal(g, p);
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
