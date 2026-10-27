import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'catalogue.dart';
import 'emulators.dart';
import 'romm/transfer.dart';
import 'session.dart';
import 'session_lease.dart';
import 'managed_profile.dart';
import 'retroarch.dart';
import 'retroarch_saves.dart';
import 'progress/file_hash.dart';
import 'setup/archive.dart';
import 'setup/package.dart';

class TestedBuild {
  TestedBuild(Map j)
    : id = j['id'] as String,
      name = j['name'] as String,
      version = j['version'] as String,
      host = j['host'] as String,
      architecture =
          j['architecture'] as String? ?? (j['host'] as String).split('-').last,
      bundle = j['bundle'] as String,
      executable = j['executable'] as String,
      hash = j['sha256'] as String,
      sdl = j['sdl'] as int,
      sdlLibrary = j['sdl_library'] as String?,
      coreHash = j['core_sha256'] as String?,
      retroNativeStateNames = j['retro_native_state_names'] == true,
      integrityAsset =
          j['integrity_asset'] as String? ??
          'assets/setup/${j['id']}.integrity.json',
      sourcePackage = j['source_package'] == null
          ? null
          : SetupPackage.fromJson(j['source_package'] as Map),
      compatibleSetupPackages = {
        for (final entry
            in (j['compatible_setup_packages'] as Map? ?? {}).entries)
          entry.key as String: [
            for (final value in entry.value as List)
              SetupPackage.fromJson(value as Map),
          ],
      },
      native = (j['native'] as Map).cast<String, String>();
  final String id, name, version, host, bundle, executable, hash;
  final String architecture;
  final String integrityAsset;
  final SetupPackage? sourcePackage;
  // Both RPCS3 distributions consume the same native PS3 data format. Keep
  // saves, firmware, licenses and add-on ownership in the existing profile.
  bool get isRpcs3 => id == 'rpcs3' || id == 'rpcs3-intel';
  bool get isPs2 => id == 'pcsx2' || id == 'armsx2';
  String get profileId => isRpcs3
      ? 'rpcs3'
      : isPs2
      ? 'ps2'
      : id;
  String get engine => isRpcs3 ? 'RPCS3' : name;
  final String? sdlLibrary, coreHash;
  final bool retroNativeStateNames;
  final int sdl;
  final Map<String, String> native;
  final Map<String, List<SetupPackage>> compatibleSetupPackages;
}

class SetupItem {
  const SetupItem(
    this.build,
    this.source,
    this.core,
    this.resources, {
    this.cores = const {},
    this.downloads = const {},
    this.packageRoot,
  });
  final TestedBuild build;
  final String source;
  final String? core;
  final Map<String, String> resources;
  final Map<String, String> cores;
  final Map<String, SetupPackage> downloads;
  final Directory? packageRoot;
  String describe(String source) {
    final package = downloads[source];
    return package == null
        ? source
        : package.url?.toString() ?? 'Setup package: ${package.file}';
  }
}

class SetupPlan {
  const SetupPlan(this.items);
  final List<SetupItem> items;
}

class ManagedEmulators extends ChangeNotifier {
  ManagedEmulators(
    this.data, {
    this.project,
    this.log,
    Future<String> Function(String)? asset,
    SetupDownloads? downloads,
  }) : asset = asset ?? rootBundle.loadString,
       downloads = downloads ?? SetupDownloads(data);
  final Directory data;
  final String? project;
  final SessionLog? log;
  final SetupDownloads downloads;
  double? progress;
  int _progressBucket = -1;
  void setPhase(String value) {
    phase = value;
    progress = null;
    _progressBucket = -1;
    log?.write(value);
    emit();
  }

  void transferProgress(String value, double? fraction) {
    final bucket = fraction == null ? -1 : (fraction * 10).floor();
    if (phase != value || bucket != _progressBucket) {
      log?.write(
        '$value${fraction == null ? '' : ' ${(fraction * 100).floor()}%'}',
      );
      _progressBucket = bucket;
    }
    phase = value;
    progress = fraction;
    emit();
  }

  final Future<String> Function(String) asset;
  final builds = <TestedBuild>[];
  final previousBuilds = <TestedBuild>[];
  final installed = <String, String>{};
  final removals = <String, String>{};
  final resourceProblems = <String, String>{};
  final coreBuilds = <String, Map>{};
  final previousCoreBuilds = <Map>[];
  final installedCoreBuilds = <String, Map>{};
  final installedCores = <String>{};
  bool readyFor(String emulator, String slug) =>
      ready(emulator) &&
      (emulator != 'RetroArch' ||
          retroSystem(slug) == null ||
          installedCores.contains(retroSystem(slug)!.core));
  bool busy = false, disposed = false;
  String phase = '', notice = '';
  String? error;
  SetupPlan? plan;
  DownloadCancellation? _cancel;
  Future<void>? _work;
  String get host =>
      '${Platform.operatingSystem}-${Abi.current().toString().split('_').last}';
  bool get supported => host == 'macos-arm64';
  Directory get root => Directory('${data.path}/emulators');
  void emit() {
    if (!disposed) notifyListeners();
  }

  Future<void> load() async {
    error = null;
    try {
      if (builds.isEmpty) {
        final j =
            jsonDecode(await asset('assets/setup/tested-builds.json')) as Map;
        final current = (j['builds'] as List)
            .map((e) => TestedBuild(e as Map))
            .toList();
        final previous = (j['previous_builds'] as List? ?? const [])
            .map((e) => TestedBuild(e as Map))
            .toList();
        if (previous.any(
          (old) => !current.any(
            (current) => current.id == old.id && current.host == old.host,
          ),
        )) {
          throw const FormatException('Unknown previous emulator identity');
        }
        builds.addAll(current);
        previousBuilds.addAll(previous);
      }
      if (coreBuilds.isEmpty && builds.any((b) => b.id == 'retroarch')) {
        final j =
            jsonDecode(await asset('assets/setup/retroarch-cores.json')) as Map;
        final current = (j['cores'] as List).cast<Map>();
        final previous = (j['previous_cores'] as List? ?? const []).cast<Map>();
        for (final c in [...current, ...previous]) {
          if (!retroSystems.any((s) => s.core == c['id']) ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(c['sha256'] as String)) {
            throw const FormatException('Invalid RetroArch core build');
          }
        }
        for (final c in current) {
          coreBuilds[c['id'] as String] = c;
        }
        previousCoreBuilds.addAll(previous);
      }
      installedCores.clear();
      installedCoreBuilds.clear();
      final file = File('${root.path}/selected.json');
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        installed.clear();
        removals.clear();
        resourceProblems.clear();
        emit();
        return;
      }
      if (type != FileSystemEntityType.file || await file.length() > 65536)
        throw const FormatException('Invalid emulator records');
      final j = jsonDecode(await file.readAsString()) as Map;
      if (j['schema_version'] != 1)
        throw const FormatException('Unsupported emulator records');
      final selected = (j['selected'] as Map).cast<String, String>();
      final pending = (j['removals'] as Map? ?? {}).cast<String, String>();
      if (selected.keys.any(pending.containsKey))
        throw const FormatException('Conflicting emulator selection/removal');
      for (final entry in [...selected.entries, ...pending.entries]) {
        if (_knownBuild(entry.key, entry.value) == null)
          throw const FormatException('Unknown managed build');
      }
      installed
        ..clear()
        ..addAll(selected);
      removals
        ..clear()
        ..addAll(pending);
      resourceProblems.clear();
      for (final entry in selected.entries) {
        final b = _knownBuild(entry.key, entry.value)!;
        if (b.id == 'retroarch') {
          for (final id in coreBuilds.keys) {
            // Updating Broomm does not replace an installed core. Prefer a new
            // version only after explicit setup has published that exact file.
            for (final c in _coreVersions(id)) {
              final path =
                  '${root.path}/${b.id}/${b.hash}/cores/$id-${c['sha256']}/core.dylib';
              final type = await FileSystemEntity.type(
                path,
                followLinks: false,
              );
              if (type == FileSystemEntityType.notFound) continue;
              if (type != FileSystemEntityType.file) {
                throw const FormatException('Invalid managed core file');
              }
              installedCores.add(id);
              installedCoreBuilds[id] = c;
              break;
            }
          }
        }
        final base = '${root.path}/${b.id}/${b.hash}/resources';
        if (b.isRpcs3 &&
            !await File('$base/ps3_firmware/sys/external/liblv2.sprx').exists())
          resourceProblems[b.id] = 'PS3 firmware required';
        if ({'ryubing', 'eden'}.contains(b.id) &&
            (!await File('$base/prod_keys').exists() ||
                !await File('$base/title_keys').exists() ||
                !await Directory('$base/switch_firmware').exists()))
          resourceProblems[b.id] = 'Switch keys and firmware required';
      }
    } catch (_) {
      error = 'Managed emulator records could not be read. Existing installations and profile data have been kept.';
    }
    emit();
  }

  Future<SetupPlan> readPlan({String? file, Set<String>? only}) async {
    if (busy) throw StateError('Emulator setup is already running.');
    if (!supported)
      throw UnsupportedError(
        'The tested native controller builds are currently available for macOS Apple Silicon. Linux, Windows and Android setup need their own validated packages; no desktop bridge is used on Android.',
      );
    await load();
    if (error != null) throw StateError(error!);
    final String source;
    Directory? base;
    if (file == null) {
      source = await asset('assets/setup/setup.json');
    } else {
      final f = File(file);
      if (await FileSystemEntity.type(file, followLinks: false) !=
              FileSystemEntityType.file ||
          await f.length() > 1024 * 1024)
        throw const FormatException(
          'Choose a regular setup JSON file smaller than 1 MiB.',
        );
      source = await f.readAsString();
      base = f.absolute.parent;
    }
    final j = jsonDecode(source) as Map;
    if (![1, 2].contains(j['schema_version']) ||
        j['host'] != host ||
        j['launchers'] is! Map)
      throw const FormatException(
        'This setup JSON does not match the current host or schema.',
      );
    final entries = (j['launchers'] as Map).cast<String, Map>();
    if (entries.isEmpty ||
        entries.keys.any((id) => !builds.any((b) => b.id == id)))
      throw const FormatException(
        'The setup file contains an unsupported emulator.',
      );
    final items = <SetupItem>[];
    for (final entry in entries.entries) {
      if (only != null && !only.contains(entry.key)) continue;
      var b = builds.firstWhere((b) => b.id == entry.key);
      // Importing an older reviewed setup pack explicitly selects its build.
      // The bundled recipe always selects the current release instead.
      if (j['schema_version'] == 2 && entry.value['source'] is Map) {
        final source = SetupPackage.fromJson(entry.value['source'] as Map);
        b =
            previousBuilds
                .where(
                  (old) =>
                      old.id == b.id &&
                      old.sourcePackage?.samePayload(source) == true,
                )
                .firstOrNull ??
            b;
      }
      await requireRuntime(b);
      if (entry.value.keys.any(
        (k) => !['source', 'core', 'cores', 'resources'].contains(k),
      ))
        throw const FormatException(
          'Setup files cannot supply commands, bridges or environment values.',
        );
      final packages = <String, SetupPackage>{};
      Future<String> path(
        Object? value,
        String slot, {
        bool localOnly = false,
      }) async {
        if (value is Map && !localOnly && j['schema_version'] == 2) {
          final package = SetupPackage.fromJson(value);
          await _trustPackage(b, slot, package);
          packages[package.reference] = package;
          return package.reference;
        }
        if (value is! String ||
            value.isEmpty ||
            value.contains(RegExp(r'[\x00\r\n]')))
          throw const FormatException('Invalid setup source path.');
        if (value.startsWith('tested:'))
          return testedSource(value.substring(7));
        if (value.contains('://'))
          throw const FormatException(
            'This tested setup pack imports extracted local application folders. Remote archives need a separately validated delivery recipe.',
          );
        final f = File(value);
        if (f.isAbsolute) return f.path;
        if (base == null)
          throw const FormatException('Choose an absolute local source path.');
        return File.fromUri(base.uri.resolve(value)).path;
      }

      final resources = <String, String>{};
      final allowed = b.isRpcs3
          ? ['ps3_firmware']
          : {'ryubing', 'eden'}.contains(b.id)
          ? ['switch_firmware', 'prod_keys', 'title_keys']
          : b.id == 'retroarch'
          ? ['bios']
          : <String>[];
      for (final r in (entry.value['resources'] as Map? ?? {}).entries) {
        if (!allowed.contains(r.key))
          throw const FormatException(
            'Unsupported resource type for this emulator.',
          );
        final source = await path(r.value, 'resources', localOnly: true);
        if (await FileSystemEntity.type(source, followLinks: false) !=
            FileSystemEntityType.notFound)
          resources[r.key as String] = source;
      }
      final cores = <String, String>{};
      for (final c in (entry.value['cores'] as Map? ?? {}).entries) {
        if (b.id != 'retroarch' || !coreBuilds.containsKey(c.key)) {
          throw const FormatException('Unknown RetroArch core');
        }
        cores[c.key as String] = await path(c.value, 'cores:${c.key}');
      }
      items.add(
        SetupItem(
          b,
          await path(entry.value['source'], 'source'),
          entry.value['core'] == null
              ? null
              : await path(entry.value['core'], 'core'),
          resources,
          cores: cores,
          downloads: packages,
          packageRoot: base,
        ),
      );
    }
    if (items.isEmpty)
      throw const FormatException('No emulators were selected.');
    plan = SetupPlan(items);
    error = null;
    notice = 'Review the sources and resources, then start setup.';
    emit();
    return plan!;
  }

  Future<void> _trustPackage(
    TestedBuild build,
    String slot,
    SetupPackage package,
  ) async {
    final j = jsonDecode(await asset('assets/setup/setup.json')) as Map;
    final entry = (j['launchers'] as Map)[build.id] as Map?;
    Object? value;
    if (entry != null) {
      value = slot.startsWith('cores:')
          ? (entry['cores'] as Map? ?? {})[slot.substring(6)]
          : entry[slot];
    }
    final accepted =
        value is Map && package.samePayload(SetupPackage.fromJson(value)) ||
        slot == 'source' && build.sourcePackage?.samePayload(package) == true ||
        (build.compatibleSetupPackages[slot] ?? const <SetupPackage>[]).any(
          package.samePayload,
        );
    if (!accepted)
      throw const FormatException(
        'This archive is not a reviewed delivery recipe for this emulator. Import a compatible extracted local build, or use the bundled recipe.',
      );
  }

  String testedSource(String key) {
    if (project == null)
      throw StateError(
        'Choose a setup JSON with local application paths. The development test cache is not bundled with Broomm.',
      );
    if (coreBuilds.containsKey(key)) {
      return '$project/prototype-data/retroarch/cores/${key}_libretro.dylib';
    }
    const names = {
      'retroarch': 'RetroArch.app',
      'dolphin': 'Dolphin.app',
      'rpcs3': 'RPCS3.app',
      'rpcs3-intel': 'RPCS3.app',
      'azahar': 'Azahar.app',
      'ryubing': 'Ryujinx.app',
      'melonds': 'melonDS.app',
      'duckstation': 'DuckStation.app',
      'pcsx2': 'PCSX2.app',
      'armsx2': 'ARMSX2.app',
      'ppsspp': 'PPSSPPSDL.app',
      'eden': 'eden.app',
    };
    if (names.containsKey(key))
      return '$project/prototype-data/$key/${names[key]}';
    return switch (key) {
      'snes9x' => '$project/prototype-data/retroarch/snes9x_libretro.dylib',
      'ps3_firmware' => '$project/prototype-data/rpcs3/portable/dev_flash',
      'switch_firmware' =>
        '$project/prototype-data/ryubing/user/bis/system/Contents/registered',
      'prod_keys' => '$project/prototype-data/ryubing/user/system/prod.keys',
      'title_keys' => '$project/prototype-data/ryubing/user/system/title.keys',
      _ => throw const FormatException('Unknown tested source'),
    };
  }

  Future<void> install(SetupPlan selected) {
    if (busy) return _work ?? Future.value();
    final work = _install(selected);
    _work = work;
    return work.whenComplete(() {
      if (identical(_work, work)) _work = null;
    });
  }

  Future<void> finishSetup() async {
    if (busy) cancel();
    await _work;
  }

  Future<void> _addRetroCores(
    SetupItem item,
    Directory release,
    DownloadCancellation cancellation,
  ) async {
    if (item.cores.isEmpty) return;
    final parent = Directory('${release.path}/cores');
    await ownedDirectory(parent);
    for (final entry in item.cores.entries) {
      cancellation.check();
      setPhase('Installing RetroArch / ${retroSystemByCore(entry.key)}');
      if (await FileSystemEntity.type(entry.value, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError(
          'The ${entry.key} core differs from the pinned build.',
        );
      }
      final hash = await sha256File(entry.value);
      final c = _coreVersions(entry.key)
          .where((c) => c['sha256'] == hash)
          .firstOrNull;
      if (c == null) {
        throw StateError(
          'The ${entry.key} core differs from the pinned build.',
        );
      }
      final target = Directory('${parent.path}/${entry.key}-${c['sha256']}');
      if (await target.exists()) {
        await ownedDirectory(target);
        if (await sha256File('${target.path}/core.dylib') != c['sha256']) {
          throw StateError('A managed core changed; its files were kept.');
        }
        continue;
      }
      final stage = await parent.createTemp('.core-');
      try {
        await File('${stage.path}/receipt.json')
            .writeAsString(jsonEncode(c), flush: true);
        await File(entry.value).copy('${stage.path}/core.dylib');
        if (await sha256File('${stage.path}/core.dylib') != c['sha256']) {
          throw const FileSystemException('Core copy verification failed');
        }
        cancellation.check();
        await stage.rename(target.path);
      } finally {
        if (await stage.exists()) await stage.delete(recursive: true);
      }
    }
  }

  Future<void> _checkCoreRemoval(Directory cores) async {
    if (await FileSystemEntity.type(cores.path, followLinks: false) ==
        FileSystemEntityType.notFound)
      return;
    await ownedDirectory(cores);
    await for (final entry in cores.list(followLinks: false)) {
      if (entry is! Directory)
        throw StateError('Unrecognized core files were kept.');
      final file = File('${entry.path}/receipt.json');
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() > 65536)
        throw StateError('Unrecognized core installation was kept.');
      final receipt = jsonDecode(await file.readAsString()) as Map;
      final id = receipt['id'], hash = receipt['sha256'];
      if (!coreBuilds.containsKey(id) ||
          hash is! String ||
          !_coreVersions(id as String).any((c) => c['sha256'] == hash))
        throw StateError('Unrecognized core ownership was kept.');
      final name = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
      final staged = RegExp(r'^\.core-[a-zA-Z0-9_-]+$').hasMatch(name);
      if (!staged && name != '$id-$hash')
        throw StateError('Core ownership differs from its directory.');
      await for (final child in entry.list(followLinks: false)) {
        if (child is! File ||
            !{
              'core.dylib',
              'receipt.json',
            }.contains(child.uri.pathSegments.last))
          throw StateError(
            'The core folder contains unrelated files; they were kept.',
          );
      }
      if (!staged && await sha256File('${entry.path}/core.dylib') != hash)
        throw StateError('The managed core changed; its files were kept.');
    }
  }

  Future<SetupItem> _prepareItem(
    SetupItem item,
    Directory release,
    Directory working,
    DownloadCancellation cancellation,
  ) async {
    final reuse =
        await FileSystemEntity.type(release.path, followLinks: false) ==
        FileSystemEntityType.directory;
    Future<String> resolve(
      String value,
      String slot,
      String installed,
      String? hash,
    ) async {
      final package = item.downloads[value];
      if (package == null) return value;
      await _trustPackage(item.build, slot, package);
      cancellation.check();
      if (reuse &&
          (hash == null ||
              await FileSystemEntity.type(installed, followLinks: false) ==
                      FileSystemEntityType.file &&
                  await sha256File(installed) == hash))
        return installed;
      return downloads.prepare(
        package,
        working,
        cancellation,
        (phase, fraction) => transferProgress(
          '${item.build.name}${slot.startsWith('cores:') ? ' / ${slot.substring(6)}' : ''}: $phase',
          fraction,
        ),
        localRoot: item.packageRoot,
      );
    }

    final b = item.build;
    final source = await resolve(
      item.source,
      'source',
      '${release.path}/${b.bundle}',
      null,
    );
    final core = item.core == null
        ? null
        : await resolve(
            item.core!,
            'core',
            '${release.path}/snes9x_libretro.dylib',
            b.coreHash,
          );
    final cores = <String, String>{};
    for (final entry in item.cores.entries) {
      final package = item.downloads[entry.value];
      final version = package == null
          ? coreBuilds[entry.key]!
          : _coreVersions(entry.key)
                    .where(
                      (c) =>
                          c['setup_package'] is Map &&
                          package.samePayload(
                            SetupPackage.fromJson(c['setup_package'] as Map),
                          ),
                    )
                    .firstOrNull ??
                coreBuilds[entry.key]!;
      final hash = version['sha256'] as String;
      cores[entry.key] = await resolve(
        entry.value,
        'cores:${entry.key}',
        '${release.path}/cores/${entry.key}-$hash/core.dylib',
        hash,
      );
    }
    return SetupItem(b, source, core, item.resources, cores: cores);
  }

  Future<void> _install(SetupPlan selected) async {
    if (busy) return;
    busy = true;
    error = null;
    final cancellation = _cancel = DownloadCancellation();
    emit();
    SessionLease? lease;
    Directory? working;
    var retainWorking = false;
    try {
      lease = await SessionLease.acquire(data);
      await ownedDirectory(root);
      // Reload under the cross-process lease before modifying selections.
      await load();
      if (error != null) throw StateError(error!);
      for (final requested in selected.items) {
        cancellation.check();
        final b = requested.build;
        await requireRuntime(b);
        if (removals.containsKey(b.id))
          throw StateError(
            'Finish removing ${b.name} before setting it up again.',
          );
        final parent = Directory('${root.path}/${b.id}');
        await ownedDirectory(parent);
        final destination = Directory('${parent.path}/${b.hash}');
        var item = requested;
        if (requested.downloads.isNotEmpty) {
          working ??= await root.createTemp('.packages-');
          item = await _prepareItem(
            requested,
            destination,
            working,
            cancellation,
          );
        }
        setPhase('Checking ${b.name} ${b.version}');
        await verifyBundle(b, item.source, cancellation);
        if (b.coreHash != null &&
            (item.core == null || await sha256File(item.core!) != b.coreHash))
          throw StateError(
            'The Snes9x core does not match the tested build. Select the tested core.',
          );
        if (await FileSystemEntity.type(destination.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          final staging = await parent.createTemp('.staging-');
          var published = false;
          try {
            setPhase('Installing ${b.name}');
            await copyTree(
              item.source,
              '${staging.path}/${b.bundle}',
              cancellation,
              allowBundleLinks: true,
            );
            if (item.core != null)
              await File(item.core!)
                  .copy('${staging.path}/snes9x_libretro.dylib');
            await File('${staging.path}/local-symbols.txt').writeAsString(
              await asset('assets/setup/${b.id}.symbols'),
              flush: true,
            );
            for (final entry in item.resources.entries) {
              setPhase('Preparing ${b.name} resources');
              await ownedDirectory(Directory('${staging.path}/resources'));
              await validateResource(entry.key, entry.value);
              await copyTree(
                entry.value,
                '${staging.path}/resources/${entry.key}',
                cancellation,
              );
            }
            setPhase('Verifying ${b.name}');
            await verifyBundle(b, '${staging.path}/${b.bundle}', cancellation);
            if (b.coreHash != null &&
                await sha256File('${staging.path}/snes9x_libretro.dylib') !=
                    b.coreHash)
              throw StateError('Copied core verification failed');
            final receipt = jsonEncode({
              'schema_version': 1,
              'id': b.id,
              'hash': b.hash,
              'version': b.version,
              'host': host,
              'resources': item.resources.keys.toList(),
              'installedAt': DateTime.now().toUtc().toIso8601String(),
            });
            final f = File('${staging.path}/receipt.json');
            await f.writeAsString(receipt, flush: true);
            if (await f.readAsString() != receipt)
              throw const FileSystemException('Setup receipt readback failed');
            cancellation.check();
            await staging.rename(destination.path);
            published = true;
          } finally {
            if (!published && await staging.exists())
              await staging.delete(recursive: true);
          }
        } else {
          await ownedDirectory(destination);
          final receipt = File('${destination.path}/receipt.json');
          if (await FileSystemEntity.type(receipt.path, followLinks: false) !=
              FileSystemEntityType.file)
            throw StateError(
              'An unrecognized managed folder already exists. Its files have been kept.',
            );
          final record = jsonDecode(await receipt.readAsString()) as Map;
          if (record['id'] != b.id || record['hash'] != b.hash)
            throw StateError(
              'Managed installation identity does not match its receipt.',
            );
          await verifyBundle(
            b,
            '${destination.path}/${b.bundle}',
            cancellation,
          );
          if (b.coreHash != null &&
              await sha256File('${destination.path}/snes9x_libretro.dylib') !=
                  b.coreHash)
            throw StateError(
              'The installed Snes9x core changed. Its files and profile progress were kept.',
            );
        }
        await _addResources(item, destination, cancellation);
        await _addRetroCores(item, destination, cancellation);
        installed[b.id] = b.hash;
        await _saveSelections();
        final readback = jsonDecode(
          await File('${root.path}/selected.json').readAsString(),
        ) as Map;
        if ((readback['selected'] as Map)[b.id] != b.hash)
          throw const FileSystemException('Setup selection readback failed');
      }
      notice = 'Emulators are ready. Choose a downloaded game on Home to play.';
      plan = null;
      await load();
    } catch (e) {
      retainWorking = e is SetupWriterUncertain;
      log?.write(
        'Emulator setup did not complete. Prior installations and profile progress were preserved.',
        level: 'warning',
      );
      error = e is DownloadCancelled
          ? 'Setup cancelled. Completed installations and profile data have been kept.'
          : '$e';
    } finally {
      if (working != null && !retainWorking) {
        // An interrupted disk-image attachment remains private. Never walk or
        // recursively delete a mount whose detach was not acknowledged.
        try {
          var pending = false;
          await for (final entry in working.list(followLinks: false)) {
            if (entry is Directory &&
                await File('${entry.path}/mount-pending').exists())
              pending = true;
          }
          if (!pending) await working.delete(recursive: true);
        } catch (_) {
          log?.write(
            'Private setup staging was retained because cleanup could not be confirmed.',
            level: 'warning',
          );
        }
      }
      await lease?.release();
      busy = false;
      _cancel = null;
      phase = '';
      progress = null;
      emit();
    }
  }

  void cancel() {
    _cancel?.cancel();
    notice = 'Cancelling setup…';
    emit();
  }

  Future<void> _saveSelections() async {
    final text = jsonEncode({
      'schema_version': 1,
      'selected': installed,
      'removals': removals,
    });
    await atomicText('${root.path}/selected.json', text);
    if (await File('${root.path}/selected.json').readAsString() != text)
      throw const FileSystemException('Emulator selection readback failed');
  }

  Future<void> remove(TestedBuild build) {
    if (busy) return _work ?? Future.value();
    final work = _remove(build);
    _work = work;
    return work.whenComplete(() {
      if (identical(_work, work)) _work = null;
    });
  }

  Future<void> _remove(TestedBuild build) async {
    busy = true;
    error = null;
    emit();
    SessionLease? lease;
    try {
      lease = await SessionLease.acquire(data);
      await load();
      if (error != null) throw StateError(error!);
      if (_knownBuild(build.id, build.hash) == null)
        throw StateError('Unknown managed emulator');
      if (installed[build.id] != build.hash && removals[build.id] != build.hash)
        throw StateError('This managed emulator is not installed.');
      final parent = Directory('${root.path}/${build.id}');
      await ownedDirectory(parent);
      final release = Directory('${parent.path}/${build.hash}');
      final trash = Directory('${parent.path}/.removing-${build.hash}');
      if (!removals.containsKey(build.id)) {
        if (await FileSystemEntity.type(release.path, followLinks: false) !=
            FileSystemEntityType.directory)
          throw StateError(
            'The managed installation is missing or linked. Existing profile data has been kept.',
          );
        final receipt = File('${release.path}/receipt.json');
        if (await FileSystemEntity.type(receipt.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await receipt.length() > 65536)
          throw StateError(
            'This folder is not a recognized managed installation. Its files have been kept.',
          );
        final record = jsonDecode(await receipt.readAsString()) as Map;
        if (record['id'] != build.id || record['hash'] != build.hash)
          throw StateError(
            'Managed installation ownership could not be verified.',
          );
        for (final entry in await release.list(followLinks: false).toList()) {
          if (![
            build.bundle,
            'resources',
            'snes9x_libretro.dylib',
            if (build.id == 'retroarch') 'cores',
            'local-symbols.txt',
            'receipt.json',
          ].contains(entry.uri.pathSegments.where((p) => p.isNotEmpty).last))
            throw StateError(
              'The managed folder contains unrelated files. Inspect it before removal; all data has been kept.',
            );
        }
        if (build.id == 'retroarch')
          await _checkCoreRemoval(Directory('${release.path}/cores'));
        removals[build.id] = build.hash;
        installed.remove(build.id);
        await _saveSelections(); // Durable intent before any destructive work.
      }
      final releaseType = await FileSystemEntity.type(
        release.path,
        followLinks: false,
      );
      final trashType = await FileSystemEntity.type(
        trash.path,
        followLinks: false,
      );
      if (releaseType != FileSystemEntityType.notFound) {
        if (releaseType != FileSystemEntityType.directory ||
            trashType != FileSystemEntityType.notFound)
          throw StateError(
            'Removal found conflicting or linked folders. Existing files have been kept.',
          );
        await release.rename(trash.path);
      } else if (trashType != FileSystemEntityType.notFound &&
          trashType != FileSystemEntityType.directory) {
        throw StateError('The removal staging folder is linked or invalid.');
      }
      setPhase('Removing ${build.name}');
      // Only this exact private deletion checkpoint is disposable; profiles and
      // source installations are siblings elsewhere, never traversed here.
      if (await trash.exists()) await trash.delete(recursive: true);
      removals.remove(build.id);
      try {
        await _saveSelections();
      } catch (_) {
        removals[build.id] = build.hash;
        rethrow;
      }
      resourceProblems.remove(build.id);
      notice =
          '${build.name} removed. Profile settings, saves and save states have been kept.';
      plan = null;
    } catch (e) {
      error = '$e';
      log?.write(
        'Managed emulator removal did not complete; profile progress retained.',
        level: 'warning',
      );
    } finally {
      await lease?.release();
      busy = false;
      phase = '';
      emit();
    }
  }

  TestedBuild? _knownBuild(String id, String hash) => [
    ...builds,
    ...previousBuilds,
  ].where((b) => b.id == id && b.hash == hash).firstOrNull;

  Iterable<Map> _coreVersions(String id) sync* {
    if (coreBuilds[id] case final Map current) yield current;
    yield* previousCoreBuilds.where((c) => c['id'] == id);
  }

  TestedBuild? buildFor(String name) {
    final current = builds.where((b) => b.name == name).firstOrNull;
    if (current == null) return null;
    return _knownBuild(current.id, installed[current.id] ?? '') ?? current;
  }

  bool ready(String name) {
    final b = buildFor(name);
    return b != null && installed[b.id] == b.hash;
  }

  Future<void> requireRuntime(TestedBuild build) async {
    if (build.architecture != 'x64' || host != 'macos-arm64') return;
    ProcessResult result;
    try {
      result = await Process.run('/usr/bin/arch', [
        '-x86_64',
        '/usr/bin/true',
      ]).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw StateError(
        '${build.name} requires Rosetta on this Mac. Install Rosetta yourself, then retry setup.',
      );
    }
    if (result.exitCode != 0)
      throw StateError(
        '${build.name} requires Rosetta on this Mac. Install Rosetta yourself, then retry setup.',
      );
  }

  Future<void> _addResources(
    SetupItem item,
    Directory release,
    DownloadCancellation cancellation,
  ) async {
    for (final entry in item.resources.entries) {
      final parent = Directory('${release.path}/resources');
      await ownedDirectory(parent);
      final target = '${parent.path}/${entry.key}';
      if (await FileSystemEntity.type(target, followLinks: false) !=
          FileSystemEntityType.notFound)
        continue;
      await validateResource(entry.key, entry.value);
      final stage = await release.createTemp('.resource-');
      try {
        await copyTree(entry.value, '${stage.path}/payload', cancellation);
        cancellation.check();
        if (await FileSystemEntity.type(
              '${stage.path}/payload',
              followLinks: false,
            ) ==
            FileSystemEntityType.directory) {
          await Directory('${stage.path}/payload').rename(target);
        } else {
          await File('${stage.path}/payload').rename(target);
        }
      } finally {
        if (await stage.exists()) await stage.delete(recursive: true);
      }
    }
    final receipt = File('${release.path}/receipt.json');
    final j = jsonDecode(await receipt.readAsString()) as Map;
    j['resources'] = {
      ...(j['resources'] as List).cast<String>(),
      ...item.resources.keys,
    }.toList();
    await atomicText(receipt.path, jsonEncode(j));
  }

  /// The add-on importer runs without an input bridge, inside private staging.
  /// Its caller holds the same session lease as setup and game launch.
  Future<String> azaharInstaller(DownloadCancellation cancellation) async {
    if (!supported)
      throw UnsupportedError(
        '3DS add-on installation needs the tested macOS ARM64 Azahar pack on this build.',
      );
    await load();
    final b = buildFor('Azahar');
    if (error != null) throw StateError(error!);
    if (b == null || !ready('Azahar'))
      throw StateError(
        'Set up Azahar in Emulator Settings, then choose Download Updates and DLC again.',
      );
    final bundle = '${root.path}/${b.id}/${b.hash}/${b.bundle}';
    await verifyBundle(b, bundle, cancellation);
    return '$bundle/${b.executable}';
  }

  Future<(String, Directory)> prepareAzaharAddons(
    String profileId,
    DownloadCancellation cancellation,
  ) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(profileId))
      throw const FormatException('Invalid profile identity');
    final executable = await azaharInstaller(cancellation);
    final b = buildFor('Azahar')!;
    final runtime = await prepareManagedProfile(
      data,
      profileId,
      b,
      Directory('${root.path}/${b.id}/${b.hash}'),
    );
    return (executable, runtime);
  }

  Future<(String, Directory)> preparePackages(
    String platform,
    String profileId,
    DownloadCancellation cancellation, {
    String? emulator,
  }) async {
    if (!{'wii', 'switch', 'psp'}.contains(platform) ||
        !supported ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(profileId)) {
      throw UnsupportedError(
        'Native package installation requires a supported private desktop profile.',
      );
    }
    await load();
    final name =
        emulator ??
        switch (platform) {
          'wii' => 'Dolphin',
          'psp' => 'PPSSPP',
          _ => 'Ryubing',
        };
    if (emulator != null &&
        (platform != 'switch' || !{'Ryubing', 'Eden'}.contains(emulator)))
      throw const FormatException('Unsupported package emulator');
    final b = buildFor(name);
    if (error != null) throw StateError(error!);
    if (b == null || !ready(name))
      throw StateError('Set up $name in Emulator Settings first.');
    final release = Directory('${root.path}/${b.id}/${b.hash}');
    await verifyBundle(b, '${release.path}/${b.bundle}', cancellation);
    final runtime = await prepareManagedProfile(data, profileId, b, release);
    return ('${release.path}/${b.bundle}/${b.executable}', runtime);
  }

  Future<(String, Directory)> prepareRpcs3Addons(
    String profileId,
    DownloadCancellation cancellation, {
    String emulator = 'RPCS3',
  }) async {
    if (!supported)
      throw UnsupportedError(
        'RPCS3 import needs the tested macOS ARM64 build.',
      );
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(profileId))
      throw const FormatException('Invalid profile identity');
    await load();
    final b = buildFor(emulator);
    if (error != null) throw StateError(error!);
    if (b == null || !b.isRpcs3 || !ready(emulator))
      throw StateError('Set up $emulator in Emulator Settings first.');
    await requireRuntime(b);
    final release = Directory('${root.path}/${b.id}/${b.hash}');
    await verifyBundle(b, '${release.path}/${b.bundle}', cancellation);
    final runtime = await prepareManagedProfile(data, profileId, b, release);
    return ('${release.path}/${b.bundle}/${b.executable}', runtime);
  }

  Future<ResolvedSession> resolve(LaunchGame game, String profileId) =>
      _resolve(
        game.emulator,
        game.rom,
        profileId,
        configuration: false,
        coreId: game.retroCore,
        contentId: game.id,
      );

  // Inspect/restore ordinary progress even before firmware is provisioned.
  // This still verifies the managed build and prepares only private storage.
  Future<ResolvedSession> resolveProgress(LaunchGame game, String profileId) =>
      _resolve(
        game.emulator,
        game.rom,
        profileId,
        configuration: true,
        coreId: game.retroCore,
        contentId: game.id,
      );

  Future<ResolvedSession> resolveConfiguration(
    String emulator,
    String profileId,
  ) => _resolve(emulator, '', profileId, configuration: true);

  Future<ResolvedSession> _resolve(
    String emulator,
    String rom,
    String profileId, {
    required bool configuration,
    String? coreId,
    String? contentId,
  }) async {
    if (!supported)
      throw UnsupportedError(
        'The native controller bridge is not yet available for this host.',
      );
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(profileId))
      throw StateError('Invalid profile identity');
    await load();
    final b = buildFor(emulator);
    if (error != null) throw StateError(error!);
    if (b == null || !ready(emulator))
      throw StateError('Set up $emulator in Emulator Settings first.');
    final release = Directory('${root.path}/${b.id}/${b.hash}');
    if (!configuration &&
        resourceProblems[b.id] != null &&
        !(b.isRpcs3 &&
            await File(
              '${data.path}/profiles/$profileId/emulators/rpcs3/portable/dev_flash/sys/external/liblv2.sprx',
            ).exists()) &&
        !({'ryubing', 'eden'}.contains(b.id) &&
            await File(
              '${data.path}/profiles/$profileId/emulators/${b.profileId}/${b.id == 'eden' ? 'data/eden/keys' : 'user/system'}/prod.keys',
            ).exists() &&
            await File(
              '${data.path}/profiles/$profileId/emulators/${b.profileId}/${b.id == 'eden' ? 'data/eden/keys' : 'user/system'}/title.keys',
            ).exists() &&
            await Directory(
              '${data.path}/profiles/$profileId/emulators/${b.profileId}/${b.id == 'eden' ? 'data/eden/nand' : 'user/bis'}/system/Contents/registered',
            ).exists()))
      throw StateError(
        '${resourceProblems[b.id]}. Add the required local resources in Emulator Settings before playing.',
      );
    await verifyBundle(
      b,
      '${release.path}/${b.bundle}',
      DownloadCancellation(),
    );
    await requireRuntime(b);
    final runtime = await prepareManagedProfile(data, profileId, b, release);
    var executable = '${release.path}/${b.bundle}/${b.executable}';
    var home = '${runtime.path}/home';
    if (b.id == 'rpcs3-intel') {
      // RPCS3 uses HOME for its macOS caches even with XDG_CACHE_HOME set.
      // Share only the ordinary PS3 data/configuration; retain separate Intel
      // caches without migrating or clearing the existing ARM caches.
      home = '${runtime.path}/home-intel';
      for (final path in [
        home,
        '$home/Library',
        '$home/Library/Application Support',
        '${runtime.path}/cache-intel',
      ])
        await ownedDirectory(Directory(path));
      final link = Link('$home/Library/Application Support/rpcs3');
      final type = await FileSystemEntity.type(link.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        await link.create('../../../portable');
      } else if (type != FileSystemEntityType.link ||
          await link.target() != '../../../portable') {
        throw StateError(
          'The private Intel RPCS3 configuration location changed. Existing progress was kept.',
        );
      }
    }
    if (b.id == 'melonds') {
      // macOS Qt 6 resolves its default preferences outside a child HOME.
      // melonDS's supported adjacent portable directory provides isolation.
      // A private copy of its single-file static executable anchors that path;
      // every launch verifies the same pinned bytes before executing it.
      final launcher =
          '${runtime.path}/launcher/melonDS.app/Contents/MacOS/melonDS';
      await ownedDirectory(File(launcher).parent);
      await ownedDirectory(Directory('${runtime.path}/launcher/portable'));
      if (!await File(launcher).exists())
        await copyTree(executable, launcher, DownloadCancellation());
      if (await sha256File(launcher) != b.hash)
        throw StateError(
          'The private melonDS launcher changed. Existing progress was kept.',
        );
      executable = launcher;
    }
    var core = b.coreHash == null
        ? null
        : '${release.path}/snes9x_libretro.dylib';
    var coreHash = b.coreHash;
    if (coreId != null) {
      if (b.id != 'retroarch' || !coreBuilds.containsKey(coreId)) {
        throw StateError('Unknown RetroArch core');
      }
      retroGameDirectory(coreId, contentId!);
      if (!installedCores.contains(coreId)) {
        throw StateError(
          'Set up RetroArch / ${retroSystemByCore(coreId)} in Emulator Settings first.',
        );
      }
      coreHash = installedCoreBuilds[coreId]!['sha256'] as String;
      core = '${release.path}/cores/$coreId-$coreHash/core.dylib';
    }
    if (core != null && await sha256File(core) != coreHash)
      throw StateError(
        'The managed core changed. Its saved data has been kept.',
      );
    if (coreId == 'flycast')
      await prepareFlycastSaves(runtime.path, contentId!, rom);
    await File(
      '${runtime.path}/local-symbols.txt',
    ).writeAsString(await asset('assets/setup/${b.id}.symbols'), flush: true);
    return ResolvedSession(
      PreparedEmulator(
        b.engine,
        runtime.path,
        executable,
        b.sdl,
        b.sdlLibrary == null
            ? null
            : '${release.path}/${b.bundle}/${b.sdlLibrary}',
        core,
        coreId: coreId,
        contentId: contentId,
        retroNativeStateNames: b.retroNativeStateNames,
        retroStateDirectory:
            coreId != null &&
                installedCoreBuilds[coreId]?['isolated_states'] == true
            ? '${retroGameDirectory(coreId, contentId!)}/states/${b.hash}-$coreHash'
            : null,
        cacheDirectory: b.id == 'rpcs3-intel'
            ? '${runtime.path}/cache-intel'
            : null,
        userDirectory: b.id == 'eden'
            ? '${runtime.path}/data/eden'
            : b.id == 'melonds'
            ? '${runtime.path}/launcher/portable'
            : b.isPs2
            ? '${runtime.path}/user/${b.id}/${b.engine}'
            : b.id == 'duckstation'
            ? '${runtime.path}/home/Library/Application Support/DuckStation'
            : b.id == 'azahar'
            ? '${runtime.path}/home/Library/Application Support/Azahar'
            : null,
      ),
      rom,
      b.hash,
      b.native,
      home: home,
      coreHash: coreHash,
      readOnly: [root.path, '${data.path}/library'],
    );
  }

  Future<void> verifyBundle(
    TestedBuild b,
    String path,
    DownloadCancellation cancellation,
  ) async {
    final expected = jsonDecode(await asset(b.integrityAsset)) as Map;
    await inspectTree(path, allowLinks: true);
    final actual = <String>{};
    final links = <String>{};
    await for (final entry in Directory(
      path,
    ).list(recursive: true, followLinks: false)) {
      cancellation.check();
      final rel = entry.path.substring(path.length + 1);
      if (entry is File) actual.add(rel);
      if (entry is Link) links.add(rel);
      if (entry is Link &&
          (expected['links'] as Map)[rel] != await entry.target())
        throw StateError('${b.name} has an unexpected bundle link.');
    }
    final files = (expected['files'] as Map).cast<String, String>();
    final expectedLinks = (expected['links'] as Map).keys
        .cast<String>()
        .toSet();
    if (links.length != expectedLinks.length ||
        !links.containsAll(expectedLinks))
      throw StateError('${b.name} is missing required application links.');
    if (actual.length != files.length || !actual.containsAll(files.keys))
      throw StateError(
        '${b.name} does not match the tested application bundle.',
      );
    final paths = files.keys.toList();
    for (var i = 0; i < paths.length; i += 64) {
      cancellation.check();
      final batch = paths.skip(i).take(64).toList();
      final result = await runOwnedTool('/usr/bin/shasum', [
        '-a',
        '256',
        ...batch.map((p) => '$path/$p'),
      ]);
      final lines = const LineSplitter().convert(result);
      if (lines.length != batch.length)
        throw StateError('Incomplete ${b.name} fingerprint');
      for (var n = 0; n < batch.length; n++) {
        if (lines[n].substring(0, 64) != files[batch[n]])
          throw StateError(
            '${b.name} files changed or are not the tested build. Existing settings have been kept.',
          );
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    cancel();
    super.dispose();
  }
}

Future<void> ownedDirectory(Directory directory) async {
  if (directory.path.contains(RegExp(r'[\x00\r\n]')))
    throw const FileSystemException('Invalid application data path');
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    await ownedDirectory(directory.parent);
    await directory.create();
  } else if (type != FileSystemEntityType.directory)
    throw FileSystemException('Expected an owned directory', directory.path);
}

Future<void> inspectTree(String path, {bool allowLinks = false}) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.directory)
    throw StateError(
      'Choose an existing, extracted application/resource folder.',
    );
  final base = await Directory(path).resolveSymbolicLinks();
  var count = 0, bytes = 0;
  await for (final entry in Directory(
    path,
  ).list(recursive: true, followLinks: false)) {
    if (++count > 30000 || entry.path.contains(RegExp(r'[\x00\r\n]')))
      throw StateError('Source tree exceeds the supported structure.');
    if (entry is Link) {
      if (!allowLinks)
        throw StateError('Resource folders cannot contain symbolic links.');
      final target = await entry.target();
      final resolved = await entry.resolveSymbolicLinks();
      if (File(target).isAbsolute || !resolved.startsWith('$base/'))
        throw StateError('A bundle link leaves the application folder.');
    } else if (entry is File) {
      bytes += await entry.length();
      if (bytes > 8 * 1024 * 1024 * 1024)
        throw StateError('Source tree exceeds 8 GiB.');
    } else if (entry is! Directory) {
      throw StateError('Unsupported source file type');
    }
  }
}

Future<void> validateResource(String kind, String path) async {
  if (kind.endsWith('_keys')) {
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        await File(path).length() > 2 * 1024 * 1024)
      throw StateError('Choose a regular key file smaller than 2 MiB.');
  } else {
    await inspectTree(path);
    if (kind == 'ps3_firmware' &&
        !await File('$path/sys/external/liblv2.sprx').exists())
      throw StateError('Choose the extracted PS3 dev_flash folder.');
    if (kind == 'switch_firmware' &&
        !(await Directory(
          path,
        ).list().toList()).any((e) => e.path.endsWith('.nca')))
      throw StateError(
        'Choose the installed Switch registered firmware folder.',
      );
  }
}

Future<String> runOwnedTool(String executable, List<String> args) async {
  final p = await Process.start(executable, args);
  final out = <int>[], err = <int>[];
  var excess = false;
  final outDone = Completer<void>(), errDone = Completer<void>();
  p.stdout.listen(
    (chunk) {
      if (out.length + chunk.length < 4 * 1024 * 1024)
        out.addAll(chunk);
      else
        excess = true;
    },
    onDone: outDone.complete,
    onError: outDone.completeError,
  );
  p.stderr.listen(
    (chunk) {
      if (err.length + chunk.length < 65536) err.addAll(chunk);
    },
    onDone: errDone.complete,
    onError: errDone.completeError,
  );
  int code;
  try {
    code = await p.exitCode.timeout(const Duration(minutes: 3));
  } on TimeoutException {
    p.kill(ProcessSignal.sigkill);
    await p.exitCode;
    throw StateError('A setup file operation timed out and was stopped.');
  } finally {
    await Future.wait([outDone.future, errDone.future]);
  }
  if (code != 0 || excess)
    throw StateError(
      'A setup file operation failed (status $code). Check the selected source and storage access.',
    );
  return utf8.decode(out);
}

Future<String> sha256File(
  String path, {
  DownloadCancellation? cancellation,
  void Function(int)? progress,
}) => gameFileHash(path, cancellation: cancellation, progress: progress);

Future<void> copyTree(
  String source,
  String target,
  DownloadCancellation cancellation, {
  bool allowBundleLinks = false,
}) async {
  cancellation.check();
  final type = await FileSystemEntity.type(source, followLinks: false);
  if (type == FileSystemEntityType.directory)
    await inspectTree(source, allowLinks: allowBundleLinks);
  else if (type != FileSystemEntityType.file)
    throw StateError('The selected local source is missing or linked.');
  if (await FileSystemEntity.type(target, followLinks: false) !=
      FileSystemEntityType.notFound)
    throw StateError('Setup refused to overwrite an existing destination.');
  if (Platform.isMacOS) {
    // APFS clones keep large, validated emulator trees cheap on macOS.
    await runOwnedTool('/bin/cp', ['-cR', source, target]);
  } else if (type == FileSystemEntityType.file) {
    await File(source).copy(target);
  } else {
    await Directory(target).create();
    final depth = Directory(source).uri.pathSegments
        .where((s) => s.isNotEmpty)
        .length;
    await for (final entry in Directory(
      source,
    ).list(recursive: true, followLinks: false)) {
      cancellation.check();
      final relative = entry.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .skip(depth)
          .join('/');
      final destination = '$target/$relative';
      if (entry is Directory) {
        await Directory(destination).create();
      } else if (entry is File) {
        await entry.copy(destination);
      } else if (entry is Link && allowBundleLinks) {
        await Link(destination).create(await entry.target());
      } else {
        throw StateError('The selected local source changed while copying.');
      }
    }
  }
  cancellation.check();
}
