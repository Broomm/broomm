import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/android/progress.dart';
import 'package:broomm/src/android/psp_root.dart';
import 'package:broomm/src/android/psp_root_store.dart';
import 'package:broomm/src/android/session.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/files.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloud_saves_test.dart' show SaveServer, profileId, serverId;
import 'psp_test.dart' show pspPbp;

/// Filesystem model at the native method boundary. This verifies real Dart
/// journals, cloud snapshots and retries; native acceptance is recorded apart.
class PspRootFixture {
  PspRootFixture(this.root);
  final Directory root;
  final emulator = androidEmulators.singleWhere((e) => e.id == 'ppsspp');
  final calls = <String>[];
  final launches = <Map<dynamic, dynamic>>[];
  final names = <String, String>{};
  final modes = <String, String>{};
  final native = '/storage/emulated/0/Android/data/org.ppsspp.ppsspp/files';
  String get appLabel => 'u:object_r:app_data_file:s0:c135,c256,c512,c768';
  String get label =>
      appLabel.replaceFirst('app_data_file:', 'media_rw_data_file:');
  String state = 'idle', exit = 'closed', selected = 'native';
  bool denied = false,
      loseReplace = false,
      loseSelect = false,
      loseRead = false;
  bool loseProfileRead = false;
  int inode = 500, clock = 100;
  int pageLimit = 8192;
  bool corruptPage = false;
  final inodes = <String, int>{};
  Map<String, String> get binding => {
    'access': 'root-psp-v1',
    'package': 'org.ppsspp.ppsspp',
    'user': '0',
    'uid': '10135',
    'dataDir': '/data/user/0/org.ppsspp.ppsspp',
    'build': 'a' * 64,
    'signer': 'b' * 64,
    'label': appLabel,
    'externalLabel': label,
    'externalGid': '1078',
    'externalMode': '2770',
    'externalDevice': '55',
    'externalInode': '99',
    'apk': androidPspApk,
    'abi': 'arm64-v8a',
  };
  String key(Map args) =>
      '${args['server']}/${args['profile']}/${args['ownerNonce']}';
  Directory memory(Map args) => Directory('${root.path}/${key(args)}');
  String fileIdentity(String path) => path.replaceAll('\\', '/');
  String mode(File file) => modes[fileIdentity(file.path)] ?? '660';
  Future<File> put(
    Map args,
    String path,
    List<int> bytes, {
    String mode = '660',
  }) async {
    final file = File('${memory(args).path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    modes[fileIdentity(file.path)] = mode;
    inodes[fileIdentity(file.path)] = ++inode;
    return file;
  }

  Future<Map<String, dynamic>> entry(File file) async {
    final n = await file.length(),
        ino = inodes.putIfAbsent(fileIdentity(file.path), () => ++inode);
    return {
      'bytes': n,
      'sha256': await progressFileHash(file),
      'metadata':
          '10135 1078 ${mode(file)} $label 55 $ino $n 123.000000001 124.000000001 1',
    };
  }

  Future<Map<String, dynamic>> files(Map args, {required bool full}) async {
    final out = <String, dynamic>{}, base = memory(args);
    final excluded = (jsonDecode(args['excluded'] as String? ?? '[]') as List)
        .toSet();
    await for (final file in base.list(recursive: true, followLinks: false)) {
      if (file is! File) continue;
      // The mocked native boundary always returns Android '/' paths, even
      // when its backing filesystem is the Windows CI runner.
      final p = fileIdentity(file.path.substring(base.path.length + 1));
      if (!full &&
          (!p.startsWith('PSP/SAVEDATA/ULUS10340') &&
                  !p.startsWith('PSP/PPSSPP_STATE/ULUS10340_1.02_') ||
              excluded.contains(p)))
        continue;
      out[p] = await entry(file);
    }
    return out;
  }

  Future<Object?> call(MethodCall call) async {
    calls.add(call.method);
    final a = (call.arguments as Map?) ?? {};
    if (call.method == 'rootEmulatorStop') {
      expect(a['package'], binding['package']);
      expect(a['build'], binding['build']);
      state = 'idle';
      return null;
    }
    if (call.method == 'installed')
      return [
        {
          'package': binding['package'],
          'build': binding['build'],
          'version': '1.20.4',
        },
      ];
    if (call.method == 'ioBusy') return false;
    if (call.method == 'fingerprint') return 'c' * 64;
    if (call.method == 'releaseGrants') return null;
    if (call.method == 'open' || call.method == 'launch') {
      if (call.method == 'launch') launches.add(Map.of(a));
      state = 'running';
      return call.method == 'launch' ? 'token' : null;
    }
    if (denied) throw PlatformException(code: 'root-denied');
    if (call.method == 'rootPspInspect')
      return {
        ...binding,
        'version': '1.20.4',
        'config': Uint8List.fromList(
          utf8.encode(
            '[SystemParam]\nMacAddress = 00:11:22:33:44:55\n[Graphics]\nRenderingMode = 0\n',
          ),
        ),
        'controls': Uint8List.fromList(
          utf8.encode('[ControlMapping]\nPause = 0-4\n'),
        ),
      };
    if (call.method == 'rootPspLifecycle')
      return {
        'state': a['process'] != null || a['launchWall'] != null
            ? (state == 'running' ? 'running' : exit)
            : state,
        'elapsed': ++clock,
        'wall': 100000 + clock,
        if (a['process'] != null) ...a['process'] as Map,
        if (a['process'] == null && a['launchWall'] != null) ...{
          'pid': 77,
          'startTicks': 99,
          'launchElapsed': a['launchElapsed'],
          'launchWall': a['launchWall'],
        },
      };
    if (state != 'idle') throw PlatformException(code: 'writer-not-closed');
    if (call.method == 'rootPspProfile') {
      if (!await memory(a).exists()) {
        await put(
          a,
          'PSP/SYSTEM/ppsspp.ini',
          (a['config'] as List).cast<int>(),
        );
        await put(
          a,
          'PSP/SYSTEM/controls.ini',
          (a['controls'] as List).cast<int>(),
        );
      }
      names[key(a)] = androidPspMemoryStick(
        binding,
        a['server'],
        a['profile'],
        a['ownerNonce'],
      );
      return {'status': 'ready', 'memoryStick': names[key(a)]};
    }
    if (call.method == 'rootPspSelection')
      return {
        'selection': selected == 'native'
            ? 'native'
            : selected == key(a)
            ? 'profile'
            : 'other',
        'sha256': pspTextDigest(
          selected == 'native' ? native : names[selected]!,
        ),
      };
    if (call.method == 'rootPspSelect') {
      final wanted = a['selection'] == 'native' ? 'native' : key(a);
      final current = pspTextDigest(
        selected == 'native' ? native : names[selected]!,
      );
      if (selected != wanted && current != a['before'])
        throw PlatformException(code: 'pointer-changed');
      selected = wanted;
      if (loseSelect) {
        loseSelect = false;
        throw PlatformException(code: 'lost-selection-reply');
      }
      return {
        'sha256': pspTextDigest(
          selected == 'native' ? native : names[selected]!,
        ),
      };
    }
    if (call.method == 'rootPspList' || call.method == 'rootPspProfileList') {
      final all = await files(a, full: call.method == 'rootPspProfileList'),
          sorted = all.keys.toList()..sort();
      final remaining = sorted
          .where(
            (p) =>
                a['cursor'] == null || p.compareTo(a['cursor'] as String) > 0,
          )
          .toList();
      final selected = corruptPage && a['cursor'] != null
          ? [sorted.first]
          : remaining.take(pageLimit).toList();
      return {
        'files': {for (final p in selected) p: all[p]},
        'next': remaining.length > pageLimit ? selected.last : null,
      };
    }
    if (call.method == 'rootPspRead' || call.method == 'rootPspProfileRead') {
      final source = File('${memory(a).path}/${a['path']}'),
          target = File(a['target'] as String);
      final e = await entry(source);
      if (e['sha256'] != a['sha256'] || e['metadata'] != a['metadata'])
        throw PlatformException(code: 'changed-capture');
      await target.create(exclusive: true);
      if (loseRead || loseProfileRead && call.method == 'rootPspProfileRead') {
        loseRead = false;
        loseProfileRead = false;
        await target.writeAsBytes([1]);
        throw PlatformException(code: 'lost-read-reply');
      }
      await source.copy(target.path);
      return null;
    }
    if (call.method == 'rootPspReplace' ||
        call.method == 'rootPspProfileReplace') {
      final target = File('${memory(a).path}/${a['path']}');
      final observed = await target.exists() ? await entry(target) : null;
      if (observed?['sha256'] == a['after']) return observed ?? {};
      if (observed?['sha256'] != a['before'] ||
          observed != null && observed['metadata'] != a['metadata'])
        throw PlatformException(code: 'native-changed');
      if (a['after'] == null)
        await target.delete();
      else {
        final source = File(a['source'] as String);
        if (await progressFileHash(source) != a['after'])
          throw PlatformException(code: 'source-changed');
        await put(
          a,
          a['path'],
          await source.readAsBytes(),
          mode: a['mode'] as String? ?? mode(target),
        );
      }
      if (loseReplace) {
        loseReplace = false;
        throw PlatformException(code: 'lost-replacement-reply');
      }
      return await target.exists() ? entry(target) : {};
    }
    throw StateError('Unexpected PSP method ${call.method}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.broomm/psp-root-test');
  late Directory temp, data;
  late PspRootFixture native;
  late AndroidEmulators manager;
  late AndroidPspRootStore roots;
  late CloudSaves cloud;
  late SaveServer api;
  late File rom;
  Future<AndroidPspPlan> plan([String profile = profileId]) async =>
      await androidProgressLayout(
        manager,
        profile,
        native.emulator,
        playablePlatforms.firstWhere((p) => p.slug == 'psp'),
        rom.path,
      ) as AndroidPspPlan;
  CloudGame game(AndroidPspPlan p) => CloudGame(
    server: serverId,
    profile: p.profile,
    user: api.user,
    rom: 42,
    client: api,
    layout: p,
  );
  Future<AndroidGameSession> start([String profile = profileId]) async {
    final session = AndroidGameSession(manager, cloud);
    addTearDown(session.dispose);
    await session.start(
      server: serverId,
      profile: profile,
      rom: 42,
      emulator: native.emulator,
      app: manager.app(native.emulator)!,
      files: [rom.path],
      selected: rom.path,
      rooted: true,
      rootPlatform: 'psp',
      emulatorClosed: false,
      prepare: (_, _) async => game(await plan(profile)),
    );
    return session;
  }

  Future<Map<String, dynamic>> activeProfile(String id) async =>
      progressJson(await roots.profileFile(id));
  Future<File> local(AndroidPspPlan p, String key, List<int> bytes) async =>
      (await p.target(key)).writeAsBytes(bytes, flush: true);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('broomm-psp-root-');
    data = await Directory('${temp.path}/data').create();
    native = PspRootFixture(await Directory('${temp.path}/native').create());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, native.call);
    manager = AndroidEmulators(data, channel: channel, enabled: true);
    roots = AndroidPspRootStore(manager);
    cloud = CloudSaves(data, notice: (_, _) {});
    api = SaveServer();
    rom = await File('${temp.path}/fixture.pbp').writeAsBytes(pspPbp());
    await manager.load();
    await manager.connectPspRoot(native.emulator);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    manager.dispose();
    api.close();
    await temp.delete(recursive: true);
  });

  test('PSP play isolates accounts, uploads native savedata and keeps states local, restores standalone pointer and native preferences', () async {
    final p = await plan(), session = await start();
    expect(native.launches.single['rootedPsp'], isTrue);
    // Native root storage has no document-provider root marker. Task handoff
    // must not depend on having connected the older shared-folder route.
    expect(native.launches.single.containsKey('root'), isFalse);
    final record = await activeProfile(profileId);
    expect(native.selected, native.key(record));
    expect(await session.finishIfPspClosed(), AndroidPspState.running);
    expect(api.records, isEmpty);
    await native.put(record, 'PSP/SAVEDATA/ULUS10340SAVE/DATA.BIN', [1, 2, 3]);
    await native.put(record, 'PSP/PPSSPP_STATE/ULUS10340_1.02_0.ppst', [9, 8]);
    await native.put(record, 'PSP/PPSSPP_STATE/load_undo.ppst', [7, 6]);
    await native.put(
      record,
      'PSP/SYSTEM/ppsspp.ini',
      utf8.encode(
        '[SystemParam]\nMacAddress = ${record['mac']}\n[Graphics]\nRenderingMode = 1\n',
      ),
    );
    native.state = 'idle';
    expect(await session.finishIfPspClosed(), AndroidPspState.closed);
    expect(native.selected, 'native');
    expect(
      await (await p.target('save/ULUS10340SAVE/DATA.BIN')).readAsBytes(),
      [1, 2, 3],
    );
    expect(api.records, isNotEmpty);
    expect(api.stateRecords, isEmpty);
    const other = 'd123456789abcdef0123456789abcdef';
    api.user = 4;
    final second = await start(other),
        secondRecord = await activeProfile(other);
    expect(secondRecord['mac'], isNot(record['mac']));
    expect(
      await File(
        '${native.memory(secondRecord).path}/PSP/PPSSPP_STATE/load_undo.ppst',
      ).exists(),
      false,
    );
    expect((await native.files(secondRecord, full: false)), isEmpty);
    await native.put(secondRecord, 'PSP/SAVEDATA/ULUS10340SAVE/DATA.BIN', [
      4,
      5,
    ]);
    native.state = 'idle';
    expect(await second.finishIfPspClosed(), AndroidPspState.closed);
    api.user = 3;
    final resumed = await start();
    expect(
      await File(
        '${native.memory(record).path}/PSP/SAVEDATA/ULUS10340SAVE/DATA.BIN',
      ).readAsBytes(),
      [1, 2, 3],
    );
    expect(
      await File(
        '${native.memory(record).path}/PSP/PPSSPP_STATE/load_undo.ppst',
      ).readAsBytes(),
      [7, 6],
    );
    expect(
      await File('${native.memory(record).path}/PSP/SYSTEM/ppsspp.ini')
          .readAsString(),
      contains('RenderingMode = 1'),
    );
    native.state = 'idle';
    await resumed.finishIfPspClosed();
  });

  test('confirmed force close publishes rooted PPSSPP savedata and restores the standalone memory stick', () async {
    final p = await plan(), session = await start();
    final owner = await activeProfile(profileId);
    const save = [4, 2, 7];
    await native.put(owner, 'PSP/SAVEDATA/ULUS10340SAVE/DATA.BIN', save);
    await session.forceClose();
    await session.finish(emulatorClosed: true);
    expect(api.records, isNotEmpty);
    expect(
      await (await p.target('save/ULUS10340SAVE/DATA.BIN')).readAsBytes(),
      save,
    );
    expect(native.selected, 'native');
    expect(await session.pending(), isNull);
  });

  test('lost native publication replies retain durable recovery and replay the same operation before inventory', () async {
    final p = await plan();
    await local(p, 'save/ULUS10340SAVE/DATA.BIN', [1, 3]);
    native.loseReplace = true;
    final session = AndroidGameSession(manager, cloud);
    addTearDown(session.dispose);
    await expectLater(
      session.start(
        server: serverId,
        profile: profileId,
        rom: 42,
        emulator: native.emulator,
        app: manager.app(native.emulator)!,
        files: [rom.path],
        selected: rom.path,
        rooted: true,
        rootPlatform: 'psp',
        prepare: (_, _) async => game(p),
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(session.active, true);
    final journal = File('${data.path}/android/psp-swap.json'),
        r = await progressJson(journal);
    expect(r['pending'], isNotNull);
    expect(native.calls, isNot(contains('launch')));
    final count = native.calls.length;
    await session.finish(emulatorClosed: true, recovery: game(p));
    final after = native.calls.skip(count).toList();
    expect(
      after.indexOf('rootPspReplace'),
      lessThan(after.indexOf('rootPspList')),
    );
    expect(await journal.exists(), false);
    expect(
      await (await p.target('save/ULUS10340SAVE/DATA.BIN')).readAsBytes(),
      [1, 3],
    );
  });

  test('unknown exits, denied root, changed pointer and missing known save never adopt empty or foreign progress', () async {
    final p = await plan();
    await local(p, 'save/ULUS10340SAVE/DATA.BIN', [2, 4]);
    final session = await start(), record = await activeProfile(profileId);
    native.state = 'idle';
    native.exit = 'unknown';
    expect(await session.finishIfPspClosed(), AndroidPspState.unknown);
    expect(await session.pending(), isNotNull);
    native.denied = true;
    await expectLater(
      session.finish(emulatorClosed: true),
      throwsA(isA<PlatformException>()),
    );
    native.denied = false;
    native.exit = 'closed';
    native.selected = 'native';
    await expectLater(session.finish(emulatorClosed: true), throwsStateError);
    native.selected = native.key(record);
    final file = File(
      '${native.memory(record).path}/PSP/SAVEDATA/ULUS10340SAVE/DATA.BIN',
    );
    final bytes = await file.readAsBytes();
    await file.delete();
    await expectLater(session.finish(emulatorClosed: true), throwsStateError);
    expect(
      await (await p.target('save/ULUS10340SAVE/DATA.BIN')).readAsBytes(),
      [2, 4],
    );
    await native.put(record, 'PSP/SAVEDATA/ULUS10340SAVE/DATA.BIN', bytes);
    await session.finish(emulatorClosed: true);
  });

  test('Open emulator is detached, keeps profile preferences and backs up auxiliary files before reinstall', () async {
    await manager.open(native.emulator, profile: profileId, server: serverId);
    expect(await File('${data.path}/android/session.json').exists(), false);
    final lease = await SessionLease.acquire(data);
    await lease.release();
    final first = await activeProfile(profileId);
    await native.put(first, 'PSP/PPSSPP_STATE/load_undo.ppst', [
      6,
      5,
      4,
    ], mode: '600');
    await native.put(
      first,
      'PSP/SYSTEM/ppsspp.ini',
      utf8.encode(
        '[SystemParam]\nMacAddress = ${first['mac']}\n[Graphics]\nRenderingMode = 1\n',
      ),
    );
    native.state = 'idle';
    await roots.restoreSettingsLoan();
    expect(native.selected, 'native');
    await roots.backupInstallation(native.binding['package']!);
    await roots.retireInstallation(native.binding['package']!);
    await native.memory(first).delete(recursive: true);
    final restored = await roots.profile(serverId, profileId, native.binding);
    expect(restored['ownerNonce'], isNot(first['ownerNonce']));
    expect(restored['mac'], first['mac']);
    final undo = File(
      '${native.memory(restored).path}/PSP/PPSSPP_STATE/load_undo.ppst',
    );
    expect(await undo.readAsBytes(), [6, 5, 4]);
    expect(native.mode(undo), '600');
    expect(
      await File('${native.memory(restored).path}/PSP/SYSTEM/ppsspp.ini')
          .readAsString(),
      contains('RenderingMode = 1'),
    );
  });

  test('partial full-profile reads retain the previous verified backup and retry into a separate archive', () async {
    final profile = await roots.profile(serverId, profileId, native.binding);
    await roots.backup(profile);
    final first = await activeProfile(profileId);
    await native.put(profile, 'PSP/PPSSPP_STATE/load_undo.ppst', [4, 3, 2, 1]);
    native.loseRead = true;
    await expectLater(roots.backup(profile), throwsA(isA<PlatformException>()));
    final failed = await activeProfile(profileId);
    expect(failed['archives'], first['archives']);
    final retained = failed['backup']['nonce'];
    await roots.backup(profile);
    final recovered = await activeProfile(profileId);
    expect(recovered['archives'], hasLength(2));
    expect(
      recovered['retained'],
      contains(equals({'kind': 'partial-backup', 'nonce': retained})),
    );
    expect(
      await roots.archiveManifest(
        recovered,
        (recovered['archives'] as List).last,
      ),
      isNotNull,
    );
  });

  test('lost memory-stick selection and partial game capture keep both recovery boundaries retryable', () async {
    final p = await plan();
    native.loseSelect = true;
    final failed = AndroidGameSession(manager, cloud);
    addTearDown(failed.dispose);
    await expectLater(
      failed.start(
        server: serverId,
        profile: profileId,
        rom: 42,
        emulator: native.emulator,
        app: manager.app(native.emulator)!,
        files: [rom.path],
        selected: rom.path,
        rooted: true,
        rootPlatform: 'psp',
        prepare: (_, _) async => game(p),
      ),
      throwsA(isA<PlatformException>()),
    );
    expect((await roots.loan())?['phase'], 'selecting');
    expect(native.calls, isNot(contains('launch')));
    await failed.finish(emulatorClosed: true, recovery: game(p));
    expect(native.selected, 'native');
    final session = await start(), owner = await activeProfile(profileId);
    await native.put(owner, 'PSP/SAVEDATA/ULUS10340SAVE/DATA.BIN', [8, 7, 6]);
    native.state = 'idle';
    native.loseRead = true;
    await expectLater(
      session.finishIfPspClosed(),
      throwsA(isA<PlatformException>()),
    );
    expect(await session.pending(), isNotNull);
    expect(
      await (await p.target('save/ULUS10340SAVE/DATA.BIN')).exists(),
      false,
    );
    expect(
      await File(
        '${native.memory(owner).path}/PSP/SAVEDATA/ULUS10340SAVE/DATA.BIN',
      ).readAsBytes(),
      [8, 7, 6],
    );
    expect(await session.finishIfPspClosed(), AndroidPspState.closed);
    expect(
      await (await p.target('save/ULUS10340SAVE/DATA.BIN')).readAsBytes(),
      [8, 7, 6],
    );
  });

  test('private native changes reconcile before cloud sync and a two-sided change requires an explicit source choice', () async {
    await manager.open(native.emulator, profile: profileId, server: serverId);
    final owner = await activeProfile(profileId);
    await native.put(owner, 'PSP/SAVEDATA/ULUS10340SAVE/DATA.BIN', [1, 4]);
    native.state = 'idle';
    final first = await start(), p = await plan();
    expect(
      await (await p.target('save/ULUS10340SAVE/DATA.BIN')).readAsBytes(),
      [1, 4],
    );
    native.state = 'idle';
    await first.finishIfPspClosed();
    await manager.open(native.emulator, profile: profileId, server: serverId);
    await native.put(owner, 'PSP/SAVEDATA/ULUS10340SAVE/DATA.BIN', [2, 5]);
    native.state = 'idle';
    await local(p, 'save/ULUS10340SAVE/DATA.BIN', [3, 6]);
    final session = AndroidGameSession(manager, cloud);
    addTearDown(session.dispose);
    var choices = 0;
    await session.start(
      server: serverId,
      profile: profileId,
      rom: 42,
      emulator: native.emulator,
      app: manager.app(native.emulator)!,
      files: [rom.path],
      selected: rom.path,
      rooted: true,
      rootPlatform: 'psp',
      prepare: (_, _) async => game(p),
      resolve: (conflict) async {
        choices++;
        expect(conflict.remoteLabel, 'PPSSPP');
        expect(conflict.localLabel, 'Broomm');
        return ProgressChoice.cloud;
      },
    );
    expect(choices, 1);
    expect(
      await File(
        '${native.memory(owner).path}/PSP/SAVEDATA/ULUS10340SAVE/DATA.BIN',
      ).readAsBytes(),
      [2, 5],
    );
    native.state = 'idle';
    await session.finishIfPspClosed();
  });

  test('bounded inventory pages merge completely and overlapping or malformed identity stays a visible failure', () async {
    final owner = await roots.profile(serverId, profileId, native.binding);
    native.pageLimit = 1;
    expect(await roots.nativeFiles(owner), hasLength(2));
    native.corruptPage = true;
    await expectLater(roots.nativeFiles(owner), throwsFormatException);
    expect(await roots.loan(), isNull);
    final changed = {...native.binding, 'uid': '100000', 'abi': 'unknown'};
    expect(androidPspRootBinding(changed), false);
    expect(
      await File('${native.memory(owner).path}/PSP/SYSTEM/ppsspp.ini').exists(),
      true,
    );
  });

  test('a later native save during backup recovery is retained and synchronized rather than acknowledged as the older capture', () async {
    final session = await start(),
        owner = await activeProfile(profileId),
        p = await plan();
    await native.put(owner, 'PSP/SAVEDATA/ULUS10340SAVE/DATA.BIN', [1, 2]);
    native.state = 'idle';
    native.loseProfileRead = true;
    await expectLater(
      session.finishIfPspClosed(),
      throwsA(isA<PlatformException>()),
    );
    expect(
      (await progressJson(File('${data.path}/android/psp-swap.json')))['phase'],
      'finishing',
    );
    expect(api.records, hasLength(1));
    await native.put(owner, 'PSP/SAVEDATA/ULUS10340SAVE/DATA.BIN', [3, 4]);
    await native.put(owner, 'PSP/PPSSPP_STATE/ULUS10340_1.02_0.ppst', [9, 10]);
    await expectLater(session.finishIfPspClosed(), throwsStateError);
    expect(
      (await progressJson(File('${data.path}/android/psp-swap.json')))['phase'],
      'launched',
    );
    expect(await session.finishIfPspClosed(), AndroidPspState.closed);
    expect(
      await (await p.target('save/ULUS10340SAVE/DATA.BIN')).readAsBytes(),
      [3, 4],
    );
    expect(api.records, hasLength(2));
    expect(api.stateRecords, isEmpty);
    expect(native.selected, 'native');
  });

  test('changing the PSP save-access route obeys the existing session lock before native or settings effects', () async {
    final lease = await SessionLease.acquire(data),
        before = native.calls.length;
    try {
      await expectLater(manager.disconnectPspRoot(), throwsStateError);
      expect(native.calls.length, before);
      expect(manager.pspRoot(), native.binding);
    } finally {
      await lease.release();
    }
    await manager.disconnectPspRoot();
    expect(manager.pspRoot(), isNull);
    await manager.load();
    expect(manager.pspRoot(), isNull);
  });
}
