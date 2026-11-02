@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/managed_profile.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/session.dart';

void main() {
  test('DuckStation native pause survives gameplay polling and Broomm still gates and resumes', () async {
    final owner = Platform.environment['BROOMM_PAUSE_FIXTURE_SOURCE'];
    if (owner == null)
      fail('Set BROOMM_PAUSE_FIXTURE_SOURCE to the existing Broomm data root.');
    final sources = Directory(owner);
    final cache = await Directory('.tool-cache/research/duckstation-pause')
        .create(recursive: true);
    final root = await cache.createTemp('native-');
    final data = await Directory('${root.absolute.path}/data').create();
    final builds =
        (jsonDecode(
              await File('assets/setup/tested-builds.json').readAsString(),
            ) as Map)['builds']
            as List;
    final build = TestedBuild(
      builds.cast<Map>().singleWhere((b) => b['id'] == 'duckstation'),
    );
    final release = Directory('${root.absolute.path}/release');
    await release.create();
    final copy = await Process.run('/usr/bin/ditto', [
      '${sources.path}/emulators/${build.id}/${build.hash}/${build.bundle}',
      '${release.path}/${build.bundle}',
    ]);
    expect(copy.exitCode, 0, reason: copy.stderr.toString());
    final runtime = await prepareManagedProfile(data, 'e' * 32, build, release);
    await File(
      '${sources.path}/profiles/bc0ad61e72fccd591439d1b013fb03ee/emulators/duckstation/system/bios.bin',
    ).copy('${runtime.path}/system/bios.bin');
    await File('${runtime.path}/local-symbols.txt').writeAsString(
      await File('assets/setup/duckstation.symbols').readAsString(),
    );
    final rom =
        '${sources.path}/library/4ceb798e01a4de684b5b2856918ec396/6583/content/Mega Man X4.chd';
    final executable = '${release.path}/${build.bundle}/${build.executable}';
    final hash = await progressFileHash(File(executable));
    expect(
      hash,
      build.hash,
      reason: 'Only the reviewed DuckStation build may receive native entry points.',
    );
    final emulator = PreparedEmulator(
      'DuckStation',
      runtime.path,
      executable,
      build.sdl,
      '${release.path}/${build.bundle}/${build.sdlLibrary}',
      null,
      userDirectory:
          '${runtime.path}/home/Library/Application Support/DuckStation',
    );
    final resolved = ResolvedSession(
      emulator,
      rom,
      hash,
      build.native,
      home: '${runtime.path}/home',
      readOnly: [sources.path],
    );
    final game = LaunchGame(
      '6583',
      'Mega Man X4',
      'psx',
      'DuckStation',
      rom,
      2,
      0xff345678,
      target: ControllerTarget.psx,
    );
    final session = GameSession(
      Directory.current.path,
      managedRoot: data.path,
      testInputs: true,
      testPreconnected: true,
      resolve: (_) async => resolved,
    );
    final observations = <String>[];
    final problems = <String>[];
    session.onProblem = problems.add;
    final input = '${runtime.path}/test-input.txt';
    Future<void> holdPause(int expected, {bool? blocked}) async {
      final until = DateTime.now().add(const Duration(milliseconds: 1200));
      var samples = 0, previous = session.status!.sample;
      while (DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 32));
        final state = session.status!;
        if (state.sample == previous) continue;
        previous = state.sample;
        samples++;
        expect(
          state.paused,
          expected,
          reason: 'Native pause changed during steady gameplay polling.',
        );
        if (blocked != null) expect(state.blocked, blocked);
      }
      expect(samples, greaterThan(10));
    }

    try {
      await session.launch(game);
      await session.waitFor(
        (s) => s.inputReady && s.paused == 1 && s.testSourceIds.length == 2,
      );
      final id = session.status!.testSourceIds.first;
      var revision = await session.command([
        PlayerAssignment(id),
      ], active: true);
      await session.waitFor(
        (s) => s.ack >= revision && !s.blocked && s.paused == 0,
      );
      await atomicText(input, '0 0 3 0 4');
      await session.waitFor((s) => s.paused == 1);
      await holdPause(1, blocked: false);
      // Re-publishing active routing must not turn a native pause into Resume.
      revision = await session.command([
        PlayerAssignment(id, swapFaces: true),
      ], active: true);
      await session.waitFor((s) => s.ack >= revision);
      await holdPause(1, blocked: false);
      observations.add(
        'native pause retained across polling and active routing publication',
      );
      await atomicText(input, '0 0 3 0 5');
      await session.waitFor((s) => s.paused == 0);
      await holdPause(0, blocked: false);
      observations.add('native resume retained');
      revision = await session.command([PlayerAssignment(id)], active: false);
      await session.waitFor(
        (s) => s.ack >= revision && s.blocked && s.paused == 1,
      );
      await atomicText(input, '0 0 3 0 0');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final beforeNativeResume = session.status!.sample;
      await atomicText(input, '0 0 3 0 5');
      await session.waitFor(
        (s) => s.sample > beforeNativeResume + 8 && s.paused == 1,
      );
      await holdPause(1, blocked: true);
      revision = await session.command([PlayerAssignment(id)], active: true);
      await session.waitFor(
        (s) => s.ack >= revision && !s.blocked && s.paused == 0,
      );
      await atomicText(input, '0 0 3 0 4');
      await session.waitFor((s) => s.paused == 1);
      await holdPause(1, blocked: false);
      revision = await session.command([PlayerAssignment(id)], active: false);
      await session.waitFor(
        (s) => s.ack >= revision && s.blocked && s.paused == 1,
      );
      revision = await session.command([PlayerAssignment(id)], active: true);
      await session.waitFor(
        (s) => s.ack >= revision && !s.blocked && s.paused == 0,
      );
      await atomicText(input, '0 0 3 0 0');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await atomicText(input, '0 0 3 0 4');
      await session.waitFor((s) => s.paused == 1);
      await holdPause(1, blocked: false);
      observations.add(
        'Broomm pause gate and explicit resume still work, including quick gate/release; subsequent native pause retained',
      );
      await atomicText(input, '0 0 2');
      await session.waitFor(
        (s) => s.blocked && s.paused == 1 && s.request == 'disconnect',
      );
      observations.add('assigned controller disconnection gates and pauses');
      await session.stop();
      expect(problems, isEmpty);
    } finally {
      if (session.running) await session.stop();
      await File('${root.path}/observations.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'root': root.absolute.path, 'emulator': build.version, 'rom': 'Mega Man X4', 'checks': observations, 'problems': problems})}\n',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
