import 'dart:io';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/controller_mapping.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native snapshots preserve six axes and explicit controller family; old protocols fail visibly', () {
    final device = ControllerDevice.fromJson({
      'id': 0,
      'name': 'Generic controller',
      'buttons': 1,
      'x': 100,
      'y': -100,
      'rx': 16000,
      'ry': -32767,
      'lt': 32000,
      'rt': 0,
      'family': 3,
    });
    expect(device.inferredFamily, ControllerFamily.nintendo);
    expect(device.axis(3), -1);
    expect(device.lt, 32000);
    final status = {
      'protocol': 1,
      'pid': 1,
      'sample': 1,
      'ack': 1,
      'requestSerial': 0,
      'request': 'initial',
      'blocked': true,
      'paused': 1,
      'window': [0, 0, 100, 100],
      'devices': [],
    };
    expect(() => BridgeStatus(status), throwsFormatException);
    status['protocol'] = 3;
    expect(() => BridgeStatus(status), throwsFormatException);
    status['protocol'] = 4;
    expect(BridgeStatus(status).paused, 1);
  });
  test('both face pairs flip; target labels and both sticks/triggers follow actual routes', () {
    const p = PlayerAssignment(1, swapFaces: true);
    final ps = targetBindings(ControllerTarget.ps3, WiiMode.nunchuk);
    for (final e in {
      'Cross': 1,
      'Circle': 0,
      'Square': 3,
      'Triangle': 2,
    }.entries) {
      final d = ControllerDevice(1, 'Pad', 1 << e.value, 0, 0);
      expect(ps[e.key]!.read(d, p), 1);
      expect(ps.values.where((b) => b.read(d, p) > 0).length, 1);
    }
    const d = ControllerDevice(
      1,
      'Pad',
      0,
      16000,
      -32767,
      rx: -32767,
      ry: 16384,
      lt: 32767,
      rt: 0,
    );
    expect(ps['L2']!.read(d, p), 1);
    expect(ps['R2']!.read(d, p), 0);
    expect(ps['Left Stick/Up']!.read(d, p), 1);
    expect(ps['Right Stick/Left']!.read(d, p), 1);
    for (final target in [
      ControllerTarget.snes,
      ControllerTarget.n3ds,
      ControllerTarget.switchPro,
    ]) {
      final b = targetBindings(target, WiiMode.nunchuk);
      expect(b['A']!.read(const ControllerDevice(1, 'Pad', 1, 0, 0), p), 1);
      expect(b['X']!.read(const ControllerDevice(1, 'Pad', 4, 0, 0), p), 1);
    }
  });
  test('family guess respects target; eight Wii variants and progressive slots are bounded', () {
    final p = Pairing(4, target: ControllerTarget.wii);
    expect(p.visibleSlots, 1);
    p.join(
      1,
      device: const ControllerDevice(
        1,
        'Nintendo Switch Pro Controller',
        0,
        0,
        0,
      ),
    );
    expect(p.players.single.swapFaces, false);
    expect(p.visibleSlots, 2);
    final seen = <String>{};
    for (var i = 0; i < 8; i++) {
      seen.add('${p.players.single.wiiMode}:${p.players.single.swapFaces}');
      p.toggleLayout(1);
      if (i.isOdd) p.cycleMode(1);
    }
    expect(seen.length, 8);
    p.join(2, device: const ControllerDevice(2, 'Xbox Wireless', 0, 0, 0));
    expect(p.players.last.swapFaces, true);
    p.join(3);
    p.join(4);
    expect(p.visibleSlots, 4);
    p.leave(2);
    expect(p.visibleSlots, 4);
    p.leave(3);
    expect(p.visibleSlots, 3);
    final ps = Pairing(1, target: ControllerTarget.ps3)
      ..join(
        1,
        device: const ControllerDevice(1, 'Switch Pro Controller', 0, 0, 0),
      );
    expect(ps.players.single.swapFaces, true);
  });
  test('Wii generated configuration and tester share bindings; classic removes remote input', () async {
    final root = await Directory.systemTemp.createTemp('broomm-wii-config-');
    try {
      final e = PreparedEmulator('Dolphin', root.path, '', 3, null, null);
      await Directory('${e.user}/Config').create(recursive: true);
      for (final mode in WiiMode.values) {
        await const DolphinAdapter().prepareWii(e, [
          PlayerAssignment(1, wiiMode: mode),
        ], 27);
        final text = await File('${e.user}/Config/WiimoteNew.ini')
            .readAsString();
        final section = text.split('[Wiimote1]').last.split('[Wiimote2]').first;
        final bindings = wiiBindings(mode);
        for (final binding in bindings.entries)
          expect(
            section,
            contains('${binding.key} = ${binding.value.dolphin}'),
          );
        final p = PlayerAssignment(1, wiiMode: mode);
        const d = ControllerDevice(1, 'Pad', 1 << 6 | 1 << 4, 0, 0);
        final prefix = mode == WiiMode.classic
            ? 'Classic/Buttons/'
            : 'Buttons/';
        expect(bindings['${prefix}Home']!.read(d, p), 1);
        expect(bindings['${prefix}+']!.read(d, p), 0);
        expect(bindings['${prefix}-']!.read(d, p), 0);
        if (mode == WiiMode.classic)
          expect(section, isNot(contains('\nButtons/')));
      }
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('SNES and 3DS adapter configs use the same Nintendo diamond as the tester', () async {
    final root = await Directory.systemTemp.createTemp('broomm-faces-');
    try {
      final ra = PreparedEmulator('RetroArch', root.path, '', 3, null, 'core');
      await const RetroArchAdapter().prepare(ra, testGames.first, 'rom', 1234);
      final config = await File('${root.path}/retroarch.cfg').readAsString();
      for (final v in nintendoFaces.entries)
        expect(
          config,
          contains('input_player1_${v.key.toLowerCase()}_btn = "${v.value}"'),
        );
      final az = PreparedEmulator('Azahar', root.path, '', 2, null, null);
      await Directory('${az.user}/config').create(recursive: true);
      await File('${az.user}/config/qt-config.ini').writeAsString(
        [
          for (final k in ['a', 'b', 'x', 'y', 'zl', 'zr'])
            'profiles\\1\\button_$k=old',
        ].join('\n'),
      );
      await const AzaharAdapter().prepare(az, testGames[4], 'rom', 0);
      final text = await File('${az.user}/config/qt-config.ini').readAsString();
      for (final v in nintendoFaces.entries)
        expect(
          text,
          contains(
            'button_${v.key.toLowerCase()}="engine:sdl,api:controller,guid:ff0013db5669727475616c2043007601,port:0,button:${v.value}"',
          ),
        );
      expect(text, contains('axis:4,threshold:0.5,direction:+'));
    } finally {
      await root.delete(recursive: true);
    }
  });
}
