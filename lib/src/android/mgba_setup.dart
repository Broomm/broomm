import 'dart:async';
import 'dart:io';

import '../progress/digest.dart';
import '../progress/files.dart';
import '../progress/zip.dart';
import 'apk_download.dart';

const _coreFile = 'mgba_libretro_android.so';
const _coreRevision = 'c6156ac820604feff1f5a51da1081e3dbce66e64';
const _maxArchive = 1024 * 1024;
const _maxCore = 8 * 1024 * 1024;

// Reviewed Libretro archives and payloads, keyed by the installed frontend ABI.
const _recipes = <String, (String, String)>{
  'arm64-v8a': (
    '126bbc51bd6ba2737e05c92b00512aa7c4b60cab60e211b23523de0ebd481c55',
    'b5a6ed40ede735ea7f1d56916f4ceed8c2aabe4d481fe3383ae2b5e5485b6545',
  ),
  'armeabi-v7a': (
    'c71a49b9c94fe3b6c1531272269f685ebc272e9d0d442d9e3a02e159c5584f49',
    'a976a807a7bd79a7dabbc42cfc02620fca17ec7011e887730e9d768689a4d651',
  ),
  'x86': (
    'c9dd8dd6e8ec430fd918114d8d0280b70884b86e72402319991cc3565a0dfb6a',
    '80fab1051294b375b9b9101d81ff4f7611f21ffcc6a658c8a5c388ba4c98ee5a',
  ),
  'x86_64': (
    '7a535185fc12d4aa7a726013811174fb109511faf96e54fa285f37266fc8b2f9',
    '946c8d859ccf1391c2bfbbc23aef8b7a27870425b0b8e689fbb30dbd3d2927e1',
  ),
};

Future<void> downloadAndroidMgba(
  Directory data,
  String abi,
  AndroidApkDownload download, {
  required void Function(int, int?) progress,
  required Future<void> Function(String stage, String sha256) publish,
}) async {
  final recipe = _recipes[abi];
  if (recipe == null)
    throw UnsupportedError('No reviewed mGBA download is available for $abi.');
  final stage = progressNonce();
  final archive = await progressFile(
    data,
    'android/mgba-stage/$stage/core.zip',
    createParents: true,
  );
  final directory = archive.parent;
  final timer = Timer(const Duration(seconds: 90), download.cancel);
  void check() {
    if (download.cancelled) throw StateError('mGBA setup cancelled.');
  }

  try {
    final url = Uri.https(
      'raw.githubusercontent.com',
      '/Broomm/broomm/$_coreRevision/vendor/android/mgba/0.11-212-7a12d6d/$abi/$_coreFile.zip',
    );
    final reply = await download.response(url), expected = reply.contentLength;
    if (expected > _maxArchive)
      throw const FormatException('The mGBA download exceeds its size limit.');
    await archive.create(exclusive: true);
    final output = await archive.open(mode: FileMode.writeOnly);
    var size = 0;
    try {
      await for (final bytes in reply.timeout(const Duration(seconds: 30))) {
        check();
        size += bytes.length;
        if (size > _maxArchive)
          throw const FormatException(
            'The mGBA download exceeds its size limit.',
          );
        await output.writeFrom(bytes);
        progress(size, expected < 0 ? null : expected);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    check();
    if (size == 0 ||
        expected >= 0 && size != expected ||
        await progressFileHash(archive) != recipe.$1)
      throw const FormatException(
        'The mGBA archive differs from the reviewed download. Try again or install the core in RetroArch.',
      );
    final zip = await ProgressZip.read(
      archive,
      maxBytes: _maxCore,
      maxEntryBytes: _maxCore,
    );
    if (zip.entries.length != 1 ||
        zip.entries.single.name != _coreFile ||
        zip.entries.single.bytes == 0)
      throw const FormatException('Unexpected files in the mGBA archive.');
    final files = await zip.extract(directory, check: check);
    if (files[_coreFile]?['sha256'] != recipe.$2)
      throw const FormatException(
        'The extracted mGBA core failed verification.',
      );
    check();
    timer.cancel();
    await publish(stage, recipe.$2);
  } finally {
    timer.cancel();
    download.client.close(force: true);
    await directory.delete(recursive: true);
  }
}
