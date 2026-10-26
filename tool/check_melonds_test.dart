import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('official melonDS plays a private downloaded DS ROM with same-runtime pairing, pause and live remap', () async {
    final project = Directory.current.path;
    final evidence = Directory(
      '$project/.tool-cache/research/library-followup',
    );
    final data = await evidence.createTemp('native-melonds-');
    const profile = 'f123456789abcdef0123456789abcdef';
    final manager = ManagedEmulators(
      data,
      project: project,
      asset: (path) => File(path).readAsString(),
    );
    await manager.load();
    final plan = await manager.readPlan(only: {'melonds'});
    await manager.install(plan);
    expect(manager.error, isNull);
    final game = LaunchGame(
      'ds',
      'Pokémon Black',
      'Nintendo DS',
      'melonDS',
      '$project/broomm-data/library/506d439865d8f46267001bdd3a1fe0e5/5569/content/Pokemon - Black Version.nds',
      1,
      0xff539388,
      target: ControllerTarget.nds,
    );
    final session = GameSession(
      project,
      managedRoot: data.path,
      testInputs: true,
      resolve: (g) => manager.resolve(g, profile),
    );
    final problems = <String>[];
    session.onProblem = problems.add;
    try {
      await session.launch(game);
      await session.waitFor(
        (s) => s.inputReady && s.paused == 1,
        timeout: const Duration(seconds: 50),
      );
      final id = session.status!.testSourceIds.first;
      final pairing = Pairing(1, target: ControllerTarget.nds)..join(id);
      await session.command(pairing.players, active: true);
      await session.waitFor(
        (s) => s.paused == 0 && s.connectedPorts == 1,
        timeout: const Duration(seconds: 10),
      );
      await session.command(pairing.players, active: false);
      await session.waitFor(
        (s) => s.paused == 1,
        timeout: const Duration(seconds: 10),
      );
      pairing.toggleLayout(id);
      await session.command(pairing.players, active: true);
      await session.waitFor(
        (s) => s.paused == 0,
        timeout: const Duration(seconds: 10),
      );
      await session.stop();
      expect(problems, isEmpty);
      final resolved = await manager.resolve(game, profile);
      final layout = await gameProgressLayout(resolved, 'nds');
      expect(layout.format, 'melonds-sav-v1');
      await File('${evidence.path}/native-melonds.json').writeAsString(
        jsonEncode({
          'root': data.path,
          'version': '1.1',
          'executable': resolved.executableHash,
          'realRom': game.rom,
          'pauseReadback': true,
          'liveRemapAcknowledged': true,
          'gameCode': layout.game,
          'progress': (await layout.files()).keys.toList(),
          'physicalControllerAcceptance': false,
        }),
      );
    } finally {
      if (session.running) await session.stop();
      manager.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
