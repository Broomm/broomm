import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../progress/digest.dart';
import '../progress/files.dart';
import '../progress/store.dart';
import '../session_lease.dart';
import '../emulators.dart';
import '../session.dart';
import '../playstation_firmware.dart';
import '../romm/client.dart';
import '../romm/transfer.dart';
import 'duck_root.dart';
import 'emulators.dart';
import 'save_plan.dart';

String androidDuckDirectory(Map r) =>
    '/storage/emulated/0/Android/data/com.github.stenzek.duckstation/files/Broomm-PS1-${r['server']}-${r['profile']}-${r['ownerNonce']}';

/// Durable, exclusive settings loans; all decisions and recovery remain Dart.
class AndroidDuckRootStore {
  AndroidDuckRootStore(this.manager, {this.check});
  final AndroidEmulators manager;
  final void Function()? check;
  final _hex = RegExp(r'^[a-f0-9]{32}$');
  File get loanFile => File('${manager.data.path}/android/duck-loan.json');
  void phase(String text) {
    try {
      manager.phase?.call('DuckStation: $text');
    } catch (_) {}
  }

  Map<String, String> arguments(Map r) => {
    ...(r['binding'] as Map).cast<String, String>(),
    for (final k in ['server', 'profile', 'ownerNonce']) k: r[k] as String,
  };

  /// A normal menu open/pause saves the retained Java settings interface. Then
  /// a frozen native check may discard the idle cache. No game is force-closed.
  Future<int> ensureClosed(
    Map<String, String> binding, {
    Map<String, int>? process,
  }) async {
    check?.call();
    var r = await readAndroidDuckState(manager, binding, process: process);
    if (r.state == AndroidDuckState.idle) return r.elapsed;
    if (r.state != AndroidDuckState.quiescent || r.process == null)
      throw StateError(
        'Close DuckStation’s game and return to Broomm before continuing. Progress was kept.',
      );
    final generation = r.process!;
    var opened = false;
    final clock = Stopwatch()..start();
    ({int elapsed, int wall})? pause;
    try {
      await manager.channel.invokeMethod<void>('open', {
        'package': binding['package'],
      });
      opened = true;
      do {
        check?.call();
        r = await readAndroidDuckState(manager, binding, process: generation);
        if (r.state == AndroidDuckState.menu) {
          pause = (elapsed: r.elapsed, wall: r.wall);
          break;
        }
        if (r.state == AndroidDuckState.running ||
            clock.elapsed > const Duration(seconds: 10))
          throw StateError(
            'DuckStation’s settings pause could not be verified. Recovery was kept.',
          );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      } while (true);
    } finally {
      if (opened) await manager.channel.invokeMethod<void>('returnToBroomm');
    }
    do {
      check?.call();
      r = await readAndroidDuckState(
        manager,
        binding,
        process: generation,
        pauseAfter: pause,
      );
      if (r.state == AndroidDuckState.quiescent && r.paused) break;
      if (r.state == AndroidDuckState.running ||
          clock.elapsed > const Duration(seconds: 20))
        throw StateError(
          'DuckStation’s background shutdown could not be verified. Recovery was kept.',
        );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    } while (true);
    final stopped = await readAndroidDuckState(
      manager,
      binding,
      process: generation,
      dispose: true,
      pauseAfter: pause,
    );
    if (stopped.state != AndroidDuckState.closed ||
        (await readAndroidDuckState(manager, binding)).state !=
            AndroidDuckState.idle)
      throw StateError(
        'DuckStation closure was not confirmed. Recovery was kept.',
      );
    return stopped.elapsed;
  }

  Future<File> profileFile(String profile) async => progressFile(
    await manager.privateRoot(
      profile,
      androidEmulators.singleWhere((e) => e.id == 'duckstation'),
    ),
    'root-profile.json',
  );
  void validateProfile(Map r, String server, String profile) {
    if (r['version'] != 1 ||
        r['server'] != server ||
        r['profile'] != profile ||
        ![
          server,
          profile,
          r['ownerNonce'] as String? ?? '',
        ].every(_hex.hasMatch) ||
        r['binding'] is! Map ||
        !androidDuckRootBinding((r['binding'] as Map).cast<String, String>()) ||
        !{'creating', 'ready', 'retired'}.contains(r['phase']) ||
        r['archives'] is! List ||
        (r['archives'] as List).length > 2 ||
        r['retained'] is! List ||
        (r['retained'] as List).length > 8)
      throw const FormatException(
        'Private PS1 ownership is damaged. Nothing was adopted.',
      );
  }

  AndroidApp selected(Map<String, String> binding) {
    final app = manager.app(
      androidEmulators.singleWhere((e) => e.id == 'duckstation'),
      package: binding['package'],
    );
    if (app == null || app.build != binding['build'])
      throw StateError(
        'Restore the original DuckStation installation before recovery.',
      );
    return app;
  }

  Future<Map<String, dynamic>> report(Map<String, String> binding) async {
    final r = await inspectAndroidDuckRoot(manager, selected(binding));
    if (!mapEquals(binding, androidDuckRootIdentity(r, selected(binding))))
      throw StateError('DuckStation identity changed.');
    return r;
  }

  Future<Map<String, dynamic>> profile(
    String server,
    String profile,
    Map<String, String> binding,
  ) async {
    await ensureClosed(binding);
    final file = await profileFile(profile);
    Map<String, dynamic>? previous;
    if (await progressExists(file.path)) {
      previous = await progressJson(file);
      validateProfile(previous, server, profile);
      if (previous['phase'] != 'retired' &&
          !mapEquals(
            (previous['binding'] as Map).cast<String, String>(),
            binding,
          ))
        throw StateError(
          'DuckStation’s private storage generation changed. Backups were kept.',
        );
      if (previous['phase'] == 'ready') {
        await manager.channel.invokeMethod<Object?>(
          'rootDuckProfile',
          arguments(previous),
        );
        return previous;
      }
    }
    var value = previous;
    if (value == null || value['phase'] == 'retired') {
      final native = await report(binding);
      value = {
        'version': 1,
        'server': server,
        'profile': profile,
        'binding': binding,
        'ownerNonce': progressNonce(),
        'phase': 'creating',
        'initialSettings': duckSettingsSeed(
          utf8.decode(native['config'] as List<int>),
        ),
        'bios': native['bios'],
        'archives': previous?['archives'] ?? <dynamic>[],
        'retained': previous?['retained'] ?? <dynamic>[],
      };
      await progressWrite(file, value);
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final r = await manager.channel.invokeMapMethod<String, dynamic>(
        'rootDuckProfile',
        {
          ...arguments(value),
          'config': utf8.encode(value['initialSettings'] as String),
        },
      );
      if (r?['status'] == 'unclaimed') {
        if ((value['retained'] as List).length >= 8)
          throw StateError(
            'Incomplete PS1 preparations need review. Native files were kept.',
          );
        (value['retained'] as List).add({
          'kind': 'unclaimed-initialization',
          'ownerNonce': value['ownerNonce'],
        });
        value['ownerNonce'] = progressNonce();
        await progressWrite(file, value);
        continue;
      }
      if (r?['status'] != 'ready' ||
          r?['directory'] != androidDuckDirectory(value))
        throw StateError('Private PS1 initialization was not confirmed.');
      if ((value['archives'] as List).isNotEmpty) {
        await restoreArchive(value);
      } else {
        final native = await nativeFiles(value);
        final bios = value['bios'];
        if (bios is! Map || bios.length > 32)
          throw StateError(
            'Import a PS1 BIOS into DuckStation once before setup. Private progress was kept.',
          );
        final transfer = progressNonce();
        for (final e in bios.entries) {
          check?.call();
          final name = e.key as String;
          if (!RegExp(r'^[A-Za-z0-9_. -]{1,120}$').hasMatch(name) ||
              e.value is! Map ||
              e.value['bytes'] != 524288)
            throw const FormatException('Incomplete PS1 BIOS inventory.');
          final target = await progressFile(
            manager.data,
            'android/shared-session/$transfer/bios/$name',
            createParents: true,
          );
          await manager.channel.invokeMethod<void>('rootDuckProfileRead', {
            ...arguments(value),
            'path': '@bios/$name',
            ...e.value as Map,
            'target': target.path,
          });
          if (await target.length() != 524288 ||
              await progressFileHash(target) != e.value['sha256'])
            throw StateError('PS1 BIOS capture was not verified.');
          await manager.channel.invokeMethod<Object?>(
            'rootDuckProfileReplace',
            {
              ...arguments(value),
              'path': 'bios/$name',
              'before': native['bios/$name']?['sha256'],
              'metadata': native['bios/$name']?['metadata'],
              'after': e.value['sha256'],
              'source': target.path,
              'token': progressNonce(),
            },
          );
        }
      }
      value['phase'] = 'ready';
      value.remove('initialSettings');
      value.remove('bios');
      await progressWrite(file, value);
      return value;
    }
    throw StateError(
      'Private PS1 initialization remains incomplete. All directories were kept.',
    );
  }

  Future<void> ensureFirmware(
    Map<String, dynamic> profile,
    int platformId,
    RommClient client,
    DownloadCancellation cancellation,
  ) async {
    check?.call();
    final files = await nativeFiles(profile);
    final bios = files.entries.where((e) => e.key.startsWith('bios/')).toList();
    if (bios.isNotEmpty) {
      if (bios.length > 32 || bios.any((e) => e.value['bytes'] != 524288))
        throw StateError('Private PS1 firmware is invalid. It was kept.');
      return;
    }
    final root = (await profileFile(profile['profile'] as String)).parent;
    await ensurePlayStationFirmware(
      ResolvedSession(
        PreparedEmulator('DuckStation', root.path, '', 0, null, null),
        '',
        androidDuckApk,
        const {},
      ),
      platformId,
      client,
      cancellation,
      phase,
    );
    check?.call();
    cancellation.check();
    final source = await progressFile(root, 'system/bios.bin'),
        hash = await progressFileHash(source),
        nonce = progressNonce();
    if (await source.length() != 524288)
      throw StateError('Private PS1 BIOS size changed.');
    final held = await progressFile(
      manager.data,
      'android/shared-session/$nonce/bios.bin',
      createParents: true,
    );
    await held.create(exclusive: true);
    final out = await held.open(mode: FileMode.writeOnly);
    try {
      await for (final b in source.openRead()) {
        check?.call();
        cancellation.check();
        await out.writeFrom(b);
      }
      await out.flush();
    } finally {
      await out.close();
    }
    if (await held.length() != 524288 ||
        await progressFileHash(held) != hash ||
        await progressFileHash(source) != hash)
      throw StateError('PS1 BIOS transfer was not verified.');
    await manager.channel.invokeMethod<Object?>('rootDuckProfileReplace', {
      ...arguments(profile),
      'path': 'bios/bios.bin',
      'before': null,
      'after': hash,
      'source': held.path,
      'token': nonce,
    });
    if ((await nativeFiles(profile))['bios/bios.bin']?['sha256'] != hash)
      throw StateError('Private PS1 BIOS publication was not confirmed.');
  }

  Future<Map<String, dynamic>?> loan() async {
    if (!await progressExists(loanFile.path)) return null;
    final r = await progressJson(
      await progressFile(manager.data, 'android/duck-loan.json'),
    );
    if (r['version'] != 1 ||
        !{'settings', 'game'}.contains(r['kind']) ||
        !{'installing', 'borrowed', 'restoring'}.contains(r['phase']) ||
        ![
          'server',
          'profile',
          'ownerNonce',
          'transaction',
          'token',
          'restoreToken',
        ].every((k) => _hex.hasMatch(r[k] as String? ?? '')) ||
        r['binding'] is! Map ||
        !androidDuckRootBinding((r['binding'] as Map).cast<String, String>()) ||
        r['original'] is! Map ||
        r['original']['sha256'] is! String ||
        r['routes'] is! Map)
      throw const FormatException(
        'DuckStation’s settings loan is damaged. All copies were kept.',
      );
    return r;
  }

  Future<Directory> loanDirectory(Map r) async => (await progressFile(
    manager.data,
    'android/shared-session/${r['transaction']}/config/.probe',
    createParents: true,
  )).parent;
  Map<String, String> routes(Map profile, AndroidDuckPlan? plan) {
    final base = androidDuckDirectory(profile),
        game = plan == null ? '$base/unassigned' : '$base/games/${plan.game}';
    return {
      'Folders/BIOS': '$base/bios',
      'Folders/MemoryCards': '$game/cards',
      'Folders/SaveStates': plan == null
          ? '$game/states'
          : '$game/${plan.stateGroup}',
      'Folders/GameSettings': '$base/gamesettings',
      'Folders/InputProfiles': '$base/inputprofiles',
      'Folders/Screenshots': '$base/screenshots',
      'MemoryCards/Card1Type': 'Shared',
      'MemoryCards/Card2Type': 'Shared',
      'MemoryCards/Card1Path': '$game/cards/card1.mcd',
      'MemoryCards/Card2Path': '$game/cards/card2.mcd',
      'Main/ApplyGameSettings': 'false',
    };
  }

  Future<void> borrow(
    Map<String, dynamic> profile, {
    required String kind,
    required String transaction,
    AndroidDuckPlan? plan,
  }) async {
    if (!{'settings', 'game'}.contains(kind) ||
        !_hex.hasMatch(transaction) ||
        (kind == 'game') != (plan != null))
      throw const FormatException('Invalid PS1 settings-loan purpose.');
    if (await loan() != null)
      throw StateError('Finish the previous DuckStation settings loan first.');
    final binding = (profile['binding'] as Map).cast<String, String>();
    await ensureClosed(binding);
    if (plan != null)
      await manager.channel.invokeMethod<void>('rootDuckGame', {
        ...arguments(profile),
        ...plan.arguments,
      });
    final before = await report(binding),
        private = await nativeFiles(profile),
        prefs = private['profile.ini'];
    if (prefs is! Map) throw StateError('Private PS1 settings are missing.');
    final r = <String, dynamic>{
      'version': 1,
      'kind': kind,
      'transaction': transaction,
      'server': profile['server'],
      'profile': profile['profile'],
      'ownerNonce': profile['ownerNonce'],
      'binding': binding,
      'phase': 'installing',
      'token': progressNonce(),
      'restoreToken': progressNonce(),
      'original': before['settings'],
      'routes': routes(profile, plan),
    };
    final dir = await loanDirectory(r),
        source = await progressFile(dir, 'private.ini');
    await manager.channel.invokeMethod<void>('rootDuckProfileRead', {
      ...arguments(r),
      'path': 'profile.ini',
      ...prefs,
      'target': source.path,
    });
    if (await progressFileHash(source) != prefs['sha256'])
      throw StateError('Private PS1 settings capture failed.');
    final config = duckIni({
      ...androidIni(await source.readAsString()),
      ...(r['routes'] as Map).cast<String, String>(),
    });
    final original = await progressFile(dir, 'original.ini'),
        working = await progressFile(dir, 'borrowed.ini');
    await original.writeAsBytes(before['config'] as List<int>, flush: true);
    await working.writeAsString(config, flush: true);
    if (await progressFileHash(original) != r['original']['sha256'])
      throw StateError('Original PS1 settings backup failed.');
    r['borrowed'] = await progressFileHash(working);
    await progressWrite(
      await progressFile(
        manager.data,
        'android/duck-loan.json',
        createParents: true,
      ),
      r,
    );
    await manager.channel.invokeMethod<Object?>('rootDuckProfileReplace', {
      ...arguments(r),
      'path': '@settings',
      'before': r['original']['sha256'],
      'metadata': r['original']['metadata'],
      'after': r['borrowed'],
      'source': working.path,
      'token': r['token'],
    });
    if ((await report(binding))['settings']['sha256'] != r['borrowed'])
      throw StateError('Private PS1 settings publication was not confirmed.');
    r['phase'] = 'borrowed';
    await progressWrite(loanFile, r);
  }

  Future<void> restoreLoan({String? transaction}) async {
    final r = await loan();
    if (r == null) return;
    if (transaction == null
        ? r['kind'] != 'settings'
        : r['transaction'] != transaction)
      throw StateError(
        'Finish the original PS1 game before restoring its settings.',
      );
    final binding = (r['binding'] as Map).cast<String, String>();
    await ensureClosed(binding);
    final current = await report(binding),
        info = current['settings'] as Map,
        dir = await loanDirectory(r),
        original = await progressFile(dir, 'original.ini');
    if (await progressFileHash(original) != r['original']['sha256'])
      throw StateError('Original PS1 settings recovery is damaged.');
    if (info['sha256'] != r['original']['sha256']) {
      final parsed = androidIni(utf8.decode(current['config'] as List<int>));
      if ((r['routes'] as Map).entries.any((e) => parsed[e.key] != e.value))
        throw StateError(
          'DuckStation changed its save routes. All native files and recovery were kept.',
        );
      if (r['phase'] != 'restoring') {
        // Hold the full observed configuration before either file replacement.
        final captured = await progressFile(
          dir,
          'captured-${progressNonce()}.ini',
        );
        await captured.writeAsBytes(
          current['config'] as List<int>,
          flush: true,
        );
        if (await progressFileHash(captured) != info['sha256'])
          throw StateError('PS1 preference capture failed.');
        final native = await nativeFiles(r), old = native['profile.ini'];
        if (old is! Map) throw StateError('Private PS1 settings disappeared.');
        r.addAll({
          'captured': captured.uri.pathSegments.last,
          'capturedHash': info['sha256'],
          'profileBefore': old,
          'profileToken': progressNonce(),
          'phase': 'restoring',
        });
        await progressWrite(loanFile, r);
      }
    }
    if (r['phase'] == 'restoring') {
      final captured = await progressFile(dir, r['captured'] as String);
      if (await progressFileHash(captured) != r['capturedHash'] ||
          !{
            r['capturedHash'],
            r['original']['sha256'],
          }.contains(info['sha256']))
        throw StateError(
          'PS1 settings changed after capture. Recovery was kept.',
        );
      await manager.channel.invokeMethod<Object?>('rootDuckProfileReplace', {
        ...arguments(r),
        'path': 'profile.ini',
        'before': r['profileBefore']['sha256'],
        'metadata': r['profileBefore']['metadata'],
        'after': r['capturedHash'],
        'source': captured.path,
        'token': r['profileToken'],
      });
      if (info['sha256'] != r['original']['sha256'])
        await manager.channel.invokeMethod<Object?>('rootDuckProfileReplace', {
          ...arguments(r),
          'path': '@settings',
          'before': info['sha256'],
          'metadata': info['metadata'],
          'after': r['original']['sha256'],
          'source': original.path,
          'token': r['restoreToken'],
        });
    }
    if ((await report(binding))['settings']['sha256'] !=
        r['original']['sha256'])
      throw StateError('Original PS1 settings restoration was not verified.');
    final profile = await progressJson(
      await profileFile(r['profile'] as String),
    );
    validateProfile(profile, r['server'], r['profile']);
    if (profile['ownerNonce'] != r['ownerNonce'])
      throw StateError('PS1 profile changed before settings backup.');
    await backup(profile);
    await loanFile.delete();
    phase('Original standalone settings restored.');
  }

  Future<void> restoreSettingsLoan() => restoreLoan();
  Future<void> openSettings(
    String server,
    String profile,
    AndroidApp app,
  ) async {
    final lease = await SessionLease.acquire(manager.data);
    try {
      await manager.ensureSetupAllowed();
      await restoreSettingsLoan();
      final binding = manager.duckRoot(package: app.package);
      if (binding == null || binding['build'] != app.build)
        throw StateError('Verify DuckStation root setup first.');
      await borrow(
        await this.profile(server, profile, binding),
        kind: 'settings',
        transaction: progressNonce(),
      );
      await manager.channel.invokeMethod<void>('open', {
        'package': app.package,
      });
      phase(
        'Opened private profile settings. Close any game before the next save operation.',
      );
    } finally {
      await lease.release();
    }
  }

  Future<void> retireInstallation(String package) async {
    final profiles = Directory('${manager.data.path}/profiles');
    if (!await progressExists(profiles.path)) return;
    await for (final entry in profiles.list(followLinks: false)) {
      if (entry is! Directory ||
          !_hex.hasMatch(
            entry.uri.pathSegments.where((s) => s.isNotEmpty).last,
          ))
        continue;
      final id = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final relative = 'profiles/$id/emulators/duckstation/root-profile.json';
      if (!await progressExists('${manager.data.path}/$relative')) continue;
      final file = await progressFile(manager.data, relative);
      final value = await progressJson(file);
      if ((value['binding'] as Map?)?['package'] != package) continue;
      validateProfile(value, value['server'], value['profile']);
      value['phase'] = 'retired';
      await progressWrite(file, value);
    }
    final prior = await loan();
    if (prior != null && (prior['binding'] as Map)['package'] == package) {
      if (prior['kind'] != 'settings' ||
          manager.app(
                androidEmulators.singleWhere((e) => e.id == 'duckstation'),
                package: package,
              ) !=
              null)
        throw StateError(
          'Finish the original PS1 settings handoff before retiring this installation.',
        );
      final file = await profileFile(prior['profile'] as String),
          value = await progressJson(
            await profileFile(prior['profile'] as String),
          );
      value['retiredSettingsLoan'] = prior;
      await progressWrite(file, value);
      await loanFile.delete();
    }
  }

  Future<void> backupInstallation(String package) async {
    await restoreSettingsLoan();
    final profiles = Directory('${manager.data.path}/profiles');
    if (!await progressExists(profiles.path)) return;
    await for (final entry in profiles.list(followLinks: false)) {
      final id = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entry is! Directory || !_hex.hasMatch(id)) continue;
      final relative = 'profiles/$id/emulators/duckstation/root-profile.json';
      if (!await progressExists('${manager.data.path}/$relative')) continue;
      final file = await progressFile(manager.data, relative);
      final record = await progressJson(file);
      validateProfile(record, record['server'], id);
      if ((record['binding'] as Map)['package'] != package ||
          record['phase'] == 'retired')
        continue;
      if (record['phase'] != 'ready')
        throw StateError(
          'Finish preparing the private PS1 profile before uninstalling. Its data was kept.',
        );
      final current = manager.duckRoot(package: package);
      if (current == null)
        throw StateError(
          'Verify DuckStation root setup before preserving its private profiles for removal.',
        );
      await backup(await profile(record['server'], id, current));
    }
  }

  Future<Map<String, dynamic>> nativeFiles(Map profile) async {
    return readAndroidDuckInventory(
      manager,
      (profile['binding'] as Map).cast<String, String>(),
      arguments(profile),
      profileData: true,
      check: check,
    );
  }

  Future<Directory> archiveDirectory(Map profile, String nonce) async {
    if (!_hex.hasMatch(nonce))
      throw const FormatException('Invalid PS1 backup identity.');
    final root = (await profileFile(profile['profile'] as String)).parent;
    final probe = await progressFile(
      root,
      'root-archives/$nonce/.probe',
      createParents: true,
    );
    return probe.parent;
  }

  Future<Map<String, dynamic>> archiveManifest(
    Map profile,
    String nonce,
  ) async {
    final directory = await archiveDirectory(profile, nonce);
    final value = await progressJson(
      await progressFile(directory, 'manifest.json'),
    );
    if (value['version'] != 1 ||
        value['server'] != profile['server'] ||
        value['profile'] != profile['profile'] ||
        value['nonce'] != nonce ||
        value['binding'] is! Map)
      throw const FormatException(
        'Private PS1 backup ownership changed. All copies were kept.',
      );
    final binding = (value['binding'] as Map).cast<String, String>();
    if (!androidDuckRootBinding(binding))
      throw const FormatException('Invalid PS1 backup installation identity.');
    final files = androidDuckInventory(value['files'], binding);
    if (value['digest'] != progressEntriesDigest(files))
      throw const FormatException('Private PS1 backup inventory changed.');
    for (final e in files.entries) {
      final file = await progressFile(directory, 'memory/${e.key}');
      if (!await file.exists() ||
          await file.length() != e.value['bytes'] ||
          await progressFileHash(file) != e.value['sha256'])
        throw const FileSystemException(
          'Private PS1 backup is incomplete. Native data was kept.',
        );
    }
    return value;
  }

  /// Hold every profile file, including global undo/settings, separately from
  /// game cloud exports. A partial capture never becomes the current backup.
  Future<void> backup(Map<String, dynamic> profile) async {
    final file = await profileFile(profile['profile'] as String);
    final record = await progressJson(file);
    validateProfile(record, profile['server'], profile['profile']);
    if (record['ownerNonce'] != profile['ownerNonce'] ||
        record['phase'] != 'ready')
      throw StateError('PS1 profile changed before its private backup.');
    final files = await nativeFiles(profile);
    final archives = List<String>.from(record['archives'] as List);
    if (archives.isNotEmpty) {
      final prior = await archiveManifest(record, archives.last);
      final old = prior['files'] as Map;
      if (duckInventorySame(old, files, metadata: false) &&
          files.keys.every(
            (p) =>
                (old[p]['metadata'] as String).split(' ')[2] ==
                (files[p]['metadata'] as String).split(' ')[2],
          ))
        return;
    }
    Map<String, dynamic>? pending = (record['backup'] as Map?)
        ?.cast<String, dynamic>();
    var reusable =
        pending != null &&
        _hex.hasMatch(pending['nonce'] as String? ?? '') &&
        pending['ownerNonce'] == record['ownerNonce'] &&
        pending['files'] is Map &&
        duckInventorySame(pending['files'] as Map, files);
    if (reusable) {
      final directory = await archiveDirectory(record, pending['nonce']);
      for (final e in files.entries) {
        final target = await progressFile(
          directory,
          'memory/${e.key}',
          createParents: true,
        );
        if (await target.exists() &&
            (await target.length() != e.value['bytes'] ||
                await progressFileHash(target) != e.value['sha256'])) {
          reusable = false;
          break;
        }
      }
    }
    if (pending != null && !reusable) {
      final retained = List<dynamic>.from(record['retained'] as List);
      if (retained.length >= 8)
        throw StateError(
          'Incomplete private PS1 backups need review. Native progress was kept.',
        );
      retained.add({'kind': 'partial-backup', 'nonce': pending['nonce']});
      record['retained'] = retained;
    }
    if (!reusable)
      pending = {
        'nonce': progressNonce(),
        'ownerNonce': record['ownerNonce'],
        'files': files,
      };
    record['backup'] = pending;
    await progressWrite(file, record);
    final nonce = pending!['nonce'] as String,
        directory = await archiveDirectory(record, nonce);
    phase('Backing up private settings data.');
    for (final e in files.entries) {
      check?.call();
      final target = await progressFile(
        directory,
        'memory/${e.key}',
        createParents: true,
      );
      if (!await target.exists())
        await manager.channel.invokeMethod<void>('rootDuckProfileRead', {
          ...arguments(profile),
          'archiveNonce': nonce,
          'path': e.key,
          ...e.value as Map,
          'target': target.path,
        });
      if (await target.length() != e.value['bytes'] ||
          await progressFileHash(target) != e.value['sha256'])
        throw const FileSystemException(
          'Private PS1 backup readback failed. Native progress was kept.',
        );
    }
    if (!duckInventorySame(files, await nativeFiles(profile)))
      throw StateError(
        'DuckStation data changed during its private backup. The incomplete copy was kept.',
      );
    await progressWrite(await progressFile(directory, 'manifest.json'), {
      'version': 1,
      'nonce': nonce,
      'server': record['server'],
      'profile': record['profile'],
      'ownerNonce': record['ownerNonce'],
      'binding': record['binding'],
      'files': files,
      'digest': progressEntriesDigest(files),
    });
    await archiveManifest(record, nonce);
    archives.add(nonce);
    final expired = archives.length > 2 ? archives.removeAt(0) : null;
    record['archives'] = archives;
    record.remove('backup');
    if (expired != null) record['cleanupArchive'] = expired;
    await progressWrite(file, record);
    if (record['cleanupArchive'] != null) {
      await removeArchive(record, record['cleanupArchive'] as String);
      record.remove('cleanupArchive');
      await progressWrite(file, record);
    }
  }

  Future<void> removeArchive(Map profile, String nonce) async {
    final manifest = await archiveManifest(profile, nonce),
        directory = await archiveDirectory(profile, nonce);
    final known = {
      'manifest.json',
      for (final path in (manifest['files'] as Map).keys) 'memory/$path',
    };
    await for (final entry in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is Link ||
          entry is File &&
              !known.contains(
                entry.path
                    .substring(directory.path.length + 1)
                    .replaceAll(Platform.pathSeparator, '/'),
              ))
        throw const FileSystemException(
          'Unrecognized private PS1 backup files were kept.',
        );
    }
    await directory.delete(recursive: true);
  }

  Future<void> restoreArchive(Map<String, dynamic> profile) async {
    final nonce = (profile['archives'] as List).last as String;
    final manifest = await archiveManifest(profile, nonce);
    final binding = (profile['binding'] as Map).cast<String, String>(),
        old = (manifest['binding'] as Map).cast<String, String>();
    if (old['apk'] != binding['apk'] || old['abi'] != binding['abi'])
      throw StateError(
        'Private PS1 backup needs its original APK and ABI. It was kept.',
      );
    final directory = await archiveDirectory(profile, nonce),
        file = await profileFile(profile['profile']);
    final expected = manifest['files'] as Map;
    final state =
        (profile['restore'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{
          'archive': nonce,
          'done': <String>[],
          'pending': null,
        };
    if (state['archive'] != nonce || state['done'] is! List)
      throw const FormatException('PS1 backup restoration record changed.');
    profile['restore'] = state;
    await progressWrite(file, profile);
    Future<void> replay(Map operation) async {
      final target = await progressFile(
        directory,
        'memory/${operation['path']}',
      );
      await manager.channel.invokeMethod<Object?>('rootDuckProfileReplace', {
        ...arguments(profile),
        ...operation,
        'archiveNonce': nonce,
        'source': target.path,
      });
    }

    if (state['pending'] != null) {
      await replay(state['pending'] as Map);
      (state['done'] as List).add(state['pending']['path']);
      state['pending'] = null;
      await progressWrite(file, profile);
    }
    var current = await nativeFiles(profile);
    for (final e in expected.entries) {
      final path = e.key as String,
          desired = e.value as Map,
          observed = current[path] as Map?;
      if ((state['done'] as List).contains(path)) {
        if (observed?['sha256'] != desired['sha256'] ||
            observed?['bytes'] != desired['bytes'])
          throw StateError(
            'Restored PS1 data changed during recovery. All backups were kept.',
          );
        continue;
      }
      if (observed != null && path != 'profile.ini')
        throw StateError(
          'Unexpected data appeared in the new PS1 workspace. It was kept.',
        );
      final operation = <String, dynamic>{
        'path': path,
        'before': observed?['sha256'],
        'metadata': observed?['metadata'],
        'after': desired['sha256'],
        'mode': (desired['metadata'] as String).split(' ')[2],
        'token': progressNonce(),
      };
      state['pending'] = operation;
      await progressWrite(file, profile);
      await replay(operation);
      (state['done'] as List).add(path);
      state['pending'] = null;
      await progressWrite(file, profile);
    }
    current = await nativeFiles(profile);
    if (!duckInventorySame(current, expected, metadata: false) ||
        current.keys.any(
          (p) =>
              (current[p]['metadata'] as String).split(' ')[2] !=
              (expected[p]['metadata'] as String).split(' ')[2],
        ))
      throw StateError(
        'Private PS1 backup restoration was not confirmed. Recovery was kept.',
      );
    profile.remove('restore');
    await progressWrite(file, profile);
  }
}
