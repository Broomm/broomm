import 'dart:io';
import 'dart:isolate';

import 'managed_emulators.dart';
import 'managed_profile.dart';
import 'romm/client.dart';
import 'romm/models.dart';
import 'romm/transfer.dart';
import 'progress/digest.dart';
import 'addons/rpcs3_import.dart';
import 'addons/files.dart' show addonJson, addonWrite;
import 'session_lease.dart';

/// Called by session supervision while its session/writer lease is held.
Future<void> ensurePs3Firmware(
  ManagedEmulators manager,
  String profile,
  int platformId,
  RommClient client,
  DownloadCancellation cancellation,
  void Function(String) phase, {
  required SessionLease lease,
  String emulator = 'RPCS3',
}) async {
  if (!lease.active || lease.key != await manager.data.resolveSymbolicLinks())
    throw StateError('PS3 firmware installation has no active session owner');
  await manager.load();
  final build = manager.buildFor(emulator);
  if (build == null || !build.isRpcs3 || !manager.ready(emulator))
    throw StateError('Set up $emulator in Emulator Settings before playing.');
  await manager.requireRuntime(build);
  final release = Directory('${manager.root.path}/${build.id}/${build.hash}');
  await ownedDirectory(release);
  await for (final previous in release.list(followLinks: false)) {
    final name = previous.uri.pathSegments.where((v) => v.isNotEmpty).last;
    if (!name.startsWith('.firmware-')) continue;
    if (previous is! Directory)
      throw StateError(
        'An unknown firmware stage was kept. Inspect managed storage before retrying.',
      );
    final marker = await addonJson(File('${previous.path}/owner.json'));
    if (marker['version'] != 1 ||
        marker['build'] != build.hash ||
        marker['kind'] != 'ps3-firmware-stage')
      throw StateError('Unrecognized firmware staging data was kept.');
    await previous.delete(recursive: true);
  }
  final private = Directory(
    '${manager.data.path}/profiles/$profile/emulators/rpcs3',
  );
  if (await File('${private.path}/portable/dev_flash/sys/external/liblv2.sprx')
      .exists())
    return;
  final target = Directory('${release.path}/resources/ps3_firmware');
  if (!await File('${target.path}/sys/external/liblv2.sprx').exists()) {
    if (await target.exists())
      throw StateError(
        'The managed PS3 firmware is incomplete. Existing files were kept; repair it in Emulator Settings.',
      );
    phase('Checking RomM for PS3 firmware');
    final candidates = (await client.firmware(platformId))
        .where(
          (f) =>
              f.platformId == platformId &&
              f.name.toLowerCase().endsWith('.pup'),
        )
        .toList();
    if (candidates.length != 1)
      throw RommFailure(
        candidates.isEmpty
            ? 'PS3 firmware is missing. Add PS3UPDAT.PUP to this platform’s firmware in RomM, then retry Play.'
            : 'RomM has several PS3 firmware files. Keep one PS3UPDAT.PUP available for automatic installation.',
      );
    final selected = candidates.single;
    await manager.verifyBundle(
      build,
      '${release.path}/${build.bundle}',
      cancellation,
    );
    final stage = await release.createTemp('.firmware-');
    try {
      await addonWrite(File('${stage.path}/owner.json'), {
        'version': 1,
        'build': build.hash,
        'kind': 'ps3-firmware-stage',
      });
      final file = File('${stage.path}/PS3UPDAT.PUP');
      phase('Downloading PS3 firmware');
      await client.downloadFirmware(
        selected,
        file,
        cancellation: cancellation,
        onProgress: (n) {},
      );
      phase('Verifying PS3 firmware');
      if (await Isolate.run(() => progressFileHash(file, md5: true)) !=
          selected.md5)
        throw const RommFailure(
          'The PS3 firmware checksum did not match RomM. Nothing was installed.',
        );
      final header = await file
          .openRead(0, 8)
          .fold<List<int>>([], (a, b) => a..addAll(b));
      if (header.length != 8 || String.fromCharCodes(header.take(5)) != 'SCEUF')
        throw const RommFailure('RomM’s firmware is not a PS3 PUP file.');
      phase('Installing PS3 firmware');
      final user = await installRpcs3Content(
        '${release.path}/${build.bundle}/${build.executable}',
        file.path,
        stage,
        cancellation,
        firmware: true,
        data: manager.data,
      );
      final flash = Directory('${user.path}/dev_flash');
      if (!await File('${flash.path}/sys/external/liblv2.sprx').exists())
        throw const RommFailure(
          'RPCS3 did not produce a complete PS3 firmware installation.',
        );
      await inspectTree(flash.path, allowLinks: false);
      cancellation.check();
      await ownedDirectory(target.parent);
      if (await target.exists())
        throw StateError(
          'PS3 firmware changed during installation. Retry Play.',
        );
      await flash.rename(target.path);
    } catch (_) {
      rethrow;
    } finally {
      await retainRpcs3InstallLog(
        stage,
        manager.data,
        onProblem: (message) => manager.log?.write(message, level: 'warning'),
      );
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }
  final runtime = await prepareManagedProfile(
    manager.data,
    profile,
    build,
    release,
  );
  final destination = Directory('${runtime.path}/portable/dev_flash');
  if (!await destination.exists()) {
    final stage = await runtime.createTemp('.firmware-');
    try {
      await copyTree(target.path, '${stage.path}/dev_flash', cancellation);
      cancellation.check();
      await Directory('${stage.path}/dev_flash').rename(destination.path);
    } finally {
      await stage.delete(recursive: true);
    }
  }
  if (!await File('${destination.path}/sys/external/liblv2.sprx').exists())
    throw StateError(
      'This profile has incomplete PS3 firmware. Existing files were kept.',
    );
  await manager.load();
}
