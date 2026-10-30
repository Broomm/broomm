import 'dart:convert';
import 'dart:io';

import 'managed_emulators.dart';
import 'romm/transfer.dart';

/// Called only while the application's session/writer lease is held.
Future<Directory> prepareManagedProfile(
  Directory data,
  String profileId,
  TestedBuild build,
  Directory release,
) async {
  final parent = Directory('${data.path}/profiles/$profileId/emulators');
  await ownedDirectory(parent);
  final destination = Directory('${parent.path}/${build.profileId}');
  final type = await FileSystemEntity.type(
    destination.path,
    followLinks: false,
  );
  if (type != FileSystemEntityType.notFound) {
    await ownedDirectory(destination);
    final marker = File('${destination.path}/profile.json');
    if (await FileSystemEntity.type(marker.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await marker.length() > 65536)
      throw StateError(
        'This emulator profile is incomplete. Its existing data has been kept; inspect ${destination.path}.',
      );
    final j = jsonDecode(await marker.readAsString()) as Map;
    if (j['version'] != 1 ||
        j['profile'] != profileId ||
        j['emulator'] != build.profileId)
      throw StateError('The emulator data belongs to a different profile.');
    for (final path in [
      'user',
      'portable',
      'home',
      'saves',
      'states',
      if (build.isRpcs3 ||
          build.id == 'azahar' ||
          build.id == 'duckstation') ...[
        'home/Library',
        'home/Library/Application Support',
      ],
      if (build.id == 'azahar') ...[
        'home/Library/Application Support/Azahar',
        'home/Library/Application Support/Azahar/config',
      ],
      if (build.id == 'duckstation')
        'home/Library/Application Support/DuckStation',
      if (build.isPs2) 'user/${build.id}/${build.engine}/inis',
      if (build.id == 'eden') ...['data/eden', 'config/eden'],
      if (build.id == 'ppsspp') ...['user/PSP', 'user/PSP/SYSTEM'],
    ]) {
      if (await FileSystemEntity.type(
            '${destination.path}/$path',
            followLinks: false,
          ) !=
          FileSystemEntityType.directory) {
        throw StateError(
          'The private emulator data is missing or linked ($path). Existing progress has been kept; restore this profile before playing.',
        );
      }
    }
    for (final path in ['cache', 'config', 'data']) {
      await ownedDirectory(Directory('${destination.path}/$path'));
    }
    if (build.isRpcs3 &&
        await Link('${destination.path}/home/Library/Application Support/rpcs3')
                .target() !=
            '../../../portable')
      throw StateError(
        'The private RPCS3 configuration location changed. Existing progress has been kept.',
      );
    if (build.isRpcs3)
      await copyMissingIcons(
        '${release.path}/${build.bundle}/Contents/Resources/Icons',
        '${destination.path}/portable/Icons',
      );
    return destination;
  }
  final stage = await parent.createTemp('.profile-');
  var published = false;
  try {
    for (final p in [
      'home',
      'config',
      'cache',
      'data',
      'system',
      'saves',
      'states',
      'screenshots',
      'user',
      'portable',
    ]) {
      await ownedDirectory(Directory('${stage.path}/$p'));
    }
    final user = build.isRpcs3
        ? '${stage.path}/portable'
        : build.id == 'eden'
        ? '${stage.path}/data/eden'
        : build.id == 'duckstation'
        ? '${stage.path}/home/Library/Application Support/DuckStation'
        : build.id == 'azahar'
        ? '${stage.path}/home/Library/Application Support/Azahar'
        : '${stage.path}/user';
    await ownedDirectory(Directory(user));
    final resources = Directory('${release.path}/resources');
    final cancellation = DownloadCancellation();
    Future<void> resource(String key, String target) async {
      final source = '${resources.path}/$key';
      if (await FileSystemEntity.type(source, followLinks: false) !=
          FileSystemEntityType.notFound) {
        await ownedDirectory(File(target).parent);
        await copyTree(source, target, cancellation);
      }
    }

    switch (build.profileId) {
      case 'eden':
        await ownedDirectory(Directory('${stage.path}/config/eden'));
        await File('${stage.path}/config/eden/qt-config.ini').writeAsString('''
[UI]
firstStart=false
firstStart\\default=false
check_for_updates=false
check_for_updates\\default=false
confirmStop=2
confirmStop\\default=false
''', flush: true);
        await resource(
          'switch_firmware',
          '$user/nand/system/Contents/registered',
        );
        await resource('prod_keys', '$user/keys/prod.keys');
        await resource('title_keys', '$user/keys/title.keys');
      case 'ppsspp':
        for (final directory in ['SYSTEM', 'SAVEDATA', 'PPSSPP_STATE', 'GAME'])
          await ownedDirectory(Directory('$user/PSP/$directory'));
        await File('$user/PSP/SYSTEM/ppsspp.ini').writeAsString('''
[General]
FirstRun=False
CheckForNewVersion=False
PauseOnLostFocus=False
EnableLogging=True
''', flush: true);
      case 'duckstation':
        await File('$user/settings.ini').writeAsString('''
[Main]
SetupWizardIncomplete=false
ConfirmPowerOff=false
SaveStateOnExit=true
[AutoUpdater]
CheckAtStartup=false
[BIOS]
SearchDirectory=${destination.path}/system
PathNTSCU=bios.bin
PathNTSCJ=bios.bin
PathPAL=bios.bin
''', flush: true);
      case 'ps2':
        for (final engine in ['pcsx2', 'armsx2']) {
          final product = engine == 'pcsx2' ? 'PCSX2' : 'ARMSX2';
          final ini = File(
            '${stage.path}/user/$engine/$product/inis/PCSX2.ini',
          );
          await ownedDirectory(ini.parent);
          await ini.writeAsString('''
[UI]
SettingsVersion=1
SetupWizardIncomplete=false
ConfirmShutdown=false
CheckForUpdatesAtStartup=false
[Folders]
Bios=${destination.path}/system
[Filenames]
BIOS=bios.bin
''', flush: true);
        }
      case 'melonds':
        await ownedDirectory(
          Directory('${stage.path}/home/Library/Preferences/melonDS'),
        );
      case 'rpcs3':
        await resource('ps3_firmware', '$user/dev_flash');
        await copyMissingIcons(
          '${release.path}/${build.bundle}/Contents/Resources/Icons',
          '$user/Icons',
        );
        await ownedDirectory(Directory('$user/GuiConfigs'));
        await File('$user/GuiConfigs/CurrentSettings.ini').writeAsString('''
[main_window]
confirmationBoxExitGame=false
confirmationBoxBootGame=false
infoBoxEnabledWelcome=false
[Meta]
checkUpdateStart=false
''', flush: true);
        await File('$user/config.yml').writeAsString('''
Core:
  PPU Decoder: Recompiler (LLVM)
  SPU Decoder: Recompiler (LLVM)
Video:
  Renderer: Vulkan
Audio:
  Renderer: Cubeb
Miscellaneous:
  Start games in fullscreen mode: false
''', flush: true);
      case 'azahar':
        await ownedDirectory(Directory('$user/config'));
        await File('$user/config/qt-config.ini').writeAsString('''
[Controls]
profile=0
profiles\\size=1
profiles\\1\\name=Broomm
[UI]
firstStart=false
firstStart\\default=false
confirmClose=false
confirmClose\\default=false
check_for_update_on_start=false
check_for_update_on_start\\default=false
[System]
is_new_3ds=true
region_value=-1
[Data%20Storage]
use_custom_storage=false
''', flush: true);
      case 'astris':
      case 'ryubing':
        await resource(
          'switch_firmware',
          '$user/bis/system/Contents/registered',
        );
        await resource('prod_keys', '$user/system/prod.keys');
        await resource('title_keys', '$user/system/title.keys');
        await ownedDirectory(Directory('$user/system'));
        if (build.id == 'ryubing')
          await File('$user/system/Profiles.json').writeAsString(
            jsonEncode({
              'profiles': [
                {
                  'user_id': profileId,
                  'name': 'Player',
                  'image': '',
                  'account_state': 'Open',
                  'online_play_state': 'Closed',
                },
              ],
              'last_opened': profileId,
            }),
            flush: true,
          );
        if (build.id == 'ryubing')
          await File('$user/Config.json')
              .writeAsString(jsonEncode(ryubingDefaults()), flush: true);
    }
    // RPCS3's macOS config lookup uses HOME when no adjacent portable root
    // exists. These links are created by Broomm, never accepted from a manifest.
    if (build.isRpcs3) {
      final support = Directory(
        '${stage.path}/home/Library/Application Support',
      );
      await ownedDirectory(support);
      await Link('${support.path}/rpcs3').create('../../../portable');
    }
    await File('${stage.path}/profile.json').writeAsString(
      jsonEncode({
        'version': 1,
        'profile': profileId,
        'emulator': build.profileId,
      }),
      flush: true,
    );
    await stage.rename(destination.path);
    published = true;
    return destination;
  } finally {
    if (!published && await stage.exists()) await stage.delete(recursive: true);
  }
}

Map<String, dynamic> ryubingDefaults() => {
  'version': 70,
  'enable_file_log': false,
  'check_updates_on_start': false,
  'enable_discord_integration': false,
  'show_confirm_exit': false,
  'disable_input_when_out_of_focus': false,
  'focus_lost_action_type': 'DoNothing',
  'backend_threading': 'Auto',
  'res_scale': 1,
  'res_scale_custom': 1,
  'max_anisotropy': -1,
  'aspect_ratio': 'Fixed16x9',
  'anti_aliasing': 'None',
  'scaling_filter': 'Bilinear',
  'scaling_filter_level': 80,
  'graphics_shaders_dump_path': '',
  'logging_enable_debug': false,
  'logging_enable_info': true,
  'logging_enable_warn': true,
  'logging_enable_error': true,
  'logging_filtered_classes': <String>[],
  'system_language': 'AmericanEnglish',
  'system_region': 'USA',
  'system_time_zone': 'UTC',
  'system_time_offset': 0,
  'docked_mode': true,
  'use_input_global_config': false,
  'enable_vsync': true,
  'vsync_mode': 1,
  'enable_shader_cache': true,
  'enable_texture_recompression': false,
  'graphics_backend': 'Vulkan',
  'preferred_gpu': '',
  'audio_backend': 'SDL2',
  'audio_volume': 1,
  'enable_internet_access': false,
  'enable_fs_integrity_checks': true,
  'fs_global_access_log_mode': 0,
  'memory_manager_mode': 'HostMappedUnsafe',
  'dram_size': 0,
  'enable_ptc': true,
  'enable_guest_enhanced_fps': false,
  'enable_hypervisor': true,
  'enable_keyboard': false,
  'enable_mouse': false,
  'game_dirs': <String>[],
  'autoload_dirs': <String>[],
  'show_title_bar': true,
  'hotkeys': {
    'pause': 'F5',
    'toggle_vsync_mode': 'F1',
    'screenshot': 'F8',
    'show_ui': 'F4',
    'toggle_mute': 'F2',
    for (final k in [
      'res_scale_up',
      'res_scale_down',
      'volume_up',
      'volume_down',
      'custom_vsync_interval_increment',
      'custom_vsync_interval_decrement',
      'turbo_mode',
    ])
      k: 'Unbound',
    'turbo_mode_while_held': false,
  },
  'input_config': [
    {
      'version': 1,
      'backend': 'GamepadSDL2',
      'id': '0-000000ff-6956-7472-7561-6c2043007601',
      'name': 'Broomm',
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
        'enable_motion': true,
        'sensitivity': 100,
        'gyro_deadzone': 1,
      },
      'rumble': {'enable_rumble': false, 'strong_rumble': 1, 'weak_rumble': 1},
    },
  ],
};

Future<void> copyMissingIcons(String source, String target) async {
  final directory = Directory(source);
  if (!await directory.exists()) return;
  await ownedDirectory(Directory(target));
  await for (final entry in directory.list(followLinks: false)) {
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entry is Directory) {
      await copyMissingIcons(entry.path, '$target/$name');
    } else if (entry is File &&
        await FileSystemEntity.type('$target/$name', followLinks: false) ==
            FileSystemEntityType.notFound) {
      await entry.copy('$target/$name');
    }
  }
}
