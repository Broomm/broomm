import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'addons/files.dart';
import 'managed_emulators.dart';
import 'progress/digest.dart';
import 'progress/zip.dart';
import 'romm/client.dart';
import 'romm/models.dart';
import 'romm/transfer.dart';
import 'session_lease.dart';

const _switchResources = {
  'prod_keys': 'system/prod.keys',
  'title_keys': 'system/title.keys',
  'switch_firmware': 'bis/system/Contents/registered',
};

Future<bool> _present(
  Directory root,
  String relative, {
  required bool directory,
}) async {
  if (await FileSystemEntity.type(
        '${root.path}/$relative',
        followLinks: false,
      ) ==
      FileSystemEntityType.notFound)
    return false;
  final checked = await addonPath(root, relative);
  if (directory) {
    await ownedDirectory(Directory(checked));
    return (await Directory(checked).list(followLinks: false).toList()).any(
      (f) => RegExp(r'/[a-fA-F0-9]{32}\.nca$').hasMatch(f.path),
    );
  }
  final f = await addonFile(root, relative);
  return relative == 'title_keys' ||
      relative.endsWith('/title.keys') ||
      await f.length() > 0;
}

void validateSwitchKeyFile(String text, {required bool prod}) {
  if (utf8.encode(text).length > 2 * 1024 * 1024 || text.contains('\u0000'))
    throw const FormatException('Invalid Switch key file');
  var header = false;
  for (final line in const LineSplitter().convert(text)) {
    final value = line.trim();
    if (value.isEmpty || value.startsWith('#') || value.startsWith(';'))
      continue;
    final match = RegExp(r'^([a-zA-Z0-9_]+)\s*=\s*([a-fA-F0-9]+)$')
        .firstMatch(value);
    if (match == null || match[2]!.length.isOdd)
      throw const FormatException(
        'The Switch key file contains an invalid entry',
      );
    if (prod && match[1] == 'header_key' && match[2]!.length == 64)
      header = true;
    if (!prod &&
        (match[1]!.length != 32 ||
            match[2]!.length != 32 ||
            !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(match[1]!)))
      throw const FormatException('Invalid title.keys entry');
  }
  if (prod && !header)
    throw const FormatException('prod.keys has no valid header_key');
}

/// Same registered/<NCA ID>.nca/00 layout used by Ryubing's InstallFromZip.
/// Extraction is bounded and confined before any resource is published.
Future<Directory> stageSwitchFirmware(File archive, Directory stage) async {
  final zip = await ProgressZip.read(
    archive,
    maxBytes: 2 * 1024 * 1024 * 1024,
    maxEntryBytes: 512 * 1024 * 1024,
  );
  if (zip.entries.isEmpty || zip.entries.length > 4096)
    throw const FormatException(
      'Firmware ZIP contains no usable NCAs or exceeds its file limit',
    );
  final targets = <String, String>{};
  for (final e in zip.entries) {
    final parts = e.name.split('/');
    final name = parts.last == '00' && parts.length > 1
        ? parts[parts.length - 2]
        : parts.last;
    final match = RegExp(r'^([a-fA-F0-9]{32})(?:\.cnmt)?\.nca$')
        .firstMatch(name);
    if (match == null ||
        e.bytes < 0xc00 ||
        targets.containsKey(match[1]!.toLowerCase()))
      throw const FormatException(
        'Firmware ZIP must contain unique NCA files (or .nca/00 directories)',
      );
    targets[match[1]!.toLowerCase()] = e.name;
  }
  final unpacked = Directory('${stage.path}/unpacked');
  await ownedDirectory(unpacked);
  await zip.extract(unpacked);
  final registered = Directory('${stage.path}/registered');
  await ownedDirectory(registered);
  for (final e in targets.entries) {
    final source = await addonFile(unpacked, e.value),
        target = await addonFile(
          registered,
          '${e.key}.nca/00',
          createParents: true,
        );
    await source.rename(target.path);
  }
  return registered;
}

/// Provision missing resources only. A newer ZIP on RomM never silently
/// updates an already configured emulator or replaces a user's private keys.
Future<void> ensureSwitchFirmware(
  ManagedEmulators manager,
  String profileId,
  int platformId,
  RommClient client,
  DownloadCancellation cancellation,
  void Function(String) phase, {
  required SessionLease lease,
  String emulator = 'Ryubing',
}) async {
  if (!lease.active || lease.key != await manager.data.resolveSymbolicLinks())
    throw StateError('Switch resource preparation has no session owner');
  final (_, profile) = await manager.preparePackages(
    'switch',
    profileId,
    cancellation,
    emulator: emulator,
  );
  final eden = emulator == 'Eden';
  final user = Directory('${profile.path}/${eden ? 'data/eden' : 'user'}');
  final paths = eden
      ? const {
          'prod_keys': 'keys/prod.keys',
          'title_keys': 'keys/title.keys',
          'switch_firmware': 'nand/system/Contents/registered',
        }
      : _switchResources;
  final missing = <String>[];
  for (final e in paths.entries) {
    if (!await _present(user, e.value, directory: e.key == 'switch_firmware'))
      missing.add(e.key);
  }
  if (missing.isEmpty) return;
  final build = manager.buildFor(emulator)!;
  final resources = Directory(
    '${manager.root.path}/${build.id}/${build.hash}/resources',
  );
  await ownedDirectory(resources);
  final needed = <String>[];
  for (final key in missing) {
    if (!await _present(resources, key, directory: key == 'switch_firmware'))
      needed.add(key);
  }
  if (needed.isNotEmpty) {
    phase('Checking RomM for Switch firmware and keys');
    final files = await client.firmware(platformId);
    final zip = files
        .where(
          (f) =>
              f.platformId == platformId &&
              f.name.toLowerCase().endsWith('.zip'),
        )
        .toList();
    final prod = files
        .where(
          (f) =>
              f.platformId == platformId && f.name.toLowerCase() == 'prod.keys',
        )
        .toList();
    final title = files
        .where(
          (f) =>
              f.platformId == platformId &&
              f.name.toLowerCase() == 'title.keys',
        )
        .toList();
    if (zip.length != 1 || prod.length != 1 || title.length != 1)
      throw const RommFailure(
        'Configure exactly one firmware ZIP, prod.keys and title.keys in the Switch platform’s RomM BIOS/firmware catalogue. Existing resources were kept.',
      );
    final selected = {
      'switch_firmware': zip.single,
      'prod_keys': prod.single,
      'title_keys': title.single,
    };
    final stage = await resources.createTemp('.switch-resources-');
    try {
      await addonWrite(File('${stage.path}/owner.json'), {
        'version': 1,
        'build': build.hash,
        'kind': 'switch-resources',
      });
      for (final key in needed) {
        cancellation.check();
        final source = selected[key]!,
            downloaded = File('${stage.path}/${source.id}.download');
        phase(
          'Downloading ${key == 'switch_firmware' ? 'Switch firmware' : source.name} from RomM',
        );
        await client.downloadFirmware(
          source,
          downloaded,
          cancellation: cancellation,
          onProgress: (_) {},
        );
        if (await Isolate.run(() => progressFileHash(downloaded, md5: true)) !=
            source.md5)
          throw const RommFailure(
            'A Switch resource download did not match RomM. Nothing was replaced.',
          );
        FileSystemEntity ready;
        if (key == 'switch_firmware') {
          phase('Installing private Switch firmware');
          ready = await Isolate.run(
            () => stageSwitchFirmware(downloaded, stage),
          );
        } else {
          validateSwitchKeyFile(
            await downloaded.readAsString(),
            prod: key == 'prod_keys',
          );
          ready = downloaded;
        }
        final target = await addonPath(resources, key);
        cancellation.check();
        if (await addonExists(target))
          throw const RommFailure(
            'A Switch resource is incomplete or changed during preparation. It was kept; repair it in Emulator Settings.',
          );
        await ready.rename(target);
        await addonWrite(File('${resources.path}/auto-$key.json'), {
          'version': 1,
          'kind': key,
          'rommFirmwareId': source.id,
          'md5': source.md5,
          'bytes': source.bytes,
        });
      }
    } finally {
      await stage.delete(recursive: true);
    }
  }
  for (final key in missing) {
    cancellation.check();
    final target = await addonPath(user, paths[key]!, createParents: true);
    if (await addonExists(target))
      throw const RommFailure(
        'Private Switch resources are incomplete. Existing files were kept; repair them before retrying.',
      );
    final stage = await profile.createTemp('.switch-resource-copy-');
    try {
      await copyTree(
        '${resources.path}/$key',
        '${stage.path}/payload',
        cancellation,
      );
      cancellation.check();
      final type = await FileSystemEntity.type(
        '${stage.path}/payload',
        followLinks: false,
      );
      if (type == FileSystemEntityType.directory)
        await Directory('${stage.path}/payload').rename(target);
      else
        await File('${stage.path}/payload').rename(target);
    } finally {
      await stage.delete(recursive: true);
    }
  }
  await manager.load();
}
