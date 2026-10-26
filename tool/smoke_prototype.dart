import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/src/catalogue.dart';
import '../lib/src/emulators.dart';
import '../lib/src/pairing.dart';
import '../lib/src/session.dart';

Future<void> main(List<String> args) async {
  final ids = args.where((a) => !a.startsWith('--')).toList();
  final repeat = int.parse(
    args.where((a) => a.startsWith('--repeat=')).firstOrNull?.split('=').last ??
        '1',
  );
  final selected = ids.isEmpty
      ? testGames
      : testGames.where((g) => ids.contains(g.id));
  final unknown = ids.where((id) => !testGames.any((g) => g.id == id));
  if (unknown.isNotEmpty)
    throw ArgumentError('Unknown game IDs: ${unknown.join(', ')}');
  if (repeat < 1 || repeat > 10) throw ArgumentError('--repeat must be 1..10');
  final results = <Map<String, dynamic>>[];
  final session = GameSession(
    Directory.current.path,
    testInputs: true,
    testPreconnected: args.contains('--preconnected'),
    onProblem: stderr.writeln,
  );
  for (final game in selected.expand((g) => List.filled(repeat, g))) {
    final exitResult = Completer<int>();
    session.onExit = (code) {
      if (!exitResult.isCompleted) exitResult.complete(code);
    };
    stdout.writeln('${game.id}: launching actual ROM');
    try {
      await session.launch(game);
      final input = '${session.emulator!.root}/test-input.txt';
      await atomicText(input, '0 0 3');
      await session.waitFor(
        (s) =>
            s.testSourceIds.length == 2 &&
            s.testSourceIds.every((id) => s.devices.any((d) => d.id == id)) &&
            s.inputReady &&
            s.paused == 1,
        timeout: const Duration(minutes: 4),
      );
      final writerCheck = await Process.run(Platform.resolvedExecutable, [
        'tool/check_writer_lock.dart',
        '${session.dataRoot}/writer.lock',
      ]);
      if (writerCheck.exitCode != 0)
        throw StateError('The emulator does not hold its session writer lock');
      final a = session.status!.testSourceIds[0],
          b = session.status!.testSourceIds[1];
      if (game.emulator == 'Dolphin' && session.status!.consolePorts != 0)
        throw StateError('Unpaired GameCube console sockets are connected');
      final assignments = [
        PlayerAssignment(a),
        if (game.players > 1) PlayerAssignment(b),
      ];
      await atomicText(input, '64 0 3');
      await session.waitFor(
        (s) => s.devices.firstWhere((d) => d.id == a).pressed(6),
      );
      final revision = await session.command(assignments, active: true);
      await session.waitFor(
        (s) => s.ack == revision && s.blocked && s.paused == 1,
      );
      final held = jsonDecode(
        await File('${session.emulator!.root}/bridge-status.json')
            .readAsString(),
      ) as Map;
      if ((held['logicalButtons'] as List).any((b) => b != 0))
        throw StateError('Confirmation press leaked into the game');
      if (args.contains('--focus-broomm')) {
        final opened = await Process.run('/usr/bin/open', [
          '${Directory.current.path}/build/macos/Build/Products/Debug/broomm.app',
        ]);
        if (opened.exitCode != 0)
          throw StateError('Could not foreground Broomm');
        // Keep Start held until the child's own NSApplication confirms it lost
        // focus. Otherwise it could resume before the launcher actually opens.
        await session.waitFor((s) => !s.appActive && s.paused == 1);
      }
      await atomicText(input, '0 0 3');

      await session.waitFor(
        (s) => s.ack == revision && s.paused == 0 && !s.blocked,
      );
      stdout.writeln('${game.id}: resumed; checking live routes');
      final getterDeadline = DateTime.now().add(const Duration(seconds: 45));
      while (DateTime.now().isBefore(getterDeadline) && session.running) {
        final raw = jsonDecode(
          await File('${session.emulator!.root}/bridge-status.json')
              .readAsString(),
        ) as Map;
        if ((raw['queries'] as int) > 100) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      Future<Map<String, dynamic>> read() async => jsonDecode(
        await File('${session.emulator!.root}/bridge-status.json')
            .readAsString(),
      ) as Map<String, dynamic>;
      Future<void> output(int mask) async {
        final until = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(until)) {
          final status = await read();
          final driverMatches =
              game.emulator != 'RetroArch' ||
              (status['driverButtons'] as List).first == mask;
          if ((status['logicalButtons'] as List).first == mask && driverMatches)
            return;
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        throw StateError(
          'Logical port 1 never read expected mask $mask: ${await read()}',
        );
      }

      await atomicText(input, '1 2 3');
      await output(1);
      if (game.controllerTarget == ControllerTarget.wii)
        await atomicText(input, '0 0 3');
      final reordered = await session.command([
        PlayerAssignment(b),
        if (game.players > 1) PlayerAssignment(a),
      ], active: true);
      await session.waitFor(
        (s) => s.ack == reordered && !s.blocked && s.paused == 0,
      );
      await atomicText(input, '1 2 3');
      await output(2);
      if (game.controllerTarget == ControllerTarget.wii)
        await atomicText(input, '0 0 3');
      final flipped = await session.command([
        PlayerAssignment(b, swapFaces: true),
        if (game.players > 1) PlayerAssignment(a),
      ], active: true);
      await session.waitFor(
        (s) => s.ack == flipped && !s.blocked && s.paused == 0,
      );
      await atomicText(input, '1 2 3');
      await output(1);
      await atomicText(input, '4 8 3');
      await output(4); // Both face pairs are swapped, including X/Y.
      if (args.contains('--close-game-window')) {
        if (game.emulator != 'Ryubing')
          throw ArgumentError('Game-window-close fixture supports Ryubing');
        await atomicText(input, '0 0 3 0 1');
        final code = await exitResult.future.timeout(
          const Duration(seconds: 20),
        );
        if (code != 0) throw StateError('Closing the game window exited $code');
        results.add({
          'game': game.id,
          'emulator': game.emulator,
          'normalGameWindowClose': true,
          'gracefulExit': true,
          'physicalControllerAcceptance': false,
        });
        stdout.writeln(
          '${game.id}: PASS — normal game-window close and emulator exit',
        );
        continue;
      }
      // The currently paired source B presses R3 + Select.
      await atomicText(input, '0 272 3');
      await session.waitFor(
        (s) => s.request == 'menu' && s.blocked && s.paused == 1,
      );
      await output(0);
      await atomicText(input, '0 0 3');
      final resumed = await session.command([
        PlayerAssignment(b),
      ], active: true);
      await session.waitFor(
        (s) => s.ack == resumed && s.paused == 0 && !s.blocked,
      );
      if (game.controllerTarget == ControllerTarget.gamecube) {
        // The native SI update runs on emulated CPU ticks. Pause after it has
        // polled input so its real console devices can be inspected safely.
        await session.command([PlayerAssignment(b)], active: false);
        await session.waitFor((s) => s.paused == 1);
        if (session.status!.consolePorts != 1)
          throw StateError(
            'Expected one connected console pad, got ${session.status!.consolePorts}',
          );
        final two = await session.command([
          PlayerAssignment(a),
          PlayerAssignment(b),
        ], active: true);
        await session.waitFor((s) => s.ack == two && s.paused == 0);
        // A native unplug has a one-second emulated cooldown. The hotkey check
        // above proves input; this wait exercises reconnect after that cooldown.
        await Future<void>.delayed(const Duration(milliseconds: 1400));
        await session.command([
          PlayerAssignment(a),
          PlayerAssignment(b),
        ], active: false);
        await session.waitFor((s) => s.paused == 1);
        if (session.status!.consolePorts != 3)
          throw StateError(
            'Expected two connected console pads, got ${session.status!.consolePorts}',
          );
        final one = await session.command([PlayerAssignment(b)], active: true);
        await session.waitFor((s) => s.ack == one && s.paused == 0);
      }
      await atomicText(input, '0 0 1'); // Physically detach paired source B.
      await session.waitFor(
        (s) => s.request == 'disconnect' && s.blocked && s.paused == 1,
      );
      await output(0);
      if (args.contains('--bridge-outage')) {
        final lost = Completer<String>();
        session.onControlLost = (message) {
          if (!lost.isCompleted) lost.complete(message);
        };
        await atomicText(input, '0 0 1 1');
        await lost.future.timeout(const Duration(seconds: 8));
        if (session.status != null || !session.running)
          throw StateError(
            'Bridge outage did not invalidate status while retaining the writer',
          );
        final stillOwned = await Process.run(Platform.resolvedExecutable, [
          'tool/check_writer_lock.dart',
          '${session.dataRoot}/writer.lock',
        ]);
        if (stillOwned.exitCode != 0)
          throw StateError('Bridge outage released the live writer lock');
        await atomicText(input, '0 0 1 0');
        await session.waitFor((s) => s.paused == 1 && s.blocked);
        session.onControlLost = null;
      }
      final status = await read();
      if (game.emulator == 'Azahar' && status['watchDeferralVerified'] != true)
        throw StateError('SDL event-watch delivery was reentrant or unordered');
      if ((status['queries'] as int) == 0)
        throw StateError('No actual emulator SDL getters observed');
      results.add({
        'game': game.id,
        'emulator': game.emulator,
        'liveRoute': true,
        'liveSwap': true,
        'bothFacePairs': true,
        if (game.emulator == 'Azahar')
          'watchDeferralVerified': status['watchDeferralVerified'],
        'hotkeyPause': true,
        'disconnectPause': true,
        'emulatorQueries': status['queries'],
        'consumedPorts': status['consumedPorts'],
        'source': 'in-process SDL virtual test sources',
        'physicalControllerAcceptance': false,
        'writerLockOwnedByEmulator': true,
        'confirmationReleaseGate': true,
        'inputDiscoveryReady': true,
        if (game.controllerTarget == ControllerTarget.gamecube)
          'consoleSocketCounts': [0, 1, 2],
        if (game.emulator == 'RetroArch') 'nativeDriverSlotInput': true,
        'preconnectedTestSources': session.testPreconnected,
        'foregroundBroommBeforeResume': args.contains('--focus-broomm'),
        if (args.contains('--bridge-outage')) 'bridgeOutageRecovery': true,
      });
      stdout.writeln(
        '${game.id}: PASS — routes, remap, hotkey, pause/resume, disconnect',
      );
    } catch (e) {
      results.add({'game': game.id, 'error': '$e'});
      stderr.writeln('${game.id}: FAILED $e');
      exitCode = 1;
    } finally {
      if (session.running) {
        try {
          await session.stop();
          if (results.isNotEmpty && results.last['game'] == game.id)
            results.last['gracefulExit'] = true;
        } catch (e) {
          stderr.writeln('Graceful exit failed: $e');
          if (results.isNotEmpty && results.last['game'] == game.id) {
            results.last['gracefulExit'] = false;
            results.last['exitError'] = '$e';
          }
          exitCode = 1;
          break;
        }
      }
    }
  }
  await File('prototype-data/smoke-results.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'host': Platform.operatingSystemVersion,
      'results': results,
    }),
  );
}
