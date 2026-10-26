import 'dart:io';

String playStationGameDirectory(String id) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,96}$').hasMatch(id))
    throw const FormatException('Invalid PlayStation game identity');
  return 'games/$id';
}

bool isPs2Emulator(String name) => name == 'PCSX2' || name == 'ARMSX2';

/// Native whole-card formats only. Individual game exports (.psv/.psu/.gme)
/// need an explicit conversion rather than being written into a console card.
Future<bool> isPlayStationMemoryCard(File file, {required bool ps2}) async {
  final bytes = await file.length();
  if (ps2) {
    if (![8, 16, 32, 64].any((mb) => bytes == mb * 1024 * 1024 ~/ 512 * 528))
      return false;
    final header = await file
        .openRead(0, 28)
        .fold<List<int>>([], (a, b) => a..addAll(b));
    // A new card is blank until the game/BIOS formats it.
    return header.every((b) => b == 0xff) ||
        String.fromCharCodes(header).startsWith('Sony PS2 Memory Card Format ');
  }
  if (bytes != 128 * 1024) return false;
  final header = await file
      .openRead(0, 2)
      .fold<List<int>>([], (a, b) => a..addAll(b));
  return header.length == 2 && header[0] == 0x4d && header[1] == 0x43;
}
