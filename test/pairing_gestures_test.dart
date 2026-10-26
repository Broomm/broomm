import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/pairing_gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const shoulders = (1 << 9) | (1 << 10), start = 1 << 6, select = 1 << 4;
  ControllerDevice pad(int bits, int rt) =>
      ControllerDevice(7, 'Pad', bits, 0, 0, rt: rt);
  late PairingGestures g;
  setUp(() => g = PairingGestures());
  List<(int, PairingAction)> send(
    int bits,
    int ms, {
    bool enabled = true,
    bool joined = true,
    int rt = 0,
  }) => g.update(
    [pad(bits, rt)],
    joined ? {7} : {},
    Duration(milliseconds: ms),
    enabled: enabled,
  );
  test(
    'shoulder chord joins first and requests a controller mode after joining',
    () {
      expect(send(shoulders, 0, joined: false), isEmpty);
      send(0, 20, joined: false);
      expect(send(1 << 9, 30, joined: false), isEmpty);
      expect(send(shoulders, 40, joined: false), [(7, PairingAction.join)]);
      expect(send(shoulders, 2000), isEmpty);
      send(1 << 10, 2010);
      expect(send(shoulders, 2020), isEmpty);
      send(0, 2030);
      expect(send(shoulders, 2040), [(7, PairingAction.mode)]);
      send(0, 2050);
      for (final mask in [
        1,
        2,
        4,
        8,
        1 << 11,
        1 << 12,
        1 << 13,
        1 << 14,
        1 << 7,
        1 << 8,
      ]) {
        expect(send(mask, 2060), isEmpty);
      }
    },
  );
  test(
    'L3+R1 cycles paired layouts once and cannot become a held Start action',
    () {
      const chord = (1 << 7) | (1 << 10);
      send(0, 0);
      expect(send(chord, 20), [(7, PairingAction.layout)]);
      expect(send(chord | start, 2000), isEmpty);
      expect(
        g.progress(7, PairingAction.play, const Duration(milliseconds: 2000)),
        0,
      );
      expect(send(start, 2100), isEmpty); // Releasing L3 cannot start a hold.
      expect(send(start, 4100), isEmpty);
      send(0, 4200);
      send(start, 4300);
      expect(send(start, 5300), [(7, PairingAction.play)]);
      send(0, 5400);
      expect(send(chord, 5500), [(7, PairingAction.layout)]);
      expect(send(chord, 7500), isEmpty);
    },
  );
  test(
    'layout chord cannot join, inherit a Start hold, or survive lost readiness',
    () {
      const chord = (1 << 7) | (1 << 10);
      send(0, 0, joined: false);
      expect(send(chord, 100, joined: false), isEmpty);
      send(0, 200);
      send(start, 300);
      expect(send(chord | start, 900), [(7, PairingAction.layout)]);
      expect(send(start, 2000), isEmpty);
      expect(send(start, 4000), isEmpty);
      send(0, 4100);
      send(chord, 4200, enabled: false);
      expect(send(chord, 7000), isEmpty);
      send(0, 7100);
      expect(send(chord, 7200), [(7, PairingAction.layout)]);
    },
  );
  test('short Start/Select tests do nothing; continuous holds fire once', () {
    send(0, 0);
    send(start, 100);
    expect(send(start, 1099), isEmpty);
    expect(
      g.progress(7, PairingAction.play, const Duration(milliseconds: 600)),
      .5,
    );
    expect(send(start, 1100), [(7, PairingAction.play)]);
    expect(send(start, 4000), isEmpty);
    send(0, 4100);
    send(select, 4200);
    expect(send(0, 4500), isEmpty);
    send(select, 4600);
    expect(send(select, 5600), [(7, PairingAction.leave)]);
    expect(send(select, 9000), isEmpty);
  });
  test(
    'gyro trigger hysteresis, chord separation and fresh release are bounded',
    () {
      const l3 = 1 << 7, r1 = 1 << 10;
      send(0, 0);
      expect(send(l3, 10, rt: 16000), isEmpty);
      expect(send(l3, 20, rt: 17000), [(7, PairingAction.gyro)]);
      expect(send(l3, 30, rt: 12000), isEmpty);
      expect(send(l3, 40, rt: 18000), isEmpty);
      expect(send(l3 | r1, 50), isEmpty);
      send(0, 60);
      expect(send(l3 | r1, 70), [(7, PairingAction.layout)]);
      expect(send(l3, 80, rt: 32767), isEmpty);
      send(0, 90);
      expect(send(l3, 100, rt: 32767), [(7, PairingAction.gyro)]);
      send(0, 110, enabled: false);
      expect(send(l3, 120, rt: 32767), isEmpty);
      send(0, 130);
      expect(send(l3, 140, rt: 32767, joined: false), isEmpty);
      send(0, 150);
      expect(send(l3 | r1 | (1 << 9), 160, rt: 32767), isEmpty);
    },
  );
  test('overlay/Home chords, disconnect and unknown pause cannot carry holds into readiness', () {
    send(0, 0);
    send(select, 100);
    send(select | (1 << 8), 200);
    expect(send(select, 2000), isEmpty);
    send(0, 2100);
    send(start, 2200);
    send(start | select, 2300);
    expect(send(start, 4000), isEmpty);
    send(0, 4100);
    send(start, 4200);
    send(start, 4300, enabled: false);
    expect(send(start, 6000), isEmpty);
    send(0, 6100);
    send(start, 6200);
    g.update([], {}, const Duration(milliseconds: 6300), enabled: true);
    expect(send(start, 8000), isEmpty);
    send(0, 8100);
    send(start, 8200);
    expect(send(start, 9200), [(7, PairingAction.play)]);
  });
}
