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

const _n64Revision = 'bb01c67e271a667445db4ed25881051fe4c656fa';
const _n64Recipes = <String, (String, String)>{
  'arm64-v8a': (
    'fe89e593448560efaaa46c7ed18000dab68a14dbaac2e433f10b7d1cf741d832',
    '4335b6b118873b04f7f752ed618e5690855def9263c6d4eaf2af366e647bc3c7',
  ),
  'armeabi-v7a': (
    'cec8bfd4cb36b0b95472c0f52e513366331bc6a0630fe9f0d7a45d5f4d723fb0',
    '2fd3523ecc0c36eebb1072b8356637fc7b7618747e992e691f9bf74f39ce67d7',
  ),
  'x86': (
    '0d5f29d268f59dbfb62dd1c0dff4c5304021a3ef96a1a9c4e8cb22b325cc5576',
    'a41c1d7b910aa5a3fdf2b026bfce817f149db0ade9bd55eec140cc8659f9b967',
  ),
  'x86_64': (
    '00a94dd1414f6295b84f46fb79ea09461b4c47fc40863abe0cc43fc37486a4da',
    'ead53e2302cb8c6e33a91ecce4b03f24753d9d6bfb4eae375f93b34093a4ce9e',
  ),
};

const _mesenRevision = '7a0fb0ae3ecbd0887f3fa706fcb99099c7cbf81b';
const _mesenRecipes = <String, (String, String)>{
  'arm64-v8a': (
    '4c78c6bc0a8683493524473c046e164855ae7eeb3df2dc6b7228c47dc00fa3ac',
    'ab8617e00521a68fbf518dc926fe8c077d3874ee0ebeba2013c52b0f7c192de9',
  ),
  'armeabi-v7a': (
    'a38927484e604eec78832fd72893ddb956a56080bd76cbcc39171453f267ee2d',
    '2437fbac81c0e0c4a60e5a838fb0cbb426b12cc59cdcc08926d2790c364f11f1',
  ),
  'x86': (
    'c4c7d1291f0a7ec7083af298388a5a2933148785190b15dbec0ac803606a34f5',
    '15ea57850e5033aebeead97db8d69980c72d599099d4fe437093788aca8d1ae4',
  ),
  'x86_64': (
    '5309f72faf3df8efffa5c211c548e022ff544122e173564f4aaa672aade23e0c',
    '2ddf03b51bc4bd55554a2ccf7b26dd86b914cf4876e3597b5a7a8c1bf282babd',
  ),
};

// Official tagged raw libraries; download and installed payload have the same
// digest. Do not mirror the release's embedded boot ROMs in Broomm's archives.
const _jaguarRevision = '34696082dbc0448caf23aa4ecb5ed40817cb8da0';
const _jaguarRecipes = <String, (String, String)>{
  'arm64-v8a': (
    '90446691d7f5b80f9ba98e4b311e6dab5bc8afd58431fb319b4e30933f891df6',
    '90446691d7f5b80f9ba98e4b311e6dab5bc8afd58431fb319b4e30933f891df6',
  ),
  'armeabi-v7a': (
    '3a173fbfaf62401c636591ba6a7ca16ef584481094f184c02519cffb093ec6cc',
    '3a173fbfaf62401c636591ba6a7ca16ef584481094f184c02519cffb093ec6cc',
  ),
  'x86': (
    '2303d1bee859c14c58507c4d4ad4aff7cc39d5e2a7e537b6fce519a99bacd47a',
    '2303d1bee859c14c58507c4d4ad4aff7cc39d5e2a7e537b6fce519a99bacd47a',
  ),
  'x86_64': (
    'a72da2e64da709839db26daf0b387373d7a74122d5a53c687bfb4dcda1da7266',
    'a72da2e64da709839db26daf0b387373d7a74122d5a53c687bfb4dcda1da7266',
  ),
};

// RetroArch 1.22.2 ships metadata for Virtual Jaguar 2.1, which disables
// states. Only the reviewed 3.11 payloads may override that stale metadata.
bool androidJaguarHasReviewedStates(String abi, String digest) =>
    _jaguarRecipes[abi]?.$2 == digest;

const _lynxRevision = 'a62e24ffdc352399a47516dc43cbd4f985f9c027';
const _lynxRecipes = <String, (String, String)>{
  'arm64-v8a': (
    '69ddfb1e6e94d45ee974f2f43c5bd4b6538f8b2ec49366ef4f6cd4b00268c07f',
    '26163656e3ebdad5f634057febf8d6a822a37f2bbead250a4a7a34726a438503',
  ),
  'armeabi-v7a': (
    'fc4522ca48d6dd527acc62d60e4382986e48852602eb6b327ff6e0c4644a5bbf',
    '2ef2dc14190f4af7f81ca7d80dffc5aedba559a73a8ac04345edbef9a866331d',
  ),
  'x86': (
    '75e4dff355c8374a48c80048e6246a019942737cdbead4ec3be62e4e48b78ad3',
    'a5a693783f9825eeef67ae328bf9891d63aaa253503d09cd739ee7a701ef29be',
  ),
  'x86_64': (
    'f50f320cf81061b0bc090758b057a9b9f66911d85fc4cdd863e673d35bb5f983',
    '0d5d0a3a2a19898bf42a7a7a6fbdbfe77354d5c334900daa2e06b917c6edd657',
  ),
};

String androidRetroCoreFile(String core) => core == 'mupen64plus_next'
    ? 'mupen64plus_next_gles3_libretro_android.so'
    : '${core}_libretro_android.so';

const _fbneoRevision = '299e4ce74bebac3fb7d84a49c8f065e2b3f17c49';
const _fbneoRecipes = <String, (String, String)>{
  'arm64-v8a': (
    'a99adee651498b0971bda7bf8533c096e26604eb405385d11f96a574d5a68bb7',
    '1513e3c3d79157dc7543b96b78e9aa6473c33e4427529c9320cb2250a50b41e9',
  ),
  'armeabi-v7a': (
    '196a9c37657e44f40ff4a622d76a54b5f9fb87fadc123d222c985a6d71c2ac3a',
    '4eaaa1e4298242f996bff827c22e549185ac036d25b03fc13774ca5d66a42d91',
  ),
  'x86': (
    '0b6769e7ba118aee5d8b5865b24607f69a8fc83ceea5b68b9fcc9265a07e4f13',
    'a08949f715105aa767a6773c2aab2495acb330ae48551969b9f2ab6f5496a2d0',
  ),
  'x86_64': (
    '87ee4fea74cf6df454e4c3e2ae6232ce47c785648d9fbb7f67f769f24bc6dc2f',
    '9acd7fa939b0225a5414fcfcf5e8e59d5eefec42ff504f69342d7c05bd87be50',
  ),
};

const _operaRevision = '7d8f0c9accdf3fb80985000276e3a7767756fe17';
const _operaRecipes = <String, (String, String)>{
  'arm64-v8a': (
    'ef8050e8fab1e6594e89590ca87be57924f0d37597282957c31968838a7b177f',
    '43626fab3f21e1c24d979291503f564422c4b9602a8a82a941a0484cfaceac6c',
  ),
  'armeabi-v7a': (
    '03b2ca9fb9153f69e2dc5c0bccfcf3cfdbec54ab191051a1d7afce1961a3d383',
    '817a7cb6530dd3a42546f49bb389f6a31f282df066fc147948fb0a38fa244eae',
  ),
  'x86': (
    '9e2205f82e956edafda6c815f298b8917510cf3a78fb9f56b878e89036121473',
    'f5cf8b43f0ad211dc4d98665a690c8d05bc6e7c14a929de2dfe20f18b3d1b67a',
  ),
  'x86_64': (
    '88ec7466b76b9a63bf1f1c57a52a8fb759b7023d3fd807bc6cc7cab69fb58e70',
    '8d108e8cf041047ace7e4f0c2552a0d8b1f983fa0d9e33a6643f8e356df1d486',
  ),
};

const _saturnRevision = '88b71d142171be9a44d45a61779a6fba198391f9';
const _saturnRecipes = <String, (String, String)>{
  'arm64-v8a': (
    '50f98896a7b829473beae0c6df2cd8ae2daffbb9e1ea64dfdd09270c4d2d6df8',
    'dc0c11180b695db1ace32cd3443946ff00eccf9b3c673e263ec3b752915f2282',
  ),
  'armeabi-v7a': (
    '314362993427f36bd6c3604f557161abe07fdcb0849822412ed86d5dc5cb8c39',
    'eb4874005d37847a98f45c680f9f5475681900e76fe157635de30b7f06a8b20e',
  ),
  'x86': (
    '83a55069a66b122aa184a8c8fe0a4d5a644c3eadb35523815ae4b8da751e49b9',
    'fc9e1a1c3a54cd8590338015686bd8b662aa50d0aec8983c243e922d536ba666',
  ),
  'x86_64': (
    '284be0225e9676da7ac70aba299ac81826a4fa5c4f8e4618dbb8b8ba960bb932',
    'a0e8958b2390c063f5e71c914e731ed5503a942a566a1781488710700e765d3c',
  ),
};

const _flycastRevision = 'f51373bf8b509331b884cc57917bf0c0869d43bc';
const _flycastRecipes = <String, (String, String)>{
  'arm64-v8a': (
    'de6e838bfed4abe61ee5ee325eaa9a8f6b61f483d0defa5b35dc7960f7d9a034',
    '741981f5f3c7c109d5477ec85923bbf1dd7ffe9fc9c7b2bd5b72e5834c1fa701',
  ),
  'armeabi-v7a': (
    'c6505d080565f4a972141b92f8376e99df3edf53ae515019fc27336d08145015',
    '9c4ba7b3c381d4ff3c0d15810b369548d168c7495d6a41b810ec0d6f810eaa38',
  ),
  'x86': (
    'e3b625dcef9a15ce5e4ffe8885b084187af31c3981794a7c78dc9ab6467d162b',
    'b5ba47b11b8d89a8731369a4cbb1faa3b377dafa7b8ade2ef524712c1b5f3526',
  ),
  'x86_64': (
    '646aadf89a712e141d66bce5a7c5436c7f7e39c877f9a248fdccc2fb2e90c19f',
    'a3bd3a25721ef8a4e23b2d27adf1ea4eac8087e43a9b965d154dbc20c8efe257',
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
    'mupen64plus_next' => (_n64Revision, '3.0-15bada8', _n64Recipes),
    'mesen' => (_mesenRevision, '0.9.9-0102910', _mesenRecipes),
    'virtualjaguar' => (_jaguarRevision, '3.11.0', _jaguarRecipes),
    'mednafen_lynx' => (_lynxRevision, '1.24.0-fcdefcf', _lynxRecipes),
    'fbneo' => (_fbneoRevision, '1.0.0.03-20261107', _fbneoRecipes),
    'opera' => (_operaRevision, '1.0.0-370d9a2', _operaRecipes),
    'mednafen_saturn' => (_saturnRevision, '1.32.1-30f4c12', _saturnRecipes),
    'flycast' => (_flycastRevision, '7adbf3c', _flycastRecipes),
    _ => throw UnsupportedError('Unsupported Android RetroArch core.'),
  };
  final coreFile = androidRetroCoreFile(core);
  final rawCore = core == 'virtualjaguar';
  final maxArchive = core == 'flycast'
      ? 6 * 1024 * 1024
      : core == 'fbneo'
      ? 20 * 1024 * 1024
      : rawCore || {'mupen64plus_next', 'mednafen_saturn'}.contains(core)
      ? 3 * 1024 * 1024
      : {'stella', 'genesis_plus_gx', 'mesen'}.contains(core)
      ? 2 * 1024 * 1024
      : _maxArchive;
  final maxCore = core == 'flycast'
      ? 24 * 1024 * 1024
      : core == 'fbneo'
      ? 96 * 1024 * 1024
      : {'genesis_plus_gx', 'mednafen_saturn'}.contains(core)
      ? 16 * 1024 * 1024
      : _maxCore;
  final recipe = recipes[abi];
  if (recipe == null)
    throw UnsupportedError('No reviewed $core download is available for $abi.');
  final stage = progressNonce();
  final archive = await progressFile(
    data,
    'android/$core-stage/$stage/${rawCore ? coreFile : 'core.zip'}',
    createParents: true,
  );
  final directory = archive.parent;
  final timer = Timer(const Duration(seconds: 90), download.cancel);
  void check() {
    if (download.cancelled) throw StateError('$core setup cancelled.');
  }

  try {
    final url = rawCore
        ? Uri.https(
            'github.com',
            '/libretro/virtualjaguar-libretro/releases/download/v$version/virtualjaguar_libretro-android-$abi.so',
          )
        : Uri.https(
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
        'The $core ${rawCore ? 'library' : 'archive'} differs from the reviewed download. Try again or install the core in RetroArch.',
      );
    if (!rawCore) {
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
    }
    check();
    timer.cancel();
    await publish(stage, recipe.$2);
  } finally {
    timer.cancel();
    download.client.close(force: true);
    await directory.delete(recursive: true);
  }
}
