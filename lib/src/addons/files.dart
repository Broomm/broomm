import 'dart:convert';
import 'dart:io';

import '../managed_emulators.dart'
    show runOwnedTool, ownedDirectory, sha256File;

Future<bool> addonExists(String path) async =>
    await FileSystemEntity.type(path, followLinks: false) !=
    FileSystemEntityType.notFound;

void addonRelative(String path) {
  if (path.isEmpty ||
      path.length > 2048 ||
      path
          .split('/')
          .any(
            (p) =>
                p.isEmpty ||
                p == '.' ||
                p == '..' ||
                RegExp(r'[\x00-\x1f\x7f\\:*?"<>|]').hasMatch(p),
          ))
    throw const FormatException('Invalid add-on path');
}

Future<String> addonPath(
  Directory root,
  String relative, {
  bool createParents = false,
}) async {
  addonRelative(relative);
  var parent = root;
  final parts = relative.split('/');
  for (final part in ['', ...parts.take(parts.length - 1)]) {
    if (part.isNotEmpty) parent = Directory('${parent.path}/$part');
    if (createParents) await ownedDirectory(parent);
    if (await FileSystemEntity.type(parent.path, followLinks: false) !=
        FileSystemEntityType.directory)
      throw const FileSystemException('Add-on storage is missing or linked');
  }
  return '${root.path}/$relative';
}

Future<File> addonFile(
  Directory root,
  String relative, {
  bool createParents = false,
}) async {
  final file = File(
    await addonPath(root, relative, createParents: createParents),
  );
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file)
    throw const FileSystemException('Add-on file is linked or invalid');
  return file;
}

Future<Map<String, dynamic>> addonJson(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() > 12 * 1024 * 1024)
    throw const FileSystemException('Invalid add-on installation record');
  return (jsonDecode(await file.readAsString()) as Map).cast<String, dynamic>();
}

Future<void> addonWrite(File target, Object value) async {
  final text = jsonEncode(value);
  if (utf8.encode(text).length > 12 * 1024 * 1024)
    throw const FormatException('Add-on installation record is too large');
  await addonFile(target.parent, target.uri.pathSegments.last);
  final stage = await target.parent.createTemp('.addon-record-');
  try {
    final file = File('${stage.path}/record');
    await file.writeAsString(text, flush: true);
    if (await file.readAsString() != text)
      throw const FileSystemException(
        'Add-on record write could not be verified',
      );
    await file.rename(target.path);
    if (await target.readAsString() != text)
      throw const FileSystemException(
        'Add-on record publication could not be verified',
      );
  } finally {
    await stage.delete(recursive: true);
  }
}

/// A bounded, exact file inventory. macOS batches its native checksum tool;
/// other hosts use the existing streaming Dart digest outside the UI isolate.
Future<Map<String, String>> addonInventory(Directory root) async {
  if (await FileSystemEntity.type(root.path, followLinks: false) !=
      FileSystemEntityType.directory)
    throw const FileSystemException('Invalid add-on content directory');
  final paths = <String>[];
  var bytes = 0;
  final depth = root.uri.pathSegments.where((s) => s.isNotEmpty).length;
  await for (final entry in root.list(recursive: true, followLinks: false)) {
    final rel = entry.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .skip(depth)
        .join('/');
    addonRelative(rel);
    if (entry is! File && entry is! Directory)
      throw const FileSystemException('Linked add-on content is not supported');
    if (entry is File) {
      paths.add(rel);
      bytes += await entry.length();
      if (paths.length > 100000 || bytes > 128 * 1024 * 1024 * 1024)
        throw const FileSystemException(
          'Add-on content exceeds supported limits',
        );
    }
  }
  paths.sort();
  final hashes = <String, String>{};
  if (!Platform.isMacOS) {
    for (final path in paths) {
      hashes[path] = await sha256File('${root.path}/$path');
    }
    return hashes;
  }
  for (var start = 0; start < paths.length; start += 64) {
    final batch = paths.skip(start).take(64).toList();
    final output = await runOwnedTool('/usr/bin/shasum', [
      '-a',
      '256',
      ...batch.map((s) => '${root.path}/$s'),
    ]);
    final lines = const LineSplitter().convert(output);
    if (lines.length != batch.length)
      throw const FileSystemException('Incomplete add-on verification');
    for (var i = 0; i < batch.length; i++) {
      final hash = lines[i].length >= 64 ? lines[i].substring(0, 64) : '';
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash))
        throw const FileSystemException('Invalid add-on fingerprint');
      hashes[batch[i]] = hash;
    }
  }
  return hashes;
}

bool sameAddonInventory(Map a, Map b) =>
    a.length == b.length && a.keys.every((k) => a[k] == b[k]);

Future<void> copyAddonFiles(
  Directory from,
  Directory to,
  Map<String, String> files,
) async {
  await ownedDirectory(to);
  for (final rel in files.keys) {
    final source = await addonFile(from, rel);
    final target = await addonFile(to, rel, createParents: true);
    if (await addonExists(target.path))
      throw const FileSystemException('Add-on copy destination exists');
    await source.copy(target.path);
  }
  if (!sameAddonInventory(await addonInventory(to), files))
    throw const FileSystemException('Copied add-on files failed verification');
}

String azaharUserPath(String profileRoot) =>
    '$profileRoot/home/Library/Application Support/Azahar';

String titleContentPath(String id) =>
    'sdmc/Nintendo 3DS/${'0' * 32}/${'0' * 32}/title/${id.substring(0, 8)}/${id.substring(8)}/content';

bool isAddonUnit(String path) =>
    RegExp(
      r'^sdmc/Nintendo 3DS/0{32}/0{32}/title/000400(0e|8c)/[0-9a-f]{8}/content$',
    ).hasMatch(path) ||
    RegExp(r'^nand/dbs/ticket\.db/000400(0E|8C)[0-9A-F]{8}\.[0-9A-F]{16}\.tik$')
        .hasMatch(path);
