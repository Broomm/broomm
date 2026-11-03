import 'dart:io';

import '../io_worker.dart';
import '../progress/digest.dart';

/// One worker for a whole application, rather than thousands of per-file
/// isolate handshakes on Flutter's UI event loop. This remains read-only.
Future<void> verifySetupBundle(Object? arguments, IoContext io) async {
  final args = arguments as List;
  final path = args[0] as String, expected = args[1] as Map;
  final name = args[2] as String, hashes = args[3] as bool;
  final root = Directory(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.directory)
    throw StateError('Choose an existing extracted application folder.');
  final base = await root.resolveSymbolicLinks();
  final files = (expected['files'] as Map).cast<String, String>();
  final expectedLinks = (expected['links'] as Map).cast<String, String>();
  final actual = <String>{}, links = <String>{};
  var count = 0, bytes = 0;
  await for (final entry in root.list(recursive: true, followLinks: false)) {
    io.cancellation.check();
    if (++count > 30000 || entry.path.contains(RegExp(r'[\x00\r\n]')))
      throw StateError('Source tree exceeds the supported structure.');
    final relative = entry.path.substring(path.length + 1);
    if (entry is File) {
      bytes += await entry.length();
      if (bytes > 8 * 1024 * 1024 * 1024)
        throw StateError('Source tree exceeds 8 GiB.');
      actual.add(relative);
    } else if (entry is Link) {
      final target = await entry.target();
      final resolved = await entry.resolveSymbolicLinks();
      if (File(target).isAbsolute || !resolved.startsWith('$base/'))
        throw StateError('A bundle link leaves the application folder.');
      if (expectedLinks[relative] != target)
        throw StateError('$name has an unexpected bundle link.');
      links.add(relative);
    } else if (entry is! Directory) {
      throw StateError('Unsupported source file type.');
    }
  }
  if (links.length != expectedLinks.length ||
      !links.containsAll(expectedLinks.keys) ||
      actual.length != files.length ||
      !actual.containsAll(files.keys))
    throw StateError('$name does not match the reviewed application bundle.');
  if (!hashes) return;
  var checked = 0;
  for (final entry in files.entries) {
    io.cancellation.check();
    final digest = ProgressDigest.sha256();
    await for (final chunk in File('$path/${entry.key}').openRead()) {
      io.cancellation.check();
      digest.add(chunk);
    }
    if (digest.finish() != entry.value)
      throw StateError(
        '$name files changed or are not the reviewed build. Existing settings have been kept.',
      );
    checked++;
    io.progress(checked / files.length, force: checked == files.length);
  }
}
