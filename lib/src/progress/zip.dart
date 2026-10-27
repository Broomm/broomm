import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'digest.dart';
import 'files.dart';

class ProgressZipEntry {
  const ProgressZipEntry(
    this.name,
    this.offset,
    this.compressed,
    this.bytes,
    this.crc,
    this.method,
    this.flags, {
    this.symbolicLink = false,
  });
  final String name;
  final int offset, compressed, bytes, crc, method, flags;
  final bool symbolicLink;
}

class ProgressZip {
  ProgressZip._(this.file, this.entries);
  final File file;
  final List<ProgressZipEntry> entries;

  static Future<ProgressZip> read(
    File file, {
    int maxBytes = progressMaxBytes,
    int maxEntryBytes = progressMaxFileBytes,
    bool inspectLinks = false,
  }) async {
    if (maxBytes < 1 ||
        maxBytes > 2 * 1024 * 1024 * 1024 ||
        maxEntryBytes < 1 ||
        maxEntryBytes > maxBytes) {
      throw const FormatException('Invalid ZIP resource limits');
    }
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > maxBytes)
      throw const FormatException('Save archive is missing or exceeds 512 MiB');
    final input = await file.open();
    try {
      final length = await input.length();
      final tailStart = (length - 65557).clamp(0, length);
      final tail = await _read(input, tailStart, length - tailStart);
      var end = -1;
      for (var i = tail.lengthInBytes - 22; i >= 0; i--) {
        if (tail.getUint32(i, Endian.little) == 0x06054b50 &&
            i + 22 + tail.getUint16(i + 20, Endian.little) ==
                tail.lengthInBytes) {
          end = i;
          break;
        }
      }
      if (end < 0)
        throw const FormatException('Expected a complete ZIP save archive');
      final count = tail.getUint16(end + 10, Endian.little),
          size = tail.getUint32(end + 12, Endian.little),
          start = tail.getUint32(end + 16, Endian.little);
      if (tail.getUint16(end + 4, Endian.little) != 0 ||
          tail.getUint16(end + 6, Endian.little) != 0 ||
          tail.getUint16(end + 8, Endian.little) != count ||
          count > progressMaxFiles ||
          start + size != tailStart + end ||
          size > 4 * 1024 * 1024)
        throw const FormatException(
          'Split, ZIP64 or oversized save archives are not supported',
        );
      final cd = await _read(input, start, size);
      var pos = 0, total = 0;
      final entries = <ProgressZipEntry>[],
          seen = <String>{},
          directories = <String>{};
      final ranges = <(int, int)>[];
      for (var i = 0; i < count; i++) {
        if (pos + 46 > size || cd.getUint32(pos, Endian.little) != 0x02014b50)
          throw const FormatException('Damaged ZIP directory');
        final flags = cd.getUint16(pos + 8, Endian.little),
            method = cd.getUint16(pos + 10, Endian.little),
            crc = cd.getUint32(pos + 16, Endian.little);
        final compressed = cd.getUint32(pos + 20, Endian.little),
            bytes = cd.getUint32(pos + 24, Endian.little);
        final names = cd.getUint16(pos + 28, Endian.little),
            extra = cd.getUint16(pos + 30, Endian.little),
            comment = cd.getUint16(pos + 32, Endian.little);
        final attributes = cd.getUint32(pos + 38, Endian.little),
            offset = cd.getUint32(pos + 42, Endian.little);
        final unixType = (attributes >>> 16) & 0xf000;
        if (pos + 46 + names + extra + comment > size ||
            names == 0 ||
            names > 2048 ||
            (flags & ~0x080e) != 0 ||
            (method != 0 && method != 8) ||
            unixType != 0 &&
                unixType != 0x8000 &&
                unixType != 0x4000 &&
                !(inspectLinks && unixType == 0xa000) ||
            compressed > maxBytes ||
            bytes > maxEntryBytes ||
            cd.getUint16(pos + 34, Endian.little) != 0)
          throw const FormatException(
            'Unsupported, encrypted, linked or oversized ZIP entry',
          );
        final encoded = cd.buffer.asUint8List(
          cd.offsetInBytes + pos + 46,
          names,
        );
        if (flags & 0x800 == 0 && encoded.any((b) => b > 127))
          throw const FormatException('Save ZIP filenames must use UTF-8');
        final name = utf8.decode(encoded);
        final directory = name.endsWith('/');
        final relative = directory ? name.substring(0, name.length - 1) : name;
        progressRelative(relative);
        if (!seen.add(relative.toLowerCase()))
          throw const FormatException('Colliding save ZIP paths');
        for (var n = 1; n < relative.split('/').length; n++) {
          directories.add(relative.split('/').take(n).join('/').toLowerCase());
        }
        final local = await _read(input, offset, 30);
        if (local.getUint32(0, Endian.little) != 0x04034b50 ||
            local.getUint16(6, Endian.little) != flags ||
            local.getUint16(8, Endian.little) != method)
          throw const FormatException('ZIP headers disagree');
        final localNames = local.getUint16(26, Endian.little),
            localExtra = local.getUint16(28, Endian.little);
        final localName = await _read(input, offset + 30, localNames);
        if (utf8.decode(
              localName.buffer.asUint8List(localName.offsetInBytes, localNames),
            ) !=
            name)
          throw const FormatException('ZIP entry identity changed');
        final data = offset + 30 + localNames + localExtra;
        var limit = data + compressed;
        if (flags & 8 != 0) {
          final descriptor = await _read(input, limit, 16);
          if (descriptor.getUint32(0, Endian.little) != 0x08074b50 ||
              descriptor.getUint32(4, Endian.little) != crc ||
              descriptor.getUint32(8, Endian.little) != compressed ||
              descriptor.getUint32(12, Endian.little) != bytes)
            throw const FormatException('ZIP data descriptor is invalid');
          limit += 16;
        } else if (local.getUint32(14, Endian.little) != crc ||
            local.getUint32(18, Endian.little) != compressed ||
            local.getUint32(22, Endian.little) != bytes) {
          throw const FormatException('ZIP entry size or checksum changed');
        }
        if (limit > start ||
            (method == 0 && compressed != bytes) ||
            (directory && bytes != 0))
          throw const FormatException('Invalid ZIP payload range');
        ranges.add((offset, limit));
        if (!directory) {
          total += bytes;
          if (total > maxBytes)
            throw const FormatException('Expanded save exceeds 512 MiB');
          entries.add(
            ProgressZipEntry(
              name,
              data,
              compressed,
              bytes,
              crc,
              method,
              flags,
              symbolicLink: unixType == 0xa000,
            ),
          );
        }
        pos += 46 + names + extra + comment;
      }
      final fileNames = entries.map((e) => e.name.toLowerCase()).toSet();
      if (pos != size || fileNames.intersection(directories).isNotEmpty)
        throw const FormatException('Save ZIP file/folder paths collide');
      ranges.sort((a, b) => a.$1.compareTo(b.$1));
      var previous = 0;
      for (final range in ranges) {
        if (range.$1 < previous || range.$1 < 0)
          throw const FormatException('Overlapping ZIP records');
        previous = range.$2;
      }
      return ProgressZip._(file, entries);
    } finally {
      await input.close();
    }
  }

  Future<Map<String, Map<String, dynamic>>> extract(
    Directory destination,
  ) async {
    if (entries.any((e) => e.symbolicLink))
      throw const FormatException(
        'Save extraction does not accept symbolic links',
      );
    await progressDirectory(destination);
    final result = <String, Map<String, dynamic>>{};
    for (final entry in entries) {
      final output = await progressFile(
        destination,
        entry.name,
        createParents: true,
      );
      await output.create(exclusive: true);
      final sink = await output.open(mode: FileMode.writeOnly);
      final crc = ProgressCrc(),
          sha = ProgressDigest.sha256(),
          md5 = ProgressDigest.md5();
      var size = 0;
      try {
        final input = file.openRead(
          entry.offset,
          entry.offset + entry.compressed,
        );
        final stream = entry.method == 8
            ? input.transform(ZLibDecoder(raw: true))
            : input;
        await for (final chunk in stream) {
          size += chunk.length;
          if (size > entry.bytes)
            throw const FormatException('ZIP expands beyond its declared size');
          crc.add(chunk);
          sha.add(chunk);
          md5.add(chunk);
          await sink.writeFrom(chunk);
        }
        if (size != entry.bytes || crc.value != entry.crc)
          throw const FormatException(
            'Save ZIP checksum or size verification failed',
          );
        await sink.flush();
      } finally {
        await sink.close();
      }
      result[entry.name] = {
        'bytes': size,
        'sha256': sha.finish(),
        'md5': md5.finish(),
      };
    }
    return result;
  }

  /// Read-only inspection for signed application bundles. Save extraction still
  /// rejects links even when a caller explicitly requests this metadata.
  Future<String> linkTarget(ProgressZipEntry entry) async {
    if (!entry.symbolicLink || entry.bytes > 2048)
      throw const FormatException('Invalid archive link');
    final input = file.openRead(entry.offset, entry.offset + entry.compressed);
    final stream = entry.method == 8
        ? input.transform(ZLibDecoder(raw: true))
        : input;
    final bytes = <int>[], crc = ProgressCrc();
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > entry.bytes)
        throw const FormatException('Archive link exceeds declared size');
      bytes.addAll(chunk);
      crc.add(chunk);
    }
    if (bytes.length != entry.bytes || crc.value != entry.crc)
      throw const FormatException('Invalid archive link checksum');
    return utf8.decode(bytes);
  }

  static Future<void> write(
    File destination,
    Directory contents,
    List<String> names,
  ) async {
    if (names.length > progressMaxFiles)
      throw const FormatException('Too many files in save snapshot');
    final seen = <String>{};
    for (final n in names) {
      progressRelative(n);
      if (!seen.add(n.toLowerCase()))
        throw const FormatException('Colliding save paths');
    }
    await destination.create(exclusive: true);
    final output = await destination.open(mode: FileMode.writeOnly);
    final central = BytesBuilder(copy: false);
    var total = 0;
    try {
      for (final name in names.toList()..sort()) {
        final file = await progressFile(contents, name);
        final bytes = await file.length();
        total += bytes;
        if (bytes > progressMaxFileBytes || total > progressMaxBytes)
          throw const FormatException('Save snapshot exceeds supported size');
        final encoded = utf8.encode(name), offset = await output.position();
        final header = ByteData(30);
        header.setUint32(0, 0x04034b50, Endian.little);
        header.setUint16(4, 20, Endian.little);
        header.setUint16(6, 0x808, Endian.little);
        header.setUint16(8, 8, Endian.little);
        header.setUint16(12, 33, Endian.little);
        header.setUint16(26, encoded.length, Endian.little);
        await output.writeFrom(header.buffer.asUint8List());
        await output.writeFrom(encoded);
        final dataStart = await output.position(), crc = ProgressCrc();
        var received = 0;
        final input = file.openRead().map((chunk) {
          received += chunk.length;
          crc.add(chunk);
          return chunk;
        });
        await for (final chunk in input.transform(ZLibEncoder(raw: true))) {
          await output.writeFrom(chunk);
        }
        if (received != bytes)
          throw const FileSystemException(
            'A snapshot file changed while packaging',
          );
        final size = await output.position() - dataStart;
        final descriptor = ByteData(16)
          ..setUint32(0, 0x08074b50, Endian.little)
          ..setUint32(4, crc.value, Endian.little)
          ..setUint32(8, size, Endian.little)
          ..setUint32(12, bytes, Endian.little);
        await output.writeFrom(descriptor.buffer.asUint8List());
        final cd = ByteData(46)
          ..setUint32(0, 0x02014b50, Endian.little)
          ..setUint16(4, 0x0314, Endian.little)
          ..setUint16(6, 20, Endian.little)
          ..setUint16(8, 0x808, Endian.little)
          ..setUint16(10, 8, Endian.little)
          ..setUint16(14, 33, Endian.little)
          ..setUint32(16, crc.value, Endian.little)
          ..setUint32(20, size, Endian.little)
          ..setUint32(24, bytes, Endian.little)
          ..setUint16(28, encoded.length, Endian.little)
          ..setUint32(38, 0x81800000, Endian.little)
          ..setUint32(42, offset, Endian.little);
        central.add(cd.buffer.asUint8List());
        central.add(encoded);
      }
      final start = await output.position(), directory = central.takeBytes();
      await output.writeFrom(directory);
      final end = ByteData(22)
        ..setUint32(0, 0x06054b50, Endian.little)
        ..setUint16(8, names.length, Endian.little)
        ..setUint16(10, names.length, Endian.little)
        ..setUint32(12, directory.length, Endian.little)
        ..setUint32(16, start, Endian.little);
      await output.writeFrom(end.buffer.asUint8List());
      await output.flush();
      if (await output.position() > progressMaxBytes)
        throw const FormatException('Save archive exceeds 512 MiB');
    } finally {
      await output.close();
    }
  }
}

Future<ByteData> _read(RandomAccessFile f, int offset, int count) async {
  if (offset < 0 || count < 0 || offset + count > await f.length())
    throw const FormatException('Truncated save archive');
  await f.setPosition(offset);
  final b = await f.read(count);
  if (b.length != count)
    throw const FormatException('Incomplete save archive read');
  return ByteData.sublistView(b);
}

String rommZipHash(Map<String, Map<String, dynamic>> entries) {
  final keys = entries.keys.toList()
    ..sort((a, b) {
      // Python sorts Unicode scalars, while Dart's default string comparison
      // sorts UTF-16 units. Match RomM for non-BMP filenames as well.
      final ar = a.runes.toList(), br = b.runes.toList();
      for (var i = 0; i < ar.length && i < br.length; i++) {
        final order = ar[i].compareTo(br[i]);
        if (order != 0) return order;
      }
      return ar.length.compareTo(br.length);
    });
  final digest = ProgressDigest.md5()
    ..add(utf8.encode(keys.map((k) => '$k:${entries[k]!['md5']}').join('\n')));
  return digest.finish();
}
