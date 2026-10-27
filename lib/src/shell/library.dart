import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../romm/client.dart';
import '../romm/models.dart';
import '../romm/transfer.dart';
import '../steamgrid.dart';
import '../session_lease.dart';

part 'library_management.dart';

class InstalledGame {
  const InstalledGame(
    this.game,
    this.directory,
    this.userId, {
    this.problem,
    this.artwork,
    this.removing = false,
  });
  final RommGame game;
  final Directory directory;
  final int userId;
  final String? problem;
  final HomeArtwork? artwork;
  final bool removing;
}

class LibrarySnapshot {
  const LibrarySnapshot(this.games, this.problem);
  final List<InstalledGame> games;
  final String? problem;
}

class DownloadProgress {
  const DownloadProgress(this.game, this.phase, this.received, this.total);
  final RommGame game;
  final String phase;
  final int received, total;
}

/// Shared immutable payloads, scoped by stable saved-server ID and RomM ID.
/// Receipts live with their files so publication is a single directory rename.
class GameLibrary {
  GameLibrary(this.data);
  final Directory data;
  Directory get root => Directory('${data.path}/library');
  static final _held = <String>{};
  static final _artSerial = <String, Future<void>>{};
  static final _metadataSerial = <String, Future<void>>{};

  /// Identity of this published installation and selected media, without reading
  /// ROM contents. A redownload/replacement receives a new installation identity.
  Future<String> installationIdentity(
    InstalledGame entry,
    String selected,
  ) async {
    final receipt = File('${entry.directory.path}/receipt.json');
    await _regularFile(receipt, maxBytes: 12 * 1024 * 1024);
    final j = jsonDecode(await receipt.readAsString()) as Map;
    final prefix = '${entry.directory.path}/content/';
    if (j['version'] != 1 ||
        j['serverId'] is! String ||
        j['game'] is! Map ||
        j['game']['id'] != entry.game.id ||
        j['completedAt'] is! String ||
        !selected.startsWith(prefix))
      throw StateError(
        'The selected game installation identity changed. Reload the library.',
      );
    final relative = selected.substring(prefix.length);
    final matches = (j['files'] as List)
        .cast<Map>()
        .where((f) => f['path'] == relative)
        .toList();
    if (matches.length != 1)
      throw StateError(
        'The selected media does not belong to this game installation.',
      );
    final file = await _payload(
      Directory('${entry.directory.path}/content'),
      relative,
      create: false,
    );
    await _regularFile(file);
    if (await file.length() != matches.single['bytes'])
      throw StateError(
        'The selected game file is incomplete. Existing files were kept.',
      );
    return jsonEncode({
      'server': j['serverId'],
      'rom': entry.game.id,
      'installed': j['completedAt'],
      'file': relative,
      'bytes': matches.single['bytes'],
    });
  }

  Future<List<String>> contentFiles(
    InstalledGame entry, {
    bool excludeAddons = false,
  }) async {
    if (await FileSystemEntity.type(
          '${entry.directory.parent.path}/.deleting-${entry.game.id}.json',
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound)
      throw StateError('Finish deleting this game before playing it.');
    if (entry.removing)
      throw StateError(
        'Finish deleting this game before downloading it again.',
      );
    final receipt = File('${entry.directory.path}/receipt.json');
    await _regularFile(receipt, maxBytes: 12 * 1024 * 1024);
    final j = jsonDecode(await receipt.readAsString()) as Map;
    if (j['version'] != 1 || (j['game'] as Map)['id'] != entry.game.id)
      throw StateError(
        'The game installation record changed. Reload the library.',
      );
    final files = (j['files'] as List).cast<Map>();
    _validatePaths(files.map((f) => f['path'] as String).toList());
    final result = <String>[];
    for (final f in files) {
      if (excludeAddons && {'update', 'dlc'}.contains(f['category'])) continue;
      final file = await _payload(
        Directory('${entry.directory.path}/content'),
        f['path'] as String,
        create: false,
      );
      await _regularFile(file);
      if (await file.length() != f['bytes'])
        throw StateError(
          'Downloaded game files are incomplete or changed. Existing data has been kept.',
        );
      result.add(file.path);
    }
    return result;
  }

  Future<T> _locked<T>(
    Future<T> Function() action, {
    String lockName = 'downloads.lock',
  }) {
    if (lockName != 'downloads.lock') return _effectLocked(action, lockName);
    final key = root.absolute.path;
    final before = _metadataSerial[key] ?? Future<void>.value();
    final work = before.then((_) => _effectLocked(action, lockName));
    final tail = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _metadataSerial[key] = tail;
    return work.whenComplete(() {
      if (identical(_metadataSerial[key], tail)) _metadataSerial.remove(key);
    });
  }

  Future<T> _effectLocked<T>(
    Future<T> Function() action,
    String lockName,
  ) async {
    if (!RegExp(r'^(downloads|artwork|game-[a-f0-9]{32}-[1-9][0-9]*)\.lock$')
        .hasMatch(lockName))
      throw const FormatException('Invalid game library lock identity');
    await data.create(recursive: true);
    await _directory(data);
    await _directory(root);
    final key = '${await root.resolveSymbolicLinks()}/$lockName';
    if (!_held.add(key))
      throw const RommFailure(
        'Another download is still finishing. Try again in a moment.',
      );
    RandomAccessFile? lock;
    try {
      final file = File('${root.path}/$lockName');
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file)
        throw const FileSystemException('Invalid download lock');
      lock = await file.open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.exclusive);
      } on FileSystemException {
        throw const RommFailure(
          'The game library is in use by another Broomm process. Try again after its download finishes.',
        );
      }
      return await action();
    } finally {
      await lock?.close();
      _held.remove(key);
    }
  }

  Future<Directory> _server(String id) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id))
      throw const FormatException('Invalid server identity');
    final dir = Directory('${root.path}/$id');
    await _directory(dir);
    return dir;
  }

  Future<LibrarySnapshot> load(String serverId) => _locked(() async {
    final directory = await _server(serverId);
    final games = <InstalledGame>[];
    String? problem;
    await for (final entry in directory.list(followLinks: false)) {
      final name = entry.uri.pathSegments.where((v) => v.isNotEmpty).last;
      final inTrash = RegExp(r'^\.deleting-\d+$').hasMatch(name);
      final intent = RegExp(r'^\.deleting-(\d+)\.json$').firstMatch(name);
      if (!RegExp(r'^\d+$').hasMatch(name) && !inTrash && intent == null)
        continue; // Uncommitted staging is never a Home entry.
      try {
        final identity =
            intent?.group(1) ?? (inTrash ? name.substring(10) : name);
        final marker = File('${directory.path}/.deleting-$identity.json');
        if (intent != null &&
            (await FileSystemEntity.type(
                      '${directory.path}/$identity',
                      followLinks: false,
                    ) !=
                    FileSystemEntityType.notFound ||
                await FileSystemEntity.type(
                      '${directory.path}/.deleting-$identity',
                      followLinks: false,
                    ) !=
                    FileSystemEntityType.notFound))
          continue;
        final gameDirectory = Directory(
          intent == null ? entry.path : '${directory.path}/.deleting-$identity',
        );
        if (intent == null) await _directory(gameDirectory, create: false);
        final hasIntent =
            await FileSystemEntity.type(marker.path, followLinks: false) !=
            FileSystemEntityType.notFound;
        final removing = inTrash || intent != null || hasIntent;
        final file = hasIntent ? marker : File('${entry.path}/receipt.json');
        await _regularFile(file, maxBytes: 12 * 1024 * 1024 + 1024);
        final j = jsonDecode(await file.readAsString()) as Map;
        if (j['version'] != 1 ||
            j['serverId'] != serverId ||
            j['game'] is! Map ||
            (hasIntent && j['deletion'] != true))
          throw const FormatException('Invalid receipt');
        final game = RommGame.fromJson(
          (j['game'] as Map).cast<String, dynamic>(),
        );
        if ('${game.id}' != identity || j['userId'] is! int)
          throw const FormatException('Mismatched game identity');
        final files = (j['files'] as List).cast<Map>();
        _validatePaths(files.map((f) => f['path'] as String).toList());
        String? damaged = removing
            ? 'Deletion is incomplete. Choose Delete again to finish cleanup.'
            : null;
        for (final f in removing ? <Map>[] : files) {
          try {
            final payload = await _payload(
              Directory('${entry.path}/content'),
              f['path'] as String,
              create: false,
            );
            await _regularFile(payload);
            if (await payload.length() != f['bytes'])
              throw const FileSystemException('File size changed');
          } catch (_) {
            damaged = 'Some downloaded files are missing or changed. Your remaining files have been kept.';
          }
        }
        HomeArtwork? artwork;
        if (!removing) {
          try {
            artwork = await artworkFor(
              serverId,
              game.id,
              legacy: Directory(entry.path),
            );
          } catch (_) {
            problem = 'Some chosen artwork could not be read. Games are kept; choose Select Artwork to replace it.';
          }
        }
        final conflict = games.indexWhere((g) => g.game.id == game.id);
        if (conflict >= 0) {
          problem = 'Conflicting local game folders were found. Inspect the library before deleting or playing them.';
          final previous = games[conflict];
          games[conflict] = InstalledGame(
            previous.game,
            previous.directory,
            previous.userId,
            problem: problem,
            removing: true,
          );
          continue;
        }
        games.add(
          InstalledGame(
            game,
            gameDirectory,
            j['userId'] as int,
            problem: damaged,
            artwork: artwork,
            removing: removing,
          ),
        );
      } catch (_) {
        problem = 'Some local game records could not be read. Existing files have been kept; check the library folder and retry.';
      }
    }
    games.sort(
      (a, b) => a.game.name.toLowerCase().compareTo(b.game.name.toLowerCase()),
    );
    return LibrarySnapshot(games, problem);
  });

  Future<InstalledGame> install({
    required String serverId,
    required int userId,
    required RommGame game,
    required RommClient client,
    required DownloadCancellation cancellation,
    required void Function(DownloadProgress) progress,
    bool verifyChecksum = true,
  }) => _locked(() async {
    cancellation.check();
    final paths = gameFilePaths(game);
    late Directory parent, destination;
    final staging = await _locked(() async {
      parent = await _server(serverId);
      destination = Directory('${parent.path}/${game.id}');
      if (await FileSystemEntity.type(
            '${parent.path}/.deleting-${game.id}.json',
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound)
        throw const RommFailure(
          'Finish deleting this game before downloading it again.',
        );
      if (await FileSystemEntity.type(
            '${parent.path}/.deleting-${game.id}',
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound)
        throw const RommFailure(
          'Finish deleting this game before downloading it again.',
        );
      if (await FileSystemEntity.type(destination.path, followLinks: false) !=
          FileSystemEntityType.notFound)
        throw const RommFailure(
          'A local installation already exists. It has been preserved; reload the library.',
        );
      // The per-game OS lock proves only this game's old stages are abandoned.
      await for (final entry in parent.list(followLinks: false)) {
        final name = entry.uri.pathSegments.where((v) => v.isNotEmpty).last;
        if (name.startsWith('.partial-${game.id}-') && entry is Directory)
          await entry.delete(recursive: true);
      }
      return parent.createTemp('.partial-${game.id}-');
    });
    var published = false;
    final total = game.files.fold<int>(0, (n, f) => n + f.bytes);
    var completed = 0;
    final receipts = <Map<String, dynamic>>[];
    try {
      final content = Directory('${staging.path}/content');
      await _directory(content);
      for (var i = 0; i < game.files.length; i++) {
        cancellation.check();
        final file = game.files[i];
        final payload = await _payload(content, paths[i], create: true);
        // The filesystem also gets a say: normalization/case aliases can
        // collide even when two manifest strings differ.
        await payload.create(exclusive: true);
        progress(
          DownloadProgress(
            game,
            'Downloading file ${i + 1} of ${game.files.length}',
            completed,
            total,
          ),
        );
        await client.downloadFile(
          file,
          payload,
          cancellation: cancellation,
          onProgress: (received) => progress(
            DownloadProgress(
              game,
              'Downloading file ${i + 1} of ${game.files.length}',
              completed + received,
              total,
            ),
          ),
        );
        cancellation.check();
        progress(
          DownloadProgress(
            game,
            '${verifyChecksum ? 'Verifying' : 'Checking transfer size for'} file ${i + 1} of ${game.files.length}',
            completed + file.bytes,
            total,
          ),
        );
        final verification = verifyChecksum
            ? await _workerCrc(payload.path, cancellation)
            : null;
        final checksum = verification?.$1;
        cancellation.check();
        if (await payload.length() != file.bytes ||
            (verification != null &&
                file.rawCrc &&
                !verification.$2 &&
                file.crc != null &&
                file.crc!.isNotEmpty &&
                checksum != file.crc!.toLowerCase().padLeft(8, '0'))) {
          throw const RommFailure(
            'Downloaded data did not match the RomM file manifest. Nothing was added to Home. Please retry.',
          );
        }
        completed += file.bytes;
        receipts.add({
          'path': paths[i],
          'bytes': file.bytes,
          if (file.category != null) 'category': file.category,
          'verification': verifyChecksum ? 'crc32' : 'transfer-size',
          if (checksum != null) 'crc32': checksum,
        });
      }
      cancellation.check();
      progress(DownloadProgress(game, 'Finishing download', total, total));
      final receipt = File('${staging.path}/receipt.json');
      final encoded = jsonEncode({
        'version': 1,
        'serverId': serverId,
        'userId': userId,
        'game': game.toJson(),
        'files': receipts,
        'completedAt': DateTime.now().toUtc().toIso8601String(),
      });
      if (utf8.encode(encoded).length > 12 * 1024 * 1024)
        throw const RommFailure(
          'The game installation record exceeds the supported size.',
        );
      await receipt.writeAsString(encoded, flush: true);
      if (await receipt.readAsString() != encoded)
        throw const FileSystemException('Receipt verification failed');
      cancellation.check();
      await _locked(() async {
        cancellation.check();
        if (await FileSystemEntity.type(destination.path, followLinks: false) !=
                FileSystemEntityType.notFound ||
            await FileSystemEntity.type(
                  '${parent.path}/.deleting-${game.id}.json',
                  followLinks: false,
                ) !=
                FileSystemEntityType.notFound)
          throw const RommFailure(
            'The game installation changed during download. Existing files were kept.',
          );
        await staging.rename(destination.path);
      });
      published = true;
      return InstalledGame(game, destination, userId);
    } finally {
      if (!published && await staging.exists())
        await staging.delete(recursive: true);
    }
  }, lockName: 'game-$serverId-${game.id}.lock');
}

/// Shared validation for initial downloads and later add-on reconciliation.
List<String> gameFilePaths(RommGame game) {
  if (game.id < 1 ||
      game.files.isEmpty ||
      game.files.length > 10000 ||
      game.fullPath.isEmpty)
    throw const RommFailure(
      'RomM did not provide a complete downloadable file manifest for this game. Refresh and retry.',
    );
  final paths = game.files.map((f) {
    if (f.fullPath.split('/').last != f.name ||
        f.id < 1 ||
        f.romId != game.id ||
        f.bytes < 0 ||
        f.bytes > 1024 * 1024 * 1024 * 1024 ||
        f.name.contains('/') ||
        f.name.contains('\\') ||
        f.name.contains('\u0000'))
      throw const RommFailure('RomM returned an invalid game file manifest.');
    if (f.fullPath == game.fullPath) return f.name;
    if (!f.fullPath.startsWith('${game.fullPath}/'))
      throw const RommFailure(
        'A game file falls outside its RomM game folder.',
      );
    return f.fullPath.substring(game.fullPath.length + 1);
  }).toList();
  _validatePaths(paths);
  if (game.files.map((f) => f.id).toSet().length != game.files.length)
    throw const RommFailure('RomM returned duplicate file identities.');
  return paths;
}

Future<void> _directory(Directory dir, {bool create = true}) async {
  var type = await FileSystemEntity.type(dir.path, followLinks: false);
  if (create && type == FileSystemEntityType.notFound) {
    await dir.create();
    type = await FileSystemEntity.type(dir.path, followLinks: false);
  }
  if (type != FileSystemEntityType.directory)
    throw const FileSystemException(
      'Library directory is missing, linked or invalid',
    );
}

Future<void> _regularFile(File file, {int? maxBytes}) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      (maxBytes != null && await file.length() > maxBytes))
    throw const FileSystemException('Invalid library file');
}

void _validatePaths(List<String> paths) {
  if (paths.isEmpty || paths.length > 10000)
    throw const RommFailure('The game has no supported file manifest.');
  final seen = <String>{};
  final directories = <String>{};
  for (final path in paths) {
    final parts = path.split('/');
    if (path.length > 2048 ||
        parts.length > 32 ||
        parts.any(
          (p) =>
              p.isEmpty ||
              p == '.' ||
              p == '..' ||
              utf8.encode(p).length > 240 ||
              p.endsWith('.') ||
              p.endsWith(' ') ||
              RegExp(r'[\x00-\x1f\x7f\\:*?"<>|]').hasMatch(p) ||
              RegExp(
                r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
                caseSensitive: false,
              ).hasMatch(p),
        ))
      throw const RommFailure(
        'A game file has an unsafe or unsupported local path. Nothing was installed.',
      );
    final key = path.toLowerCase();
    if (!seen.add(key))
      throw const RommFailure(
        'Game files have colliding local names. Nothing was installed.',
      );
    for (var i = 1; i < parts.length; i++) {
      directories.add(parts.take(i).join('/').toLowerCase());
    }
  }
  if (seen.intersection(directories).isNotEmpty)
    throw const RommFailure(
      'Game file and folder names collide. Nothing was installed.',
    );
}

Future<File> _payload(
  Directory content,
  String path, {
  required bool create,
}) async {
  await _directory(content, create: create);
  final parts = path.split('/');
  var parent = content;
  for (final part in parts.take(parts.length - 1)) {
    parent = Directory('${parent.path}/$part');
    await _directory(parent, create: create);
  }
  return File('${parent.path}/${parts.last}');
}

/// IEEE CRC-32, over raw bytes (also the standard ZIP/zlib CRC). Runs on a
/// worker isolate during installation, including the disk readback.
Future<String> rawCrc32(String path) async {
  final table = List<int>.generate(256, (n) {
    for (var i = 0; i < 8; i++) {
      n = (n & 1) != 0 ? 0xedb88320 ^ (n >>> 1) : n >>> 1;
    }
    return n;
  });
  var crc = 0xffffffff;
  await for (final chunk in File(path).openRead()) {
    for (final byte in chunk) {
      crc = table[(crc ^ byte) & 255] ^ (crc >>> 8);
    }
  }
  return ((crc ^ 0xffffffff) & 0xffffffff).toRadixString(16).padLeft(8, '0');
}

Future<String> cancellableCrc32(
  String path,
  DownloadCancellation cancellation,
) async => (await _workerCrc(path, cancellation)).$1;

Future<(String, bool)> _workerCrc(
  String path,
  DownloadCancellation cancellation,
) async {
  final port = ReceivePort();
  Isolate? worker;
  final result = Completer<Object>();
  port.listen((value) {
    if (result.isCompleted) return;
    if (value is List &&
        value.length == 2 &&
        value[0] is String &&
        value[1] is bool) {
      result.complete(value);
    } else {
      result.complete(
        const FileSystemException('Downloaded file could not be verified'),
      );
    }
  });
  try {
    worker = await Isolate.spawn(
      _crcWorker,
      (path, port.sendPort),
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    cancellation.check();
    cancellation.abort = () {
      worker?.kill(priority: Isolate.immediate);
      if (!result.isCompleted) result.complete(const DownloadCancelled());
    };
    final value = await result.future;
    if (value is List) return (value[0] as String, value[1] as bool);
    throw value;
  } finally {
    cancellation.abort = null;
    worker?.kill(priority: Isolate.immediate);
    port.close();
  }
}

void _crcWorker((String, SendPort) input) async {
  final file = await File(input.$1).open();
  late List<int> header;
  try {
    header = await file.read(512);
  } finally {
    await file.close();
  }
  bool signature(List<int> bytes, [int offset = 0]) =>
      header.length >= offset + bytes.length &&
      List.generate(
        bytes.length,
        (i) => header[offset + i] == bytes[i],
      ).every((v) => v);
  // RomM also identifies compressed formats by MIME, so the extension and
  // archive_members field alone cannot prove that its CRC covers raw bytes.
  final container =
      signature([0x50, 0x4b, 0x03, 0x04]) ||
      signature([0x50, 0x4b, 0x05, 0x06]) ||
      signature([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]) ||
      signature([0x1f, 0x8b]) ||
      signature([0x42, 0x5a, 0x68]) ||
      signature([0x52, 0x61, 0x72, 0x21]) ||
      signature([0xfd, 0x37, 0x7a, 0x58, 0x5a, 0]) ||
      signature([0x28, 0xb5, 0x2f, 0xfd]) ||
      signature([0x75, 0x73, 0x74, 0x61, 0x72], 257);
  input.$2.send([await rawCrc32(input.$1), container]);
}
