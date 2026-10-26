import 'dart:io';
import 'dart:isolate';

import 'addons/files.dart';
import 'playstation.dart';
import 'managed_emulators.dart' show ownedDirectory;
import 'progress/digest.dart';
import 'romm/client.dart';
import 'romm/transfer.dart';
import 'session.dart';

/// Install a uniquely identified, checksum-verified BIOS from this platform's
/// RomM catalogue. Never replace configured firmware or use another server.
Future<void> ensurePlayStationFirmware(
  ResolvedSession session,
  int platformId,
  RommClient client,
  DownloadCancellation cancellation,
  void Function(String) phase,
) async {
  final e = session.emulator;
  final ps2 = isPs2Emulator(e.name);
  if (!ps2 && e.name != 'DuckStation')
    throw const FormatException('Not a PlayStation BIOS integration');
  final system = Directory('${e.root}/system');
  await ownedDirectory(system);
  final bios = await addonFile(system, 'bios.bin', createParents: false);
  Future<bool> valid(File file) async {
    final size = await file.length();
    if (!ps2) return size == 512 * 1024;
    if (size != 4 * 1024 * 1024) return false;
    final bytes = await file
        .openRead(0, 512 * 1024)
        .fold<List<int>>([], (a, b) => a..addAll(b));
    // ROMDIR is part of the native PS2 ROM image. Reject a size-only match.
    final text = String.fromCharCodes(bytes);
    return text.contains('ROMDIR') && text.contains('ROMVER');
  }

  if (await bios.exists()) {
    if (!await valid(bios))
      throw StateError(
        'The private ${ps2 ? 'PS2' : 'PS1'} BIOS is invalid. It was kept; replace it explicitly before playing.',
      );
    return;
  }
  final all = await client.firmware(platformId);
  var candidates = all
      .where(
        (f) =>
            f.platformId == platformId &&
            f.bytes == (ps2 ? 4 * 1024 * 1024 : 512 * 1024) &&
            f.name.toLowerCase().endsWith('.bin'),
      )
      .toList();
  final named = candidates
      .where((f) => f.name.toLowerCase() == 'bios.bin')
      .toList();
  if (named.isNotEmpty) candidates = named;
  if (candidates.length != 1)
    throw StateError(
      'Add one ${ps2 ? '4 MiB PS2' : '512 KiB PS1'} BIOS named bios.bin to this platform’s RomM BIOS/firmware catalogue and rescan. Existing files were kept.',
    );
  final source = candidates.single;
  final stage = await system.createTemp('.bios-');
  try {
    cancellation.check();
    phase('Downloading ${ps2 ? 'PS2' : 'PS1'} BIOS from RomM');
    final file = File('${stage.path}/bios.bin');
    await client.downloadFirmware(
      source,
      file,
      cancellation: cancellation,
      onProgress: (_) {},
    );
    if (await Isolate.run(() => progressFileHash(file, md5: true)) !=
            source.md5 ||
        !await valid(file))
      throw StateError(
        'The downloaded BIOS did not match its native format or RomM checksum. Existing firmware was kept.',
      );
    cancellation.check();
    if (await bios.exists())
      throw const FileSystemException('BIOS changed during installation');
    await file.rename(bios.path);
  } finally {
    await stage.delete(recursive: true);
  }
}
