import 'package:broomm/src/pairing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'gyro preference follows identity and survives type, faces and reorder',
    () {
      final pairing = Pairing(4, target: ControllerTarget.wii)
        ..join(1)
        ..join(2);
      pairing.toggleGyro(1);
      pairing.toggleLayout(1);
      pairing.cycleMode(1);
      pairing.setWiiMode(1, WiiMode.upright);
      pairing.move(0, 1);
      expect(pairing.players.last.deviceId, 1);
      expect(pairing.players.last.gyroEnabled, false);
      expect(pairing.players.first.gyroEnabled, true);
      pairing.toggleGyro(99);
      pairing.toggleGyro(1);
      expect(pairing.players.last.gyroEnabled, true);
      expect(pairing.players.last.swapFaces, true);
      expect(pairing.players.last.wiiMode, WiiMode.upright);
    },
  );
  test('Wii type cycling preserves each player face orientation and face swaps preserve type', () {
    final p = Pairing(4, target: ControllerTarget.wii)
      ..join(0)
      ..join(42);
    p.toggleLayout(0);
    for (var i = 0; i < 4; i++) {
      final mode = p.players.first.wiiMode;
      p.toggleLayout(0);
      p.toggleLayout(0);
      expect(p.players.first.wiiMode, mode);
      p.cycleMode(0);
      expect(p.players.first.swapFaces, true);
      expect(p.players.last.wiiMode, WiiMode.nunchuk);
      expect(p.players.last.swapFaces, false);
    }
    expect(p.players.first.wiiMode, WiiMode.nunchuk);
    p.cycleMode(1234);
    expect(p.players.map((v) => v.deviceId), [0, 42]);
  });
  test('platforms without controller types ignore mode cycling', () {
    for (final target in ControllerTarget.values.where(
      (t) => t != ControllerTarget.wii,
    )) {
      final p = Pairing(1, target: target)..join(0);
      p.toggleLayout(0);
      final before = p.players.single;
      p.cycleMode(0);
      expect(p.players.single, same(before));
    }
  });
  const a = ControllerDevice(0, 'Same model', 0, 0, 0);
  const b = ControllerDevice(42, 'Same model', 0, 0, 0);
  test(
    'same-model controllers keep process identity, order and live layout',
    () {
      final pairing = Pairing(4);
      expect(pairing.join(a.id), isTrue);
      expect(pairing.join(b.id), isTrue);
      expect(pairing.join(a.id), isFalse);
      pairing.toggleLayout(b.id);
      pairing.move(1, -1);
      expect(pairing.players.map((p) => p.deviceId), [42, 0]);
      expect(pairing.players.first.swapFaces, isTrue);
      expect(pairing.valid([a, b]), isTrue);
    },
  );
  test(
    'disconnect removes only the missing source and needs explicit rejoin',
    () {
      final pairing = Pairing(4)
        ..join(0)
        ..join(42);
      pairing.removeDisconnected([b]);
      expect(pairing.players.single.deviceId, 42);
      pairing.removeDisconnected([a, b]);
      expect(pairing.players.length, 1);
      expect(pairing.join(0), isTrue);
      expect(pairing.players.map((p) => p.deviceId), [42, 0]);
    },
  );
  test('one-player systems and empty assignments cannot overfill or play', () {
    final pairing = Pairing(1);
    expect(pairing.valid([a]), isFalse);
    expect(pairing.join(0), isTrue);
    expect(pairing.join(42), isFalse);
    expect(pairing.valid([b]), isFalse);
    pairing.leave(0);
    expect(pairing.valid([a, b]), isFalse);
  });
}
