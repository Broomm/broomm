import 'pairing.dart';

// SDL inputs are positional on every runtime, including SDL2 (child-scoped hint).
const nintendoFaces = {'A': 1, 'B': 0, 'X': 3, 'Y': 2};
const dpadButtons = {'Up': 11, 'Down': 12, 'Left': 13, 'Right': 14};
const _dolphinButtons = [
  'Button A',
  'Button B',
  'Button X',
  'Button Y',
  'Back',
  'Guide',
  'Start',
  'Thumb L',
  'Thumb R',
  'Shoulder L',
  'Shoulder R',
  'Pad N',
  'Pad S',
  'Pad W',
  'Pad E',
];
const _dolphinAxes = [
  'Left X',
  'Left Y',
  'Right X',
  'Right Y',
  'Trigger L',
  'Trigger R',
];

class InputBinding {
  const InputBinding.button(this.button)
    : axis = null,
      sign = 1,
      alternatives = const [],
      excluded = const [],
      required = const [];
  const InputBinding.axis(this.axis, [this.sign = 1])
    : button = null,
      alternatives = const [],
      excluded = const [],
      required = const [];
  const InputBinding.any(this.alternatives)
    : button = null,
      axis = null,
      sign = 1,
      excluded = const [],
      required = const [];
  const InputBinding.chord(this.required, [this.excluded = const []])
    : button = null,
      axis = null,
      sign = 1,
      alternatives = const [];
  final int? button, axis;
  final int sign;
  final List<InputBinding> alternatives;
  final List<int> required, excluded;
  double read(ControllerDevice d, PlayerAssignment p) {
    bool pressed(int b) => d.pressed(p.sourceButton(b));
    if (button != null) return pressed(button!) ? 1 : 0;
    if (axis != null) return (d.axis(axis!) * sign).clamp(0, 1);
    if (alternatives.isNotEmpty)
      return alternatives
          .map((b) => b.read(d, p))
          .reduce((a, b) => a > b ? a : b);
    return required.every(pressed) && !excluded.any(pressed) ? 1 : 0;
  }

  String get dolphin {
    String key(int b) => '`${_dolphinButtons[b]}`';
    if (button != null) return key(button!);
    if (axis != null) {
      final a = axis!;
      if (a >= 4) return '`${_dolphinAxes[a]}`';
      final direction = (a.isOdd ? -sign : sign) > 0 ? '+' : '-';
      return '`${_dolphinAxes[a]}$direction`';
    }
    if (alternatives.isNotEmpty)
      return alternatives.map((b) => b.dolphin).join(' | ');
    return [
      ...required.map(key),
      ...excluded.map((b) => '!${key(b)}'),
    ].join(' & ');
  }
}

Map<String, InputBinding> wiiBindings(
  WiiMode mode, {
  bool pointerFromStick = true,
}) {
  const b = InputBinding.button, a = InputBinding.axis;
  const plus = InputBinding.chord([6], [4]);
  const minus = InputBinding.chord([4], [6, 8]);
  const home = InputBinding.chord([4, 6]);
  if (mode == WiiMode.classic)
    return {
      for (final v in nintendoFaces.entries)
        'Classic/Buttons/${v.key}': b(v.value),
      'Classic/Buttons/+': plus,
      'Classic/Buttons/-': minus,
      'Classic/Buttons/Home': home,
      'Classic/Buttons/ZL': a(4),
      'Classic/Buttons/ZR': a(5),
      'Classic/Triggers/L': b(9),
      'Classic/Triggers/R': b(10),
      'Classic/Triggers/L-Analog': b(9),
      'Classic/Triggers/R-Analog': b(10),
      for (final v in dpadButtons.entries) 'Classic/D-Pad/${v.key}': b(v.value),
      ..._stickBindings('Classic/Left Stick', 0),
      ..._stickBindings('Classic/Right Stick', 2),
    };
  return {
    'Buttons/A': b(1),
    'Buttons/B': b(0),
    'Buttons/1': b(2),
    'Buttons/2': b(3),
    'Buttons/+': plus,
    'Buttons/-': minus,
    'Buttons/Home': home,
    for (final v in dpadButtons.entries)
      'D-Pad/${v.key}': mode == WiiMode.nunchuk
          ? b(v.value)
          : InputBinding.any([b(v.value), _direction(v.key, 0)]),
    'Shake/X': b(10),
    'Shake/Y': b(10),
    'Shake/Z': b(10),
    if (pointerFromStick) ..._stickBindings('IR', 2),
    if (mode == WiiMode.nunchuk) ...{
      'Nunchuk/Buttons/C': b(9),
      'Nunchuk/Buttons/Z': a(4),
      ..._stickBindings('Nunchuk/Stick', 0),
    },
  };
}

InputBinding _direction(String direction, int axis) => switch (direction) {
  'Left' => InputBinding.axis(axis, -1),
  'Right' => InputBinding.axis(axis),
  'Up' => InputBinding.axis(axis + 1, -1),
  _ => InputBinding.axis(axis + 1),
};
Map<String, InputBinding> _stickBindings(String prefix, int axis) => {
  for (final dir in ['Up', 'Down', 'Left', 'Right'])
    '$prefix/$dir': _direction(dir, axis),
};

Map<String, InputBinding> targetBindings(
  ControllerTarget target,
  WiiMode mode, {
  bool pointerFromStick = true,
}) {
  final retro = retroBindings(target);
  if (retro != null) return retro;
  const b = InputBinding.button, a = InputBinding.axis;
  if (target == ControllerTarget.wii)
    return wiiBindings(mode, pointerFromStick: pointerFromStick);
  return {
    if (target == ControllerTarget.psp) ...{
      'Cross': b(0),
      'Circle': b(1),
      'Square': b(2),
      'Triangle': b(3),
      'L': b(9),
      'R': b(10),
    } else if (target.isPlayStation) ...{
      'Cross': b(0),
      'Circle': b(1),
      'Square': b(2),
      'Triangle': b(3),
      'L1': b(9),
      'R1': b(10),
      'L2': a(4),
      'R2': a(5),
      'L3': b(7),
      'R3': b(8),
      if (target == ControllerTarget.ps3) 'PS': b(5),
    } else if (target == ControllerTarget.gamecube) ...{
      'A': b(0),
      'B': b(1),
      'X': b(2),
      'Y': b(3),
      'Z': b(10),
      'L': a(4),
      'R': a(5),
    } else ...{
      for (final v in nintendoFaces.entries) v.key: b(v.value),
      'L': b(9),
      'R': b(10),
      if (target != ControllerTarget.snes &&
          target != ControllerTarget.nds) ...{
        'ZL': a(4),
        'ZR': a(5),
      },
      if (target == ControllerTarget.switchPro) ...{'L3': b(7), 'R3': b(8)},
    },
    if (target != ControllerTarget.gamecube) 'Select': b(4),
    'Start': b(6),
    for (final v in dpadButtons.entries) v.key: b(v.value),
    if (target != ControllerTarget.snes && target != ControllerTarget.nds)
      ..._stickBindings('Left Stick', 0),
    if (target != ControllerTarget.snes && target != ControllerTarget.nds)
      ..._stickBindings('Right Stick', 2),
  };
}

/// Labels follow each core's default RetroPad mapping, shared by the live
/// tester and SDL configuration. Extended peripherals remain core settings.
Map<String, InputBinding>? retroBindings(ControllerTarget target) {
  const b = InputBinding.button, a = InputBinding.axis;
  final faces = switch (target) {
    ControllerTarget.nes ||
    ControllerTarget.gameboy ||
    ControllerTarget.gba => {'A': b(1), 'B': b(0)},
    ControllerTarget.atari => {'Fire': b(0)},
    ControllerTarget.masterSystem => {'1': b(0), '2': b(1)},
    ControllerTarget.pcengine => {'I': b(1), 'II': b(0)},
    ControllerTarget.lynx => {
      'A': b(0),
      'B': b(1),
      'Option 1': b(9),
      'Option 2': b(10),
    },
    ControllerTarget.megadrive || ControllerTarget.saturn => {
      'A': b(2),
      'B': b(0),
      'C': b(1),
      'X': b(9),
      'Y': b(3),
      'Z': b(10),
      if (target == ControllerTarget.saturn) ...{'L': a(4), 'R': a(5)},
    },
    ControllerTarget.n64 => {
      'A': b(0),
      'B': b(2),
      'L': b(9),
      'R': b(10),
      'Z': a(4),
      ..._stickBindings('Left Stick', 0),
      ..._stickBindings('C', 2),
    },
    ControllerTarget.dreamcast => {
      'A': b(0),
      'B': b(1),
      'X': b(2),
      'Y': b(3),
      'L': a(4),
      'R': a(5),
      ..._stickBindings('Left Stick', 0),
    },
    ControllerTarget.pad3do => {
      'A': b(2),
      'B': b(0),
      'C': b(1),
      'L': b(9),
      'R': b(10),
    },
    ControllerTarget.jaguar => {
      'A': b(0),
      'B': b(1),
      'C': b(3),
      'Option': b(4),
    },
    ControllerTarget.arcade => {
      '1': b(0),
      '2': b(1),
      '3': b(3),
      '4': b(2),
      '5': b(9),
      '6': b(10),
      'Coin': b(4),
    },
    _ => null,
  };
  if (faces == null) return null;
  return {
    ...faces,
    if (target == ControllerTarget.gba) ...{'L': b(9), 'R': b(10)},
    for (final v in dpadButtons.entries) v.key: b(v.value),
    'Start': b(6),
    if (!{
      ControllerTarget.atari,
      ControllerTarget.arcade,
      ControllerTarget.dreamcast,
      ControllerTarget.n64,
      ControllerTarget.jaguar,
    }.contains(target))
      'Select': b(4),
  };
}
