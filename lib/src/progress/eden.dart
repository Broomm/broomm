import 'dart:io';
import 'dart:typed_data';

import '../session.dart' show ResolvedSession;
import '../romm/transfer.dart';
import 'files.dart';
import 'layout.dart';
import 'ryubing.dart' show SwitchNeedsInitialization, switchSourceIdentity;

Future<ProgressLayout> edenProgressLayout(
  ResolvedSession session,
  String user, {
  DownloadCancellation? cancellation,
}) async {
  final root = Directory(session.emulator.root),
      source = await switchSourceIdentity(session);
  cancellation?.check();
  final identity = File(
    '${root.path}/progress-identities/installed-${source.$1}.json',
  );
  if (!await progressExists(identity.path))
    throw SwitchNeedsInitialization(source.$1);
  final j = await progressJson(identity);
  if (j['version'] != 2 ||
      j['source'] != source.$2 ||
      j['emulator'] != session.executableHash ||
      j['program'] is! String ||
      !RegExp(r'^010[0-9a-f]{13}$').hasMatch(j['program'] as String)) {
    throw const FormatException(
      'Eden game identity changed. Existing progress was kept.',
    );
  }
  final program = j['program'] as String;
  final binding = await _account(root, user);
  final paths = <String, String>{};
  for (final kind in ['save', 'device']) {
    final future = kind == 'save'
        ? '$user/nand/user/save/account/${binding.$1}/${program.toUpperCase()}/0'
        : '$user/nand/user/save/device/${program.toUpperCase()}/0';
    final legacy =
        '$user/nand/user/save/0000000000000000/${kind == 'save' ? binding.$2 : '0' * 32}/${program.toUpperCase()}';
    paths[kind] = await _directoryExists(root, future) ? future : legacy;
  }
  return _EdenLayout(root.path, user, program, binding, paths);
}

Future<bool> _directoryExists(Directory root, String relative) async {
  progressRelative(relative);
  var directory = root;
  for (final part in ['', ...relative.split('/')]) {
    if (part.isNotEmpty) directory = Directory('${directory.path}/$part');
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return false;
    if (type != FileSystemEntityType.directory)
      throw const FileSystemException(
        'Eden save directory is linked or invalid',
      );
  }
  return true;
}

Future<(String, String)> _account(Directory root, String user) async {
  final file = await progressFile(
    root,
    '$user/nand/system/save/8000000000000010/su/avators/profiles.dat',
  );
  if (!await file.exists() || await file.length() != 0x650) {
    throw const FormatException(
      'The private Eden console account is missing or invalid. Existing saves were kept.',
    );
  }
  final b = await file.readAsBytes();
  for (var i = 0; i < 8; i++) {
    final at = 0x10 + 0xc8 * i, bytes = b.sublist(at, at + 16);
    if (bytes.every((n) => n == 0)) continue;
    if (!List.generate(16, (n) => b[at + 16 + n] == bytes[n]).every((v) => v)) {
      throw const FormatException(
        'Eden console account identity is inconsistent',
      );
    }
    final d = ByteData.sublistView(Uint8List.fromList(bytes));
    return (
      bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join(),
      d
              .getUint64(8, Endian.little)
              .toRadixString(16)
              .padLeft(16, '0')
              .toUpperCase() +
          d
              .getUint64(0, Endian.little)
              .toRadixString(16)
              .padLeft(16, '0')
              .toUpperCase(),
    );
  }
  throw const FormatException('The private Eden console has no account');
}

class _EdenLayout extends ProgressLayout {
  _EdenLayout(String root, this.user, String program, this.binding, this.paths)
    // Both Switch backends export the same logical save/device directory ZIP.
    // Keep the existing format ID so choosing a default does not fork progress.
    : super(
        root,
        'ryubing-directory-v1',
        program,
        [for (final e in paths.entries) ProgressArea(e.key, e.value)],
        note: 'Switch native save-directory ZIP, compatible with the Ryubing save/device areas. Console identities, firmware and installed content are excluded. Eden does not support save states.',
      );
  final String user;
  final (String, String) binding;
  final Map<String, String> paths;
  Future<void> _check() async {
    if (await _account(Directory(root), user) != binding)
      throw const FormatException(
        'The private Eden account changed. Existing saves were kept.',
      );
    for (final e in paths.entries) {
      if (!e.value.endsWith('/0')) {
        final future = e.key == 'save'
            ? '$user/nand/user/save/account/${binding.$1}/${game.toUpperCase()}/0'
            : '$user/nand/user/save/device/${game.toUpperCase()}/0';
        if (await _directoryExists(Directory(root), future))
          throw const FormatException(
            'Eden save storage moved. Reopen this game’s cloud save menu to refresh its boundary.',
          );
      }
    }
  }

  @override
  Future<Map<String, File>> files() async {
    await _check();
    return super.files();
  }

  @override
  Future<File> target(String key) async {
    await _check();
    return super.target(key);
  }
}
