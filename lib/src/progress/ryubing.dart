import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../managed_emulators.dart' show sha256File;
import '../session.dart' show ResolvedSession;
import 'files.dart';
import 'layout.dart';

class SwitchNeedsInitialization extends UnsupportedError {
  SwitchNeedsInitialization(this.hash)
    : super(
        'Launch this Switch game once to initialize and identify its private save storage.',
      );
  final String hash;
}

/// Bind a native Loader Start observation to the actual launched ROM bytes.
/// Titles, filenames, enumeration order and a different game's newest folder
/// never select a Switch save. No console/save index is written by Broomm.
Future<void> recordRyubingGame(
  ResolvedSession session,
  String program,
  String expectedHash,
) async {
  if (!RegExp(r'^010[0-9a-f]{13}$').hasMatch(program))
    throw const FormatException('Invalid native Switch program identity');
  if (await sha256File(session.rom) != expectedHash)
    throw const FormatException('The Switch ROM changed during initialization');
  final root = Directory(session.emulator.root);
  final file = await progressFile(
    root,
    'progress-identities/$expectedHash.json',
    createParents: true,
  );
  await progressWrite(file, {
    'version': 1,
    'romSha256': expectedHash,
    'program': program,
    'emulator': session.executableHash,
  });
}

Future<ProgressLayout> ryubingProgressLayout(
  ResolvedSession session,
  String user,
) async {
  final root = Directory(session.emulator.root),
      hash = await sha256File(session.rom);
  final file = File('${root.path}/progress-identities/$hash.json');
  if (!await progressExists(file.path)) throw SwitchNeedsInitialization(hash);
  final j = await progressJson(file);
  if (j['version'] != 1 ||
      j['romSha256'] != hash ||
      j['emulator'] != session.executableHash ||
      j['program'] is! String ||
      !RegExp(r'^010[0-9a-f]{13}$').hasMatch(j['program'] as String))
    throw const FormatException(
      'Switch native game identity is incomplete or belongs to another build. Existing progress was kept.',
    );
  final binding = await _binding(root, user, j['program'] as String);
  if (binding.isEmpty)
    throw const FormatException(
      'The initialized Switch save index no longer contains this game. Existing cloud and local progress were kept.',
    );
  return _RyubingLayout(root.path, user, j['program'] as String, binding);
}

class _RyubingLayout extends ProgressLayout {
  _RyubingLayout(String root, this.user, String program, this.bindings)
    : super(
        root,
        'ryubing-directory-v1',
        program,
        [
          for (final e in bindings.entries)
            ProgressArea(e.key, '$user/bis/user/save/${e.value.$1}/0'),
        ],
        note: 'Switch save states are not supported. Import a ZIP of the game’s save-directory contents. Console accounts, save indexes and other games are excluded.',
      );
  final String user;
  final Map<String, (String, String)>
  bindings; // logical area -> native ID, UID
  Future<void> _checkBinding() async {
    final current = await _binding(Directory(root), user, game);
    if (current.length != bindings.length ||
        bindings.keys.any((k) => current[k] != bindings[k]))
      throw const FormatException(
        'The active Switch user or save identity changed. Existing progress was kept.',
      );
  }

  @override
  Future<Map<String, File>> files() async {
    await _checkBinding();
    return super.files();
  }

  @override
  Future<File> target(String key) async {
    await _checkBinding();
    return super.target(key);
  }
}

Future<Map<String, (String, String)>> _binding(
  Directory root,
  String user,
  String program,
) async {
  final profiles = await progressJson(
    await progressFile(root, '$user/system/Profiles.json'),
  );
  final uid = profiles['last_opened'];
  if (uid is! String ||
      !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(uid) ||
      profiles['profiles'] is! List ||
      !(profiles['profiles'] as List).any(
        (p) => p is Map && p['user_id'] == uid,
      ))
    throw const FormatException(
      'The active private Switch account could not be verified',
    );
  final index = await progressFile(
    root,
    '$user/bis/system/save/8000000000000000/0/imkvdb.arc',
  );
  if (!await index.exists())
    throw const FormatException(
      'The private Switch save index is missing. Existing progress was kept.',
    );
  final b = await index.readAsBytes();
  if (b.length < 12 ||
      b.length > 4 * 1024 * 1024 ||
      ascii.decode(b.sublist(0, 4), allowInvalid: true) != 'IMKV')
    throw const FormatException('Unsupported Switch save index');
  final d = ByteData.sublistView(b),
      count = ByteData.sublistView(b).getUint32(8, Endian.little);
  if (d.getUint32(4, Endian.little) != 0 || count > 10000)
    throw const FormatException('Unsupported Switch save index version');
  var pos = 12;
  final result = <String, (String, String)>{};
  for (var i = 0; i < count; i++) {
    if (pos + 12 > b.length ||
        ascii.decode(b.sublist(pos, pos + 4), allowInvalid: true) != 'IMEN' ||
        d.getUint32(pos + 4, Endian.little) != 64 ||
        d.getUint32(pos + 8, Endian.little) != 64 ||
        pos + 140 > b.length)
      throw const FormatException('Invalid Switch save index entry');
    final key = pos + 12, value = key + 64;
    pos += 140;
    final title = d
        .getUint64(key, Endian.little)
        .toRadixString(16)
        .padLeft(16, '0');
    if (title != program) continue;
    final type = b[key + 0x20],
        rank = b[key + 0x21],
        slot = d.getUint16(key + 0x22, Endian.little);
    if (![1, 3].contains(type) || rank != 0 || slot != 0) continue;
    final owner =
        d.getUint64(key + 8, Endian.little).toRadixString(16).padLeft(16, '0') +
        d.getUint64(key + 16, Endian.little).toRadixString(16).padLeft(16, '0');
    if ((type == 1 && owner != uid.toLowerCase()) ||
        (type == 3 && owner != '0' * 32))
      continue;
    if (b[value + 0x18] != 1)
      throw const FormatException(
        'Switch game save is outside the user storage space',
      );
    final id = d
        .getUint64(value, Endian.little)
        .toRadixString(16)
        .padLeft(16, '0');
    if (id == '0' * 16) throw const FormatException('Invalid Switch save ID');
    final area = type == 1 ? 'save' : 'device';
    if (result.containsKey(area))
      throw const FormatException('Conflicting Switch save identities');
    for (final copy in [0, 1]) {
      final file = await progressFile(
        root,
        '$user/bis/user/save/$id/ExtraData$copy',
      );
      if (!await file.exists() || await file.length() != 512)
        throw const FormatException(
          'Switch save ownership metadata is missing',
        );
      final extra = await file
          .openRead(0, 64)
          .fold<List<int>>([], (a, b) => a..addAll(b));
      if (!List.generate(64, (p) => extra[p] == b[key + p]).every((v) => v))
        throw const FormatException(
          'Switch save metadata disagrees with its index',
        );
    }
    final native = await progressFile(root, '$user/bis/user/save/$id/0/.probe');
    if (!await native.parent.exists())
      throw const FormatException(
        'The committed Switch save directory is missing',
      );
    result[area] = (id, owner);
  }
  if (pos != b.length)
    throw const FormatException('Unexpected trailing Switch save index data');
  return result;
}
