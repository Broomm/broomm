import 'dart:convert';
import 'dart:io';

import '../lib/src/catalogue.dart';
import '../lib/src/pairing.dart';
import '../lib/src/session.dart';

// Short real-device observation; no synthetic input or device reconfiguration.
Future<void> main() async {
  final s = GameSession(Directory.current.path, onProblem: stderr.writeln);
  try {
    await s.launch(testGames.firstWhere((g) => g.id == 'brawl'));
    await s.waitFor(
      (v) =>
          v.paused == 1 &&
          v.devices.any((d) => d.accelerometerReady && d.gyroReady),
      timeout: const Duration(seconds: 90),
    );
    final devices = s.status!.devices
        .where((d) => d.accelerometerReady && d.gyroReady)
        .take(4)
        .toList();
    final rev = await s.command([
      for (final d in devices) PlayerAssignment(d.id),
    ], active: true);
    await s.waitFor((v) => v.ack == rev && !v.blocked && v.paused == 0);
    await Future<void>.delayed(const Duration(seconds: 5));
    final raw = jsonDecode(
      await File('${s.emulator!.root}/bridge-status.json').readAsString(),
    ) as Map<String, dynamic>;
    if (raw.containsKey('testSourceIds'))
      throw StateError('Synthetic inputs must be disabled');
    for (var p = 0; p < devices.length; p++) {
      if (!(raw['motionReads'][p][0] > 0 && raw['motionReads'][p][1] > 0))
        throw StateError(
          'Dolphin did not consume both sensors for player ${p + 1}',
        );
      final source = (raw['devices'] as List).firstWhere(
        (d) => d['id'] == devices[p].id,
      ) as Map;
      if (source['sensorReady'] != 3)
        throw StateError('Physical sensor data became unavailable');
    }
    await File('prototype-data/motion-hardware.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'host': Platform.operatingSystemVersion,
        'emulator': 'Dolphin 2609',
        'game': 'brawl',
        'syntheticSources': false,
        'assignedSourceIds': devices.map((d) => d.id).toList(),
        'snapshot': raw,
        'physicalSensorsSampled': true,
        'emulatorGetterConsumption': true,
        'ownerMovementPointingGameplayAcceptance': false,
      }),
    );
    stdout.writeln(
      'PASS: ${devices.length} physical motion controllers sampled; Dolphin consumed both sensors per assigned player.',
    );
  } finally {
    if (s.running) await s.stop();
  }
}
