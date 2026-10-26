part of 'library.dart';

extension LibraryManagement on GameLibrary {
  Future<T> _artLocked<T>(Future<T> Function() work) async {
    final key = data.absolute.path,
        before = GameLibrary._artSerial[data.absolute.path];
    final done = Completer<void>();
    GameLibrary._artSerial[key] = done.future;
    try {
      await before;
      return await _locked(work, lockName: 'artwork.lock');
    } finally {
      done.complete();
      if (identical(GameLibrary._artSerial[key], done.future))
        unawaited(GameLibrary._artSerial.remove(key));
    }
  }

  Future<Directory> _artRoot(String server, int id) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(server) || id < 1)
      throw const FormatException('Invalid artwork identity');
    for (final p in [
      data.path,
      '${data.path}/home-artwork',
      '${data.path}/home-artwork/$server',
      '${data.path}/home-artwork/$server/$id',
    ])
      await _directory(Directory(p));
    return Directory('${data.path}/home-artwork/$server/$id');
  }

  Future<HomeArtwork?> artworkFor(String server, int id, {Directory? legacy}) =>
      _artLocked(() async {
        final chosen = await _readHomeArtwork(await _artRoot(server, id), id);
        return chosen ??
            (legacy == null ? null : await _readHomeArtwork(legacy, id));
      });
  Future<HomeArtwork?> saveArtwork(
    String server,
    int id, {
    ArtworkDownload? icon,
    ArtworkDownload? hero,
    ArtworkDownload? logo,
  }) => _artLocked(() async {
    final game = await _ownedGame(server, id);
    if (await FileSystemEntity.type(
          '${game.parent.path}/.deleting-$id.json',
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound)
      throw const RommFailure(
        'Finish deleting this game before changing artwork.',
      );
    HomeArtwork? inherited;
    try {
      inherited = await _readHomeArtwork(game, id);
    } catch (_) {
      /* Optional damaged artwork can be replaced explicitly. */
    }
    return _writeArtwork(
      await _artRoot(server, id),
      id,
      icon: icon,
      hero: hero,
      logo: logo,
      inherited: inherited,
    );
  });
  Future<HomeArtwork?> saveDownloadArtwork(
    String server,
    int id, {
    ArtworkDownload? icon,
    ArtworkDownload? hero,
    ArtworkDownload? logo,
  }) => _artLocked(() async {
    if (await FileSystemEntity.type(
          '${root.path}/$server/.deleting-$id.json',
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound)
      throw const RommFailure(
        'Finish deleting this game before selecting artwork.',
      );
    return _writeArtwork(
      await _artRoot(server, id),
      id,
      icon: icon,
      hero: hero,
      logo: logo,
    );
  });
  Future<void> discardDownloadArtwork(String server, int id) =>
      _artLocked(() async {
        final art = await _artRoot(server, id);
        // This private namespace stores only known immutable image choices. A
        // foreign file is kept and surfaced, never swept by a download cleanup.
        await for (final e in art.list(recursive: true, followLinks: false)) {
          final p = e.path
              .substring(art.path.length + 1)
              .replaceAll(Platform.pathSeparator, '/');
          if (e is Directory &&
              p != 'artwork' &&
              !RegExp(
                r'^artwork/(choice-[A-Za-z0-9_-]+|\.pending-[A-Za-z0-9_-]+)$',
              ).hasMatch(p))
            throw const FileSystemException(
              'Artwork cleanup found an unrelated directory; it was kept.',
            );
          if (e is Link ||
              (e is File &&
                  p != 'artwork.json' &&
                  !RegExp(r'^artwork-[A-Za-z0-9_-]+\.pending$').hasMatch(p) &&
                  !RegExp(
                    r'^artwork/(choice-[A-Za-z0-9_-]+|\.pending-[A-Za-z0-9_-]+)/(icon\.png|hero\.(png|jpg|webp)|logo\.(png|webp))$',
                  ).hasMatch(p)))
            throw const FileSystemException(
              'Artwork cleanup found unrelated files; existing data was kept.',
            );
        }
        await art.delete(recursive: true);
      });

  Future<HomeArtwork?> _writeArtwork(
    Directory game,
    int gameId, {
    ArtworkDownload? icon,
    ArtworkDownload? hero,
    ArtworkDownload? logo,
    HomeArtwork? inherited,
  }) async {
    HomeArtwork? previous;
    try {
      previous = await _readHomeArtwork(game, gameId);
    } catch (_) {
      /* Explicit selection can replace a damaged optional record. */
    }
    previous ??= inherited;
    if (icon == null && hero == null && logo == null) return previous;
    final root = Directory('${game.path}/artwork');
    await _directory(root);
    final stage = await root.createTemp('.pending-');
    Directory? published;
    File? pending;
    var committed = false;
    try {
      final records = <String, dynamic>{};
      for (final kind in ArtworkKind.values) {
        final selected = switch (kind) {
          ArtworkKind.icon => icon,
          ArtworkKind.hero => hero,
          ArtworkKind.logo => logo,
        };
        if (selected == null) {
          final existing = switch (kind) {
            ArtworkKind.icon => previous?.icon,
            ArtworkKind.hero => previous?.hero,
            ArtworkKind.logo => previous?.logo,
          };
          if (existing != null) {
            final file = File(existing);
            await _regularFile(file, maxBytes: 24 * 1024 * 1024);
            final name = '${kind.name}.${existing.split('.').last}';
            await file.copy('${stage.path}/$name');
            records[kind.name] = {
              'file': name,
              'author': switch (kind) {
                ArtworkKind.icon => previous?.iconCredit,
                ArtworkKind.hero => previous?.heroCredit,
                ArtworkKind.logo => previous?.logoCredit,
              },
            };
          }
          continue;
        }
        if (selected.art.kind != kind)
          throw const FormatException('Artwork kind mismatch');
        validateArtworkDownload(selected);
        final suffix = switch (selected.art.mime) {
          'image/png' => 'png',
          'image/jpeg' => 'jpg',
          'image/webp' => 'webp',
          _ => throw const FormatException('Invalid image format'),
        };
        final name = '${kind.name}.$suffix';
        final file = File('${stage.path}/$name');
        await file.create(exclusive: true);
        await file.writeAsBytes(selected.bytes, flush: true);
        if (await file.length() != selected.bytes.length)
          throw const FileSystemException('Artwork write was incomplete');
        records[kind.name] = {...selected.art.toJson(), 'file': name};
      }
      final choice =
          'choice-${stage.uri.pathSegments.where((s) => s.isNotEmpty).last.substring(9)}';
      if (await FileSystemEntity.type(
            '${root.path}/$choice',
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound)
        throw const FileSystemException(
          'Artwork destination already exists; previous files are kept',
        );
      published = await stage.rename('${root.path}/$choice');
      final encoded = jsonEncode({
        'version': 1,
        'gameId': gameId,
        'choice': choice,
        ...records,
      });
      final target = File('${game.path}/artwork.json');
      final type = await FileSystemEntity.type(target.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file)
        throw const FileSystemException('Invalid artwork record');
      pending = await File(
        '${game.path}/artwork-${choice.substring(7)}.pending',
      ).create(exclusive: true);
      await pending.writeAsString(encoded, flush: true);
      await pending.rename(target.path);
      committed = true;
      if (await target.readAsString() != encoded)
        throw const FileSystemException(
          'Artwork publication could not be verified',
        );
      // Each choice is immutable. The previous exact image files can now go;
      // preserve anything a user may have placed alongside them.
      final oldPath = previous?.icon ?? previous?.hero ?? previous?.logo;
      if (oldPath != null)
        try {
          final old = File(oldPath).parent;
          final contents = await old.list(followLinks: false).toList();
          if (contents.every(
            (f) =>
                f is File &&
                RegExp(r'^(icon\.png|logo\.(png|webp)|hero\.(png|jpg|webp))$')
                    .hasMatch(f.uri.pathSegments.last),
          ))
            await old.delete(recursive: true);
        } on FileSystemException {
          /* New artwork is committed; retain old files if cleanup is unavailable. */
        }
      return await _readHomeArtwork(game, gameId);
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
      if (!committed && published != null && await published.exists())
        await published.delete(recursive: true);
      if (pending != null && await pending.exists()) await pending.delete();
    }
  }

  Future<Directory> _ownedGame(
    String serverId,
    int id, {
    bool removing = false,
  }) async {
    if (id < 1) throw const FormatException('Invalid game identity');
    final parent = await _server(serverId);
    final game = Directory('${parent.path}/${removing ? '.deleting-' : ''}$id');
    await _directory(game, create: false);
    final marker = File('${parent.path}/.deleting-$id.json');
    final useMarker =
        removing &&
        await FileSystemEntity.type(marker.path, followLinks: false) !=
            FileSystemEntityType.notFound;
    final receipt = useMarker ? marker : File('${game.path}/receipt.json');
    await _regularFile(receipt, maxBytes: 12 * 1024 * 1024 + 1024);
    final j = jsonDecode(await receipt.readAsString()) as Map;
    if (j['version'] != 1 ||
        j['serverId'] != serverId ||
        j['game'] is! Map ||
        (j['game'] as Map)['id'] != id ||
        (useMarker && j['deletion'] != true))
      throw const FormatException('Unrecognized installation ownership');
    return game;
  }

  Future<void> remove(
    String serverId,
    int gameId, {
    Future<void> Function()? uninstallAddons,
  }) async {
    if (gameId < 1) throw const FormatException('Invalid game identity');
    final lease = await SessionLease.acquire(data);
    try {
      await _locked(() async {
        final parent = await _server(serverId);
        final source = Directory('${parent.path}/$gameId');
        final trash = Directory('${parent.path}/.deleting-$gameId');
        final marker = File('${parent.path}/.deleting-$gameId.json');
        final sourceType = await FileSystemEntity.type(
          source.path,
          followLinks: false,
        );
        final trashType = await FileSystemEntity.type(
          trash.path,
          followLinks: false,
        );
        if (sourceType == FileSystemEntityType.notFound &&
            trashType == FileSystemEntityType.notFound) {
          if (await FileSystemEntity.type(marker.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
            await _readDeletionIntent(marker, serverId, gameId);
            await uninstallAddons?.call();
            await discardDownloadArtwork(serverId, gameId);
            await marker.delete();
          }
          return;
        }
        if (sourceType != FileSystemEntityType.notFound &&
            trashType != FileSystemEntityType.notFound)
          throw const FileSystemException(
            'Conflicting deletion folders; files have been kept',
          );
        final game = await _ownedGame(
          serverId,
          gameId,
          removing: sourceType == FileSystemEntityType.notFound,
        );
        for (final f in await game.list(followLinks: false).toList()) {
          final name = f.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (![
                'receipt.json',
                'content',
                'artwork',
                'artwork.json',
              ].contains(name) &&
              !RegExp(r'^artwork-[a-zA-Z0-9_-]+\.pending$').hasMatch(name))
            throw const FileSystemException(
              'The game folder contains unrelated files. Inspect it before deletion; all files are kept.',
            );
        }
        if (await FileSystemEntity.type(marker.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          final receipt = jsonDecode(
            await File('${game.path}/receipt.json').readAsString(),
          ) as Map;
          final encoded = jsonEncode({...receipt, 'deletion': true});
          if (encoded.length > 12 * 1024 * 1024 + 1024)
            throw const FormatException('Deletion record too large');
          final stage = await parent.createTemp('.delete-intent-');
          try {
            final record = File('${stage.path}/intent.json');
            await record.create(exclusive: true);
            await record.writeAsString(encoded, flush: true);
            if (await record.readAsString() != encoded)
              throw const FileSystemException(
                'Deletion intent verification failed',
              );
            if (await FileSystemEntity.type(marker.path, followLinks: false) !=
                FileSystemEntityType.notFound)
              throw const FileSystemException('Deletion intent already exists');
            await record.rename(marker.path);
            if (await marker.readAsString() != encoded)
              throw const FileSystemException(
                'Published deletion intent could not be verified',
              );
          } finally {
            await stage.delete(recursive: true);
          }
        } else {
          await _readDeletionIntent(marker, serverId, gameId);
        }
        await uninstallAddons?.call();
        // The identity checkpoint is outside recursive cleanup, even if its
        // inner receipt disappears before another file fails to be removed.
        if (sourceType != FileSystemEntityType.notFound)
          await source.rename(trash.path);
        await trash.delete(recursive: true);
        await discardDownloadArtwork(serverId, gameId);
        await marker.delete();
      });
    } finally {
      await lease.release();
    }
  }
}

Future<void> _readDeletionIntent(File marker, String server, int id) async {
  await _regularFile(marker, maxBytes: 12 * 1024 * 1024 + 1024);
  final j = jsonDecode(await marker.readAsString()) as Map;
  if (j['userId'] is! int ||
      j['files'] is! List ||
      j['version'] != 1 ||
      j['serverId'] != server ||
      j['deletion'] != true ||
      j['game'] is! Map ||
      (j['game'] as Map)['id'] != id)
    throw const FormatException(
      'Invalid deletion identity; existing files have been kept',
    );
}

void validateArtworkDownload(ArtworkDownload selected) {
  final b = selected.bytes, art = selected.art;
  if (b.length < 24 || b.length > 24 * 1024 * 1024)
    throw const FormatException('Invalid artwork size');
  final png = [137, 80, 78, 71, 13, 10, 26, 10];
  bool starts(List<int> prefix, [int offset = 0]) => List.generate(
    prefix.length,
    (i) => b[offset + i] == prefix[i],
  ).every((v) => v);
  if (art.mime == 'image/png') {
    if (!starts(png) || !starts([73, 72, 68, 82], 12))
      throw const FormatException('The selected artwork is not a PNG image');
    final d = ByteData.sublistView(b);
    if (d.getUint32(16) != art.width || d.getUint32(20) != art.height)
      throw const FormatException('Artwork dimensions changed');
  } else if (art.mime == 'image/jpeg') {
    if (!starts([255, 216, 255]))
      throw const FormatException('Invalid JPEG artwork');
  } else if (art.mime == 'image/webp') {
    if (!starts([82, 73, 70, 70]) || !starts([87, 69, 66, 80], 8))
      throw const FormatException('Invalid WebP artwork');
  } else {
    throw const FormatException('Unsupported artwork format');
  }
  if (art.width <= 0 ||
      art.height <= 0 ||
      art.width * art.height > 32 * 1024 * 1024 ||
      (art.kind == ArtworkKind.icon &&
          (art.width != art.height || art.mime != 'image/png')) ||
      (art.kind == ArtworkKind.logo &&
          !['image/png', 'image/webp'].contains(art.mime)))
    throw const FormatException('Artwork has unsupported dimensions or format');
}

Future<HomeArtwork?> _readHomeArtwork(Directory game, int id) async {
  final file = File('${game.path}/artwork.json');
  if (await FileSystemEntity.type(file.path, followLinks: false) ==
      FileSystemEntityType.notFound)
    return null;
  await _regularFile(file, maxBytes: 65536);
  final j = jsonDecode(await file.readAsString()) as Map;
  final choice = j['choice'];
  if (j['version'] != 1 ||
      j['gameId'] != id ||
      choice is! String ||
      !RegExp(r'^choice-[a-zA-Z0-9_-]{1,80}$').hasMatch(choice))
    throw const FormatException('Invalid artwork record');
  final root = Directory('${game.path}/artwork');
  await _directory(root, create: false);
  final dir = Directory('${root.path}/$choice');
  await _directory(dir, create: false);
  Future<String?> image(String kind) async {
    final entry = j[kind];
    if (entry == null) return null;
    if (entry is! Map ||
        entry['file'] is! String ||
        !RegExp(switch (kind) {
          'icon' => r'^icon\.png$',
          'logo' => r'^logo\.(png|webp)$',
          _ => r'^hero\.(png|jpg|webp)$',
        }).hasMatch(entry['file'] as String))
      throw const FormatException('Invalid artwork path');
    final image = File('${dir.path}/${entry['file']}');
    await _regularFile(image, maxBytes: 24 * 1024 * 1024);
    return image.path;
  }

  return HomeArtwork(
    icon: await image('icon'),
    hero: await image('hero'),
    logo: await image('logo'),
    iconCredit: (j['icon'] as Map?)?['author'] as String?,
    heroCredit: (j['hero'] as Map?)?['author'] as String?,
    logoCredit: (j['logo'] as Map?)?['author'] as String?,
  );
}
