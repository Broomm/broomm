import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// RPCS3 reads a matching sidecar itself. Validate without returning/logging
/// the key bytes or putting them in command arguments/environment values.
Future<String?> ps3DiscKey(File iso) async {
  final stem = iso.path.replaceFirst(RegExp(r'\.[^.]+$'), '');
  for (final suffix in ['dkey', 'key']) {
    final key = File('$stem.$suffix');
    final type = await FileSystemEntity.type(key.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (type != FileSystemEntityType.file || await key.length() > 64)
      throw const FormatException(
        'The PS3 disc key is not a supported regular file.',
      );
    final bytes = await key.readAsBytes();
    if (bytes.length != 16 &&
        !(bytes.length >= 32 &&
            bytes.length <= 34 &&
            RegExp(r'^[0-9a-fA-F]{32}(\r?\n)?$')
                .hasMatch(ascii.decode(bytes, allowInvalid: true))))
      throw const FormatException(
        'The PS3 disc key must contain 32 hexadecimal characters or 16 binary bytes. Rescan the matching sidecar in RomM.',
      );
    return key.path;
  }
  return null;
}

/// Read only the bounded metadata RPCS3 also uses; RPCS3 boots the ISO itself.
/// No disc extraction, shell command, mount, or write to the user's image.
Future<Uint8List> ps3DiscMetadata(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file)
    throw const FormatException('The PS3 disc image is not a regular file.');
  final input = await file.open();
  try {
    final length = await input.length();
    Future<Uint8List> read(int offset, int size) async {
      if (offset < 0 || size < 0 || offset + size > length)
        throw const FormatException('Truncated PS3 disc image.');
      await input.setPosition(offset);
      final b = await input.read(size);
      if (b.length != size)
        throw const FormatException('Truncated PS3 disc image.');
      return b;
    }

    var volume = length;
    int number(ByteData data, int at, int bytes) {
      final a = bytes == 4
          ? data.getUint32(at, Endian.little)
          : data.getUint16(at, Endian.little);
      final b = bytes == 4
          ? data.getUint32(at + bytes, Endian.big)
          : data.getUint16(at + bytes, Endian.big);
      if (a != b)
        throw const FormatException('Inconsistent PS3 disc metadata.');
      return a;
    }

    ({int offset, int bytes, bool directory, String name}) record(Uint8List b) {
      if (b.length < 34 ||
          b[0] != b.length ||
          33 + b[32] > b.length ||
          b[1] != 0 ||
          b[26] != 0 ||
          b[27] != 0 ||
          b[25] & 0x80 != 0)
        throw const FormatException('Unsupported PS3 disc directory record.');
      final d = ByteData.sublistView(b),
          offset = number(ByteData.sublistView(b), 2, 4) * 2048,
          bytes = number(ByteData.sublistView(b), 10, 4);
      if (number(d, 28, 2) != 1 || offset < 0 || offset + bytes > volume)
        throw const FormatException('PS3 disc entry extends beyond its image.');
      final name = ascii
          .decode(b.sublist(33, 33 + b[32]))
          .replaceFirst(RegExp(r';[0-9]+$'), '');
      return (
        offset: offset,
        bytes: bytes,
        directory: b[25] & 2 != 0,
        name: name,
      );
    }

    Uint8List? pvd;
    for (var sector = 16; sector < 80; sector++) {
      final b = await read(sector * 2048, 2048);
      if (ascii.decode(b.sublist(1, 6), allowInvalid: true) != 'CD001' ||
          b[6] != 1)
        throw const FormatException(
          'RPCS3 needs a supported ISO 9660 PS3 disc image.',
        );
      if (b[0] == 1) {
        pvd = b;
        break;
      }
      if (b[0] == 255) break;
    }
    if (pvd == null)
      throw const FormatException('No PS3 ISO volume metadata was found.');
    final descriptor = ByteData.sublistView(pvd);
    if (number(descriptor, 128, 2) != 2048)
      throw const FormatException('Unsupported PS3 ISO sector size.');
    volume = number(descriptor, 80, 4) * 2048;
    if (volume > length || volume < 17 * 2048)
      throw const FormatException('The PS3 disc image is incomplete.');
    final root = record(pvd.sublist(156, 156 + pvd[156]));
    Future<({int offset, int bytes, bool directory, String name})> find(
      List<String> path,
    ) async {
      var current = root;
      final seen = <int>{};
      for (final segment in path) {
        if (!current.directory ||
            current.bytes > 16 * 1024 * 1024 ||
            !seen.add(current.offset))
          throw const FormatException('Invalid PS3 disc directory.');
        final data = await read(current.offset, current.bytes);
        final matches =
            <({int offset, int bytes, bool directory, String name})>[];
        for (var pos = 0; pos < data.length;) {
          final size = data[pos];
          if (size == 0) {
            pos = (pos ~/ 2048 + 1) * 2048;
            continue;
          }
          if (size < 34 || pos + size > data.length || pos % 2048 + size > 2048)
            throw const FormatException('Damaged PS3 disc directory.');
          if (33 + data[pos + 32] > size)
            throw const FormatException('Damaged PS3 disc filename.');
          // ISO's self/parent records have binary names, never path segments.
          if (!(data[pos + 32] == 1 && data[pos + 33] <= 1)) {
            final name = ascii
                .decode(data.sublist(pos + 33, pos + 33 + data[pos + 32]))
                .replaceFirst(RegExp(r';[0-9]+$'), '');
            // Large game data such as GT6's GT.VOL legitimately has multiple
            // extents. We never read/extract those files. Apply the stricter
            // single-extent checks only to the requested metadata/boot path.
            if (name.toUpperCase() == segment)
              matches.add(record(data.sublist(pos, pos + size)));
          }
          pos += size;
        }
        if (matches.length != 1)
          throw FormatException(
            'PS3 disc is missing an unambiguous ${path.join('/')}.',
          );
        current = matches.single;
      }
      return current;
    }

    final boot = await find(['PS3_GAME', 'USRDIR', 'EBOOT.BIN']);
    if (boot.directory || boot.bytes == 0)
      throw const FormatException('The PS3 disc has no boot executable.');
    final sfo = await find(['PS3_GAME', 'PARAM.SFO']);
    if (sfo.directory || sfo.bytes > 1024 * 1024)
      throw const FormatException('Invalid PS3 title metadata.');
    return await read(sfo.offset, sfo.bytes);
  } finally {
    await input.close();
  }
}
