import 'dart:convert';
import 'dart:typed_data';

import '../game_launch.dart';
import '../progress/files.dart';
import '../progress/layout.dart';
import '../retroarch.dart';
import 'emulators.dart';
import 'save_plan.dart';

/// Persisted identity for the explicitly connected GBA route, never an inferred
/// grant. The native service rechecks every field before each file operation.
bool androidRootBinding(Map<String, String> binding) {
  final pkg = binding['package'], uid = int.tryParse(binding['uid'] ?? '');
  return binding['access'] == 'root-gba-v1' &&
      {
        'com.retroarch.aarch64',
        'com.retroarch',
        'com.retroarch.ra32',
      }.contains(pkg) &&
      binding['user'] == '0' &&
      uid != null &&
      uid >= 10000 &&
      uid < 100000 &&
      {'/data/user/0/$pkg', '/data/data/$pkg'}.contains(binding['dataDir']) &&
      [
        'build',
        'signer',
      ].every((k) => RegExp(r'^[a-f0-9]{64}$').hasMatch(binding[k] ?? '')) &&
      RegExp(r'^u:object_r:app_data_file:s0(?::[a-zA-Z0-9_,.]+)?$')
          .hasMatch(binding['label'] ?? '') &&
      binding.keys.toSet().containsAll({
        'access',
        'package',
        'user',
        'uid',
        'dataDir',
        'build',
        'signer',
        'label',
      }) &&
      binding.length == 8;
}

Future<Map<String, dynamic>> inspectAndroidGbaRoot(
  AndroidEmulators manager,
  AndroidApp app,
) async {
  final value = await manager.channel.invokeMapMethod<String, dynamic>(
    'rootInspect',
    {'package': app.package, 'build': app.build},
  );
  if (value == null ||
      value['config'] is! Uint8List ||
      (value['config'] as Uint8List).length > 262144 ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['core'] as String? ?? '') ||
      value['package'] != app.package ||
      value['build'] != app.build) {
    throw const FormatException(
      'Root GBA inspection returned incomplete or mismatched data.',
    );
  }
  final binding = <String, String>{
    'access': 'root-gba-v1',
    for (final key in [
      'package',
      'user',
      'uid',
      'dataDir',
      'build',
      'signer',
      'label',
    ])
      key: value[key] as String,
  };
  if (!androidRootBinding(binding))
    throw const FormatException('Invalid root GBA identity.');
  // Fail on undecodable/conflicting configuration before publishing a binding.
  androidIni(utf8.decode(value['config'] as Uint8List));
  return value;
}

Future<AndroidSavePlan> rootedGbaProgress(
  AndroidEmulators manager,
  String profile,
  AndroidEmulator emulator,
  GamePlatform platform,
  String rom,
  String content, {
  String? package,
}) async {
  if (platform.slug != 'gba' ||
      (platform.retroCore != null && platform.retroCore != 'mgba'))
    throw UnsupportedError(
      'Root save access currently supports Game Boy Advance with mGBA only. Configure a shared folder for other platforms.',
    );
  final binding = manager.gbaRoot(emulator, package: package)!;
  if (!androidRootBinding(binding))
    throw const FormatException('Invalid root save connection.');
  final app = manager.app(emulator, package: package)!;
  if (app.build != binding['build'])
    throw StateError(
      'RetroArch changed. Finish any pending recovery before reconnecting root saves.',
    );
  final report = await inspectAndroidGbaRoot(manager, app);
  for (final key in binding.keys.where((k) => k != 'access')) {
    if (report[key] != binding[key])
      throw StateError(
        'The root emulator identity changed. Existing progress was kept.',
      );
  }
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(content))
    throw const FormatException('Invalid root game identity.');
  final root = await manager.privateRoot(profile, emulator);
  final stem = retroStateStem(rom), base = 'files/Broomm/$profile/$content';
  progressRelative('$stem.srm');
  final area = ProgressArea(
    'save',
    'root-gba/$content/saves',
    prefix: stem,
    exact: '$stem.srm',
  );
  final configPath = '$base/config-${progressNonce()}.cfg';
  final native = binding['dataDir']!;
  final config = androidRetroConfig(
    utf8.decode(report['config'] as Uint8List),
    {
      'savefile_directory': '$native/$base/saves',
      'savestate_directory': '$native/$base/states',
      'sort_savefiles_enable': 'false',
      'sort_savefiles_by_content_enable': 'false',
      'sort_savestates_enable': 'false',
      'sort_savestates_by_content_enable': 'false',
      'savefiles_in_content_dir': 'false',
      'savestates_in_content_dir': 'false',
      'config_save_on_exit': 'false',
      'auto_overrides_enable': 'false',
      'save_file_compression': 'false',
      'savestate_auto_load': 'false',
      'savestate_auto_save': 'false',
    },
  );
  return AndroidSavePlan(
    ProgressLayout(
      root.path,
      'libretro-mgba-v1',
      content,
      [area],
      note: 'Rooted Android mGBA ordinary saves. Save states are not synchronized by this first route.',
    ),
    emulator,
    binding,
    [AndroidSaveArea(area, '$base/saves', rename: '$stem.srm')],
    launch: {
      'configPath': configPath,
      'configNative': '$native/$configPath',
      'configText': config,
    },
  );
}
