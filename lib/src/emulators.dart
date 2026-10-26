import 'dart:convert';
import 'dart:io';

import 'catalogue.dart';
import 'controller_mapping.dart';
import 'pairing.dart';
import 'nintendo_ds.dart';
import 'ps3_disc.dart';
import 'retroarch.dart';
import 'retroarch_saves.dart';
import 'playstation.dart';

part 'playstation_adapters.dart';
part 'ppsspp_adapter.dart';
part 'eden_adapter.dart';

class PreparedEmulator {
  PreparedEmulator(
    this.name,
    this.root,
    this.executable,
    this.sdlMajor,
    this.sdlLibrary,
    this.core, {
    this.userDirectory,
    this.cacheDirectory,
    this.coreId,
    this.contentId,
  });
  final String name, root, executable;
  final String? sdlLibrary, core;
  final int sdlMajor;
  final String? userDirectory;
  final String? cacheDirectory;
  final String? coreId, contentId;
  String get user =>
      userDirectory ?? '$root/${name == 'RPCS3' ? 'portable' : 'user'}';
  factory PreparedEmulator.fromJson(Map<String, dynamic> j) => PreparedEmulator(
    j['name'] as String,
    j['root'] as String,
    j['executable'] as String,
    j['sdl_major'] as int,
    j['sdl_library'] as String?,
    j['core'] as String?,
  );
}

Future<void> atomicText(String path, String text) async {
  final tmp = File('$path.pending');
  await tmp.writeAsString(text, flush: true);
  await tmp.rename(path);
}

String _patchPreferences(
  String text,
  Map<String, Map<String, String>> changes,
) {
  if (text.length > 1024 * 1024)
    throw StateError(
      'Emulator preferences are too large. Existing settings were kept.',
    );
  final pending = {
    for (final e in changes.entries) e.key: Map<String, String>.of(e.value),
  };
  final output = <String>[], sections = <String>{}, keys = <String>{};
  var section = '';
  void finish() {
    for (final e in (pending.remove(section) ?? <String, String>{}).entries)
      output.add('${e.key} = ${e.value}');
  }

  for (final line in const LineSplitter().convert(text)) {
    final header = RegExp(r'^\s*\[([^\]]+)\]\s*$').firstMatch(line);
    if (header != null) {
      finish();
      section = header[1]!;
      if (changes.containsKey(section) && !sections.add(section))
        throw StateError(
          'Duplicate emulator preference sections. Existing settings were kept.',
        );
    }
    final key = RegExp(r'^\s*([\w]+)\s*=').firstMatch(line)?[1];
    if (changes[section]?.containsKey(key) == true &&
        !keys.add('$section.$key'))
      throw StateError(
        'Duplicate emulator preferences. Existing settings were kept.',
      );
    final value = pending[section]?.remove(key);
    output.add(value == null ? line : '$key = $value');
  }
  finish();
  for (final e in pending.entries) {
    if (e.key.isNotEmpty) output.add('[${e.key}]');
    for (final v in e.value.entries) output.add('${v.key} = ${v.value}');
  }
  return '${output.join('\n')}\n';
}

// Each concrete adapter owns its arguments and configuration semantics.
abstract class EmulatorAdapter {
  const EmulatorAdapter();
  Future<List<String>> configurationArguments(PreparedEmulator e) async => [];
  Future<List<String>> prepare(
    PreparedEmulator e,
    TestGame game,
    String rom,
    int commandPort,
  );
  static EmulatorAdapter forName(String name) => switch (name) {
    'RetroArch' => const RetroArchAdapter(),
    'Dolphin' => const DolphinAdapter(),
    'RPCS3' => const Rpcs3Adapter(),
    'Azahar' => const AzaharAdapter(),
    'Ryubing' => const RyubingAdapter(),
    'melonDS' => const MelonDsAdapter(),
    'DuckStation' => const DuckStationAdapter(),
    'PCSX2' || 'ARMSX2' => const Ps2Adapter(),
    'PPSSPP' => const PpssppAdapter(),
    'Eden' => const EdenAdapter(),
    _ => throw UnsupportedError('Unsupported emulator: $name'),
  };
}

class MelonDsAdapter extends EmulatorAdapter {
  const MelonDsAdapter();
  @override
  Future<List<String>> prepare(
    PreparedEmulator e,
    TestGame game,
    String rom,
    int commandPort,
  ) async {
    // Use the verified profile-private portable anchor; macOS Qt's normal
    // preferences location is not reliably redirected by a child HOME.
    if (Directory(e.user).absolute.path != '${e.root}/launcher/portable')
      throw StateError(
        'The private melonDS portable directory could not be verified.',
      );
    final identity = await dsSaveIdentity(rom);
    for (final folder in ['saves', 'states'])
      await Directory('${e.root}/$folder/$identity').create(recursive: true);
    await Directory(e.user).create(recursive: true);
    final config = File('${e.user}/melonDS.toml');
    final existing = await config.exists() ? await config.readAsString() : '';
    if (existing.length > 1024 * 1024)
      throw StateError(
        'The melonDS configuration is too large. Existing settings were kept.',
      );
    await atomicText(
      config.path,
      patchMelonDsConfig(existing, {
        'Emu': {'DirectBoot': 'true', 'ExternalBIOSEnable': 'false'},
        'Instance0': {
          'JoystickID': '0',
          'SaveFilePath': jsonEncode('${e.root}/saves/$identity'),
          'SavestatePath': jsonEncode('${e.root}/states/$identity'),
        },
        'Instance0.Joystick': {
          for (final e in {
            ...nintendoFaces,
            ...dpadButtons,
            'L': 9,
            'R': 10,
            'Select': 4,
            'Start': 6,
          }.entries)
            e.key: '${e.value}',
        },
      }),
    );
    return [rom];
  }
}

String patchMelonDsConfig(
  String existing,
  Map<String, Map<String, String>> values,
) {
  final pending = {
    for (final e in values.entries) e.key: Map<String, String>.of(e.value),
  };
  final output = <String>[], seen = <String>{}, seenKeys = <String>{};
  var table = '';
  void remaining() {
    final keys = pending.remove(table);
    if (keys != null)
      for (final e in keys.entries) output.add('${e.key} = ${e.value}');
  }

  for (final line in const LineSplitter().convert(existing)) {
    final header = RegExp(r'^\s*\[([^\]]+)\]\s*(?:#.*)?$').firstMatch(line);
    if (header != null) {
      remaining();
      table = header[1]!;
      if (values.containsKey(table) && !seen.add(table))
        throw StateError(
          'melonDS has duplicate configuration tables. Existing settings were kept.',
        );
    }
    final key = RegExp(r'^\s*([A-Za-z0-9_]+)\s*=').firstMatch(line)?[1];
    if (values[table]?.containsKey(key) == true && !seenKeys.add('$table.$key'))
      throw StateError(
        'melonDS has duplicate managed settings. Existing settings were kept.',
      );
    final value = pending[table]?[key];
    if (value != null) {
      pending[table]!.remove(key);
      output.add(table == 'Emu' ? line : '$key = $value');
    } else
      output.add(line);
  }
  remaining();
  for (final e in pending.entries) {
    output.add('[${e.key}]');
    for (final v in e.value.entries) output.add('${v.key} = ${v.value}');
  }
  return '${output.join('\n')}\n';
}

class RetroArchAdapter extends EmulatorAdapter {
  const RetroArchAdapter();
  @override
  Future<List<String>> configurationArguments(PreparedEmulator e) async {
    final config = File('${e.root}/retroarch.cfg');
    if (!await config.exists()) {
      await atomicText(
        config.path,
        {
          'config_save_on_exit': 'true',
          'savefile_directory': '${e.root}/saves',
          'savestate_directory': '${e.root}/states',
          'system_directory': '${e.root}/system',
          'cache_directory': '${e.root}/cache',
          'rgui_config_directory': '${e.root}/config',
        }.entries.map((v) => '${v.key} = ${jsonEncode(v.value)}').join('\n'),
      );
    }
    // Use --appendconfig for this session's save-on-exit setting; the existing
    // gameplay configuration and any user preferences remain the base file.
    final extra = '${e.root}/configure.cfg';
    await atomicText(extra, 'config_save_on_exit = "true"\n');
    return ['-c', config.path, '--appendconfig', extra];
  }

  @override
  Future<List<String>> prepare(
    PreparedEmulator e,
    TestGame game,
    String rom,
    int commandPort,
  ) async {
    final lines = <String, String>{
      'config_save_on_exit': 'false',
      'video_driver': 'glcore',
      'video_fullscreen': 'false',
      'video_window_width': '1100',
      'video_window_height': '760',
      'input_driver': 'sdl3',
      'input_joypad_driver': 'sdl3',
      'input_autodetect_enable': 'false',
      'input_pause_nonactive': 'false',
      'pause_nonactive': 'false',
      'menu_show_start_screen': 'false',
      'quit_press_twice': 'false',
      'confirm_quit': 'false',
      'network_cmd_enable': 'true',
      'network_cmd_port': '$commandPort',
      'stdin_cmd_enable': 'false',
      'savefile_directory': e.coreId == null
          ? '${e.root}/saves'
          : '${e.root}/${retroGameDirectory(e.coreId!, e.contentId!)}/saves',
      'savestate_directory': e.coreId == null
          ? '${e.root}/states'
          : '${e.root}/${retroGameDirectory(e.coreId!, e.contentId!)}/states',
      'sort_savefiles_enable': e.coreId == null ? 'true' : 'false',
      'sort_savestates_enable': e.coreId == null ? 'true' : 'false',
      if (e.coreId != null) ...{
        'sort_savefiles_by_content_enable': 'false',
        'sort_savestates_by_content_enable': 'false',
        'savefiles_in_content_dir': 'false',
        'savestates_in_content_dir': 'false',
      },
      'system_directory': '${e.root}/system',
      'screenshot_directory': '${e.root}/screenshots',
      'cache_directory': '${e.root}/cache',
      'rgui_config_directory': '${e.root}/config',
      'core_options_path': '${e.root}/config/core-options.cfg',
      'input_remapping_directory': '${e.root}/config/remaps',
      'playlist_directory': '${e.root}/config/playlists',
      'runtime_log_directory': '${e.root}/config/runtime',
    };
    for (var p = 1; p <= game.players; p++) {
      lines['input_player${p}_joypad_index'] = '${p - 1}';
      for (final entry in {
        for (final face in nintendoFaces.entries)
          face.key.toLowerCase(): face.value,
        'select': 4,
        'start': 6,
        'l': 9,
        'r': 10,
        'up': 11,
        'down': 12,
        'left': 13,
        'right': 14,
        'l3': 7,
        'r3': 8,
      }.entries) {
        lines['input_player${p}_${entry.key}_btn'] = '${entry.value}';
      }
      lines['input_player${p}_l2_axis'] = '+4';
      lines['input_player${p}_r2_axis'] = '+5';
      lines['input_player${p}_l_x_plus_axis'] = '+0';
      lines['input_player${p}_l_x_minus_axis'] = '-0';
      lines['input_player${p}_l_y_plus_axis'] = '+1';
      lines['input_player${p}_l_y_minus_axis'] = '-1';
      lines['input_player${p}_r_x_plus_axis'] = '+2';
      lines['input_player${p}_r_x_minus_axis'] = '-2';
      lines['input_player${p}_r_y_plus_axis'] = '+3';
      lines['input_player${p}_r_y_minus_axis'] = '-3';
    }
    if (e.coreId != null) {
      for (final kind in ['saves', 'states']) {
        await Directory(
          '${e.root}/${retroGameDirectory(e.coreId!, e.contentId!)}/$kind',
        ).create(recursive: true);
      }
    }
    String? sessionOptions;
    if (e.coreId == 'flycast') {
      // Disabled is Flycast's default: it writes VMUs under system/dc, outside
      // the game boundary. Force all ports into this game's private save path.
      // Session options inherit the user's other settings without changing the
      // profile's editable base options or another core's preferences.
      final text = await retroCoreOptionsText(e.root, 'Flycast', rom);
      final options =
          '${e.root}/${retroGameDirectory(e.coreId!, e.contentId!)}/core-options.cfg';
      await atomicText(
        options,
        _patchPreferences(text, {
          '': {'reicast_per_content_vmus': '"All VMUs"'},
        }),
      );
      sessionOptions =
          '${e.root}/${retroGameDirectory(e.coreId!, e.contentId!)}/session-options.cfg';
      await atomicText(
        sessionOptions,
        'core_options_path = ${jsonEncode(options)}\ngame_specific_options = "false"\nglobal_core_options = "true"\n',
      );
    }
    final config = File('${e.root}/retroarch.cfg');
    final existing = await config.exists() ? await config.readAsString() : '';
    for (final key in [
      'video_driver',
      'video_fullscreen',
      'video_window_width',
      'video_window_height',
    ]) {
      if (RegExp('^\\s*$key\\s*=', multiLine: true).hasMatch(existing))
        lines.remove(key);
    }
    await atomicText(
      config.path,
      _patchPreferences(existing, {
        '': {for (final v in lines.entries) v.key: jsonEncode(v.value)},
      }),
    );
    if (e.core == null) throw StateError('RetroArch core not prepared');
    return [
      '-c', '${e.root}/retroarch.cfg', '-L', e.core!,
      if (sessionOptions != null) ...['--appendconfig', sessionOptions],
      // The deprecated -s option bypasses save-directory initialization in
      // this frontend. Save RAM uses its private directory and native name.
      if (e.coreId != null) ...[
        '-S',
        '${e.root}/${retroGameDirectory(e.coreId!, e.contentId!)}/states/game.state',
      ],
      rom,
    ];
  }
}

const portNames = [
  'Broomm Probe A',
  'Broomm Probe B',
  'Broomm Probe C',
  'Broomm Probe D',
];

class DolphinAdapter extends EmulatorAdapter {
  const DolphinAdapter();
  @override
  Future<List<String>> configurationArguments(PreparedEmulator e) async => [
    '-u',
    e.user,
  ];
  @override
  Future<List<String>> prepare(
    PreparedEmulator e,
    TestGame game,
    String rom,
    int commandPort,
  ) async {
    final cfg = '${e.user}/Config';
    await Directory(cfg).create(recursive: true);
    final dolphin = File('$cfg/Dolphin.ini');
    final existing = await dolphin.exists() ? await dolphin.readAsString() : '';
    await atomicText(
      dolphin.path,
      _patchPreferences(existing, {
        'Interface': {'ConfirmStop': 'False'},
        'Core': {
          if (!RegExp(r'^\s*CPUThread\s*=', multiLine: true).hasMatch(existing))
            'CPUThread': 'True',
          for (var p = 0; p < 4; p++) 'SIDevice$p': '0',
        },
        'Display': {'RenderToMain': 'True', 'Fullscreen': 'False'},
        'Input': {'BackgroundInput': 'True'},
        'Analytics': {'PermissionAsked': 'True', 'Enabled': 'False'},
      }),
    );
    final text = StringBuffer();
    for (var p = 0; p < 4; p++) {
      text.writeln('[GCPad${p + 1}]\nDevice = SDL/0/${portNames[p]}');
      for (final entry in {
        'Buttons/A': 'Button A',
        'Buttons/B': 'Button B',
        'Buttons/X': 'Button X',
        'Buttons/Y': 'Button Y',
        'Buttons/Z': 'Shoulder R',
        'Buttons/Start': 'Start',
        'D-Pad/Up': 'Pad N',
        'D-Pad/Down': 'Pad S',
        'D-Pad/Left': 'Pad W',
        'D-Pad/Right': 'Pad E',
        'Main Stick/Left': 'Left X-',
        'Main Stick/Right': 'Left X+',
        'Main Stick/Up': 'Left Y+',
        'Main Stick/Down': 'Left Y-',
        'C-Stick/Left': 'Right X-',
        'C-Stick/Right': 'Right X+',
        'C-Stick/Up': 'Right Y+',
        'C-Stick/Down': 'Right Y-',
        'Triggers/L': 'Trigger L',
        'Triggers/R': 'Trigger R',
        'Triggers/L-Analog': 'Trigger L',
        'Triggers/R-Analog': 'Trigger R',
      }.entries) {
        text.writeln('${entry.key} = `${entry.value}`');
      }
      text.writeln('Main Stick/Modifier/Range = 50.0');
    }
    await atomicText('$cfg/GCPadNew.ini', text.toString());
    if (game.controllerTarget == ControllerTarget.wii)
      await prepareWii(e, [], 0);
    return ['-u', e.user, '--exec', rom];
  }

  Future<void> prepareWii(
    PreparedEmulator e,
    List<PlayerAssignment> players,
    int revision, {
    List<ControllerDevice> devices = const [],
  }) async {
    final text = StringBuffer('[Broomm]\nRevision = $revision\n');
    for (var p = 0; p < 4; p++) {
      final mode = p < players.length ? players[p].wiiMode : WiiMode.nunchuk;
      text.writeln(
        '[Wiimote${p + 1}]\nSource = 0\nDevice = SDL/0/${portNames[p]}',
      );
      text.writeln(
        'Extension = ${mode == WiiMode.classic
            ? 'Classic'
            : mode == WiiMode.nunchuk
            ? 'Nunchuk'
            : 'None'}',
      );
      text.writeln('Extension/Attach MotionPlus = False');
      text.writeln(
        'Options/Upright Wiimote = ${mode == WiiMode.upright ? 'True' : 'False'}',
      );
      text.writeln(
        'Options/Sideways Wiimote = ${mode == WiiMode.sideways ? 'True' : 'False'}',
      );
      final assignment = p < players.length ? players[p] : null;
      final device = p < players.length
          ? devices.where((d) => d.id == players[p].deviceId).firstOrNull
          : null;
      final remote = mode != WiiMode.classic;
      final pointing = assignment?.gyroPointer(device) ?? false;
      for (final binding in wiiBindings(
        mode,
        pointerFromStick: !pointing,
      ).entries)
        text.writeln('${binding.key} = ${binding.value.dolphin}');
      if (remote && device?.accelerometerAvailable == true)
        for (final direction in [
          'Up',
          'Down',
          'Left',
          'Right',
          'Forward',
          'Backward',
        ])
          text.writeln('IMUAccelerometer/$direction = `Accel $direction`');
      if (remote &&
          assignment?.gyroEnabled == true &&
          device?.gyroAvailable == true)
        for (final direction in [
          'Pitch Up',
          'Pitch Down',
          'Roll Left',
          'Roll Right',
          'Yaw Left',
          'Yaw Right',
        ])
          text.writeln('IMUGyroscope/$direction = `Gyro $direction`');
      text.writeln(
        'IR/Relative Input = True\nIR/Auto-Hide = False\nIR/Dead Zone = 15.0',
      );
      text.writeln(
        'IMUIR/Enabled = ${pointing ? 'True' : 'False'}\nIRPassthrough/Enabled = False',
      );
      if (pointing) text.writeln('IMUIR/Recenter = `Thumb R` & !`Back`');
      if (remote && !pointing)
        text.writeln('IR/Recenter = `Thumb R` & !`Back`');
      text.writeln('Nunchuk/Stick/Calibration = 100.00');
      text.writeln(
        'Classic/Left Stick/Calibration = 100.00\nClassic/Right Stick/Calibration = 100.00',
      );
    }
    text.writeln('[BalanceBoard]\nSource = 0');
    await atomicText('${e.user}/Config/WiimoteNew.ini', text.toString());
  }
}

class Rpcs3Adapter extends EmulatorAdapter {
  const Rpcs3Adapter();
  @override
  Future<List<String>> prepare(
    PreparedEmulator e,
    TestGame game,
    String rom,
    int commandPort,
  ) async {
    if (rom.toLowerCase().endsWith('.iso')) await ps3DiscKey(File(rom));
    final gui = File('${e.user}/GuiConfigs/CurrentSettings.ini');
    var guiText = await gui.readAsString();
    for (final key in [
      'confirmationBoxExitGame',
      'confirmationBoxBootGame',
      'infoBoxEnabledWelcome',
    ]) {
      final line = RegExp('^$key=.*\$', multiLine: true);
      if (line.hasMatch(guiText)) {
        guiText = guiText.replaceAll(line, '$key=false');
      } else {
        guiText = guiText.replaceFirst(
          '[main_window]',
          '[main_window]\n$key=false',
        );
      }
    }
    if (!guiText.contains('[Meta]')) guiText += '\n[Meta]\n';
    final update = RegExp(r'^checkUpdateStart=.*$', multiLine: true);
    guiText = update.hasMatch(guiText)
        ? guiText.replaceAll(update, 'checkUpdateStart=false')
        : guiText.replaceFirst('[Meta]', '[Meta]\ncheckUpdateStart=false');
    await atomicText(gui.path, guiText);
    final main = File('${e.user}/config.yml');
    var settings = await main.readAsString();
    settings = settings.replaceAll(
      'Start games in fullscreen mode: true',
      'Start games in fullscreen mode: false',
    );
    await atomicText(main.path, settings);
    final cfg = '${e.user}/input_configs/global';
    await Directory(cfg).create(recursive: true);
    final text = StringBuffer();
    for (var p = 0; p < 7; p++) {
      text.writeln('Player ${p + 1} Input:');
      if (p >= 4) {
        text.writeln('  Handler: Null');
        continue;
      }
      text.writeln('  Handler: SDL\n  Device: ${portNames[p]} 1\n  Config:');
      for (final v in {
        'Cross': 'South',
        'Circle': 'East',
        'Square': 'West',
        'Triangle': 'North',
        'Start': 'Start',
        'Select': 'Back',
        'PS Button': 'Guide',
        'L1': 'LB',
        'R1': 'RB',
        'L2': 'LT',
        'R2': 'RT',
        'L3': 'LS',
        'R3': 'RS',
        'Up': 'Up',
        'Down': 'Down',
        'Left': 'Left',
        'Right': 'Right',
        'Left Stick Left': 'LS X-',
        'Left Stick Right': 'LS X+',
        'Left Stick Up': 'LS Y+',
        'Left Stick Down': 'LS Y-',
        'Right Stick Left': 'RS X-',
        'Right Stick Right': 'RS X+',
        'Right Stick Up': 'RS Y+',
        'Right Stick Down': 'RS Y-',
      }.entries) {
        text.writeln('    ${v.key}: ${v.value}');
      }
    }
    await atomicText('$cfg/Default.yml', text.toString());
    await atomicText(
      '${e.user}/input_configs.yml',
      'Active Configurations:\n  global: Default\n',
    );
    return [rom];
  }
}

class AzaharAdapter extends EmulatorAdapter {
  const AzaharAdapter();
  @override
  Future<List<String>> prepare(
    PreparedEmulator e,
    TestGame game,
    String rom,
    int commandPort,
  ) async {
    final file = File('${e.user}/config/qt-config.ini');
    var text = await file.readAsString();
    void set(String key, String value, {String section = 'Controls'}) {
      final re = RegExp('^${RegExp.escape(key)}=.*\$', multiLine: true);
      if (re.hasMatch(text)) {
        text = text.replaceAllMapped(re, (_) => '$key=$value');
      } else {
        text = text.replaceFirst(
          '[$section]',
          '[$section]\n$key=$value\n$key\\default=false',
        );
      }
      text = text.replaceAll('$key\\default=true', '$key\\default=false');
    }

    for (final k in [
      'firstStart',
      'confirmClose',
      'check_for_update_on_start',
    ]) {
      set(k, 'false', section: 'UI');
    }
    const base =
        'engine:sdl,api:controller,guid:ff0013db5669727475616c2043007601,port:0';
    for (final v in {
      for (final face in nintendoFaces.entries)
        face.key.toLowerCase(): face.value,
      'select': 4,
      'start': 6,
      'l': 9,
      'r': 10,
      'up': 11,
      'down': 12,
      'left': 13,
      'right': 14,
    }.entries) {
      set('profiles\\1\\button_${v.key}', '"$base,button:${v.value}"');
    }
    for (final v in {'zl': 4, 'zr': 5}.entries) {
      set(
        'profiles\\1\\button_${v.key}',
        '"$base,axis:${v.value},threshold:0.5,direction:+"',
      );
    }
    set(
      'profiles\\1\\circle_pad',
      '"$base,axis_x:0,axis_y:1,deadzone:0.1,range:1.0"',
    );
    set(
      'profiles\\1\\c_stick',
      '"$base,axis_x:2,axis_y:3,deadzone:0.1,range:1.0"',
    );
    set('profiles\\1\\motion_device', '"$base"');
    await atomicText(file.path, text);
    return [rom];
  }
}

class RyubingAdapter extends EmulatorAdapter {
  const RyubingAdapter();
  @override
  Future<List<String>> configurationArguments(PreparedEmulator e) async => [
    '-r',
    e.user,
  ];
  @override
  Future<List<String>> prepare(
    PreparedEmulator e,
    TestGame game,
    String rom,
    int commandPort,
  ) async {
    final file = File('${e.user}/Config.json');
    final c = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    c.addAll({
      'check_updates_on_start': false,
      'enable_file_log': false,
      'show_confirm_exit': false,
      'disable_input_when_out_of_focus': false,
    });
    // Pin the same positional Nintendo diamond the tester projects, even if
    // the private fixture was changed through the emulator's own settings.
    final seed = Map<String, dynamic>.from(
      (c['input_config'] as List).first as Map,
    );
    seed['motion'] = {
      ...Map<String, dynamic>.from(seed['motion'] as Map),
      'motion_backend': 'GamepadDriver',
      'enable_motion': true,
    };
    seed['right_joycon'] = {
      ...Map<String, dynamic>.from(seed['right_joycon'] as Map),
      'button_a': 'B',
      'button_b': 'A',
      'button_x': 'Y',
      'button_y': 'X',
    };
    c['input_config'] = [
      for (var p = 0; p < 4; p++)
        {
          ...seed,
          'id': '$p-000000ff-6956-7472-7561-6c2043007601',
          'player_index': 'Player${p + 1}',
        },
    ];
    await atomicText(file.path, const JsonEncoder.withIndent('  ').convert(c));
    return ['-r', e.user, rom];
  }
}
