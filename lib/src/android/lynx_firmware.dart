import 'dart:async';
import 'dart:io';

import '../progress/digest.dart';
import '../progress/files.dart';
import '../romm/client.dart';
import '../romm/models.dart';
import '../romm/transfer.dart';

const androidLynxBootMd5 = 'fcd403db69f54290b51035d82f835e7b';

/// A verified immutable input, rechecked against this digest at session staging.
/// It is not progress and must never enter a cloud save inventory.
class AndroidLynxBootImage {
  AndroidLynxBootImage._(this.file, this.sha256);
  final File file;
  final String sha256;
}

/// Transfer integrity at the RomM boundary; the concrete caller selects firmware.
/// Destination is private staging, never an existing published BIOS.
Future<void> downloadAndroidFirmware(
  RommClient client,
  RommFirmware source,
  File destination,
  DownloadCancellation cancellation,
) async {
  cancellation.check();
  if (await progressExists(destination.path))
    throw const FileSystemException('Firmware staging already exists.');
  await client.downloadFirmware(
    source,
    destination,
    cancellation: cancellation,
    onProgress: (_) {},
  );
  cancellation.check();
  await progressFile(destination.parent, destination.uri.pathSegments.last);
  if (await destination.length() != source.bytes ||
      await progressFileHash(destination, md5: true) != source.md5)
    throw const RommFailure(
      'The BIOS download did not match RomM. Existing firmware was kept.',
    );
}

/// Called only by normal Play preparation while the production SessionLease is
/// held. Cache objects are exclusive and immutable; the atomic index selects one.
/// Repair retains older/damaged objects, and an unreadable index is an error.
Future<AndroidLynxBootImage> ensureAndroidLynxBoot(
  Directory profileRoot,
  int platform,
  RommClient client,
  DownloadCancellation cancellation,
  void Function(String) phase,
) async {
  cancellation.check();
  final index = await progressFile(
    profileRoot,
    'lynx-firmware/index.json',
    createParents: true,
  );
  var damaged = false;
  if (await progressExists(index.path)) {
    final record = await progressJson(index);
    if (record['version'] != 1 ||
        record['platform'] != platform ||
        record['bytes'] != 512 ||
        record['md5'] != androidLynxBootMd5 ||
        !RegExp(r'^[a-f0-9]{32}$')
            .hasMatch(record['object'] as String? ?? '') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(record['sha256'] as String? ?? ''))
      throw const FormatException(
        'The cached Lynx BIOS record is invalid. Existing files were kept.',
      );
    final file = await progressFile(index.parent, '${record['object']}.img');
    if (await file.exists() &&
        await file.length() == 512 &&
        await progressFileHash(file, md5: true) == androidLynxBootMd5 &&
        await progressFileHash(file) == record['sha256']) {
      cancellation.check();
      phase('Using verified Lynx BIOS.');
      return AndroidLynxBootImage._(file, record['sha256'] as String);
    }
    damaged = true;
  }
  phase(
    damaged
        ? 'Repairing the cached Lynx BIOS from RomM…'
        : 'Checking RomM for the Lynx BIOS…',
  );
  final remote = await client.firmware(platform);
  cancellation.check();
  final matches = remote
      .where(
        (f) =>
            f.platformId == platform && f.name.toLowerCase() == 'lynxboot.img',
      )
      .toList();
  if (matches.length != 1)
    throw RommFailure(
      matches.isEmpty
          ? 'Missing lynxboot.img. Add the required Lynx BIOS to this platform in RomM, then try Play again.'
          : 'RomM has more than one lynxboot.img for this platform. Keep one matching Lynx BIOS, then try Play again.',
    );
  final source = matches.single;
  if (source.bytes != 512 || source.md5 != androidLynxBootMd5)
    throw const RommFailure(
      'RomM’s lynxboot.img is not the required 512-byte Lynx BIOS. Existing files were kept.',
    );
  final stage = await index.parent.createTemp('incoming-');
  var timedOut = false;
  var writerUncertain = false;
  final timer = Timer(const Duration(seconds: 60), () {
    timedOut = true;
    cancellation.cancel();
  });
  try {
    phase('Downloading and verifying the Lynx BIOS…');
    final incoming = File('${stage.path}/lynxboot.img');
    await downloadAndroidFirmware(client, source, incoming, cancellation);
    final hash = await progressFileHash(incoming);
    final nonce = progressNonce();
    final target = await progressFile(index.parent, '$nonce.img');
    cancellation.check();
    await target.create(exclusive: true);
    await target.writeAsBytes(await incoming.readAsBytes(), flush: true);
    if (await target.length() != 512 ||
        await progressFileHash(target) != hash ||
        await progressFileHash(target, md5: true) != androidLynxBootMd5)
      throw const FileSystemException(
        'The verified Lynx BIOS changed during publication.',
      );
    cancellation.check();
    await progressWrite(index, {
      'version': 1,
      'platform': platform,
      'object': nonce,
      'bytes': 512,
      'md5': androidLynxBootMd5,
      'sha256': hash,
    });
    phase('Lynx BIOS ready.');
    return AndroidLynxBootImage._(target, hash);
  } on DownloadCancelled {
    if (timedOut)
      throw const RommFailure(
        'The Lynx BIOS download timed out. Try Play again.',
      );
    rethrow;
  } on DownloadWriterUncertain {
    writerUncertain = true;
    rethrow;
  } finally {
    timer.cancel();
    if (!writerUncertain) await stage.delete(recursive: true);
  }
}
