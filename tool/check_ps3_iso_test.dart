import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/ps3_disc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('RPCS3 boots the owner encrypted ISO using the downloaded adjacent dkey in an isolated profile', () async {
    final project = Directory.current.path;
    final evidence = Directory('$project/.tool-cache/research/slotted-saves');
    final data = await evidence.createTemp('native-ps3-iso-');
    final manager = ManagedEmulators(
      data,
      project: project,
      asset: (p) => File(p).readAsString(),
    );
    await manager.load();
    await manager.install(
      await manager.readPlan(
        file: 'tool/setup-development.json',
        only: {'rpcs3'},
      ),
    );
    expect(manager.error, isNull);
    final rom =
        '$project/broomm-data/library/506d439865d8f46267001bdd3a1fe0e5/8002/content/3D Dot Game Heroes (USA).iso';
    final key = await ps3DiscKey(File(rom));
    expect(key, isNotNull);
    final meta = await readPs3GameMetadata(rom);
    expect(meta['TITLE_ID'], matches(r'^[A-Z]{4}[0-9]{5}$'));
    final game = LaunchGame(
      '8002',
      '3D Dot Game Heroes',
      'PlayStation 3',
      'RPCS3',
      rom,
      4,
      0xff539388,
      target: ControllerTarget.ps3,
    );
    final session = GameSession(
      project,
      managedRoot: data.path,
      testInputs: true,
      resolve: (g) => manager.resolve(g, 'f123456789abcdef0123456789abcdef'),
    );
    final problems = <String>[];
    session.onProblem = problems.add;
    try {
      await session.launch(game);
      await session.waitFor(
        (s) => s.inputReady && s.paused == 1,
        timeout: const Duration(minutes: 8),
      );
      final pairing = Pairing(4, target: ControllerTarget.ps3)
        ..join(session.status!.testSourceIds.first);
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
      expect(problems, isEmpty);
      final resolved = await manager.resolve(
        game,
        'f123456789abcdef0123456789abcdef',
      );
      final layout = await gameProgressLayout(resolved, 'ps3');
      expect(layout.game, meta['TITLE_ID']);
      await File('${evidence.path}/native-ps3-iso.json').writeAsString(
        jsonEncode({
          'root': data.path,
          'game': 8002,
          'title': meta['TITLE_ID'],
          'hash': resolved.executableHash,
          'downloadedDkeyPresent': true,
          'keyPassedInArguments': false,
          'nativePausePairResumeClose': true,
          'physicalControllerAcceptance': false,
        }),
      );
    } finally {
      if (session.running) await session.stop();
      manager.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
