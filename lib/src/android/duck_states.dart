import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Observed beta-12126 state envelope. This validates correspondence without
/// decompressing native state data or opening any ROM. Layout facts are checked
/// against real native output; no upstream implementation is incorporated.
Future<void> validateAndroidDuckState(File file, String publication) async {
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(publication))
    throw const FormatException('Invalid PS1 state publication identity.');
  final size = await file.length();
  if (size < 224 || size > 256 * 1024 * 1024)
    throw const FormatException(
      'Incomplete DuckStation state. Progress was kept.',
    );
  final input = await file.open();
  try {
    final bytes = await input.read(224);
    if (bytes.length != 224)
      throw const FormatException('Truncated DuckStation state header.');
    final h = ByteData.sublistView(bytes);
    int number(int offset) => h.getUint32(offset, Endian.little);
    if (number(0) != 0x43435544 || number(4) != 97)
      throw const FormatException(
        'This PS1 state does not match the reviewed DuckStation state format.',
      );
    final regions = <({int offset, int length})>[];
    void region(int offset, int length) {
      if (length == 0) return;
      if (offset < 224 || length < 0 || offset > size || length > size - offset)
        throw const FormatException('PS1 state offsets are incomplete.');
      regions.add((offset: offset, length: length));
    }

    final mediaLength = number(168),
        mediaOffset = number(172),
        overrideLength = number(216),
        overrideOffset = number(220);
    if (mediaLength > 4096 ||
        overrideLength > 4096 ||
        mediaLength == 0 && overrideLength == 0)
      throw const FormatException('PS1 state has no bounded game document.');
    region(mediaOffset, mediaLength);
    region(overrideOffset, overrideLength);
    region(number(196), number(192));
    region(number(212), number(204));
    if (number(180) > 3 ||
        number(200) > 3 ||
        number(184) >= 32768 ||
        number(188) >= 32768 ||
        number(204) == 0 ||
        number(208) == 0 ||
        number(208) > 32 * 1024 * 1024)
      throw const FormatException('Invalid PS1 state payload bounds.');
    regions.sort((a, b) => a.offset.compareTo(b.offset));
    var end = 224;
    for (final r in regions) {
      if (r.offset < end)
        throw const FormatException('PS1 state resources overlap.');
      end = r.offset + r.length;
    }
    if (end != size)
      throw const FormatException('PS1 state publication is incomplete.');
    for (final r in [
      (offset: mediaOffset, length: mediaLength),
      (offset: overrideOffset, length: overrideLength),
    ]) {
      if (r.length == 0) continue;
      await input.setPosition(r.offset);
      final text = await input.read(r.length);
      if (text.length != r.length)
        throw const FormatException('Truncated PS1 media reference.');
      final path = utf8.decode(text),
          prefix =
              '/android_content/app.broomm.broomm.games.documents/document@$publication/';
      if (!path.startsWith(prefix) ||
          path.length == prefix.length ||
          path.runes.any((c) => c < 32 || c == 127))
        throw const FormatException(
          'PS1 state belongs to a different game publication. All copies were kept.',
        );
    }
    if (await file.length() != size)
      throw const FileSystemException('PS1 state changed during validation.');
  } finally {
    await input.close();
  }
}
