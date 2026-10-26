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
  test('a no-game writer is isolated, excludes sessions until native exit and retains its private settings after a failed start', () async {
    final binary = '${data.path}/configuration-child';
    final compiler = await Process.run(
      '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang',
      ['tool/fixtures/configuration_child.c', '-o', binary],
    );
    expect(compiler.exitCode, 0, reason: '${compiler.stderr}');
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
    final configuration = EmulatorConfiguration(data, Directory.current.path);
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
      expect(await configuration.done, 0);
    }
    expect(await settings.readAsString(), 'configured in private HOME');
    final failed = EmulatorConfiguration(data, Directory.current.path);
    await expectLater(
      failed.start(() async => throw StateError('not ready')),
      throwsStateError,
    );
    final lease = await SessionLease.acquire(data);
    await lease.release();
    expect(await foreign.exists(), false);
  });
}
