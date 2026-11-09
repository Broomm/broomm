import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../progress/digest.dart';
import '../romm/transfer.dart';

const androidDuckStationDocumentVersion = '0.1-12693-gcc4a0d678';

/// DuckStation stores its media document in states. Its identity must survive
/// grant revocation and another device's local library/profile identifiers.
/// Use the installed publication record, never a launch-time ROM checksum.
/// This establishes managed installation identity, not fresh payload integrity.
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
  final owned = RegExp(r'^([a-f0-9]{32})/([1-9][0-9]*)/content/')
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
  final deadline = Timer(const Duration(seconds: 30), () {
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
    final clock = Stopwatch()..start();
    phase?.call('Checking DuckStation’s installed game record…');
    stop.check();
    final record = File('${Directory(content).parent.path}/receipt.json');
    const limit = 12 * 1024 * 1024;
    if (await FileSystemEntity.type(record.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException(
        'Game installation record is missing or linked.',
      );
    }
    final beforeRecord = await record.stat();
    if (beforeRecord.size < 1 || beforeRecord.size > limit) {
      throw const FormatException('Invalid game installation record size.');
    }
    final text = await record
        .openRead(0, limit + 1)
        .transform(utf8.decoder)
        .join();
    stop.check();
    final publication = jsonDecode(text);
    if (publication is! Map ||
        publication['version'] != 1 ||
        publication['serverId'] != owned.group(1) ||
        publication['game'] is! Map ||
        publication['game']['id'].toString() != owned.group(2) ||
        publication['game']['id'] is! int ||
        publication['game']['platform_slug'] != 'psx' ||
        publication['game']['fs_name'] is! String ||
        (publication['game']['fs_name'] as String).isEmpty ||
        publication['game']['revision'] != null &&
            publication['game']['revision'] is! String ||
        publication['files'] is! List ||
        (publication['files'] as List).length != names.length) {
      throw const FormatException(
        'DuckStation game installation record changed. Reload the library.',
      );
    }
    final published = <String, int>{};
    for (final item in publication['files'] as List) {
      if (item is! Map ||
          item['path'] is! String ||
          item['bytes'] is! int ||
          published.containsKey(item['path']) ||
          !entries.containsKey(item['path']) ||
          observations[item['path']]!.size != item['bytes']) {
        throw const FormatException(
          'DuckStation files do not match their installation record.',
        );
      }
      published[item['path'] as String] = item['bytes'] as int;
    }
    final afterRecord = await record.stat();
    if (beforeRecord.size != afterRecord.size ||
        beforeRecord.modified != afterRecord.modified ||
        beforeRecord.changed != afterRecord.changed ||
        await FileSystemEntity.type(record.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw const FileSystemException(
        'Game installation record changed during inspection.',
      );
    }
    final manifest = [
      for (final name in names) [name, published[name]],
    ];
    for (final name in names) {
      stop.check();
      final before = observations[name]!,
          after = await inspect(entries[name]!.path);
      if (before.size != after.size ||
          before.modified != after.modified ||
          before.changed != after.changed) {
        throw const FileSystemException(
          'Game files changed during document inspection.',
        );
      }
    }
    stop.check();
    final digest = ProgressDigest.sha256()
      ..add(
        utf8.encode(
          jsonEncode([
            'broomm-duckstation-publication-v2',
            publication['game']['id'],
            publication['game']['platform_slug'],
            publication['game']['fs_name'],
            publication['game']['revision'],
            manifest,
          ]),
        ),
      );
    phase?.call(
      'DuckStation game record checked in ${clock.elapsedMilliseconds} ms.',
    );
    return digest.finish().substring(0, 32);
  } catch (_) {
    if (timedOut) {
      throw StateError(
        'Checking DuckStation game installation timed out. Nothing was launched.',
      );
    }
    cancellation?.check();
    rethrow;
  } finally {
    deadline.cancel();
  }
}
