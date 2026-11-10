import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/progress/files.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';

const serverId = 'a123456789abcdef0123456789abcdef';
const profileId = 'b123456789abcdef0123456789abcdef';

class SaveServer extends RommClient {
  SaveServer() : super(Uri.parse('https://example.invalid'));
  final records = <int, RommSave>{};
  final stateRecords = <int, RommSave>{};
  final contents = <int, List<int>>{};
  final readIds = <int>[], updatedIds = <int>[];
  int serial = 0, user = 3, stateCalls = 0;
  bool offline = false, loseUploadReply = false;
  int? loseSaveReadback;
  Future<void> check() async {
    if (offline) throw const RommFailure('Offline test server');
  }

  RommSave add(
    List<int> bytes, {
    String name = 'broomm',
    String emulator = 'Broomm',
    String? slot,
  }) {
    final id = ++serial;
    final save = RommSave(
      id: id,
      romId: 42,
      userId: user,
      name: name,
      bytes: bytes.length,
      emulator: emulator,
      slot: slot,
      updated: 'r$serial',
    );
    records[id] = save;
    contents[id] = bytes;
    return save;
  }

  @override
  Future<RommUser> currentUser() async {
    await check();
    return RommUser(user, 'owner');
  }

  @override
  Future<List<RommSave>> saves(int id) async {
    await check();
    return records.values.toList();
  }

  @override
  Future<RommSave> save(int id) async {
    await check();
    return records[id]!;
  }

  @override
  Future<List<RommSave>> states(int id) async {
    await check();
    stateCalls++;
    return stateRecords.values.toList();
  }

  @override
  Future<RommSave> state(int id) async {
    await check();
    stateCalls++;
    return stateRecords[id]!;
  }

  @override
  Future<RommSave> uploadState(
    int rom,
    File file, {
    required String name,
    required DownloadCancellation cancellation,
    void Function(int)? onProgress,
  }) async {
    await check();
    cancellation.check();
    stateCalls++;
    final id = ++serial, bytes = await file.readAsBytes();
    if (stateRecords.values.any((s) => s.name == name))
      throw const RommFailure('State already exists');
    final result = RommSave(
      id: id,
      romId: rom,
      userId: user,
      name: name,
      bytes: bytes.length,
      emulator: 'Broomm',
      updated: 'r$id',
      stateAsset: true,
    );
    stateRecords[id] = result;
    contents[id] = bytes;
    return result;
  }

  @override
  Future<void> downloadState(
    RommSave state,
    File destination, {
    required DownloadCancellation cancellation,
    void Function(int)? onProgress,
  }) {
    stateCalls++;
    return downloadSave(
      state,
      destination,
      cancellation: cancellation,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> downloadSave(
    RommSave save,
    File destination, {
    required DownloadCancellation cancellation,
    void Function(int)? onProgress,
  }) async {
    await check();
    cancellation.check();
    readIds.add(save.id);
    if (save.id == loseSaveReadback) {
      loseSaveReadback = null;
      throw const RommFailure('Save readback interrupted');
    }
    await destination.create(exclusive: true);
    await destination.writeAsBytes(contents[save.id]!, flush: true);
  }

  @override
  Future<RommSave> uploadSave(
    int rom,
    File file, {
    required String name,
    RommSave? replace,
    String? slot,
    required DownloadCancellation cancellation,
    void Function(int)? onProgress,
  }) async {
    await check();
    cancellation.check();
    final bytes = await file.readAsBytes();
    if (slot != null) {
      final date = DateTime.utc(2026, 10, 22)
          .add(Duration(seconds: serial))
          .toIso8601String()
          .substring(0, 19)
          .replaceAll('T', '_')
          .replaceAll(':', '-');
      name = 'Broomm [$date].${name.split('.').last}';
    }
    final result = replace == null
        ? add(bytes, name: name, slot: slot)
        : RommSave(
            id: replace.id,
            romId: rom,
            userId: user,
            name: name,
            bytes: bytes.length,
            emulator: 'Broomm',
            updated: 'r${++serial}',
          );
    records[result.id] = result;
    contents[result.id] = bytes;
    updatedIds.add(result.id);
    if (loseUploadReply) {
      loseUploadReply = false;
      throw const RommFailure('Upload reply lost');
    }
    return result;
  }

  @override
  Future<RommSave> renameSave(RommSave save, String name) async {
    if (records.values.any((s) => s.name == name))
      throw const RommFailure('Name already exists', status: 409);
    final result = RommSave(
      id: save.id,
      romId: save.romId,
      userId: save.userId,
      name: name,
      bytes: save.bytes,
      emulator: save.emulator,
      slot: save.slot,
      updated: 'r${++serial}',
    );
    records[result.id] = result;
    return result;
  }
}

class Device {
  Device(this.root, this.api) : cloud = CloudSaves(root, notice: (m, p) {});
  final Directory root;
  final SaveServer api;
  final CloudSaves cloud;
  late final native = Directory(
    '${root.path}/profiles/$profileId/emulators/azahar',
  );
  late final game = CloudGame(
    server: serverId,
    profile: profileId,
    user: 3,
    rom: 42,
    client: api,
    layout: ProgressLayout(native.path, 'azahar-data-v1', '00040000000edf00', [
      const ProgressArea('save', 'private/game/data'),
    ]),
  );
  File get save => File('${native.path}/private/game/data/00000001/main.bin');
  Future<void> write(String text) async {
    await save.parent.create(recursive: true);
    await save.writeAsString(text, flush: true);
    await File('${native.path}/private/game/data/00000001.metadata')
        .writeAsString('fixture metadata', flush: true);
  }

  Future<void> sync({ProgressResolver? resolve}) =>
      cloud.idle(() => cloud.sync(game, resolve: resolve));
}

void main() {
  late Directory tmp;
  late SaveServer api;
  late Device a, b;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('broomm-cloud-test-');
    api = SaveServer();
    a = Device(Directory('${tmp.path}/a'), api);
    b = Device(Directory('${tmp.path}/b'), api);
  });
  tearDown(() async {
    api.close();
    await tmp.delete(recursive: true);
  });

  test('automatic sync writes only the exact account/game Broomm asset and pulls it on another device', () async {
    final other = api.add([1, 2, 3], name: 'Manual backup');
    final foreign = api.add([4, 5], emulator: 'Azahar');
    await a.write('first progress');
    await a.sync();
    final managed = api.records.values.singleWhere((s) => s.managed);
    final firstVersion = List<int>.from(api.contents[managed.id]!);
    await b.sync();
    expect(await b.save.readAsString(), 'first progress');
    await a.write('second progress');
    await a.sync();
    expect(api.records.values.where((s) => s.versioned), hasLength(2));
    expect(
      api.updatedIds.toSet(),
      api.records.values.where((s) => s.versioned).map((s) => s.id).toSet(),
    );
    expect(api.contents[managed.id], firstVersion);
    expect(api.readIds, isNot(contains(other.id)));
    expect(api.readIds, isNot(contains(foreign.id)));
    expect(api.contents[other.id], [1, 2, 3]);
    expect(api.contents[foreign.id], [4, 5]);
    await b.sync();
    expect(await b.save.readAsString(), 'second progress');
  });

  test('offline edits are retained and divergent devices require an explicit choice', () async {
    await a.write('common');
    await a.sync();
    await b.sync();
    await a.write('offline A');
    api.offline = true;
    await expectLater(a.sync(), throwsA(isA<RommFailure>()));
    expect(await a.save.readAsString(), 'offline A');
    expect((await a.cloud.store(a.game).state())['pending'], true);
    api.offline = false;
    await b.write('online B');
    await b.sync();
    final before = {
      for (final e in api.contents.entries) e.key: List<int>.from(e.value),
    };
    await expectLater(
      a.sync(
        resolve: (c) async {
          expect(c.remote, isNotNull);
          return ProgressChoice.cancel;
        },
      ),
      throwsA(isA<RommFailure>()),
    );
    expect(api.contents, before);
    expect(await a.save.readAsString(), 'offline A');
    await a.sync(resolve: (c) async => ProgressChoice.cloud);
    expect(await a.save.readAsString(), 'online B');
    final snapshots = Directory(
      '${a.cloud.store(a.game).directory.path}/snapshots',
    );
    final files = await snapshots
        .list(recursive: true)
        .where((e) => e is File && e.path.endsWith('main.bin'))
        .cast<File>()
        .toList();
    expect(
      await Future.wait(files.map((f) => f.readAsString())),
      contains('offline A'),
    );
  });

  test('legacy single-file progress migrates once into native version history without changing the old asset', () async {
    await a.write('legacy progress');
    final snapshot = await a.cloud.store(a.game).capture();
    final bytes = await snapshot.bundle.readAsBytes();
    final legacy = api.add(bytes);
    await b.sync();
    expect(await b.save.readAsString(), 'legacy progress');
    final version = api.records.values.singleWhere((s) => s.versioned);
    expect(version.name, endsWith('.zip'));
    expect(api.contents[legacy.id], bytes);
    expect(api.records[legacy.id]!.legacyManaged, true);
    await a.sync();
    await b.sync();
    expect(api.records.values.where((s) => s.versioned), hasLength(1));
    expect(api.updatedIds, [version.id]);
  });

  test(
    'lost upload acknowledgement is recovered without a second managed file',
    () async {
      await a.write('safe snapshot');
      api.loseUploadReply = true;
      await expectLater(a.sync(), throwsA(isA<RommFailure>()));
      expect((await a.cloud.store(a.game).state())['pending'], true);
      await a.sync();
      expect(api.records.values.where((s) => s.managed), hasLength(1));
      expect(api.updatedIds, hasLength(1));
      expect((await a.cloud.store(a.game).state())['pending'], false);
    },
  );

  test('explicit import copies the selected asset into broomm; named backups do not join automatic sync', () async {
    await a.write('original');
    await a.sync();
    await b.write('chosen');
    final sourceSnapshot = await b.cloud.store(b.game).capture();
    final sourceBytes = await sourceSnapshot.bundle.readAsBytes();
    final source = api.add(sourceBytes, name: 'Before the boss');
    await a.cloud.idle(() => a.cloud.useExisting(a.game, source));
    expect(await a.save.readAsString(), 'chosen');
    expect(api.contents[source.id], sourceBytes);
    await a.cloud.idle(() => a.cloud.backup(a.game, 'My checkpoint'));
    final backup = api.records.values.singleWhere(
      (s) => s.name == 'My checkpoint.zip',
    );
    final backupBytes = List<int>.from(api.contents[backup.id]!);
    await a.write('later');
    await a.sync();
    expect(api.contents[backup.id], backupBytes);
    expect(api.records.values.where((s) => s.versioned), hasLength(3));
    await expectLater(
      a.cloud.idle(() => a.cloud.backup(a.game, 'My checkpoint')),
      throwsA(isA<RommFailure>()),
    );
    expect(api.contents[backup.id], backupBytes);
  });

  test('duplicates, wrong account and missing working saves cannot be treated as an empty server', () async {
    await a.write('original');
    await a.sync();
    final initial = List<int>.from(api.contents.values.single);
    api.add(initial, name: api.records.values.single.name, slot: 'BROOMM');
    await expectLater(a.sync(), throwsA(isA<RommFailure>()));
    expect(api.updatedIds, hasLength(1));
    api.records.remove(api.records.keys.last);
    api.user = 8;
    await expectLater(a.sync(), throwsA(isA<RommFailure>()));
    api.user = 3;
    await a.save.parent.parent.delete(recursive: true);
    await expectLater(a.sync(), throwsA(isA<FileSystemException>()));
    expect(api.contents.values.first, initial);
  });

  test('a held production session lease prevents manual save effects and abnormal exits retain progress', () async {
    await a.write('good');
    await a.sync();
    final lease = await SessionLease.acquire(a.root);
    try {
      await expectLater(
        a.cloud.idle(() => a.cloud.backup(a.game, 'blocked')),
        throwsA(isA<StateError>()),
      );
    } finally {
      await lease.release();
    }
    await a.write('after crash');
    await a.cloud.idle(() => a.cloud.afterPlay(a.game, 1));
    final state = await a.cloud.store(a.game).state();
    expect(state['unclean'], true);
    expect(state['pending'], true);
    expect(api.updatedIds, hasLength(1));
    expect(await a.save.readAsString(), 'after crash');
  });

  test('an interrupted named backup resumes its exact snapshot without creating duplicate backups', () async {
    await a.write('backup version');
    api.loseUploadReply = true;
    await expectLater(
      a.cloud.idle(() => a.cloud.backup(a.game, 'Checkpoint')),
      throwsA(isA<RommFailure>()),
    );
    await a.write('newer local progress');
    await a.cloud.idle(() => a.cloud.backup(a.game, 'Checkpoint'));
    expect(
      api.records.values.where((s) => s.name == 'Checkpoint.zip'),
      hasLength(1),
    );
    expect(api.updatedIds, hasLength(1));
    expect(await a.save.readAsString(), 'newer local progress');
    final remote = api.records.values.single;
    await a.cloud.idle(() => a.cloud.useExisting(a.game, remote));
    expect(await a.save.readAsString(), 'backup version');
  });

  test(
    'pending immutable progress retries without a ROM or native installation',
    () async {
      await a.write('baseline');
      await a.sync();
      await a.write('offline progress');
      api.offline = true;
      await expectLater(a.sync(), throwsA(isA<RommFailure>()));
      // Disposable fixture only: retry must need neither native files nor ROMs.
      await a.native.delete(recursive: true);
      api.offline = false;
      await a.cloud.idle(
        () => a.cloud.retryPending(
          server: serverId,
          profile: profileId,
          user: 3,
          rom: 42,
          client: api,
        ),
      );
      await b.sync();
      expect(await b.save.readAsString(), 'offline progress');
      expect(await a.native.exists(), false);
    },
  );

  test('restore recovery rolls forward partial publication and refuses an unrecognized concurrent writer', () async {
    await a.write('one');
    final second = File('${a.save.parent.path}/second.bin');
    await second.writeAsString('one');
    final st = a.cloud.store(a.game),
        before = await a.cloud.store(a.game).capture();
    await a.write('two');
    await second.writeAsString('two');
    final after = await st.capture();
    await a.write('one');
    await second.writeAsString('one');
    await progressWrite(st.journal, {
      'before': st.storageId(before),
      'after': st.storageId(after),
      'state': {'pending': true, 'local': st.storageId(after)},
    });
    // Simulate process loss after one native file has been published.
    await a.write('two');
    final reopened = ProgressStore(
      st.directory,
      a.game.layout,
      42,
      3,
      ownerRoot: a.root,
    );
    await reopened.recover();
    expect(await a.save.readAsString(), 'two');
    expect(await second.readAsString(), 'two');
    expect(await st.journal.exists(), false);
    expect((await st.state())['pending'], true);
    await progressWrite(st.journal, {
      'before': st.storageId(before),
      'after': st.storageId(after),
      'state': {'pending': false},
    });
    await second.writeAsString('external writer');
    await expectLater(reopened.recover(), throwsA(isA<FileSystemException>()));
    expect(await second.readAsString(), 'external writer');
    expect(await st.journal.exists(), true);
    expect(await after.bundle.exists(), true);
    expect(await before.bundle.exists(), true);
  });

  test('a competing Broomm lineage cannot silently replace the last acknowledged device version', () async {
    await a.write('common');
    await a.sync();
    await b.sync();
    final common = await b.cloud.store(b.game).state();
    await b.write('competing B');
    final stale = await b.cloud
        .store(b.game)
        .capture(parents: [common['commit'] as String]);
    await a.write('acknowledged A');
    await a.sync();
    final record = api.records.values.last;
    final competingBytes = await stale.bundle.readAsBytes();
    api.contents[record.id] = competingBytes;
    api.records[record.id] = RommSave(
      id: record.id,
      romId: 42,
      userId: 3,
      name: record.name,
      bytes: competingBytes.length,
      emulator: 'Broomm',
      slot: record.slot,
      updated: 'competing write',
    );
    await expectLater(
      a.sync(resolve: (_) async => ProgressChoice.cancel),
      throwsA(isA<RommFailure>()),
    );
    expect(await a.save.readAsString(), 'acknowledged A');
    expect(api.contents[record.id], competingBytes);
  });

  test('Android raw SRAM retries without native files; same-build states stay local', () async {
    CloudGame android(Device d, String group) => CloudGame(
      server: serverId,
      profile: profileId,
      user: 3,
      rom: 42,
      client: api,
      layout: ProgressLayout(d.native.path, 'libretro-mgba-v1', '42', [
        const ProgressArea('save', 'save', prefix: 'Game', exact: 'Game.srm'),
        ProgressArea(group, group, prefix: 'Game'),
      ]),
    );
    const group = 'states-1111111111111111-android';
    final first = android(a, group);
    await a.cloud.idle(() => a.cloud.beforePlay(first));
    await (await first.layout.target('save/game.srm')).writeAsBytes([1, 2]);
    await (await first.layout.target('$group/game.state2'))
        .writeAsBytes([3, 4, 5]);
    api.offline = true;
    await a.cloud.idle(() => a.cloud.afterPlay(first, 0));
    expect((await a.cloud.store(first).state())['pending'], true);
    await a.native.delete(recursive: true);
    api.offline = false;
    await a.cloud.idle(
      () => a.cloud.retryPending(
        server: serverId,
        profile: profileId,
        user: 3,
        rom: 42,
        client: api,
      ),
    );
    expect(await a.native.exists(), false);
    expect(api.stateCalls, 0);
    final same = android(b, group);
    await b.cloud.idle(() => b.cloud.beforePlay(same));
    expect(await (await same.layout.target('save/game.srm')).readAsBytes(), [
      1,
      2,
    ]);
    expect(
      await (await same.layout.target('$group/game.state2')).exists(),
      false,
    );
  });

  test('other slots, names and emulator folders remain untouched when BROOMM history is created', () async {
    await a.write('local progress');
    api.serial = 1;
    for (final record in [
      const RommSave(
        id: 1,
        romId: 42,
        userId: 3,
        name: 'BROOMM',
        bytes: 3,
        emulator: 'Broomm',
      ),
      const RommSave(
        id: 1,
        romId: 42,
        userId: 3,
        name: 'broomm',
        bytes: 3,
        emulator: 'Broomm',
        slot: 'manual',
      ),
      const RommSave(
        id: 1,
        romId: 42,
        userId: 3,
        name: 'broomm',
        bytes: 3,
        emulator: 'Azahar',
        directory: 'users/owner/saves/3ds/42/Broomm',
      ),
    ]) {
      api.records[1] = record;
      api.contents[1] = [1, 2, 3];
      await a.sync();
      expect(api.contents[1], [1, 2, 3]);
    }
    expect(api.updatedIds, [2]);
    expect(api.readIds, isNot(contains(1)));
    expect(await a.save.readAsString(), 'local progress');
  });

  const group = 'states-1111111111111111-macos-arm64';
  CloudGame withStates(Device d) => CloudGame(
    server: serverId,
    profile: profileId,
    user: 3,
    rom: 42,
    client: d.api,
    layout: ProgressLayout(
      d.native.path,
      'azahar-data-v1',
      '00040000000edf00',
      [
        const ProgressArea('save', 'private/game/data'),
        const ProgressArea(group, 'states'),
      ],
    ),
  );

  test('old mixed saves import ordinary bytes without pulling state assets or touching local states', () async {
    final ga = withStates(a), gb = withStates(b);
    await a.write('old ordinary save');
    await (await ga.layout.target('$group/game.cst'))
        .writeAsString('old cloud state');
    final old = await a.cloud.store(ga).capture();
    final mixed = api.add(
      await old.bundle.readAsBytes(),
      name: 'Broomm [2026-10-22_00-00-00].zip',
      slot: 'BROOMM',
    );
    final companion = RommSave(
      id: 100,
      romId: 42,
      userId: 3,
      name: mixed.name,
      bytes: 10,
      emulator: 'Broomm',
      stateAsset: true,
    );
    api.stateRecords[companion.id] = companion;
    final local = await gb.layout.target('$group/game.cst');
    await local.writeAsString('keep local state');
    await b.cloud.idle(() => b.cloud.beforePlay(gb));
    expect(await b.save.readAsString(), 'old ordinary save');
    expect(await local.readAsString(), 'keep local state');
    final st = b.cloud.store(gb);
    final restored = await st.load((await st.state())['snapshot'] as String);
    expect(restored.hasStates, false);
    await b.cloud.idle(() => b.cloud.backup(gb, 'My save'));
    final backup = api.records.values.singleWhere(
      (s) => s.name == 'My save.zip',
    );
    final backupZip = await File('${tmp.path}/backup.zip')
        .writeAsBytes(api.contents[backup.id]!);
    expect((await st.importNative(backupZip)).hasStates, false);
    await expectLater(
      b.cloud.idle(() => b.cloud.useExisting(gb, companion)),
      throwsA(isA<RommFailure>()),
    );
    expect(api.stateCalls, 0);
    expect(api.stateRecords[companion.id], companion);
    expect(await local.readAsString(), 'keep local state');
  });

  test('legacy mixed common baseline compares ordinary saves when retrying an older queued snapshot', () async {
    final game = withStates(a), st = a.cloud.store(game);
    final localState = await game.layout.target('$group/game.cst');
    await a.write('common save');
    await localState.writeAsString('first state');
    final common = await st.capture();
    final remote = api.add(
      await common.bundle.readAsBytes(),
      name: 'Broomm [2026-10-22_00-00-00].zip',
      slot: 'BROOMM',
    );
    await a.write('queued save');
    await localState.writeAsString('second state');
    final pending = await st.capture();
    await st.save({
      'baseline': common.digest,
      'commit': common.id,
      'snapshot': st.storageId(common),
      'local': st.storageId(pending),
      'remote': remote.id,
      'pending': true,
    });
    await a.cloud.idle(
      () => a.cloud.retryPending(
        server: serverId,
        profile: profileId,
        user: 3,
        rom: 42,
        client: api,
      ),
    );
    expect(api.records, hasLength(2));
    final newest = await st.load((await st.state())['snapshot'] as String);
    expect(newest.ordinaryDigest, pending.ordinaryDigest);
    expect(newest.hasStates, false);
    expect(await localState.readAsString(), 'second state');
    expect(api.stateCalls, 0);
  });

  test(
    'missing working save keeps a first offline snapshot queued for recovery',
    () async {
      final game = withStates(a), st = a.cloud.store(game);
      await a.write('unsynced save');
      api.offline = true;
      await a.cloud.idle(() => a.cloud.afterPlay(game, 0));
      final pending = await st.state();
      await a.save.delete();
      await File('${a.save.parent.parent.path}/00000001.metadata').delete();
      await (await game.layout.target('$group/game.cst'))
          .writeAsString('local state');
      api.offline = false;
      await expectLater(
        a.cloud.idle(() => a.cloud.sync(game)),
        throwsA(isA<FileSystemException>()),
      );
      expect((await st.state())['local'], pending['local']);
      expect((await st.load(pending['local'] as String)).ordinaryEmpty, false);
      expect(api.records, isEmpty);
    },
  );

  test(
    'state-only sessions and legacy versions produce no new remote saves',
    () async {
      final ga = withStates(a), gb = withStates(b);
      final state = await ga.layout.target('$group/game.cst');
      await state.writeAsString('legacy state');
      final old = await a.cloud.store(ga).capture();
      final record = api.add(
        await old.bundle.readAsBytes(),
        name: 'Broomm [2026-10-22_00-00-00].zip',
        slot: 'BROOMM',
      );
      await a.cloud.idle(() => a.cloud.beforePlay(ga));
      await state.writeAsString('updated state');
      await a.cloud.idle(() => a.cloud.afterPlay(ga, 0));
      expect(await state.readAsString(), 'updated state');
      expect(api.records.keys, [record.id]);
      await expectLater(
        a.cloud.idle(() => a.cloud.backup(ga, 'No ordinary save')),
        throwsA(isA<RommFailure>()),
      );
      await b.cloud.idle(() => b.cloud.sync(gb));
      expect(await (await gb.layout.target('$group/game.cst')).exists(), false);
      await b.write('new ordinary save');
      await b.cloud.idle(() => b.cloud.sync(gb));
      expect(api.records, hasLength(2));
      expect(api.contents[record.id], await old.bundle.readAsBytes());
      expect(api.stateCalls, 0);
    },
  );
}
