import 'dart:convert';
import 'dart:io';

import '../lib/src/catalogue.dart';
import '../lib/src/session.dart';

Future<void> main(List<String> args) async {
  final s = GameSession(Directory.current.path, onProblem: stderr.writeln);
  try {
    await s.launch(testGames.firstWhere((g) => g.id == 'brawl'));
    await s.waitFor((v) => v.paused == 1, timeout: const Duration(minutes: 3));
    await File('.tool-cache/research/native-profile-pid.json')
        .writeAsString(jsonEncode({'pid': s.status!.pid}));
    final result = await Process.run('/usr/bin/sample', [
      '${s.status!.pid}',
      '2',
      '-file',
      '.tool-cache/research/native-pairing-${args.firstOrNull ?? 'baseline'}.sample',
    ]);
    stdout.writeln(result.stderr);
    stdout.writeln('Native sample exit ${result.exitCode}');
  } finally {
    if (s.running) await s.stop();
  }
}
