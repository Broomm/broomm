import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/app_model.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/host.dart';
import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends DesktopHost {
  @override
  Future<void> show({List<double>? frame, bool overlay = false}) async {}
  @override
  Future<void> hide(int pid) async {}
}

void main() {
  test('Azahar initial close repeats and cancellation before readiness remain safe', () async {
    final game = testGames.firstWhere((g) => g.id == 'mk7');
    final results = <Map<String, dynamic>>[];
    for (
      var i = const String.fromEnvironment('AZAHAR_CANCEL_ONLY') == '1' ? 2 : 0;
      i < 3;
      i++
    ) {
      final inventory = jsonDecode(
        await File('prototype-data/installations.json').readAsString(),
      ) as Map;
      final input =
          '${inventory['emulators']['Azahar']['root']}/test-input.txt';
      await atomicText(input, i == 2 ? '0 0 3 1' : '0 0 3');
      final s = GameSession(
        Directory.current.path,
        testInputs: true,
        onProblem: stderr.writeln,
      );
      final m = PrototypeModel(
        Directory.current.path,
        host: _Host(),
        gameSession: s,
      );
      try {
        await m.select(game);
        stdout.writeln('Azahar startup case $i launched');
        if (i < 2)
          await s.waitFor(
            (v) => m.screen == Screen.pairing && m.canPair,
            timeout: const Duration(minutes: 4),
          );
        else {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          expect(m.screen, Screen.loading);
        }
        await m.stop();
        if (s.running) {
          final pid = s.processId!;
          await Process.run('/usr/bin/sample', [
            '$pid',
            '2',
            '-file',
            '.tool-cache/research/azahar-loading-cancel.sample',
          ]);
          stderr.writeln(
            'Azahar startup case $i close failure: ${m.error}; pid=$pid',
          );
        }
        expect(s.running, false);
        expect(m.screen, Screen.library);
        results.add({
          'iteration': i,
          'initialPausedClose': i < 2,
          'cancelWithoutReadinessObservation': i == 2,
          'gracefulExit': true,
        });
      } finally {
        if (s.running) await s.stop();
        await atomicText(input, '0 0 3');
      }
    }
    await File('prototype-data/azahar-startup-close-results.json')
        .writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'results': results,
          }),
        );
  }, timeout: const Timeout(Duration(minutes: 7)));
  test('all supplied games expose pairing only after input and pause readiness', () async {
    final results = <Map<String, dynamic>>[];
    for (final game in testGames) {
      stdout.writeln('${game.id}: loading then initial pairing');
      final s = GameSession(
        Directory.current.path,
        testInputs: true,
        onProblem: stderr.writeln,
      );
      final m = PrototypeModel(
        Directory.current.path,
        host: _Host(),
        gameSession: s,
      );
      var loadingSeen = false, earlyPairing = false;
      final clock = Stopwatch()..start();
      m.addListener(() {
        if (m.screen == Screen.loading) loadingSeen = true;
        if (m.screen == Screen.pairing &&
            (!m.canPair || s.status?.inputReady != true))
          earlyPairing = true;
      });
      try {
        await m.select(game);
        expect(m.screen, Screen.loading, reason: game.id);
        if (m.error != null) throw StateError(m.error!);
        await atomicText('${s.emulator!.root}/test-input.txt', '0 0 3');
        await s.waitFor(
          (v) =>
              m.screen == Screen.pairing &&
              m.canPair &&
              v.inputReady &&
              v.paused == 1,
          timeout: const Duration(minutes: 4),
        );
        expect(loadingSeen, true);
        expect(earlyPairing, false);
        expect(m.busy, false);
        stdout.writeln(
          '${game.id}: ready after ${clock.elapsedMilliseconds} ms; closing while initially paused',
        );
        results.add({
          'game': game.id,
          'loadingSeen': true,
          'pairingOnlyWhenUsable': true,
          'inputReady': true,
          'paused': 1,
          'startupMs': clock.elapsedMilliseconds,
          'pid': s.status!.pid,
        });
      } finally {
        if (s.running) await s.stop();
      }
    }
    // Force missing startup observations, then cancel via the real UI model.
    final metadata = jsonDecode(
      await File('prototype-data/installations.json').readAsString(),
    ) as Map;
    final input =
        '${metadata['emulators']['RetroArch']['root']}/test-input.txt';
    await atomicText(input, '0 0 3 1');
    final s = GameSession(
      Directory.current.path,
      testInputs: true,
      onProblem: stderr.writeln,
    );
    final m = PrototypeModel(
      Directory.current.path,
      host: _Host(),
      gameSession: s,
    );
    try {
      await m.select(testGames.first);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(m.screen, Screen.loading);
      expect(m.busy, false);
      await m.stop();
      expect(m.screen, Screen.library);
      expect(s.running, false);
      results.add({
        'cancelBeforeStartupObservation': true,
        'returnedToLibrary': true,
        'gracefulExit': true,
      });
    } finally {
      if (s.running) await s.stop();
      await atomicText(input, '0 0 3');
    }
    await File('prototype-data/startup-results.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'host': Platform.operatingSystemVersion,
        'results': results,
        'source':
            'actual games/bridges, real Dart model, presentation suppressed',
        'physicalInputAcceptance': false,
      }),
    );
  }, timeout: const Timeout(Duration(minutes: 15)));
}
