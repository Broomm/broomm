import 'dart:convert';
import 'dart:io';

Future<String> digest(String path) async {
  final result = await Process.run('/usr/bin/shasum', ['-a', '256', path]);
  if (result.exitCode != 0) throw StateError('Cannot hash evidence input');
  return (result.stdout as String).split(' ').first;
}

Future<void> main() async {
  final root = Directory.current.path;
  final base = '$root/experiments/injection';
  final inventory = jsonDecode(
    File('$base/artifacts/local-installations.json').readAsStringSync(),
  ) as Map;
  final results = <String, Object?>{};
  var failed = false;
  for (final name in ['RetroArch', 'Dolphin', 'RPCS3', 'Azahar', 'Ryubing']) {
    final session = '$base/sessions/${name.toLowerCase()}';
    final parts = <String>[];
    for (var i = 9; i >= 0; i--) {
      final f = File('$session/probe.log${i == 0 ? '' : '.$i'}');
      if (f.existsSync()) parts.add(f.readAsStringSync());
    }
    final log = parts.join('\n');
    final pids = RegExp(r'INJECTED pid=(\d+)')
        .allMatches(log)
        .map((m) => m[1]!)
        .toSet();
    final clean = pids.length == 1;
    final counters = RegExp(
      r'COUNTERS query=(\d+) changed=(\d+) events=(\d+) watched=(\d+) draws=(\d+)',
    ).allMatches(log).lastOrNull;
    final modes = RegExp(
      r'QUERY [^\n]*mode=(\d)',
    ).allMatches(log).map((m) => int.parse(m[1]!)).toSet().toList()..sort();
    final self = RegExp(r'SELF_CHECK mode=(\d)[^\n]*pass=(\d)')
        .allMatches(log)
        .toList();
    final selfFailures = self.where((m) => m[2] != '1').length;
    final selfModes = self.map((m) => int.parse(m[1]!)).toSet().toList()
      ..sort();
    final pause = log
        .split('\n')
        .where(
          (l) =>
              l.contains('CORE_STATE before=2 requested=1 after=1') ||
              l.contains('CORE_STATE before=1 requested=2 after=2') ||
              l.contains('QT_PAUSE_CALLED') ||
              l.contains('QT_PAUSE_TOGGLED') ||
              l.contains('WINDOW_TITLE') && l.contains('(Paused)'),
        )
        .map((l) => l.replaceFirst(RegExp(r'^.*?pid=\d+ '), ''))
        .toList();
    if (name == 'RetroArch')
      pause.addAll(
        File('$session/command-status.log')
            .readAsLinesSync()
            .where((l) => l.startsWith('GET_STATUS')),
      );
    final versions = RegExp(r'SDL_VERSION value=(\S+)')
        .allMatches(log)
        .map((m) => m[1])
        .toSet()
        .toList();
    final original = inventory[name] as Map;
    final installation = jsonDecode(
      File('$session/installation.json').readAsStringSync(),
    ) as Map;
    final hashes = await Future.wait([
      digest(original['executable'] as String),
      digest(installation['executable'] as String),
      digest('$session/probe.log'),
    ]);
    final queries = counters == null ? 0 : int.parse(counters[1]!);
    final changed = counters == null ? 0 : int.parse(counters[2]!);
    final draws = counters == null ? 0 : int.parse(counters[5]!);
    final changedModes = <int>{};
    var passthroughMismatches = 0;
    for (final m in RegExp(
      r'QUERY [^\n]*raw=(-?\d+) effective=(-?\d+) mode=(\d)',
    ).allMatches(log)) {
      if (m[1] != m[2]) {
        changedModes.add(int.parse(m[3]!));
        if (m[3] == '0') passthroughMismatches++;
      }
    }
    final titleLines = log
        .split('\n')
        .where((l) => l.contains('WINDOW_TITLE'))
        .toList();
    final pausedTitle = titleLines.indexWhere((l) => l.contains('(Paused)'));
    final pauseRoundTrip = switch (name) {
      'RetroArch' =>
        pause.any((l) => l.contains('GET_STATUS PAUSED')) &&
            pause.any((l) => l.contains('GET_STATUS PLAYING')),
      'Dolphin' =>
        log.contains('CORE_STATE before=2 requested=1 after=1') &&
            log.contains('CORE_STATE before=1 requested=2 after=2'),
      'Azahar' =>
        log.contains(
              'value=1 before_frame_advancing=0 after_frame_advancing=1',
            ) &&
            log.contains(
              'value=0 before_frame_advancing=1 after_frame_advancing=0',
            ),
      'RPCS3' =>
        log.contains('value=1 raw_before=3 raw_after=4') &&
            log.contains('value=0 raw_before=4 raw_after=3'),
      'Ryubing' =>
        pausedTitle >= 0 &&
            titleLines
                .skip(pausedTitle + 1)
                .any((l) => !l.contains('(Paused)')),
      _ => false,
    };
    final passed =
        clean &&
        queries > 0 &&
        changed > 0 &&
        draws > 0 &&
        selfFailures == 0 &&
        selfModes.length == 3 &&
        modes.length == 3 &&
        pauseRoundTrip &&
        passthroughMismatches == 0 &&
        changedModes.containsAll([1, 2]) &&
        hashes[0] == hashes[1];
    failed |= !passed;
    results[name] = {
      'single_process_log': clean,
      'sdl_version': versions,
      'queries_at_last_snapshot': queries,
      'changed_queries_at_last_snapshot': changed,
      'events_at_last_snapshot': counters == null ? 0 : int.parse(counters[3]!),
      'watch_callbacks_at_last_snapshot': counters == null
          ? 0
          : int.parse(counters[4]!),
      'draws_at_last_snapshot': draws,
      'native_query_modes': modes,
      'native_changed_query_modes': changedModes.toList()..sort(),
      'sampled_passthrough_mismatches': passthroughMismatches,
      'fixture_checks': self.length,
      'fixture_modes': selfModes,
      'fixture_failures': selfFailures,
      'pause_observations': pause,
      'pause_resume_round_trip': pauseRoundTrip,
      'original_and_private_executable_sha256': hashes[0],
      'private_executable_matches_original': hashes[0] == hashes[1],
      'probe_log_sha256': hashes[2],
      'recorded_evidence_complete': passed,
    };
    stdout.writeln(
      '$name evidence=${passed ? 'complete' : 'INCOMPLETE'} queries=$queries changed=$changed draws=$draws fixture_failures=$selfFailures',
    );
  }
  final os = await Process.run('/usr/bin/sw_vers', ['-productVersion']);
  final result = {
    'captured_at_utc': DateTime.now().toUtc().toIso8601String(),
    'host': {
      'os': 'macOS',
      'version': (os.stdout as String).trim(),
      'architecture': 'arm64',
    },
    'scope': 'In-process synthetic-controller game tests; no physical-controller, visual/fullscreen, Linux/Steam or other-host acceptance.',
    'bridge_sha256': {
      'sdl2': await digest('$base/build/probe-sdl2.dylib'),
      'sdl3': await digest('$base/build/probe-sdl3.dylib'),
    },
    'emulators': results,
  };
  await File('$root/docs/research/injection-validation-evidence.json')
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(result)}\n');
  if (failed) exitCode = 1;
}
