import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/session_lease.dart';

void main() {
  late Directory data;
  late String executable, guard;
  late File writer;
  setUp(() async {
    final project = Directory.current.path;
    final evidence = Directory(
      '$project/.tool-cache/research/library-followup',
    );
    data = await evidence.createTemp('installer-guard-');
    executable = '${data.path}/wait';
    guard = '$project/build/native/broomm-installer-guard.dylib';
    final cc = await Process.run(
      '/usr/bin/xcrun',
      [
        'clang',
        '-Wall',
        '-Wextra',
        '-Werror',
        'tool/fixtures/installer_wait.c',
        '-o',
        executable,
      ],
      environment: {
        'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer',
      },
    );
    expect(cc.exitCode, 0, reason: '${cc.stderr}');
    writer = File('${data.path}/writer.lock');
    await writer.writeAsString('');
  });
  Future<SessionLease> released() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      try {
        return await SessionLease.acquire(data);
      } on StateError {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  test('the actual native installer guard excludes a new session until its child exits', () async {
    final child = await Process.start(
      executable,
      [],
      environment: {
        'DYLD_INSERT_LIBRARIES': guard,
        'BROOMM_INSTALLER_WRITER_LOCK': writer.path,
      },
    );
    try {
      expect(
        await child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'ready',
      );
      await expectLater(SessionLease.acquire(data), throwsStateError);
    } finally {
      await child.stdin.close();
      expect(await child.exitCode, 0);
    }
    final lease = await released();
    await lease.release();
  });
  test('an opted-in unattended installer abort remains a non-success exit without SIGABRT and releases its writer lock', () async {
    final child = await Process.start(
      executable,
      [],
      environment: {
        'DYLD_INSERT_LIBRARIES': guard,
        'BROOMM_INSTALLER_WRITER_LOCK': writer.path,
        'BROOMM_INSTALLER_ABORT_MODE': 'rpcs3-cli-v1',
        'BROOMM_FIXTURE_ABORT': '1',
      },
    );
    final diagnostics = child.stderr.transform(utf8.decoder).join();
    expect(
      await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first,
      'ready',
    );
    await expectLater(SessionLease.acquire(data), throwsStateError);
    await child.stdin.close();
    expect(await child.exitCode, 86);
    expect(await diagnostics, contains('BROOMM_RPCS3_CLI_ABORT_V1'));
    final lease = await released();
    await lease.release();
  });
  test('without the installer opt-in the original abort still delivers SIGABRT', () async {
    final child = await Process.start(
      executable,
      [],
      environment: {
        'DYLD_INSERT_LIBRARIES': guard,
        'BROOMM_INSTALLER_WRITER_LOCK': writer.path,
        'BROOMM_FIXTURE_ABORT': '1',
        // Fixture-only handler observes the original signal and exits normally
        // before the OS creates another unwanted crash notification.
        'BROOMM_FIXTURE_HANDLE_ABORT': '1',
      },
    );
    final diagnostics = child.stderr.transform(utf8.decoder).join();
    expect(
      await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first,
      'ready',
    );
    await child.stdin.close();
    expect(await child.exitCode, 87);
    expect(
      await diagnostics,
      contains('original abort reached SIGABRT handler'),
    );
    final lease = await released();
    await lease.release();
  });
  test(
    'a live native orphan keeps the writer lease after its parent disappears',
    () async {
      final stop = File('${data.path}/stop');
      final parent = await Process.run('dart', [
        'tool/fixtures/orphan_installer.dart',
        executable,
        guard,
        writer.path,
        stop.path,
      ]);
      expect(parent.exitCode, 0, reason: '${parent.stderr}');
      expect((parent.stdout as String).trim(), 'ready');
      try {
        await expectLater(SessionLease.acquire(data), throwsStateError);
      } finally {
        await stop.writeAsString('stop');
        final lease = await released();
        await lease.release();
      }
    },
  );
  test('a held writer or linked lock rejects the installer before its main function', () async {
    final held = await writer.open(mode: FileMode.append);
    await held.lock(FileLock.exclusive);
    try {
      final child = await Process.run(
        executable,
        [],
        environment: {
          'DYLD_INSERT_LIBRARIES': guard,
          'BROOMM_INSTALLER_WRITER_LOCK': writer.path,
        },
      );
      expect(child.exitCode, 78);
      expect(child.stdout, '');
    } finally {
      await held.close();
    }
    final target = File('${data.path}/keep');
    await target.writeAsString('keep');
    await writer.delete();
    await Link(writer.path).create(target.path);
    final child = await Process.run(
      executable,
      [],
      environment: {
        'DYLD_INSERT_LIBRARIES': guard,
        'BROOMM_INSTALLER_WRITER_LOCK': writer.path,
      },
    );
    expect(child.exitCode, 78);
    expect(child.stdout, '');
    expect(await target.readAsString(), 'keep');
  });
}
