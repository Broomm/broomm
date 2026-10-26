part of 'emulators.dart';

/// Pinned Eden uses SDL2 and its own SimpleINI schema, not Ryubing JSON.
class EdenAdapter extends EmulatorAdapter {
  const EdenAdapter();
  @override
  Future<List<String>> prepare(
    PreparedEmulator e,
    TestGame game,
    String rom,
    int commandPort,
  ) async {
    final file = File('${e.root}/config/eden/qt-config.ini');
    final controls = <String, String>{};
    for (var p = 0; p < 8; p++) {
      final prefix = 'player_${p}_';
      controls['${prefix}connected'] = 'false';
      controls['${prefix}type'] = '0'; // Pro Controller.
      controls['${prefix}profile_name'] = '';
      if (p >= 4) continue;
      // Eden clears SDL's name CRC bytes before identifying a joystick.
      final pad = 'engine:sdl,guid:ff0000005669727475616c2043007601,port:$p';
      for (final b in {
        'a': 1,
        'b': 0,
        'x': 3,
        'y': 2,
        'lstick': 7,
        'rstick': 8,
        'l': 9,
        'r': 10,
        'plus': 6,
        'minus': 4,
        'dleft': 13,
        'dup': 11,
        'dright': 14,
        'ddown': 12,
        'home': 5,
        'screenshot': 15,
        'slleft': 9,
        'srleft': 10,
        'slright': 9,
        'srright': 10,
      }.entries)
        controls['${prefix}button_${b.key}'] = '$pad,button:${b.value}';
      controls['${prefix}button_zl'] = '$pad,axis:4,direction:+,threshold:0.5';
      controls['${prefix}button_zr'] = '$pad,axis:5,direction:+,threshold:0.5';
      controls['${prefix}lstick'] =
          '$pad,axis_x:0,axis_y:1,deadzone:0.15,range:1';
      controls['${prefix}rstick'] =
          '$pad,axis_x:2,axis_y:3,deadzone:0.15,range:1';
      controls['${prefix}motionleft'] = '$pad,motion:0';
      controls['${prefix}motionright'] = '$pad,motion:0';
    }
    final updates = <String, Map<String, String>>{
      'Controls': controls,
      'UI': {
        'firstStart': 'false',
        'singleWindowMode': 'true',
        'fullscreen': 'false',
        'check_for_updates': 'false',
        'confirmStop': '2',
        'pauseWhenInBackground': 'false',
        'select_user_on_boot': 'false',
        'disableControllerApplet': 'true',
      },
      'System': {'current_user': '0'},
    };
    for (final group in updates.values) {
      for (final key in group.keys.toList()) group['$key\\default'] = 'false';
    }
    await atomicText(
      file.path,
      _patchPreferences(await _sonyPreferences(file), updates),
    );
    return ['-g', rom, '-u', '0'];
  }
}
