import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/progress/files.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/progress/zip.dart';
import 'package:broomm/src/retroarch_saves.dart';
import 'package:broomm/src/session.dart';

import 'cloud_saves_test.dart' show SaveServer, serverId, profileId;

void main() {
  late Directory root, native;
  late SaveServer api;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-retro-save-');
    native = Directory('${root.path}/profiles/$profileId/emulators/retroarch');
    await native.create(recursive: true);
    await File('${native.path}/profile.json')
        .writeAsString(jsonEncode({'version': 1, 'emulator': 'retroarch'}));
    api = SaveServer();
  });
  tearDown(() async {
    api.close();
    await root.delete(recursive: true);
  });
  PreparedEmulator emulator(String core) => PreparedEmulator(
    'RetroArch',
    native.path,
    'unused',
    3,
    null,
    'unused',
    coreId: core,
    contentId: '42',
  );
  Future<ProgressLayout> layout(String slug, String core) => gameProgressLayout(
    ResolvedSession(
      emulator(core),
      '/media/Title.chd',
      'a' * 64,
      {},
      coreHash: 'b' * 64,
    ),
    slug,
  );
  CloudGame game(ProgressLayout l) => CloudGame(
    server: serverId,
    profile: profileId,
    user: 3,
    rom: 42,
    client: api,
    layout: l,
  );
  CloudSaves cloud() => CloudSaves(root, notice: (m, p) {});

  test('Opera native NVRAM survives upload readback and restore with its real nested filename', () async {
    final l = await layout('3do', 'opera'), g = game(l), c = cloud();
    final file = await l.target('save/opera/per_game/Title.0.srm');
    await file.writeAsBytes(List.generate(32768, (i) => i % 251));
    final s = c.store(g), before = await s.capture();
    await c.sync(g);
    expect(api.records.values.single.name, endsWith('.srm'));
    expect((await s.state())['pending'], false);
    expect(
      (await s.load((await s.state())['snapshot'] as String)).ordinaryDigest,
      before.ordinaryDigest,
    );
    final imported = await s.importNative(file);
    expect(imported.entries.keys, ['save/opera/per_game/Title.0.srm']);
    await file.writeAsBytes(List.filled(32768, 7));
    await s.restore(imported, {});
    expect((await s.capture()).ordinaryDigest, before.ordinaryDigest);
  });
  test('a lost Opera upload reply retries from its retained snapshot without native ROM access or duplicate upload', () async {
    final l = await layout('3do', 'opera'), g = game(l), c = cloud();
    await (await l.target('save/opera/per_game/Title.0.srm'))
        .writeAsBytes(List.filled(32768, 9));
    api.loseUploadReply = true;
    await expectLater(c.sync(g), throwsA(isA<Exception>()));
    expect(api.records, hasLength(1));
    await native.delete(recursive: true);
    await c.retryPending(
      server: serverId,
      profile: profileId,
      user: 3,
      rom: 42,
      client: api,
    );
    expect(api.records, hasLength(1));
    final state = jsonDecode(
      await File('${root.path}/cloud-saves/$serverId/$profileId/42/state.json')
          .readAsString(),
    ) as Map;
    expect(state['pending'], false);
  });
  for (final (slug, core, statesOnly) in [
    ('genesis', 'genesis_plus_gx', false),
    ('lynx', 'mednafen_lynx', true),
  ]) {
    test(
      '$core retries retained offline progress after native removal using its real core identity',
      () async {
        final l = await layout(slug, core), g = game(l), c = cloud();
        final key = statesOnly ? '${l.areas.last.id}/game' : 'save/game.srm';
        await (await l.target(key)).writeAsBytes(List.filled(8192, 3));
        final store = c.store(g), snapshot = await store.capture();
        await store.save({'local': store.storageId(snapshot), 'pending': true});
        await native.delete(recursive: true);
        await c.retryPending(
          server: serverId,
          profile: profileId,
          user: 3,
          rom: 42,
          client: api,
        );
        expect(api.records, hasLength(1));
        expect((await store.state())['pending'], false);
        expect(
          api.records.values.single.name,
          endsWith(statesOnly ? '.zip' : '.srm'),
        );
      },
    );
  }
  test('Opera honors shared/version options and rejects a truncated raw NVRAM without changing progress', () async {
    await Directory('${native.path}/config').create();
    await File('${native.path}/config/core-options.cfg').writeAsString(
      'opera_nvram_storage = "per game"\nopera_nvram_version = "0"\n',
    );
    await Directory('${native.path}/config/Opera').create();
    await File('${native.path}/config/Opera/Opera.opt').writeAsString(
      'opera_nvram_storage = "shared"\nopera_nvram_version = "3"\n',
    );
    final l = await layout('3do', 'opera'), s = cloud().store(game(l));
    expect(l.rawSaveKey, 'save/opera/shared/nvram.3.srm');
    await File('${native.path}/retroarch.cfg').writeAsString(
      'global_core_options = "true"\ngame_specific_options = "false"\n',
    );
    expect(
      (await layout('3do', 'opera')).rawSaveKey,
      'save/opera/per_game/Title.0.srm',
    );
    final file = await l.target(l.rawSaveKey!);
    await file.writeAsBytes(List.filled(32768, 1));
    final broken = File('${root.path}/truncated.srm');
    await broken.writeAsBytes([1, 2, 3]);
    await expectLater(s.importNative(broken), throwsFormatException);
    expect(await file.length(), 32768);
  });
  Future<File> legacy(String slot) async {
    final f = await progressFile(
      native,
      'system/dc/vmu_save_$slot.bin',
      createParents: true,
    );
    await f.writeAsBytes(List.filled(131072, slot.codeUnitAt(0)));
    return f;
  }

  test('legacy Dreamcast cards migrate once to the sole game and retain both originals and subsequent private progress', () async {
    final original = await legacy('A1');
    await prepareFlycastSaves(native.path, '42', '/media/Title.chd');
    final l = await layout('dc', 'flycast');
    final files = await l.files();
    expect(files.keys, ['save/Title.A1.bin']);
    expect(
      await files.values.single.readAsBytes(),
      await original.readAsBytes(),
    );
    await files.values.single.writeAsBytes(List.filled(131072, 8));
    await prepareFlycastSaves(native.path, '42', '/media/Title.chd');
    expect((await files.values.single.readAsBytes()).first, 8);
    await prepareFlycastSaves(native.path, '43', '/media/Other.chd');
    expect(
      await Directory('${native.path}/core-data/flycast/43/saves').exists(),
      false,
    );
    expect(await original.length(), 131072);
    final s = cloud().store(game(l)),
        snapshot = await s.capture(),
        out = await s.exportNative(snapshot);
    try {
      expect(out.extension, 'zip');
      expect(
        (await s.importNative(out.file)).ordinaryDigest,
        snapshot.ordinaryDigest,
      );
    } finally {
      await out.close();
    }
  });
  test('ambiguous old Dreamcast cards and conflicting private cards are preserved without guessed replacement', () async {
    final old = await legacy('A1');
    await Directory('${native.path}/core-data/flycast/43/saves')
        .create(recursive: true);
    await expectLater(
      prepareFlycastSaves(native.path, '42', '/media/Title.chd'),
      throwsFormatException,
    );
    await Directory('${native.path}/core-data/flycast/43')
        .delete(recursive: true);
    final private = await progressFile(
      native,
      'core-data/flycast/42/saves/Title.A1.bin',
      createParents: true,
    );
    await private.writeAsBytes(List.filled(131072, 7));
    await expectLater(
      prepareFlycastSaves(native.path, '42', '/media/Title.chd'),
      throwsFormatException,
    );
    expect((await old.readAsBytes()).first, 'A'.codeUnitAt(0));
    expect((await private.readAsBytes()).first, 7);
  });
  test('Dreamcast import rejects truncated VMUs and unrelated system flash without replacing the device card', () async {
    final l = await layout('dc', 'flycast'), s = cloud().store(game(l));
    final card = await l.target('save/game.A1.bin');
    await card.writeAsBytes(List.filled(131072, 4));
    final source = Directory('${root.path}/external');
    await source.create();
    for (final (name, length) in [
      ('Title.A1.bin', 12),
      ('dc_nvmem.bin', 131072),
    ]) {
      await File('${source.path}/$name').writeAsBytes(List.filled(length, 6));
      final archive = File('${root.path}/$name.zip');
      await ProgressZip.write(archive, source, [name]);
      await expectLater(s.importNative(archive), throwsFormatException);
      expect((await card.readAsBytes()).first, 4);
    }
  });
  test('Flycast launch forces every VMU into per-game saves while retaining the editable base settings', () async {
    await Directory('${native.path}/config').create();
    final base = File('${native.path}/config/core-options.cfg');
    const original =
        'reicast_per_content_vmus = "disabled"\nreicast_internal_resolution = "1280x960"\n';
    await base.writeAsString(original);
    final args = await const RetroArchAdapter().prepare(
      emulator('flycast'),
      LaunchGame(
        '42',
        'Title',
        'dc',
        'RetroArch',
        '/media/Title.chd',
        4,
        0,
        retroCore: 'flycast',
      ),
      '/media/Title.chd',
      9999,
    );
    expect(await base.readAsString(), original);
    expect(args, contains('--appendconfig'));
    final config = await File(args[args.indexOf('--appendconfig') + 1])
        .readAsString();
    expect(config, contains('/core-data/flycast/42/core-options.cfg'));
    expect(config, contains('global_core_options = "true"'));
    final options = await File(
      '${native.path}/core-data/flycast/42/core-options.cfg',
    ).readAsString();
    expect(options, contains('reicast_per_content_vmus = "All VMUs"'));
    expect(options, contains('reicast_internal_resolution = "1280x960"'));
  });
}
