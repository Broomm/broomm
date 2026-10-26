import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/widgets/motion_tester.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'motion distinguishes unknown, absent, supported and failed samples',
    () {
      Map<String, dynamic> source() => {
        'id': 7,
        'name': 'Controller',
        'buttons': 0,
        'x': 0,
        'y': 0,
      };
      expect(ControllerDevice.fromJson(source()).sensors, -1);
      final none = ControllerDevice.fromJson({
        ...source(),
        'sensors': 0,
        'sensorReady': 3,
      });
      expect(none.accelerometerReady || none.gyroReady, isFalse);
      final partial = ControllerDevice.fromJson({
        ...source(),
        'sensors': 3,
        'sensorReady': 1,
        'accel': [1, 9, 2],
        'gyro': [0, 0, 0],
      });
      expect(partial.accelerometerReady, isTrue);
      expect(partial.gyroReady, isFalse);
      expect(partial.accel, [1.0, 9.0, 2.0]);
      expect(
        () => ControllerDevice.fromJson({
          ...source(),
          'gyro': [0, double.nan, 0],
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'Wii native motion follows paired identity and active Remote type',
    () async {
      final root = await Directory.systemTemp.createTemp('broomm-motion-');
      try {
        final e = PreparedEmulator('Dolphin', root.path, '', 3, null, null);
        await Directory('${e.user}/Config').create(recursive: true);
        Future<String> config(
          List<PlayerAssignment> players,
          List<ControllerDevice> devices,
        ) async {
          await const DolphinAdapter().prepareWii(
            e,
            players,
            1,
            devices: devices,
          );
          return File('${e.user}/Config/WiimoteNew.ini').readAsString();
        }

        const motion = ControllerDevice(
          12,
          'motion',
          0,
          0,
          0,
          sensors: 3,
          sensorReady: 3,
        );
        final full = await config([const PlayerAssignment(12)], [motion]);
        final first = full.split('[Wiimote2]').first;
        expect(first, contains('IMUAccelerometer/Up = `Accel Up`'));
        expect(first, contains('IMUGyroscope/Yaw Left = `Gyro Yaw Left`'));
        expect(first, contains('IMUIR/Enabled = True'));
        expect(first, contains('IMUIR/Recenter = `Thumb R` & !`Back`'));
        expect(first, isNot(contains('\nIR/Right =')));
        for (final mode in [WiiMode.upright, WiiMode.nunchuk]) {
          final disabled = (await config(
            [PlayerAssignment(12, wiiMode: mode, gyroEnabled: false)],
            [motion],
          )).split('[Wiimote2]').first;
          expect(disabled, contains('IMUIR/Enabled = False'));
          expect(disabled, contains('IR/Right = `Right X+`'));
          expect(disabled, contains('IR/Up = `Right Y+`'));
          expect(disabled, contains('IR/Recenter = `Thumb R` & !`Back`'));
          expect(disabled, isNot(contains('IMUGyroscope/Yaw Left')));
          expect(disabled, contains('IMUAccelerometer/Up'));
          final absent = (await config(
            [PlayerAssignment(99, wiiMode: mode)],
            [motion],
          )).split('[Wiimote2]').first;
          expect(absent, contains('IR/Right = `Right X+`'));
        }
        final classic = await config(
          [const PlayerAssignment(12, wiiMode: WiiMode.classic)],
          [motion],
        );
        expect(classic, isNot(contains('IMUGyroscope/Yaw Left')));
        expect(classic, isNot(contains('IMUIR/Enabled = True')));
        final other = await config([const PlayerAssignment(99)], [motion]);
        expect(other, isNot(contains('IMUAccelerometer/Up')));
        final partial = await config(
          [const PlayerAssignment(12)],
          [
            const ControllerDevice(
              12,
              'partial',
              0,
              0,
              0,
              sensors: 1,
              sensorReady: 1,
            ),
          ],
        );
        expect(partial, contains('IMUAccelerometer/Up'));
        expect(partial, isNot(contains('IMUGyroscope/Yaw Left')));
        expect(partial, isNot(contains('IMUIR/Enabled = True')));
        final recovering = await config(
          [const PlayerAssignment(12)],
          [
            const ControllerDevice(
              12,
              'temporarily unavailable',
              0,
              0,
              0,
              sensors: 3,
              sensorReady: 0,
            ),
          ],
        );
        expect(recovering, contains('IMUGyroscope/Yaw Left'));
        expect(recovering, contains('IMUIR/Enabled = True'));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    '3DS and Switch configure local native motion and preserve other settings',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'broomm-motion-config-',
      );
      try {
        final azahar = PreparedEmulator(
          'Azahar',
          '${root.path}/azahar',
          '',
          2,
          null,
          null,
        );
        final ini = File('${azahar.user}/config/qt-config.ini');
        await ini.parent.create(recursive: true);
        await ini.writeAsString(
          '[Controls]\nprofiles\\1\\motion_device="engine:motion_emu"\nprofiles\\1\\motion_device\\default=true\n[Other]\nvalue=keep\n',
        );
        await const AzaharAdapter().prepare(
          azahar,
          testGames.firstWhere((g) => g.id == 'mk7'),
          'rom',
          0,
        );
        final text = await ini.readAsString();
        expect(
          text,
          contains(
            'profiles\\1\\motion_device="engine:sdl,api:controller,guid:ff0013db5669727475616c2043007601,port:0"',
          ),
        );
        expect(text, contains('profiles\\1\\motion_device\\default=false'));
        expect(text, contains('value=keep'));
        final switchEmu = PreparedEmulator(
          'Ryubing',
          '${root.path}/switch',
          '',
          2,
          null,
          null,
        );
        final json = File('${switchEmu.user}/Config.json');
        await json.parent.create(recursive: true);
        await json.writeAsString(
          jsonEncode({
            'other': 'keep',
            'input_config': [
              {
                'right_joycon': {},
                'motion': {
                  'motion_backend': 'CemuHook',
                  'sensitivity': 75,
                  'gyro_deadzone': 2,
                  'enable_motion': false,
                },
              },
            ],
          }),
        );
        await const RyubingAdapter().prepare(
          switchEmu,
          testGames.firstWhere((g) => g.id == '3dworld'),
          'rom',
          0,
        );
        final cfg = jsonDecode(await json.readAsString()) as Map;
        expect(cfg['other'], 'keep');
        for (final player in cfg['input_config'] as List) {
          expect(player['motion']['enable_motion'], isTrue);
          expect(player['motion']['motion_backend'], 'GamepadDriver');
          expect(player['motion']['sensitivity'], 75);
          expect(player['motion']['gyro_deadzone'], 2);
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'motion tester exposes failures and target usage without inventing capability',
    (tester) async {
      Future<void> show(
        ControllerDevice d, {
        WiiMode mode = WiiMode.nunchuk,
        bool gyroEnabled = true,
      }) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MotionTester(
              device: d,
              target: ControllerTarget.wii,
              mode: mode,
              gyroEnabled: gyroEnabled,
            ),
          ),
        ),
      );
      await show(const ControllerDevice(1, 'unknown', 0, 0, 0));
      expect(find.textContaining('information unavailable'), findsOneWidget);
      await show(const ControllerDevice(1, 'none', 0, 0, 0, sensors: 0));
      expect(find.textContaining('no sensors exposed'), findsOneWidget);
      const partial = ControllerDevice(
        1,
        'partial',
        0,
        0,
        0,
        sensors: 3,
        sensorReady: 1,
        accel: [0, 9.8, 0],
      );
      await show(partial);
      expect(
        find.text('Some motion sensors are not returning data'),
        findsOneWidget,
      );
      expect(find.textContaining('Motion active'), findsOneWidget);
      await show(partial, mode: WiiMode.classic);
      expect(find.textContaining('does not use it'), findsOneWidget);
      expect(find.text('Gyro'), findsNothing);
      const full = ControllerDevice(
        1,
        'motion',
        0,
        0,
        0,
        sensors: 3,
        sensorReady: 3,
      );
      await show(full);
      expect(find.text('Gyro'), findsOneWidget);
      await show(full, gyroEnabled: false);
      expect(find.text('Gyro'), findsNothing);
      expect(find.text('Tilt / g'), findsNothing);
      expect(find.textContaining('Pointer: right stick'), findsOneWidget);
      await show(full);
      expect(find.text('Gyro'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
