import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../controller_mapping.dart';
import '../pairing.dart';

class ControllerTester extends StatelessWidget {
  const ControllerTester({
    super.key,
    required this.target,
    required this.assignment,
    this.device,
    this.miniature = false,
  });
  final ControllerTarget target;
  final PlayerAssignment assignment;
  final ControllerDevice? device;
  final bool miniature;
  Map<String, double> get values => device == null
      ? const {}
      : {
          for (final v in targetBindings(
            target,
            assignment.wiiMode,
            pointerFromStick: assignment.stickPointer(device),
          ).entries)
            v.key: device == null ? 0 : v.value.read(device!, assignment),
        };
  @override
  Widget build(BuildContext context) {
    final input = values;
    return RepaintBoundary(
      child: Semantics(
        label: miniature
            ? assignment.wiiMode.label
            : 'Target controller. ${input.entries.where((e) => e.value > .2).map((e) => e.key).join(', ')}',
        child: CustomPaint(
          size: const Size(500, 300),
          painter: _ControllerPainter(target, assignment.wiiMode, input),
        ),
      ),
    );
  }
}

// Original vector silhouettes; the controls represent the adapter's target,
// rather than labels printed on the physical source controller.
class _ControllerPainter extends CustomPainter {
  _ControllerPainter(this.target, this.mode, this.values);
  final ControllerTarget target;
  final WiiMode mode;
  final Map<String, double> values;
  static const active = Color(0xff9bffd6);
  final body = Paint()..color = const Color(0xff3a4657);
  final edge = Paint()
    ..color = const Color(0xff64748a)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  late Canvas c;
  bool on(String key) => (values[key] ?? 0) > .5;
  void text(
    String label,
    Offset p, {
    double size = 14,
    Color color = const Color(0xffecf2ff),
  }) {
    final t = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: size,
          fontFamily: 'Helvetica Neue',
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    t.paint(c, p - Offset(t.width / 2, t.height / 2));
    t.dispose();
  }

  void shell(Rect r, double radius) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
    c.drawRRect(rr, body);
    c.drawRRect(rr, edge);
  }

  void button(
    String key,
    String label,
    double x,
    double y, {
    double radius = 17,
    Color? color,
  }) {
    final p = Offset(x, y), lit = on(key);
    if (lit)
      c.drawCircle(
        p,
        radius + 5,
        Paint()..color = active.withValues(alpha: .16),
      );
    c.drawCircle(
      p,
      radius,
      Paint()..color = lit ? active : const Color(0xff172231),
    );
    c.drawCircle(
      p,
      radius,
      Paint()
        ..color = lit ? active : (color ?? const Color(0xff8b9bb0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final ink = lit
        ? const Color(0xff0b3027)
        : (color ?? const Color(0xffe1e9f5));
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    if (target.isPlayStation && ['×', '○', '□', '△'].contains(label)) {
      final r = radius * .45;
      switch (label) {
        case '×':
          c.drawLine(p + Offset(-r, -r), p + Offset(r, r), pen);
          c.drawLine(p + Offset(r, -r), p + Offset(-r, r), pen);
        case '○':
          c.drawCircle(p, r, pen);
        case '□':
          c.drawRect(
            Rect.fromCenter(center: p, width: r * 2, height: r * 2),
            pen,
          );
        case '△':
          c.drawPath(
            Path()
              ..moveTo(p.dx, p.dy - r)
              ..lineTo(p.dx + r, p.dy + r)
              ..lineTo(p.dx - r, p.dy + r)
              ..close(),
            pen,
          );
      }
    } else if (label == '⌂') {
      c.drawPath(
        Path()
          ..moveTo(p.dx - 4, p.dy)
          ..lineTo(p.dx, p.dy - 4)
          ..lineTo(p.dx + 4, p.dy)
          ..lineTo(p.dx + 4, p.dy + 4)
          ..lineTo(p.dx - 4, p.dy + 4)
          ..close(),
        pen,
      );
    } else {
      text(
        label,
        p,
        size: label.length > 2
            ? 9
            : radius < 14
            ? 11
            : 16,
        color: ink,
      );
    }
  }

  void pill(String key, String label, double x, double y, {double width = 54}) {
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, y), width: width, height: 23),
      const Radius.circular(8),
    );
    c.drawRRect(r, Paint()..color = on(key) ? active : const Color(0xff172231));
    text(
      label,
      Offset(x, y),
      size: 11,
      color: on(key) ? const Color(0xff0b3027) : const Color(0xffe1e9f5),
    );
  }

  void dpad(double x, double y, {String prefix = '', double step = 20}) {
    for (final entry in {
      'Up': Offset(0, -step),
      'Down': Offset(0, step),
      'Left': Offset(-step, 0),
      'Right': Offset(step, 0),
    }.entries) {
      final p = Offset(x, y) + entry.value;
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: p, width: step * .9, height: step * .9),
        const Radius.circular(3),
      );
      c.drawRRect(
        r,
        Paint()
          ..color = on('$prefix${entry.key}')
              ? active
              : const Color(0xff111c29),
      );
    }
    c.drawCircle(Offset(x, y), 7, Paint()..color = const Color(0xff111c29));
  }

  void stick(
    String prefix,
    double x,
    double y, {
    String? click,
    String? label,
    double radius = 24,
  }) {
    final dx = (values['$prefix/Right'] ?? 0) - (values['$prefix/Left'] ?? 0);
    final dy = (values['$prefix/Down'] ?? 0) - (values['$prefix/Up'] ?? 0);
    final p = Offset(x, y), moved = dx.abs() > .12 || dy.abs() > .12;
    c.drawCircle(p, radius + 4, Paint()..color = const Color(0xff15202e));
    c.drawCircle(
      p + Offset(dx * 9, dy * 9),
      radius - 4,
      Paint()
        ..color = (click != null && on(click)) || moved
            ? active
            : const Color(0xff657388),
    );
    text(
      label ?? '',
      p + Offset(dx * 9, dy * 9),
      size: 10,
      color: const Color(0xff142133),
    );
  }

  void diamond(
    Map<String, String> labels,
    double x,
    double y, {
    String prefix = '',
    double step = 30,
  }) {
    final offsets = [
      Offset(0, step),
      Offset(step, 0),
      Offset(-step, 0),
      Offset(0, -step),
    ];
    var i = 0;
    for (final e in labels.entries) {
      final p = Offset(x, y) + offsets[i++];
      button(
        '$prefix${e.key}',
        e.value,
        p.dx,
        p.dy,
        radius: 15,
        color: target.isPlayStation
            ? [
                const Color(0xffa6c8ff),
                const Color(0xffff999e),
                const Color(0xffe4b0d9),
                const Color(0xff99e6c8),
              ][i - 1]
            : null,
      );
    }
  }

  void grips() {
    final p = Path()
      ..moveTo(145, 78)
      ..cubicTo(100, 62, 81, 114, 65, 211)
      ..cubicTo(60, 253, 95, 274, 125, 240)
      ..lineTo(173, 197)
      ..lineTo(327, 197)
      ..lineTo(375, 240)
      ..cubicTo(405, 274, 440, 253, 435, 211)
      ..cubicTo(419, 114, 400, 62, 355, 78)
      ..close();
    c.drawPath(p, body);
    c.drawPath(p, edge);
  }

  void gamepad() {
    if (target == ControllerTarget.psp) {
      psp();
      return;
    }
    final ps = target.isPlayStation;
    final gc = target == ControllerTarget.gamecube;
    final classic = target == ControllerTarget.wii;
    final prefix = classic ? 'Classic/' : '';
    grips();
    text(
      ps
          ? switch (target) {
              ControllerTarget.psx => 'DUALSHOCK',
              ControllerTarget.ps2 => 'DUALSHOCK 2',
              _ => 'DUALSHOCK 3',
            }
          : gc
          ? 'GAMECUBE'
          : classic
          ? 'CLASSIC'
          : 'PRO CONTROLLER',
      const Offset(250, 98),
      size: 10,
      color: const Color(0xffb8c4d4),
    );
    if (gc) {
      pill('L', 'L', 130, 66);
      pill('R', 'R', 370, 66);
      pill('Z', 'Z', 398, 94, width: 32);
      button('A', 'A', 360, 148, radius: 25, color: const Color(0xff86d4bd));
      button('B', 'B', 322, 175, radius: 14, color: const Color(0xfff5a9a2));
      pill('X', 'X', 400, 137, width: 30);
      pill('Y', 'Y', 357, 105, width: 40);
      stick('Left Stick', 140, 136);
      stick('Right Stick', 310, 212, label: 'C', radius: 20);
      dpad(204, 208, step: 16);
      button('Start', 'START', 250, 149, radius: 16);
      return;
    }
    if (ps) {
      pill('L2', 'L2', 130, 43);
      pill('R2', 'R2', 370, 43);
      pill('L1', 'L1', 130, 70);
      pill('R1', 'R1', 370, 70);
      dpad(140, 141);
      diamond(
        {'Cross': '×', 'Circle': '○', 'Square': '□', 'Triangle': '△'},
        360,
        141,
      );
      stick('Left Stick', 204, 207, click: 'L3', label: 'L3');
      stick('Right Stick', 296, 207, click: 'R3', label: 'R3');
    } else {
      pill('${prefix}${classic ? 'Buttons/' : ''}ZL', 'ZL', 130, 43);
      pill('${prefix}${classic ? 'Buttons/' : ''}ZR', 'ZR', 370, 43);
      pill('${prefix}${classic ? 'Triggers/' : ''}L', 'L', 130, 70);
      pill('${prefix}${classic ? 'Triggers/' : ''}R', 'R', 370, 70);
      if (classic) {
        dpad(140, 141, prefix: 'Classic/D-Pad/');
        stick('Classic/Left Stick', 204, 207);
        stick('Classic/Right Stick', 296, 207);
      } else {
        stick('Left Stick', 140, 141, click: 'L3');
        dpad(204, 207);
        stick('Right Stick', 296, 207, click: 'R3');
      }
      diamond(
        {'B': 'B', 'A': 'A', 'Y': 'Y', 'X': 'X'},
        360,
        141,
        prefix: classic ? 'Classic/Buttons/' : '',
      );
    }
    pill(
      classic ? 'Classic/Buttons/-' : 'Select',
      ps ? 'SELECT' : '−',
      223,
      142,
      width: 40,
    );
    pill(
      classic ? 'Classic/Buttons/+' : 'Start',
      ps ? 'START' : '+',
      278,
      142,
      width: 40,
    );
    if (classic) button('Classic/Buttons/Home', '⌂', 250, 176, radius: 12);
    if (target == ControllerTarget.ps3)
      button('PS', 'PS', 250, 176, radius: 12);
  }

  void snes() {
    shell(const Rect.fromLTWH(70, 90, 360, 155), 70);
    pill('L', 'L', 138, 78, width: 85);
    pill('R', 'R', 362, 78, width: 85);
    dpad(147, 165, step: 23);
    diamond({'B': 'B', 'A': 'A', 'Y': 'Y', 'X': 'X'}, 355, 165, step: 31);
    pill('Select', 'SELECT', 224, 186, width: 48);
    pill('Start', 'START', 279, 186, width: 48);
    text(
      'SUPER NINTENDO',
      const Offset(250, 120),
      size: 10,
      color: const Color(0xffbcc6d8),
    );
  }

  void psp() {
    shell(const Rect.fromLTWH(36, 56, 428, 190), 58);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(157, 80, 186, 132),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xff14202e),
    );
    text(
      'PSP',
      const Offset(250, 147),
      size: 26,
      color: const Color(0xff718896),
    );
    pill('L', 'L', 102, 48, width: 64);
    pill('R', 'R', 398, 48, width: 64);
    dpad(100, 125, step: 20);
    stick('Left Stick', 102, 203, radius: 18);
    diamond(
      {'Cross': '×', 'Circle': '○', 'Square': '□', 'Triangle': '△'},
      399,
      133,
      step: 25,
    );
    pill('Select', 'SELECT', 340, 228, width: 43);
    pill('Start', 'START', 393, 228, width: 43);
  }

  void handheld() {
    shell(const Rect.fromLTWH(100, 8, 300, 133), 12);
    shell(const Rect.fromLTWH(100, 149, 300, 143), 12);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(151, 26, 198, 101),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xff14202e),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(183, 165, 134, 109),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xff14202e),
    );
    text(
      target == ControllerTarget.nds ? 'NINTENDO DS' : 'NINTENDO 3DS',
      const Offset(250, 78),
      size: 14,
      color: const Color(0xff8394ae),
    );
    if (target != ControllerTarget.nds)
      stick('Left Stick', 140, 188, radius: 16);
    dpad(141, 247, step: 14);
    diamond({'B': 'B', 'A': 'A', 'Y': 'Y', 'X': 'X'}, 356, 225, step: 22);
    if (target != ControllerTarget.nds)
      stick('Right Stick', 324, 177, radius: 10);
    pill('Select', 'SELECT', 223, 283, width: 40);
    pill('Start', 'START', 279, 283, width: 40);
    pill('L', 'L', 122, 141, width: 33);
    if (target != ControllerTarget.nds) pill('ZL', 'ZL', 163, 141, width: 33);
    if (target != ControllerTarget.nds) pill('ZR', 'ZR', 337, 141, width: 33);
    pill('R', 'R', 378, 141, width: 33);
  }

  void remote() {
    final side = mode == WiiMode.sideways, nun = mode == WiiMode.nunchuk;
    if (side) {
      shell(const Rect.fromLTWH(70, 112, 360, 90), 18);
      dpad(118, 157, step: 16);
      button('Buttons/A', 'A', 177, 157, radius: 16);
      pill('Buttons/-', '−', 221, 157, width: 26);
      button('Buttons/Home', '⌂', 253, 157, radius: 10);
      pill('Buttons/+', '+', 285, 157, width: 26);
      button('Buttons/1', '1', 344, 157);
      button('Buttons/2', '2', 391, 157);
      pill('Buttons/B', 'B · back', 185, 211, width: 64);
    } else {
      final x = nun ? 307.0 : 250.0;
      shell(Rect.fromLTWH(x - 37, 7, 74, 280), 16);
      dpad(x, 50, step: 16);
      button('Buttons/A', 'A', x, 105, radius: 18);
      pill('Buttons/-', '−', x - 23, 145, width: 18);
      button('Buttons/Home', '⌂', x, 145, radius: 9);
      pill('Buttons/+', '+', x + 23, 145, width: 18);
      button('Buttons/1', '1', x, 217, radius: 14);
      button('Buttons/2', '2', x, 251, radius: 14);
      pill('Buttons/B', 'B · back', x + 85, 104, width: 70);
      for (var i = 0; i < 4; i++)
        c.drawCircle(
          Offset(x - 18 + i * 12, 274),
          3,
          Paint()..color = const Color(0xff79a9e8),
        );
      if (nun) {
        final cable = Path()
          ..moveTo(175, 224)
          ..cubicTo(169, 300, 245, 305, 307, 285);
        c.drawPath(
          cable,
          Paint()
            ..color = const Color(0xff8492a6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        shell(const Rect.fromLTWH(136, 90, 76, 148), 34);
        stick('Nunchuk/Stick', 174, 130, radius: 22);
        pill('Nunchuk/Buttons/C', 'C', 174, 178, width: 42);
        pill('Nunchuk/Buttons/Z', 'Z', 174, 211, width: 42);
      }
    }
    stick('IR', side ? 250 : 420, side ? 258 : 207, label: 'IR', radius: 19);
    pill('Shake/X', 'SHAKE', side ? 350 : 420, side ? 257 : 254, width: 66);
  }

  @override
  void paint(Canvas canvas, Size size) {
    c = canvas;
    c.save();
    final scale = (size.width / 500).clamp(0.0, size.height / 300);
    c.translate(
      (size.width - 500 * scale) / 2,
      (size.height - 300 * scale) / 2,
    );
    c.scale(scale);
    if (retroBindings(target) case final bindings?) {
      shell(const Rect.fromLTWH(65, 30, 370, 240), 40);
      text(target.name.toUpperCase(), const Offset(250, 53), size: 13);
      dpad(130, 150);
      final keys = bindings.keys
          .where(
            (k) =>
                !{'Up', 'Down', 'Left', 'Right'}.contains(k) &&
                !k.contains('/'),
          )
          .toList();
      for (var i = 0; i < keys.length; i++) {
        final x = 210.0 + i % 4 * 52;
        final y = 102.0 + i ~/ 4 * 56;
        button(keys[i], keys[i], x, y, radius: keys[i].length > 3 ? 22 : 17);
      }
      if (bindings.containsKey('Left Stick/Up'))
        stick('Left Stick', 130, 222, radius: 23);
      if (bindings.containsKey('C/Up'))
        stick('C', 364, 225, label: 'C', radius: 23);
    } else
      switch (target) {
        case ControllerTarget.snes:
          snes();
        case ControllerTarget.n3ds:
        case ControllerTarget.nds:
          handheld();
        case ControllerTarget.wii:
          if (mode == WiiMode.classic) {
            gamepad();
          } else {
            remote();
          }
        default:
          gamepad();
      }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _ControllerPainter old) =>
      target != old.target ||
      mode != old.mode ||
      !mapEquals(values, old.values);
}
