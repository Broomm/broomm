import 'dart:convert';
import 'dart:io';
import 'dart:math';

const progressMaxBytes = 512 * 1024 * 1024;
const progressMaxFileBytes = 256 * 1024 * 1024;
const progressMaxFiles = 4096;

String progressNonce() => List<int>.generate(
  16,
  (_) => Random.secure().nextInt(256),
).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
Future<bool> progressExists(String path) async =>
    await FileSystemEntity.type(path, followLinks: false) !=
    FileSystemEntityType.notFound;
void progressRelative(String path) {
  if (path.isEmpty ||
      path.length > 2048 ||
      path.split('/').length > 32 ||
      path
          .split('/')
          .any(
            (p) =>
                p.isEmpty ||
                p == '.' ||
                p == '..' ||
                p.endsWith('.') ||
                p.endsWith(' ') ||
                utf8.encode(p).length > 200 ||
                RegExp(r'[\x00-\x1f\x7f\\:*?"<>|]').hasMatch(p) ||
                RegExp(
                  r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
                  caseSensitive: false,
                ).hasMatch(p),
          ))
    throw const FormatException(
      'Unsafe save path. Existing progress has been kept.',
    );
}

Future<void> progressDirectory(Directory dir) async {
  final type = await FileSystemEntity.type(dir.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    await progressDirectory(dir.parent);
    await dir.create();
  } else if (type != FileSystemEntityType.directory) {
    throw const FileSystemException(
      'Save storage is missing, linked or invalid',
    );
  }
}

Future<String> progressPath(
  Directory root,
  String relative, {
  bool createParents = false,
}) async {
  progressRelative(relative);
  var current = root;
  for (final part in [
    '',
    ...relative.split('/').take(relative.split('/').length - 1),
  ]) {
    if (part.isNotEmpty) current = Directory('${current.path}/$part');
    if (createParents) await progressDirectory(current);
    if (await FileSystemEntity.type(current.path, followLinks: false) !=
        FileSystemEntityType.directory)
      throw const FileSystemException('Save directory is missing or linked');
  }
  return '${root.path}/$relative';
}

Future<File> progressFile(
  Directory root,
  String path, {
  bool createParents = false,
}) async {
  final file = File(
    await progressPath(root, path, createParents: createParents),
  );
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file)
    throw const FileSystemException('A save file is linked or invalid');
  return file;
}

Future<Map<String, dynamic>> progressJson(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() > 4 * 1024 * 1024)
    throw const FileSystemException(
      'The save recovery record is missing or invalid',
    );
  return (jsonDecode(await file.readAsString()) as Map).cast<String, dynamic>();
}

Future<void> progressWrite(File target, Map value) async {
  final text = jsonEncode(value);
  if (utf8.encode(text).length > 4 * 1024 * 1024)
    throw const FormatException('Save record is too large');
  await progressFile(target.parent, target.uri.pathSegments.last);
  final stage = await target.parent.createTemp('.record-');
  try {
    final temp = File('${stage.path}/record');
    await temp.writeAsString(text, flush: true);
    if (await temp.readAsString() != text)
      throw const FileSystemException(
        'Save record write could not be verified',
      );
    await temp.rename(target.path);
    if (await target.readAsString() != text)
      throw const FileSystemException(
        'Save record publication could not be verified',
      );
  } finally {
    await stage.delete(recursive: true);
  }
}
