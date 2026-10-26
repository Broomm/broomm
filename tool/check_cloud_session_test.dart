import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';

import '../test/cloud_saves_test.dart' show SaveServer, profileId, serverId;

void main() {
  test('real RetroArch writer exits before progress capture and retains the session lease through verified cloud finalization', () async {
    if (!Platform.isMacOS)
      throw UnsupportedError('Requires the tested macOS native pack');
    final project = Directory.current.path;
    final evidence = Directory('$project/.tool-cache/research/cloud-saves');
    await evidence.create(recursive: true);
    final data = await evidence.createTemp('native-session-');
    final owner = Directory('$project/broomm-data');
    final buildList = jsonDecode(
      await File('$project/assets/setup/tested-builds.json').readAsString(),
    ) as Map;
    final build = (buildList['builds'] as List).cast<Map>().singleWhere(
      (b) => b['id'] == 'retroarch',
    );
    final hash = build['sha256'] as String;
    final bundle = Directory('${data.path}/emulators/retroarch/$hash');
    await bundle.parent.create(recursive: true);
    final lease = await SessionLease.acquire(owner);
    try {
      final copy = await Process.run('/bin/cp', [
        '-cR',
        '${owner.path}/emulators/retroarch/$hash',
        bundle.path,
      ]);
      expect(copy.exitCode, 0, reason: '${copy.stderr}');
      final profile = Directory('${data.path}/profiles/$profileId/emulators');
      await profile.create(recursive: true);
      final copiedProfile = await Process.run('/bin/cp', [
        '-cR',
        '${owner.path}/profiles/15770cf1430ff66c406582cc4245ae63/emulators/retroarch',
        '${profile.path}/retroarch',
      ]);
      expect(copiedProfile.exitCode, 0, reason: '${copiedProfile.stderr}');
      await File('${profile.path}/retroarch/profile.json').writeAsString(
        jsonEncode({
          'version': 1,
          'profile': profileId,
          'emulator': 'retroarch',
        }),
        flush: true,
      );
    } finally {
      await lease.release();
    }
    await File('${data.path}/emulators/selected.json').writeAsString(
      jsonEncode({
        'schema_version': 1,
        'selected': {'retroarch': hash},
      }),
    );
    final manager = ManagedEmulators(
      data,
      project: project,
      asset: (path) => File(path).readAsString(),
    );
    await manager.load();
    final api = SaveServer();
    final cloud = CloudSaves(data, notice: (m, p) {}, phase: stdout.writeln);
    final g = testGames.first;
    final game = LaunchGame(
      g.id,
      g.title,
      g.platform,
      g.emulator,
      '$project/roms/${g.rom}',
      g.players,
      g.color,
      target: g.controllerTarget,
    );
    late CloudGame progress;
    final events = <String>[], problems = <String>[];
    final session = GameSession(
      project,
      managedRoot: data.path,
      testInputs: true,
      resolve: (game) async {
        final resolved = await manager.resolve(game, profileId);
        progress = CloudGame(
          server: serverId,
          profile: profileId,
          user: 3,
          rom: 42,
          client: api,
          layout: await gameProgressLayout(resolved, 'snes'),
        );
        await cloud.beforePlay(progress);
        return resolved;
      },
    );
    session.onProblem = problems.add;
    session.onFinalizingProgress = () => events.add('visible-finalization');
    session.finalizeProgress = (code) async {
      expect(session.finalizingProgress, true);
      await expectLater(SessionLease.acquire(data), throwsA(isA<StateError>()));
      await cloud.afterPlay(progress, code);
      events.add('progress-verified');
    };
    session.onExit = (code) {
      expect(code, 0);
      events.add('exit-complete');
    };
    try {
      await session.launch(game);
      await session.waitFor(
        (s) => s.inputReady && s.paused == 1,
        timeout: const Duration(seconds: 45),
      );
      await session.stop();
      expect(events, [
        'visible-finalization',
        'progress-verified',
        'exit-complete',
      ]);
      expect(problems, isEmpty);
      expect(api.records.values.where((s) => s.managed), hasLength(1));
      expect((await cloud.store(progress).state())['pending'], false);
      final released = await SessionLease.acquire(data);
      await released.release();
      await File('${evidence.path}/native-session.json').writeAsString(
        jsonEncode({
          'emulator': 'RetroArch',
          'build': hash,
          'root': data.path,
          'realWriterExitBeforeCapture': true,
          'sessionLeaseHeldDuringFinalization': true,
          'managedAssetReadback': true,
          'server': 'in-memory fixture; not owner-authenticated RomM',
          'events': events,
        }),
        flush: true,
      );
    } finally {
      if (session.running) await session.stop();
      api.close();
      manager.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
