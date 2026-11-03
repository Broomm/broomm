import 'dart:io';

import '../progress/files.dart';
import 'settings_paths.dart';

/// The caller holds SessionLease, including native writers, and has obtained
/// explicit confirmation to remove installations and reset settings. Console
/// data, account identities, native saves/states and sync recovery are retained.
/// A durable intent makes an interrupted reset repeatable without relying on
/// valid installation receipts. Symlinks are removed, never traversed.
Future<void> resetEmulatorData(
  Directory data,
  void Function(String) phase, {
  Future<void> Function()? clearPreferences,
  Future<void> Function(String, String)? seedSettings,
}) async {
  final journal = File('${data.path}/emulator-reset.json');
  final targets = <String>['emulators', 'setup-downloads', 'setup-packages'];
  final retainedProfiles = <(String, String)>[];
  final profiles = Directory('${data.path}/profiles');
  if (await progressExists(profiles.path)) {
    await progressDirectory(profiles);
    await for (final profile in profiles.list(followLinks: false)) {
      final id = profile.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) continue;
      if (profile is! Directory)
        throw const FileSystemException(
          'A linked profile must be inspected before resetting emulators.',
        );
      final emulators = Directory('${profile.path}/emulators');
      if (!await progressExists(emulators.path)) continue;
      await progressDirectory(emulators);
      await for (final emulator in emulators.list(followLinks: false)) {
        if (emulator is! Directory) continue;
        final name = emulator.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(name) || name.startsWith('.'))
          continue;
        retainedProfiles.add((id, name));
        for (final setting in emulatorSettingsPaths(name)) {
          final relative = 'profiles/$id/emulators/$name/$setting';
          // Missing optional native configuration parents need no mutation.
          if (await progressExists('${data.path}/$relative'))
            targets.add(relative);
        }
        if (name == 'retroarch') {
          final cores = Directory('${emulator.path}/core-data');
          if (await cores.exists()) {
            await progressDirectory(cores);
            await for (final core in cores.list(followLinks: false)) {
              if (core is! Directory) continue;
              await for (final game in core.list(followLinks: false)) {
                if (game is! Directory) continue;
                for (final file in [
                  'core-options.cfg',
                  'session-options.cfg',
                ]) {
                  final relative =
                      '${game.path.substring(data.path.length + 1)}/$file';
                  if (await progressExists('${data.path}/$relative'))
                    targets.add(relative);
                }
              }
            }
          }
        }
      }
    }
  }
  if (await progressExists(journal.path)) {
    final record = await progressJson(journal);
    if (record['product'] != 'Broomm emulator reset' || record['version'] != 1)
      throw const FormatException('Unrecognized emulator reset record.');
  }
  // Check all ancestors before writing intent or deleting any target.
  for (final relative in targets) await progressPath(data, relative);
  await progressWrite(journal, {
    'product': 'Broomm emulator reset',
    'version': 1,
  });
  for (final relative in targets) {
    phase('Resetting $relative…');
    final path = await progressPath(data, relative);
    switch (await FileSystemEntity.type(path, followLinks: false)) {
      case FileSystemEntityType.directory:
        await Directory(path).delete(recursive: true);
        if (relative.startsWith('profiles/')) await Directory(path).create();
      case FileSystemEntityType.link:
        await Link(path).delete();
      case FileSystemEntityType.file:
        await File(path).delete();
      case FileSystemEntityType.notFound:
        break;
      default:
        throw const FileSystemException('Unsupported emulator storage entry.');
    }
  }
  for (final (profile, emulator) in retainedProfiles)
    await seedSettings?.call(profile, emulator);
  await clearPreferences?.call();
  await journal.delete();
}
