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
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/romm/transfer.dart';

// Explicit local fixture manifest: [{id, release, rom, platform}]. Releases
// must be exact reviewed builds; owner games/resources are copied/read only.
void main() {
  final manifest = Platform.environment['BROOMM_PAUSE_FIXTURES'];
  if (manifest == null) {
    test(
      'local pause fixture prerequisites',
      () => fail('Set BROOMM_PAUSE_FIXTURES to a local fixture manifest.'),
    );
    return;
  }
  final fixtures = jsonDecode(File(manifest).readAsStringSync()) as List;
  final builds =
      (jsonDecode(File('assets/setup/tested-builds.json').readAsStringSync())
              as Map)['builds']
          as List;
  for (final fixture in fixtures.cast<Map>()) {
    test('native ${fixture['id']} preserves independent pause and Broomm controller gates', () async {
      final build = TestedBuild(
        builds.cast<Map>().singleWhere((b) => b['id'] == fixture['id']),
      );
      final cache = await Directory('.tool-cache/research/emulator-pause')
          .create(recursive: true);
      final root = await cache.createTemp('native-${build.id}-');
      final data = await Directory('${root.absolute.path}/data').create();
      final source = Directory(fixture['release'] as String).absolute;
      final release = Directory('${root.absolute.path}/release');
      final copy = await Process.run('/usr/bin/ditto', [
        source.path,
        release.path,
      ]);
      expect(copy.exitCode, 0, reason: copy.stderr.toString());
      final executable = '${release.path}/${build.bundle}/${build.executable}';
      final manager = ManagedEmulators(
        data,
        asset: (p) => File(p).readAsString(),
      );
      final receipt = jsonDecode(
        await File('${release.path}/receipt.json').readAsString(),
      ) as Map;
      final executableHash = await manager.verifyBundle(
        build,
        '${release.path}/${build.bundle}',
        DownloadCancellation(),
        preparation: (receipt['preparation'] as Map?)?.cast<String, String>(),
      );
      manager.dispose();
      expect(await progressFileHash(File(executable)), executableHash);
      final lease = await SessionLease.acquire(data);
      late Directory runtime;
      try {
        runtime = await prepareManagedProfile(data, 'e' * 32, build, release);
      } finally {
        await lease.release();
      }
      await File('${runtime.path}/local-symbols.txt').writeAsString(
        await File('assets/setup/${build.id}.symbols').exists()
            ? await File('assets/setup/${build.id}.symbols').readAsString()
            : '',
      );
      final emulator = PreparedEmulator(
        build.engine,
        runtime.path,
        executable,
        build.sdl,
        build.sdlLibrary == null
            ? null
            : '${release.path}/${build.bundle}/${build.sdlLibrary}',
        build.id == 'retroarch'
            ? File('build/native-pause-checks/pause-core.dylib').absolute.path
            : null,
        userDirectory: build.id == 'eden' ? '${runtime.path}/data/eden' : null,
      );
      final rom = File(fixture['rom'] as String).absolute.path;
      final game = LaunchGame(
        'pause-fixture',
        'Pause fixture',
        fixture['platform'] as String,
        build.engine,
        rom,
        4,
        0xff345678,
        target: build.id == 'retroarch'
            ? ControllerTarget.snes
            : ControllerTarget.switchPro,
      );
      final session = GameSession(
        Directory.current.path,
        managedRoot: data.path,
        testInputs: true,
        testPreconnected: true,
        resolve: (_) async => ResolvedSession(
          emulator,
          rom,
          executableHash,
          build.native,
          home: '${runtime.path}/home',
          readOnly: [source.path, File(rom).parent.path],
          buildHash: build.hash,
        ),
      );
      final problems = <String>[], checks = <String>[];
      session.onProblem = problems.add;
      final input = '${runtime.path}/test-input.txt';
      Future<void> nativePause(bool paused) async {
        if (build.id == 'retroarch') {
          final cfg = await File('${runtime.path}/retroarch.cfg')
              .readAsString();
          final port = int.parse(
            RegExp(r'network_cmd_port\s*=\s*"(\d+)"').firstMatch(cfg)![1]!,
          );
          final socket = await RawDatagramSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          try {
            socket.send(
              utf8.encode('PAUSE_TOGGLE'),
              InternetAddress.loopbackIPv4,
              port,
            );
          } finally {
            socket.close();
          }
        } else {
          await atomicText(input, '0 0 3 0 0');
          await Future<void>.delayed(const Duration(milliseconds: 120));
          await atomicText(input, '0 0 3 0 ${paused ? 4 : 5}');
        }
        await session.waitFor((s) => s.paused == (paused ? 1 : 0));
      }

      Future<void> hold(int paused, {bool? blocked}) async {
        var sample = session.status!.sample, count = 0;
        final until = DateTime.now().add(const Duration(milliseconds: 1200));
        while (DateTime.now().isBefore(until)) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          final s = session.status!;
          if (s.sample == sample) continue;
          sample = s.sample;
          count++;
          expect(
            s.paused,
            paused,
            reason: '${build.id}: independent pause changed during gameplay',
          );
          if (blocked != null) expect(s.blocked, blocked);
        }
        expect(count, greaterThan(10));
      }

      try {
        stdout.writeln(
          'Native pause fixture: ${build.name} ${build.version}, root=${root.path}',
        );
        await session.launch(game);
        await session.waitFor(
          (s) => s.inputReady && s.paused == 1 && s.testSourceIds.isNotEmpty,
          timeout: const Duration(seconds: 90),
        );
        final id = session.status!.testSourceIds.first;
        var players = [PlayerAssignment(id)];
        var revision = await session.command(players, active: true);
        await session.waitFor(
          (s) => s.ack >= revision && !s.blocked && s.paused == 0,
        );
        await nativePause(true);
        await hold(1, blocked: false);
        players = [
          PlayerAssignment(id, swapFaces: true),
          if (session.status!.testSourceIds.length > 1)
            PlayerAssignment(session.status!.testSourceIds[1]),
        ];
        revision = await session.command(players, active: true);
        await session.waitFor((s) => s.ack >= revision);
        await hold(1, blocked: false);
        checks.add(
          'native pause preserved through polling and active port/routing changes',
        );
        await nativePause(false);
        await hold(0, blocked: false);
        checks.add('native resume preserved');
        revision = await session.command(players, active: false);
        await session.waitFor(
          (s) => s.ack >= revision && s.blocked && s.paused == 1,
        );
        // Native Resume while Broomm owns the gate must be paused again.
        if (build.id == 'retroarch') {
          final cfg = await File('${runtime.path}/retroarch.cfg')
              .readAsString();
          final port = int.parse(
            RegExp(r'network_cmd_port\s*=\s*"(\d+)"').firstMatch(cfg)![1]!,
          );
          final socket = await RawDatagramSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          socket.send(
            utf8.encode('PAUSE_TOGGLE'),
            InternetAddress.loopbackIPv4,
            port,
          );
          socket.close();
        } else {
          await atomicText(input, '0 0 3 0 5');
        }
        final sample = session.status!.sample;
        await session.waitFor((s) => s.sample > sample + 8 && s.paused == 1);
        await hold(1, blocked: true);
        revision = await session.command(players, active: true);
        await session.waitFor(
          (s) => s.ack >= revision && !s.blocked && s.paused == 0,
        );
        await nativePause(true);
        await hold(1, blocked: false);
        checks.add(
          'Broomm pause/reassert/release works and subsequent native pause survives',
        );
        revision = await session.command(players, active: false);
        await session.waitFor((s) => s.ack >= revision && s.blocked);
        revision = await session.command(players, active: true);
        await session.waitFor(
          (s) => s.ack >= revision && !s.blocked && s.paused == 0,
        );
        checks.add('quick gate/release resumes explicitly');
        await atomicText(input, build.id == 'astris' ? '0 1 3' : '0 0 2');
        await session.waitFor(
          (s) => s.blocked && s.paused == 1 && s.request == 'disconnect',
        );
        checks.add('assigned-source disconnect still pauses');
        await session.stop();
        expect(problems, isEmpty);
      } finally {
        if (session.running) await session.stop();
        await File('${root.path}/observations.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert({'emulator': build.id, 'version': build.version, 'root': root.absolute.path, 'checks': checks, 'problems': problems, 'synthetic_core': build.id == 'retroarch', 'physical_controllers': false, 'romm_writes': false})}\n',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
