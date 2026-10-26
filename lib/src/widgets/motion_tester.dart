import 'package:flutter/material.dart';

import '../pairing.dart';

class MotionTester extends StatelessWidget {
  const MotionTester({
    super.key,
    required this.device,
    required this.target,
    required this.mode,
    this.gyroEnabled = true,
  });
  final ControllerDevice device;
  final ControllerTarget target;
  final WiiMode mode;
  final bool gyroEnabled;
  bool get used =>
      target == ControllerTarget.ps3 ||
      target == ControllerTarget.n3ds ||
      target == ControllerTarget.switchPro ||
      (target == ControllerTarget.wii && mode != WiiMode.classic);
  bool get showBars => used && gyroEnabled && device.gyroReady;
  @override
  Widget build(BuildContext context) {
    final available = device.sensors > 0;
    final ready = device.accelerometerReady || device.gyroReady;
    final message = device.sensors < 0
        ? 'Motion: sensor information unavailable'
        : !available
        ? 'Motion: no sensors exposed by this controller / input driver'
        : !ready
        ? 'Motion: sensors detected · waiting for data'
        : !used
        ? 'Motion available · this controller type does not use it'
        : 'Motion active${!gyroEnabled ? ' · gyro off' : ''}${target == ControllerTarget.wii && gyroEnabled && device.gyroAvailable && device.accelerometerAvailable ? ' · R3 to recenter pointer' : ''}';
    final stickPointer =
        target == ControllerTarget.wii &&
        mode != WiiMode.classic &&
        !(gyroEnabled && device.gyroAvailable && device.accelerometerAvailable);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: ready && used ? const Color(0xff9bdfc0) : Colors.white60,
            ),
          ),
          if (stickPointer)
            const Text(
              'Pointer: right stick · R3 to recenter',
              style: TextStyle(fontSize: 11, color: Color(0xff9bdfc0)),
            ),
          if (showBars) ...[
            const SizedBox(height: 8),
            for (final sensor in [if (device.accelerometerReady) 0, 1])
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      sensor == 0 ? 'Tilt / g' : 'Gyro',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white60,
                      ),
                    ),
                  ),
                  for (var axis = 0; axis < 3; axis++)
                    Expanded(
                      child: _axis(
                        ['X', 'Y', 'Z'][axis],
                        (sensor == 0
                            ? device.accel[axis] / 9.80665
                            : device.gyro[axis]),
                        sensor == 0
                            ? device.accelerometerReady
                            : gyroEnabled && device.gyroReady,
                      ),
                    ),
                ],
              ),
          ],
          if (used &&
              device.sensors >= 0 &&
              device.sensors & ~device.sensorReady != 0)
            const Text(
              'Some motion sensors are not returning data',
              style: TextStyle(fontSize: 10, color: Colors.amber),
            ),
        ],
      ),
    );
  }

  Widget _axis(String label, double value, bool ready) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    child: Row(
      children: [
        Text(
          '$label ',
          style: const TextStyle(fontSize: 10, color: Colors.white60),
        ),
        Expanded(
          child: SizedBox(
            height: 5,
            child: LayoutBuilder(
              builder: (context, size) => Stack(
                children: [
                  Container(color: Colors.white12),
                  Positioned(
                    left: size.maxWidth / 2 - .5,
                    width: 1,
                    top: 0,
                    bottom: 0,
                    child: Container(color: Colors.white38),
                  ),
                  if (ready)
                    Positioned(
                      left: size.maxWidth * (.5 + value.clamp(-1.0, 0.0) / 2),
                      width: size.maxWidth * value.abs().clamp(0.0, 1.0) / 2,
                      top: 0,
                      bottom: 0,
                      child: Container(color: const Color(0xff9bdfc0)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
