import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../progress/digest.dart';
import '../progress/files.dart';
import '../progress/layout.dart';
import 'duckstation_documents.dart';
import 'emulators.dart';
import 'save_plan.dart';

const androidDuckApk =
    '3e944243fa6d201d2c2c935f1a1b104fe7e2696c6f2a6b3d719fa212660d73f7';
const androidDuckRootFields = {
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
String duckDigest(String text) =>
    (ProgressDigest.sha256()..add(utf8.encode(text))).finish();

bool androidDuckRootBinding(Map<String, String> b) {
  const pkg = 'com.github.stenzek.duckstation';
  final uid = int.tryParse(b['uid'] ?? ''),
      mode = int.tryParse(b['externalMode'] ?? '', radix: 8);
  return b.keys.toSet().containsAll(androidDuckRootFields) &&
      b.length == androidDuckRootFields.length &&
      b['access'] == 'root-duck-v1' &&
      b['package'] == pkg &&
      b['user'] == '0' &&
      uid != null &&
      uid >= 10000 &&
      uid < 100000 &&
      {'/data/user/0/$pkg', '/data/data/$pkg'}.contains(b['dataDir']) &&
      [
        'build',
        'signer',
      ].every((k) => RegExp(r'^[a-f0-9]{64}$').hasMatch(b[k] ?? '')) &&
      RegExp(r'^u:object_r:app_data_file:s0(?::[a-zA-Z0-9_,.]+)?$')
          .hasMatch(b['label'] ?? '') &&
      b['externalLabel'] ==
          b['label']!.replaceFirst('app_data_file:', 'media_rw_data_file:') &&
      mode != null &&
      (mode & 7) == 0 &&
      (mode & 448) == 448 &&
      (mode & 2560) == 0 &&
      (int.tryParse(b['externalGid'] ?? '') ?? -1) >= 0 &&
      [
        'externalDevice',
        'externalInode',
      ].every((k) => (int.tryParse(b[k] ?? '') ?? 0) > 0) &&
      b['apk'] == androidDuckApk &&
      b['abi'] == 'arm64-v8a';
}

Future<Map<String, dynamic>> inspectAndroidDuckRoot(
  AndroidEmulators manager,
  AndroidApp app,
) async {
  final report = await manager.channel.invokeMapMethod<String, dynamic>(
    'rootDuckInspect',
    {'package': app.package, 'build': app.build},
  );
  if (report == null ||
      report['config'] is! Uint8List ||
      (report['config'] as Uint8List).length > 262144 ||
      report['settings'] is! Map)
    throw const FormatException('Incomplete DuckStation settings inspection.');
  androidDuckRootIdentity(report, app);
  androidIni(utf8.decode(report['config'] as Uint8List));
  return report;
}

Map<String, String> androidDuckRootIdentity(
  Map<String, dynamic> report,
  AndroidApp app,
) {
  final b = <String, String>{'access': 'root-duck-v1'};
  for (final k in androidDuckRootFields.where((k) => k != 'access')) {
    if (report[k] is! String)
      throw const FormatException('Incomplete DuckStation storage identity.');
    b[k] = report[k] as String;
  }
  if (!androidDuckRootBinding(b) ||
      b['package'] != app.package ||
      b['build'] != app.build ||
      report['version'] != app.version)
    throw const FormatException(
      'DuckStation installation changed. Progress was kept.',
    );
  return Map.unmodifiable(b);
}

enum AndroidDuckState {
  idle,
  menu,
  running,
  quiescent,
  closed,
  interrupted,
  unknown,
}

Future<
  ({
    AndroidDuckState state,
    Map<String, int>? process,
    int elapsed,
    int wall,
    bool paused,
  })
>
readAndroidDuckState(
  AndroidEmulators manager,
  Map<String, String> binding, {
  Map<String, int>? process,
  bool dispose = false,
  int? launchedAfter,
  ({int elapsed, int wall})? pauseAfter,
}) async {
  final r = await manager.channel.invokeMapMethod<String, dynamic>(
    dispose ? 'rootDuckStop' : 'rootDuckLifecycle',
    {
      ...binding,
      if (process != null) 'process': process,
      if (launchedAfter != null && process == null)
        'launchElapsed': launchedAfter,
      if (pauseAfter != null) ...{
        'pauseElapsed': pauseAfter.elapsed,
        'pauseWall': pauseAfter.wall,
      },
    },
  );
  final state = AndroidDuckState.values
      .where((s) => s.name == r?['state'])
      .firstOrNull;
  if (state == null ||
      r?['elapsed'] is! int ||
      (r!['elapsed'] as int) <= 0 ||
      r['wall'] is! int ||
      r['wall'] <= 0)
    throw const FormatException('Incomplete DuckStation writer observation.');
  final found =
      r['pid'] is int &&
          r['startTicks'] is int &&
          r['pid'] > 0 &&
          r['startTicks'] > 0
      ? {'pid': r['pid'] as int, 'startTicks': r['startTicks'] as int}
      : null;
  if (found != null && process != null && !mapEquals(found, process))
    throw const FormatException(
      'DuckStation process generation changed. Recovery was kept.',
    );
  return (
    state: state,
    process: found,
    elapsed: r['elapsed'] as int,
    wall: r['wall'] as int,
    paused: r['paused'] == true,
  );
}

/// One game owns both whole cards and every native state in its exact-build
/// directory. No serial/title guess assigns original standalone progress.
class AndroidDuckPlan extends ProgressLayout {
  AndroidDuckPlan(
    ProgressLayout layout,
    this.binding,
    this.profile,
    this.publication, {
    required this.platformId,
  }) : super(
         layout.root,
         layout.format,
         layout.game,
         layout.areas,
         note: layout.note,
       );
  final Map<String, String> binding;
  final String profile, publication;
  final int platformId;
  String get stateGroup =>
      areas.singleWhere((a) => a.id.startsWith('states-')).id;
  Map<String, String> get arguments => {
    ...binding,
    'game': game,
    'stateGroup': stateGroup,
  };
  String nativePath(String key) {
    final a = areas.singleWhere((a) => key.startsWith('${a.id}/'));
    final native = a.native(key.substring(a.id.length + 1));
    if (!a.accepts(native))
      throw const FormatException('PS1 save is outside its game.');
    return 'games/$game/${a.id == 'save' ? 'cards' : a.id}/$native';
  }

  String? key(String path) {
    progressRelative(path);
    for (final a in areas) {
      final prefix = 'games/$game/${a.id == 'save' ? 'cards' : a.id}/';
      if (path.startsWith(prefix) && a.accepts(path.substring(prefix.length)))
        return '${a.id}/${a.logical(path.substring(prefix.length))}';
    }
    return null;
  }
}

Future<AndroidDuckPlan> rootedAndroidDuckProgress(
  AndroidEmulators manager,
  String profile,
  AndroidEmulator emulator,
  String rom,
  String game,
  List<String> files, {
  required int platformId,
  String? package,
}) async {
  final app = manager.app(emulator, package: package),
      binding = manager.duckRoot(package: package);
  if (emulator.id != 'duckstation' ||
      app == null ||
      binding == null ||
      !androidDuckRootBinding(binding) ||
      binding['build'] != app.build ||
      !RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(game))
    throw StateError('Verify DuckStation root setup before playing.');
  final root = await manager.privateRoot(profile, emulator);
  final publication = await androidDuckStationDocumentToken(
    manager.data,
    files,
    rom,
  );
  final state =
      'states-${duckDigest('${binding['apk']}:${binding['abi']}:$publication').substring(0, 16)}-android';
  return AndroidDuckPlan(
    ProgressLayout(
      root.path,
      'duckstation-cards-v1',
      game,
      [
        ProgressArea(
          'save',
          'user/games/$game/cards',
          pattern: r'^card[12]\.mcd$',
        ),
        ProgressArea(
          state,
          'user/games/$game/$state',
          pattern: r'^[A-Za-z0-9_-]{1,160}\.sav(?:\.bak)?$',
        ),
      ],
      note: 'Private whole PS1 memory cards. States require this DuckStation build, ABI and game publication.',
    ),
    binding,
    profile,
    publication,
    platformId: platformId,
  );
}

bool duckInventorySame(Map a, Map b, {bool metadata = true}) =>
    a.length == b.length &&
    a.keys.every(
      (k) =>
          b[k] is Map &&
          a[k]['sha256'] == b[k]['sha256'] &&
          a[k]['bytes'] == b[k]['bytes'] &&
          (!metadata || a[k]['metadata'] == b[k]['metadata']),
    );

Map<String, dynamic> androidDuckInventory(
  Object? raw,
  Map<String, String> binding, {
  bool Function(String)? accepts,
}) {
  if (raw is! Map || raw.length > 8192)
    throw const FormatException('Invalid DuckStation inventory.');
  final result = <String, dynamic>{};
  var total = 0;
  for (final e in raw.entries) {
    if (e.key is! String || e.value is! Map)
      throw const FormatException('Incomplete DuckStation inventory.');
    final path = e.key as String;
    progressRelative(path);
    if (accepts != null && !accepts(path))
      throw const FormatException(
        'DuckStation progress belongs to another game.',
      );
    final v = e.value as Map;
    if (v.length != 3 ||
        v['bytes'] is! int ||
        v['bytes'] < 0 ||
        v['bytes'] > 256 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(v['sha256'] as String? ?? '') ||
        v['metadata'] is! String)
      throw const FormatException('Incomplete DuckStation file metadata.');
    final m = (v['metadata'] as String).split(' ');
    if (m.length != 10 ||
        m[0] != binding['uid'] ||
        m[1] != binding['externalGid'] ||
        !RegExp(r'^6[0246]0$').hasMatch(m[2]) ||
        m[3] != binding['externalLabel'] ||
        ![m[4], m[5]].every((s) => (int.tryParse(s) ?? 0) > 0) ||
        int.tryParse(m[6]) != v['bytes'] ||
        ![m[7], m[8]].every((s) => RegExp(r'^[0-9]+\.[0-9]{9}$').hasMatch(s)) ||
        m[9] != '1')
      throw const FormatException('DuckStation file ownership changed.');
    total += v['bytes'] as int;
    if (total > 2 * 1024 * 1024 * 1024)
      throw const FormatException('Private PS1 data exceeds its backup limit.');
    result[path] = Map<String, dynamic>.from(v);
  }
  return result;
}

Future<Map<String, dynamic>> readAndroidDuckInventory(
  AndroidEmulators manager,
  Map<String, String> binding,
  Map<String, dynamic> arguments, {
  bool profileData = false,
  bool Function(String)? accepts,
  void Function()? check,
}) async {
  final files = <String, dynamic>{};
  String? cursor;
  final clock = Stopwatch()..start();
  for (var page = 0; page <= 8192; page++) {
    check?.call();
    if (clock.elapsed > const Duration(minutes: 3))
      throw StateError(
        'DuckStation inventory timed out. Native data was kept.',
      );
    final r = await manager.channel.invokeMapMethod<String, dynamic>(
      profileData ? 'rootDuckProfileList' : 'rootDuckList',
      {...arguments, if (cursor != null) 'cursor': cursor},
    );
    if (r == null || r.length != 2 || !r.containsKey('next'))
      throw const FormatException('Incomplete DuckStation inventory page.');
    final entries = androidDuckInventory(r['files'], binding, accepts: accepts),
        names = <String>[];
    names.addAll(entries.keys);
    names.sort();
    if (names.any(
      (p) => files.containsKey(p) || cursor != null && p.compareTo(cursor) <= 0,
    ))
      throw const FormatException('DuckStation inventory pages overlap.');
    files.addAll(entries);
    if (r['next'] == null)
      return androidDuckInventory(files, binding, accepts: accepts);
    if (names.isEmpty || r['next'] != names.last)
      throw const FormatException(
        'DuckStation inventory continuation changed.',
      );
    cursor = names.last;
  }
  throw const FormatException('DuckStation inventory exceeded its page limit.');
}

String duckIni(Map<String, String> values) {
  final sections = <String, Map<String, String>>{};
  for (final e in values.entries) {
    final slash = e.key.indexOf('/');
    if (slash < 1 ||
        e.value.runes.any((c) => c < 32 || c == 127) ||
        !RegExp(r'^[A-Za-z0-9_. -]+/[A-Za-z0-9_. -]+$').hasMatch(e.key))
      throw const FormatException(
        'Unsupported DuckStation preference encoding.',
      );
    (sections[e.key.substring(0, slash)] ??= {})[e.key.substring(slash + 1)] =
        e.value;
  }
  final out = StringBuffer();
  for (final section in sections.entries) {
    out.writeln('[${section.key}]');
    for (final e in section.value.entries) out.writeln('${e.key} = ${e.value}');
    out.writeln();
  }
  return out.toString();
}

String duckSettingsSeed(String source) {
  const sections = {
    'CPU',
    'GPU',
    'Display',
    'Audio',
    'CDROM',
    'Console',
    'Pad',
    'Pad1',
    'Pad2',
    'ControllerPorts',
    'Hotkeys',
    'TouchscreenController',
    'Emulation',
  };
  const main = {
    'SaveStateOnExit',
    'SaveStateBackups',
    'PauseOnFocusLoss',
    'PauseOnMenu',
    'StartPaused',
  };
  return duckIni(
    Map.fromEntries(
      androidIni(source).entries.where(
        (e) =>
            sections.contains(e.key.split('/').first) ||
            e.key.startsWith('Main/') && main.contains(e.key.substring(5)),
      ),
    ),
  );
}
