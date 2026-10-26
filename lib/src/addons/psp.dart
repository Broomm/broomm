import 'dart:io';

import '../managed_emulators.dart' show ownedDirectory;
import '../progress/digest.dart';
import '../progress/zip.dart';
import '../romm/transfer.dart';
import 'files.dart';

/// PSP has no universal package installer. Accept explicit native memory-stick
/// trees, so a ZIP/name never guesses whether content belongs in GAME/SAVEDATA.
String pspContentPath(String path, String base) {
  addonRelative(path);
  if (!path.startsWith('PSP/')) path = 'PSP/$path';
  final parts = path.split('/');
  if (parts.length < 4 ||
      parts[0] != 'PSP' ||
      !{'GAME', 'SAVEDATA'}.contains(parts[1]) ||
      !RegExp('^${RegExp.escape(base)}[A-Za-z0-9_-]{0,80}\$')
          .hasMatch(parts[2]))
    throw const FormatException(
      'PSP updates/DLC must contain PSP/GAME/<matching disc ID>/... or PSP/SAVEDATA/<matching disc ID>.../... . Preserve that structure in RomM or its ZIP; firmware and unrelated titles were kept out.',
    );
  return path;
}

Future<void> stagePspContent(
  String base,
  Iterable<(String, String)> inputs,
  Directory stage,
  Directory payload,
  Map<String, dynamic> units,
  int version,
  DownloadCancellation cancellation,
) async {
  var sequence = 0;
  for (final input in inputs) {
    cancellation.check();
    final file = File(input.$1), path = input.$2;
    final entries = <String, File>{};
    if (path.toLowerCase().endsWith('.zip')) {
      final root = Directory('${stage.path}/psp-unpack-${sequence++}');
      await ownedDirectory(root);
      final zip = await ProgressZip.read(
        file,
        maxBytes: 2 * 1024 * 1024 * 1024,
        maxEntryBytes: 1024 * 1024 * 1024,
      );
      await zip.extract(root);
      for (final e in zip.entries)
        entries[e.name] = await addonFile(root, e.name);
    } else {
      // Remove only RomM's category folder. Native PSP/ path remains explicit.
      entries[path.substring(path.indexOf('/') + 1)] = file;
    }
    if (entries.isEmpty)
      throw const FormatException('PSP package contains no native files');
    for (final e in entries.entries) {
      cancellation.check();
      final relative = pspContentPath(e.key, base),
          hash = await progressFileHash(e.value);
      final previous = units[relative] as Map?;
      if (previous != null) {
        if ((previous['files'] as Map)[''] != hash)
          throw const FormatException(
            'Two PSP packages contain different bytes at the same path. Keep one version in RomM; existing content was kept.',
          );
        continue;
      }
      final destination = await addonFile(
        payload,
        relative,
        createParents: true,
      );
      if (await destination.exists())
        throw const FileSystemException('PSP staging collision');
      await e.value.copy(destination.path);
      if (await progressFileHash(destination) != hash)
        throw const FileSystemException(
          'PSP content copy could not be verified',
        );
      units[relative] = {
        'version': version,
        'files': {'': hash},
      };
    }
  }
}
