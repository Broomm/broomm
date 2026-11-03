@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

// Explicit native check only: use an existing disposable managed installation,
// read-only test media and locally provisioned firmware/keys. No cloud calls,
// owner saves or console/account identities are copied into the fixture.
void main() {
  test('Eden reconnects a replacement source, changes players and resumes rendering', () async {
    final env = Platform.environment;
    final data = Directory(env['BROOMM_EDEN_TEST_DATA']!);
    expect(data.path, contains('/.tool-cache/research/'));
    final reference = Directory(env['BROOMM_EDEN_TEST_REFERENCE']!);
    final backend =
        env['BROOMM_EDEN_EXPECT_BACKEND'] ?? env['QT_QPA_PLATFORM'] ?? 'xcb';
    final resultName = env['BROOMM_EDEN_TEST_CASE'] ?? backend;
    expect(['wayland', 'xcb'], contains(backend));
    expect(['wayland', 'xcb', 'default'], contains(resultName));
    final evidence = Directory(env['BROOMM_EDEN_TEST_EVIDENCE']!);
    await evidence.create(recursive: true);
    final random = Random.secure();
    final profile = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final manager = ManagedEmulators(
      data,
      asset: (p) => File(p).readAsString(),
    );
    final prepared = await manager.resolveConfiguration('Eden', profile);
    final e = prepared.emulator;
    final keys = await Directory('${e.user}/keys').create(recursive: true);
    for (final name in ['prod.keys', 'title.keys']) {
      final source = File('${reference.path}/keys/$name');
      if (!await source.exists()) continue;
      final target = await source.copy('${keys.path}/$name');
      expect((await Process.run('chmod', ['600', target.path])).exitCode, 0);
    }
    final firmware = '${e.user}/nand/system/Contents/registered';
    await Directory(firmware).parent.create(recursive: true);
    final copy = await Process.run('cp', [
      '--reflink=auto',
      '-a',
      '--',
      '${reference.path}/nand/system/Contents/registered',
      firmware,
    ]);
    expect(copy.exitCode, 0, reason: '${copy.stderr}');
    final game = LaunchGame(
      '8103',
      'Smash reconnect fixture',
      'switch',
      'Eden',
      env['BROOMM_EDEN_TEST_ROM']!,
      4,
      0,
      target: ControllerTarget.switchPro,
    );
    final problems = <String>[], steps = <String>[];
    int? exit;
    final session = GameSession(
      Directory.current.path,
      managedRoot: data.path,
      testInputs: true,
      testPreconnected: true,
      resolve: (g) async {
        final resolved = await manager.resolve(g, profile);
        return ResolvedSession(
          resolved.emulator,
          resolved.rom,
          resolved.executableHash,
          {...resolved.native, 'XDG_DATA_DIRS': '/usr/local/share:/usr/share'},
          home: resolved.home,
        );
      },
    );
    session.onProblem = problems.add;
    session.onExit = (code) => exit = code;
    var passed = false;
    int logicalButtons() =>
        (jsonDecode(
                      File('${e.root}/bridge-status.json').readAsStringSync(),
                    )['logicalButtons']
                    as List)
                .first
            as int;
    Future<void> controls(int buttons, int present) => atomicText(
      '${e.root}/test-input.txt',
      '$buttons 0 $present 0 0 0 0 -32768 0 0 -32768 0 0 0 0',
    );
    Future<void> resume(List<PlayerAssignment> players) async {
      final revision = await session.command(players, active: true);
      final ports = (1 << players.length) - 1;
      await session.waitFor(
        (s) =>
            s.ack >= revision &&
            !s.blocked &&
            s.paused == 0 &&
            s.consolePorts == ports,
        timeout: const Duration(seconds: 30),
      );
      final sample = session.status!.sample;
      await session.waitFor(
        (s) => s.sample > sample + 60 && s.paused == 0,
        timeout: const Duration(seconds: 15),
      );
    }

    try {
      await session.launch(game);
      await session.waitFor(
        (s) => s.inputReady && s.paused == 1 && session.nativeProgramId != null,
        timeout: const Duration(seconds: 120),
      );
      final trace = await File('${e.root}/bridge.log').readAsString();
      expect(trace, contains('backend=$backend'));
      steps.add('Actual Qt backend confirmed: $backend');
      var id = session.status!.testSourceIds.first;
      await resume([PlayerAssignment(id)]);
      steps.add('Initial play and continued native samples');
      for (var cycle = 0; cycle < 3; cycle++) {
        await controls(0, 2);
        await session.waitFor(
          (s) =>
              s.request == 'disconnect' &&
              s.blocked &&
              s.paused == 1 &&
              s.consolePorts == 0,
          timeout: const Duration(seconds: 20),
        );
        steps.add('Disconnect $cycle: gate, pause and native port removal');
        await controls(0, 3);
        await session.waitFor(
          (s) =>
              s.testSourceIds.first != id &&
              s.testSourceIds.first != 0xffffffff &&
              s.devices.any((d) => d.id == s.testSourceIds.first),
        );
        id = session.status!.testSourceIds.first;
        await resume([PlayerAssignment(id)]);
        steps.add('Reconnect $cycle: replacement ID and live resume');
        await controls(2, 3);
        await session.waitFor((s) => (logicalButtons() & 2) != 0);
        await controls(0, 3);
        await session.waitFor((s) => logicalButtons() == 0);
      }
      await session.command([PlayerAssignment(id)], active: false);
      await session.waitFor((s) => s.paused == 1 && s.blocked);
      await resume([
        PlayerAssignment(id),
        PlayerAssignment(session.status!.testSourceIds.last),
      ]);
      steps.add('Two native console ports applied while paused, then resumed');
      await session.command([PlayerAssignment(id)], active: false);
      await session.waitFor((s) => s.paused == 1 && s.blocked);
      await resume([PlayerAssignment(id)]);
      steps.add('Returned to one native console port and resumed');
      expect(problems, isEmpty, reason: problems.join('\n'));
      passed = true;
    } finally {
      try {
        await session.stop();
      } finally {
        await File('${evidence.path}/$resultName.json').writeAsString(
          jsonEncode({
            'passed': passed && exit == 0 && problems.isEmpty,
            'backend': backend,
            'profile': e.root,
            'steps': steps,
            'problems': problems,
            'exit': exit,
            'physical_input_verified': false,
          }),
        );
        manager.dispose();
      }
    }
    expect(exit, 0);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
