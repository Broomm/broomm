import 'dart:convert';
import 'dart:typed_data';

/// Shared PARAM.SFO string table used by the Sony console adapters.
Map<String, String> parseSonySfo(Uint8List b, {String label = 'PS3'}) {
  if (b.length < 20) throw FormatException('Truncated $label metadata');
  final d = ByteData.sublistView(b);
  if (d.getUint32(0) != 0x00505346)
    throw FormatException('Invalid $label metadata');
  final k = d.getUint32(8, Endian.little),
      v = d.getUint32(12, Endian.little),
      count = d.getUint32(16, Endian.little);
  if (count > 1024 ||
      20 + count * 16 > b.length ||
      k < 20 + count * 16 ||
      k >= v ||
      v > b.length)
    throw FormatException('Invalid $label metadata table');
  final result = <String, String>{};
  for (var i = 0; i < count; i++) {
    final p = 20 + 16 * i, key = k + d.getUint16(20 + 16 * i, Endian.little);
    if (key >= v || key >= b.length)
      throw FormatException('Invalid $label metadata key');
    final end = b.indexOf(0, key),
        value = v + d.getUint32(p + 12, Endian.little),
        length = d.getUint32(p + 4, Endian.little);
    if (key < k ||
        end < key ||
        end >= v ||
        value < v ||
        value + length > b.length)
      throw FormatException('Invalid $label metadata offsets');
    if (d.getUint16(p + 2, Endian.little) == 0x204)
      result[utf8.decode(b.sublist(key, end))] = utf8
          .decode(b.sublist(value, value + length))
          .replaceAll('\x00', '');
  }
  return result;
}
