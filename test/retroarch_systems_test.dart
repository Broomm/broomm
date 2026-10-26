import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/retroarch.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/progress/zip.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-retro-');
    await File('${root.path}/profile.json')
        .writeAsString(jsonEncode({'version': 1, 'emulator': 'retroarch'}));
  });
  tearDown(() async => root.delete(recursive: true));
  PreparedEmulator emulator(String core, String id) => PreparedEmulator(
    'RetroArch',
    root.path,
    'unused',
    3,
    null,
    '/unused/core.dylib',
    coreId: core,
    contentId: id,
  );
  Future<ProgressLayout> layout(String slug, String game, {String? hash}) =>
      gameProgressLayout(
        ResolvedSession(
          emulator(retroSystem(slug)!.core, game),
          '/old/filename.gb',
          'a' * 64,
          {},
          coreHash: hash ?? 'b' * 64,
        ),
        slug,
      );
  test('all 18 server RetroArch systems have concrete recipes and PS4 remains an ordinary downloadable unsupported platform', () {
    expect(retroSystems.map((s) => s.slug).toSet(), hasLength(18));
    expect(retroSystems.map((s) => s.core).toSet(), hasLength(14));
    for (final spec in retroSystems) {
      final game = RommGame(
        id: 1,
        name: 'Game',
        platformId: 1,
        platform: spec.slug,
        platformSlug: spec.slug,
      );
      final route = gamePlatform(game, [])!;
      expect(route.retroCore, spec.core);
      expect(
        launchDescriptor(game, route, '/rom').controllerTarget,
        spec.target,
      );
    }
    expect(
      gamePlatform(
        RommGame(
          id: 1,
          name: 'PS4',
          platformId: 1,
          platform: 'PS4',
          platformSlug: 'ps4',
        ),
        [],
      ),
      isNull,
    );
    expect(
      gameCandidates(playablePlatforms.firstWhere((p) => p.slug == 'saturn'), [
        '/disc.bin',
        '/disc.cue',
        '/dlc/other.cue',
      ]),
      ['/disc.cue'],
    );
  });
  test('new core launch uses private native save paths and legacy SNES sorting survives a previous new-core launch', () async {
    final e = emulator('gambatte', '123');
    final g = LaunchGame(
      '123',
      'GB',
      'GB',
      'RetroArch',
      'old.zip',
      1,
      0,
      target: ControllerTarget.gameboy,
      retroCore: 'gambatte',
    );
    final args = await const RetroArchAdapter().prepare(
      e,
      g,
      '/content/outer.gb',
      9999,
    );
    expect(args, isNot(contains('-s')));
    expect(args[args.indexOf('-S') + 1], endsWith('/states/game.state'));
    final snes = PreparedEmulator(
      'RetroArch',
      root.path,
      'unused',
      3,
      null,
      '/unused/snes.dylib',
    );
    await const RetroArchAdapter().prepare(
      snes,
      LaunchGame(
        'super-mario-world',
        'SMW',
        'SNES',
        'RetroArch',
        'x.sfc',
        2,
        0,
        target: ControllerTarget.snes,
      ),
      '/content/game.sfc',
      9999,
    );
    final config = await File('${root.path}/retroarch.cfg').readAsString();
    expect(config, contains('sort_savefiles_enable = "true"'));
    expect(config, contains('sort_savestates_enable = "true"'));
  });
  test('ZIP save identity matches the native outer archive and rejects ambiguity before native play', () async {
    final source = Directory('${root.path}/archive');
    await source.create();
    await File('${source.path}/inner.gb').writeAsBytes([1]);
    final single = File('${root.path}/outer.zip');
    await ProgressZip.write(single, source, ['inner.gb']);
    expect(await retroSaveStem(single.path, 'gambatte'), 'outer');
    await File('${source.path}/second.gb').writeAsBytes([2]);
    final ambiguous = File('${root.path}/two.zip');
    await ProgressZip.write(ambiguous, source, ['inner.gb', 'second.gb']);
    await expectLater(
      retroSaveStem(ambiguous.path, 'gambatte'),
      throwsFormatException,
    );
  });
  test('compressed Sega games capture existing native outer-name SRAM and ignore unrelated inner-name files', () async {
    final source = Directory('${root.path}/zip-source');
    await source.create();
    for (final (slug, ext) in [
      ('genesis', 'md'),
      ('gamegear', 'gg'),
      ('sms', 'sms'),
    ]) {
      await File('${source.path}/inner.$ext').writeAsBytes([1, 2, 3]);
      final zip = File('${root.path}/outer-$slug.zip');
      await ProgressZip.write(zip, source, ['inner.$ext']);
      final spec = retroSystem(slug)!;
      final l = await gameProgressLayout(
        ResolvedSession(
          emulator(spec.core, slug),
          zip.path,
          'a' * 64,
          {},
          coreHash: 'b' * 64,
        ),
        slug,
      );
      final native = await l.target('save/game.srm');
      await native.writeAsBytes([4, 5, 6]);
      await File('${native.parent.path}/inner.srm').writeAsBytes([7]);
      expect(native.uri.pathSegments.last, 'outer-$slug.srm');
      expect((await l.files()).keys, ['save/game.srm']);
      final s = ProgressStore(Directory('${root.path}/store-$slug'), l, 1, 1);
      final snapshot = await s.capture(), out = await s.exportNative(snapshot);
      try {
        expect(
          (await s.importNative(out.file)).ordinaryDigest,
          snapshot.ordinaryDigest,
        );
      } finally {
        await out.close();
      }
    }
  });
  test('SRAM and RTC round trip together; another game/core cannot capture them and core updates isolate states', () async {
    final a = await layout('gb', '123'),
        b = await layout('gb', '124'),
        c = await layout('gba', '123'),
        changed = await layout('gb', '123', hash: 'c' * 64);
    final s = await a.target('save/game.srm'),
        rtc = await a.target('save/game.rtc');
    await s.writeAsBytes(List.filled(8192, 3));
    await rtc.writeAsBytes([1, 2, 3]);
    expect(await b.files(), isEmpty);
    expect(await c.files(), isEmpty);
    expect(a.identity, changed.identity);
    expect(a.areas.last.id, isNot(changed.areas.last.id));
    final store = ProgressStore(Directory('${root.path}/snapshots'), a, 1, 1);
    final snap = await store.capture();
    final out = await store.exportNative(snap);
    try {
      expect(out.extension, 'zip');
      final imported = await store.importNative(out.file);
      expect(imported.ordinaryDigest, snap.ordinaryDigest);
      await rtc.delete();
      await s.writeAsBytes([8]);
      await store.restore(imported, {});
      expect(await s.length(), 8192);
      expect(await rtc.readAsBytes(), [1, 2, 3]);
    } finally {
      await out.close();
    }
  });
  test('one SRAM exports native .srm and external .sav imports normalize without inventing a wrapper', () async {
    final a = await layout('gba', '123'),
        store = ProgressStore(Directory('${root.path}/store'), a, 1, 1);
    final source = File('${root.path}/external.sav');
    await source.writeAsBytes(List.filled(32768, 9));
    final imported = await store.importNative(source);
    expect(imported.entries.keys, ['save/game.srm']);
    await store.restore(imported, {});
    final exported = await store.exportNative(await store.capture());
    try {
      expect(exported.extension, 'srm');
      expect(await exported.file.readAsBytes(), await source.readAsBytes());
    } finally {
      await exported.close();
    }
  });
  test('Dreamcast multi-file VMU capture includes private data but excludes another game and state groups', () async {
    final a = await layout('dc', '123'), other = await layout('dc', '124');
    await (await a.target('save/game.A1.bin'))
        .writeAsBytes(List.filled(131072, 1));
    await (await a.target('save/game.B1.bin'))
        .writeAsBytes(List.filled(131072, 3));
    expect(await other.files(), isEmpty);
    final store = ProgressStore(Directory('${root.path}/dc-store'), a, 1, 1),
        snapshot = await store.capture();
    final out = await store.exportNative(snapshot);
    try {
      expect(out.extension, 'zip');
      expect(
        (await store.importNative(out.file)).ordinaryDigest,
        snapshot.ordinaryDigest,
      );
    } finally {
      await out.close();
    }
  });
  for (final changed in [false, true]) {
    test(
      'managed core pack removal preserves progress and ${changed ? 'refuses changed binaries' : 'removes its own verified installation'}',
      () async {
        final manager = ManagedEmulators(root, asset: (_) async => '');
        final build = TestedBuild({
          'id': 'retroarch',
          'name': 'RetroArch',
          'version': 'test',
          'host': 'macos-arm64',
          'bundle': 'RetroArch.app',
          'executable': 'x',
          'sha256': 'a' * 64,
          'sdl': 3,
          'native': <String, String>{},
        });
        manager.builds.add(build);
        manager.installed['retroarch'] = build.hash;
        manager.coreBuilds['gambatte'] = {'id': 'gambatte'};
        final release = Directory(
          '${root.path}/emulators/retroarch/${build.hash}',
        );
        await release.create(recursive: true);
        await File('${root.path}/emulators/selected.json').writeAsString(
          jsonEncode({
            'schema_version': 1,
            'selected': {'retroarch': build.hash},
            'removals': <String, String>{},
          }),
        );
        await File('${release.path}/receipt.json')
            .writeAsString(jsonEncode({'id': 'retroarch', 'hash': build.hash}));
        final hash = (ProgressDigest.sha256()..add([1, 2, 3])).finish();
        final core = Directory('${release.path}/cores/gambatte-$hash');
        await core.create(recursive: true);
        await File('${core.path}/receipt.json')
            .writeAsString(jsonEncode({'id': 'gambatte', 'sha256': hash}));
        await File('${core.path}/core.dylib')
            .writeAsBytes(changed ? [9] : [1, 2, 3]);
        final save = File('${root.path}/profiles/private/save');
        await save.parent.create(recursive: true);
        await save.writeAsString('keep');
        await manager.remove(build);
        expect(await save.readAsString(), 'keep');
        expect(await release.exists(), changed);
        if (changed)
          expect(manager.error, isNotNull);
        else
          expect(manager.error, isNull);
        manager.dispose();
      },
    );
  }
}
