import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/src/session.dart';

Future<void> main(List<String> args) async {
  final label = args.firstOrNull ?? 'baseline';
  final dir = await Directory.systemTemp.createTemp('broomm-log-profile-');
  try {
    final log = SessionLog('${dir.path}/session.log');
    final watch = Stopwatch()..start();
    final gaps = <int>[];
    var previous = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
      final now = watch.elapsedMicroseconds;
      if (previous > 0) gaps.add(now - previous);
      previous = now;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final start = watch.elapsedMicroseconds;
    for (var i = 0; i < 4000; i++) log.write('Emulator output $i ${'x' * 512}');
    final enqueue = watch.elapsedMicroseconds - start;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    timer.cancel();
    await log.close();
    await File('.tool-cache/research/session-log-$label.json').writeAsString(
      jsonEncode({
        'chunks': 4000,
        'payloadBytes': 4000 * 512,
        'enqueueMs': enqueue / 1000,
        'maxEventLoopGapMs': gaps.reduce((a, b) => a > b ? a : b) / 1000,
      }),
    );
  } finally {
    await dir.delete(recursive: true);
  }
}
