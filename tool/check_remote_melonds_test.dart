// Explicit native check. Supply an existing managed installation and a local DS
// ROM. Copy under the source session lease, then use only fresh private saves.
import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native melonDS remote touch, geometry and hidden primary shutdown', () async {
    final source = Platform.environment['BROOMM_REMOTE_FIXTURE_INSTALL'];
    final rom = Platform.environment['BROOMM_REMOTE_FIXTURE_ROM'];
    if (!Platform.isMacOS || source == null || rom == null) {
      throw StateError(
        'Requires macOS, BROOMM_REMOTE_FIXTURE_INSTALL and BROOMM_REMOTE_FIXTURE_ROM.',
      );
    }
    final project = Directory.current.path;
    final evidence = Directory('$project/.tool-cache/research/remote-followup');
    await evidence.create(recursive: true);
    final data = await evidence.createTemp('native-');
    final manager = ManagedEmulators(
      data,
      project: project,
      asset: (path) => File(path).readAsString(),
    );
    final lease = await SessionLease.acquire(Directory(source));
    try {
      await manager.load();
      final build = manager.buildFor('melonDS')!;
      await manager.install(
        SetupPlan([
          SetupItem(
            build,
            '$source/emulators/${build.id}/${build.hash}/${build.bundle}',
            null,
            {},
          ),
        ]),
      );
      expect(manager.error, isNull);
      await File(rom).copy('${data.path}/game.nds');
    } finally {
      await lease.release();
    }
    final helper = '${evidence.path}/window-check';
    final compile = await Process.run('/usr/bin/xcrun', [
      'swiftc',
      '-target',
      'arm64-apple-macos13.0',
      '-sdk',
      '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk',
      '-module-cache-path',
      '$project/.tool-cache/swift-module-cache',
      'macos/Runner/SessionRecovery.swift',
      'tool/fixtures/remote_emulator_window.swift',
      '-o',
      helper,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stderr}');
    final reports = <Map<String, Object?>>[];
    try {
      // Both normal and split-window sessions must close through the root
      // frontend even after Broomm has hidden the emulator windows.
      for (final remote in [false, true, true]) {
        final ipc = await Directory.systemTemp.createTemp('brm-remote-native-');
        final socket = '${ipc.path}/input';
        final session = GameSession(
          project,
          managedRoot: data.path,
          testInputs: true,
          remoteSocket: socket,
          remoteScreen: remote,
          resolve: (game) =>
              manager.resolve(game, 'f123456789abcdef0123456789abcdef'),
        );
        final problems = <String>[];
        session.onProblem = problems.add;
        final game = LaunchGame(
          'ds',
          'Private DS fixture',
          'Nintendo DS',
          'melonDS',
          '${data.path}/game.nds',
          1,
          0xff539388,
          target: ControllerTarget.nds,
        );
        try {
          await session.launch(game);
          await session.waitFor(
            (s) => s.inputReady && s.paused == 1,
            timeout: const Duration(seconds: 40),
          );
          final pairing = Pairing(1, target: ControllerTarget.nds)
            ..join(session.status!.testSourceIds.first);
          await session.command(pairing.players, active: true);
          await session.waitFor(
            (s) => s.paused == 0,
            timeout: const Duration(seconds: 10),
          );
          final root = session.emulator!.root;
          final target = File('${data.path}/target.json');
          await target.writeAsString(
            jsonEncode({...session.macWindowTarget!, 'remoteSocket': socket}),
          );
          Future<Map<String, dynamic>> read() async =>
              jsonDecode(await File('$root/bridge-status.json').readAsString())
                  as Map<String, dynamic>;
          if (remote) {
            await session.waitFor(
              (s) => s.remoteCapture.length == 5 && s.remoteCapture[0] > 0,
              timeout: const Duration(seconds: 10),
            );
            expect(session.status!.remoteCapture[3], greaterThan(512));
            Future<void> touch(String report) async {
              final result = await Process.run(helper, [target.path, report]);
              expect(result.exitCode, 0, reason: '${result.stderr}');
            }

            await touch('touch 1 250 185');
            Future<void> waitTouch(bool pressed) async {
              final deadline = DateTime.now().add(const Duration(seconds: 2));
              while (DateTime.now().isBefore(deadline)) {
                final value = (await read())['remoteTouch'] as List;
                if (value[0] == pressed) return;
                await Future<void>.delayed(const Duration(milliseconds: 15));
              }
              fail('Native frontend touch did not become $pressed');
            }

            await waitTouch(true);
            expect((await read())['remoteTouch'], [true, 250, 185]);
            await touch('touch 0 250 185');
            await waitTouch(false);
            await touch('touch 1 100 80');
            await waitTouch(true);
            await session.command(pairing.players, active: false);
            await session.waitFor(
              (s) => s.paused == 1,
              timeout: const Duration(seconds: 10),
            );
            await waitTouch(false);
          } else {
            await session.command(pairing.players, active: false);
            await session.waitFor(
              (s) => s.paused == 1,
              timeout: const Duration(seconds: 10),
            );
          }
          await atomicText('$root/test-input.txt', '0 0 3 0 6');
          final hiddenDeadline = DateTime.now().add(const Duration(seconds: 3));
          while (!(await File(
            '$root/bridge.log',
          ).readAsString()).contains('SESSION_TEST_HIDE visible=0')) {
            if (DateTime.now().isAfter(hiddenDeadline))
              fail('The emulator did not confirm hiding.');
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          final inspect = await Process.run(helper, [target.path, 'inspect']);
          expect(inspect.exitCode, 0, reason: '${inspect.stderr}');
          // WindowServer can retain a fading snapshot after AppKit isVisible
          // becomes false. The logged AppKit observation above is the owning
          // boundary used by the old close selector, independent of that fade.
          final geometry = session.status!.remoteCapture;
          final watch = Stopwatch()..start();
          await session.stop();
          watch.stop();
          expect(problems, isEmpty);
          expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
          expect(await File('$root/remote-layout.json').exists(), false);
          expect(
            await File('$root/bridge.log').readAsString(),
            contains('MELONDS_QUIT_PRIMARY_WINDOW'),
          );
          reports.add({
            'remote': remote,
            'closeMilliseconds': watch.elapsedMilliseconds,
            'geometry': geometry,
            'hiddenShutdown': true,
            'frontendTouchReadback': remote,
            'executable': session.emulator?.executable,
          });
        } finally {
          if (session.running) await session.stop();
          if (await ipc.exists()) await ipc.delete(recursive: true);
        }
      }
      await File('${evidence.path}/native-results.json').writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert({'data': data.path, 'cases': reports}),
      );
    } finally {
      manager.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
