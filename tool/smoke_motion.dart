import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/src/catalogue.dart';
import '../lib/src/emulators.dart';
import '../lib/src/pairing.dart';
import '../lib/src/session.dart';

// Opt-in synthetic sensors, inside the real emulator, with the supplied ROMs.
Future<void> main(List<String> args) async {
  final results = <Map<String, dynamic>>[];
  final selected = testGames.where(
    (g) => (args.isEmpty ? ['brawl', 'rayman', 'mk7', '3dworld'] : args)
        .contains(g.id),
  );
  final s = GameSession(
    Directory.current.path,
    testInputs: true,
    testMotion: true,
    onProblem: stderr.writeln,
  );
  for (final game in selected) {
    stdout.writeln('${game.id}: launch with motion sources');
    try {
      await s.launch(game);
      final input = '${s.emulator!.root}/test-input.txt';
      final motion = '${s.emulator!.root}/test-motion.txt';
      Future<void> sensors({
        int supportA = 3,
        int readyA = 3,
        int supportB = 3,
        int readyB = 3,
      }) => atomicText(
        motion,
        '$supportA $readyA 1 9 2 .1 .2 .3\n$supportB $readyB -3 8 -4 -.4 -.5 -.6\n',
      );
      await atomicText(input, '0 0 3');
      await sensors();
      await s.waitFor(
        (v) =>
            v.paused == 1 &&
            v.testSourceIds.length == 2 &&
            v.testSourceIds.every(
              (id) => v.devices.any((d) => d.id == id && d.sensorReady == 3),
            ),
        timeout: const Duration(minutes: 4),
      );
      final a = s.status!.testSourceIds[0], b = s.status!.testSourceIds[1];
      Future<Map<String, dynamic>> read() async => jsonDecode(
        await File('${s.emulator!.root}/bridge-status.json').readAsString(),
      ) as Map<String, dynamic>;
      Future<Map<String, dynamic>> until(
        bool Function(Map<String, dynamic>) ready,
      ) async {
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        Map<String, dynamic> v = {};
        while (DateTime.now().isBefore(deadline)) {
          v = await read();
          if (ready(v)) return v;
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        throw StateError('Motion readback failed: $v');
      }

      bool close(dynamic actual, List<List<double>> expected) {
        if (actual is! List || actual.length != 2) return false;
        for (var t = 0; t < 2; t++)
          for (var i = 0; i < 3; i++) {
            if (((actual[t][i] as num).toDouble() - expected[t][i]).abs() >
                .0001)
              return false;
          }
        return true;
      }

      const av = [
            [1.0, 9.0, 2.0],
            [.1, .2, .3],
          ],
          bv = [
            [-3.0, 8.0, -4.0],
            [-.4, -.5, -.6],
          ];
      const neutral = [
        [0.0, 9.80665, 0.0],
        [0.0, 0.0, 0.0],
      ];
      final eventConsumer = game.emulator == 'Azahar';
      final consumerField = eventConsumer
          ? 'deliveredMotion'
          : 'consumedMotion';
      Future<void> apply(
        List<PlayerAssignment> players, {
        bool active = true,
      }) async {
        final rev = await s.command(players, active: active);
        await s.waitFor(
          (v) =>
              v.ack == rev &&
              v.paused == (active ? 0 : 1) &&
              v.blocked == !active,
        );
      }

      await apply([
        PlayerAssignment(a),
        if (game.players > 1) PlayerAssignment(b),
      ]);
      await until(
        (v) =>
            close((v[consumerField] as List)[0], av) &&
            (game.players == 1 || close((v[consumerField] as List)[1], bv)),
      );
      stdout.writeln(
        '${game.id}: actual ${eventConsumer ? 'watcher delivery' : 'sensor getter'} observed; reassigning',
      );
      await apply([
        PlayerAssignment(b, swapFaces: true),
        if (game.players > 1) PlayerAssignment(a),
      ]);
      await until(
        (v) =>
            close((v[consumerField] as List)[0], bv) &&
            (game.players == 1 || close((v[consumerField] as List)[1], av)),
      );
      await apply([
        PlayerAssignment(b, swapFaces: true, gyroEnabled: false),
        if (game.players > 1) PlayerAssignment(a),
      ]);
      await until(
        (v) =>
            close((v['logicalMotion'] as List)[0], [bv[0], neutral[1]]) &&
            (game.emulator == 'Dolphin' ||
                close((v[consumerField] as List)[0], [bv[0], neutral[1]])) &&
            (game.players == 1 || close((v[consumerField] as List)[1], av)),
      );
      await apply([
        PlayerAssignment(b),
        if (game.players > 1) PlayerAssignment(a),
      ]);
      await until((v) => close((v[consumerField] as List)[0], bv));
      // A supported sensor that fails must neutralize, independently per sensor.
      await sensors(readyB: 1);
      await until(
        (v) => close((v[consumerField] as List)[0], [bv[0], neutral[1]]),
      );
      await sensors(supportB: 0, readyB: 0);
      await until((v) => close((v[consumerField] as List)[0], neutral));
      await sensors();
      await until((v) => close((v[consumerField] as List)[0], bv));
      // Menu closes the route immediately. Cached event consumers also receive
      // neutral samples while paused, so old movement is not retained.
      await atomicText(input, '0 272 3');
      await s.waitFor((v) => v.paused == 1 && v.blocked && v.request == 'menu');
      await until(
        (v) =>
            close((v['logicalMotion'] as List)[0], neutral) &&
            (!eventConsumer || close((v[consumerField] as List)[0], neutral)),
      );
      await atomicText(input, '0 0 3');
      await apply([PlayerAssignment(b)]);
      await until((v) => close((v[consumerField] as List)[0], bv));
      await atomicText(input, '0 0 1');
      await s.waitFor(
        (v) => v.paused == 1 && v.blocked && v.request == 'disconnect',
      );
      final finalStatus = await until(
        (v) => close((v['logicalMotion'] as List)[0], neutral),
      );
      results.add({
        'game': game.id,
        'emulator': game.emulator,
        'route': true,
        'reassign': true,
        'faceSwapDoesNotRotateMotion': true,
        'perPlayerGyroToggleKeepsAcceleration': true,
        'failedSensorNeutral': true,
        'unsupportedSourceNeutral': true,
        'recovery': true,
        'pauseGate': true,
        'disconnectGate': true,
        'consumerEvidence': eventConsumer
            ? 'SDL watcher callback returned (not game HID readback)'
            : 'real emulator SDL getter returned routed values',
        'motionReads': finalStatus['motionReads'],
        'motionDelivered': finalStatus['motionDelivered'],
        'physicalControllerAcceptance': false,
      });
      stdout.writeln('${game.id}: PASS');
    } catch (e) {
      stderr.writeln('${game.id}: FAILED $e');
      results.add({'game': game.id, 'error': '$e'});
      exitCode = 1;
    } finally {
      if (s.running) {
        try {
          await s.stop();
          results.last['gracefulExit'] = true;
        } catch (e) {
          stderr.writeln('Graceful exit failed: $e');
          exitCode = 1;
          break;
        }
      }
    }
  }
  await File('prototype-data/motion-results.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'host': Platform.operatingSystemVersion,
      'results': results,
    }),
  );
}
