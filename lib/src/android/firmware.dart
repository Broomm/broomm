import 'dart:io';
import 'dart:isolate';

import '../playstation_firmware.dart';
import '../progress/digest.dart';
import '../progress/files.dart';
import '../romm/client.dart';
import '../romm/transfer.dart';
import '../switch_firmware.dart';
import 'armsx2_root.dart';
import 'eden_root.dart';
import 'emulators.dart';
import 'root_media.dart';

Future<void> provisionAndroidEden(
  AndroidEmulators manager,
  AndroidApp app,
  int platformId,
  RommClient client,
  DownloadCancellation cancellation,
  void Function(String) phase,
) async {
  final status = await manager.channel.invokeMapMethod<String, String>(
    'rootEdenFirmwareStatus',
    {'package': app.package, 'build': app.build},
  );
  final binding = {...?status, 'access': androidEdenRootAccess};
  if (binding.remove('version') case final String version)
    binding['emulatorVersion'] = version;
  final pending = binding.remove('missing');
  if (!androidEdenRootBinding(binding) ||
      binding['build'] != app.build ||
      pending == null)
    throw StateError('Eden’s firmware destination could not be verified.');
  if (pending.isEmpty) return;
  final missing = pending.split(',');
  if (missing.toSet().length != missing.length ||
      missing.any(
        (key) => !{'prod_keys', 'title_keys', 'switch_firmware'}.contains(key),
      ))
    throw const FormatException('Invalid Eden firmware inventory.');

  cancellation.check();
  phase('Checking RomM for Switch firmware and keys');
  final catalogue = await rommSwitchResources(client, platformId);
  final stage = (await progressFile(
    manager.data,
    'android/shared-session/${progressNonce()}/.probe',
    createParents: true,
  )).parent;
  try {
    final sources = <String, File>{};
    final digests = <String, String>{};
    for (final key in missing) {
      final source = catalogue[key]!;
      final firmware = key == 'switch_firmware';
      if (source.bytes < (key == 'title_keys' ? 0 : 1) ||
          source.bytes > (firmware ? 2 * 1024 * 1024 * 1024 : 256 * 1024))
        throw StateError(
          'The RomM Switch resource exceeds its supported size.',
        );
      cancellation.check();
      final file = await downloadRommSwitchResource(
        client,
        key,
        source,
        stage,
        cancellation,
        phase,
      );
      if (firmware)
        await Isolate.run(() => validateSwitchFirmwareArchive(file));
      sources[key] = file;
      digests[key] = await Isolate.run(() => progressFileHash(file));
    }
    for (final entry in sources.entries) {
      cancellation.check();
      phase(
        entry.key == 'switch_firmware'
            ? 'Installing Switch firmware in Eden'
            : 'Installing Switch keys in Eden',
      );
      await manager.channel.invokeMethod<void>('rootEdenProvision', {
        ...binding,
        'path': entry.key,
        'source': entry.value.path,
        'after': digests[entry.key],
      });
    }
    cancellation.check();
  } finally {
    await stage.delete(recursive: true);
  }
}

const _armsFirmwareAccess = 'armsx2-firmware-v1';
const androidArmsx2ImportBios = 'Broomm BIOS/broomm-ps2-bios.bin';

bool canProvisionArmsx2Bios(AndroidApp app) =>
    app.package == androidArmsx2RootPackage &&
    app.version == androidArmsx2RootVersion;

Future<void> prepareSharedArmsx2Bios(
  AndroidEmulators manager,
  String package,
  String tree,
  int platformId,
  RommClient client,
  DownloadCancellation cancellation,
  void Function(String) phase, {
  AndroidApp? app,
}) async {
  final destination = {
    'emulator': 'armsx2',
    'package': package,
    'tree': tree,
    'path': androidArmsx2ImportBios,
  };
  await _withAndroidPs2Bios(manager, platformId, client, cancellation, phase, (
    bios,
    sha,
  ) async {
    final current = manager.installed[package];
    if (app != null &&
        (current?.build != app.build || current?.enabled != true))
      throw StateError('ARMSX2 changed during setup. Refresh and retry.');
    phase('Preparing the ARMSX2 BIOS import folder');
    await manager.channel.invokeMethod<void>('sharedReplace', {
      ...destination,
      'after': sha,
      'source': bios.path,
      'token': '${sha.substring(0, 32)}-in',
    });
  });
}

Future<void> prepareRootArmsx2ImportBios(
  AndroidEmulators manager,
  int platformId,
  RommClient client,
  DownloadCancellation cancellation,
  void Function(String) phase,
) => _withAndroidPs2Bios(manager, platformId, client, cancellation, phase, (
  bios,
  sha,
) async {
  phase('Preparing the ARMSX2 App Data Folder and BIOS');
  final prepared = await manager.channel.invokeMethod<bool>(
    'rootPrepareEmulatorInstall',
    {'package': androidArmsx2RootPackage, 'source': bios.path, 'after': sha},
  );
  if (prepared != true)
    throw StateError('Android did not confirm BIOS preparation.');
});

Future<void> provisionAndroidArmsx2Bios(
  AndroidEmulators manager,
  AndroidApp app,
  int platformId,
  RommClient client,
  DownloadCancellation cancellation,
  void Function(String) phase,
) async {
  final status = await manager.channel.invokeMapMethod<String, String>(
    'rootArmsx2BiosStatus',
    {'package': app.package, 'build': app.build},
  );
  final binding = {...?status, 'access': _armsFirmwareAccess};
  if (binding.remove('version') case final String version)
    binding['emulatorVersion'] = version;
  final missing = binding.remove('missing');
  if (!androidAppMediaBinding(
        binding,
        access: _armsFirmwareAccess,
        package: androidArmsx2RootPackage,
        version: androidArmsx2RootVersion,
        signer: androidArmsx2RootSigner,
      ) ||
      binding['build'] != app.build ||
      !{'true', 'false'}.contains(missing))
    throw StateError('ARMSX2’s firmware destination could not be verified.');
  if (missing == 'false') return;
  await _withAndroidPs2Bios(manager, platformId, client, cancellation, phase, (
    bios,
    sha,
  ) async {
    phase('Installing the PS2 BIOS in ARMSX2');
    await manager.channel.invokeMethod<void>('rootArmsx2BiosProvision', {
      ...binding,
      'after': sha,
      'source': bios.path,
    });
  });
}

Future<void> _withAndroidPs2Bios(
  AndroidEmulators manager,
  int platformId,
  RommClient client,
  DownloadCancellation cancellation,
  void Function(String) phase,
  Future<void> Function(File, String) install,
) async {
  final stage = (await progressFile(
    manager.data,
    'android/shared-session/${progressNonce()}/.probe',
    createParents: true,
  )).parent;
  try {
    cancellation.check();
    await ensurePlayStationBios(
      stage,
      ps2: true,
      platformId: platformId,
      client: client,
      cancellation: cancellation,
      phase: phase,
    );
    final bios = await progressFile(stage, 'bios.bin');
    final sha = await Isolate.run(() => progressFileHash(bios));
    cancellation.check();
    await install(bios, sha);
    cancellation.check();
  } finally {
    await stage.delete(recursive: true);
  }
}
