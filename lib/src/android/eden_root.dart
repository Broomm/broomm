import 'root_media.dart';

const androidEdenRootPackage = 'dev.eden.eden_emulator';
const androidEdenRootVersion = '1f6734c';
const androidEdenRootAccess = 'root-eden-v1';
const androidEdenRootSigner =
    '7fca26483b2d1b3dc3e6d9bb836e2fee18f09dc644353befd2fce8606bd2a40a';
const androidEdenRootApkSha256 =
    'befbf70b1a05715811fe092ef9cf71e6f1c1672008a6c5caa31d633e99615668';

bool androidEdenRootBinding(Map<String, String> binding) =>
    androidAppMediaBinding(
      binding,
      access: androidEdenRootAccess,
      package: androidEdenRootPackage,
      version: androidEdenRootVersion,
      signer: androidEdenRootSigner,
    );
