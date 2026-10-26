import 'dart:convert';
import 'dart:io';

void main() {
  final f = File(
    '${Directory.current.path}/experiments/injection/sessions/ryubing/user/Config.json',
  );
  final c = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  c['check_updates_on_start'] = false;
  c['enable_file_log'] = false; // Stock macOS log path is outside this fixture.
  c['show_confirm_exit'] = false;
  c['disable_input_when_out_of_focus'] = false;
  c['input_config'] = [
    {
      'version': 1,
      'backend': 'GamepadSDL2',
      'id': '0-000000ff-6956-7472-7561-6c2043007601',
      'name': 'Virtual Controller',
      'controller_type': 'ProController',
      'player_index': 'Player1',
      'left_joycon_stick': {
        'joystick': 'Left',
        'stick_button': 'LeftStick',
        'invert_stick_x': false,
        'invert_stick_y': false,
        'rotate90_cw': false,
      },
      'right_joycon_stick': {
        'joystick': 'Right',
        'stick_button': 'RightStick',
        'invert_stick_x': false,
        'invert_stick_y': false,
        'rotate90_cw': false,
      },
      'left_joycon': {
        'button_minus': 'Back',
        'button_l': 'LeftShoulder',
        'button_zl': 'LeftTrigger',
        'button_sl': 'Unbound',
        'button_sr': 'Unbound',
        'dpad_up': 'DpadUp',
        'dpad_down': 'DpadDown',
        'dpad_left': 'DpadLeft',
        'dpad_right': 'DpadRight',
      },
      'right_joycon': {
        'button_plus': 'Start',
        'button_r': 'RightShoulder',
        'button_zr': 'RightTrigger',
        'button_sl': 'Unbound',
        'button_sr': 'Unbound',
        'button_a': 'B',
        'button_b': 'A',
        'button_x': 'Y',
        'button_y': 'X',
      },
      'deadzone_left': 0.1,
      'deadzone_right': 0.1,
      'range_left': 1,
      'range_right': 1,
      'trigger_threshold': 0.5,
      'motion': {
        'motion_backend': 'GamepadDriver',
        'enable_motion': false,
        'sensitivity': 100,
        'gyro_deadzone': 1,
      },
      'rumble': {'strong_rumble': 1, 'weak_rumble': 1, 'enable_rumble': false},
    },
  ];
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(c));
}
