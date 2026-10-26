import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/romm/models.dart';

import 'cloud_saves_test.dart' show SaveServer, serverId, profileId;

void main() {
  late Directory data, native;
  late SaveServer api;
  late ProgressLayout layout;
  late CloudSaves cloud;
  late CloudGame game;
  late List<bool> problemNotices;
  Future<ResolvedSession> session(
    String code, {
    String folder = 'roms',
    int revision = 0,
  }) async {
    final rom = File('${data.path}/$folder/Game.nds');
    await rom.parent.create(recursive: true);
    final bytes = Uint8List(32)..setRange(12, 16, ascii.encode(code));
    bytes[0x1e] = revision;
    await rom.writeAsBytes(bytes);
    return ResolvedSession(
      PreparedEmulator(
        'melonDS',
        native.path,
        'fixture-executable',
        2,
        null,
        null,
        userDirectory: '${native.path}/launcher/portable',
      ),
      rom.path,
      'a' * 64,
      {},
    );
  }

  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-ds-progress-');
    native = Directory('${data.path}/profiles/$profileId/emulators/melonds');
    await native.create(recursive: true);
    await File('${native.path}/profile.json').writeAsString(
      jsonEncode({'version': 1, 'profile': profileId, 'emulator': 'melonds'}),
    );
    layout = await gameProgressLayout(await session('IRBO'), 'nds');
    api = SaveServer();
    problemNotices = [];
    cloud = CloudSaves(
      data,
      notice: (_, problem) {
        problemNotices.add(problem);
      },
    );
    game = CloudGame(
      server: serverId,
      profile: profileId,
      user: 3,
      rom: 42,
      client: api,
      layout: layout,
    );
  });
  tearDown(() async {
    api.close();
    await data.delete(recursive: true);
  });
  test('a raw DS save imports in place, copies to broomm, and later sync changes only the managed save', () async {
    final raw = Uint8List(524288)
      ..[0] = 0x50
      ..[1] = 0x4b
      ..[2] = 0x42
      ..[3] = 0x41;
    final source = api.add(raw, name: 'My DS progress', emulator: 'melonDS');
    await cloud.idle(() => cloud.useExisting(game, source));
    final local = await layout.target('save/game.sav');
    expect(await local.readAsBytes(), raw);
    final managed = api.records.values.singleWhere((s) => s.managed);
    expect(api.contents[source.id], raw);
    expect(
      managed.name,
      matches(r'^Broomm \[\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\]\.sav$'),
    );
    expect(managed.slot, 'BROOMM');
    expect(api.contents[managed.id], raw);
    final readCount = api.readIds.where((id) => id == source.id).length;
    final changed = Uint8List.fromList(raw)..[10] = 77;
    await local.writeAsBytes(changed);
    await cloud.idle(() => cloud.sync(game));
    expect(api.updatedIds.last, isNot(managed.id));
    expect(api.contents[managed.id], raw);
    expect(api.readIds.where((id) => id == source.id).length, readCount);
    expect(api.contents[source.id]![10], 0);
  });
  test('same ROM filenames with different verified game codes/revisions have separate native save boundaries', () async {
    final second = await gameProgressLayout(
      await session('YP2E', folder: 'other'),
      'nds',
    );
    final revised = await gameProgressLayout(
      await session('IRBO', folder: 'revised', revision: 1),
      'nds',
    );
    final a = await layout.target('save/game.sav'),
        b = await second.target('save/game.sav'),
        c = await revised.target('save/game.sav');
    expect({a.path, b.path, c.path}.length, 3);
    await b.writeAsString('unrelated');
    await a.writeAsBytes(Uint8List(8192));
    expect((await layout.files()).keys, ['save/game.sav']);
    expect(await b.readAsString(), 'unrelated');
  });
  test('the latest BROOMM timestamp wins over listing order and unrelated autosaves remain unread', () async {
    final newer = Uint8List(8192)..[10] = 2, older = Uint8List(8192)..[10] = 1;
    final newest = api.add(
      newer,
      name: 'Broomm [2026-10-22_20-00-00].sav',
      slot: 'BROOMM',
    );
    api.add(older, name: 'Broomm [2026-10-22_19-00-00].sav', slot: 'BROOMM');
    final other = api.add(
      older,
      name: 'Pokemon Ranger [2026-10-23_10-00-00].sav',
      emulator: 'melonds',
      slot: 'autosave',
    );
    await cloud.idle(() => cloud.sync(game));
    expect(await (await layout.target('save/game.sav')).readAsBytes(), newer);
    expect(api.readIds, contains(newest.id));
    expect(api.readIds, isNot(contains(other.id)));
    expect(api.updatedIds, isEmpty);
  });
  test('a lost state-upload reply resumes the same public native version without duplicating either asset or overwriting progress', () async {
    final raw = await layout.target('save/game.sav');
    await raw.writeAsBytes(Uint8List(8192));
    await cloud.idle(() => cloud.beforePlay(game));
    final stateArea = layout.areas.singleWhere(
      (a) => a.id.startsWith('states-'),
    );
    final state = await layout.target('${stateArea.id}/game1');
    await state.writeAsString('verified state');
    api.loseStateReply = true;
    await cloud.idle(() => cloud.afterPlay(game, 0));
    expect(problemNotices.last, true);
    expect((await cloud.store(game).state())['pending'], true);
    expect(api.records.values.where((s) => s.versioned), hasLength(2));
    final uploaded = api.records.values.last;
    expect(uploaded.name, endsWith('.sav'));
    expect(api.contents[uploaded.id]!.length, 8192);
    expect(api.stateRecords, hasLength(1));
    await cloud.idle(
      () => cloud.retryPending(
        server: serverId,
        profile: profileId,
        user: 3,
        rom: 42,
        client: api,
      ),
    );
    expect(api.records.values.where((s) => s.versioned), hasLength(2));
    expect(api.stateRecords, hasLength(1));
    expect((await cloud.store(game).state())['pending'], false);
    expect(await state.readAsString(), 'verified state');
  });
  test('a DSV container or ambiguous/multifile raw save is rejected without replacing local progress', () async {
    final nativeSave = await layout.target('save/game.sav');
    await nativeSave.writeAsString('keep');
    final store = ProgressStore(
      Directory('${data.path}/import'),
      layout,
      42,
      3,
    );
    final dsv = File('${data.path}/container.dsv');
    await dsv.writeAsBytes(Uint8List(524288 + 122));
    await expectLater(store.importNative(dsv), throwsA(isA<FormatException>()));
    expect(await nativeSave.readAsString(), 'keep');
  });
  test('finishing an older pending state upload preserves newer crashed progress and still requires review', () async {
    final raw = await layout.target('save/game.sav');
    await raw.writeAsBytes(Uint8List(8192));
    await cloud.idle(() => cloud.beforePlay(game));
    final stateArea = layout.areas.singleWhere(
      (a) => a.id.startsWith('states-'),
    );
    await (await layout.target('${stateArea.id}/game1'))
        .writeAsString('state from normal session');
    api.loseStateReply = true;
    await cloud.idle(() => cloud.afterPlay(game, 0));
    final st = cloud.store(game);
    final changed = Uint8List(8192)..[10] = 77;
    await raw.writeAsBytes(changed);
    await st.save({...await st.state(), 'unclean': true});
    var review = false;
    await expectLater(
      cloud.idle(
        () => cloud.sync(
          game,
          resolve: (conflict) async {
            review = true;
            expect(conflict.reason, contains('did not close normally'));
            return ProgressChoice.cancel;
          },
        ),
      ),
      throwsA(isA<RommFailure>()),
    );
    expect(review, true);
    final retained = await st.state();
    expect(retained['unclean'], true);
    expect(retained['pending'], true);
    expect(api.records.values.where((s) => s.versioned), hasLength(2));
    expect(await raw.readAsBytes(), changed);
    final snapshot = await st.load(retained['local'] as String);
    expect(
      await File('${snapshot.directory.path}/files/save/game.sav')
          .readAsBytes(),
      changed,
    );
  });
}
