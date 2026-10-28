@TestOn('mac-os')
library;

import 'dart:io';

import 'package:broomm/src/emulator_configuration.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data, root;
  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-configure-test-');
    root = await Directory('${data.path}/profiles/test/emulator')
        .create(recursive: true);
    for (final folder in ['home', 'config', 'data', 'cache'])
      await Directory('${root.path}/$folder').create();
  });
  tearDown(() async {
    await data.delete(recursive: true);
  });
  Future<File> guardLibrary() async {
    // A fresh checkout has no build/native artifacts. Compile this test's
    // actual writer guard in its private project rather than borrowing a
    // developer's previous application build.
    final guard = File(
      '${data.path}/build/native/broomm-installer-guard.dylib',
    );
    await guard.parent.create(recursive: true);
    final guardCompiler = await Process.run(
      '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang',
      [
        '-dynamiclib',
        '-std=c11',
        if (Platform.environment['BROOMM_CONFIGURATION_SANITIZERS'] == '1') ...[
          '-fsanitize=undefined',
          '-fsanitize-undefined-trap-on-error',
        ],
        'native/installer_guard.c',
        '-framework',
        'AppKit',
        '-o',
        guard.path,
      ],
    );
    expect(guardCompiler.exitCode, 0, reason: '${guardCompiler.stderr}');
    return guard;
  }

  test('no-game arguments select only managed data and do not overwrite existing configuration', () async {
    final e = PreparedEmulator(
      'RetroArch',
      root.path,
      '/not-launched',
      3,
      null,
      null,
    );
    final config = File('${root.path}/retroarch.cfg');
    await config.writeAsString('video_driver = "vulkan"\nvideo_scale = "3"\n');
    expect(await const RetroArchAdapter().configurationArguments(e), [
      '-c',
      config.path,
      '--appendconfig',
      '${root.path}/configure.cfg',
    ]);
    expect(
      await config.readAsString(),
      'video_driver = "vulkan"\nvideo_scale = "3"\n',
    );
    expect(await const DolphinAdapter().configurationArguments(e), [
      '-u',
      e.user,
    ]);
    expect(await const RyubingAdapter().configurationArguments(e), [
      '-r',
      e.user,
    ]);
    for (final name in ['RPCS3', 'Azahar', 'melonDS'])
      expect(
        await EmulatorAdapter.forName(name).configurationArguments(e),
        isEmpty,
      );
  });
  test('subsequent game preparation preserves private graphics and unrelated preferences while refreshing owned controller routing', () async {
    final config = File('${root.path}/retroarch.cfg');
    await config.writeAsString(
      'video_driver = "vulkan"\nvideo_scale = "3"\ninput_driver = "old"\n',
    );
    final retro = PreparedEmulator(
      'RetroArch',
      root.path,
      '/not-launched',
      3,
      null,
      '/managed/core',
    );
    await const RetroArchAdapter().prepare(
      retro,
      testGames.firstWhere((g) => g.emulator == 'RetroArch'),
      '/test.sfc',
      12345,
    );
    expect(await config.readAsString(), contains('video_driver = "vulkan"'));
    expect(await config.readAsString(), contains('video_scale = "3"'));
    expect(await config.readAsString(), contains('input_driver = "sdl3"'));
    final dolphin = PreparedEmulator(
      'Dolphin',
      root.path,
      '/not-launched',
      3,
      null,
      null,
    );
    final ini = File('${dolphin.user}/Config/Dolphin.ini');
    await ini.parent.create(recursive: true);
    await ini.writeAsString(
      '[Core]\nCPUThread = False\nOverclock = 0.75\nSIDevice0 = 6\n[Unrelated]\nKeep = yes\n',
    );
    await const DolphinAdapter().prepare(
      dolphin,
      testGames.firstWhere((g) => g.emulator == 'Dolphin'),
      '/test.iso',
      0,
    );
    final patched = await ini.readAsString();
    expect(patched, contains('CPUThread = False'));
    expect(patched, contains('Overclock = 0.75'));
    expect(patched, contains('SIDevice0 = 0'));
    expect(patched, contains('Keep = yes'));
    await ini.writeAsString('[Core]\nSIDevice0 = 1\nSIDevice0 = 2\n');
    final before = await ini.readAsString();
    await expectLater(
      const DolphinAdapter().prepare(
        dolphin,
        testGames.firstWhere((g) => g.emulator == 'Dolphin'),
        '/test.iso',
        0,
      ),
      throwsStateError,
    );
    expect(await ini.readAsString(), before);
  });
  test('OS handoff returns while the private no-game app is alive and retains the native writer lock without a launcher lifetime watcher', () async {
    final app = await Directory('${data.path}/Configuration.app/Contents/MacOS')
        .create(recursive: true);
    final binary = '${app.path}/configuration-child';
    await File('${app.parent.path}/Info.plist')
        .writeAsString('''<?xml version="1.0"?><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>configuration-child</string>
<key>CFBundleIdentifier</key><string>app.broomm.configuration-fixture.${DateTime.now().microsecondsSinceEpoch}</string>
<key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/>
</dict></plist>''');
    final compiler = await Process.run(
      '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang',
      ['tool/fixtures/configuration_child.c', '-o', binary],
    );
    expect(compiler.exitCode, 0, reason: '${compiler.stderr}');
    await guardLibrary();
    final release = File('${root.path}/home/release'),
        foreign = File('${data.path}/foreign');
    final e = PreparedEmulator(
      'Dolphin',
      root.path,
      binary,
      3,
      null,
      null,
      userDirectory: foreign.path,
    );
    final configuration = EmulatorConfiguration(data, data.path);
    await configuration.start(() async => ResolvedSession(e, '', '', {}));
    final settings = File('${root.path}/home/private-settings');
    try {
      for (var i = 0; i < 100 && !await settings.exists(); i++)
        await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await settings.readAsString(), 'configured in private HOME');
      await expectLater(SessionLease.acquire(data), throwsStateError);
      final writer = await File('${data.path}/writer.lock')
          .open(mode: FileMode.append);
      try {
        await expectLater(
          writer.lock(FileLock.exclusive),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        await writer.close();
      }
      expect(await foreign.exists(), false);
    } finally {
      await release.writeAsString('close');
    }
    expect(await settings.readAsString(), 'configured in private HOME');
    final failed = EmulatorConfiguration(data, Directory.current.path);
    await expectLater(
      failed.start(() async => throw StateError('not ready')),
      throwsStateError,
    );
    // Native fixture cleanup only: production never polls for app exit.
    SessionLease? lease;
    final until = DateTime.now().add(const Duration(seconds: 3));
    while (lease == null && DateTime.now().isBefore(until)) {
      try {
        lease = await SessionLease.acquire(data);
      } on StateError {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    expect(lease, isNotNull);
    await lease!.release();
    expect(await foreign.exists(), false);
  });
  test('a competing coordinator or linked lock refuses detached configuration before its main function', () async {
    final guard = await guardLibrary();
    final binary = '${data.path}/guard-rejection';
    final compiler = await Process.run(
      '/usr/bin/xcrun',
      ['clang', 'tool/fixtures/installer_wait.c', '-o', binary],
      environment: {
        'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer',
      },
    );
    expect(compiler.exitCode, 0, reason: '${compiler.stderr}');
    final lease = await SessionLease.acquire(data);
    Future<ProcessResult> launch() => Process.run(
      binary,
      [],
      includeParentEnvironment: false,
      environment: {
        'DYLD_INSERT_LIBRARIES': guard.path,
        'BROOMM_INSTALLER_WRITER_LOCK': '${data.path}/writer.lock',
        'BROOMM_CONFIGURATION_SESSION_LOCK': '${data.path}/session.lock',
        'BROOMM_CONFIGURATION_ROOT': root.path,
        'BROOMM_CONFIGURATION_SANDBOX': '(version 1)(allow default)',
      },
    );
    try {
      expect((await launch()).exitCode, 78);
    } finally {
      await lease.release();
    }
    expect((await launch()).exitCode, 0);
    await File('${data.path}/session.lock')
        .rename('${data.path}/session.original');
    await Link('${data.path}/session.lock').create('session.original');
    expect((await launch()).exitCode, 78);
    expect(await File('${data.path}/session.original').exists(), true);
  });
}
