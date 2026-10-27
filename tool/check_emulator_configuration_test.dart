import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:broomm/src/emulator_configuration.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all tested no-game applications start privately and exclude competing sessions until fixture cleanup', () async {
    final project = Directory.current.path;
    final evidence = Directory(
      '$project/.tool-cache/research/downloads-status',
    );
    final data = await evidence.createTemp('native-configuration-');
    final manager = ManagedEmulators(
      data,
      project: project,
      asset: (p) => File(p).readAsString(),
    );
    final log = SessionLog(
      '${data.path}/configuration.log',
      source: 'configuration-check',
    );
    final results = <Map<String, Object>>[];
    const profile = 'f323456789abcdef0123456789abcdef';
    await manager.load();
    await manager.install(
      await manager.readPlan(file: 'tool/setup-development.json'),
    );
    expect(manager.error, isNull, reason: manager.error);
    try {
      for (final build in manager.builds) {
        final child = EmulatorConfiguration(data, project, log: log);
        final clock = Stopwatch()..start();
        await child.start(
          () => manager.resolveConfiguration(build.name, profile),
        );
        try {
          await Future<void>.delayed(const Duration(seconds: 3));
          expect(
            child.pid,
            isNotNull,
            reason: '${build.name} closed before configuration.',
          );
          await expectLater(SessionLease.acquire(data), throwsStateError);
          results.add({
            'emulator': build.name,
            'noGameProcess': true,
            'competingSessionExcluded': true,
            'elapsedMs': clock.elapsedMilliseconds,
          });
          stdout.writeln(
            '${build.name} private configuration started without a game.',
          );
        } finally {
          if (child.pid case final pid?) {
            Process.killPid(pid, ProcessSignal.sigterm);
            try {
              await child.done!.timeout(const Duration(seconds: 3));
            } on TimeoutException {
              Process.killPid(pid, ProcessSignal.sigkill);
              await child.done;
            }
          }
          final lease = await SessionLease.acquire(data);
          await lease.release();
        }
      }
      await File('${evidence.path}/native-configuration.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'root': data.path, 'results': results, 'ownerProfilesWritten': false, 'visualSettingsAcceptance': false, 'cleanup': 'signals to disposable native fixtures only; user quits normally in production', 'nativeNormalQuitAcceptance': false})}\n',
      );
    } finally {
      manager.dispose();
      await log.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
