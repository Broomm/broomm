bool androidAppMediaBinding(
  Map<String, String> binding, {
  required String access,
  required String package,
  required String version,
  required String signer,
  Set<String> extra = const {},
}) {
  final keys = {
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
    ...extra,
  };
  final label = binding['label'] ?? '';
  return binding.length == keys.length &&
      binding.keys.every(keys.contains) &&
      binding['access'] == access &&
      binding['package'] == package &&
      binding['emulatorVersion'] == version &&
      binding['signer'] == signer &&
      binding['user'] == '0' &&
      binding['externalGid'] == '1078' &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(binding['build'] ?? '') &&
      RegExp(r'^1[0-9]{4}$').hasMatch(binding['uid'] ?? '') &&
      {
        '/data/user/0/$package',
        '/data/data/$package',
      }.contains(binding['dataDir']) &&
      RegExp(r'^u:object_r:app_data_file:s0(?::c[0-9]+(?:,c[0-9]+)*)?$')
          .hasMatch(label) &&
      binding['externalLabel'] ==
          label.replaceFirst('app_data_file:', 'media_rw_data_file:') &&
      ['externalDevice', 'externalInode'].every(
        (key) => RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(binding[key] ?? ''),
      );
}
