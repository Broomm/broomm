import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../managed_emulators.dart' show ownedDirectory, copyTree;
import '../managed_profile.dart' show ryubingDefaults;
import '../romm/models.dart';
import '../romm/transfer.dart';
import 'files.dart';
import 'wii.dart';

/// The native scanner/importer may write only disposable staging. The native
/// guard holds the production writer lock even if the launcher disappears.
Future<Process> startPackageTool(
  String executable,
  List<String> arguments,
  Directory stage,
  Directory data,
  Map<String, String> extra,
) async {
  if (!Platform.isMacOS)
    throw UnsupportedError(
      'Native package import has not been validated on this host.',
    );
  final root = await stage.resolveSymbolicLinks();
  final writer = '${await data.resolveSymbolicLinks()}/writer.lock';
  final bundled =
      '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/native/broomm-installer-guard.dylib';
  final guard = await File(bundled).exists()
      ? bundled
      : '${Directory.current.path}/build/native/broomm-installer-guard.dylib';
  if (!await File(guard).exists())
    throw StateError('The native installer guard is missing.');
  for (final p in ['home', 'config', 'cache', 'data', 'tmp']) {
    await ownedDirectory(Directory('$root/$p'));
  }
  String quote(String s) => jsonEncode(s);
  return Process.start(
    '/usr/bin/sandbox-exec',
    [
      '-p',
      '(version 1)(allow default)(deny network*)(deny file-write* (require-all (require-not (subpath ${quote(root)})) (require-not (literal ${quote(writer)}))))',
      '/usr/bin/env',
      'DYLD_INSERT_LIBRARIES=$guard',
      File(executable).absolute.path,
      ...arguments,
    ],
    workingDirectory: root,
    includeParentEnvironment: false,
    environment: {
      'HOME': '$root/home',
      'XDG_CONFIG_HOME': '$root/config',
      'XDG_CACHE_HOME': '$root/cache',
      'XDG_DATA_HOME': '$root/data',
      'TMPDIR': '$root/tmp',
      'PATH': '/usr/bin:/bin',
      'LANG': 'en_US.UTF-8',
      'BROOMM_INSTALLER_WRITER_LOCK': writer,
      ...extra,
    },
  );
}

Future<void> importWiiWad(
  String executable,
  String input,
  Directory stage,
  Directory data,
  DownloadCancellation cancellation,
) async {
  stage = Directory(await stage.resolveSymbolicLinks());
  await readWiiWad(input);
  final user = Directory('${stage.path}/user');
  await ownedDirectory(Directory('${user.path}/Config'));
  await File('${user.path}/Config/Dolphin.ini').writeAsString(
    '[Analytics]\nPermissionAsked = True\nEnabled = False\n[Interface]\nConfirmStop = False\n',
    flush: true,
  );
  final child = await startPackageTool(
    executable,
    ['-u', user.path],
    stage,
    data,
    {
      'BROOMM_DOLPHIN_WAD': File(input).absolute.path,
      'QT_QPA_PLATFORM': 'cocoa',
    },
  );
  final output = <int>[];
  final out = child.stdout.listen((b) {
    if (output.length + b.length < 65536) output.addAll(b);
  }).asFuture<void>();
  final diagnostics = File('${stage.path}/installer.log').openWrite();
  var diagnosticBytes = 0;
  final err = child.stderr.listen((bytes) {
    if (diagnosticBytes < 1024 * 1024)
      diagnostics.add(bytes.take(1024 * 1024 - diagnosticBytes).toList());
    diagnosticBytes += bytes.length;
  }).asFuture<void>();
  cancellation.abort = () => child.kill(ProcessSignal.sigkill);
  int code;
  try {
    cancellation.check();
    code = await child.exitCode.timeout(const Duration(minutes: 2));
  } on TimeoutException {
    child.kill(ProcessSignal.sigkill);
    await child.exitCode;
    throw const RommFailure(
      'Dolphin WAD installation timed out; existing content was kept.',
    );
  } finally {
    if (cancellation.cancelled) {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
    }
    await Future.wait([out, err]);
    await diagnostics.close();
    cancellation.abort = null;
  }
  cancellation.check();
  if (code != 0 ||
      !utf8
          .decode(output, allowMalformed: true)
          .contains('BROOMM_DOLPHIN_WAD_V1_OK')) {
    throw RommFailure(
      'Dolphin could not import this WAD (status $code). Existing games and progress were kept.',
    );
  }
}

class SwitchPackages {
  const SwitchPackages(this.title, this.updates, this.dlc);
  final String title;
  final Map<String, dynamic>? updates;
  final List<dynamic>? dlc;
}

/// Ryubing's JSON paths can use either separator on Windows. Compare identities
/// before publishing metadata so a native spelling cannot retain a staging path.
Uri switchPackagePathIdentity(String path) {
  final windows =
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) || path.startsWith(r'\\');
  return windows
      ? Uri.file(path, windows: true).normalizePath()
      : File(path).absolute.uri.normalizePath();
}

Object relocateSwitchPackagePaths(
  Object? value,
  Map<Uri, String> replacements,
) {
  if (value is String)
    return replacements[switchPackagePathIdentity(value)] ?? value;
  if (value is Map)
    return {
      for (final entry in value.entries)
        entry.key: relocateSwitchPackagePaths(entry.value, replacements),
    };
  if (value is List)
    return value
        .map((v) => relocateSwitchPackagePaths(v, replacements))
        .toList();
  return value!;
}

/// Let the pinned Ryubing scanner decrypt CNMT/NCA metadata and choose the
/// highest update. Never derive title, version or DLC IDs from package names.
Future<SwitchPackages> inspectSwitchPackages(
  String executable,
  String base,
  Directory packages,
  Directory stage,
  Directory profile,
  Directory data,
  DownloadCancellation cancellation,
) async {
  stage = Directory(await stage.resolveSymbolicLinks());
  final user = Directory('${stage.path}/user');
  await ownedDirectory(Directory('${user.path}/system'));
  for (final key in ['prod.keys', 'title.keys']) {
    final source = File(
      await addonPath(Directory('${profile.path}/user'), 'system/$key'),
    );
    if (await source.exists())
      await copyTree(source.path, '${user.path}/system/$key', cancellation);
  }
  if (!await File('${user.path}/system/prod.keys').exists())
    throw const RommFailure(
      'Set up Switch keys before installing updates/DLC.',
    );
  await addonWrite(File('${user.path}/Config.json'), {
    ...ryubingDefaults(),
    'game_dirs': [File(base).absolute.parent.path],
    'autoload_dirs': [packages.absolute.path],
    'shown_file_types': {
      'nsp': true,
      'pfs0': true,
      'xci': true,
      'nca': true,
      'nro': true,
      'nso': true,
    },
    'show_confirm_exit': false,
  });
  final knownPaths = <String>{File(base).absolute.path};
  final configured = Directory('${profile.path}/user/games');
  if (await configured.exists()) {
    var count = 0;
    await for (final dir in configured.list(followLinks: false)) {
      if (++count > 8192)
        throw const FormatException('Too many Switch configuration records');
      final id = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!RegExp(r'^010[a-f0-9]{13}$').hasMatch(id)) continue;
      if (dir is! Directory)
        throw const FileSystemException('Linked Switch game metadata was kept');
      for (final name in ['updates', 'dlc']) {
        final file = File('${dir.path}/$name.json');
        if (!await addonExists(file.path)) continue;
        final checked = await addonFile(dir, '$name.json');
        if (await checked.length() > 12 * 1024 * 1024)
          throw const FormatException('Switch game metadata exceeds limits');
        final value = jsonDecode(await checked.readAsString());
        if (name == 'updates' && value is Map && value['paths'] is List)
          knownPaths.addAll((value['paths'] as List).cast<String>());
        if (name == 'dlc' && value is List)
          knownPaths.addAll(value.map((v) => (v as Map)['path'] as String));
        final target = await addonFile(
          user,
          'games/$id/$name.json',
          createParents: true,
        );
        await checked.copy(target.path);
      }
    }
  }
  final expected = (await packages.list(followLinks: false).toList())
      .whereType<File>()
      .map((f) => f.absolute.path)
      .toSet();
  final child = await startPackageTool(
    executable,
    ['-r', user.path],
    stage,
    data,
    const {},
  );
  final diagnostics = <int>[];
  void output(List<int> bytes) {
    if (diagnostics.length < 1024 * 1024)
      diagnostics.addAll(bytes.take(1024 * 1024 - diagnostics.length));
  }

  final out = child.stdout.listen(output).asFuture<void>(),
      err = child.stderr.listen(output).asFuture<void>();
  cancellation.abort = () => child.kill(ProcessSignal.sigkill);
  var exited = false;
  unawaited(child.exitCode.then((_) => exited = true));
  SwitchPackages? result;
  try {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (!exited && DateTime.now().isBefore(deadline)) {
      cancellation.check();
      final games = Directory('${user.path}/games');
      if (await games.exists()) {
        for (final entry in await games.list(followLinks: false).toList()) {
          final id = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (entry is! Directory || !RegExp(r'^010[a-f0-9]{13}$').hasMatch(id))
            continue;
          try {
            final updateFile = File('${entry.path}/updates.json'),
                dlcFile = File('${entry.path}/dlc.json');
            final updates = await updateFile.exists()
                ? await addonJson(updateFile)
                : null;
            final dlc = await dlcFile.exists()
                ? jsonDecode(await dlcFile.readAsString()) as List
                : null;
            final represented = <String>{
              ...?((updates?['paths'] as List?)?.cast<String>()),
              for (final c in dlc ?? []) (c as Map)['path'] as String,
            };
            if (expected.isNotEmpty && represented.containsAll(expected)) {
              validateSwitchPackages(id, updates, dlc, {
                ...expected,
                ...knownPaths,
              });
              result = SwitchPackages(id, updates, dlc);
              break;
            }
          } on FormatException {
            /* native JSON may be mid-publication */
          }
        }
      }
      if (result != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  } finally {
    // Only our disposable inspector is stopped. No profile/save writer runs.
    child.kill(ProcessSignal.sigterm);
    try {
      await child.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
    }
    await Future.wait([out, err]);
    cancellation.abort = null;
  }
  cancellation.check();
  if (result == null) {
    final directory = Directory('${data.path}/package-diagnostics');
    await ownedDirectory(directory);
    final text = utf8
        .decode(diagnostics, allowMalformed: true)
        .replaceAll(RegExp(r'[a-fA-F0-9]{32,}'), '[redacted]')
        .replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
    await File('${directory.path}/switch-inspector.log')
        .writeAsString(text, flush: true);
  }
  if (result == null)
    throw const RommFailure(
      'Ryubing could not validate every package for this game. Check its title/region, format and configured keys; no content was installed.',
    );
  return result;
}

void validateSwitchPackages(
  String id,
  Map? updates,
  List? dlc,
  Set<String> paths,
) {
  if (!RegExp(r'^010[a-f0-9]{13}$').hasMatch(id))
    throw const FormatException('Invalid Switch application ID');
  final base = BigInt.parse(id, radix: 16), mask = ~BigInt.from(0x1fff);
  if (updates != null &&
      (updates['paths'] is! List ||
          (updates['paths'] as List).isEmpty ||
          !(updates['paths'] as List).every(
            (p) => p is String && paths.contains(p),
          ) ||
          !(updates['paths'] as List).contains(updates['selected'])))
    throw const FormatException('Invalid native Switch update selection');
  for (final container in dlc ?? []) {
    if (container is! Map ||
        !paths.contains(container['path']) ||
        container['dlc_nca_list'] is! List ||
        (container['dlc_nca_list'] as List).isEmpty)
      throw const FormatException('Invalid native Switch DLC container');
    for (final n in container['dlc_nca_list'] as List) {
      if (n is! Map ||
          n['title_id'] is! int ||
          n['is_enabled'] is! bool ||
          n['path'] is! String ||
          !RegExp(r'^/[a-fA-F0-9]{32}\.nca$').hasMatch(n['path'] as String) ||
          (BigInt.from(n['title_id'] as int) & mask) != base)
        throw const FormatException(
          'Switch DLC belongs to another application',
        );
    }
  }
}
