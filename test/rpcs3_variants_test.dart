@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_model_test.dart' show FixtureRomm, settleModel;

void main() {
  late Directory root;
  late ManagedEmulators manager;
  late Map<String, String> assets;
  late SetupPlan plan;
  const profile = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-rpcs3-variants-');
    assets = {};
    final records = <Map<String, Object>>[], launchers = <String, Object>{};
    final firmware = File('${root.path}/firmware/sys/external/liblv2.sprx');
    await firmware.parent.create(recursive: true);
    await firmware.writeAsString('fixture firmware');
    for (final (id, name) in [
      ('rpcs3', 'RPCS3'),
      ('rpcs3-intel', 'RPCS3 Intel'),
    ]) {
      final file = File('${root.path}/source/$id/RPCS3.app/app');
      await file.parent.create(recursive: true);
      await file.writeAsString('fixture $id');
      final hash = await sha256File(file.path);
      records.add({
        'id': id,
        'name': name,
        'version': 'fixture',
        'host': 'macos-arm64',
        'bundle': 'RPCS3.app',
        'executable': 'app',
        'sha256': hash,
        'sdl': 3,
        'native': <String, String>{},
      });
      assets['assets/setup/$id.integrity.json'] = jsonEncode({
        'files': {'app': hash},
        'links': {},
      });
      assets['assets/setup/$id.symbols'] = 'fixture';
      launchers[id] = {
        'source': file.parent.path,
        'resources': {'ps3_firmware': firmware.parent.parent.parent.path},
      };
    }
    assets['assets/setup/tested-builds.json'] = jsonEncode({'builds': records});
    assets['assets/setup/setup.json'] = jsonEncode({
      'schema_version': 1,
      'host': 'macos-arm64',
      'launchers': launchers,
    });
    manager = ManagedEmulators(
      Directory('${root.path}/data'),
      asset: (p) async => assets[p]!,
    );
    plan = await manager.readPlan();
    await manager.install(plan);
    expect(manager.error, isNull, reason: manager.error);
  });
  tearDown(() async {
    if (!manager.disposed) manager.dispose();
    await root.delete(recursive: true);
  });
  LaunchGame game(String name) => LaunchGame(
    '42',
    'Game',
    'PlayStation 3',
    name,
    '${root.path}/game.iso',
    4,
    0,
  );

  test('separate releases share only the verified profile and preserve progress/preferences when switching architectures', () async {
    final lease = await SessionLease.acquire(manager.data);
    try {
      final arm = await manager.resolve(game('RPCS3'), profile);
      final save = File(
        '${arm.emulator.user}/dev_hdd0/home/00000001/savedata/BLUS30490SAVE/DATA',
      );
      await save.parent.create(recursive: true);
      await save.writeAsString('local progress');
      final config = File('${arm.emulator.user}/config.yml');
      await config.writeAsString('owner configured settings');
      final cache = File('${arm.home}/Library/Caches/rpcs3/arm-object');
      await cache.parent.create(recursive: true);
      await cache.writeAsString('retained ARM cache');
      final intel = await manager.resolve(game('RPCS3 Intel'), profile);
      expect(intel.emulator.executable, isNot(arm.emulator.executable));
      expect(intel.emulator.name, 'RPCS3');
      expect(intel.emulator.root, arm.emulator.root);
      expect(intel.emulator.user, arm.emulator.user);
      expect(intel.home, isNot(arm.home));
      expect(intel.emulator.cacheDirectory, endsWith('/cache-intel'));
      expect(await save.readAsString(), 'local progress');
      expect(await config.readAsString(), 'owner configured settings');
      expect(await cache.readAsString(), 'retained ARM cache');
      expect(
        await Link('${intel.home}/Library/Application Support/rpcs3')
            .resolveSymbolicLinks(),
        await Directory(arm.emulator.user).resolveSymbolicLinks(),
      );
      final other = await manager.resolve(
        game('RPCS3 Intel'),
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      expect(
        await File(
          '${other.emulator.user}/dev_hdd0/home/00000001/savedata/BLUS30490SAVE/DATA',
        ).exists(),
        false,
      );
    } finally {
      await lease.release();
    }
  });

  test('changed profile ownership and redirected Intel HOME fail without replacing native data', () async {
    final lease = await SessionLease.acquire(manager.data);
    try {
      final arm = await manager.resolve(game('RPCS3'), profile);
      final marker = File('${arm.emulator.root}/profile.json');
      final original = await marker.readAsString();
      await marker.writeAsString(
        jsonEncode({'version': 1, 'profile': profile, 'emulator': 'different'}),
      );
      await expectLater(
        manager.resolve(game('RPCS3 Intel'), profile),
        throwsStateError,
      );
      expect(await marker.readAsString(), contains('different'));
      await marker.writeAsString(original);
      final intel = await manager.resolve(game('RPCS3 Intel'), profile);
      final link = Link('${intel.home}/Library/Application Support/rpcs3');
      await link.delete();
      await link.create(root.path);
      await expectLater(
        manager.resolve(game('RPCS3 Intel'), profile),
        throwsStateError,
      );
      expect(await link.target(), root.path);
    } finally {
      await lease.release();
    }
  });

  test('PS3 defaults persist by variant and removing Intel retains the ARM choice and shared savedata', () async {
    final model = ShellModel(
      ShellStorage(manager.data),
      emulatorManager: manager,
      clientFactory: FixtureRomm.new,
    );
    await model.start();
    await model.addServer('https://server.example');
    await model.login('Player', 'fixture');
    await settleModel(model);
    const platform = RommPlatform(33, 'PlayStation 3', 'ps3', 1);
    model.platforms = [platform];
    final rom = RommGame(
      id: 42,
      name: 'Game',
      platformId: 33,
      platform: platform.name,
      platformSlug: 'ps3',
    );
    expect(platformEmulators(platform).map((e) => e.emulatorId), [
      'rpcs3',
      'rpcs3-intel',
    ]);
    expect(model.launchPlatform(rom)!.emulator, 'RPCS3');
    await model.setDefaultEmulator(platform, 'rpcs3-intel');
    expect(model.launchPlatform(rom)!.emulator, 'RPCS3 Intel');
    model.platforms = [];
    expect(
      model.launchPlatform(rom)!.emulator,
      'RPCS3 Intel',
      reason: 'A failed platform refresh cannot change a known installed game’s default',
    );
    model.platforms = [platform];
    expect(
      (await model.storage.load()).emulatorDefaults.values,
      contains('rpcs3-intel'),
    );
    final lease = await SessionLease.acquire(manager.data);
    late File save;
    try {
      final session = await manager.resolve(game('RPCS3 Intel'), profile);
      save = File('${session.emulator.user}/savedata-canary');
      await save.writeAsString('progress');
    } finally {
      await lease.release();
    }
    await manager.remove(manager.buildFor('RPCS3 Intel')!);
    expect(manager.error, isNull, reason: manager.error);
    expect(manager.ready('RPCS3'), true);
    expect(model.launchPlatform(rom)!.emulator, 'RPCS3');
    expect(await save.readAsString(), 'progress');
    model.dispose();
  });
}
