const androidMelonRootAccess = 'root-melonds-v1';
const androidMelonRootPackage = 'me.magnum.melonds';
const androidMelonRootVersion = '2.0.1 GH';
const androidMelonRootSigner =
    '0493bb8749289f0304cc868489dd68b930c19ccc4dce2da876bfe6b9bdbabebc';
const androidMelonRootApk =
    'https://github.com/rafaelvcaetano/melonDS-android/releases/download/2.0.1/app-gitHub-prod-release.apk';
const androidMelonRootApkSha256 =
    '646eb4564c71b0817ace6474e92c169da16630d58826c43e0fe648896311ec94';

bool androidMelonRootBinding(Map<String, String> binding) {
  const keys = {
    'access',
    'build',
    'package',
    'emulatorVersion',
    'signer',
    'uid',
    'user',
    'dataDir',
    'label',
    'externalLabel',
    'externalGid',
    'externalDevice',
    'externalInode',
    'stateDirectory',
  };
  final label = binding['label'] ?? '';
  final media = binding['externalLabel'];
  return binding.length == keys.length &&
      binding.keys.every(keys.contains) &&
      binding['access'] == androidMelonRootAccess &&
      binding['package'] == androidMelonRootPackage &&
      binding['emulatorVersion'] == androidMelonRootVersion &&
      binding['signer'] == androidMelonRootSigner &&
      binding['user'] == '0' &&
      binding['externalGid'] == '1078' &&
      {'files/saves', 'files/savestates'}.contains(binding['stateDirectory']) &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(binding['build'] ?? '') &&
      RegExp(r'^1[0-9]{4}$').hasMatch(binding['uid'] ?? '') &&
      {
        '/data/user/0/$androidMelonRootPackage',
        '/data/data/$androidMelonRootPackage',
      }.contains(binding['dataDir']) &&
      RegExp(r'^u:object_r:app_data_file:s0(?::c[0-9]+(?:,c[0-9]+)*)?$')
          .hasMatch(label) &&
      media == label.replaceFirst('app_data_file:', 'media_rw_data_file:') &&
      ['externalDevice', 'externalInode'].every(
        (key) => RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(binding[key] ?? ''),
      );
}
