import 'dart:io';
import 'dart:isolate';

import '../progress/digest.dart';
import 'files.dart';

Future<Map<String, int>> addonStamp(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file)
    throw const FileSystemException('Native content is missing or linked');
  final s = await file.stat();
  return {
    'bytes': s.size,
    'modified': s.modified.microsecondsSinceEpoch,
    'changed': s.changed.microsecondsSinceEpoch,
    'mode': s.mode,
  };
}

bool sameAddonStamp(Object? a, Map b) =>
    a is Map &&
    a.length == b.length &&
    b.entries.every((e) => a[e.key] == e.value);

/// These are local, metadata-bound receipts for immutable installed content,
/// never saves. A changed/missing receipt triggers a fresh hash. Copy/rename
/// propagation uses the OS file operation and checks both source and destination.
class AddonVerification {
  AddonVerification(this.profile, this.engine);
  final Directory profile;
  final String engine;
  Map<String, dynamic>? _rows;
  File get record => File('${profile.path}/.$engine-content-verification.json');

  Future<Map<String, dynamic>> _load() async {
    if (_rows != null) return _rows!;
    if (!await addonExists(record.path)) return _rows = {};
    final j = await addonJson(record);
    if (j['version'] != 1 ||
        j['files'] is! Map ||
        (j['files'] as Map).length > 4096)
      throw const FormatException('Invalid native content verification record');
    return _rows = (j['files'] as Map).cast<String, dynamic>();
  }

  Future<void> remember(File file, String hash, {Object? expectedStamp}) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))
      throw const FormatException('Invalid native content fingerprint');
    final stamp = await addonStamp(file);
    if (expectedStamp != null && !sameAddonStamp(expectedStamp, stamp))
      throw const FileSystemException(
        'Native content changed during installation',
      );
    final rows = await _load();
    if (rows.length >= 4096) rows.remove(rows.keys.first);
    final old = rows[file.absolute.path];
    if (old is Map &&
        old['hash'] == hash &&
        sameAddonStamp(old['stamp'], stamp))
      return;
    rows[file.absolute.path] = {'hash': hash, 'stamp': stamp};
    await addonWrite(record, {'version': 1, 'files': rows});
  }

  Future<String?> fingerprint(String path) async {
    if (!await addonExists(path)) return null;
    final file = File(path), before = await addonStamp(File(path));
    final rows = await _load(), saved = rows[file.absolute.path];
    if (saved is Map &&
        saved['hash'] is String &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(saved['hash'] as String) &&
        sameAddonStamp(saved['stamp'], before))
      return saved['hash'] as String;
    final hash = await Isolate.run(() => progressFileHash(File(path)));
    await remember(file, hash, expectedStamp: before);
    return hash;
  }

  Future<void> copy(String source, String target, String hash) async {
    if (await fingerprint(source) != hash)
      throw const FileSystemException(
        'Native copy source changed; existing content was kept',
      );
    final before = await addonStamp(File(source));
    await File(target).create(exclusive: true);
    await File(source).copy(target);
    if (!sameAddonStamp(before, await addonStamp(File(source))) ||
        (await addonStamp(File(target)))['bytes'] != before['bytes'])
      throw const FileSystemException('Native content changed while copying');
    await remember(File(target), hash);
  }

  Future<void> rename(String source, String target, String hash) async {
    if (await fingerprint(source) != hash)
      throw const FileSystemException('Native publication source changed');
    final before = await addonStamp(File(source));
    await File(source).rename(target);
    final after = await addonStamp(File(target));
    if (['bytes', 'modified', 'mode'].any((k) => before[k] != after[k]))
      throw const FileSystemException(
        'Native content changed while publishing',
      );
    await remember(File(target), hash);
  }

  Future<void> relocated(String from, String to) async {
    final rows = await _load();
    for (final e in rows.entries.toList()) {
      if (!e.key.startsWith('$from/')) continue;
      final file = File('$to/${e.key.substring(from.length + 1)}'),
          value = e.value as Map;
      if (sameAddonStamp(value['stamp'], await addonStamp(file))) {
        rows[file.absolute.path] = value;
        rows.remove(e.key);
      }
    }
    await addonWrite(record, {'version': 1, 'files': rows});
  }
}
