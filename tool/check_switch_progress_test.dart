import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/ryubing.dart';
import 'package:broomm/src/progress/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Ryubing cold identification closes its writer before save restore; committed save content survives native reopen', () async {
    final project = Directory.current.path;
    final evidence = Directory(
      '$project/.tool-cache/research/library-followup',
    );
    final data = await evidence.createTemp('native-switch-');
    final source = Directory(
      '$project/.tool-cache/research/managed-play/native-data',
    );
    const profile = 'f123456789abcdef0123456789abcdef';
    final buildJson = jsonDecode(
      await File('assets/setup/tested-builds.json').readAsString(),
    ) as Map;
    final build = (buildJson['builds'] as List).cast<Map>().singleWhere(
      (b) => b['id'] == 'ryubing',
    );
    final sourceLease = await SessionLease.acquire(source);
    try {
      for (final path in [
        'emulators/ryubing',
        'profiles/$profile/emulators/ryubing',
      ]) {
        final target = Directory('${data.path}/$path');
        await target.parent.create(recursive: true);
        final r = await Process.run('/bin/cp', [
          '-cR',
          '${source.path}/$path',
          target.path,
        ]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
      }
    } finally {
      await sourceLease.release();
    }
    await File('${data.path}/emulators/selected.json').writeAsString(
      jsonEncode({
        'schema_version': 1,
        'selected': {'ryubing': build['sha256']},
      }),
    );
    final manager = ManagedEmulators(
      data,
      project: project,
      asset: (p) => File(p).readAsString(),
    );
    await manager.load();
    final game = LaunchGame(
      '3dworld',
      'Super Mario 3D World',
      'Nintendo Switch',
      'Ryubing',
      '$project/roms/switch/Super Mario 3D World + Bowsers Fury.nsp',
      4,
      0xff539388,
    );
    late GameSession session;
    late ProgressLayout layout;
    late File sentinel;
    final phases = <String>[];
    session = GameSession(
      project,
      managedRoot: data.path,
      testInputs: true,
      resolve: (g) async {
        final resolved = await manager.resolve(g, profile);
        try {
          layout = await gameProgressLayout(resolved, 'switch');
        } on SwitchNeedsInitialization catch (needed) {
          phases.add('native-initialization');
          final program = await session.initializeSwitchStorage(resolved, g);
          phases.add('initial-writer-stopped');
          await recordRyubingGame(resolved, program, needed.hash);
          layout = await gameProgressLayout(resolved, 'switch');
        }
        sentinel = await layout.target('save/broomm-probe');
        await sentinel.writeAsString('committed-snapshot');
        final working = File(
          sentinel.path.replaceFirst('/0/broomm-probe', '/1/broomm-probe'),
        );
        await working.writeAsString('uncommitted-working-copy');
        phases.add('restore-before-gameplay');
        return resolved;
      },
    );
    try {
      await session.launch(game);
      await session.waitFor(
        (s) => s.inputReady && s.paused == 1,
        timeout: const Duration(seconds: 60),
      );
      final pairing = Pairing(4, target: ControllerTarget.switchPro)
        ..join(session.status!.testSourceIds.first);
      await session.command(pairing.players, active: true);
      await session.waitFor(
        (s) => s.paused == 0,
        timeout: const Duration(seconds: 10),
      );
      final committedMirror = File(
        sentinel.path.replaceFirst('/0/broomm-probe', '/1/broomm-probe'),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (DateTime.now().isBefore(deadline) &&
          await committedMirror.readAsString() != 'committed-snapshot') {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await session.stop();
      expect(phases, [
        'native-initialization',
        'initial-writer-stopped',
        'restore-before-gameplay',
      ]);
      expect(await sentinel.readAsString(), 'committed-snapshot');
      final working = File(
        sentinel.path.replaceFirst('/0/broomm-probe', '/1/broomm-probe'),
      );
      expect(await working.readAsString(), 'committed-snapshot');
      final lease = await SessionLease.acquire(data);
      try {
        final store = ProgressStore(
          Directory('${data.path}/roundtrip'),
          layout,
          42,
          3,
          ownerRoot: data,
        );
        final snapshot = await store.capture();
        expect(snapshot.entries.keys, contains('save/broomm-probe'));
        expect(
          snapshot.entries.keys.any(
            (p) =>
                p.contains('ExtraData') ||
                p.contains('Profiles') ||
                p.contains('imkvdb'),
          ),
          false,
        );
        final exported = await store.exportNative(snapshot);
        try {
          expect(exported.extension, 'zip');
          final imported = await store.importNative(exported.file);
          expect(imported.ordinaryDigest, snapshot.ordinaryDigest);
          final retained = ProgressStore(
            Directory('${data.path}/retained-roundtrip'),
            ProgressLayout(
              layout.root,
              layout.format,
              layout.game,
              [],
              archiveOnly: true,
            ),
            42,
            3,
          );
          final portable = await retained.importNative(exported.file);
          expect(portable.ordinaryDigest, snapshot.ordinaryDigest);
        } finally {
          await exported.close();
        }
      } finally {
        await lease.release();
      }
      await File('${evidence.path}/native-switch-progress.json').writeAsString(
        jsonEncode({
          'root': data.path,
          'build': build['sha256'],
          'program': layout.game,
          'phases': phases,
          'committed0RestoredToWorking1': true,
          'nativeZipRoundTrip': true,
          'physicalGameplay': false,
        }),
      );
    } finally {
      if (session.running) await session.stop();
      manager.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
