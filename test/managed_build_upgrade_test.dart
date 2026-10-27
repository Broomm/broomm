@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/zip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ManagedEmulators manager;
  late Map<String, String> assets;
  late Map<String, dynamic> current, previous;
  late File legacySetup, currentExecutable;
  const profile = 'a123456789abcdef0123456789abcdef';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-build-upgrade-');
    Future<Map<String, dynamic>> build(String version) async {
      final app = await Directory('${root.path}/$version/Fake.app')
          .create(recursive: true);
      final executable = await File('${app.path}/app').writeAsString(version);
      return {
        'id': 'retroarch',
        'name': 'RetroArch',
        'host': 'macos-arm64',
        'version': version,
        'bundle': 'Fake.app',
        'executable': 'app',
        'sha256': await progressFileHash(executable),
        'sdl': 3,
        'native': <String, String>{},
      };
    }

    current = await build('current');
    previous = await build('previous');
    currentExecutable = File('${root.path}/current/Fake.app/app');
    final archive = File('${root.path}/previous.zip');
    await ProgressZip.write(archive, Directory('${root.path}/previous'), [
      'Fake.app/app',
    ]);
    previous['integrity_asset'] =
        'assets/setup/retroarch-previous.integrity.json';
    previous['source_package'] = {
      'file': 'previous.zip',
      'sha256': await progressFileHash(archive),
      'bytes': await archive.length(),
      'format': 'zip',
      'entry': 'Fake.app',
    };
    assets = {
      'assets/setup/tested-builds.json': jsonEncode({
        'builds': [current],
        'previous_builds': [previous],
      }),
      'assets/setup/retroarch.integrity.json': jsonEncode({
        'files': {'app': current['sha256']},
        'links': {},
      }),
      'assets/setup/retroarch-previous.integrity.json': jsonEncode({
        'files': {'app': previous['sha256']},
        'links': {},
      }),
      'assets/setup/retroarch.symbols': '',
      'assets/setup/retroarch-cores.json': jsonEncode({'cores': []}),
      'assets/setup/setup.json': jsonEncode({
        'schema_version': 2,
        'host': 'macos-arm64',
        'launchers': {
          'retroarch': {'source': '${root.path}/current/Fake.app'},
        },
      }),
    };
    legacySetup = await File('${root.path}/legacy.json').writeAsString(
      jsonEncode({
        'schema_version': 2,
        'host': 'macos-arm64',
        'launchers': {
          'retroarch': {'source': previous['source_package']},
        },
      }),
    );
    manager = ManagedEmulators(
      Directory('${root.path}/data'),
      asset: (path) async => assets[path]!,
    );
    await manager.install(await manager.readPlan(file: legacySetup.path));
    expect(manager.error, isNull, reason: manager.error);
    final runtime = await manager.resolveConfiguration('RetroArch', profile);
    await File('${runtime.emulator.root}/saves/progress.srm')
        .writeAsString('keep save');
    await File('${runtime.emulator.root}/states/progress.state')
        .writeAsString('keep state');
  });
  tearDown(() async {
    manager.dispose();
    await root.delete(recursive: true);
  });

  test('previous installs remain usable until explicit setup selects the release, preserving private progress', () async {
    final restarted = ManagedEmulators(manager.data, asset: manager.asset);
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.error, isNull);
    expect(restarted.ready('RetroArch'), true);
    final old = await restarted.resolveConfiguration('RetroArch', profile);
    expect(old.executableHash, previous['sha256']);
    final plan = await restarted.readPlan();
    expect(plan.items.single.build.hash, current['sha256']);
    expect(restarted.buildFor('RetroArch')!.hash, previous['sha256']);
    await restarted.install(plan);
    expect(restarted.error, isNull, reason: restarted.error);
    final updated = await restarted.resolveConfiguration('RetroArch', profile);
    expect(updated.executableHash, current['sha256']);
    expect(updated.emulator.root, old.emulator.root);
    expect(
      await File('${updated.emulator.root}/saves/progress.srm').readAsString(),
      'keep save',
    );
    expect(
      await File('${updated.emulator.root}/states/progress.state')
          .readAsString(),
      'keep state',
    );
    expect(await File(old.emulator.executable).readAsString(), 'previous');
    final imported = await restarted.readPlan(file: legacySetup.path);
    expect(imported.items.single.build.hash, previous['sha256']);
    expect(restarted.buildFor('RetroArch')!.hash, current['sha256']);
  });

  test('failed release verification keeps the selected previous build and its progress usable', () async {
    await currentExecutable.writeAsString('changed untrusted executable');
    await manager.install(await manager.readPlan());
    expect(manager.error, isNotNull);
    final restarted = ManagedEmulators(manager.data, asset: manager.asset);
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.error, isNull);
    final old = await restarted.resolveConfiguration('RetroArch', profile);
    expect(old.executableHash, previous['sha256']);
    expect(
      await File('${old.emulator.root}/saves/progress.srm').readAsString(),
      'keep save',
    );
    expect(
      await Directory('${manager.root.path}/retroarch/${current['sha256']}')
          .exists(),
      false,
    );
  });

  test('unrecognized selected builds remain errors and are never migrated or discarded', () async {
    final selection = File('${manager.root.path}/selected.json');
    final value = jsonDecode(await selection.readAsString()) as Map;
    value['selected']['retroarch'] = 'f' * 64;
    await selection.writeAsString(jsonEncode(value), flush: true);
    final original = await selection.readAsString();
    final restarted = ManagedEmulators(manager.data, asset: manager.asset);
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.error, isNotNull);
    expect(await selection.readAsString(), original);
    expect(
      await File(
        '${manager.data.path}/profiles/$profile/emulators/retroarch/saves/progress.srm',
      ).readAsString(),
      'keep save',
    );
  });
}
