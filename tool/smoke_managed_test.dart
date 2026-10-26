import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/app_model.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/host.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

class QuietHost extends DesktopHost {
  @override
  Future<void> show({List<double>? frame, bool overlay = false}) async {}
  @override
  Future<void> hide(int pid) async {}
}

void main() {
  test('real managed installs and private profiles play the supplied ROMs', () async {
    final project = Directory.current.path;
    final data = Directory(
      '$project/.tool-cache/research/managed-play/native-data',
    );
    final manager = ManagedEmulators(
      data,
      project: project,
      asset: (path) => File(path).readAsString(),
    );
    String last = '';
    manager.addListener(() {
      if (manager.phase != last) {
        last = manager.phase;
        stdout.writeln(last);
      }
    });
    await manager.load();
    final ids = Platform.environment['BROOMM_SMOKE_GAMES']?.split(',');
    final games = testGames
        .where((g) => ids == null || ids.contains(g.id))
        .toList();
    expect(games, isNotEmpty, reason: 'No matching test ROM IDs selected');
    final plan = await manager.readPlan(
      only: games.map((g) => g.emulator.toLowerCase()).toSet(),
    );
    await manager.install(plan);
    expect(manager.error, isNull, reason: manager.error);
    final results = <Map<String, dynamic>>[];
    final failures = <String>[];
    for (final g in games) {
      stdout.writeln(
        '${g.id}: launching managed copy with retained private profile data',
      );
      final game = LaunchGame(
        'download-${g.id}',
        g.title,
        g.platform,
        g.emulator,
        '$project/roms/${g.rom}',
        g.players,
        g.color,
        target: g.controllerTarget,
      );
      final session = GameSession(
        project,
        managedRoot: data.path,
        testInputs: true,
        resolve: (game) => manager.resolve(
          game,
          Platform.environment['BROOMM_SMOKE_PROFILE'] ??
              'f123456789abcdef0123456789abcdef',
        ),
      );
      final model = PrototypeModel(
        project,
        host: QuietHost(),
        gameSession: session,
      );
      try {
        await model.select(game);
        expect(model.error, isNull, reason: model.error);
        // Cold PS3 shader/PPU generation was measured beyond six minutes.
        final until = DateTime.now().add(const Duration(minutes: 10));
        while (DateTime.now().isBefore(until) &&
            session.running &&
            model.screen != Screen.pairing) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (model.screen != Screen.pairing)
          throw StateError(
            'Startup failed for ${g.id}: ${model.error}; ${session.status?.paused}; ${model.notice}',
          );
        final input = '${session.emulator!.root}/test-input.txt';
        await atomicText(input, '0 0 3');
        await session.waitFor(
          (s) => s.inputReady && s.testSourceIds.length == 2 && s.paused == 1,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await atomicText(input, '1536 0 3');
        final joined = DateTime.now().add(const Duration(seconds: 5));
        while (model.pairing!.players.isEmpty &&
            DateTime.now().isBefore(joined)) {
          await Future<void>.delayed(const Duration(milliseconds: 32));
        }
        expect(model.pairing!.players.length, 1);
        await atomicText(input, '0 0 3');
        await session.waitFor(
          (s) => s.devices
              .where((d) => d.id == model.pairing!.players.first.deviceId)
              .every((d) => d.buttons == 0),
        );
        await model.play();
        expect(model.screen, Screen.playing, reason: model.error);
        await model.menu();
        expect(model.paused, true, reason: model.error);
        model.showPairing();
        model.layout(model.pairing!.players.first.deviceId);
        await model.play();
        expect(model.screen, Screen.playing, reason: model.error);
        final runtime = session.emulator!.root;
        await model.stop();
        expect(session.running, false, reason: model.error);
        results.add({
          'game': g.id,
          'emulator': g.emulator,
          'profileRoot': runtime,
          'pairing': true,
          'resumed': true,
          'liveRemap': true,
          'closed': true,
        });
        stdout.writeln('${g.id}: pairing, play, menu/remap and close passed');
      } catch (e) {
        failures.add('${g.id}: $e');
        results.add({'game': g.id, 'passed': false, 'error': '$e'});
      } finally {
        if (session.running) {
          try {
            await model.stop();
          } catch (e) {
            failures.add('${g.id}: normal close failed: $e');
          }
        }
        model.dispose();
      }
    }
    await File(
      Platform.environment['BROOMM_SMOKE_RECORD'] ??
          '$project/.tool-cache/research/managed-play/native-results.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(results)}\n');
    manager.dispose();
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 40)));
}
