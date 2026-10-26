import 'dart:io';
import 'dart:isolate';

import 'addons/files.dart';
import 'managed_emulators.dart';
import 'progress/digest.dart';
import 'romm/client.dart';
import 'romm/models.dart';
import 'romm/transfer.dart';
import 'session.dart';

/// Concrete core firmware names from the pinned Libretro metadata. No BIOS is
/// fetched from a public download site, and no system RetroArch data is used.
Future<void> ensureRetroFirmware(
  ManagedEmulators manager,
  ResolvedSession session,
  int platformId,
  RommClient client,
  DownloadCancellation cancellation,
  void Function(String) phase,
) async {
  final core = session.emulator.coreId;
  if (core == null) return;
  final meta = manager.coreBuilds[core]!['firmware'] as Map;
  final paths = <String, bool>{};
  for (final e in meta.entries) {
    if (!RegExp(r'^firmware[0-9]+_path$').hasMatch(e.key as String)) continue;
    final key = (e.key as String).replaceFirst('_path', '_opt');
    final path = e.value as String;
    addonRelative(path);
    paths[path] = meta[key] == 'false';
  }
  // Firmware lists describe every machine a core can emulate. Fetch only
  // what this concrete console/media route uses, not arcade/CD accessories.
  paths.removeWhere(
    (path, _) => switch (core) {
      'mgba' => path != 'gba_bios.bin',
      'flycast' => !{'dc/dc_boot.bin', 'dc/dc_flash.bin'}.contains(path),
      'genesis_plus_gx' ||
      'picodrive' ||
      'mupen64plus_next' ||
      'virtualjaguar' => true,
      'mesen' => !session.rom.toLowerCase().endsWith('.fds'),
      'mednafen_pce_fast' => !RegExp(
        r'\.(cue|ccd|chd|m3u)$',
        caseSensitive: false,
      ).hasMatch(session.rom),
      _ => false,
    },
  );
  final system = Directory('${session.emulator.root}/system');
  await ownedDirectory(system);
  final build = manager.buildFor('RetroArch')!;
  final provided = Directory(
    '${manager.root.path}/retroarch/${build.hash}/resources/bios',
  );
  for (final path in paths.keys) {
    final target = await addonFile(system, path, createParents: true);
    if (await target.exists()) continue;
    if (await provided.exists()) {
      if (await FileSystemEntity.type(
            '${provided.path}/$path',
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        final local = await addonFile(provided, path, createParents: false);
        await local.copy(target.path);
      }
    }
  }
  final missing = <String>[];
  for (final path in paths.keys) {
    if (!await File('${system.path}/$path').exists()) missing.add(path);
  }
  if (missing.isEmpty) return;
  Future<bool> hasOperaBios() async => (await Future.wait(
    paths.keys
        .where((p) => !p.contains('kanji'))
        .map((p) => File('${system.path}/$p').exists()),
  )).any((v) => v);
  if (core == 'opera' && await hasOperaBios()) return;
  // Optional firmware is useful, but an offline lookup must not prevent a
  // core with an HLE/embedded BIOS or already configured BIOS from playing.
  List<RommFirmware> remote;
  try {
    remote = await client.firmware(platformId);
  } on RommFailure {
    if (paths.entries.any((e) => e.value && missing.contains(e.key)) ||
        core == 'opera')
      rethrow;
    return;
  }
  for (final path in missing) {
    final name = path.split('/').last;
    final matches = remote
        .where(
          (f) =>
              f.platformId == platformId &&
              f.name.toLowerCase() == name.toLowerCase(),
        )
        .toList();
    if (matches.length != 1) continue;
    final source = matches.single;
    final stage = await system.createTemp('.firmware-');
    try {
      cancellation.check();
      phase('Downloading $name from RomM');
      final file = File('${stage.path}/bios');
      await client.downloadFirmware(
        source,
        file,
        cancellation: cancellation,
        onProgress: (_) {},
      );
      if (await Isolate.run(() => progressFileHash(file, md5: true)) !=
          source.md5)
        throw const RommFailure(
          'A BIOS download did not match RomM. Existing firmware was kept.',
        );
      final target = await addonFile(system, path, createParents: true);
      cancellation.check();
      if (await target.exists())
        throw const FileSystemException('Firmware changed during download');
      await file.rename(target.path);
    } finally {
      await stage.delete(recursive: true);
    }
  }
  final required = <String>[];
  for (final e in paths.entries) {
    if (e.value && !await File('${system.path}/${e.key}').exists())
      required.add(e.key);
  }
  if (core == 'opera' && !await hasOperaBios()) {
    required.add('a supported 3DO system BIOS');
  }
  if (required.isNotEmpty)
    throw RommFailure(
      'Missing ${required.join(', ')}. Add the BIOS to this platform in RomM or import a RetroArch setup JSON with a local bios resource.',
    );
}
