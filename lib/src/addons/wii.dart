import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Read only signed-metadata structure here; Dolphin validates/decrypts the
/// native contents. System/IOS WADs cannot enter the game-package workflow.
class WiiWad {
  const WiiWad(
    this.title,
    this.version,
    this.contents,
    this.sharedHashes,
    this.regularContents,
  );
  final String title;
  final int version, contents;
  final Set<String> sharedHashes;
  final int regularContents;
  bool get shared => sharedHashes.isNotEmpty;
  String get type => title.substring(0, 8);
}

Future<WiiWad> readWiiWad(String path) async {
  final f = await File(path).open();
  try {
    final length = await f.length();
    final header = await f.read(0x20);
    if (header.length != 0x20) throw const FormatException('Truncated Wii WAD');
    final d = ByteData.sublistView(header);
    int align(int v) => (v + 63) & ~63;
    final hs = d.getUint32(0),
        cert = d.getUint32(8),
        crl = d.getUint32(12),
        ticket = d.getUint32(16),
        size = d.getUint32(20);
    final offset = align(hs) + align(cert) + align(crl) + align(ticket);
    if (hs != 0x20 ||
        !{0x4973, 0x6962}.contains(d.getUint16(4)) ||
        ticket < 0x2a4 ||
        size < 0x140 + 0xa4 ||
        size > 4 * 1024 * 1024 ||
        offset + size > length) {
      throw const FormatException('Invalid Wii WAD structure');
    }
    await f.setPosition(offset);
    final bytes = await f.read(size), tmd = ByteData.sublistView(bytes);
    final sig = switch (tmd.getUint32(0)) {
      0x10000 => 0x240,
      0x10001 => 0x140,
      0x10002 => 0x80,
      _ => throw const FormatException('Unsupported Wii TMD signature'),
    };
    if (size < sig + 0xa4) throw const FormatException('Truncated Wii TMD');
    final id = tmd.getUint64(sig + 0x4c).toRadixString(16).padLeft(16, '0');
    final count = tmd.getUint16(sig + 0x9e);
    if (!{'00010001', '00010005'}.contains(id.substring(0, 8)) ||
        count < 1 ||
        sig + 0xa4 + count * 36 > size) {
      throw const FormatException(
        'Only Wii game/DLC titles are accepted; system WADs are excluded',
      );
    }
    final shared = <String>{};
    var regular = 0;
    final seen = <int>{};
    for (var n = 0; n < count; n++) {
      final c = sig + 0xa4 + n * 36;
      if (!seen.add(tmd.getUint32(c)))
        throw const FormatException('Duplicate Wii content');
      if (tmd.getUint16(c + 6) & 0x8000 != 0)
        shared.add(
          bytes
              .sublist(c + 16, c + 36)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(),
        );
      else
        regular++;
    }
    return WiiWad(id, tmd.getUint16(sig + 0x9c), count, shared, regular);
  } finally {
    await f.close();
  }
}

Future<String> wiiGameIdentity(String path) async {
  if (path.toLowerCase().endsWith('.wad'))
    return (await readWiiWad(path)).title;
  final id = await wiiDiscId(path);
  return '00010000${ascii.encode(id.substring(0, 4)).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

Future<String> wiiDiscId(String path) async {
  final f = await File(path).open();
  try {
    final h = await f.read(0x80);
    if (h.length < 0x80) throw const FormatException('Truncated Wii disc');
    final start = ascii.decode(h.take(4).toList(), allowInvalid: true);
    final magic = ByteData.sublistView(h).getUint32(0);
    final offset = magic == 0x52565a01 || magic == 0x57494101
        ? 0x58
        : start == 'WBFS'
        ? -1
        : 0;
    Uint8List disc;
    if (offset < 0) {
      // First occupied WBFS slot, bounded disc header lookup.
      final shift = h[8], blockShift = h[9];
      if (shift < 9 || shift > 20 || blockShift < shift || blockShift > 26)
        throw const FormatException('Invalid WBFS geometry');
      await f.setPosition(12);
      final table = await f.read((1 << shift) - 12);
      final slot = table.where((b) => b != 0).firstOrNull;
      if (slot == null) throw const FormatException('Empty WBFS container');
      await f.setPosition(slot * (1 << shift));
      disc = await f.read(0x80);
    } else {
      await f.setPosition(offset);
      disc = await f.read(0x80);
    }
    if (disc.length != 0x80 ||
        ByteData.sublistView(disc).getUint32(0x18) != 0x5d1c9ea3)
      throw const FormatException('The content is not a supported Wii disc');
    final id = disc.sublist(0, 6);
    final value = ascii.decode(id, allowInvalid: true);
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(value))
      throw const FormatException('Invalid Wii disc identity');
    return value;
  } finally {
    await f.close();
  }
}

void matchWiiContent(String base, WiiWad wad, String kind) {
  if (base.startsWith('00010001') &&
      wad.type == '00010001' &&
      wad.title != base) {
    throw const FormatException(
      'The Wii channel update belongs to another title',
    );
  }
  if (base.startsWith('00010001') &&
      wad.type == '00010005' &&
      base.substring(10) != wad.title.substring(10)) {
    throw const FormatException('Wii channel DLC belongs to another title');
  }
  if (base.startsWith('00010000') && wad.type != '00010005') {
    throw const FormatException(
      'A Wii disc accepts DLC WADs, not channel/system updates',
    );
  }
  // Disc and DLC title IDs use different namespaces. RomM's game attachment
  // supplies their association; the native region must still agree.
  if (base.substring(14) != wad.title.substring(14)) {
    throw const FormatException('Wii package and base game regions differ');
  }
}
