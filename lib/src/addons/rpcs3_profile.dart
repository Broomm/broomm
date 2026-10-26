import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../progress/digest.dart' show progressFileHash;
import '../progress/layout.dart' show readPs3Sfo;
import 'files.dart';
import 'profile.dart' show LegacyRpcs3AddonProfile;

/// RPCS3 puts packages and game-created installation data in the same title
/// directory. Own package files individually, never that directory. Callers
/// hold SessionLease through preparation, recovery and publication.
class Rpcs3AddonProfile {
  Rpcs3AddonProfile(this.profile, {this.checkpoint});
  final Directory profile;
  final void Function(String)? checkpoint;
  Directory get user => Directory('${profile.path}/portable');
  File get record => File('${profile.path}/addons.json');
  Directory get transaction =>
      Directory('${profile.path}/.ps3-addon-transaction');
  static final _hash = RegExp(r'^[a-f0-9]{64}$');
  static final _owner = RegExp(r'^[a-f0-9]{32}/[1-9][0-9]*$');

  bool acceptsUnit(String path) =>
      RegExp(r'^dev_hdd0/game/[A-Z]{4}[0-9]{5}$').hasMatch(path) ||
      RegExp(
        r'^dev_hdd0/home/00000001/exdata/[A-Z]{2}[0-9]{4}-[A-Z]{4}[0-9]{5}_00-[A-Za-z0-9_]{16}\.rap$',
      ).hasMatch(path);
  bool directoryUnit(String path) => path.startsWith('dev_hdd0/game/');
  bool _acceptsFile(String path) {
    addonRelative(path);
    return RegExp(r'^dev_hdd0/game/[A-Z]{4}[0-9]{5}/.+$').hasMatch(path) ||
        (!directoryUnit(path) && acceptsUnit(path));
  }

  void _validate(Map value) {
    if (value['version'] != 2 ||
        value['files'] is! Map ||
        (value['files'] as Map).length > 100000)
      throw const FormatException('Invalid PS3 file ownership');
    for (final e in (value['files'] as Map).entries) {
      if (e.key is! String || !_acceptsFile(e.key as String) || e.value is! Map)
        throw const FormatException('Invalid PS3 owned file');
      final f = e.value as Map;
      if (f['hash'] is! String ||
          !_hash.hasMatch(f['hash'] as String) ||
          f['version'] is! int ||
          f['owners'] is! List ||
          (f['owners'] as List).isEmpty ||
          !(f['owners'] as List).every(
            (o) => o is String && _owner.hasMatch(o),
          ) ||
          (f['original'] != null &&
              (f['original'] is! String ||
                  !_hash.hasMatch(f['original'] as String))))
        throw const FormatException('Invalid PS3 owned file metadata');
    }
  }

  Future<Map<String, dynamic>> _registry() async {
    if (!await addonExists(record.path))
      return {'version': 2, 'files': <String, dynamic>{}};
    final j = await addonJson(record);
    _validate(j);
    return j;
  }

  Future<String?> _fingerprint(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file)
      throw const FileSystemException('PS3 package file is linked or invalid');
    return Isolate.run(() => progressFileHash(File(path)));
  }

  Future<String> _original(String hash) async {
    if (!_hash.hasMatch(hash))
      throw const FormatException('Invalid PS3 original fingerprint');
    return addonPath(
      profile,
      '.ps3-addon-originals/$hash',
      createParents: true,
    );
  }

  Future<void> _copy(String source, String target, String hash) async {
    if (await addonExists(target))
      throw const FileSystemException('A PS3 staging file already exists');
    await File(target).create(exclusive: true);
    final sink = File(target).openWrite();
    try {
      await sink.addStream(File(source).openRead());
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (await _fingerprint(target) != hash)
      throw const FileSystemException('PS3 package copy could not be verified');
  }

  Future<void> apply(
    String owner,
    Directory payload,
    Map<String, dynamic> units,
  ) async {
    if (!_owner.hasMatch(owner))
      throw const FormatException('Invalid PS3 add-on owner');
    await recover();
    final before = await _registry();
    final next = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
    final files = next['files'] as Map, sources = <String, String>{};
    final incomingPaths = <String>{};
    for (final e in units.entries) {
      if (!acceptsUnit(e.key) || e.value is! Map)
        throw const FormatException('Invalid PS3 package unit');
      final unit = e.value as Map, hashes = unit['files'] as Map;
      if (unit['version'] is! int || hashes.isEmpty || hashes.length > 100000)
        throw const FormatException('Invalid PS3 package inventory');
      if (directoryUnit(e.key)) {
        final metadata = File(
          await addonPath(user, '${e.key}/PARAM.SFO', createParents: true),
        );
        if (await addonExists(metadata.path) &&
            (await readPs3Sfo(metadata))['TITLE_ID'] != e.key.split('/').last)
          throw const FormatException(
            'Existing PS3 title metadata has a different identity; content was kept',
          );
      }
      for (final h in hashes.entries) {
        final path = directoryUnit(e.key) ? '${e.key}/${h.key}' : e.key;
        if (!_acceptsFile(path) ||
            h.value is! String ||
            !_hash.hasMatch(h.value as String) ||
            !incomingPaths.add(path) ||
            (!directoryUnit(e.key) && h.key != ''))
          throw const FormatException('Invalid PS3 package file');
        final old = files[path] as Map?;
        final owners = {
          ...?((old?['owners'] as List?)?.cast<String>()),
          owner,
        }.toList()..sort();
        if (old != null && (old['version'] as int) > (unit['version'] as int)) {
          files[path] = {...old, 'owners': owners};
        } else {
          files[path] = {
            'hash': h.value,
            'version': unit['version'],
            'owners': owners,
            if (old?['original'] != null) 'original': old!['original'],
          };
          sources[path] = await addonPath(payload, path);
        }
      }
    }
    for (final path in files.keys.toList().cast<String>()) {
      if (incomingPaths.contains(path)) continue;
      final file = files[path] as Map;
      final owners = (file['owners'] as List).where((o) => o != owner).toList();
      if (owners.isEmpty) {
        files.remove(path);
      } else {
        file['owners'] = owners;
      }
    }
    await _change(before, next, sources, {
      ...incomingPaths,
      for (final e in (before['files'] as Map).entries)
        if (((e.value as Map)['owners'] as List).contains(owner))
          e.key as String,
    });
  }

  Future<void> remove(String owner) async {
    if (!_owner.hasMatch(owner))
      throw const FormatException('Invalid PS3 add-on owner');
    await recover();
    final before = await _registry(),
        next =
            jsonDecode(jsonEncode(await _registry())) as Map<String, dynamic>;
    final files = next['files'] as Map, affected = <String>{};
    for (final path in files.keys.toList().cast<String>()) {
      final file = files[path] as Map, owners = file['owners'] as List;
      if (!owners.contains(owner)) continue;
      affected.add(path);
      final remaining = owners.where((o) => o != owner).toList();
      if (remaining.isEmpty) {
        files.remove(path);
      } else {
        file['owners'] = remaining;
      }
    }
    await _change(before, next, {}, affected);
  }

  Future<void> _change(
    Map before,
    Map next,
    Map<String, String> sources,
    Set<String> affected,
  ) async {
    final old = before['files'] as Map, wanted = next['files'] as Map;
    final ops = <Map<String, dynamic>>[];
    for (final path in affected) {
      final previous = old[path] as Map?, incoming = wanted[path] as Map?;
      final target = await addonPath(user, path, createParents: true);
      final actual = await _fingerprint(target);
      if (previous != null &&
          actual != null &&
          actual != previous['hash'] &&
          actual != incoming?['hash'])
        throw const FileSystemException(
          'A PS3 package file changed outside Broomm; existing content and progress were kept',
        );
      if (previous == null && incoming != null && actual != null) {
        // Preserve pre-existing metadata (and any overlapping package file)
        // durably before acquiring ownership. Uninstall restores these bytes.
        final original = await _original(actual);
        if (!await addonExists(original)) await _copy(target, original, actual);
        if (await _fingerprint(original) != actual)
          throw const FileSystemException(
            'The retained PS3 original changed; existing files were kept',
          );
        incoming['original'] = actual;
      }
      final expected =
          incoming?['hash'] as String? ?? previous?['original'] as String?;
      if (actual == expected) continue;
      if (incoming == null && actual != null && actual != previous?['hash'])
        throw const FileSystemException(
          'A PS3 package file changed outside Broomm; it was kept with its ownership record',
        );
      final source = incoming == null
          ? (expected == null ? null : await _original(expected))
          : sources[path];
      if (expected != null && source == null)
        throw const FileSystemException(
          'The newer shared PS3 package needs repair from the game that supplied it',
        );
      ops.add({
        'path': path,
        'old': actual,
        'new': expected,
        if (source != null) 'source': source,
      });
    }
    _validate(next);
    if (ops.isEmpty) {
      if (jsonEncode(before) != jsonEncode(next))
        await addonWrite(record, next);
      return;
    }
    final stage = await profile.createTemp('.ps3-addon-prepare-');
    var published = false;
    try {
      for (var i = 0; i < ops.length; i++) {
        final op = ops[i];
        if (op['new'] != null)
          await _copy(
            op['source'] as String,
            '${stage.path}/new-$i',
            op['new'] as String,
          );
        op.remove(
          'source',
        ); // Recovery accepts only local, index-addressed staging.
      }
      await addonWrite(File('${stage.path}/journal.json'), {
        'version': 2,
        'before': before,
        'next': next,
        'operations': ops,
      });
      if (await addonExists(transaction.path))
        throw const FileSystemException('PS3 package recovery is pending');
      await stage.rename(transaction.path);
      published = true;
      checkpoint?.call('prepared');
      await recover();
    } finally {
      if (!published && await stage.exists())
        await stage.delete(recursive: true);
    }
  }

  Future<void> recover() async {
    // Complete old directory journals before converting their recorded files.
    if (await addonExists('${profile.path}/addons-pending.json') ||
        await addonExists('${profile.path}/.addon-transaction'))
      await LegacyRpcs3AddonProfile(profile).recover();
    if (await addonExists(record.path)) {
      final old = await addonJson(record);
      if (old['version'] == 1) {
        final legacy = LegacyRpcs3AddonProfile(profile);
        final files = <String, dynamic>{};
        if (old['units'] is! Map)
          throw const FormatException('Invalid legacy PS3 ownership');
        for (final e in (old['units'] as Map).entries) {
          if (e.key is! String || !legacy.acceptsUnit(e.key as String))
            throw const FormatException('Invalid legacy PS3 unit');
          final u = e.value as Map;
          for (final f in (u['files'] as Map).entries) {
            final path = legacy.directoryUnit(e.key as String)
                ? '${e.key}/${f.key}'
                : e.key as String;
            if (files.containsKey(path) ||
                (!legacy.directoryUnit(e.key as String) && f.key != ''))
              throw const FormatException('Conflicting legacy PS3 files');
            files[path] = {
              'hash': f.value,
              'version': u['version'],
              'owners': u['owners'],
            };
          }
        }
        final migrated = {'version': 2, 'files': files};
        _validate(migrated);
        await addonWrite(record, migrated);
      }
    }
    if (!await addonExists(transaction.path)) return;
    final journal = File(
      await addonPath(profile, '.ps3-addon-transaction/journal.json'),
    );
    final j = await addonJson(journal);
    if (j['version'] != 2 ||
        j['operations'] is! List ||
        (j['operations'] as List).length > 100000)
      throw const FormatException('Invalid PS3 file recovery');
    final before = j['before'] as Map, next = j['next'] as Map;
    _validate(before);
    _validate(next);
    final current = jsonEncode(await _registry());
    if (current != jsonEncode(before) && current != jsonEncode(next))
      throw const FileSystemException('PS3 ownership changed during recovery');
    final committed = j['committed'] == true, seen = <String>{};
    if (committed && current != jsonEncode(next))
      throw const FormatException('PS3 committed ownership differs');
    final ops = (j['operations'] as List).cast<Map>();
    final names = {
      'journal.json',
      for (var i = 0; i < ops.length; i++) ...[
        if (ops[i]['old'] != null) 'old-$i',
        if (ops[i]['new'] != null) 'new-$i',
      ],
    };
    await for (final entry in transaction.list(followLinks: false)) {
      if (entry is! File || !names.contains(entry.uri.pathSegments.last))
        throw const FileSystemException(
          'PS3 recovery contains unrecognized files; they were kept',
        );
    }
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i], path = op['path'] as String;
      if (!_acceptsFile(path) || !seen.add(path))
        throw const FormatException('Invalid PS3 recovery path');
      final previous = op['old'] as String?, incoming = op['new'] as String?;
      final old = (before['files'] as Map)[path] as Map?,
          wanted = (next['files'] as Map)[path] as Map?;
      if ((previous != null && !_hash.hasMatch(previous)) ||
          (incoming != null && !_hash.hasMatch(incoming)) ||
          incoming != (wanted?['hash'] ?? old?['original']) ||
          (old == null && previous != wanted?['original']))
        throw const FormatException('PS3 recovery differs from its ownership');
      final target = await addonPath(user, path, createParents: true);
      final backup = await addonPath(transaction, 'old-$i'),
          ready = await addonPath(transaction, 'new-$i');
      var actual = await _fingerprint(target);
      final saved = await _fingerprint(backup);
      final preparedHash = await _fingerprint(ready);
      if ((saved != null && saved != previous) ||
          (preparedHash != null && preparedHash != incoming))
        throw const FileSystemException(
          'PS3 recovery data changed; all files were kept',
        );
      if (actual == incoming &&
          (committed || previous == null || saved == previous))
        continue;
      if (committed)
        throw const FileSystemException(
          'Committed PS3 package changed before cleanup; recovery was kept',
        );
      if (saved == null && previous != null) {
        if (actual != previous)
          throw const FileSystemException(
            'PS3 package changed during recovery; files were kept',
          );
        await File(target).rename(backup);
        actual = null;
        checkpoint?.call('backed-up');
      } else if (saved != previous) {
        throw const FileSystemException('PS3 recovery backup differs');
      }
      if (actual != null)
        throw const FileSystemException(
          'An unrelated file blocks PS3 recovery',
        );
      if (incoming != null) {
        if (preparedHash != incoming)
          throw const FileSystemException('Pending PS3 package is incomplete');
        await File(ready).rename(target);
        if (await _fingerprint(target) != incoming)
          throw const FileSystemException(
            'PS3 publication could not be verified',
          );
      }
      checkpoint?.call('published');
    }
    await addonWrite(record, next);
    await addonWrite(journal, {...j, 'committed': true});
    checkpoint?.call('committed');
    await transaction.delete(recursive: true);
  }
}
