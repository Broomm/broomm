// Cleanup for native test processes created by these fixtures only.
import 'dart:io';

import 'package:broomm/src/session_lease.dart';

Future<int> configurationFixturePid(String executable) async {
  final expected = await File(executable).resolveSymbolicLinks();
  final until = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(until)) {
    final result = await Process.run('/bin/ps', ['-ww', '-axo', 'pid=,comm=']);
    if (result.exitCode != 0)
      throw StateError('Fixture process inventory failed.');
    for (final line in (result.stdout as String).split('\n')) {
      final match = RegExp(r'^\s*([0-9]+)\s+(.+)$').firstMatch(line);
      if (match != null && match[2] == expected) return int.parse(match[1]!);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('The disposable emulator process was not found.');
}

Future<void> closeConfigurationFixture(int pid, Directory data) async {
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigkill]) {
    Process.killPid(pid, signal);
    final until = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(until)) {
      try {
        final lease = await SessionLease.acquire(data);
        await lease.release();
        return;
      } on StateError {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  }
  throw StateError(
    'The disposable configuration fixture did not release its writer lock.',
  );
}

Future<void> configurationFixtureReady(Directory data, int pid) async {
  // Read-only kernel lock query in a separate test process: acquiring locks
  // ourselves would introduce contention into the launch being tested.
  final probe = File('${data.path}/lock-probe');
  if (!await probe.exists()) {
    final compiler = await Process.run(
      '/usr/bin/xcrun',
      [
        'clang',
        '-std=c11',
        '-Wall',
        '-Wextra',
        '-Werror',
        'tool/fixtures/configuration_lock.c',
        '-o',
        probe.path,
      ],
      environment: {
        'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer',
      },
    );
    if (compiler.exitCode != 0)
      throw StateError(
        'Could not compile native lock observation: ${compiler.stderr}',
      );
  }
  // A measured cold Rosetta launch took nine seconds to reach constructors.
  // This observation belongs only to the harness; production never waits.
  final until = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(until)) {
    final result = await Process.run(probe.path, [
      '${data.path}/session.lock',
      '$pid',
    ]);
    if (result.exitCode == 0) return;
    if (result.exitCode != 1)
      throw StateError('Native fixture lock ownership could not be confirmed.');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError(
    'The disposable configuration process never acquired its coordinator lock.',
  );
}
