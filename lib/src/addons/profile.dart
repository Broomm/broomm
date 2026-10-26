import 'dart:convert';
import 'dart:io';

import '../managed_emulators.dart' show sha256File;
import 'files.dart';

/// All callers hold SessionLease, including recovery before emulator startup.
/// Only content directories and individual tickets are units: title data,
/// extdata, configuration and save states can never enter a transaction.
class OwnedAddonProfile {
  OwnedAddonProfile(this.profile, {this.checkpoint});
  final Directory profile;
  final void Function(String)? checkpoint;
  bool acceptsUnit(String path) => isAddonUnit(path);
  bool directoryUnit(String path) => path.endsWith('/content');
  Directory get user => Directory(azaharUserPath(profile.path));
  File get record => File('${profile.path}/addons.json');
  File get pending => File('${profile.path}/addons-pending.json');
  Directory get transaction => Directory('${profile.path}/.addon-transaction');

  Future<Map<String, dynamic>> _registry() async {
    if (!await addonExists(record.path))
      return {'version': 1, 'units': <String, dynamic>{}};
    final j = await addonJson(record);
    _validateRegistry(j);
    return j;
  }

  void _validateRegistry(Map j) {
    if (j['version'] != 1 ||
        j['units'] is! Map ||
        (j['units'] as Map).length > 2048)
      throw const FormatException('Invalid profile add-on record');
    for (final e in (j['units'] as Map).entries) {
      if (e.key is! String || !acceptsUnit(e.key as String) || e.value is! Map)
        throw const FormatException('Invalid profile add-on unit');
      final unit = e.value as Map;
      _validateFiles(unit['files'] as Map, directoryUnit(e.key as String));
      if (unit['version'] is! int ||
          unit['owners'] is! List ||
          (unit['owners'] as List).isEmpty ||
          !(unit['owners'] as List).every(
            (o) =>
                o is String &&
                RegExp(r'^[a-f0-9]{32}/[1-9][0-9]*$').hasMatch(o),
          ))
        throw const FormatException('Invalid add-on ownership');
    }
  }

  void _validateFiles(Map files, bool directory, {bool allowEmpty = false}) {
    if ((!allowEmpty && files.isEmpty) ||
        files.length > 100000 ||
        (!directory && (files.length != 1 || !files.containsKey(''))))
      throw const FormatException('Invalid add-on file inventory');
    for (final e in files.entries) {
      if (directory) addonRelative(e.key as String);
      if (e.value is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(e.value as String))
        throw const FormatException('Invalid add-on file fingerprint');
    }
  }

  Future<Map<String, String>?> _inventory(String path, bool directory) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (directory) return addonInventory(Directory(path));
    if (type != FileSystemEntityType.file)
      throw const FileSystemException('Installed add-on is linked or invalid');
    return {'': await sha256File(path)};
  }

  Future<void> apply(
    String owner,
    Directory payload,
    Map<String, dynamic> units,
  ) async {
    if (!RegExp(r'^[a-f0-9]{32}/[1-9][0-9]*$').hasMatch(owner))
      throw const FormatException('Invalid add-on owner');
    await recover();
    final before = await _registry();
    final next = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
    final nextUnits = next['units'] as Map;
    final replacements = <String, String>{};
    for (final e in units.entries) {
      final path = e.key;
      if (!acceptsUnit(path))
        throw const FormatException('Invalid imported add-on location');
      final incoming = (e.value as Map).cast<String, dynamic>();
      _validateFiles(incoming['files'] as Map, directoryUnit(path));
      if (incoming['version'] is! int)
        throw const FormatException('Invalid title version');
      final old = nextUnits[path] as Map?;
      final owners = <String>{
        ...?((old?['owners'] as List?)?.cast<String>()),
        owner,
      }.toList()..sort();
      // A different installed release of the same title may already provide a
      // newer version. Claim it, and never silently downgrade shared content.
      final chosen =
          old != null && (old['version'] as int) > (incoming['version'] as int)
          ? old
          : incoming;
      nextUnits[path] = {...chosen, 'owners': owners};
      if (identical(chosen, incoming))
        replacements[path] = await addonPath(payload, path);
    }
    // A newer ticket can supersede this game's previous ticket. Keep units
    // still claimed by another installed ROM/server.
    for (final path in nextUnits.keys.toList().cast<String>()) {
      if (units.containsKey(path)) continue;
      final unit = nextUnits[path] as Map;
      final owners = (unit['owners'] as List)
          .cast<String>()
          .where((s) => s != owner)
          .toList();
      if (owners.isEmpty) {
        nextUnits.remove(path);
      } else {
        unit['owners'] = owners;
      }
    }
    _validateRegistry(next);
    await _change(before, next, replacements, {
      ...units.keys,
      for (final e in (before['units'] as Map).entries)
        if (((e.value as Map)['owners'] as List).contains(owner))
          e.key as String,
    });
  }

  Future<void> remove(String owner) async {
    await recover();
    final before = await _registry();
    final next = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
    final units = next['units'] as Map;
    for (final key in units.keys.toList()) {
      final unit = units[key] as Map;
      final owners = (unit['owners'] as List).where((s) => s != owner).toList();
      if (owners.isEmpty) {
        units.remove(key);
      } else {
        unit['owners'] = owners;
      }
    }
    await _change(before, next, {}, {
      for (final e in (before['units'] as Map).entries)
        if (((e.value as Map)['owners'] as List).contains(owner))
          e.key as String,
    });
  }

  Future<void> _change(
    Map before,
    Map next,
    Map<String, String> sources,
    Set<String> affected,
  ) async {
    final old = before['units'] as Map, desired = next['units'] as Map;
    final operations = <Map<String, dynamic>>[];
    for (final path in {...old.keys, ...desired.keys}.cast<String>()) {
      final previous = old[path] as Map?, incoming = desired[path] as Map?;
      if (!affected.contains(path)) continue;
      final target = await addonPath(user, path, createParents: true);
      final actual = await _inventory(target, directoryUnit(path));
      if (previous == null && actual != null)
        throw const FileSystemException(
          'The emulator already has untracked content for this title. It has been preserved.',
        );
      if (previous != null &&
          actual != null &&
          actual.keys.any((p) => !(previous['files'] as Map).containsKey(p)))
        throw const FileSystemException(
          'An add-on content folder contains untracked files. They have been kept; inspect the folder before retrying.',
        );
      if (incoming == null
          ? actual == null
          : actual != null &&
                sameAddonInventory(actual, incoming['files'] as Map))
        continue;
      if (incoming != null && !sources.containsKey(path))
        throw const FileSystemException(
          'The newer shared add-on needs repair. Run Download Updates and DLC on the installed version that supplied it; existing data was kept.',
        );
      operations.add({
        'path': path,
        'expected': previous?['files'],
        'old': actual,
        'new': incoming?['files'],
      });
    }
    if (operations.isEmpty) {
      if (jsonEncode(before) != jsonEncode(next))
        await addonWrite(record, next);
      return;
    }
    final stage = await profile.createTemp('.addon-prepare-');
    var published = false;
    try {
      for (var i = 0; i < operations.length; i++) {
        final op = operations[i], path = operations[i]['path'] as String;
        if (op['new'] == null) continue;
        final source = sources[path];
        if (source == null)
          throw const FileSystemException('Missing verified add-on source');
        if (directoryUnit(path)) {
          await copyAddonFiles(
            Directory(source),
            Directory('${stage.path}/new-$i'),
            (op['new'] as Map).cast<String, String>(),
          );
        } else {
          await File(source).copy('${stage.path}/new-$i');
          if (!sameAddonInventory(
            (await _inventory('${stage.path}/new-$i', false))!,
            op['new'] as Map,
          ))
            throw const FileSystemException(
              'Ticket copy could not be verified',
            );
        }
      }
      await addonWrite(File('${stage.path}/journal.json'), {
        'version': 1,
        'before': before,
        'next': next,
        'operations': operations,
      });
      if (await addonExists(transaction.path))
        throw const FileSystemException(
          'An add-on transaction is already pending',
        );
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
    if (!await addonExists(transaction.path) &&
        !await addonExists(pending.path))
      return;
    // Resolve every parent without following links, including on retry.
    if (!await addonExists(pending.path)) {
      await addonPath(profile, '.addon-transaction/journal.json');
      await addonWrite(
        pending,
        await addonJson(File('${transaction.path}/journal.json')),
      );
    }
    final journal = await addonJson(pending);
    if (journal['version'] != 1 ||
        journal['operations'] is! List ||
        (journal['operations'] as List).length > 4096)
      throw const FormatException('Invalid add-on recovery record');
    final before = journal['before'] as Map, next = journal['next'] as Map;
    _validateRegistry(before);
    _validateRegistry(next);
    final current = await _registry();
    final committed = journal['committed'] == true;
    if (jsonEncode(current) != jsonEncode(before) &&
        jsonEncode(current) != jsonEncode(next))
      throw const FileSystemException(
        'Profile add-on ownership changed during recovery',
      );
    if (committed && jsonEncode(current) != jsonEncode(next))
      throw const FileSystemException(
        'Committed add-on ownership does not match its checkpoint',
      );
    final ops = (journal['operations'] as List).cast<Map>();
    final paths = <String>{};
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i], path = ops[i]['path'] as String;
      if (!acceptsUnit(path) || !paths.add(path))
        throw const FormatException('Invalid recovery target');
      final directory = directoryUnit(path);
      final previous = op['old'] as Map?, incoming = op['new'] as Map?;
      if (previous != null)
        _validateFiles(previous, directory, allowEmpty: true);
      if (incoming != null) _validateFiles(incoming, directory);
      if (jsonEncode(op['expected']) !=
              jsonEncode((before['units'] as Map)[path]?['files']) ||
          jsonEncode(incoming) !=
              jsonEncode((next['units'] as Map)[path]?['files']))
        throw const FormatException(
          'Recovery ownership does not match the transaction',
        );
      final expected = op['expected'] as Map?;
      if (previous != null &&
          (expected == null ||
              previous.keys.any((p) => !expected.containsKey(p))))
        throw const FormatException('Recovery includes unowned content');
      final target = await addonPath(user, path, createParents: true);
      final backup = '${transaction.path}/old-$i',
          prepared = '${transaction.path}/new-$i';
      var actual = await _inventory(target, directory);
      if (committed) {
        if (incoming == null
            ? actual != null
            : actual == null || !sameAddonInventory(actual, incoming))
          throw const FileSystemException(
            'Committed add-on files changed before cleanup; recovery data is kept',
          );
        continue;
      }
      final saved = await _inventory(backup, directory);
      if (actual != null &&
          incoming != null &&
          sameAddonInventory(actual, incoming))
        continue;
      if (previous != null && saved == null) {
        if (actual == null || !sameAddonInventory(actual, previous))
          throw const FileSystemException(
            'Add-on recovery found changed content; files are kept',
          );
        if (directory) {
          await Directory(target).rename(backup);
        } else {
          await File(target).rename(backup);
        }
        actual = null;
        checkpoint?.call('backed-up');
      } else if (saved != null &&
          (previous == null || !sameAddonInventory(saved, previous))) {
        throw const FileSystemException('The add-on recovery backup changed');
      }
      if (actual != null)
        throw const FileSystemException(
          'An unrelated file blocks add-on recovery',
        );
      if (incoming != null) {
        final ready = await _inventory(prepared, directory);
        if (ready == null || !sameAddonInventory(ready, incoming))
          throw const FileSystemException(
            'The pending add-on payload is incomplete; recovery data is kept',
          );
        if (directory) {
          await Directory(prepared).rename(target);
        } else {
          await File(prepared).rename(target);
        }
        final verified = await _inventory(target, directory);
        if (verified == null || !sameAddonInventory(verified, incoming))
          throw const FileSystemException(
            'Installed add-on publication could not be verified',
          );
        checkpoint?.call('published');
      }
    }
    await addonWrite(record, next);
    await addonWrite(pending, {...journal, 'committed': true});
    checkpoint?.call('committed');
    if (await addonExists(transaction.path)) {
      if (await FileSystemEntity.type(transaction.path, followLinks: false) !=
          FileSystemEntityType.directory)
        throw const FileSystemException('Invalid add-on recovery directory');
      await transaction.delete(recursive: true);
    }
    await pending.delete();
  }
}

class AzaharAddonProfile extends OwnedAddonProfile {
  AzaharAddonProfile(super.profile, {super.checkpoint});
}

// Read/recover the directory transactions written by earlier Broomm builds.
// Current PS3 ownership is per file; see rpcs3_profile.dart.
class LegacyRpcs3AddonProfile extends OwnedAddonProfile {
  LegacyRpcs3AddonProfile(super.profile, {super.checkpoint});
  @override
  Directory get user => Directory('${profile.path}/portable');
  @override
  bool acceptsUnit(String path) =>
      RegExp(r'^dev_hdd0/game/[A-Z]{4}[0-9]{5}$').hasMatch(path) ||
      RegExp(
        r'^dev_hdd0/home/00000001/exdata/[A-Z]{2}[0-9]{4}-[A-Z]{4}[0-9]{5}_00-[A-Za-z0-9_]{16}\.rap$',
      ).hasMatch(path);
  @override
  bool directoryUnit(String path) => path.startsWith('dev_hdd0/game/');
}
