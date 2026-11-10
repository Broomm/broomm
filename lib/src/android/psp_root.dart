import 'dart:convert';
import 'dart:typed_data';

import '../emulators.dart';
import '../progress/digest.dart';
import '../progress/files.dart';
import '../progress/layout.dart';
import '../psp.dart';
import '../session.dart';
import 'emulators.dart';
import 'save_plan.dart';

const androidPspApk =
    'dd702a31270ecd68db37afee311d6efe08b1d4da9601d2750ce1a73bbd316c3f';
const androidPspRootFields = {
  'access',
  'package',
  'user',
  'uid',
  'dataDir',
  'build',
  'signer',
  'label',
  'externalLabel',
  'externalGid',
  'externalMode',
  'externalDevice',
  'externalInode',
  'apk',
  'abi',
};

bool androidPspRootBinding(Map<String, String> value) {
  final uid = int.tryParse(value['uid'] ?? ''),
      mode = int.tryParse(value['externalMode'] ?? '', radix: 8);
  final appLabel = value['label'] ?? '';
  return value.keys.toSet().containsAll(androidPspRootFields) &&
      value.length == androidPspRootFields.length &&
      value['access'] == 'root-psp-v1' &&
      value['package'] == 'org.ppsspp.ppsspp' &&
      value['user'] == '0' &&
      uid != null &&
      uid >= 10000 &&
      uid < 100000 &&
      {
        '/data/user/0/org.ppsspp.ppsspp',
        '/data/data/org.ppsspp.ppsspp',
      }.contains(value['dataDir']) &&
      [
        'build',
        'signer',
      ].every((key) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value[key] ?? '')) &&
      RegExp(r'^u:object_r:app_data_file:s0(?::[a-zA-Z0-9_,.]+)?$')
          .hasMatch(appLabel) &&
      value['externalLabel'] ==
          appLabel.replaceFirst('app_data_file:', 'media_rw_data_file:') &&
      mode != null &&
      (mode & 7) == 0 &&
      (mode & 448) == 448 &&
      (mode & 2560) == 0 &&
      RegExp(r'^[0-7]{3,4}$').hasMatch(value['externalMode'] ?? '') &&
      (int.tryParse(value['externalGid'] ?? '') ?? -1) >= 0 &&
      [
        'externalDevice',
        'externalInode',
      ].every((key) => (int.tryParse(value[key] ?? '') ?? 0) > 0) &&
      value['apk'] == androidPspApk &&
      {'arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64'}.contains(value['abi']);
}

Map<String, String> androidPspRootIdentity(
  Map<String, dynamic> report,
  AndroidApp app,
) {
  final binding = <String, String>{'access': 'root-psp-v1'};
  for (final key in androidPspRootFields.where((key) => key != 'access')) {
    if (report[key] is! String)
      throw const FormatException('Incomplete PPSSPP root storage identity.');
    binding[key] = report[key] as String;
  }
  if (!androidPspRootBinding(binding) ||
      binding['package'] != app.package ||
      binding['build'] != app.build ||
      report['version'] != app.version)
    throw const FormatException(
      'PPSSPP root storage identity changed. Progress was kept.',
    );
  return Map.unmodifiable(binding);
}

Future<Map<String, dynamic>> inspectAndroidPspRoot(
  AndroidEmulators manager,
  AndroidApp app,
) async {
  final report = await manager.channel.invokeMapMethod<String, dynamic>(
    'rootPspInspect',
    {'package': app.package, 'build': app.build},
  );
  if (report == null ||
      report['config'] is! Uint8List ||
      report['controls'] is! Uint8List ||
      (report['config'] as Uint8List).length > 262144 ||
      (report['controls'] as Uint8List).length > 65536)
    throw const FormatException('Incomplete PPSSPP settings inspection.');
  androidPspRootIdentity(report, app);
  androidIni(utf8.decode(report['config'] as Uint8List));
  androidIni(utf8.decode(report['controls'] as Uint8List));
  return report;
}

enum AndroidPspState { idle, running, closed, interrupted, unknown }

Future<Map<String, dynamic>> readAndroidPspInventory(
  AndroidEmulators manager,
  Map<String, String> binding,
  Map<String, dynamic> arguments, {
  bool profileData = false,
  bool Function(String)? accepts,
  void Function()? check,
}) async {
  final files = <String, dynamic>{}, clock = Stopwatch()..start();
  String? cursor;
  for (var page = 0; page <= 8192; page++) {
    check?.call();
    if (clock.elapsed > const Duration(minutes: 3))
      throw StateError(
        'PSP inventory exceeded its time limit. Native data and recovery were kept.',
      );
    final response = await manager.channel.invokeMapMethod<String, dynamic>(
      profileData ? 'rootPspProfileList' : 'rootPspList',
      {...arguments, if (cursor != null) 'cursor': cursor},
    );
    if (response == null ||
        response.length != 2 ||
        !response.containsKey('next'))
      throw const FormatException('Incomplete PSP inventory page.');
    final entries = androidPspInventory(
      response['files'],
      binding,
      profileData: profileData,
      accepts: accepts,
    );
    final paths = entries.keys.toList()..sort();
    if (paths.any(
      (p) => files.containsKey(p) || cursor != null && p.compareTo(cursor) <= 0,
    ))
      throw const FormatException(
        'PSP inventory pages overlapped. Nothing was inferred missing.',
      );
    files.addAll(entries);
    if (response['next'] == null)
      return androidPspInventory(
        files,
        binding,
        profileData: profileData,
        accepts: accepts,
      );
    if (paths.isEmpty || response['next'] != paths.last)
      throw const FormatException(
        'PSP inventory continuation was not verified.',
      );
    cursor = paths.last;
  }
  throw const FormatException('PSP inventory exceeded its page limit.');
}

Future<
  ({AndroidPspState state, int elapsed, int wall, Map<String, int>? process})
>
readAndroidPspState(
  AndroidEmulators manager,
  Map<String, String> binding, {
  Map<String, int>? process,
  ({int elapsed, int wall})? launchedAfter,
  bool shared = false,
}) async {
  if (!shared && !androidPspRootBinding(binding))
    throw const FormatException('Invalid PPSSPP root connection.');
  final report = await manager.channel.invokeMapMethod<String, dynamic>(
    shared ? 'rootPspSharedLifecycle' : 'rootPspLifecycle',
    {
      ...binding,
      if (process != null) 'process': process,
      if (process == null && launchedAfter != null) ...{
        'launchElapsed': launchedAfter.elapsed,
        'launchWall': launchedAfter.wall,
      },
    },
  );
  final state = AndroidPspState.values
      .where((s) => s.name == report?['state'])
      .firstOrNull;
  if (state == null ||
      report?['elapsed'] is! int ||
      report?['wall'] is! int ||
      report!['elapsed'] <= 0 ||
      report['wall'] <= 0)
    throw const FormatException('Incomplete PPSSPP writer observation.');
  final keys = {
    'pid',
    'startTicks',
    'launchElapsed',
    'launchWall',
    if (shared) 'activityCreated',
  };
  final observed = keys.every((key) => report[key] is int && report[key] > 0)
      ? {for (final key in keys) key: report[key] as int}
      : null;
  if (observed != null &&
      process != null &&
      keys.any((key) => observed[key] != process[key]))
    throw const FormatException(
      'PPSSPP process identity changed. Recovery was kept.',
    );
  return (
    state: state,
    elapsed: report['elapsed'] as int,
    wall: report['wall'] as int,
    process: observed,
  );
}

/// Seed only reviewed preferences. Account secrets, histories and native undo
/// associations stay with the original memory stick; this profile owns its console.
String androidPspSettingsSeed(String source, String mac) {
  if (!RegExp(r'^(?:[a-f0-9]{2}:){5}[a-f0-9]{2}$').hasMatch(mac))
    throw const FormatException('Invalid private PSP console identity.');
  const sections = {
    'CPU',
    'Graphics',
    'Sound',
    'Control',
    'JIT',
    'Theme',
    'DisplayLayout.Landscape',
    'DisplayLayout.Portrait',
    'TouchControls.Landscape',
    'TouchControls.Portrait',
    'GestureControls.Left',
    'GestureControls.Right',
  };
  const general = {
    'Language',
    'ShowSaveLoadIndicator',
    'SaveLoadResetsAVdumping',
    'StateSlot',
    'EnableStateUndo',
    'SaveStateSlotCount',
    'PauseWhenMinimized',
    'UIScaleFactor',
    'BackgroundAnimation',
    'TransparentBackground',
    'UITint',
    'UISaturation',
    'CheckForNewVersion',
  };
  const system = {
    'PSPModel',
    'PSPFirmwareVersion',
    'GameLanguage',
    'ParamTimeFormat',
    'ParamDateFormat',
    'TimeZone',
    'DayLightSavings',
    'ButtonPreference',
  };
  final selected = <String, Map<String, String>>{};
  for (final entry in androidIni(source).entries) {
    final slash = entry.key.indexOf('/');
    if (slash < 1) continue;
    final section = entry.key.substring(0, slash),
        key = entry.key.substring(slash + 1);
    if (!(sections.contains(section) ||
        section == 'General' && general.contains(key) ||
        section == 'SystemParam' && system.contains(key)))
      continue;
    if (entry.value.runes.any((c) => c < 32 || c == 127) ||
        !RegExp(r'^[A-Za-z0-9_. -]+$').hasMatch(key))
      throw const FormatException('Unsupported PPSSPP preference encoding.');
    (selected[section] ??= {})[key] = entry.value;
  }
  (selected['SystemParam'] ??= {})['MacAddress'] = mac;
  selected['SystemParam']!['NickName'] = 'PPSSPP';
  final out = StringBuffer();
  for (final section in selected.entries) {
    out.writeln('[${section.key}]');
    for (final setting in section.value.entries)
      out.writeln('${setting.key} = ${setting.value}');
    out.writeln();
  }
  return out.toString();
}

/// PSP uses its own private memory stick, not a Libretro core/configuration.
class AndroidPspPlan extends ProgressLayout {
  AndroidPspPlan(
    ProgressLayout layout,
    this.binding,
    this.profile,
    this.version,
  ) : super(
        layout.root,
        layout.format,
        layout.game,
        layout.areas,
        note: layout.note,
      );
  final Map<String, String> binding;
  final String profile, version;
  String get stateGroup =>
      areas.singleWhere((a) => a.id.startsWith('states-')).id;
  Set<String> get excluded => {
    for (final p in areas.singleWhere((a) => a.id == 'save').excluded)
      if (RegExp('^${RegExp.escape(game)}[A-Za-z0-9_-]{0,80}/').hasMatch(p))
        'PSP/SAVEDATA/$p',
  };
  Map<String, String> get arguments => {
    ...binding,
    'discId': game,
    'discVersion': version,
  };
  String nativePath(String key) {
    final area = areas.singleWhere((a) => key.startsWith('${a.id}/'));
    final native = area.native(key.substring(area.id.length + 1));
    if (!area.accepts(native))
      throw const FormatException('PSP save is outside its game boundary.');
    final path =
        'PSP/${area.id == 'save' ? 'SAVEDATA' : 'PPSSPP_STATE'}/$native';
    progressRelative(path);
    return path;
  }

  String? key(String native) {
    progressRelative(native);
    for (final area in areas) {
      final prefix = 'PSP/${area.id == 'save' ? 'SAVEDATA' : 'PPSSPP_STATE'}/';
      if (native.startsWith(prefix) &&
          area.accepts(native.substring(prefix.length)))
        return '${area.id}/${area.logical(native.substring(prefix.length))}';
    }
    return null;
  }

  Map<String, dynamic> inventory(Object? raw) =>
      androidPspInventory(raw, binding, accepts: (path) => key(path) != null);
}

/// Validate the complete response before interpreting absence or publishing data.
Map<String, dynamic> androidPspInventory(
  Object? raw,
  Map<String, String> binding, {
  bool profileData = false,
  bool Function(String)? accepts,
}) {
  if (raw is! Map || raw.length > (profileData ? 8192 : 4096))
    throw const FormatException('Invalid PSP native inventory.');
  final result = <String, dynamic>{};
  var total = 0;
  for (final e in raw.entries) {
    if (e.key is! String || e.value is! Map)
      throw const FormatException('Incomplete PSP inventory.');
    progressRelative(e.key as String);
    if (accepts != null && !accepts(e.key as String))
      throw const FormatException(
        'Native PSP progress belongs to another game.',
      );
    final value = e.value as Map;
    if (value.length != 3 ||
        value['bytes'] is! int ||
        value['bytes'] < 0 ||
        value['bytes'] > (profileData ? 1024 : 256) * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String? ?? '') ||
        value['metadata'] is! String)
      throw const FormatException('Incomplete native PSP file metadata.');
    final m = (value['metadata'] as String).split(' ');
    if (m.length != 10 ||
        m[0] != binding['uid'] ||
        m[1] != binding['externalGid'] ||
        !RegExp(r'^6[0246]0$').hasMatch(m[2]) ||
        m[3] != binding['externalLabel'] ||
        (int.tryParse(m[4]) ?? 0) <= 0 ||
        (int.tryParse(m[5]) ?? 0) <= 0 ||
        int.tryParse(m[6]) != value['bytes'] ||
        ![m[7], m[8]].every((v) => RegExp(r'^[0-9]+\.[0-9]{9}$').hasMatch(v)) ||
        m[9] != '1')
      throw const FormatException(
        'Native PSP ownership or file identity changed.',
      );
    total += value['bytes'] as int;
    if (total > (profileData ? 2048 : 512) * 1024 * 1024)
      throw const FormatException(
        'PSP data exceeds its capture limit. Native data was kept.',
      );
    result[e.key as String] = Map<String, dynamic>.from(value);
  }
  return result;
}

Future<AndroidPspPlan> rootedAndroidPspProgress(
  AndroidEmulators manager,
  String profile,
  AndroidEmulator emulator,
  String rom, {
  String? package,
}) async {
  final app = manager.app(emulator, package: package),
      binding = manager.pspRoot(package: package);
  if (emulator.id != 'ppsspp' ||
      app == null ||
      binding == null ||
      !androidPspRootBinding(binding) ||
      binding['build'] != app.build)
    throw StateError(
      'Verify PPSSPP root setup before playing. Progress was kept.',
    );
  final root = await manager.privateRoot(profile, emulator),
      metadata = await pspGameMetadata(rom);
  final version = metadata['DISC_VERSION'] ?? '1.00';
  final existing = await gameProgressLayout(
    ResolvedSession(
      PreparedEmulator('PPSSPP', root.path, '', 0, null, null),
      rom,
      binding['apk']!,
      const {},
    ),
    'psp',
  );
  final digest = ProgressDigest.sha256()
    ..add(utf8.encode('${binding['apk']}:${binding['abi']}:$version'));
  final state = 'states-${digest.finish().substring(0, 16)}-android';
  final layout = ProgressLayout(root.path, existing.format, existing.game, [
    existing.areas.singleWhere((a) => a.id == 'save'),
    ProgressArea(
      state,
      'state-builds/$state/user/PSP/PPSSPP_STATE',
      prefix: '${existing.game}_${version}_',
      pattern: r'^[^/]+_[0-9]{1,10}\.(?:undo\.)?(?:ppst|jpg)$',
    ),
  ], note: existing.note);
  return AndroidPspPlan(layout, binding, profile, version);
}
