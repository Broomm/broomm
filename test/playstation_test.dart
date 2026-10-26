import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/controller_mapping.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/managed_profile.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/playstation.dart';
import 'package:broomm/src/playstation_firmware.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session.dart';

import 'cloud_saves_test.dart' show SaveServer, serverId, profileId;

class _Firmware extends RommClient {
  _Firmware(this.bytes) : super(Uri.parse('https://example.invalid'));
  final List<int> bytes;
  var reads = 0, downloads = 0, platform = 23;
  String? checksum;
  List<RommFirmware>? catalogue;
  @override
  Future<List<RommFirmware>> firmware(int id) async {
    reads++;
    final digest = ProgressDigest.md5()..add(bytes);
    return catalogue ??
        [
          RommFirmware(
            1,
            platform,
            'bios.bin',
            bytes.length,
            checksum ?? digest.finish(),
          ),
        ];
  }

  @override
  Future<void> downloadFirmware(
    RommFirmware file,
    File target, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    cancellation.check();
    downloads++;
    await target.writeAsBytes(bytes);
    onProgress(bytes.length);
  }
}

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('broomm-playstation-'),
  );
  tearDown(() async => root.delete(recursive: true));
  TestedBuild build(String name) => TestedBuild({
    'id': name.toLowerCase(),
    'name': name,
    'host': 'macos-arm64',
    'version': 'test',
    'bundle': '$name.app',
    'executable': 'Contents/MacOS/$name',
    'sha256': 'a' * 64,
    'sdl': 3,
    'native': <String, String>{},
  });
  Future<PreparedEmulator> emulator(
    String name, {
    String profile = profileId,
  }) async {
    final native = await prepareManagedProfile(
      root,
      profile,
      build(name),
      Directory('${root.path}/release'),
    );
    return PreparedEmulator(
      name,
      native.path,
      'unused',
      3,
      null,
      null,
      contentId: '42',
      userDirectory: name == 'DuckStation'
          ? '${native.path}/home/Library/Application Support/DuckStation'
          : '${native.path}/user/${name.toLowerCase()}/$name',
    );
  }

  ResolvedSession resolved(PreparedEmulator e) =>
      ResolvedSession(e, '/media/game.chd', 'a' * 64, {});
  Future<File> card(String path, {bool ps2 = false, int marker = 7}) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    if (ps2) {
      final io = await f.open(mode: FileMode.write);
      try {
        await io.truncate(8 * 1024 * 1024 ~/ 512 * 528);
        await io.writeFrom(ascii.encode('Sony PS2 Memory Card Format '));
        await io.setPosition(4096);
        await io.writeByte(marker);
      } finally {
        await io.close();
      }
    } else {
      final bytes = Uint8List(128 * 1024)
        ..[0] = 0x4d
        ..[1] = 0x43
        ..[4096] = marker;
      await f.writeAsBytes(bytes);
    }
    return f;
  }

  test(
    'PS1/PS2 catalogue routing preserves emulator choices and disc descriptors',
    () {
      final psx = playablePlatforms.singleWhere((p) => p.slug == 'psx');
      expect(
        platformEmulators(const RommPlatform(10, 'PlayStation 2', 'ps2', 1))
            .map((p) => p.emulatorId),
        containsAll(['armsx2', 'pcsx2']),
      );
      expect(
        gameCandidates(psx, [
          'tracks/game.bin',
          'tracks/game.cue',
          'updates/update.bin',
        ]),
        ['tracks/game.cue'],
      );
      expect(gameCandidates(psx, ['disc1.cue', 'disc2.cue', 'game.m3u']), [
        'game.m3u',
      ]);
      expect(() => playStationGameDirectory('../other'), throwsFormatException);
    },
  );

  test('PS2 alternatives share cards but keep settings and exact-build states private', () async {
    final pcs = await emulator('PCSX2'), arms = await emulator('ARMSX2');
    expect(pcs.root, arms.root);
    expect(pcs.user, isNot(arms.user));
    for (final e in [pcs, arms]) {
      final ini = File('${e.user}/inis/PCSX2.ini');
      await ini.writeAsString(
        '${await ini.readAsString()}\n[EmuCore/GS]\nupscale_multiplier=3\n',
      );
      final game = LaunchGame(
        '42',
        'Title',
        'ps2',
        e.name,
        '/media/a [title].chd',
        2,
        0,
        target: ControllerTarget.ps2,
      );
      final args = await EmulatorAdapter.forName(e.name)
          .prepare(e, game, game.rom, 0);
      expect(args.take(2), ['-datapath', Directory(e.user).parent.path]);
      expect(args.last, game.rom);
      expect(await ini.readAsString(), contains('upscale_multiplier=3'));
    }
    final a = await gameProgressLayout(resolved(pcs), 'ps2');
    final b = await gameProgressLayout(
      ResolvedSession(arms, '/media/game.chd', 'b' * 64, {}),
      'ps2',
    );
    expect(
      (await a.target('save/slot1.ps2')).path,
      (await b.target('save/slot1.ps2')).path,
    );
    expect(a.areas.last.path, isNot(b.areas.last.path));
    expect(a.areas.last.id, isNot(b.areas.last.id));
    final other = await emulator('PCSX2', profile: 'b' * 32);
    expect(other.root, isNot(pcs.root));
  });

  test(
    'DuckStation uses private HOME storage and preserves rendering preferences',
    () async {
      final e = await emulator('DuckStation'),
          ini = File('${(await emulator('DuckStation')).user}/settings.ini');
      await ini.writeAsString(
        '${await ini.readAsString()}\n[GPU]\nResolutionScale=3\n',
      );
      final game = LaunchGame(
        '42',
        'Title',
        'psx',
        'DuckStation',
        '/media/-title.chd',
        2,
        0,
        target: ControllerTarget.psx,
      );
      final args = await EmulatorAdapter.forName(e.name)
          .prepare(e, game, game.rom, 0);
      expect(args.sublist(args.length - 2), ['--', game.rom]);
      final text = await ini.readAsString();
      expect(text, contains('ResolutionScale=3'));
      expect(text, contains('${e.root}/games/42/cards'));
      expect(text, contains('Cross = SDL-0/A'));
      expect(
        targetBindings(ControllerTarget.psx, WiiMode.upright).keys,
        containsAll(['Cross', 'Circle', 'Square', 'Triangle']),
      );
      expect(
        targetBindings(ControllerTarget.ps2, WiiMode.upright).keys,
        containsAll(['L3', 'R3', 'L2', 'R2']),
      );
      expect(
        targetBindings(ControllerTarget.psx, WiiMode.upright),
        isNot(contains('PS')),
      );
    },
  );

  test('BIOS provisioning verifies checksum, reuses the configured file and isolates platforms', () async {
    final e = await emulator('DuckStation'),
        api = _Firmware(List.filled(512 * 1024, 4));
    addTearDown(api.close);
    await ensurePlayStationFirmware(
      resolved(e),
      23,
      api,
      DownloadCancellation(),
      (_) {},
    );
    expect(api.downloads, 1);
    await ensurePlayStationFirmware(
      resolved(e),
      23,
      api,
      DownloadCancellation(),
      (_) {},
    );
    expect(api.reads, 1);
    expect(api.downloads, 1);
    final ps2 = await emulator('PCSX2');
    await expectLater(
      ensurePlayStationFirmware(
        resolved(ps2),
        10,
        api,
        DownloadCancellation(),
        (_) {},
      ),
      throwsStateError,
    );
    expect(await File('${ps2.root}/system/bios.bin').exists(), false);
  });

  test('bad or cancelled BIOS transfers never publish and retain an existing invalid BIOS', () async {
    final e = await emulator('DuckStation'),
        api = _Firmware(List.filled(512 * 1024, 8))..checksum = '0' * 32;
    addTearDown(api.close);
    await expectLater(
      ensurePlayStationFirmware(
        resolved(e),
        23,
        api,
        DownloadCancellation(),
        (_) {},
      ),
      throwsStateError,
    );
    final bios = File('${e.root}/system/bios.bin');
    expect(await bios.exists(), false);
    final cancel = DownloadCancellation()..cancel();
    await expectLater(
      ensurePlayStationFirmware(resolved(e), 23, api, cancel, (_) {}),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(await bios.exists(), false);
    await bios.writeAsBytes([1, 2, 3]);
    await expectLater(
      ensurePlayStationFirmware(
        resolved(e),
        23,
        api,
        DownloadCancellation(),
        (_) {},
      ),
      throwsStateError,
    );
    expect(await bios.readAsBytes(), [1, 2, 3]);
  });

  test('PS1 whole cards export/readback/restore and reject truncated or foreign save containers', () async {
    final e = await emulator('DuckStation'),
        layout = await gameProgressLayout(resolved(e), 'psx');
    final api = SaveServer();
    addTearDown(api.close);
    final g = CloudGame(
      server: serverId,
      profile: profileId,
      user: 3,
      rom: 42,
      client: api,
      layout: layout,
    );
    final c = CloudSaves(root, notice: (_, __) {}), store = c.store(g);
    final original = await card((await layout.target('save/card1.mcd')).path);
    await c.sync(g);
    expect(api.records.values.single.name, endsWith('.mcd'));
    expect((await store.state())['pending'], false);
    final before = await store.capture(),
        exported = await store.exportNative(before);
    try {
      final imported = await store.importNative(exported.file);
      await original.delete();
      await store.restore(imported, {});
      expect((await store.capture()).ordinaryDigest, before.ordinaryDigest);
    } finally {
      await exported.close();
    }
    final invalid = File('${root.path}/foreign.sav');
    await invalid.writeAsBytes(List.filled(128 * 1024, 0));
    await expectLater(store.importNative(invalid), throwsFormatException);
    await invalid.writeAsBytes([0x4d, 0x43]);
    await expectLater(store.importNative(invalid), throwsFormatException);
    expect((await store.capture()).ordinaryDigest, before.ordinaryDigest);
  });

  test('PS2 whole-card ZIPs work in both emulators without importing state groups or BIOS', () async {
    final e = await emulator('PCSX2'),
        layout = await gameProgressLayout(resolved(e), 'ps2');
    final store = ProgressStore(
      Directory('${root.path}/cloud'),
      layout,
      3,
      42,
      ownerRoot: root,
    );
    await card((await layout.target('save/slot1.ps2')).path, ps2: true);
    await card(
      (await layout.target('save/slot2.ps2')).path,
      ps2: true,
      marker: 19,
    );
    final before = await store.capture(),
        exported = await store.exportNative(before);
    try {
      expect(exported.extension, 'zip');
      final arms = await emulator('ARMSX2'),
          other = await gameProgressLayout(resolved(arms), 'ps2');
      final imported = await ProgressStore(
        Directory('${root.path}/other-cloud'),
        other,
        3,
        42,
        ownerRoot: root,
      ).importNative(exported.file);
      expect(imported.ordinaryDigest, before.ordinaryDigest);
      expect(imported.hasStates, false);
    } finally {
      await exported.close();
    }
    final invalid = await card('${root.path}/wrong.ps2');
    await expectLater(store.importNative(invalid), throwsFormatException);
    expect((await store.capture()).ordinaryDigest, before.ordinaryDigest);
  });

  test('switching PS2 engines retains one cloud card and each engine’s matching states', () async {
    final pcs = await emulator('PCSX2'), arms = await emulator('ARMSX2');
    final first = await gameProgressLayout(resolved(pcs), 'ps2');
    final second = await gameProgressLayout(
      ResolvedSession(arms, '/media/game.chd', 'b' * 64, {}),
      'ps2',
    );
    final api = SaveServer();
    addTearDown(api.close);
    CloudGame game(ProgressLayout layout) => CloudGame(
      server: serverId,
      profile: profileId,
      user: 3,
      rom: 42,
      client: api,
      layout: layout,
    );
    final cloud = CloudSaves(root, notice: (_, __) {});
    await cloud.beforePlay(game(first));
    await card((await first.target('save/slot1.ps2')).path, ps2: true);
    await (await first.target('${first.areas.last.id}/slot.p2s'))
        .writeAsBytes([1, 2, 3]);
    await cloud.afterPlay(game(first), 0);
    expect(api.records.values.single.name, endsWith('.ps2'));
    await cloud.beforePlay(game(second));
    expect(api.records, hasLength(1));
    expect((await cloud.store(game(second)).state())['pending'], false);
    expect(
      (await second.files()).keys.where((k) => k.startsWith('states-')),
      isEmpty,
    );
    await (await second.target('${second.areas.last.id}/slot.p2s'))
        .writeAsBytes([4, 5, 6]);
    await cloud.afterPlay(game(second), 0);
    final afterSwitch = await cloud
        .store(game(second))
        .capture(
          retained: await cloud
              .store(game(second))
              .load(
                (await cloud.store(game(second)).state())['snapshot'] as String,
              ),
        );
    expect(
      afterSwitch.entries.keys.where((k) => k.startsWith('states-')),
      containsAll([
        '${first.areas.last.id}/slot.p2s',
        '${second.areas.last.id}/slot.p2s',
      ]),
    );
    final versions = api.records.length;
    await cloud.sync(game(first));
    expect(api.records, hasLength(versions));
    expect((await cloud.store(game(first)).state())['pending'], false);
    expect(
      await (await first.target('${first.areas.last.id}/slot.p2s'))
          .readAsBytes(),
      [1, 2, 3],
    );
  });
}
