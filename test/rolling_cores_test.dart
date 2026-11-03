@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/setup/package.dart';
import 'package:flutter_test/flutter_test.dart';

class ProviderCore extends SetupDownloads {
  ProviderCore(super.data, this.library);
  final File library;
  bool fail = false;
  final requested = <String>[];
  @override
  Future<String> prepare(
    SetupPackage package,
    Directory working,
    DownloadCancellation cancellation,
    void Function(String, double?) progress, {
    Directory? localRoot,
  }) async {
    requested.add(package.entry);
    if (fail) throw StateError('controlled provider failure');
    return library.path;
  }
}

void main() {
  late Directory data, fixture;
  late ManagedEmulators manager;
  late ProviderCore provider;
  late Map<String, String> assets;
  const profile = 'a123456789abcdef0123456789abcdef';
  final elf = List<int>.filled(64, 0)
    ..setRange(0, 6, [0x7f, 69, 76, 70, 2, 1])
    ..[16] = 3
    ..[18] = 62;
  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('broomm-rolling-core-');
    data = Directory('${fixture.path}/data');
    final source = await Directory('${fixture.path}/AppDir').create();
    final app = await File('${source.path}/app').writeAsBytes(elf);
    provider = ProviderCore(
      data,
      await File('${fixture.path}/core.so').writeAsBytes([...elf, 1]),
    );
    final package = {
      'url': 'https://buildbot.libretro.com/nightly/linux/x86_64/latest/mesen_libretro.so.zip',
      'sha256': '0' * 64,
      'bytes': 1,
      'format': 'zip',
      'entry': 'mesen_libretro.so',
      'rolling': true,
    };
    assets = {
      'assets/setup/linux-x64/tested-builds.json': jsonEncode({
        'builds': [
          {
            'id': 'retroarch',
            'name': 'RetroArch',
            'host': 'linux-x64',
            'version': 'fixture',
            'bundle': 'AppDir',
            'executable': 'app',
            'sha256': await progressFileHash(app),
            'sdl': 3,
            'native': {},
            'integrity_asset':
                'assets/setup/linux-x64/retroarch.integrity.json',
          },
        ],
      }),
      'assets/setup/linux-x64/retroarch.integrity.json': jsonEncode({
        'files': {'app': await progressFileHash(app)},
        'links': {},
      }),
      'assets/setup/linux-x64/retroarch.symbols': '',
      'assets/setup/linux-x64/retroarch-cores.json': jsonEncode({
        'cores': [
          {
            'id': 'mesen',
            'sha256': '0' * 64,
            'host': 'linux-x64',
            'source_url': package['url'],
            'firmware': {},
          },
        ],
      }),
      'assets/setup/linux-x64/setup.json': jsonEncode({
        'schema_version': 2,
        'host': 'linux-x64',
        'launchers': {
          'retroarch': {
            'source': source.path,
            'cores': {'mesen': package},
          },
        },
      }),
    };
    manager = ManagedEmulators(
      data,
      hostOverride: 'linux-x64',
      asset: (p) async => assets[p]!,
      downloads: provider,
    );
  });
  tearDown(() async {
    manager.dispose();
    await fixture.delete(recursive: true);
  });
  Future<void> install() async {
    await manager.install(await manager.readPlan());
    expect(manager.error, isNull, reason: manager.error);
  }

  LaunchGame game() => const LaunchGame(
    '42',
    'Fixture',
    'NES',
    'RetroArch',
    '/fixture/game.nes',
    2,
    0,
    target: ControllerTarget.nes,
    retroCore: 'mesen',
  );

  test('setting up a second platform retains the shared executable and downloads only its core', () async {
    final j = jsonDecode(assets['assets/setup/linux-x64/setup.json']!) as Map;
    final r = (j['launchers'] as Map)['retroarch'] as Map;
    final next = {...(r['cores'] as Map)['mesen'] as Map}
      ..['url'] = 'https://buildbot.libretro.com/nightly/linux/x86_64/latest/gambatte_libretro.so.zip'
      ..['entry'] = 'gambatte_libretro.so';
    (r['cores'] as Map)['gambatte'] = next;
    assets['assets/setup/linux-x64/setup.json'] = jsonEncode(j);
    final c = jsonDecode(
      assets['assets/setup/linux-x64/retroarch-cores.json']!,
    ) as Map;
    (c['cores'] as List).add({
      ...((c['cores'] as List).first as Map),
      'id': 'gambatte',
      'source_url': next['url'],
    });
    assets['assets/setup/linux-x64/retroarch-cores.json'] = jsonEncode(c);
    await manager.install((await manager.readPlan()).forPlatform('nes'));
    expect(manager.error, isNull, reason: manager.error);
    expect(manager.installedCores, {'mesen'});
    expect(manager.readyFor('RetroArch', 'gb'), isFalse);
    final b = manager.buildFor('RetroArch')!;
    final executable = File(
      '${manager.root.path}/retroarch/${b.hash}/${b.bundle}/${b.executable}',
    );
    final before = await executable.stat();
    await manager.install((await manager.readPlan()).forPlatform('gb'));
    expect(manager.error, isNull, reason: manager.error);
    expect(manager.installedCores, {'mesen', 'gambatte'});
    expect(manager.readyFor('RetroArch', 'gb'), isTrue);
    expect((await executable.stat()).modified, before.modified);
    expect(provider.requested, ['mesen_libretro.so', 'gambatte_libretro.so']);
  });
  test('current provider core is selected by its actual hash and survives restart without networking', () async {
    await install();
    final actual = await progressFileHash(provider.library);
    expect(manager.installedCoreBuilds['mesen']!['sha256'], actual);
    final restarted = ManagedEmulators(
      data,
      hostOverride: 'linux-x64',
      asset: manager.asset,
    );
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.error, isNull);
    final resolved = await restarted.resolve(game(), profile);
    expect(resolved.coreHash, actual);
    expect(resolved.emulator.retroStateDirectory, contains(actual));
  });
  test('explicit core update keeps native saves and gives states a new build directory', () async {
    await install();
    final before = await manager.resolve(game(), profile);
    final save = File(
      '${before.emulator.root}/core-data/mesen/42/saves/game.srm',
    );
    await save.parent.create(recursive: true);
    await save.writeAsString('progress');
    await provider.library.writeAsBytes([...elf, 2]);
    await install();
    final after = await manager.resolve(game(), profile);
    expect(after.coreHash, isNot(before.coreHash));
    expect(
      after.emulator.retroStateDirectory,
      isNot(before.emulator.retroStateDirectory),
    );
    expect(await save.readAsString(), 'progress');
    expect(await File(before.emulator.core!).exists(), isTrue);
  });
  test(
    'failed new core transfer leaves the selected previous core usable',
    () async {
      await install();
      final before = await manager.resolve(game(), profile);
      provider.fail = true;
      await manager.install(await manager.readPlan());
      expect(manager.error, isNotNull);
      final after = await manager.resolve(game(), profile);
      expect(after.coreHash, before.coreHash);
      expect(after.emulator.core, before.emulator.core);
    },
  );
}
