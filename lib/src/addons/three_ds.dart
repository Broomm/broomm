import 'dart:io';
import 'dart:typed_data';

/// Only reads public container headers. Azahar remains responsible for CIA
/// validation/import; Broomm never decrypts, rewrites or executes package data.
class ThreeDsTitle {
  const ThreeDsTitle(this.id, this.version);
  final String id;
  final int version;
  String get kind => switch (id.substring(0, 8)) {
    '0004000e' => 'update',
    '0004008c' => 'dlc',
    _ => 'game',
  };
  bool belongsTo(String base) =>
      base.startsWith('00040000') && id.substring(8) == base.substring(8);
}

Future<ByteData> _read(RandomAccessFile f, int offset, int count) async {
  if (offset < 0 || count < 0 || offset + count > await f.length())
    throw const FormatException('Truncated 3DS container');
  await f.setPosition(offset);
  final bytes = await f.read(count);
  if (bytes.length != count)
    throw const FormatException('Incomplete 3DS container read');
  return ByteData.sublistView(bytes);
}

String _hex(int id) => id.toRadixString(16).padLeft(16, '0');

Future<String> readThreeDsGameId(String path) async {
  final f = await File(path).open();
  try {
    var h = await _read(f, 0, 0x200);
    if (h.getUint32(0x100) == 0x4e435344) {
      // NCSD
      final offset = h.getUint32(0x120, Endian.little) * 0x200;
      if (offset < 0x200 || h.getUint32(0x124, Endian.little) == 0)
        throw const FormatException('Missing main 3DS partition');
      h = await _read(f, offset, 0x200);
    }
    if (h.getUint32(0x100) != 0x4e434348)
      throw const FormatException('Expected an unpacked NCSD/NCCH 3DS game');
    final id = _hex(h.getUint64(0x118, Endian.little));
    if (!id.startsWith('00040000'))
      throw const FormatException('This is not a 3DS application title');
    return id;
  } finally {
    await f.close();
  }
}

Future<ThreeDsTitle> readCiaTitle(String path) async {
  final f = await File(path).open();
  try {
    final h = await _read(f, 0, 0x20);
    final header = h.getUint32(0, Endian.little);
    final cert = h.getUint32(8, Endian.little);
    final ticket = h.getUint32(12, Endian.little);
    final tmdSize = h.getUint32(16, Endian.little);
    int align(int n) => (n + 63) & ~63;
    if (header != 0x2020 ||
        cert > 1024 * 1024 ||
        ticket > 1024 * 1024 ||
        tmdSize > 4 * 1024 * 1024)
      throw const FormatException('Expected an uncompressed CIA package');
    final offset = align(header) + align(cert) + align(ticket);
    final tmd = await _read(f, offset, tmdSize);
    final body = switch (tmd.getUint32(0)) {
      0x10000 || 0x10003 => 0x240,
      0x10001 || 0x10004 => 0x140,
      0x10002 || 0x10005 => 0x80,
      _ => throw const FormatException('Unsupported CIA signature type'),
    };
    if (tmdSize < body + 0x9c4)
      throw const FormatException('Incomplete CIA title metadata');
    final count = tmd.getUint16(body + 0x9e);
    if (count == 0 || tmdSize < body + 0x9c4 + count * 0x30)
      throw const FormatException('Incomplete CIA content table');
    final id = _hex(tmd.getUint64(body + 0x4c));
    if (!id.startsWith('0004000e') && !id.startsWith('0004008c'))
      throw const FormatException(
        'Only 3DS update and DLC titles can be installed here',
      );
    return ThreeDsTitle(id, tmd.getUint16(body + 0x9c));
  } finally {
    await f.close();
  }
}
