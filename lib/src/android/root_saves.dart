import 'dart:convert';
import 'dart:typed_data';

import '../game_launch.dart';
import '../progress/files.dart';
import '../progress/digest.dart';
import '../progress/layout.dart';
import '../retroarch.dart';
import 'emulators.dart';
import 'save_plan.dart';
import 'retroarch_core_setup.dart';
import 'opera.dart';

enum AndroidRetroArchState { idle, running, closed, interrupted, unknown }

String? androidRootRetroCore(String platform) => switch (platform) {
  '3do' => 'opera',
  'gba' => 'mgba',
  'snes' => 'snes9x',
  'gb' || 'gbc' => 'gambatte',
  'atari2600' => 'stella',
  'tg16' => 'mednafen_pce_fast',
  'genesis' || 'sms' || 'gamegear' => 'genesis_plus_gx',
  'sega32' => 'picodrive',
  'n64' => 'mupen64plus_next',
  'nes' => 'mesen',
  'jaguar' => 'virtualjaguar',
  'lynx' => 'mednafen_lynx',
  'arcade' => 'fbneo',
  _ => null,
};

String? androidRootRetroAccess(String platform) => switch (platform) {
  'gba' => 'root-gba-v1',
  'snes' => 'root-snes-v1',
  'gb' || 'gbc' => 'root-gameboy-v1',
  'atari2600' ||
  '3do' ||
  'tg16' ||
  'genesis' ||
  'sms' ||
  'gamegear' ||
  'sega32' ||
  'n64' ||
  'nes' ||
  'jaguar' ||
  'lynx' ||
  'arcade' => 'root-cartridge-v1',
  _ => null,
};

Future<({AndroidRetroArchState state, int? elapsed, Map<String, int>? process})>
readAndroidRetroArchState(
  AndroidEmulators manager,
  Map<String, String> binding, {
  int? launchedAfter,
  Map<String, int>? process,
}) async {
  final report = await manager.channel.invokeMapMethod<String, dynamic>(
    'rootLifecycle',
    {
      ...binding,
      if (launchedAfter != null) 'launchedAfter': launchedAfter,
      if (process != null) 'process': process,
    },
  );
  final state = AndroidRetroArchState.values
      .where((state) => state.name == report?['state'])
      .firstOrNull;
  if (state == null)
    throw const FormatException('Invalid RetroArch process report.');
  const keys = ['pid', 'startTicks', 'observedElapsed', 'observedWall'];
  return (
    state: state,
    elapsed: report?['elapsed'] as int?,
    process:
        state == AndroidRetroArchState.running &&
            keys.every((k) => report?[k] is int && (report![k] as int) > 0)
        ? {for (final k in keys) k: report![k] as int}
        : null,
  );
}

/// Persisted identity for an explicitly connected rooted RetroArch route, never an inferred
/// grant. The native service rechecks every field before each file operation.
bool androidRootBinding(Map<String, String> binding) {
  final pkg = binding['package'], uid = int.tryParse(binding['uid'] ?? '');
  return androidRootAccessModes.contains(binding['access']) &&
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

Future<Map<String, dynamic>> inspectAndroidRetroArchRoot(
  AndroidEmulators manager,
  AndroidApp app, {
  String platform = 'gba',
}) async {
  final value = await manager.channel.invokeMapMethod<String, dynamic>(
    'rootInspect',
    {
      'package': app.package,
      'build': app.build,
      'coreName':
          androidRootRetroCore(platform) ??
          (throw UnsupportedError('Unsupported rooted RetroArch system.')),
    },
  );
  if (value == null ||
      !{'arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64'}.contains(value['abi']) ||
      value['config'] is! Uint8List ||
      (value['config'] as Uint8List).length > 262144 ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['core'] as String? ?? '') ||
      value['package'] != app.package ||
      value['build'] != app.build) {
    throw const FormatException(
      'Root RetroArch inspection returned incomplete or mismatched data.',
    );
  }
  androidRetroArchRootIdentity(value, app, platform: platform);
  // Fail on undecodable/conflicting configuration before publishing a binding.
  androidIni(utf8.decode(value['config'] as Uint8List));
  return value;
}

Map<String, String> androidRetroArchRootIdentity(
  Map<String, dynamic> value,
  AndroidApp app, {
  String platform = 'gba',
}) {
  final binding = <String, String>{
    'access':
        androidRootRetroAccess(platform) ??
        (throw UnsupportedError('Unsupported rooted RetroArch system.')),
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
  if (!androidRootBinding(binding) ||
      binding['package'] != app.package ||
      binding['build'] != app.build)
    throw const FormatException('Invalid root RetroArch identity.');
  return binding;
}

bool androidRetroArchNeedsSetup(Map<String, dynamic> report, AndroidApp app) {
  if (report['frontendAssetsPending'] != true) return false;
  final config = androidIni(utf8.decode(report['config'] as Uint8List));
  final path = config['assets_directory']?.replaceFirst(RegExp(r'/+$'), '');
  return path == null ||
      path.isEmpty ||
      path == 'default' ||
      path == '/data/user/0/${app.package}/assets' ||
      path == '/data/data/${app.package}/assets';
}

Future<AndroidSavePlan> rootedRetroArchProgress(
  AndroidEmulators manager,
  String profile,
  AndroidEmulator emulator,
  GamePlatform platform,
  String rom,
  String content, {
  String? package,
}) async {
  final core = androidRootRetroCore(platform.slug);
  if (core == null ||
      (platform.retroCore != null && platform.retroCore != core))
    throw UnsupportedError(
      'Root saves are not yet implemented for this RetroArch platform. Configure a shared folder.',
    );
  final binding = manager.rootConnection(
    emulator,
    platform.slug,
    package: package,
  )!;
  if (!androidRootBinding(binding))
    throw const FormatException('Invalid root save connection.');
  final app = manager.app(emulator, package: package)!;
  if (app.build != binding['build'])
    throw StateError(
      'RetroArch changed. Finish any pending recovery before reconnecting root saves.',
    );
  final report = await inspectAndroidRetroArchRoot(
    manager,
    app,
    platform: platform.slug,
  );
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
  final driver = core == 'fbneo' ? stem.toLowerCase() : null;
  final opera = core == 'opera';
  final configNonce = progressNonce();
  final savedConfig = utf8.decode(report['config'] as Uint8List);
  final preferences = androidIni(savedConfig);
  final operaOptions = opera
      ? await readAndroidOperaOptions(
          manager.channel,
          binding,
          preferences,
          rom,
          'rom-$configNonce',
        )
      : <String, String>{};
  final rawSave = opera ? androidOperaRawSaveKey(operaOptions, stem) : null;
  if (opera) androidOperaResourceNames(operaOptions);
  if (driver != null && !rom.toLowerCase().endsWith('.zip'))
    throw UnsupportedError(
      'Rooted FBNeo currently needs a complete ZIP ROMset. Convert 7z sets to ZIP without renaming the set or its chips.',
    );
  if (driver != null && !RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(driver))
    throw const FormatException(
      'FBNeo needs the original ROMset filename, such as simpsons2p.zip. Keep the complete matching ROMset together.',
    );
  final area = ProgressArea(
    'save',
    'root-${platform.slug}/$content/saves',
    prefix: driver == null && !opera ? stem : null,
    exact: core == 'gambatte' || driver != null || opera ? null : '$stem.srm',
    pattern: opera
        ? '^(?:opera/per_game/${RegExp.escape(stem)}\\.[0-9]\\.srm|opera/shared/nvram\\.[0-9]\\.srm|${RegExp.escape(stem)}\\.srm|3DO\\.nvram)\$'
        : driver != null
        ? '^fbneo/(?:${RegExp.escape(driver)}\\.(?:fs|nv|hi|memcard)|shared\\.memcard)\$'
        : core == 'gambatte'
        ? '^${RegExp.escape(stem)}\\.(?:srm|rtc)\$'
        : null,
  );
  final identity = ProgressDigest.sha256()
    ..add(
      utf8.encode(
        '${await manager.fingerprint(app)}:${report['abi']}:${report['core']}',
      ),
    );
  final group = 'states-${identity.finish().substring(0, 16)}-android';
  final states = ProgressArea(
    group,
    'root-${platform.slug}/$content/$group',
    prefix: stem,
    pattern:
        '^${RegExp.escape(stem)}\\.state(?:[0-9]{1,10}|\\.auto)?(?:\\.png)?\$',
  );
  final configPath = '$base/config-$configNonce.cfg';
  final native = binding['dataDir']!;
  final configuredProfiles = preferences['joypad_autoconfig_dir'];
  final bundledProfiles =
      report['bundledControllerProfiles'] == true &&
      preferences['input_autodetect_enable'] != 'false' &&
      (configuredProfiles == null ||
          configuredProfiles.isEmpty ||
          configuredProfiles == 'default' ||
          configuredProfiles == '/data/user/0/${app.package}/autoconfig' ||
          configuredProfiles == '/data/data/${app.package}/autoconfig');
  final config = androidRetroConfig(savedConfig, {
    ...androidRetroOptionPaths(preferences, app.package),
    'savefile_directory': '$native/$base/saves',
    'savestate_directory': '$native/$base/states/$group',
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
    if (core == 'mednafen_lynx' || opera) ...{
      'system_directory': '$native/$base/system-$configNonce',
      'systemfiles_in_content_dir': 'false',
    },
    if (core == 'virtualjaguar' &&
        androidJaguarHasReviewedStates(report['abi'], report['core']))
      'core_info_savestate_bypass': 'true',
    if (bundledProfiles)
      'joypad_autoconfig_dir':
          '$native/files/Broomm/controller-profiles-${app.build}',
  });
  return AndroidSavePlan(
    ProgressLayout(
      root.path,
      core == 'snes9x' ? 'snes9x-sram-v1' : 'libretro-$core-v1',
      core == 'snes9x' ? 'snes' : content,
      [area, states],
      note: 'Rooted RetroArch saves and states. States require the same APK, ABI and core build.',
      rawSave: rawSave,
    ),
    emulator,
    binding,
    [
      AndroidSaveArea(
        area,
        '$base/saves',
        rename: core == 'gambatte' || driver != null || opera
            ? null
            : '$stem.srm',
        arcadeDriver: driver,
        operaStem: opera ? stem : null,
      ),
      AndroidSaveArea(states, '$base/states/$group'),
    ],
    launch: {
      'platform': platform.slug,
      'coreName': core,
      'configPath': configPath,
      'stateGroup': group,
      'configNative': '$native/$configPath',
      'configText': config,
      if (opera) 'transaction': configNonce,
      if (opera) ...{
        'sourceCore': report['core'] as String,
        'sourceAbi': report['abi'] as String,
        'sourceConfig':
            (ProgressDigest.sha256()..add(report['config'] as Uint8List))
                .finish(),
      },
      if (core == 'mednafen_lynx')
        'lynxFirmwarePath': '$base/system-$configNonce/lynxboot.img',
      if (androidRetroArchNeedsSetup(report, app)) 'frontendSetup': 'true',
      if (bundledProfiles && report['controllerProfilesReady'] != true)
        'prepareControllerProfiles': 'true',
    },
    operaOptions: operaOptions,
  );
}

/// Disc hashing/firmware transfer can outlast an external settings/core edit.
/// Recheck the prepared boundary before cloud inspection or any native write.
Future<void> verifyAndroidOperaPreparation(
  AndroidEmulators manager,
  AndroidSavePlan plan,
  String selected,
) async {
  if (!plan.rooted || plan.launch['coreName'] != 'opera')
    throw const FormatException('Invalid Opera preparation boundary.');
  final app = manager.app(plan.emulator, package: plan.binding['package']);
  if (app == null)
    throw StateError('RetroArch changed during preparation. Try Play again.');
  final report = await inspectAndroidRetroArchRoot(
    manager,
    app,
    platform: '3do',
  );
  final config = report['config'] as Uint8List;
  if (plan.binding.entries.any(
        (e) => e.key != 'access' && report[e.key] != e.value,
      ) ||
      report['core'] != plan.launch['sourceCore'] ||
      report['abi'] != plan.launch['sourceAbi'] ||
      (ProgressDigest.sha256()..add(config)).finish() !=
          plan.launch['sourceConfig'])
    throw StateError(
      'RetroArch’s core or configuration changed during preparation. Existing progress was kept. Try Play again.',
    );
  final options = await readAndroidOperaOptions(
    manager.channel,
    plan.binding,
    androidIni(utf8.decode(config)),
    selected,
    'rom-${plan.launch['transaction']}',
  );
  if (options.length != plan.operaOptions.length ||
      options.entries.any((e) => plan.operaOptions[e.key] != e.value))
    throw StateError(
      'Opera’s core options changed during preparation. Existing progress was kept. Try Play again.',
    );
}
