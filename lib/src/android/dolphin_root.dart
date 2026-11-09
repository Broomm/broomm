import 'root_media.dart';

const androidDolphinRootAccess = 'root-dolphin-v1';
const androidDolphinRootPackage = 'org.dolphinemu.dolphinemu';
const androidDolphinRootVersion = '2609a';
const androidDolphinRootSigner =
    '8e7556d64ce8f7f15e36c4b3380aab0e326431146f9b26d2adee35326951fcab';
const androidDolphinRootApk =
    'https://dl.dolphin-emu.org/releases/2609a/dolphin-2609a.apk';
const androidDolphinRootApkSha256 =
    '7f753124d289585a4e6fa649d4852c78e674bd45d5d1f6f6b891fe65460c1793';

bool androidDolphinRootBinding(Map<String, String> binding) =>
    androidAppMediaBinding(
      binding,
      access: androidDolphinRootAccess,
      package: androidDolphinRootPackage,
      version: androidDolphinRootVersion,
      signer: androidDolphinRootSigner,
    );
