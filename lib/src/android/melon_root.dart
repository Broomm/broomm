import 'root_media.dart';

const androidMelonRootAccess = 'root-melonds-v1';
const androidMelonRootPackage = 'me.magnum.melonds';
const androidMelonRootVersion = '2.0.1 GH';
const androidMelonRootSigner =
    '0493bb8749289f0304cc868489dd68b930c19ccc4dce2da876bfe6b9bdbabebc';
const androidMelonRootApk =
    'https://github.com/rafaelvcaetano/melonDS-android/releases/download/2.0.1/app-gitHub-prod-release.apk';
const androidMelonRootApkSha256 =
    '646eb4564c71b0817ace6474e92c169da16630d58826c43e0fe648896311ec94';

bool androidMelonRootBinding(Map<String, String> binding) =>
    {'files/saves', 'files/savestates'}.contains(binding['stateDirectory']) &&
    androidAppMediaBinding(
      binding,
      access: androidMelonRootAccess,
      package: androidMelonRootPackage,
      version: androidMelonRootVersion,
      signer: androidMelonRootSigner,
      extra: const {'stateDirectory'},
    );
