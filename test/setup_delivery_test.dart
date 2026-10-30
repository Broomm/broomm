@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/zip.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Map<String, String> assets;
  late ManagedEmulators manager;
  late Map<String, dynamic> recipe;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-setup-delivery-');
    final input = await Directory('${root.path}/source/Fake.app')
        .create(recursive: true);
    final executable = await File('${input.path}/app')
        .writeAsString('reviewed fixture');
    final hash = await progressFileHash(executable);
    final archive = File('${root.path}/fixture.zip');
    await ProgressZip.write(archive, input.parent, ['Fake.app/app']);
    recipe = {
      'url': 'https://provider.example/fixture.zip',
      'sha256': await progressFileHash(archive),
      'bytes': await archive.length(),
      'format': 'zip',
      'entry': 'Fake.app',
    };
    assets = {
      'assets/setup/tested-builds.json': jsonEncode({
        'builds': [
          {
            'id': 'dolphin',
            'name': 'Dolphin',
            'version': 'fixture',
            'host': 'macos-arm64',
            'bundle': 'Fake.app',
            'executable': 'app',
            'sha256': hash,
            'sdl': 3,
            'native': {},
          },
        ],
      }),
      'assets/setup/dolphin.integrity.json': jsonEncode({
        'files': {'app': hash},
        'links': {},
      }),
      'assets/setup/dolphin.symbols': 'fixture symbols',
      'assets/setup/setup.json': jsonEncode({
        'schema_version': 2,
        'host': 'macos-arm64',
        'launchers': {
          'dolphin': {'source': recipe},
        },
      }),
    };
    manager = ManagedEmulators(
      Directory('${root.path}/data'),
      asset: (p) async => assets[p]!,
    );
    await manager.load();
  });
  tearDown(() async {
    manager.dispose();
    await root.delete(recursive: true);
  });
  Future<SetupPlan> localPlan() async {
    final local = {...recipe}..remove('url');
    local['file'] = 'fixture.zip';
    final json = File('${root.path}/setup.json');
    await json.writeAsString(
      jsonEncode({
        'schema_version': 2,
        'host': 'macos-arm64',
        'launchers': {
          'dolphin': {'source': local},
        },
      }),
    );
    return manager.readPlan(file: json.path);
  }

  test('bundled default reviews without project paths or writes; a compatible archive import installs and restarts independently of its source', () async {
    final review = await manager.readPlan();
    expect(manager.project, isNull);
    expect(
      review.items.single.describe(review.items.single.source),
      'https://provider.example/fixture.zip',
    );
    expect(await manager.data.exists(), false);
    final plan = await localPlan();
    await manager.install(plan);
    expect(manager.error, isNull, reason: manager.error);
    expect(manager.ready('Dolphin'), true);
    await File('${root.path}/fixture.zip').delete();
    await manager.install(
      review,
    ); // Recognized installed build needs no download.
    expect(manager.error, isNull, reason: manager.error);
    final second = ManagedEmulators(manager.data, asset: manager.asset);
    await second.load();
    expect(second.ready('Dolphin'), true);
    second.dispose();
    expect(
      (await manager.root.list().toList()).where(
        (e) => e.path.contains('.packages-'),
      ),
      isEmpty,
    );
  });
  test('shipping Ryubing setup needs no companion file or checkout and still accepts the previous reviewed pack', () async {
    final data = Directory('${root.path}/packaged-data');
    final shipping = ManagedEmulators(
      data,
      asset: (p) => File(p).readAsString(),
    );
    addTearDown(shipping.dispose);
    final current = await shipping.readPlan(only: {'ryubing'});
    expect(shipping.project, isNull);
    expect(current.items.single.downloads.values.single.url, isNotNull);
    expect(current.items.single.downloads.values.single.file, isNull);
    final previous =
        current.items.single.build.compatibleSetupPackages['source']!.single;
    final legacy = await File('${root.path}/legacy.json').writeAsString(
      jsonEncode({
        'schema_version': 2,
        'host': 'macos-arm64',
        'launchers': {
          'ryubing': {
            'source': {
              'file': previous.file,
              'sha256': previous.sha256,
              'bytes': previous.bytes,
              'format': previous.format,
              'entry': previous.entry,
            },
          },
        },
      }),
    );
    final imported = await shipping.readPlan(
      file: legacy.path,
      only: {'ryubing'},
    );
    expect(imported.items.single.downloads.values.single.file, previous.file);
    expect(await data.exists(), false);
  });
  test('unreviewed package content and executable preparation cannot be authorized by an imported JSON', () async {
    final file = File('${root.path}/invalid.json');
    for (final change in [
      {'sha256': '0' * 64},
      {'entry': 'Other.app'},
      {'prepare': 'macos-adhoc'},
      {'prepare': 'macos-dolphin'},
      {'command': 'anything'},
    ]) {
      await file.writeAsString(
        jsonEncode({
          'schema_version': 2,
          'host': 'macos-arm64',
          'launchers': {
            'dolphin': {
              'source': {...recipe, ...change},
            },
          },
        }),
      );
      await expectLater(
        manager.readPlan(file: file.path),
        throwsFormatException,
      );
    }
    expect(await manager.data.exists(), false);
  });
  test('shipping setup needs only HTTPS downloads and retains exact legacy core-slot compatibility', () async {
    final data = Directory('${root.path}/shipping-setup');
    final shipping = ManagedEmulators(
      data,
      asset: (p) => File(p).readAsString(),
    );
    addTearDown(shipping.dispose);
    final plan = await shipping.readPlan(only: {'dolphin', 'retroarch'});
    final dolphin = plan.items.firstWhere((i) => i.build.id == 'dolphin');
    expect(dolphin.downloads.values.single.file, isNull);
    expect(dolphin.downloads.values.single.prepare, 'macos-dolphin');
    final retroarch = plan.items.firstWhere((i) => i.build.id == 'retroarch');
    expect(
      retroarch.downloads.values.where((p) => p.url != null),
      hasLength(16),
    );
    expect(retroarch.downloads.values.every((p) => p.file == null), true);
    final all = await shipping.readPlan();
    expect(all.items, hasLength(13));
    expect(
      all.items
          .expand((i) => i.downloads.values)
          .every((p) => p.url != null && p.file == null),
      true,
    );
    final json =
        jsonDecode(await File('assets/setup/setup.json').readAsString()) as Map;
    final legacy = await File('${root.path}/legacy-cores.json').writeAsString(
      jsonEncode({
        'schema_version': 2,
        'host': 'macos-arm64',
        'launchers': {
          'retroarch': {
            'source': json['launchers']['retroarch']['source'],
            'core':
                jsonDecode(
                      await File('assets/setup/tested-builds.json')
                          .readAsString(),
                    )['builds']
                    .firstWhere(
                      (b) => b['id'] == 'retroarch',
                    )['compatible_setup_packages']['core']
                    .single,
          },
        },
      }),
    );
    final previous = await shipping.readPlan(
      file: legacy.path,
      only: {'retroarch'},
    );
    expect(
      previous.items.single.downloads[previous.items.single.core]!.file,
      isNotNull,
    );
    final invalid = jsonDecode(await legacy.readAsString()) as Map;
    invalid['launchers']['retroarch']['cores'] = {
      'mgba': invalid['launchers']['retroarch']['core'],
    };
    await legacy.writeAsString(jsonEncode(invalid));
    await expectLater(
      shipping.readPlan(file: legacy.path),
      throwsFormatException,
    );
    expect(await data.exists(), false);
  });
  test('a new default delivery preserves only explicitly reviewed older source archives', () async {
    final metadata =
        jsonDecode(assets['assets/setup/tested-builds.json']!) as Map;
    (metadata['builds'] as List).single['compatible_setup_packages'] = {
      'source': [recipe],
    };
    assets['assets/setup/tested-builds.json'] = jsonEncode(metadata);
    assets['assets/setup/setup.json'] = jsonEncode({
      'schema_version': 2,
      'host': 'macos-arm64',
      'launchers': {
        'dolphin': {
          'source': {...recipe, 'sha256': '1' * 64, 'bytes': 999},
        },
      },
    });
    manager.dispose();
    manager = ManagedEmulators(
      Directory('${root.path}/data'),
      asset: (p) async => assets[p]!,
    );
    final old = await localPlan();
    await manager.install(old);
    expect(manager.error, isNull, reason: manager.error);
    expect(manager.ready('Dolphin'), true);
    final unsafe = File('${root.path}/unsafe.json');
    final fileRecipe = {...recipe}..remove('url');
    fileRecipe['file'] = 'fixture.zip';
    await unsafe.writeAsString(
      jsonEncode({
        'schema_version': 2,
        'host': 'macos-arm64',
        'launchers': {
          'dolphin': {
            'source': {...fileRecipe, 'sha256': '2' * 64},
          },
        },
      }),
    );
    await expectLater(
      manager.readPlan(file: unsafe.path),
      throwsFormatException,
    );
    await unsafe.writeAsString(
      jsonEncode({
        'schema_version': 2,
        'host': 'macos-arm64',
        'launchers': {
          'dolphin': {
            'source': fileRecipe,
            'compatible_setup_packages': {
              'source': [fileRecipe],
            },
          },
        },
      }),
    );
    await expectLater(
      manager.readPlan(file: unsafe.path),
      throwsFormatException,
    );
  });
  test('altered archive and a held production session lease block publication while preserving progress and permit retry', () async {
    final plan = await localPlan();
    await manager.data.create(recursive: true);
    final save = await File('${manager.data.path}/keep.sav')
        .writeAsString('progress');
    final lease = await SessionLease.acquire(manager.data);
    await manager.install(plan);
    expect(manager.error, isNotNull);
    expect(manager.ready('Dolphin'), false);
    await lease.release();
    final archive = File('${root.path}/fixture.zip'),
        good = await File('${root.path}/fixture.zip').readAsBytes();
    await archive.writeAsBytes([...good]..[0] = 0);
    await manager.install(plan);
    expect(manager.error, isNotNull);
    expect(manager.ready('Dolphin'), false);
    expect(await save.readAsString(), 'progress');
    await archive.writeAsBytes(good);
    await manager.install(plan);
    expect(manager.error, isNull, reason: manager.error);
    expect(manager.ready('Dolphin'), true);
    expect(await save.readAsString(), 'progress');
  });
  test('reusing an installed frontend verifies its required base core and preserves changed or missing core data', () async {
    final core = await File('${root.path}/core.dylib')
        .writeAsString('pinned native core');
    final builds =
        jsonDecode(assets['assets/setup/tested-builds.json']!) as Map;
    final record = (builds['builds'] as List).single as Map;
    record['id'] = 'retroarch';
    record['name'] = 'RetroArch';
    record['core_sha256'] = await progressFileHash(core);
    assets['assets/setup/tested-builds.json'] = jsonEncode(builds);
    assets['assets/setup/retroarch-cores.json'] = jsonEncode({'cores': []});
    assets['assets/setup/retroarch.integrity.json'] =
        assets['assets/setup/dolphin.integrity.json']!;
    assets['assets/setup/retroarch.symbols'] = 'fixture symbols';
    final local = {...recipe}..remove('url');
    local['file'] = 'fixture.zip';
    assets['assets/setup/setup.json'] = jsonEncode({
      'schema_version': 2,
      'host': 'macos-arm64',
      'launchers': {
        'retroarch': {'source': recipe, 'core': core.path},
      },
    });
    final file = await File('${root.path}/setup.json').writeAsString(
      jsonEncode({
        'schema_version': 2,
        'host': 'macos-arm64',
        'launchers': {
          'retroarch': {'source': local, 'core': core.path},
        },
      }),
    );
    manager.dispose();
    manager = ManagedEmulators(
      Directory('${root.path}/data'),
      asset: (p) async => assets[p]!,
    );
    final plan = await manager.readPlan(file: file.path);
    await manager.install(plan);
    expect(manager.error, isNull, reason: manager.error);
    final installed = File(
      '${manager.root.path}/retroarch/${record['sha256']}/snes9x_libretro.dylib',
    );
    await manager.install(await manager.readPlan());
    expect(manager.error, isNull);
    final save = await File('${manager.data.path}/keep.sav')
        .writeAsString('progress');
    await installed.writeAsString('changed native core');
    await manager.install(plan);
    expect(manager.error, isNotNull);
    expect(await installed.readAsString(), 'changed native core');
    await installed.delete();
    await manager.install(plan);
    expect(manager.error, isNotNull);
    expect(await installed.exists(), false);
    expect(await save.readAsString(), 'progress');
  });
  test('abnormal signing retains private staging; cancellation before signing never starts the writer or removes earlier recovery data', () async {
    recipe['prepare'] = 'macos-adhoc';
    assets['assets/setup/setup.json'] = jsonEncode({
      'schema_version': 2,
      'host': 'macos-arm64',
      'launchers': {
        'dolphin': {'source': recipe},
      },
    });
    final plan = await localPlan();
    await manager.data.create(recursive: true);
    final save = await File('${manager.data.path}/keep.sav')
        .writeAsString('progress');
    // The reviewed fixture is deliberately not a signable native app. A real
    // provider archive changed in this way would fail its hash before this point.
    await manager.install(plan);
    expect(manager.error, contains('private staging was kept'));
    Future<List<FileSystemEntity>> stages() async =>
        (await manager.root.list().toList())
            .where((e) => e.path.contains('.packages-'))
            .toList();
    expect(await stages(), hasLength(1));
    var cancelled = false;
    void cancelBeforeSigning() {
      if (!cancelled && manager.phase.contains('Preparing reviewed macOS')) {
        cancelled = true;
        manager.cancel();
      }
    }

    manager.addListener(cancelBeforeSigning);
    await manager.install(plan);
    manager.removeListener(cancelBeforeSigning);
    expect(cancelled, true);
    expect(manager.error, contains('Setup cancelled'));
    expect(await stages(), hasLength(1));
    expect(await save.readAsString(), 'progress');
    expect(manager.installed, isEmpty);
  });
}
