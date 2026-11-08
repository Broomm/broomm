import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../progress/digest.dart';
import '../progress/file_hash.dart';
import '../romm/transfer.dart';

const androidDuckStationDocumentVersion = '0.1-12693-gcc4a0d678';

/// DuckStation stores its media document in states. Its identity must survive
/// grant revocation and another device's local library/profile identifiers.
/// The session supervisor holds SessionLease; these files are immutable library
/// payloads. No save files, account data or credential storage are read here.
Future<String> androidDuckStationDocumentToken(
  Directory data,
  List<String> files,
  String selected, {
  DownloadCancellation? cancellation,
  void Function(String)? phase,
}) async {
  final prefix = '${data.absolute.path}/library/';
  if (files.isEmpty ||
      files.length > 10000 ||
      files.toSet().length != files.length ||
      !files.contains(selected) ||
      !selected.startsWith(prefix)) {
    throw const FormatException('Invalid DuckStation game manifest.');
  }
  final owned = RegExp(r'^[a-f0-9]{32}/[1-9][0-9]*/content/')
      .firstMatch(selected.substring(prefix.length));
  if (owned == null) {
    throw const FormatException('DuckStation game is outside the library.');
  }
  final content = '$prefix${owned[0]}';
  final entries = <String, File>{};
  final observations = <String, FileStat>{};
  var total = 0;
  Future<FileStat> inspect(String path) async {
    if (!path.startsWith(content)) {
      throw const FormatException(
        'DuckStation files belong to different games.',
      );
    }
    final relative = path.substring(content.length);
    final parts = relative.split('/');
    if (parts.length > 33 ||
        utf8.encode(relative).length > 4096 ||
        parts.any(
          (p) =>
              p.isEmpty ||
              p == '.' ||
              p == '..' ||
              RegExp(r'[\x00-\x1f\x7f\\]').hasMatch(p),
        )) {
      throw const FormatException('Invalid DuckStation document path.');
    }
    var directory = data.absolute;
    final parents = path.substring('${data.absolute.path}/'.length).split('/')
      ..removeLast();
    for (final part in ['', ...parents]) {
      if (part.isNotEmpty) directory = Directory('${directory.path}/$part');
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const FileSystemException('Game directory is missing or linked.');
      }
    }
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException('Game file is missing or linked.');
    }
    return File(path).stat();
  }

  final stop = DownloadCancellation();
  var timedOut = false;
  if (cancellation != null) {
    cancellation.check();
    unawaited(cancellation.whenCancelled.then((_) => stop.cancel()));
  }
  final deadline = Timer(const Duration(minutes: 5), () {
    timedOut = true;
    stop.cancel();
  });
  try {
    for (final path in files) {
      stop.check();
      final stat = await inspect(path);
      total += stat.size;
      if (stat.size < 0 ||
          total > 32 * 1024 * 1024 * 1024 ||
          (path == selected && stat.size == 0)) {
        throw const FormatException(
          'DuckStation game manifest exceeds its bounds.',
        );
      }
      final relative = path.substring(content.length);
      entries[relative] = File(path);
      observations[relative] = stat;
    }
    final names = entries.keys.toList()..sort();
    final manifest = <Object>[];
    final clock = Stopwatch()..start();
    var completed = 0, last = -1000;
    for (var index = 0; index < names.length; index++) {
      stop.check();
      final name = names[index], file = entries[name]!;
      phase?.call(
        'Checking DuckStation game file ${index + 1} of ${names.length}…',
      );
      final hash = await gameFileHash(
        file.path,
        cancellation: stop,
        progress: (bytes) {
          if (clock.elapsedMilliseconds - last < 1000) return;
          last = clock.elapsedMilliseconds;
          phase?.call(
            'Checking DuckStation game files: ${completed + bytes} of $total bytes.',
          );
        },
      );
      completed += observations[name]!.size;
      manifest.add([name, observations[name]!.size, hash]);
    }
    for (final name in names) {
      stop.check();
      final before = observations[name]!,
          after = await inspect(entries[name]!.path);
      if (before.size != after.size ||
          before.modified != after.modified ||
          before.changed != after.changed) {
        throw const FileSystemException(
          'Game files changed during document verification.',
        );
      }
    }
    stop.check();
    final digest = ProgressDigest.sha256()
      ..add(
        utf8.encode(jsonEncode(['broomm-duckstation-documents-v1', manifest])),
      );
    phase?.call(
      'DuckStation game files verified in ${clock.elapsedMilliseconds} ms.',
    );
    return digest.finish().substring(0, 32);
  } catch (_) {
    if (timedOut) {
      throw StateError(
        'Checking DuckStation game files timed out. Nothing was launched.',
      );
    }
    cancellation?.check();
    rethrow;
  } finally {
    deadline.cancel();
  }
}
