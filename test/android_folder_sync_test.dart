import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show Endian;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/android/citra_mmj.dart';
import 'package:broomm/src/android/dolphin_root.dart';
import 'package:broomm/src/android/melon_root.dart';
import 'package:broomm/src/android/progress.dart';
import 'package:broomm/src/android/save_plan.dart';
import 'package:broomm/src/android/session.dart';
import 'package:broomm/src/android/shared_saves.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/service.dart';

import 'cloud_saves_test.dart' show SaveServer, profileId, serverId;
import 'psp_test.dart' show pspPbp;
import 'support/addon_fixtures.dart' show base3ds, baseTitle;
import 'support/android_document_paths.dart';

/// Filesystem model of the SAF boundary, with explicit failures. This exercises
/// real Dart transactions/cloud persistence, not Android provider acceptance.
class AndroidFolderFixture {
  AndroidFolderFixture(this.root);
  final Directory root;
  final trees = <String, Directory>{};
  bool revoked = false;
  int replacements = 0;
  int coreScans = 0;
  int apkScans = 0;
  int? failAt;
  String? picked;
  Directory? melonRoot, dolphinRoot;
  bool melonRunning = false;
  bool mmjReady = true;
  final melonMetadata =
      '10139 1078 660 u:object_r:media_rw_data_file:s0:c139,c256,c512,c768';
  Future<Object?> call(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    final melon = call.method.startsWith('rootMelon');
    if (melon || call.method.startsWith('rootDolphin')) {
      final prefix = melon ? 'rootMelon' : 'rootDolphin';
      if (melonRunning) throw PlatformException(code: 'writer-live');
      if (call.method == '${prefix}Inspect') {
        final package = melon
            ? androidMelonRootPackage
            : androidDolphinRootPackage;
        return {
          'package': package,
          'build': 'a' * 64,
          'version': melon
              ? androidMelonRootVersion
              : androidDolphinRootVersion,
          'signer': melon ? androidMelonRootSigner : androidDolphinRootSigner,
          'user': '0',
          'uid': '10139',
          'dataDir': '/data/user/0/$package',
          'label': 'u:object_r:app_data_file:s0:c139,c256,c512,c768',
          'externalLabel':
              'u:object_r:media_rw_data_file:s0:c139,c256,c512,c768',
          'externalGid': '1078',
          'externalDevice': '65038',
          'externalInode': '32295',
          if (melon) 'stateDirectory': 'files/savestates',
        };
      }
      final root = (melon ? melonRoot : dolphinRoot)!;
      final relative = args['path'] as String?;
      final target = relative == null ? null : File('${root.path}/$relative');
      final result = await this.call(
        MethodCall(call.method.replaceFirst(prefix, 'shared'), {
          ...args,
          'tree': melon ? 'fixture:melon' : 'fixture:dolphin',
        }),
      );
      if (call.method == '${prefix}Replace' && target != null) {
        final metadata = File('${target.path}.metadata');
        if (args['after'] != null) {
          await metadata.writeAsString(args['metadata'] as String);
        } else if (await metadata.exists()) {
          await metadata.delete();
        }
      }
      if (result is! Map<String, dynamic>) return result;
      for (final entry in result.entries) {
        final meta = File('${root.path}/${entry.key}.metadata');
        (entry.value as Map)['metadata'] = await meta.exists()
            ? await meta.readAsString()
            : melonMetadata;
      }
      return result;
    }
    switch (call.method) {
      case 'sharedPick':
        if (picked != null) revoked = false;
        return picked;
      case 'installed':
        return [
          for (final e in androidEmulators)
            for (final p in e.packages)
              {
                'package': p,
                'build': 'a' * 64,
                'version': melonRoot != null && p == androidMelonRootPackage
                    ? androidMelonRootVersion
                    : dolphinRoot != null && p == androidDolphinRootPackage
                    ? androidDolphinRootVersion
                    : p == androidMmjSharedPackage
                    ? androidMmjSharedVersion
                    : 'fixture',
              },
        ];
      case 'fingerprint':
        apkScans++;
        return 'b' * 64;
      case 'writers':
        return 99; // Explicit closure confirmation is sufficient.
      case 'ioBusy':
        return false;
      case 'launch':
        return 'game-token';
      case 'releaseGrants':
        return null;
    }
    if (revoked) throw PlatformException(code: 'revoked');
    if (args['access'] == androidMmjRootFolderAccess && !mmjReady)
      throw PlatformException(code: 'mmj-storage-unverified');
    final tree = trees[args['tree']]!;
    String clean(String p) =>
        p == '@root' ? '' : p.replaceFirst(RegExp(r'^@root/'), '');
    File file(String p) => File('${tree.path}/${clean(p)}');
    if (call.method == 'sharedCheck') return null;
    if (call.method == 'sharedStat') {
      final f = file(args['path']);
      if (!await f.exists()) return null;
      final s = await f.stat();
      return {
        'id': args['path'],
        'bytes': s.size,
        'modified': s.modified.millisecondsSinceEpoch,
      };
    }
    if (call.method == 'sharedBytes') {
      final f = file(args['path']);
      return await f.exists() ? f.readAsBytes() : null;
    }
    if (call.method == 'sharedChildren') {
      final dir = Directory('${tree.path}/${args['path']}');
      return await dir.exists()
          ? [
              await for (final e in dir.list())
                {
                  'name': e.uri.pathSegments.where((s) => s.isNotEmpty).last,
                  'directory': e is Directory,
                },
            ]
          : [];
    }
    if (call.method == 'sharedList') {
      final result = <String, dynamic>{};
      for (final area in (args['areas'] as List).cast<Map>()) {
        if ((area['exact'] as String? ?? '').endsWith('.so')) coreScans++;
        final path = area['path'] as String,
            dir = path == '@root'
                ? tree
                : Directory('${tree.path}/${clean(path)}');
        if (!await dir.exists()) continue;
        final selector = ProgressArea(
          'save',
          'unused',
          prefix: area['prefix'],
          suffix: area['suffix'],
          exact: area['exact'],
          pattern: area['pattern'],
          folderPrefix: area['folderPrefix'],
          gciId: area['gciId'],
          excluded: area['excluded'] == null
              ? {}
              : (jsonDecode(area['excluded']) as List).cast<String>().toSet(),
        );
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is! File) continue;
          final relative = androidDocumentRelativePath(dir.uri, e.uri);
          if (!selector.accepts(relative) ||
              selector.gciId != null &&
                  !await progressGciMatches(e, selector.gciId!))
            continue;
          final key = '$path/$relative';
          if (result.containsKey(key))
            throw StateError('Overlapping native boundaries');
          result[key] = {
            'bytes': await e.length(),
            'sha256': await progressFileHash(e),
          };
        }
      }
      return result;
    }
    if (call.method == 'sharedRead') {
      final from = file(args['path']), to = File(args['target']);
      if (await progressFileHash(from) != args['sha256'])
        throw StateError('External write');
      await to.create(exclusive: true);
      await from.copy(to.path);
      return null;
    }
    if (call.method == 'sharedReplace') {
      if (++replacements == failAt)
        throw PlatformException(code: 'interrupted');
      final target = file(args['path']),
          before = await target.exists()
              ? await progressFileHash(target)
              : null;
      if (before != args['before'] && before != args['after'])
        throw PlatformException(code: 'outside-write');
      if (args['after'] == null) {
        if (await target.exists()) await target.delete();
      } else {
        final source = File(args['source']);
        await target.parent.create(recursive: true);
        await source.copy(target.path);
      }
      return null;
    }
    throw UnimplementedError(call.method);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.broomm/folder-test');
  late Directory temp, data;
  late AndroidFolderFixture fixture;
  late AndroidEmulators manager;
  late CloudSaves cloud;
  final sessions = <AndroidGameSession>[], apis = <SaveServer>[];
  AndroidEmulator emulator(String id) =>
      androidEmulators.singleWhere((e) => e.id == id);
  Future<Directory> connect(String id, {bool verifyMmj = false}) async {
    final e = emulator(id), app = manager.app(e)!;
    final uri = id == 'retroarch'
        ? 'content://${app.package}.documents/tree/${Uri.encodeComponent('/data/user/0/${app.package}')}'
        : 'content://com.android.externalstorage.documents/tree/${Uri.encodeComponent('primary:${id == 'citra-mmj' ? 'citra-emu' : 'Broomm/$id'}')}';
    final root = await Directory('${temp.path}/external/$id')
        .create(recursive: true);
    fixture.trees[uri] = root;
    await manager.confirmSharedStorage(e, uri, verifyMmj: verifyMmj);
    return root;
  }

  Future<File> put(Directory root, String path, List<int> bytes) async {
    final f = File('${root.path}/$path');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    return f;
  }

  Future<CloudGame> game(String profile, SaveServer api, File rom) async =>
      CloudGame(
        server: serverId,
        profile: profile,
        user: api.user,
        rom: 42,
        client: api,
        layout: await androidProgressLayout(
          manager,
          profile,
          emulator('melonds'),
          playablePlatforms.firstWhere((p) => p.slug == 'nds'),
          rom.path,
          contentId: '42',
        ),
      );
  Future<AndroidGameSession> start(CloudGame g, File rom) async {
    final s = AndroidGameSession(manager, cloud);
    sessions.add(s);
    await s.start(
      server: serverId,
      profile: g.profile,
      rom: 42,
      emulator: emulator('melonds'),
      app: manager.app(emulator('melonds'))!,
      files: [rom.path],
      selected: rom.path,
      game: g,
    );
    return s;
  }

  SaveServer api([int user = 3]) {
    final a = SaveServer()..user = user;
    apis.add(a);
    return a;
  }

  Future<File> ds() =>
      put(temp, 'Ranger.nds', Uint8List(32)..setAll(12, ascii.encode('APRE')));
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('broomm-folder-');
    data = await Directory('${temp.path}/data').create();
    fixture = AndroidFolderFixture(temp);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, fixture.call);
    manager = AndroidEmulators(data, channel: channel, enabled: true);
    await manager.load();
    cloud = CloudSaves(data, notice: (_, _) {});
  });
  tearDown(() async {
    for (final s in sessions) s.dispose();
    sessions.clear();
    for (final a in apis) a.close();
    apis.clear();
    manager.dispose();
    await Future<void>.delayed(Duration.zero);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temp.delete(recursive: true);
  });
  test('rooted DS keeps native files while live, then syncs each profile and restores originals', () async {
    final native = await Directory('${temp.path}/native').create();
    fixture.melonRoot = native;
    fixture.trees['fixture:melon'] = native;
    final app = emulator('melonds');
    await manager.load();
    await manager.connectMelonRoot(app);
    await manager.load();
    expect(manager.connected(profileId, app, platform: 'nds'), isTrue);
    final rom = await ds(), first = api(), second = api(9);
    final standalone = await put(native, 'files/saves/Ranger.sav', [7, 7]);
    final unrelated = await put(native, 'files/saves/Other.sav', [99]);
    final standaloneSlot = await put(native, 'files/savestates/Ranger.ml1', [
      8,
    ]);
    final a = await game(profileId, first, rom), session = await start(a, rom);
    expect(await standalone.exists(), isFalse);
    expect(await standaloneSlot.exists(), isFalse);
    await standalone.writeAsBytes(List.filled(512, 1));
    await standaloneSlot.writeAsBytes([4, 5]);
    fixture.melonRunning = true;
    await expectLater(
      session.finish(emulatorClosed: true, recovery: a),
      throwsA(isA<PlatformException>()),
    );
    expect(await standaloneSlot.readAsBytes(), [4, 5]);
    expect(first.records, isEmpty);
    expect(await session.pending(), isNotNull);
    fixture.melonRunning = false;
    await session.finish(emulatorClosed: true, recovery: a);
    expect(first.contents[first.records.keys.single], List.filled(512, 1));
    expect(first.stateRecords, isNotEmpty);
    expect(await standalone.readAsBytes(), [7, 7]);
    expect(await standaloneSlot.readAsBytes(), [8]);
    final b = await game('2' * 32, second, rom), other = await start(b, rom);
    expect(await standalone.exists(), isFalse);
    expect(await standaloneSlot.exists(), isFalse);
    await standalone.writeAsBytes(List.filled(512, 2));
    await other.finish(emulatorClosed: true, recovery: b);
    expect(second.contents[second.records.keys.single], List.filled(512, 2));
    expect(await unrelated.readAsBytes(), [99]);
    expect(await standalone.readAsBytes(), [7, 7]);
    expect(await standaloneSlot.readAsBytes(), [8]);
  });
  test('rooted DS inventories a full set of native states but bounds each slot', () async {
    fixture.melonRoot = temp;
    final emulator = androidEmulators.singleWhere((e) => e.id == 'melonds');
    await manager.load();
    await manager.connectMelonRoot(emulator);
    final plan =
        (await game(profileId, api(), await ds())).layout as AndroidSavePlan;
    final saves = SharedAndroidSaves(manager);
    Map<String, Object> state(int bytes) => {
      'bytes': bytes,
      'sha256': '0' * 64,
      'metadata':
          '${plan.binding['uid']} ${plan.binding['externalGid']} 660 ${plan.binding['externalLabel']}',
    };
    final files = {
      for (var slot = 0; slot <= 8; slot++)
        'files/savestates/Ranger.ml$slot': state(19498151),
    };
    expect(saves.inventory(files, plan), hasLength(9));
    files['files/savestates/Ranger.ml1'] = state(32 * 1024 * 1024 + 1);
    expect(() => saves.inventory(files, plan), throwsFormatException);
  });
  test(
    'a changed melonDS installation cannot use the stored root binding',
    () async {
      fixture.melonRoot = temp;
      final emulator = androidEmulators.singleWhere((e) => e.id == 'melonds');
      await manager.load();
      await manager.connectMelonRoot(emulator);
      manager.installed[androidMelonRootPackage] = const AndroidApp(
        androidMelonRootPackage,
        androidMelonRootVersion,
        'changed',
      );
      expect(manager.connected(profileId, emulator, platform: 'nds'), isFalse);
      await expectLater(game(profileId, api(), await ds()), throwsStateError);
    },
  );
  test(
    'rooted Dolphin preserves standalone GCI files and isolates title data',
    () async {
      final native = await Directory('${temp.path}/dolphin-native').create();
      fixture.dolphinRoot = native;
      fixture.trees['fixture:dolphin'] = native;
      final app = emulator('dolphin');
      await manager.load();
      await manager.connectDolphinRoot(app, 'ngc');
      await manager.load();
      expect(manager.connected(profileId, app, platform: 'ngc'), isTrue);
      expect(manager.connected(profileId, app, platform: 'wii'), isTrue);
      Future<AndroidSavePlan> plan(
        String platform,
        String id,
        int offset,
        int magic,
      ) async {
        final header = Uint8List(128)..setAll(0, ascii.encode(id));
        ByteData.sublistView(header).setUint32(offset, magic);
        final disc = await put(temp, '$id.iso', header);
        return await androidProgressLayout(
          manager,
          profileId,
          app,
          playablePlatforms.firstWhere((p) => p.slug == platform),
          disc.path,
          contentId: '42',
        ) as AndroidSavePlan;
      }

      final gc = await plan('ngc', 'GAFE01', 0x1c, 0xc2339f3d);
      final wii = await plan('wii', 'RZDE01', 0x18, 0x5d1c9ea3);
      expect(gc.method('List'), 'rootDolphinList');
      expect(gc.localKey('files/StateSaves/GAFE01.s00'), isNotNull);
      expect(gc.localKey('files/StateSaves/GAFE01.s99'), isNull);
      expect(gc.localKey('files/StateSaves/RZDE01.s00'), isNull);
      expect(
        wii.localKey('files/Wii/title/00010000/525a4445/data/save.dat'),
        'save/save.dat',
      );
      expect(
        wii.localKey('files/Wii/title/00010000/525a444a/data/save.dat'),
        isNull,
      );
      expect(
        wii.localKey('files/Wii/title/00010000/525a4445/content/title.tmd'),
        isNull,
      );
      final saves = SharedAndroidSaves(manager);
      final server = api();
      final cloudGame = CloudGame(
        server: serverId,
        profile: profileId,
        user: server.user,
        rom: 42,
        client: server,
        layout: gc,
      );
      Uint8List gci(String id, int fill) =>
          Uint8List.fromList(List.filled(64 + 8192, fill))
            ..setAll(0, ascii.encode(id));
      const folder = 'files/GC/USA/Card A';
      final standalone = await put(
        native,
        '$folder/Standalone.gci',
        gci('GAFE01', 1),
      );
      final unrelated = await put(
        native,
        '$folder/Other.gci',
        gci('GZLE01', 2),
      );
      final undo = await put(
        native,
        'files/StateSaves/lastState.sav',
        gci('GZLE01', 5),
      );
      final deleted = await put(
        native,
        '$folder/Standalone.gci.deleted',
        gci('GAFE01', 6),
      );
      final selected = gc.launch['romPath']!;
      await saves.begin(
        cloudGame,
        gc,
        manager.app(app)!.build,
        selected: selected,
      );
      expect(await standalone.exists(), isFalse);
      expect(await undo.exists(), isFalse);
      expect(await deleted.exists(), isFalse);
      final written = await put(
        native,
        '$folder/Session.gci',
        gci('GAFE01', 3),
      );
      await put(native, 'files/StateSaves/GAFE01.s00', gci('GAFE01', 4));
      await undo.writeAsBytes(gci('GAFE01', 7));
      expect(await saves.capture(cloudGame, cloud, gc), isTrue);
      await saves.restoreOriginal(cloudGame, gc);
      expect(await standalone.readAsBytes(), gci('GAFE01', 1));
      expect(await unrelated.readAsBytes(), gci('GZLE01', 2));
      expect(await undo.readAsBytes(), gci('GZLE01', 5));
      expect(await deleted.readAsBytes(), gci('GAFE01', 6));
      expect(await written.exists(), isFalse);
      expect(await saves.pending, isFalse);
      expect((await gc.files()).keys, contains('cardA/Session.gci'));
      expect(
        (await gc.files()).keys,
        everyElement(isNot(startsWith('dolphin-undo'))),
      );
    },
  );

  test('stable ARMSX2 is preferred; nightly remains discoverable with its own persistent folder', () async {
    final e = emulator('armsx2');
    expect(
      manager.installed.keys,
      containsAll(['com.armsx2', 'com.armsx2.nightly']),
    );
    expect(manager.app(e)!.package, 'com.armsx2');
    await connect('armsx2');
    manager.installed.remove('com.armsx2');
    expect(manager.app(e)!.package, 'com.armsx2.nightly');
    expect(manager.folder(e), isNull);
    await connect('armsx2');
    await manager.load();
    expect(manager.app(e)!.package, 'com.armsx2');
    expect(manager.folder(e), isNotNull);
  });
  test('an unchanged APK reinstall refreshes inspection without splitting compatible Android states', () async {
    await connect('melonds');
    final rom = await ds(),
        remote = api(),
        first = await game(profileId, remote, rom);
    final group = first.layout.areas.singleWhere(
      (a) => a.id.startsWith('states-'),
    );
    final inspected = fixture.apkScans, app = manager.app(emulator('melonds'))!;
    manager.installed[app.package] = AndroidApp(
      app.package,
      app.version,
      'c' * 64,
    );
    final reinstalled = await game(profileId, remote, rom);
    expect(fixture.apkScans, inspected + 1);
    expect(
      reinstalled.layout.areas
          .singleWhere((a) => a.id.startsWith('states-'))
          .path,
      group.path,
    );
  });
  test('session config replaces save-path assignments without duplicate-key precedence or unrelated preference loss', () {
    final cfg = androidRetroConfig(
      'savefile_directory = "old"\nsavefile_directory = "older"\ninput_joypad_driver = "android"\n',
      {'savefile_directory': '/owned/saves'},
    );
    expect(
      RegExp(r'^savefile_directory\s*=', multiLine: true).allMatches(cfg),
      hasLength(1),
    );
    expect(androidIni(cfg)['savefile_directory'], '/owned/saves');
    expect(androidIni(cfg)['input_joypad_driver'], 'android');
  });
  test('one folder serves two profiles; DS native .sav and Android states upload and standalone data is restored', () async {
    final external = await connect('melonds'),
        rom = await ds(),
        first = api(),
        second = api(9);
    await put(external, 'Ranger.sav', [7, 7]);
    await put(external, 'Another.sav', [99]);
    final a = await game(profileId, first, rom), s = await start(a, rom);
    expect(await File('${external.path}/Ranger.sav').exists(), false);
    await put(external, 'Ranger.sav', List.filled(512, 1));
    await put(external, 'Ranger.ml1', [5, 6]);
    await s.finish(emulatorClosed: true, recovery: a);
    expect(first.records.values.single.slot, 'BROOMM');
    expect(first.records.values.single.name, endsWith('.sav'));
    expect(first.contents[first.records.keys.single], List.filled(512, 1));
    expect(first.stateRecords, isNotEmpty);
    expect(await File('${external.path}/Ranger.sav').readAsBytes(), [7, 7]);
    expect(await File('${external.path}/Another.sav').readAsBytes(), [99]);
    final b = await game('c123456789abcdef0123456789abcdef', second, rom),
        t = await start(b, rom);
    expect(await File('${external.path}/Ranger.sav').exists(), false);
    await put(external, 'Ranger.sav', List.filled(512, 8));
    await t.finish(emulatorClosed: true, recovery: b);
    expect(second.contents[second.records.keys.single], List.filled(512, 8));
    expect(
      await (await a.layout.target('save/game.sav')).readAsBytes(),
      List.filled(512, 1),
    );
  });
  test('offline capture and revoked access retain progress; user can keep native folder when recovery is blocked', () async {
    final external = await connect('melonds'),
        rom = await ds(),
        remote = api(),
        g = await game(profileId, remote, rom);
    final s = await start(g, rom);
    await put(external, 'Ranger.sav', List.filled(512, 3));
    fixture.revoked = true;
    await expectLater(
      s.finish(emulatorClosed: true, recovery: g),
      throwsA(isA<PlatformException>()),
    );
    expect(await s.pending(), isNotNull);
    expect(remote.records, isEmpty);
    fixture.picked = manager.folder(emulator('melonds'))!['tree'];
    await s.reconnectFolder();
    remote.offline = true;
    await s.finish(emulatorClosed: true, recovery: g);
    expect(await s.pending(), isNull);
    expect(
      await (await g.layout.target('save/game.sav')).readAsBytes(),
      List.filled(512, 3),
    );
    remote.offline = false;
    await cloud.sync(g);
    expect(remote.records, isNotEmpty);
    final t = await start(g, rom);
    fixture.revoked = true;
    await t.keepMmjFolder(emulatorClosed: true);
    expect(await t.pending(), isNull);
  });
  test('interrupted external replacement recovers without adopting standalone saves', () async {
    final external = await connect('melonds'),
        rom = await ds(),
        remote = api(),
        g = await game(profileId, remote, rom);
    await put(external, 'Ranger.sav', [42]);
    await (await g.layout.target('save/game.sav'))
        .writeAsBytes(List.filled(512, 1));
    fixture.failAt = 1;
    final s = AndroidGameSession(manager, cloud);
    sessions.add(s);
    await expectLater(
      s.start(
        server: serverId,
        profile: profileId,
        rom: 42,
        emulator: emulator('melonds'),
        app: manager.app(emulator('melonds'))!,
        files: [rom.path],
        selected: rom.path,
        game: g,
      ),
      throwsA(isA<PlatformException>()),
    );
    fixture.failAt = null;
    await s.finish(emulatorClosed: true, recovery: g);
    expect(await File('${external.path}/Ranger.sav').readAsBytes(), [42]);
    expect(remote.contents[remote.records.keys.single], List.filled(512, 1));
  });
  test('verified MMJ refuses uncertain storage and preserves legacy states without publishing them', () async {
    const id = 'citra-mmj';
    fixture.mmjReady = false;
    await expectLater(
      connect(id, verifyMmj: true),
      throwsA(isA<PlatformException>()),
    );
    expect(manager.folder(emulator(id)), isNull);
    fixture.mmjReady = true;
    final external = await connect(id, verifyMmj: true);
    final bytes = Uint8List(0x500)..setAll(0, base3ds());
    ByteData.sublistView(bytes)
        .setUint64(0x400, int.parse(baseTitle, radix: 16), Endian.little);
    final rom = await put(temp, 'game.3ds', bytes);
    final plan = await androidProgressLayout(
      manager,
      profileId,
      emulator(id),
      playablePlatforms.firstWhere((p) => p.slug == '3ds'),
      rom.path,
      contentId: '42',
    ) as AndroidSavePlan;
    expect(plan.areas.where((a) => a.id.startsWith('states-')), isEmpty);
    final statePath = 'states/${baseTitle.toUpperCase()}.01.cst';
    final standalone = await put(external, statePath, [1, 3, 5]);
    final remote = api();
    final game = CloudGame(
      server: serverId,
      profile: profileId,
      user: remote.user,
      rom: 42,
      client: remote,
      layout: plan,
    );
    final session = AndroidGameSession(manager, cloud);
    sessions.add(session);
    await session.start(
      server: serverId,
      profile: profileId,
      rom: 42,
      emulator: emulator(id),
      app: manager.app(emulator(id))!,
      files: [rom.path],
      selected: rom.path,
      game: game,
    );
    expect(await standalone.exists(), isFalse);
    await put(external, statePath, [2, 4, 6]);
    await session.finish(emulatorClosed: true);
    expect(await standalone.readAsBytes(), [1, 3, 5]);
    expect(remote.records, isEmpty);
  });

  test('PSP, 3DS, GameCube, PS1, PS2 and RetroArch resolve constrained native save boundaries', () async {
    final psp = await put(temp, 'game.pbp', pspPbp());
    await connect('ppsspp');
    final p = await androidProgressLayout(
      manager,
      profileId,
      emulator('ppsspp'),
      playablePlatforms.firstWhere((p) => p.slug == 'psp'),
      psp.path,
      contentId: '42',
    );
    expect(p.format, 'ppsspp-savedata-v1');
    final threeDsBytes = Uint8List(0x500)..setAll(0, base3ds());
    ByteData.sublistView(threeDsBytes)
        .setUint64(0x400, int.parse(baseTitle, radix: 16), Endian.little);
    final threeDs = await put(temp, 'game.3ds', threeDsBytes);
    for (final id in ['azahar', 'citra-mmj']) {
      await connect(id);
      final plan = await androidProgressLayout(
        manager,
        profileId,
        emulator(id),
        playablePlatforms.firstWhere((p) => p.slug == '3ds'),
        threeDs.path,
        contentId: '42',
      );
      expect(plan.format, 'azahar-data-v1');
      expect(plan.game, baseTitle);
      expect(plan.areas.where((a) => a.id.startsWith('states-')), hasLength(1));
    }
    final cube = await connect('dolphin');
    await put(
      cube,
      'Config/Dolphin.ini',
      utf8.encode('[Core]\nSlotA=8\nSlotB=8\n'),
    );
    final h = Uint8List(128)..setAll(0, ascii.encode('GAFE01'));
    ByteData.sublistView(h).setUint32(0x1c, 0xc2339f3d);
    final disc = await put(temp, 'game.iso', h);
    final gc = await androidProgressLayout(
      manager,
      profileId,
      emulator('dolphin'),
      playablePlatforms.firstWhere((p) => p.slug == 'ngc'),
      disc.path,
      contentId: '42',
    );
    expect(gc.format, 'dolphin-gci-v1');
    expect(gc.areas.first.gciId, 'GAFE01');
    await connect('duckstation');
    final ps1 = await androidProgressLayout(
      manager,
      profileId,
      emulator('duckstation'),
      playablePlatforms.firstWhere((p) => p.slug == 'psx'),
      disc.path,
      contentId: '42',
    );
    expect(
      (ps1 as AndroidSavePlan).remotePath('save/card1.mcd'),
      'memcards/shared_card_1.mcd',
    );
    final arms = await connect('armsx2');
    await put(
      arms,
      'PCSX2-Android.ini',
      utf8.encode(
        '[MemoryCards]\nSlot1_Filename=Mcd001.ps2\nSlot2_Filename=Mcd002.ps2\n',
      ),
    );
    final ps2 = await androidProgressLayout(
      manager,
      profileId,
      emulator('armsx2'),
      playablePlatforms.firstWhere((p) => p.slug == 'ps2'),
      disc.path,
      contentId: '42',
    );
    expect(
      (ps2 as AndroidSavePlan).remotePath('save/slot1.ps2'),
      'memcards/Mcd001.ps2',
    );
    await put(
      arms,
      'PCSX2-Android.ini',
      utf8.encode('[Folders]\nMemoryCards=/unrelated/cards\n'),
    );
    await expectLater(
      androidProgressLayout(
        manager,
        profileId,
        emulator('armsx2'),
        playablePlatforms.firstWhere((p) => p.slug == 'ps2'),
        disc.path,
        contentId: '42',
      ),
      throwsStateError,
    );
    final ra = await connect('retroarch');
    await put(
      ra,
      'files/retroarch.cfg',
      utf8.encode('input_joypad_driver = "android"\n'),
    );
    await put(ra, 'cores/snes9x_libretro_android.so', [1]);
    final retro = await androidProgressLayout(
      manager,
      profileId,
      emulator('retroarch'),
      playablePlatforms.firstWhere((p) => p.slug == 'snes'),
      disc.path,
      contentId: '42',
    );
    expect(
      (retro as AndroidSavePlan).launch['configText'],
      contains('input_joypad_driver = "android"'),
    );
    expect(retro.launch['configNative'], startsWith('/data/user/0/'));
    final oldState = retro.areas.singleWhere((a) => a.id.startsWith('states-'));
    final retainedState = await retro.target('${oldState.id}/game1');
    await retainedState.writeAsBytes([6]);
    final coreScans = fixture.coreScans;
    await manager.load();
    await androidProgressLayout(
      manager,
      profileId,
      emulator('retroarch'),
      playablePlatforms.firstWhere((p) => p.slug == 'snes'),
      disc.path,
      contentId: '42',
    );
    expect(fixture.coreScans, coreScans);
    await File('${ra.path}/cores/snes9x_libretro_android.so')
        .writeAsBytes([1, 2]);
    final updatedCore = await androidProgressLayout(
      manager,
      profileId,
      emulator('retroarch'),
      playablePlatforms.firstWhere((p) => p.slug == 'snes'),
      disc.path,
      contentId: '42',
    );
    expect(fixture.coreScans, coreScans + 1);
    expect(
      updatedCore.areas.singleWhere((a) => a.id.startsWith('states-')).path,
      isNot(oldState.path),
    );
    expect(
      (await updatedCore.files()).keys.where((k) => k.startsWith('states-')),
      isEmpty,
    );
    expect(await retainedState.readAsBytes(), [6]);
  });

  test('Eden follows native per-title legacy/future placement without capturing another console account or NAND contents', () async {
    final external = await connect('eden'), profiles = Uint8List(0x650);
    // One UUID half has the high bit set. Its native folder must remain 32
    // hexadecimal digits, matching desktop Eden and not signed Dart integers.
    const raw = 'cde3270c6ca84eec4b59b7456231292f';
    final uuid = [
      for (var i = 0; i < raw.length; i += 2)
        int.parse(raw.substring(i, i + 2), radix: 16),
    ];
    profiles.setAll(0x10, uuid);
    profiles.setAll(0x20, uuid);
    await put(
      external,
      'nand/system/save/8000000000000010/su/avators/profiles.dat',
      profiles,
    );
    await put(
      external,
      'keys/prod.keys',
      utf8.encode('header_key = ${'0' * 64}\n'),
    );
    final name = ascii.encode('${'1' * 32}.nca\u0000'),
        offset = 40 + name.length;
    final bytes = Uint8List(offset + 0xc00), d = ByteData.sublistView(bytes);
    bytes.setAll(0, ascii.encode('PFS0'));
    d.setUint32(4, 1, Endian.little);
    d.setUint32(8, name.length, Endian.little);
    d.setUint64(24, 0xc00, Endian.little);
    bytes.setAll(40, name);
    bytes.setAll(offset + 0x200, ascii.encode('NCA3'));
    d.setUint64(offset + 0x208, 0xc00, Endian.little);
    d.setUint64(
      offset + 0x210,
      int.parse('0100000000010000', radix: 16),
      Endian.little,
    );
    final rom = await put(temp, 'switch.nsp', bytes);
    // An account directory for another title must not select the new layout.
    await Directory(
      '${external.path}/nand/user/save/account/$raw/0100000000020000/0',
    ).create(recursive: true);
    Future<AndroidSavePlan> plan() async => (await androidProgressLayout(
      manager,
      profileId,
      emulator('eden'),
      playablePlatforms.firstWhere((p) => p.emulatorId == 'eden'),
      rom.path,
      contentId: '42',
    )) as AndroidSavePlan;
    final legacy = await plan();
    expect(legacy.format, 'ryubing-directory-v1');
    expect(legacy.areas, hasLength(2));
    expect(
      legacy.remotePath('save/main'),
      'nand/user/save/0000000000000000/2F29316245B7594BEC4EA86C0C27E3CD/0100000000010000/main',
    );
    final future = 'nand/user/save/account/$raw/0100000000010000/0';
    await Directory('${external.path}/$future').create(recursive: true);
    final updated = await plan();
    expect(updated.remotePath('save/main'), '$future/main');
    profiles[0x20] = 2;
    await put(
      external,
      'nand/system/save/8000000000000010/su/avators/profiles.dat',
      profiles,
    );
    await expectLater(plan(), throwsFormatException);
  });
}
