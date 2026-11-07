import 'dart:async';
import 'dart:io';

import '../progress/digest.dart';
import '../progress/files.dart';
import '../progress/zip.dart';
import 'apk_download.dart';

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

const _snesRevision = 'e95826b793c5f1ff07c87adef4fd4fbe2f76880f';
const _snesRecipes = <String, (String, String)>{
  'arm64-v8a': (
    'a8ca6cfcaf82b2e03448f95bfadcc3b34690544e3de99f4848a5bdbf3ecc668d',
    'dfd51707769000b08551e61eee4fe1a68d9e6188d62bf849c762339fa6bebcd3',
  ),
  'armeabi-v7a': (
    '09de76ea9645be3554158eea82efedb9abe9b623c46d6e6ee8046574e2f3dcda',
    '9de9b3537a32325fd58514d52a37731aae3ce4002286f909dab8292621c9abc2',
  ),
  'x86': (
    'c52cce3e619b3722647954c37ef9988a22f7ccba577316a9e3828d57e75a4153',
    'c8c98c6fb67ea59cd4dd8a0d6c5302ed9469325c8d4cb147499feb212c45b5ce',
  ),
  'x86_64': (
    '047b7834a71db47878b29792506b41cadaec6d2740014b41460844aad94a4706',
    '312f1345b2494914ed20c9717cf6a80ad06b8451773c4da4e61c262e97276beb',
  ),
};

const _gambatteRevision = 'd58888fe71f5a1975e931522d91eb2a2f22fcac7';
const _gambatteRecipes = <String, (String, String)>{
  'arm64-v8a': (
    '5f3e9b5c7e236ca78558cf1f2342680b9ca91a6e8cbf33021ed938e9d7d7cc4d',
    '940085c7a138b0ff5161c56e1e92bdab06ba9d12d29430c9b406628ed2b8aa26',
  ),
  'armeabi-v7a': (
    '3f97b0c76253238cc3ac7c1f794438c17faa918dfe95c797438a85daaaf6c0b5',
    '8c1babd7a734fa7ff85684928e2d57d20826cc2326aeb5b293382166f1148722',
  ),
  'x86': (
    '6c407b31bddb1f42703c210240dc4a9b712a505560fe8284438a23d75abae434',
    '3fcfd63fbe880591eab5005b993bd6f013ab13fa09c80b91b8fde3ca1756dda2',
  ),
  'x86_64': (
    'd971cf8d776741e68d41e7e56c39737a91b1233a6f6e9be2d99e94676bdbc059',
    '265988a3f6394de587221f3568c572a6c8289a26f402250077ff5ac008369341',
  ),
};

Future<void> downloadAndroidRetroCore(
  Directory data,
  String core,
  String abi,
  AndroidApkDownload download, {
  required void Function(int, int?) progress,
  required Future<void> Function(String stage, String sha256) publish,
}) async {
  final (revision, version, recipes) = switch (core) {
    'mgba' => (_coreRevision, '0.11-212-7a12d6d', _recipes),
    'snes9x' => (_snesRevision, '1.63-fae2fea', _snesRecipes),
    'gambatte' => (
      _gambatteRevision,
      '0.5.0-netlink-77f2567',
      _gambatteRecipes,
    ),
    _ => throw UnsupportedError('Unsupported Android RetroArch core.'),
  };
  final coreFile = '${core}_libretro_android.so';
  final recipe = recipes[abi];
  if (recipe == null)
    throw UnsupportedError('No reviewed $core download is available for $abi.');
  final stage = progressNonce();
  final archive = await progressFile(
    data,
    'android/$core-stage/$stage/core.zip',
    createParents: true,
  );
  final directory = archive.parent;
  final timer = Timer(const Duration(seconds: 90), download.cancel);
  void check() {
    if (download.cancelled) throw StateError('$core setup cancelled.');
  }

  try {
    final url = Uri.https(
      'raw.githubusercontent.com',
      '/Broomm/broomm/$revision/vendor/android/$core/$version/$abi/$coreFile.zip',
    );
    final reply = await download.response(url), expected = reply.contentLength;
    if (expected > _maxArchive)
      throw FormatException('The $core download exceeds its size limit.');
    await archive.create(exclusive: true);
    final output = await archive.open(mode: FileMode.writeOnly);
    var size = 0;
    try {
      await for (final bytes in reply.timeout(const Duration(seconds: 30))) {
        check();
        size += bytes.length;
        if (size > _maxArchive)
          throw FormatException('The $core download exceeds its size limit.');
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
      throw FormatException(
        'The $core archive differs from the reviewed download. Try again or install the core in RetroArch.',
      );
    final zip = await ProgressZip.read(
      archive,
      maxBytes: _maxCore,
      maxEntryBytes: _maxCore,
    );
    if (zip.entries.length != 1 ||
        zip.entries.single.name != coreFile ||
        zip.entries.single.bytes == 0)
      throw FormatException('Unexpected files in the $core archive.');
    final files = await zip.extract(directory, check: check);
    if (files[coreFile]?['sha256'] != recipe.$2)
      throw FormatException('The extracted $core core failed verification.');
    check();
    timer.cancel();
    await publish(stage, recipe.$2);
  } finally {
    timer.cancel();
    download.client.close(force: true);
    await directory.delete(recursive: true);
  }
}
