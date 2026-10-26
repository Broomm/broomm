import 'dart:io';

import 'progress/digest.dart';
import 'progress/files.dart';
import 'retroarch.dart';

/// Match the frontend's existing game/folder/core/global option precedence.
/// The returned text is a source for an isolated session override, not a new
/// settings store. Core names are concrete pinned library names.
Future<String> retroCoreOptionsText(
  String root,
  String library,
  String rom,
) async {
  final stem = File(rom).uri.pathSegments.last
      .replaceFirst(RegExp(r'\.[^.]+$'), '');
  final folder = File(rom).parent.uri.pathSegments
      .where((s) => s.isNotEmpty)
      .lastOrNull;
  var frontend = '';
  if (await progressExists('$root/retroarch.cfg')) {
    final file = await progressFile(Directory(root), 'retroarch.cfg');
    if (await file.length() > 1024 * 1024)
      throw const FormatException('RetroArch configuration is too large');
    frontend = await file.readAsString();
  }
  bool flag(String name, bool fallback) {
    final values = RegExp(
      '^\\s*$name\\s*=\\s*"?(true|false)"?\\s*(?:#.*)?\$',
      multiLine: true,
    ).allMatches(frontend).map((m) => m[1] == 'true').toSet();
    if (values.length > 1)
      throw const FormatException(
        'RetroArch has conflicting option-storage settings',
      );
    return values.firstOrNull ?? fallback;
  }

  final gameSpecific = flag('game_specific_options', true);
  final global = flag('global_core_options', false);
  for (final path in [
    if (gameSpecific) 'config/$library/$stem.opt',
    if (gameSpecific && folder != null) 'config/$library/$folder.opt',
    if (!global) 'config/$library/$library.opt',
    'config/core-options.cfg',
  ]) {
    progressRelative(path);
    if (!await progressExists('$root/$path')) continue;
    final file = await progressFile(Directory(root), path);
    if (await file.length() > 1024 * 1024)
      throw const FormatException('RetroArch core options are too large');
    return file.readAsString();
  }
  return '';
}

/// Opera writes its own NVRAM image rather than exposing ordinary Libretro
/// SRAM. Retain its native directory/version when importing a raw .srm.
Future<String> operaRawSaveKey(String root, String rom) async {
  final text = await retroCoreOptionsText(root, 'Opera', rom);
  String option(String name, String fallback) {
    final values = RegExp(
      '^\\s*$name\\s*=\\s*"([^"]*)"\\s*\$',
      multiLine: true,
    ).allMatches(text).map((m) => m[1]!).toSet();
    if (values.length > 1)
      throw const FormatException('Opera has conflicting NVRAM options');
    return values.firstOrNull ?? fallback;
  }

  final storage = option('opera_nvram_storage', 'per game');
  final version = option('opera_nvram_version', '0');
  if (!{'per game', 'shared'}.contains(storage) ||
      !RegExp(r'^[0-9]$').hasMatch(version))
    throw const FormatException('Opera NVRAM options are not recognized');
  final stem = await retroSaveStem(rom, 'opera');
  final key = storage == 'shared'
      ? 'save/opera/shared/nvram.$version.srm'
      : 'save/opera/per_game/$stem.$version.srm';
  progressRelative(key);
  return key;
}

/// Called under the session/writer lease, before cloud inspection or play.
/// Old builds left VMUs in the profile's system directory. Copy those cards
/// only when there is one unambiguous historical game; never delete originals.
Future<void> prepareFlycastSaves(
  String root,
  String content,
  String rom,
) async {
  final owner = Directory(root);
  final base = Directory('$root/core-data/flycast');
  await progressDirectory(base);
  final journal = await progressFile(
    owner,
    'core-data/flycast/legacy-vmus.json',
  );
  Map<String, dynamic>? record;
  if (await progressExists(journal.path)) {
    record = await progressJson(journal);
    if (record['version'] != 1 ||
        record['content'] is! String ||
        record['files'] is! Map)
      throw const FormatException(
        'The retained Dreamcast VMU migration is invalid',
      );
    if (record['complete'] == true || record['content'] != content) return;
  }
  if (record == null) {
    final files = <String, String>{};
    for (final port in ['A', 'B', 'C', 'D']) {
      for (final slot in ['1', '2']) {
        final path = 'system/dc/vmu_save_$port$slot.bin';
        if (!await progressExists('$root/$path')) continue;
        final source = await progressFile(owner, path);
        if (await source.length() != 128 * 1024)
          throw const FormatException(
            'A retained Dreamcast VMU has an invalid size; it was kept',
          );
        files['$port$slot'] = await progressFileHash(source);
      }
    }
    if (files.isEmpty) return;
    final games = <String>{};
    await for (final entry in base.list(followLinks: false)) {
      if (entry is Directory &&
          !entry.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last
              .startsWith('.'))
        games.add(entry.uri.pathSegments.where((s) => s.isNotEmpty).last);
    }
    if (games.difference({content}).isNotEmpty)
      throw const FormatException(
        'Legacy shared Dreamcast VMUs need explicit per-game migration. The original cards were kept in the profile’s system/dc folder; no game was overwritten.',
      );
    record = {
      'version': 1,
      'content': content,
      'files': files,
      'complete': false,
    };
    await progressWrite(journal, record);
  }
  final stem = await retroSaveStem(rom, 'flycast');
  for (final entry in (record['files'] as Map).entries) {
    final slot = entry.key as String;
    if (!RegExp(r'^[A-D][12]$').hasMatch(slot) ||
        entry.value is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.value as String))
      throw const FormatException(
        'The retained Dreamcast VMU inventory is invalid',
      );
    final source = await progressFile(owner, 'system/dc/vmu_save_$slot.bin');
    if (await source.length() != 128 * 1024 ||
        await progressFileHash(source) != entry.value)
      throw const FormatException(
        'A legacy Dreamcast VMU changed during migration. Both copies were kept.',
      );
    final target = await progressFile(
      owner,
      '${retroGameDirectory('flycast', content)}/saves/$stem.$slot.bin',
      createParents: true,
    );
    if (await progressExists(target.path)) {
      if (await progressFileHash(target) != entry.value)
        throw const FormatException(
          'A private Dreamcast VMU already contains different data. Both cards were kept; review the private and legacy VMUs before playing.',
        );
    } else {
      final bytes = await source.readAsBytes();
      await target.create(exclusive: true);
      await target.writeAsBytes(bytes, flush: true);
    }
    if (await progressFileHash(target) != entry.value ||
        await progressFileHash(source) != entry.value)
      throw const FormatException(
        'Dreamcast VMU migration could not be verified. Original cards were kept.',
      );
  }
  await progressWrite(journal, {...record, 'complete': true});
}
