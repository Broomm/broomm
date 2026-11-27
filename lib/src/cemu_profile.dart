import 'dart:io';

import 'cemu.dart';
import 'managed_emulators.dart' show ownedDirectory, copyTree;
import 'progress/files.dart';
import 'setup/linux_identity.dart';
import 'romm/transfer.dart';

/// A versioned private portable anchor. The MLC is deliberately outside it:
/// ordinary saves/accounts persist across emulator upgrades and signatures.
Future<(String executable, String portable)> prepareCemuLauncher({
  required Directory profile,
  required Directory source,
  required String executable,
  required String executableHash,
  required Map inventory,
  required String host,
}) async {
  final parent = Directory('${profile.path}/launcher');
  await ownedDirectory(parent);
  final target = Directory('${parent.path}/$executableHash');
  final files = (inventory['files'] as Map).keys.cast<String>().toList();
  if ((inventory['links'] as Map).isNotEmpty)
    throw const FormatException(
      'This Cemu build has unsupported portable links.',
    );
  final mac = host.startsWith('macos-');
  final bundle = mac ? 'Cemu.app' : 'Cemu';
  final portable = mac ? 'portable' : '$bundle/portable';
  final selected = File('${profile.path}/cemu-launcher.json');
  if (!await target.exists()) {
    final stage = await parent.createTemp('.cemu-');
    var published = false;
    try {
      await copyTree(
        source.path,
        '${stage.path}/$bundle',
        DownloadCancellation(),
        allowBundleLinks: true,
      );
      final stamp = await linuxTreeStamp(
        Directory('${stage.path}/$bundle'),
        files,
      );
      await progressWrite(File('${stage.path}/receipt.json'), {
        'version': 1,
        'hash': executableHash,
        'files': stamp,
      });
      await ownedDirectory(Directory('${stage.path}/$portable'));
      if (await selected.exists()) {
        final prior = await progressJson(selected);
        final previous = prior['hash'];
        final oldPortable = prior['portable'];
        if (previous is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(previous) ||
            oldPortable != 'portable' && oldPortable != 'Cemu/portable')
          throw const FormatException(
            'Cemu’s previous private launcher is not recognized. Existing data was kept.',
          );
        final settings = await progressFile(
          parent,
          '$previous/$oldPortable/settings.xml',
        );
        if (await settings.exists()) {
          final text = await readCemuXml(settings);
          cemuXml(text, 'content');
          await File('${stage.path}/$portable/settings.xml')
              .writeAsString(text, flush: true);
        }
      }
      await stage.rename(target.path);
      published = true;
    } finally {
      if (!published && await stage.exists())
        await stage.delete(recursive: true);
    }
  }
  await ownedDirectory(target);
  final receipt = await progressJson(File('${target.path}/receipt.json'));
  if (receipt['version'] != 1 || receipt['hash'] != executableHash)
    throw const FormatException(
      'Cemu’s private launcher identity changed. Existing data was kept.',
    );
  await verifyLinuxStamp(
    Directory('${target.path}/$bundle'),
    files,
    receipt['files'],
  );
  await ownedDirectory(Directory('${target.path}/$portable'));
  await ownedDirectory(Directory('${profile.path}/user/mlc01'));
  await progressWrite(selected, {
    'version': 1,
    'hash': executableHash,
    'portable': portable,
  });
  return ('${target.path}/$bundle/$executable', '${target.path}/$portable');
}
