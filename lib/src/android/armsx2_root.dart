import 'root_media.dart';

const androidArmsx2RootPackage = 'com.armsx2';
const androidArmsx2RootVersion = '2.9.2';
const androidArmsx2RootAccess = 'root-armsx2-v1';
const androidArmsx2RootSigner =
    'df91c9ce39d3f53c9bab5f2c1e0820e761800c93f1805305b87e87486d244d5a';
const androidArmsx2RootApk =
    'https://github.com/ARMSX2/ARMSX2/releases/download/2.9.2/ARMSX2-2.9.2-legacy-armv8.0-sdk26.apk';
const androidArmsx2RootApkSha256 =
    '5603dbc218cd164a1ed1daadcf2d3a79ecb93a8e978bd845363aa415ee852fa1';

bool androidArmsx2RootBinding(Map<String, String> binding) =>
    androidAppMediaBinding(
      binding,
      access: androidArmsx2RootAccess,
      package: androidArmsx2RootPackage,
      version: androidArmsx2RootVersion,
      signer: androidArmsx2RootSigner,
    );
