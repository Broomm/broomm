part of 'library.dart';

extension LibraryPlatformIcons on GameLibrary {
  Future<Uint8List?> platformIconFor(
    String server,
    String slug, {
    required Future<bool> Function(Uint8List) validatePng,
    RommClient? client,
  }) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(server) ||
        !RommClient.isPlatformIconSlug(slug)) {
      return null;
    }
    final cache = Directory('${data.path}/platform-icons');
    final folder = Directory('${cache.path}/$server');
    final file = File('${folder.path}/icon-$slug.png');
    Future<Uint8List?> readCached() async {
      try {
        for (final dir in [data, cache, folder]) {
          await _directory(dir, create: false);
        }
        await _regularFile(file, maxBytes: RommClient.platformIconByteLimit);
        final png = await file.readAsBytes();
        return await validatePng(png) ? png : null;
      } on FileSystemException {
        return null;
      }
    }

    final cached = await readCached();
    if (cached != null || client == null) return cached;
    final ico = await client.platformIcon(slug);
    final png = ico == null ? null : await _platformIconPng(ico, validatePng);
    if (png == null) return null;
    try {
      return await _artLocked(() async {
        final published = await readCached();
        if (published != null) return published;
        for (final dir in [data, cache, folder]) {
          await _directory(dir);
        }
        final type = await FileSystemEntity.type(file.path, followLinks: false);
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.file) {
          return png;
        }
        final stage = await folder.createTemp('.pending-');
        try {
          final pending = await File('${stage.path}/icon.png')
              .writeAsBytes(png, flush: true);
          await pending.rename(file.path);
        } finally {
          await stage.delete(recursive: true);
        }
        return png;
      });
    } on FileSystemException {
      // An unwritable cache must not prevent displaying optional artwork.
      return png;
    }
  }
}

// RomM's built-in ICOs carry PNG frames. Extract a bounded frame so Flutter
// uses its regular image pipeline on every host.
Future<Uint8List?> _platformIconPng(
  Uint8List ico,
  Future<bool> Function(Uint8List) validatePng,
) async {
  if (ico.length < 22 || ico.length > RommClient.platformIconByteLimit) {
    return null;
  }
  final header = ByteData.sublistView(ico);
  final count = header.getUint16(4, Endian.little);
  final end = 6 + 16 * count;
  if (header.getUint16(0, Endian.little) != 0 ||
      header.getUint16(2, Endian.little) != 1 ||
      count == 0 ||
      count > 32 ||
      end > ico.length) {
    return null;
  }
  final entries = <({int offset, int length, int area})>[];
  for (var entry = 6; entry < end; entry += 16) {
    final length = header.getUint32(entry + 8, Endian.little);
    final offset = header.getUint32(entry + 12, Endian.little);
    if (offset < end || offset + length > ico.length) continue;
    final width = ico[entry] == 0 ? 256 : ico[entry];
    final height = ico[entry + 1] == 0 ? 256 : ico[entry + 1];
    entries.add((offset: offset, length: length, area: width * height));
  }
  entries.sort((a, b) => b.area.compareTo(a.area));
  for (final entry in entries) {
    final png = Uint8List.sublistView(
      ico,
      entry.offset,
      entry.offset + entry.length,
    );
    if (await validatePng(png)) return png;
  }
  return null;
}
