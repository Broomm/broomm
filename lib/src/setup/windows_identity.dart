import 'dart:io';
import 'dart:typed_data';

Future<void> verifyWindowsPe(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file)
    throw const FormatException('The Windows executable is missing or linked.');
  final handle = await file.open();
  try {
    final dos = await handle.read(64);
    if (dos.length != 64 || dos[0] != 77 || dos[1] != 90)
      throw const FormatException('Expected a Windows executable.');
    final offset = ByteData.sublistView(dos).getUint32(60, Endian.little);
    if (offset < 64 ||
        offset > 1024 * 1024 ||
        offset + 26 > await handle.length())
      throw const FormatException('Invalid Windows executable header.');
    await handle.setPosition(offset);
    final pe = await handle.read(26);
    final header = ByteData.sublistView(pe);
    if (pe.length != 26 ||
        header.getUint32(0, Endian.little) != 0x4550 ||
        header.getUint16(4, Endian.little) != 0x8664 ||
        header.getUint16(24, Endian.little) != 0x20b)
      throw const FormatException(
        'Cemu requires the reviewed Windows x64 executable.',
      );
  } finally {
    await handle.close();
  }
}
