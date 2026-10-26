import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/src/catalogue.dart';
import '../lib/src/emulators.dart';
import '../lib/src/pairing.dart';
import '../lib/src/session.dart';

// Real supplied Brawl ROM, private Dolphin, opt-in SDL source substitutes.
Future<void> main() async {
  final s = GameSession(
    Directory.current.path,
    testInputs: true,
    onProblem: stderr.writeln,
  );
  final results = <Map<String, dynamic>>[];
  try {
    await s.launch(testGames.firstWhere((g) => g.id == 'brawl'));
    final input = '${s.emulator!.root}/test-input.txt';
    await atomicText(input, '0 0 3');
    await s.waitFor(
      (v) =>
          v.paused == 1 &&
          v.testSourceIds.length == 2 &&
          v.devices.any((d) => d.id == v.testSourceIds.first),
      timeout: const Duration(minutes: 4),
    );
    final id = s.status!.testSourceIds.first;
    Future<Map<String, dynamic>> read() async => jsonDecode(
      await File('${s.emulator!.root}/bridge-status.json').readAsString(),
    ) as Map<String, dynamic>;
    Future<Map<String, dynamic>> until(
      bool Function(Map<String, dynamic>) ready,
    ) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      Map<String, dynamic> v = {};
      while (DateTime.now().isBefore(deadline)) {
        v = await read();
        if (ready(v)) return v;
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      throw StateError('Wii readback failed: $v');
    }

    final pairing = Pairing(4, target: ControllerTarget.wii)..join(id);
    for (final mode in WiiMode.values) {
      for (final flip in [false, true]) {
        stdout.writeln('${mode.label}, flip=$flip: native reload');
        await atomicText(input, '0 0 3');
        while (pairing.players.single.wiiMode != mode) pairing.cycleMode(id);
        if (pairing.players.single.swapFaces != flip) pairing.toggleLayout(id);
        final assignment = pairing.players.single;
        if (assignment.wiiMode != mode || assignment.swapFaces != flip)
          throw StateError('Controller type and face selection are coupled');
        final revision = await s.command([assignment], active: true);
        await s.waitFor(
          (v) => v.ack == revision && v.paused == 0 && !v.blocked,
        );
        final expected = mode == WiiMode.classic
            ? 0
            : flip
            ? 0x800
            : 0x400;
        await atomicText(input, '1 0 3');
        await until(
          (v) => ((v['wiiButtons'] as List).first as int) & 0xf00 == expected,
        );
        await atomicText(input, '4 0 3');
        final upper = mode == WiiMode.classic
            ? 0
            : flip
            ? 0x100
            : 0x200;
        await until(
          (v) => ((v['wiiButtons'] as List).first as int) & 0xf00 == upper,
        );
        await atomicText(input, '0 0 3');
        // Let the CPU apply the emulated extension-port transition, then
        // inspect its actual active extension only with the CPU paused.
        await Future<void>.delayed(const Duration(milliseconds: 1600));
        final pause = await s.command([assignment], active: false);
        await s.waitFor((v) => v.ack == pause && v.paused == 1);
        final ext = mode == WiiMode.classic
            ? 2
            : mode == WiiMode.nunchuk
            ? 1
            : 0;
        final v = await until(
          (v) =>
              (v['wiiApplied'] as int) >= pause &&
              (v['wiiSelected'] as List).first == ext &&
              (v['wiiActive'] as List).first == ext &&
              v['wiiSources'] == 1 &&
              v['consolePorts'] == 0,
        );
        results.add({
          'mode': mode.name,
          'swapFaces': flip,
          'reloadAcknowledged': true,
          'independentModeAndFaceSelection': true,
          'selectedExtension': (v['wiiSelected'] as List).first,
          'activeExtension': (v['wiiActive'] as List).first,
          'orientation': (v['wiiOrientation'] as List).first,
          'remoteFaceGetterVerified': mode != WiiMode.classic,
          'classicGameInputOwnerVerificationRequired': mode == WiiMode.classic,
          'wiiSourceMask': v['wiiSources'],
          'gamecubeSocketMask': v['consolePorts'],
          'pid': v['pid'],
        });
      }
    }
    final other = s.status!.testSourceIds.last;
    final mixed = [
      PlayerAssignment(id, wiiMode: WiiMode.nunchuk),
      PlayerAssignment(other, wiiMode: WiiMode.classic, swapFaces: true),
    ];
    final two = await s.command(mixed, active: true);
    await s.waitFor((v) => v.ack == two && !v.blocked && v.paused == 0);
    await atomicText(input, '1 2 3');
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    await atomicText(input, '0 0 3');
    final pause = await s.command(mixed, active: false);
    await s.waitFor((v) => v.ack == pause && v.paused == 1);
    await until(
      (v) =>
          v['wiiSources'] == 3 &&
          (v['wiiActive'] as List)[0] == 1 &&
          (v['wiiActive'] as List)[1] == 2 &&
          v['consolePorts'] == 0,
    );
    results.add({
      'mixedPlayers': true,
      'wiiSourceMask': 3,
      'activeExtensions': [1, 2],
      'gamecubeSocketMask': 0,
    });
    stdout.writeln(
      'PASS: all eight Wii variants in the same running Brawl session',
    );
  } catch (e) {
    stderr.writeln(e);
    exitCode = 1;
    results.add({'error': '$e'});
  } finally {
    if (s.running) await s.stop();
  }
  await File('prototype-data/wii-results.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'host': Platform.operatingSystemVersion,
      'results': results,
      'source': 'in-process SDL virtual test sources',
      'physicalControllerAcceptance': false,
    }),
  );
}
