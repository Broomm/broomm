@TestOn('mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native PSP folder and bookmark preference writes stay in the child volatile domain', () async {
    final root = await Directory('.tool-cache/research/psp')
        .createTemp('defaults-');
    final executable = '${root.absolute.path}/defaults-probe';
    final sanitized = Platform.environment['BROOMM_DEFAULTS_SANITIZERS'] == '1';
    final flags = sanitized
        ? ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
        : <String>[];
    var guard =
        '${Directory.current.path}/build/native/broomm-installer-guard.dylib';
    if (sanitized) {
      guard = '${root.absolute.path}/guard-sanitized.dylib';
      final bridge = await Process.run(
        '/usr/bin/xcrun',
        [
          'clang',
          '-Wall',
          '-Wextra',
          '-Werror',
          ...flags,
          '-dynamiclib',
          'native/installer_guard.c',
          '-framework',
          'AppKit',
          '-o',
          guard,
        ],
        environment: {
          'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer',
        },
      );
      expect(bridge.exitCode, 0, reason: '${bridge.stderr}');
    }
    final compile = await Process.run(
      '/usr/bin/xcrun',
      [
        'clang',
        '-Wall',
        '-Wextra',
        '-Werror',
        ...flags,
        'tool/fixtures/ppsspp_defaults.c',
        '-framework',
        'AppKit',
        '-o',
        executable,
      ],
      environment: {
        'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer',
      },
    );
    expect(compile.exitCode, 0, reason: '${compile.stderr}');
    for (final key in [
      'UserPreferredMemoryStickDirectoryPath',
      'SecureBookmarks',
    ]) {
      final result = await Process.run(
        executable,
        [],
        environment: {
          'DYLD_INSERT_LIBRARIES': guard,
          'BROOMM_PSP_MEMSTICK': '${root.absolute.path}/private-user',
          'BROOMM_DEFAULTS_PROBE_KEY': key,
          if (sanitized) 'UBSAN_OPTIONS': 'halt_on_error=1',
        },
      );
      expect(result.exitCode, 0, reason: '$key: ${result.stderr}');
      expect(result.stdout, contains('private volatile preferences verified'));
    }
    stdout.writeln('PPSSPP defaults evidence: ${root.path}');
  });
}
