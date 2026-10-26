import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'files.dart';
import 'package_profile.dart';

Map<String, String> readWiiContentMap(List<int> bytes) {
  if (bytes.length % 28 != 0 || bytes.length > 28 * 65536)
    throw const FormatException('Invalid Wii shared-content map');
  final result = <String, String>{}, hashes = <String>{};
  for (var i = 0; i < bytes.length; i += 28) {
    final id = ascii.decode(bytes.sublist(i, i + 8));
    final hash = bytes
        .sublist(i + 8, i + 28)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (!RegExp(r'^[a-f0-9]{8}$').hasMatch(id) ||
        result.containsKey(id) ||
        !hashes.add(hash))
      throw const FormatException('Conflicting Wii shared-content identity');
    result[id] = hash;
  }
  return result;
}

Uint8List writeWiiContentMap(Map<String, String> map) {
  if (map.length > 65536 ||
      map.values.toSet().length != map.length ||
      map.entries.any(
        (e) =>
            !RegExp(r'^[a-f0-9]{8}$').hasMatch(e.key) ||
            !RegExp(r'^[a-f0-9]{40}$').hasMatch(e.value),
      ))
    throw const FormatException('Invalid Wii shared-content identity');
  return Uint8List.fromList([
    for (final e in map.entries) ...[
      ...ascii.encode(e.key),
      for (var i = 0; i < 40; i += 2)
        int.parse(e.value.substring(i, i + 2), radix: 16),
    ],
  ]);
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
Uint8List _unhex(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);

/// Dolphin's shared map is a console index. Preserve its established IDs and
/// append new hashes; never copy an importer's freshly numbered map over it.
/// Empty historical index rows may remain after last-use file removal, just
/// like the native uninstaller; they contain no ticket, title or content.
class WiiSharedContent {
  WiiSharedContent(this.profile);
  final Directory profile;
  File get journal => File('${profile.path}/wii-shared-map-pending.json');
  Future<File> get target => addonFile(
    Directory('${profile.path}/user'),
    'Wii/shared1/content.map',
    createParents: true,
  );

  Future<String?> _current() async {
    final file = await target;
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    readWiiContentMap(bytes);
    return _hex(bytes);
  }

  Future<void> recover() async {
    if (!await addonExists(journal.path)) return;
    final j = await addonJson(journal);
    if (j['version'] != 1 ||
        j['after'] is! String ||
        j['before'] != null && j['before'] is! String)
      throw const FormatException('Invalid Wii map recovery');
    final next = _unhex(j['after'] as String);
    final after = readWiiContentMap(next),
        before = readWiiContentMap(
          j['before'] == null ? [] : _unhex(j['before'] as String),
        );
    if (before.keys.any((k) => after[k] != before[k]))
      throw const FormatException(
        'Wii map recovery would change a console identity',
      );
    final actual = await _current();
    if (actual != j['before'] && actual != j['after'])
      throw const FileSystemException(
        'The Wii shared map changed outside Broomm; recovery was kept',
      );
    if (actual != j['after']) {
      final file = await target, stage = await profile.createTemp('.wii-map-');
      try {
        final ready = File('${stage.path}/map');
        await ready.writeAsBytes(next, flush: true);
        if (_hex(await ready.readAsBytes()) != j['after'])
          throw const FileSystemException('Wii map readback failed');
        await ready.rename(file.path);
      } finally {
        await stage.delete(recursive: true);
      }
    }
    if (await _current() != j['after'])
      throw const FileSystemException('Wii map publication readback failed');
    await journal.delete();
  }

  Future<Map<String, dynamic>> materialize(
    Directory canonical,
    Directory output,
    Map<String, dynamic> units,
    Map<String, dynamic> shared,
  ) async {
    await recover();
    await copyAddonFiles(canonical, output, {
      for (final e in units.entries)
        e.key: (e.value['files'] as Map)[''] as String,
    });
    final before = await _current(),
        rows = readWiiContentMap(before == null ? [] : _unhex(before));
    var nextId = rows.isEmpty
        ? 0
        : (rows.keys
                  .map((k) => int.parse(k, radix: 16))
                  .reduce((a, b) => a > b ? a : b) +
              1);
    final result = Map<String, dynamic>.of(units);
    for (final e in shared.entries) {
      if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(e.key) ||
          e.value is! Map ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(e.value['hash'] as String))
        throw const FormatException('Invalid Wii shared payload');
      var id = rows.entries.where((r) => r.value == e.key).firstOrNull?.key;
      id ??= (nextId++).toRadixString(16).padLeft(8, '0');
      if (id.length != 8) throw const FormatException('Wii shared map is full');
      rows[id] = e.key;
      final path = 'Wii/shared1/$id.app',
          source = await addonFile(canonical, 'shared/${e.key}.app');
      final destination = await addonFile(output, path, createParents: true);
      await source.copy(destination.path);
      result[path] = {
        'version': 0,
        'files': {'': e.value['hash']},
      };
    }
    final after = _hex(writeWiiContentMap(rows));
    if (after != (before ?? '')) {
      await addonWrite(journal, {
        'version': 1,
        'before': before,
        'after': after,
      });
      await recover();
    }
    return result;
  }

  Future<void> preserveNativeReferences(String owner) async {
    await recover();
    final policy = PackageProfile(profile, 'wii');
    await policy.recover();
    final registry = await policy.ownership(), files = registry['files'] as Map;
    final before = await _current();
    if (before == null) return;
    final rows = readWiiContentMap(_unhex(before)), used = <String>{};
    final titles = Directory('${profile.path}/user/Wii/title');
    if (!await titles.exists()) return;
    var inspected = 0;
    await for (final entry in titles.list(
      recursive: true,
      followLinks: false,
    )) {
      if (++inspected > 100000)
        throw const FormatException('Wii reference scan exceeds limits');
      if (entry is! File && entry is! Directory)
        throw const FileSystemException('Linked Wii title storage was kept');
      if (entry is! File || !entry.path.endsWith('/content/title.tmd'))
        continue;
      final relative = entry.path.substring('${profile.path}/user/'.length);
      final record = files[relative] as Map?;
      File observed = entry;
      if (record != null &&
          (record['owners'] as List).length == 1 &&
          (record['owners'] as List).single == owner) {
        if (record['original'] == null) continue;
        observed = await addonFile(
          profile,
          '.wii-addon-originals/${record['original']}',
        );
      }
      if (await observed.length() > 4 * 1024 * 1024)
        throw const FormatException('Invalid Wii title metadata');
      used.addAll(wiiTmdSharedHashes(await observed.readAsBytes()));
    }
    for (final e in rows.entries) {
      if (used.contains(e.value))
        await policy.preserveShared('Wii/shared1/${e.key}.app');
    }
  }
}

Set<String> wiiTmdSharedHashes(Uint8List bytes) {
  if (bytes.length < 4)
    throw const FormatException('Truncated Wii title metadata');
  final d = ByteData.sublistView(bytes),
      body = switch (ByteData.sublistView(bytes).getUint32(0)) {
        0x10000 => 0x240,
        0x10001 => 0x140,
        0x10002 => 0x80,
        _ => throw const FormatException('Unrecognized Wii title signature'),
      };
  if (bytes.length < body + 0xa4)
    throw const FormatException('Truncated Wii title header');
  final count = d.getUint16(body + 0x9e);
  if (bytes.length < body + 0xa4 + count * 36)
    throw const FormatException('Truncated Wii content records');
  return {
    for (var i = 0; i < count; i++)
      if (d.getUint16(body + 0xa4 + i * 36 + 6) & 0x8000 != 0)
        _hex(
          bytes.sublist(body + 0xa4 + i * 36 + 16, body + 0xa4 + i * 36 + 36),
        ),
  };
}
