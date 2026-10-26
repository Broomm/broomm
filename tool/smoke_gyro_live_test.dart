import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/app_model.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/host.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

// Native integration test, explicitly invoked with real ROMs/bridges provisioned.
// Host presentation is suppressed; the real Dart model and process/session run.
class _NoPresentation extends DesktopHost {
  @override
  Future<void> show({List<double>? frame, bool overlay = false}) async {}
  @override
  Future<void> hide(int pid) async {}
}

void main() {
  test('live gyro shortcut and vertical Remote pointer fallback', () async {
    final s = GameSession(
      Directory.current.path,
      testInputs: true,
      testMotion: true,
      onProblem: stderr.writeln,
    );
    final m = PrototypeModel(
      Directory.current.path,
      host: _NoPresentation(),
      gameSession: s,
    );
    final results = <Map<String, dynamic>>[];
    try {
      await m.select(testGames.firstWhere((g) => g.id == 'brawl'));
      if (m.error != null) throw StateError(m.error!);
      final input = '${s.emulator!.root}/test-input.txt';
      final motion = '${s.emulator!.root}/test-motion.txt';
      Future<void> write({
        int maskA = 0,
        bool triggerA = false,
        int maskB = 0,
        bool triggerB = false,
      }) => atomicText(
        input,
        '$maskA $maskB 3 0 0 25000 -25000 ${triggerA ? 32767 : -32768} -25000 25000 ${triggerB ? 32767 : -32768}',
      );
      await write();
      await atomicText(motion, '3 3 1 9 2 .1 .2 .3\n1 1 -3 8 -4 0 0 0\n');
      await s.waitFor(
        (v) =>
            m.screen == Screen.pairing &&
            m.canPair &&
            v.paused == 1 &&
            v.testSourceIds.length == 2 &&
            v.devices.any(
              (d) => d.id == v.testSourceIds[0] && d.sensorReady == 3,
            ),
        timeout: const Duration(minutes: 4),
      );
      final a = s.status!.testSourceIds[0], b = s.status!.testSourceIds[1];
      m.join(a);
      Future<Map<String, dynamic>> until(
        bool Function(Map<String, dynamic>) ready,
      ) async {
        final end = DateTime.now().add(const Duration(seconds: 25));
        Map<String, dynamic> v = {};
        while (DateTime.now().isBefore(end)) {
          v = jsonDecode(
            await File('${s.emulator!.root}/bridge-status.json').readAsString(),
          ) as Map<String, dynamic>;
          if (m.error != null) throw StateError(m.error!);
          if (ready(v)) return v;
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        throw StateError(
          'Live gyro/pointer readback failed: $v; screen=${m.screen}, busy=${m.busy}',
        );
      }

      bool pointer(Map<String, dynamic> v, bool stick, {bool sourceB = false}) {
        final xy = v['wiiPointer'][0] as List;
        return stick
            ? sourceB
                  ? xy.every((n) => (n as num) < -.5)
                  : xy.every((n) => (n as num) > .5)
            : xy.every((n) => (n as num).abs() < .001);
      }

      Future<void> chord(bool on) async {
        final serial = s.status!.requestSerial;
        await write(maskA: 1 << 7, triggerA: true);
        final held = await until(
          (v) =>
              v['request'] == 'gyro' &&
              v['requestSerial'] > serial &&
              v['blocked'] == true &&
              v['paused'] == 1 &&
              v['gyroEnabled'][0] == (on ? 1 : 0),
        );
        expect((held['logicalButtons'] as List).every((b) => b == 0), true);
        // A held analog chord stays gated and is consumed exactly once.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(m.pairing!.players.single.gyroEnabled, on);
        expect(s.status!.requestSerial, serial + 1);
        await write();
        await until(
          (v) =>
              m.screen == Screen.playing &&
              !m.busy &&
              v['paused'] == 0 &&
              v['blocked'] == false,
        );
      }

      for (final mode in [WiiMode.upright, WiiMode.nunchuk]) {
        if (m.screen == Screen.playing) {
          await m.menu();
          m.showPairing();
        }
        m.wiiMode(a, mode);
        await m.play();
        await until(
          (v) =>
              pointer(v, false) && (v['consumedMotion'][0][1][0] as num) > .09,
        );
        await chord(false);
        await until(
          (v) =>
              pointer(v, true) &&
              (v['logicalMotion'][0][1] as List).every((n) => n == 0) &&
              v['logicalMotion'][0][0][0] == 1,
        );
        await chord(true);
        await until(
          (v) =>
              pointer(v, false) && (v['consumedMotion'][0][1][0] as num) > .09,
        );
        results.add({
          'mode': mode.name,
          'liveModelShortcut': true,
          'heldChordOnce': true,
          'gyroOffKeepsAcceleration': true,
          'stickFallbackNativeRawInput': true,
          'gyroOnUnbindsStickPointer': true,
          'sameProcess': s.status!.pid,
        });
      }
      await m.menu();
      m.showPairing();
      m.leave(a);
      m.join(b);
      m.wiiMode(b, WiiMode.upright);
      await m.play();
      await until((v) => pointer(v, true, sourceB: true));
      results.add({
        'sourceWithoutGyro': true,
        'stickFallbackNativeRawInput': true,
        'sameProcess': s.status!.pid,
      });
    } finally {
      if (s.running) await s.stop();
      await File('prototype-data/gyro-live-results.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'host': Platform.operatingSystemVersion,
          'results': results,
          'source': 'synthetic sources; actual Brawl, bridge, Dart model and native Cursor::GetState(false)',
          'gameIRCameraOrPhysicalFeelAccepted': false,
        }),
      );
    }
  }, timeout: const Timeout(Duration(minutes: 7)));
}
