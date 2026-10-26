@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/managed_profile.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root, source;
  late ManagedEmulators manager;
  late TestedBuild build;
  late String digest;
  late Map<String, String> assets;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-managed-unit-');
    source = Directory('${root.path}/source/Fake.app');
    await source.create(recursive: true);
    await File('${source.path}/app').writeAsString('exact tested executable');
    digest = await sha256File('${source.path}/app');
    final record = {
      'id': 'dolphin',
      'name': 'Dolphin',
      'host': 'macos-arm64',
      'version': 'fixture',
      'bundle': 'Fake.app',
      'executable': 'app',
      'sha256': digest,
      'sdl': 3,
      'native': <String, String>{},
    };
    build = TestedBuild(record);
    assets = {
      'assets/setup/tested-builds.json': jsonEncode({
        'builds': [record],
      }),
      'assets/setup/dolphin.integrity.json': jsonEncode({
        'files': {'app': digest},
        'links': {},
      }),
      'assets/setup/dolphin.symbols': 'fixture symbol data',
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
  Future<SetupPlan> plan({Map<String, dynamic>? entry}) async {
    final f = File('${root.path}/setup.json');
    await f.writeAsString(
      jsonEncode({
        'schema_version': 1,
        'host': 'macos-arm64',
        'launchers': {
          'dolphin': entry ?? {'source': source.path},
        },
      }),
    );
    return manager.readPlan(file: f.path);
  }

  test('reading a plan has no install effect; explicit setup publishes verified binaries and restart records without touching the source', () async {
    final p = await plan();
    expect(await manager.root.exists(), false);
    await manager.install(p);
    expect(manager.error, isNull, reason: manager.error);
    expect(manager.ready('Dolphin'), true);
    final binary = File('${manager.root.path}/dolphin/$digest/Fake.app/app');
    expect(await binary.readAsString(), 'exact tested executable');
    expect(
      await File('${source.path}/app').readAsString(),
      'exact tested executable',
    );
    final second = ManagedEmulators(manager.data, asset: manager.asset);
    await second.load();
    expect(second.ready('Dolphin'), true);
    second.dispose();
    await manager.install(p);
    expect(manager.error, isNull);
  });
  test('changed binaries and escaping bundle links fail before publication and retain existing data for a later retry', () async {
    final p = await plan();
    await File('${source.path}/app').writeAsString('changed executable');
    await manager.install(p);
    expect(manager.error, isNotNull);
    expect(manager.ready('Dolphin'), false);
    await File('${source.path}/app').writeAsString('exact tested executable');
    await Link('${source.path}/outside').create(root.path);
    await manager.install(await plan());
    expect(manager.error, isNotNull);
    expect(manager.ready('Dolphin'), false);
    await Link('${source.path}/outside').delete();
    await manager.install(await plan());
    expect(manager.error, isNull);
    final canary = File('${manager.data.path}/preserved-save');
    await canary.writeAsString('local progress');
    await File('${manager.root.path}/dolphin/$digest/Fake.app/app')
        .writeAsString('manual replacement');
    await manager.install(await plan());
    expect(manager.error, isNotNull);
    expect(await canary.readAsString(), 'local progress');
    expect(
      await File('${manager.root.path}/dolphin/$digest/Fake.app/app')
          .readAsString(),
      'manual replacement',
    );
  });
  test('a live session lease excludes setup, cancellation cannot publish a partial emulator, and retry remains usable', () async {
    final p = await plan();
    final lease = await SessionLease.acquire(manager.data);
    await manager.install(p);
    expect(manager.error, isNotNull);
    expect(manager.ready('Dolphin'), false);
    await lease.release();
    var cancelled = false;
    void cancel() {
      if (!cancelled && manager.phase.startsWith('Installing')) {
        cancelled = true;
        manager.cancel();
      }
    }

    manager.addListener(cancel);
    await manager.install(await plan());
    manager.removeListener(cancel);
    expect(manager.error, contains('cancelled'));
    expect(manager.ready('Dolphin'), false);
    await manager.install(await plan());
    expect(manager.error, isNull);
  });
  test('manifest commands, foreign hosts and corrupt selections cannot replace known state', () async {
    await expectLater(
      plan(
        entry: {
          'source': source.path,
          'environment': {'HOME': 'outside'},
        },
      ),
      throwsFormatException,
    );
    final f = File('${root.path}/wrong.json');
    await f.writeAsString(
      jsonEncode({'schema_version': 1, 'host': 'linux-x64', 'launchers': {}}),
    );
    await expectLater(manager.readPlan(file: f.path), throwsFormatException);
    await manager.install(await plan());
    final selected = File('${manager.root.path}/selected.json');
    await selected.writeAsString('{damaged');
    await manager.load();
    expect(manager.error, isNotNull);
    await expectLater(plan(), throwsStateError);
    expect(await selected.readAsString(), '{damaged');
  });
  test('profiles share the executable but retain separate writable data, and incomplete data cannot be silently reset', () async {
    await manager.install(await plan());
    final release = Directory('${manager.root.path}/dolphin/$digest');
    final a = await prepareManagedProfile(
      manager.data,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      build,
      release,
    );
    await File('${a.path}/saves/game.sav').writeAsString('profile A progress');
    final b = await prepareManagedProfile(
      manager.data,
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      build,
      release,
    );
    expect(await File('${b.path}/saves/game.sav').exists(), false);
    await prepareManagedProfile(
      manager.data,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      build,
      release,
    );
    expect(
      await File('${a.path}/saves/game.sav').readAsString(),
      'profile A progress',
    );
    await File('${a.path}/profile.json').delete();
    await expectLater(
      prepareManagedProfile(
        manager.data,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        build,
        release,
      ),
      throwsStateError,
    );
    expect(
      await File('${a.path}/saves/game.sav').readAsString(),
      'profile A progress',
    );
  });
  test('missing or redirected writable roots block relaunch rather than fabricate empty progress', () async {
    final release = Directory('${root.path}/release');
    final runtime = await prepareManagedProfile(
      manager.data,
      'dddddddddddddddddddddddddddddddd',
      build,
      release,
    );
    final state = File('${runtime.path}/states/retained.state');
    await state.writeAsString('retained progress');
    final saves = Directory('${runtime.path}/saves');
    await saves.delete();
    await expectLater(
      prepareManagedProfile(
        manager.data,
        'dddddddddddddddddddddddddddddddd',
        build,
        release,
      ),
      throwsStateError,
    );
    expect(await saves.exists(), false);
    expect(await state.readAsString(), 'retained progress');
    await Link(saves.path).create(root.path);
    await expectLater(
      prepareManagedProfile(
        manager.data,
        'dddddddddddddddddddddddddddddddd',
        build,
        release,
      ),
      throwsStateError,
    );
    expect(await state.readAsString(), 'retained progress');
  });
  test('removal withdraws only the shared managed installation and preserves profile progress and original sources', () async {
    final p = await plan();
    await manager.install(p);
    final save = File('${manager.data.path}/profiles/retained-save');
    await save.parent.create(recursive: true);
    await save.writeAsString('progress');
    await manager.remove(build);
    expect(manager.error, isNull);
    expect(manager.ready('Dolphin'), false);
    expect(
      await Directory('${manager.root.path}/dolphin/$digest').exists(),
      false,
    );
    expect(await save.readAsString(), 'progress');
    expect(
      await File('${source.path}/app').readAsString(),
      'exact tested executable',
    );
    await manager.install(p);
    expect(manager.ready('Dolphin'), true);
    expect(await save.readAsString(), 'progress');
  });
  test('active writers exclude removal; a checkpointed interrupted removal can finish after restart', () async {
    await manager.install(await plan());
    final lease = await SessionLease.acquire(manager.data);
    await manager.remove(build);
    expect(manager.error, isNotNull);
    expect(manager.ready('Dolphin'), true);
    await lease.release();
    // Persist a real pending-removal checkpoint, like an interrupted process.
    final selected = File('${manager.root.path}/selected.json');
    await selected.writeAsString(
      jsonEncode({
        'schema_version': 1,
        'selected': {},
        'removals': {'dolphin': digest},
      }),
      flush: true,
    );
    final restarted = ManagedEmulators(manager.data, asset: manager.asset);
    await restarted.load();
    expect(restarted.ready('Dolphin'), false);
    expect(restarted.removals.containsKey('dolphin'), true);
    await restarted.remove(build);
    expect(restarted.error, isNull);
    expect(restarted.removals, isEmpty);
    restarted.dispose();
  });
  test('unrecognized release files block deletion instead of removing unrelated data', () async {
    await manager.install(await plan());
    final unrelated = File(
      '${manager.root.path}/dolphin/$digest/unrelated-save',
    );
    await unrelated.writeAsString('keep');
    await manager.remove(build);
    expect(manager.error, isNotNull);
    expect(manager.ready('Dolphin'), true);
    expect(await unrelated.readAsString(), 'keep');
  });
  test('Azahar config and progress use the same private HOME location consumed by the macOS build', () async {
    final azahar = TestedBuild({
      'id': 'azahar',
      'name': 'Azahar',
      'version': 'fixture',
      'host': 'macos-arm64',
      'bundle': 'Fake.app',
      'executable': 'app',
      'sha256': digest,
      'sdl': 2,
      'native': <String, String>{},
    });
    final runtime = await prepareManagedProfile(
      manager.data,
      'cccccccccccccccccccccccccccccccc',
      azahar,
      source,
    );
    final user = '${runtime.path}/home/Library/Application Support/Azahar';
    final e = PreparedEmulator(
      'Azahar',
      runtime.path,
      '${source.path}/app',
      2,
      null,
      null,
      userDirectory: user,
    );
    await const AzaharAdapter().prepare(e, testGames[4], '/games/test.cci', 0);
    final settings = File('$user/config/qt-config.ini');
    expect(await settings.readAsString(), contains('confirmClose=false'));
    expect(await settings.readAsString(), contains('profiles\\1\\button_a='));
    final save = File('$user/game.sav');
    await save.writeAsString('3DS progress');
    await prepareManagedProfile(
      manager.data,
      'cccccccccccccccccccccccccccccccc',
      azahar,
      source,
    );
    expect(await save.readAsString(), '3DS progress');
  });
}
