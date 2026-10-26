import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'sony_sfo.dart';

class _PspSectorSink extends ByteConversionSink {
  final data = BytesBuilder(copy: false);
  @override
  void add(List<int> chunk) {
    if (data.length + chunk.length > 2048)
      throw const FormatException('PSP CSO sector exceeds its declared size.');
    data.add(chunk);
  }

  @override
  void close() {}
}

Uint8List _inflateSector(List<int> bytes) {
  final result = _PspSectorSink(), decoder = ZLibDecoder(raw: true);
  final input = decoder.startChunkedConversion(result);
  input.add(bytes);
  input.close();
  return result.data.takeBytes();
}

/// Bounded native metadata reads; no decompression of the complete game.
/// CISO v1 uses independent raw-deflate sectors. ZSO/other codecs need their
/// own verified reader rather than being mistaken for an ordinary ISO.
Future<Map<String, String>> pspGameMetadata(String path) async {
  final file = File(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('The PSP game is missing or linked.');
  }
  final io = await file.open();
  try {
    final size = await io.length();
    Future<Uint8List> raw(int offset, int length) async {
      if (offset < 0 || length < 0 || offset + length > size)
        throw const FormatException('Truncated PSP game metadata.');
      await io.setPosition(offset);
      final result = await io.read(length);
      if (result.length != length)
        throw const FormatException('Truncated PSP game metadata.');
      return result;
    }

    final header = await raw(0, 40);
    Uint8List metadata;
    if (header[0] == 0 && ascii.decode(header.sublist(1, 4)) == 'PBP') {
      final d = ByteData.sublistView(header),
          start = d.getUint32(8, Endian.little),
          end = d.getUint32(12, Endian.little);
      if (start < 40 || end <= start || end - start > 1024 * 1024)
        throw const FormatException('Invalid PSP PBP metadata offsets.');
      metadata = await raw(start, end - start);
    } else {
      var volume = size, compressed = false, align = 0, blocks = 0;
      final d = ByteData.sublistView(header);
      final magic = ascii.decode(header.sublist(0, 4), allowInvalid: true);
      if (magic == 'CISO') {
        volume = d.getUint64(8, Endian.little);
        align = header[21];
        blocks = (volume + 2047) ~/ 2048;
        if (d.getUint32(4, Endian.little) != 24 ||
            d.getUint32(16, Endian.little) != 2048 ||
            header[20] != 1 ||
            align > 16 ||
            volume < 17 * 2048 ||
            volume > 8 * 1024 * 1024 * 1024 ||
            24 + (blocks + 1) * 4 > size)
          throw const FormatException(
            'Unsupported or truncated PSP CSO header.',
          );
        compressed = true;
      } else if (magic == 'ZISO' || path.toLowerCase().endsWith('.cso')) {
        throw const FormatException(
          'Use an ISO, PBP or CISO v1 PSP game. This compressed format is not supported yet.',
        );
      }
      final cache = <int, Uint8List>{};
      Future<Uint8List> sector(int n) async {
        if (n < 0 || n * 2048 >= volume)
          throw const FormatException('PSP metadata extends beyond its image.');
        if (!compressed) return raw(n * 2048, 2048);
        if (cache[n] case final saved?) return saved;
        final index = ByteData.sublistView(await raw(24 + n * 4, 8)),
            entry = index.getUint32(0, Endian.little),
            start = (entry & 0x7fffffff) << align,
            end = (index.getUint32(4, Endian.little) & 0x7fffffff) << align;
        if (start < 24 + (blocks + 1) * 4 ||
            end <= start ||
            end - start > 128 * 1024 ||
            end > size)
          throw const FormatException('Invalid PSP CSO sector range.');
        final bytes = await raw(
          start,
          entry & 0x80000000 != 0 ? 2048 : end - start,
        );
        final decoded = entry & 0x80000000 != 0 ? bytes : _inflateSector(bytes);
        if (decoded.length != 2048)
          throw const FormatException('Invalid PSP CSO sector length.');
        if (cache.length >= 64) cache.remove(cache.keys.first);
        return cache[n] = decoded;
      }

      Future<Uint8List> read(int offset, int length) async {
        if (offset < 0 ||
            length < 0 ||
            length > 1024 * 1024 ||
            offset + length > volume)
          throw const FormatException('Invalid PSP metadata range.');
        final out = BytesBuilder(copy: false);
        for (var at = offset; at < offset + length;) {
          final b = await sector(at ~/ 2048), pos = at % 2048;
          final count = (offset + length - at).clamp(0, 2048 - pos);
          out.add(b.sublist(pos, pos + count));
          at += count;
        }
        return out.takeBytes();
      }

      int number(Uint8List b, int at) {
        final d = ByteData.sublistView(b), a = d.getUint32(at, Endian.little);
        if (a != d.getUint32(at + 4, Endian.big))
          throw const FormatException('Inconsistent PSP ISO metadata.');
        return a;
      }

      ({int offset, int bytes, bool directory}) record(Uint8List b) {
        if (b.length < 34 ||
            b[0] != b.length ||
            33 + b[32] > b.length ||
            b[1] != 0 ||
            b[25] & 0x80 != 0)
          throw const FormatException('Unsupported PSP ISO directory entry.');
        final offset = number(b, 2) * 2048, bytes = number(b, 10);
        if (offset + bytes > volume)
          throw const FormatException('Truncated PSP ISO entry.');
        return (offset: offset, bytes: bytes, directory: b[25] & 2 != 0);
      }

      final pvd = await read(16 * 2048, 2048);
      if (pvd[0] != 1 ||
          ascii.decode(pvd.sublist(1, 6)) != 'CD001' ||
          pvd[6] != 1)
        throw const FormatException('No supported PSP ISO volume was found.');
      var current = record(pvd.sublist(156, 156 + pvd[156]));
      final seen = <int>{};
      for (final segment in ['PSP_GAME', 'PARAM.SFO']) {
        if (!current.directory ||
            current.bytes > 1024 * 1024 ||
            !seen.add(current.offset))
          throw const FormatException('Invalid PSP ISO directory.');
        final b = await read(current.offset, current.bytes);
        final matches = <({int offset, int bytes, bool directory})>[];
        for (var pos = 0; pos < b.length;) {
          final length = b[pos];
          if (length == 0) {
            pos = (pos ~/ 2048 + 1) * 2048;
            continue;
          }
          if (length < 34 ||
              pos + length > b.length ||
              pos % 2048 + length > 2048 ||
              33 + b[pos + 32] > length)
            throw const FormatException('Damaged PSP ISO directory.');
          final name = ascii
              .decode(
                b.sublist(pos + 33, pos + 33 + b[pos + 32]),
                allowInvalid: true,
              )
              .replaceFirst(RegExp(r';[0-9]+$'), '');
          if (name.toUpperCase() == segment)
            matches.add(record(b.sublist(pos, pos + length)));
          pos += length;
        }
        if (matches.length != 1)
          throw const FormatException(
            'PSP game has no unambiguous PSP_GAME/PARAM.SFO.',
          );
        current = matches.single;
      }
      if (current.directory)
        throw const FormatException('Invalid PSP metadata file.');
      metadata = await read(current.offset, current.bytes);
    }
    final sfo = parseSonySfo(metadata, label: 'PSP');
    if (!RegExp(r'^[A-Z]{4}[0-9]{5}$').hasMatch(sfo['DISC_ID'] ?? ''))
      throw const FormatException(
        'PSP cloud saves require a native DISC_ID. Homebrew without one needs a separate verified save identity.',
      );
    return sfo;
  } finally {
    await io.close();
  }
}
