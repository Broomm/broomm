import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Intel RPCS3 boots an encrypted ISO through Rosetta with native pairing, remap and pause readback', () async {
    final project = Directory.current.path;
    final evidence = Directory('$project/.tool-cache/research/rpcs3-intel');
    final data = await evidence.createTemp('native-');
    const profile = 'f123456789abcdef0123456789abcdef';
    final manager = ManagedEmulators(
      data,
      project: project,
      asset: (p) => File(p).readAsString(),
    );
    await manager.load();
    await manager.install(await manager.readPlan(only: {'rpcs3-intel'}));
    expect(manager.error, isNull, reason: manager.error);
    final game = LaunchGame(
      '8002',
      '3D Dot Game Heroes',
      'PlayStation 3',
      'RPCS3 Intel',
      '$project/broomm-data/library/506d439865d8f46267001bdd3a1fe0e5/8002/content/3D Dot Game Heroes (USA).iso',
      4,
      0xff539388,
      target: ControllerTarget.ps3,
    );
    final passes = <Map<String, Object>>[];
    try {
      for (var pass = 1; pass <= 2; pass++) {
        final problems = <String>[];
        final session = GameSession(
          project,
          managedRoot: data.path,
          testInputs: true,
          resolve: (g) => manager.resolve(g, profile),
          onProblem: problems.add,
        );
        final clock = Stopwatch()..start();
        stdout.writeln('Intel RPCS3 pass $pass; isolated fixture ${data.path}');
        try {
          await session.launch(game);
          await session.waitFor(
            (s) => s.inputReady && s.paused == 1,
            timeout: const Duration(minutes: 10),
          );
          final ready = clock.elapsedMilliseconds;
          final id = session.status!.testSourceIds.first;
          final pairing = Pairing(4, target: ControllerTarget.ps3)..join(id);
          await session.command(pairing.players, active: true);
          await session.waitFor(
            (s) => s.paused == 0 && s.connectedPorts == 1,
            timeout: const Duration(seconds: 15),
          );
          await Future<void>.delayed(const Duration(seconds: 3));
          await session.command(pairing.players, active: false);
          await session.waitFor(
            (s) => s.paused == 1,
            timeout: const Duration(seconds: 15),
          );
          pairing.toggleLayout(id);
          await session.command(pairing.players, active: true);
          await session.waitFor(
            (s) => s.paused == 0 && s.connectedPorts == 1,
            timeout: const Duration(seconds: 15),
          );
          await session.command(pairing.players, active: false);
          await session.waitFor(
            (s) => s.paused == 1,
            timeout: const Duration(seconds: 15),
          );
          await session.stop();
          expect(problems, isEmpty, reason: problems.join('\n'));
          final resolved = await manager.resolve(game, profile);
          expect(resolved.emulator.name, 'RPCS3');
          expect(
            resolved.emulator.root,
            '${data.path}/profiles/$profile/emulators/rpcs3',
          );
          expect(resolved.home, endsWith('/home-intel'));
          final layout = await gameProgressLayout(resolved, 'ps3');
          expect(layout.game, 'BLUS30490');
          expect(layout.format, 'rpcs3-savedata-v1');
          passes.add({
            'pass': pass,
            'readyMs': ready,
            'hash': resolved.executableHash,
            'pairPauseResumeRemapNormalClose': true,
            'saveIdentity': layout.identity,
          });
          stdout.writeln(
            'Intel RPCS3 pass $pass ready in ${ready / 1000}s; normal exit',
          );
        } finally {
          if (session.running) await session.stop();
        }
      }
      await File('${evidence.path}/native.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'root': data.path, 'host': manager.host, 'game': 8002, 'passes': passes, 'physicalControllerAcceptance': false, 'remoteSaveWrites': false})}\n',
      );
    } finally {
      manager.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 24)));
}
