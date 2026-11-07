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

const _stellaRevision = '48b34a0671b41d9b20853cc823805af1d49f0b75';
const _stellaRecipes = <String, (String, String)>{
  'arm64-v8a': (
    '0100f75f456ac426ffc7023f0de183123347633d8af82bf86fefd04121f316e4',
    '144acc1ba3defb1ab7eae7da64d90fbe2754527aaf1fc616819afdb5758379f9',
  ),
  'armeabi-v7a': (
    '73b34ecbacb84dec6e346c8bd8a6c88db51b48df064de9b3fcdf88785cede5f4',
    '11e17d80e8b42e475e0305de50ec59768523c443f45f8e77c76897f8a13d5517',
  ),
  'x86': (
    '4c04137ed0240cde967d9d8fd4785e1ee503e2edb02916bd1bce7e89f8e9e6e1',
    'f78764ac2ff3e7d4e2a4cf5042b709002677fd3a4fc406a9ca559e0d57edf96f',
  ),
  'x86_64': (
    '6de2893dff16a79b5bcf2a1e7e75b908ab0bf3aeac626777d8923e5d06e7e78f',
    '9937d6585e1ab71b480bf08274d55f86d91dccf8c83535c27e2b5adff3e7fd83',
  ),
};

const _pceRevision = '48b34a0671b41d9b20853cc823805af1d49f0b75';
const _pceRecipes = <String, (String, String)>{
  'arm64-v8a': (
    'b766eaddcb8da5ce5af6aeb8ac4a72e54f07b9ab255461dfc3f525f2ef1e448a',
    '57c3d7ea453a892c36c482cd5d3881d94da342708d214633d05e3fba0902f9e1',
  ),
  'armeabi-v7a': (
    '2fbfffe0356dc671c3c265a2ea41b49b00502a01d61a6b09b21eb8fed7a14b9b',
    'bdfe0fee9b5698dd80b1e94255970f25a32146807a9a0d8bf582876b84b2f87d',
  ),
  'x86': (
    'fb49098504b90b9e755918637bfd6978a13a110aaed705594c524f40de26ae3d',
    '602d97f16d9f9ec59571a3bddf0fa9bd2556c09e83fd33983abb62bf40de9950',
  ),
  'x86_64': (
    'f4989731293ae00b6a2bb3fa5d3eb07089592ebe178ac095ed79e93afb84615a',
    '5774470071d3aee2504b55fbec372663fa1847457548d799d95d40a4900c5103',
  ),
};

const _genesisRevision = 'db5b758bdb057bd52c7c93b07bf4dc10a046fc16';
const _genesisRecipes = <String, (String, String)>{
  'arm64-v8a': (
    '83e86c72f4bd45030aef53e4d8649c3f84db67564020ff5ae40a55adaa0b2caa',
    'c01d7782bfdd6486710f42893138f5f521e7cd190c5c44fa2b5b76b79cc8639c',
  ),
  'armeabi-v7a': (
    '7f2358ca136080a94302b7c677d53374d82d89885bac038ec5371c25d5dd63c2',
    '134ec967580bde69d733c61b20ded28865e496dfc1589caab901d82b3cb0c416',
  ),
  'x86': (
    '7d7ea0ea6dc3349b9351f9cf37f924b82920fa4b3462773c0d0573f4f9d8d8c4',
    '9e917b6d1f5f28f3ae2c7acef03655342a11a66340f8bb73b437afd981de8942',
  ),
  'x86_64': (
    'e4619f37c2c9dc3cc8bc05c5c76e6f67ebac75817a1da84d7aeed5e592f59fb7',
    '03a8290fe10bad57309febc7da78d86112f5879f9d9731351d194f287fd32376',
  ),
};

const _picoRevision = 'db5b758bdb057bd52c7c93b07bf4dc10a046fc16';
const _picoRecipes = <String, (String, String)>{
  'arm64-v8a': (
    '97feea3a6801be6761ee325d4b56ba34ad49f69e3b46aa3076166df3bece890e',
    '92d28b94fd9381a9dea670e57d58a0f3252a99d0ffde8d310add41f81f90a4fd',
  ),
  'armeabi-v7a': (
    'ad5ed45d21027be641da7839145e9319a3fb0e5fe25ff7c1c64ccc97eab6d6ff',
    'c1cc15edda64c4a98696cd678117f989029db93ed57a53a583791524c6041cf8',
  ),
  'x86': (
    'fea141befd74f2f4143e7c4ca2bad94fe6d434ac4dca980d737dd72ddcbcc638',
    'eae3fd61842cfa9d1edede2a2e7b1a05226c66b12b6984f45af9732182afc3fd',
  ),
  'x86_64': (
    '53448e5b96e97571a436f7db5e8f2ffa0c3c15c2c94ef32248d3b011e108733a',
    '204aa87b3644d223986769f826bf9a518d220a2ea9b80b037985ef699daf195c',
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
    'stella' => (_stellaRevision, '8.0-pre-20261107', _stellaRecipes),
    'mednafen_pce_fast' => (_pceRevision, '1.31.0.0-2de1ce1', _pceRecipes),
    'genesis_plus_gx' => (_genesisRevision, '1.7.4-f27655b', _genesisRecipes),
    'picodrive' => (_picoRevision, '2.05-1890c29', _picoRecipes),
    _ => throw UnsupportedError('Unsupported Android RetroArch core.'),
  };
  final coreFile = '${core}_libretro_android.so';
  final maxArchive = {'stella', 'genesis_plus_gx'}.contains(core)
      ? 2 * 1024 * 1024
      : _maxArchive;
  final maxCore = core == 'genesis_plus_gx' ? 16 * 1024 * 1024 : _maxCore;
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
    if (expected > maxArchive)
      throw FormatException('The $core download exceeds its size limit.');
    await archive.create(exclusive: true);
    final output = await archive.open(mode: FileMode.writeOnly);
    var size = 0;
    try {
      await for (final bytes in reply.timeout(const Duration(seconds: 30))) {
        check();
        size += bytes.length;
        if (size > maxArchive)
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
      maxBytes: maxCore,
      maxEntryBytes: maxCore,
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
