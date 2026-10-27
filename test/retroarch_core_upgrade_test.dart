@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ManagedEmulators manager;
  late Map<String, String> assets;
  late Map current, previous;
  late File nextCore;
  late String frontend;
  const profile = 'a123456789abcdef0123456789abcdef';
  const game = LaunchGame(
    '42',
    'Game',
    'GB',
    'RetroArch',
    '/content/Title.gb',
    1,
    0,
    target: ControllerTarget.gameboy,
    retroCore: 'gambatte',
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-core-upgrade-');
    final app = await Directory('${root.path}/Fake.app').create();
    frontend = await progressFileHash(
      await File('${app.path}/app').writeAsString('frontend'),
    );
    Future<Map> core(String version) async {
      final file = await File('${root.path}/$version.dylib')
          .writeAsString(version);
      return <String, dynamic>{
        'id': 'gambatte',
        'sha256': await progressFileHash(file),
        'version': version,
      };
    }

    current = await core('current')
      ..['isolated_states'] = true;
    previous = await core('previous');
    nextCore = File('${root.path}/current.dylib');
    assets = {
      'assets/setup/tested-builds.json': jsonEncode({
        'builds': [
          {
            'id': 'retroarch',
            'name': 'RetroArch',
            'version': 'fixture',
            'host': 'macos-arm64',
            'bundle': 'Fake.app',
            'executable': 'app',
            'sha256': frontend,
            'sdl': 3,
            'retro_native_state_names': true,
            'native': {},
          },
        ],
      }),
      'assets/setup/retroarch.integrity.json': jsonEncode({
        'files': {'app': frontend},
        'links': {},
      }),
      'assets/setup/retroarch.symbols': '',
      'assets/setup/retroarch-cores.json': jsonEncode({
        'cores': [current],
        'previous_cores': [previous],
      }),
      'assets/setup/setup.json': jsonEncode({
        'schema_version': 1,
        'host': 'macos-arm64',
        'launchers': {
          'retroarch': {
            'source': app.path,
            'cores': {'gambatte': nextCore.path},
          },
        },
      }),
    };
    manager = ManagedEmulators(
      Directory('${root.path}/data'),
      asset: (p) async => assets[p]!,
    );
    final legacy = await File('${root.path}/legacy.json').writeAsString(
      jsonEncode({
        'schema_version': 1,
        'host': 'macos-arm64',
        'launchers': {
          'retroarch': {
            'source': app.path,
            'cores': {'gambatte': '${root.path}/previous.dylib'},
          },
        },
      }),
    );
    await manager.install(await manager.readPlan(file: legacy.path));
    expect(manager.error, isNull, reason: manager.error);
    final session = await manager.resolve(game, profile);
    await const RetroArchAdapter().prepare(
      session.emulator,
      game,
      game.rom,
      9999,
    );
    final layout = await gameProgressLayout(session, 'gb');
    await (await layout.target('save/game.srm'))
        .writeAsString('ordinary progress');
    final state = layout.areas.singleWhere((a) => a.id.startsWith('states-'));
    await (await layout.target('${state.id}/game'))
        .writeAsString('previous state');
  });
  tearDown(() async {
    manager.dispose();
    await root.delete(recursive: true);
  });

  test('startup keeps the installed previous core; explicit upgrade shares saves and separates native state files and fingerprints', () async {
    final restarted = ManagedEmulators(manager.data, asset: manager.asset);
    addTearDown(restarted.dispose);
    final before = await restarted.resolve(game, profile);
    expect(restarted.readyFor('RetroArch', 'gb'), true);
    expect(before.coreHash, previous['sha256']);
    final oldLayout = await gameProgressLayout(before, 'gb');
    final plan = await restarted.readPlan();
    expect(
      (await restarted.resolve(game, profile)).coreHash,
      previous['sha256'],
    );
    await restarted.install(plan);
    expect(restarted.error, isNull, reason: restarted.error);
    final after = await restarted.resolve(game, profile);
    expect(after.coreHash, current['sha256']);
    await const RetroArchAdapter().prepare(
      after.emulator,
      game,
      game.rom,
      9999,
    );
    final updated = await gameProgressLayout(after, 'gb');
    expect(
      await (await updated.target('save/game.srm')).readAsString(),
      'ordinary progress',
    );
    final oldState = oldLayout.areas.singleWhere(
      (a) => a.id.startsWith('states-'),
    );
    final newState = updated.areas.singleWhere(
      (a) => a.id.startsWith('states-'),
    );
    expect(newState.id, isNot(oldState.id));
    expect(newState.path, isNot(oldState.path));
    expect(
      (await updated.files()).keys.any((k) => k.startsWith('states-')),
      false,
    );
    expect(
      await (await oldLayout.target('${oldState.id}/game')).readAsString(),
      'previous state',
    );
    await (await updated.target('${newState.id}/game'))
        .writeAsString('new state');
    final config = await File('${after.emulator.root}/retroarch.cfg')
        .readAsString();
    expect(
      config,
      contains(
        'savestate_directory = ${jsonEncode('${after.emulator.root}/${newState.path}')}',
      ),
    );
    expect(await File(before.emulator.core!).readAsString(), 'previous');
    await restarted.remove(restarted.buildFor('RetroArch')!);
    expect(restarted.error, isNull, reason: restarted.error);
    expect(
      await (await oldLayout.target('${oldState.id}/game')).readAsString(),
      'previous state',
    );
    expect(
      await (await updated.target('${newState.id}/game')).readAsString(),
      'new state',
    );
  });

  test('an unrecognized new core cannot replace the usable previous core or its ordinary progress', () async {
    await nextCore.writeAsString('unrecognized binary');
    await manager.install(await manager.readPlan());
    expect(manager.error, isNotNull);
    final resolved = await manager.resolve(game, profile);
    expect(resolved.coreHash, previous['sha256']);
    final layout = await gameProgressLayout(resolved, 'gb');
    expect(
      await (await layout.target('save/game.srm')).readAsString(),
      'ordinary progress',
    );
    expect(await nextCore.readAsString(), 'unrecognized binary');
  });

  test('cancellation before core publication keeps the old selection and remains retryable', () async {
    var cancelled = false;
    void cancel() {
      if (!cancelled && manager.phase.startsWith('Installing RetroArch /')) {
        cancelled = true;
        manager.cancel();
      }
    }

    manager.addListener(cancel);
    await manager.install(await manager.readPlan());
    manager.removeListener(cancel);
    expect(manager.error, isNotNull);
    expect((await manager.resolve(game, profile)).coreHash, previous['sha256']);
    await manager.install(await manager.readPlan());
    expect(manager.error, isNull, reason: manager.error);
    expect((await manager.resolve(game, profile)).coreHash, current['sha256']);
  });
}
