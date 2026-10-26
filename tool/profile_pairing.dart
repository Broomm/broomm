import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../lib/main.dart';
import '../lib/src/app_model.dart';
import '../lib/src/pairing.dart';
import '../lib/src/session.dart';

// Explicit UI-only benchmark entry point. Never enables synthetic emulator
// sources in the interactive app or opens an emulator/session writer.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const label = String.fromEnvironment(
    'PROFILE_LABEL',
    defaultValue: 'baseline',
  );
  final model = PrototypeModel(Directory.current.path)..screen = Screen.pairing;
  model.pairing = Pairing(4, target: ControllerTarget.wii);
  for (var id = 1; id <= 4; id++) model.pairing!.join(id);
  final frames = <FrameTiming>[], gaps = <int>[];
  final clock = Stopwatch()..start();
  var prior = 0, tick = 0;
  SchedulerBinding.instance.addTimingsCallback((values) {
    if (clock.elapsedMilliseconds > 2000) frames.addAll(values);
  });
  runApp(BroommPrototype(model: model));
  final timer = Timer.periodic(const Duration(milliseconds: 32), (_) {
    final now = clock.elapsedMicroseconds;
    if (prior > 0 && now > 2000000) gaps.add(now - prior);
    prior = now;
    final phase = (++tick % 100) / 100;
    final status = BridgeStatus({
      'inputReady': true,
      'protocol': 4,
      'pid': 1,
      'sample': tick,
      'ack': 1,
      'requestSerial': 0,
      'request': 'initial',
      'blocked': true,
      'paused': 1,
      'window': [0, 0, 1180, 800],
      'devices': [
        for (var id = 1; id <= 4; id++)
          {
            'id': id,
            'name': 'Nintendo Switch Pro Controller $id',
            'buttons': tick % 20 == 0 ? 1 : 0,
            'x': 0,
            'y': 0,
            'rx': 0,
            'ry': 0,
            'lt': 0,
            'rt': 0,
            'sensors': 3,
            'sensorReady': 3,
            'accel': [phase, 9.8, phase],
            'gyro': [phase, phase, phase],
          },
      ],
    });
    model.session.status = status;
    model.session.onStatus!(status);
  });
  Timer(const Duration(seconds: 22), () async {
    timer.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    Map<String, dynamic> stats(Iterable<int> values) {
      final sorted = values.toList()..sort();
      num percentile(double p) =>
          sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * p).round()] / 1000;
      return {
        'count': sorted.length,
        'p50ms': percentile(.5),
        'p95ms': percentile(.95),
        'p99ms': percentile(.99),
        'maxms': percentile(1),
        'over33ms': sorted.where((v) => v > 33333).length,
        'over100ms': sorted.where((v) => v > 100000).length,
      };
    }

    final output = File('.tool-cache/research/pairing-performance-$label.json');
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'host': Platform.operatingSystemVersion,
        'mode': 'macOS debug, 4 Wii cards, 32ms status cadence, 2s warmup',
        'build': stats(frames.map((f) => f.buildDuration.inMicroseconds)),
        'raster': stats(frames.map((f) => f.rasterDuration.inMicroseconds)),
        'eventLoopGaps': stats(gaps),
        'rssBytes': ProcessInfo.currentRss,
        'physicalInputAcceptance': false,
      }),
    );
    stdout.writeln('PAIRING_PROFILE ${output.path}');
    exit(0);
  });
}
