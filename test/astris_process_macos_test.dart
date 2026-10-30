@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/astris_process.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixture;
  late String executable, guard;
  Future<void> run(String command, List<String> arguments) async {
    final result = await Process.run(
      command,
      arguments,
      environment: {
        'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer',
      },
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  setUpAll(() async {
    fixture = await Directory.systemTemp.createTemp('broomm-native launch-');
    fixture = Directory(await fixture.resolveSymbolicLinks());
    final app = Directory('${fixture.path}/Native Fixture.app/Contents');
    await Directory('${app.path}/MacOS').create(recursive: true);
    executable = '${app.path}/MacOS/fixture';
    guard = '${fixture.path}/guard.dylib';
    await File('${app.path}/Info.plist').writeAsString('''
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>fixture</string>
<key>CFBundleIdentifier</key><string>app.broomm.native-launch-fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>''');
    await run('/usr/bin/xcrun', [
      'clang',
      '-fobjc-arc',
      '-fblocks',
      '-Wall',
      '-Wextra',
      '-Werror',
      'native/test_launch_application.m',
      '-framework',
      'AppKit',
      '-o',
      executable,
    ]);
    await run('/usr/bin/xcrun', [
      'clang',
      '-dynamiclib',
      '-std=c11',
      '-Wall',
      '-Wextra',
      '-Werror',
      'native/installer_guard.c',
      '-framework',
      'AppKit',
      '-o',
      guard,
    ]);
    await run('/usr/bin/codesign', ['--force', '--sign', '-', app.parent.path]);
  });
  tearDownAll(() async => fixture.delete(recursive: true));

  test(
    'failed OS launch revokes admission and releases pending pipe readers',
    () async {
      final root = await fixture.createTemp('failed-');
      final writer = '${root.path}/writer.lock';
      await File(writer).writeAsString('');
      await expectLater(
        AstrisProcess.start(
          executable: '${root.path}/Missing.app/Contents/MacOS/missing',
          root: root.path,
          writer: writer,
          guard: guard,
          environment: const {},
        ),
        throwsStateError,
      );
      expect(await File('${root.path}/astris-launch-ticket').exists(), false);
      final lease = await SessionLease.acquire(root);
      await lease.release();
    },
  );

  test(
    'helper termination cannot release the native writer or finalize early',
    () async {
      final root = await fixture.createTemp('normal-');
      final writer = '${root.path}/writer.lock';
      await File(writer).writeAsString('');
      Process? request;
      final child = await AstrisProcess.start(
        executable: executable,
        root: root.path,
        writer: writer,
        guard: guard,
        observeRequest: (p) => request = p,
        environment: {
          'BROOMM_ASTRIS_ROOT': root.path,
          'BROOMM_WRITER_LOCK': writer,
        },
      );
      final output = utf8.decoder.bind(child.stdout).join();
      final errors = child.stderr.drain<void>();
      try {
        expect(child.pid, isNot(request!.pid));
        request!.kill(ProcessSignal.sigterm);
        await request!.exitCode;
        final native = AstrisProcessIdentity(guard, writer, executable);
        final identity = native.writer()!;
        expect(native.alive(identity), true);
        expect(
          native.alive([identity[0], identity[1] + 1, identity[2]]),
          false,
        );
        await expectLater(SessionLease.acquire(root), throwsStateError);
        await File('${root.path}/finish').writeAsString('');
        expect(await child.exitCode.timeout(const Duration(seconds: 10)), 0);
        expect(await output, contains('native fixture output'));
        await errors;
        final lease = await SessionLease.acquire(root);
        await lease.release();
      } finally {
        await File('${root.path}/finish').writeAsString('');
        await child.exitCode.timeout(const Duration(seconds: 10));
      }
    },
  );

  test(
    'foreign executable and a crash cannot become a successful session',
    () async {
      final root = await fixture.createTemp('crash-');
      final writer = '${root.path}/writer.lock';
      await File(writer).writeAsString('');
      await File('${root.path}/astris-exit.json')
          .writeAsString(jsonEncode({'pid': 1, 'normal': true}));
      final child = await AstrisProcess.start(
        executable: executable,
        root: root.path,
        writer: writer,
        guard: guard,
        environment: {
          'BROOMM_ASTRIS_ROOT': root.path,
          'BROOMM_WRITER_LOCK': writer,
          'BROOMM_FIXTURE_CRASH': '1',
        },
      );
      final out = child.stdout.drain<void>(), err = child.stderr.drain<void>();
      try {
        expect(
          () => AstrisProcessIdentity(guard, writer, '/usr/bin/true').writer(),
          throwsStateError,
        );
        await File('${root.path}/finish').writeAsString('');
        expect(await child.exitCode.timeout(const Duration(seconds: 10)), -1);
        await Future.wait([out, err]);
      } finally {
        await File('${root.path}/finish').writeAsString('');
        await child.exitCode.timeout(const Duration(seconds: 10));
      }
    },
  );
}
