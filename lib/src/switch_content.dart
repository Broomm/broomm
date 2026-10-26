import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'macos_aes.dart';

/// Nintendo XTS data units use a big-endian sector IV, then standard XTS
/// little-endian polynomial tweaks. AES itself is supplied by the OS adapter.
Uint8List switchXtsSector(
  Uint8List bytes,
  Uint8List key,
  int sector, {
  bool decrypt = true,
}) {
  if (bytes.length != 512 || key.length != 32 || sector < 0)
    throw const FormatException('Invalid Switch header sector');
  final iv = Uint8List(16);
  ByteData.sublistView(iv).setUint64(8, sector);
  final tweak = macosAesEcb(iv, Uint8List.sublistView(key, 16), decrypt: false),
      tweaks = Uint8List(512),
      input = Uint8List(512);
  for (var at = 0; at < 512; at += 16) {
    for (var i = 0; i < 16; i++) {
      tweaks[at + i] = tweak[i];
      input[at + i] = bytes[at + i] ^ tweak[i];
    }
    var carry = 0;
    for (var i = 0; i < 16; i++) {
      final n = tweak[i];
      tweak[i] = ((n << 1) & 255) | carry;
      carry = n >> 7;
    }
    if (carry != 0) tweak[0] ^= 0x87;
  }
  final output = macosAesEcb(
    input,
    Uint8List.sublistView(key, 0, 16),
    decrypt: decrypt,
  );
  for (var i = 0; i < 512; i++) output[i] ^= tweaks[i];
  return output;
}

class SwitchArchiveEntry {
  const SwitchArchiveEntry(this.name, this.offset, this.bytes);
  final String name;
  final int offset, bytes;
}

class SwitchNcaHeader {
  const SwitchNcaHeader(this.title, this.type, this.bytes, this.rights);
  final String title;
  final int type, bytes;
  final String rights;
}

Future<Uint8List> switchRead(
  RandomAccessFile file,
  int size,
  int offset,
  int bytes,
) async {
  if (offset < 0 ||
      bytes < 0 ||
      offset + bytes > size ||
      bytes > 8 * 1024 * 1024)
    throw const FormatException('Invalid Switch archive range');
  await file.setPosition(offset);
  final b = await file.read(bytes);
  if (b.length != bytes)
    throw const FormatException('Truncated Switch archive');
  return b;
}

Future<List<SwitchArchiveEntry>> switchArchiveEntries(
  File source, {
  int offset = 0,
  int? length,
}) async {
  if (await FileSystemEntity.type(source.path, followLinks: false) !=
      FileSystemEntityType.file)
    throw const FormatException('Switch archive is missing or linked');
  final f = await source.open();
  try {
    final size = await f.length(), limit = length ?? size - offset;
    if (limit < 16 || offset < 0 || offset + limit > size)
      throw const FormatException('Invalid Switch archive size');
    final header = await switchRead(f, size, offset, 16),
        magic = ascii.decode(header.sublist(0, 4), allowInvalid: true),
        d = ByteData.sublistView(header),
        hfs = magic == 'HFS0';
    if (magic != 'PFS0' && !hfs)
      throw const FormatException(
        'Use an uncompressed Switch NSP/XCI. This package container is unsupported.',
      );
    final count = d.getUint32(4, Endian.little),
        strings = d.getUint32(8, Endian.little),
        stride = hfs ? 64 : 24,
        metadata = 16 + count * stride + strings;
    if (count < 1 ||
        count > 4096 ||
        strings > 4 * 1024 * 1024 ||
        metadata > 8 * 1024 * 1024 ||
        metadata > limit)
      throw const FormatException('Switch archive metadata exceeds its limits');
    final b = await switchRead(f, size, offset, metadata),
        bd = ByteData.sublistView(b),
        names = <String>{},
        ranges = <(int, int)>[],
        result = <SwitchArchiveEntry>[];
    for (var i = 0; i < count; i++) {
      final at = 16 + i * stride,
          start = bd.getUint64(at, Endian.little),
          bytes = bd.getUint64(at + 8, Endian.little),
          nameAt = bd.getUint32(at + 16, Endian.little),
          table = 16 + count * stride;
      if (nameAt >= strings ||
          start < 0 ||
          bytes < 1 ||
          start + bytes > limit - metadata)
        throw const FormatException('Invalid Switch archive entry');
      final end = b.indexOf(0, table + nameAt);
      if (end < table + nameAt || end >= metadata)
        throw const FormatException('Invalid Switch archive name');
      final name = utf8.decode(b.sublist(table + nameAt, end));
      if (name.isEmpty ||
          name.length > 255 ||
          name.contains(RegExp(r'[/\\\x00-\x1f]')) ||
          name == '.' ||
          name == '..' ||
          !names.add(name.toLowerCase()))
        throw const FormatException(
          'Unsafe or duplicated Switch archive entry',
        );
      ranges.add((start, start + bytes));
      result.add(SwitchArchiveEntry(name, offset + metadata + start, bytes));
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 1; i < ranges.length; i++)
      if (ranges[i].$1 < ranges[i - 1].$2)
        throw const FormatException('Overlapping Switch archive entries');
    return result;
  } finally {
    await f.close();
  }
}

Future<List<SwitchArchiveEntry>> switchGameEntries(File game) async {
  if (!game.path.toLowerCase().endsWith('.xci'))
    return switchArchiveEntries(game);
  final f = await game.open();
  late int root;
  try {
    final h = await switchRead(f, await f.length(), 0, 0x200);
    if (ascii.decode(h.sublist(0x100, 0x104), allowInvalid: true) != 'HEAD')
      throw const FormatException('Invalid Switch XCI header');
    root = ByteData.sublistView(h).getUint64(0x130, Endian.little);
  } finally {
    await f.close();
  }
  final partitions = await switchArchiveEntries(game, offset: root),
      secure = partitions.where((e) => e.name == 'secure').toList();
  if (secure.length != 1)
    throw const FormatException('Switch XCI has no unique secure partition');
  return switchArchiveEntries(
    game,
    offset: secure.single.offset,
    length: secure.single.bytes,
  );
}

Future<SwitchNcaHeader> switchNcaHeader(
  File archive,
  SwitchArchiveEntry entry,
  Uint8List key,
) async {
  if (entry.bytes < 0xc00) throw const FormatException('Truncated Switch NCA');
  final f = await archive.open();
  late Uint8List b;
  try {
    b = await switchRead(f, await f.length(), entry.offset + 0x200, 512);
  } finally {
    await f.close();
  }
  if (ascii.decode(b.sublist(0, 4), allowInvalid: true) != 'NCA3')
    b = switchXtsSector(b, key, 1);
  final d = ByteData.sublistView(b);
  if (ascii.decode(b.sublist(0, 4), allowInvalid: true) != 'NCA3' ||
      b[5] > 5 ||
      d.getUint64(8, Endian.little) != entry.bytes)
    throw const FormatException(
      'Switch NCA header cannot be verified with the configured prod.keys',
    );
  final id = d.getUint64(16, Endian.little).toRadixString(16).padLeft(16, '0');
  if (!RegExp(r'^010[0-9a-f]{13}$').hasMatch(id))
    throw const FormatException('Switch package is not game content');
  return SwitchNcaHeader(
    id,
    b[5],
    entry.bytes,
    b
        .sublist(0x30, 0x40)
        .map((n) => n.toRadixString(16).padLeft(2, '0'))
        .join(),
  );
}

Future<Uint8List> switchHeaderKey(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() > 2 * 1024 * 1024)
    throw const FormatException(
      'The private Switch keys are missing or invalid',
    );
  final values =
      RegExp(r'^\s*header_key\s*=\s*([0-9a-fA-F]{64})\s*$', multiLine: true)
          .allMatches(await file.readAsString())
          .map((m) => m[1]!.toLowerCase())
          .toSet();
  if (values.length != 1)
    throw const FormatException('prod.keys has no unambiguous header key');
  final text = values.single;
  return Uint8List.fromList([
    for (var i = 0; i < text.length; i += 2)
      int.parse(text.substring(i, i + 2), radix: 16),
  ]);
}

Future<String> switchBaseIdentity(File game, Uint8List key) async {
  final ids = <String>{};
  for (final e in await switchGameEntries(game)) {
    if (!e.name.toLowerCase().endsWith('.nca')) continue;
    final h = await switchNcaHeader(game, e, key);
    if (h.type == 0 && (int.parse(h.title, radix: 16) & 0x1fff) == 0)
      ids.add(h.title);
  }
  if (ids.length != 1)
    throw const FormatException(
      'Select a Switch base game with one unambiguous native program ID',
    );
  return ids.single;
}
