import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../progress/digest.dart';
import '../progress/files.dart';
import '../progress/store.dart';
import '../session_lease.dart';
import 'emulators.dart';
import 'psp_root.dart';

String androidPspMemoryStick(
  Map<String, String> binding,
  String server,
  String profile,
  String nonce,
) =>
    '/storage/emulated/0/Android/data/${binding['package']}/files/Broomm-PSP-$server-$profile-$nonce/memstick';

String pspTextDigest(String text) {
  final digest = ProgressDigest.sha256()..add(utf8.encode(text));
  return digest.finish();
}

bool pspInventorySame(Map a, Map b, {bool metadata = true}) =>
    a.length == b.length &&
    a.keys.every(
      (key) =>
          b[key] is Map &&
          a[key]['sha256'] == b[key]['sha256'] &&
          a[key]['bytes'] == b[key]['bytes'] &&
          (!metadata || a[key]['metadata'] == b[key]['metadata']),
    );

/// Durable profile ownership and memory-stick loans. Open emulator is detached:
/// no game session, lifetime watcher or close-on-Broomm-quit behavior is added.
class AndroidPspRootStore {
  AndroidPspRootStore(this.manager, {this.check});
  final AndroidEmulators manager;
  final void Function()? check;
  final _hex = RegExp(r'^[a-f0-9]{32}$');
  File get loanFile => File('${manager.data.path}/android/psp-loan.json');

  void phase(String text) {
    try {
      manager.phase?.call('PPSSPP: $text');
    } catch (_) {}
  }

  Map<String, String> arguments(Map record) => {
    ...(record['binding'] as Map).cast<String, String>(),
    for (final key in ['server', 'profile', 'ownerNonce'])
      key: record[key] as String,
  };

  Future<({int elapsed, int wall})> ensureClosed(
    Map<String, String> binding,
  ) async {
    check?.call();
    final report = await readAndroidPspState(manager, binding);
    if (report.state != AndroidPspState.idle)
      throw StateError(
        report.state == AndroidPspState.running
            ? 'PPSSPP is still running. Save and use its Exit action, then retry.'
            : 'PPSSPP’s shutdown could not be verified. Open its menu and use Exit, then retry. Recovery was kept.',
      );
    return (elapsed: report.elapsed, wall: report.wall);
  }

  Future<File> profileFile(String profile) async => progressFile(
    await manager.privateRoot(
      profile,
      androidEmulators.singleWhere((e) => e.id == 'ppsspp'),
    ),
    'root-profile.json',
  );

  void validateProfile(Map value, String server, String profile) {
    if (!_hex.hasMatch(server) ||
        !_hex.hasMatch(profile) ||
        value['version'] != 1 ||
        value['server'] != server ||
        value['profile'] != profile ||
        !_hex.hasMatch(value['ownerNonce'] as String? ?? '') ||
        value['binding'] is! Map ||
        !androidPspRootBinding(
          (value['binding'] as Map).cast<String, String>(),
        ) ||
        !{'creating', 'ready', 'retired'}.contains(value['phase']) ||
        !RegExp(r'^(?:[a-f0-9]{2}:){5}[a-f0-9]{2}$')
            .hasMatch(value['mac'] as String? ?? '') ||
        value['archives'] is! List ||
        (value['archives'] as List).length > 2 ||
        value['retained'] is! List ||
        (value['retained'] as List).length > 8)
      throw const FormatException(
        'Private PSP profile ownership is damaged. Nothing was adopted.',
      );
  }

  Future<Map<String, dynamic>> profile(
    String server,
    String profile,
    Map<String, String> binding,
  ) async {
    if (!_hex.hasMatch(server) ||
        !_hex.hasMatch(profile) ||
        !androidPspRootBinding(binding))
      throw const FormatException('Invalid private PSP profile identity.');
    await ensureClosed(binding);
    final file = await profileFile(profile);
    Map<String, dynamic>? previous;
    if (await progressExists(file.path)) {
      previous = await progressJson(file);
      validateProfile(previous, server, profile);
      final old = (previous['binding'] as Map).cast<String, String>();
      if (previous['phase'] != 'retired' &&
          old.entries.any((e) => e.key != 'build' && binding[e.key] != e.value))
        throw StateError(
          'PPSSPP’s private storage generation changed. Existing profile data and backups were kept.',
        );
      if (previous['phase'] == 'ready') {
        final value = {...previous, 'binding': binding};
        await manager.channel.invokeMapMethod<String, dynamic>(
          'rootPspSelection',
          arguments(value),
        );
        if (!mapEquals(old, binding)) await progressWrite(file, value);
        return value;
      }
    }
    final selected = manager.app(
      androidEmulators.singleWhere((e) => e.id == 'ppsspp'),
      package: binding['package'],
    );
    if (selected == null || selected.build != binding['build'])
      throw StateError('Refresh PPSSPP setup first.');
    Map<String, dynamic> value;
    if (previous == null || previous['phase'] == 'retired') {
      final inspected = await inspectAndroidPspRoot(manager, selected);
      if (!mapEquals(androidPspRootIdentity(inspected, selected), binding))
        throw StateError('PPSSPP changed during profile preparation.');
      final random = Random.secure();
      final macBytes = List.generate(6, (_) => random.nextInt(256));
      macBytes[0] = (macBytes[0] & 0xfc) | 2;
      final mac =
          previous?['mac'] as String? ??
          macBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
      // Keep the original controls, without copying account/console settings.
      final controls = utf8.decode(inspected['controls'] as List<int>);
      if (controls.runes.any((c) => c == 0 || c == 127))
        throw const FormatException('Unsupported PSP control-file encoding.');
      value = {
        'version': 1,
        'server': server,
        'profile': profile,
        'binding': binding,
        'ownerNonce': progressNonce(),
        'phase': 'creating',
        'mac': mac,
        'initialSettings': androidPspSettingsSeed(
          utf8.decode(inspected['config'] as List<int>),
          mac,
        ),
        'initialControls': controls,
        'archives': previous?['archives'] ?? <dynamic>[],
        'retained': previous?['retained'] ?? <dynamic>[],
      };
      await progressWrite(file, value);
    } else
      value = {...previous, 'binding': binding};
    for (var attempt = 0; attempt < 2; attempt++) {
      final result = await manager.channel.invokeMapMethod<String, dynamic>(
        'rootPspProfile',
        {
          ...arguments(value),
          'config': utf8.encode(value['initialSettings'] as String),
          'controls': utf8.encode(value['initialControls'] as String),
        },
      );
      if (result?['status'] == 'unclaimed') {
        final retained = List<dynamic>.from(value['retained'] as List);
        if (retained.length >= 8)
          throw StateError(
            'Several incomplete PSP preparations were kept. Review recovery before retrying.',
          );
        retained.add({
          'ownerNonce': value['ownerNonce'],
          'kind': 'unclaimed-initialization',
        });
        value.addAll({'retained': retained, 'ownerNonce': progressNonce()});
        await progressWrite(file, value);
        phase(
          'Keeping an unclaimed preparation and creating a fresh private directory.',
        );
        continue;
      }
      if (result?['status'] != 'ready' ||
          result?['memoryStick'] !=
              androidPspMemoryStick(
                binding,
                server,
                profile,
                value['ownerNonce'] as String,
              ))
        throw const FormatException(
          'Private PSP initialization was not verified.',
        );
      if ((value['archives'] as List).isNotEmpty) await restoreArchive(value);
      value['phase'] = 'ready';
      value.remove('initialSettings');
      value.remove('initialControls');
      await progressWrite(file, value);
      return value;
    }
    throw StateError(
      'Private PSP initialization remains incomplete. Existing directories were kept.',
    );
  }

  Future<Map<String, dynamic>?> loan() async {
    if (!await progressExists(loanFile.path)) return null;
    final value = await progressJson(
      await progressFile(manager.data, 'android/psp-loan.json'),
    );
    if (value['version'] != 1 ||
        !{'settings', 'game'}.contains(value['kind']) ||
        !{'selecting', 'selected', 'restoring'}.contains(value['phase']) ||
        ![
          'server',
          'profile',
          'ownerNonce',
          'transaction',
          'token',
          'restoreToken',
        ].every((key) => _hex.hasMatch(value[key] as String? ?? '')) ||
        value['binding'] is! Map ||
        !androidPspRootBinding(
          (value['binding'] as Map).cast<String, String>(),
        ))
      throw const FormatException(
        'PPSSPP’s memory-stick handoff record is damaged. It was kept.',
      );
    final binding = (value['binding'] as Map).cast<String, String>();
    final native =
        '/storage/emulated/0/Android/data/${binding['package']}/files';
    final selected = androidPspMemoryStick(
      binding,
      value['server'],
      value['profile'],
      value['ownerNonce'],
    );
    if (value['original'] != pspTextDigest(native) ||
        value['selected'] != pspTextDigest(selected))
      throw const FormatException(
        'PPSSPP’s memory-stick recovery identity changed.',
      );
    return value;
  }

  Future<Map<String, dynamic>> borrow(
    Map<String, dynamic> profile, {
    required String kind,
    required String transaction,
  }) async {
    if (!{'settings', 'game'}.contains(kind) || !_hex.hasMatch(transaction))
      throw const FormatException(
        'Invalid PSP handoff purpose or transaction.',
      );
    if (await loan() != null)
      throw StateError('Finish PPSSPP’s previous memory-stick handoff first.');
    final binding = (profile['binding'] as Map).cast<String, String>();
    await ensureClosed(binding);
    final selection = await manager.channel.invokeMapMethod<String, dynamic>(
      'rootPspSelection',
      arguments(profile),
    );
    final native =
        '/storage/emulated/0/Android/data/${binding['package']}/files';
    if (selection?['selection'] != 'native' ||
        selection?['sha256'] != pspTextDigest(native))
      throw StateError(
        'PPSSPP uses a different memory stick without a matching handoff. Nothing was overwritten.',
      );
    final value = <String, dynamic>{
      'version': 1,
      'kind': kind,
      'transaction': transaction,
      'server': profile['server'],
      'profile': profile['profile'],
      'ownerNonce': profile['ownerNonce'],
      'binding': binding,
      'phase': 'selecting',
      'token': progressNonce(),
      'restoreToken': progressNonce(),
      'original': selection!['sha256'],
      'selected': pspTextDigest(
        androidPspMemoryStick(
          binding,
          profile['server'],
          profile['profile'],
          profile['ownerNonce'],
        ),
      ),
    };
    await progressWrite(
      await progressFile(
        manager.data,
        'android/psp-loan.json',
        createParents: true,
      ),
      value,
    );
    await manager.channel.invokeMapMethod<String, dynamic>('rootPspSelect', {
      ...arguments(value),
      'selection': 'profile',
      'before': value['original'],
      'token': value['token'],
    });
    final verified = await manager.channel.invokeMapMethod<String, dynamic>(
      'rootPspSelection',
      arguments(value),
    );
    if (verified?['selection'] != 'profile' ||
        verified?['sha256'] != value['selected'])
      throw StateError(
        'PPSSPP’s private memory-stick selection was not confirmed. Recovery was kept.',
      );
    value['phase'] = 'selected';
    await progressWrite(loanFile, value);
    return value;
  }

  Future<void> restoreLoan({String? transaction}) async {
    final value = await loan();
    if (value == null) return;
    if (transaction == null
        ? value['kind'] != 'settings'
        : value['transaction'] != transaction)
      throw StateError(
        'Finish the original PPSSPP game before changing its memory stick.',
      );
    final binding = (value['binding'] as Map).cast<String, String>();
    final app = manager.app(
      androidEmulators.singleWhere((e) => e.id == 'ppsspp'),
      package: binding['package'],
    );
    if (app == null || app.build != binding['build'])
      throw StateError(
        'Restore the original PPSSPP installation before finishing its memory-stick handoff.',
      );
    await ensureClosed(binding);
    // Open emulator can change settings, auxiliary undo and game files. Hold
    // the entire private stick before restoring the standalone selection.
    if (value['kind'] == 'settings' && value['phase'] != 'restoring') {
      final profile = await progressJson(
        await profileFile(value['profile'] as String),
      );
      validateProfile(profile, value['server'], value['profile']);
      if (profile['ownerNonce'] != value['ownerNonce'])
        throw StateError(
          'The private PSP settings profile changed. Recovery was kept.',
        );
      await backup(profile);
    }
    value['phase'] = 'restoring';
    await progressWrite(loanFile, value);
    final selection = await manager.channel.invokeMapMethod<String, dynamic>(
      'rootPspSelection',
      arguments(value),
    );
    if (selection?['selection'] != 'native') {
      if (selection?['selection'] != 'profile' ||
          selection?['sha256'] != value['selected'])
        throw StateError(
          'PPSSPP’s selected memory stick changed. Recovery was kept.',
        );
      await manager.channel.invokeMapMethod<String, dynamic>('rootPspSelect', {
        ...arguments(value),
        'selection': 'native',
        'before': value['selected'],
        'token': value['restoreToken'],
      });
    }
    final verified = await manager.channel.invokeMapMethod<String, dynamic>(
      'rootPspSelection',
      arguments(value),
    );
    if (verified?['selection'] != 'native' ||
        verified?['sha256'] != value['original'])
      throw StateError(
        'PPSSPP’s original memory stick was not restored. Recovery was kept.',
      );
    await loanFile.delete();
    phase('Original standalone memory stick restored.');
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
      final binding = manager.pspRoot(package: app.package);
      if (binding == null || binding['build'] != app.build)
        throw StateError('Verify PPSSPP setup first.');
      final record = await this.profile(server, profile, binding);
      await borrow(record, kind: 'settings', transaction: progressNonce());
      await manager.channel.invokeMethod<void>('open', {
        'package': app.package,
      });
      phase(
        'Opened private profile settings. Close PPSSPP before the next save operation.',
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
      final relative = 'profiles/$id/emulators/ppsspp/root-profile.json';
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
                androidEmulators.singleWhere((e) => e.id == 'ppsspp'),
                package: package,
              ) !=
              null)
        throw StateError(
          'Finish the original PSP memory-stick handoff before retiring this installation.',
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
      final relative = 'profiles/$id/emulators/ppsspp/root-profile.json';
      if (!await progressExists('${manager.data.path}/$relative')) continue;
      final file = await progressFile(manager.data, relative);
      final record = await progressJson(file);
      validateProfile(record, record['server'], id);
      if ((record['binding'] as Map)['package'] != package ||
          record['phase'] == 'retired')
        continue;
      if (record['phase'] != 'ready')
        throw StateError(
          'Finish preparing the private PSP profile before uninstalling. Its data was kept.',
        );
      final current = manager.pspRoot(package: package);
      if (current == null)
        throw StateError(
          'Verify PPSSPP root setup before preserving its private profiles for removal.',
        );
      await backup(await profile(record['server'], id, current));
    }
  }

  Future<Map<String, dynamic>> nativeFiles(Map profile) async {
    return readAndroidPspInventory(
      manager,
      (profile['binding'] as Map).cast<String, String>(),
      arguments(profile),
      profileData: true,
      check: check,
    );
  }

  Future<Directory> archiveDirectory(Map profile, String nonce) async {
    if (!_hex.hasMatch(nonce))
      throw const FormatException('Invalid PSP backup identity.');
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
        value['binding'] is! Map ||
        value['mac'] != profile['mac'])
      throw const FormatException(
        'Private PSP backup ownership changed. All copies were kept.',
      );
    final binding = (value['binding'] as Map).cast<String, String>();
    if (!androidPspRootBinding(binding))
      throw const FormatException('Invalid PSP backup installation identity.');
    final files = androidPspInventory(
      value['files'],
      binding,
      profileData: true,
    );
    if (value['digest'] != progressEntriesDigest(files))
      throw const FormatException('Private PSP backup inventory changed.');
    for (final e in files.entries) {
      final file = await progressFile(directory, 'memory/${e.key}');
      if (!await file.exists() ||
          await file.length() != e.value['bytes'] ||
          await progressFileHash(file) != e.value['sha256'])
        throw const FileSystemException(
          'Private PSP backup is incomplete. Native data was kept.',
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
      throw StateError('PSP profile changed before its private backup.');
    final files = await nativeFiles(profile);
    final archives = List<String>.from(record['archives'] as List);
    if (archives.isNotEmpty) {
      final prior = await archiveManifest(record, archives.last);
      final old = prior['files'] as Map;
      if (pspInventorySame(old, files, metadata: false) &&
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
        pspInventorySame(pending['files'] as Map, files);
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
          'Incomplete private PSP backups need review. Native progress was kept.',
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
    phase('Backing up private memory-stick data.');
    for (final e in files.entries) {
      check?.call();
      final target = await progressFile(
        directory,
        'memory/${e.key}',
        createParents: true,
      );
      if (!await target.exists())
        await manager.channel.invokeMethod<void>('rootPspProfileRead', {
          ...arguments(profile),
          'archiveNonce': nonce,
          'path': e.key,
          ...e.value as Map,
          'target': target.path,
        });
      if (await target.length() != e.value['bytes'] ||
          await progressFileHash(target) != e.value['sha256'])
        throw const FileSystemException(
          'Private PSP backup readback failed. Native progress was kept.',
        );
    }
    if (!pspInventorySame(files, await nativeFiles(profile)))
      throw StateError(
        'PPSSPP data changed during its private backup. The incomplete copy was kept.',
      );
    await progressWrite(await progressFile(directory, 'manifest.json'), {
      'version': 1,
      'nonce': nonce,
      'server': record['server'],
      'profile': record['profile'],
      'ownerNonce': record['ownerNonce'],
      'binding': record['binding'],
      'mac': record['mac'],
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
          'Unrecognized private PSP backup files were kept.',
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
        'Private PSP backup needs its original APK and ABI. It was kept.',
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
      throw const FormatException('PSP backup restoration record changed.');
    profile['restore'] = state;
    await progressWrite(file, profile);
    Future<void> replay(Map operation) async {
      final target = await progressFile(
        directory,
        'memory/${operation['path']}',
      );
      await manager.channel.invokeMethod<Object?>('rootPspProfileReplace', {
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
            'Restored PSP data changed during recovery. All backups were kept.',
          );
        continue;
      }
      if (observed != null &&
          !{'PSP/SYSTEM/ppsspp.ini', 'PSP/SYSTEM/controls.ini'}.contains(path))
        throw StateError(
          'Unexpected data appeared in the new PSP memory stick. It was kept.',
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
    if (!pspInventorySame(current, expected, metadata: false) ||
        current.keys.any(
          (p) =>
              (current[p]['metadata'] as String).split(' ')[2] !=
              (expected[p]['metadata'] as String).split(' ')[2],
        ))
      throw StateError(
        'Private PSP backup restoration was not confirmed. Recovery was kept.',
      );
    profile.remove('restore');
    await progressWrite(file, profile);
  }
}
