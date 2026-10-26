import 'dart:io';
import 'dart:typed_data';

Uint8List artworkPng(int width, int height) {
  final out = BytesBuilder();
  out.add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String name, List<int> data) {
    final size = ByteData(4)..setUint32(0, data.length);
    out.add(size.buffer.asUint8List());
    final payload = [...name.codeUnits, ...data];
    out.add(payload);
    var crc = 0xffffffff;
    for (final byte in payload) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
      }
    }
    final check = ByteData(4)..setUint32(0, (crc ^ 0xffffffff) & 0xffffffff);
    out.add(check.buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk('IHDR', header.buffer.asUint8List());
  final rows = BytesBuilder();
  for (var y = 0; y < height; y++) {
    rows.addByte(0);
    for (var x = 0; x < width; x++) {
      rows.add([30 + (x * 150 ~/ width), 65 + (y * 85 ~/ height), 140, 255]);
    }
  }
  chunk('IDAT', zlib.encode(rows.takeBytes()));
  chunk('IEND', []);
  return out.takeBytes();
}
