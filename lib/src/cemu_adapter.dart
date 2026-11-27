part of 'emulators.dart';

class CemuAdapter extends EmulatorAdapter {
  const CemuAdapter();

  Future<void> settings(PreparedEmulator e) async {
    if (!Directory(e.user).absolute.path
            .startsWith('${Directory(e.root).absolute.path}/launcher/') ||
        !e.user.endsWith('/portable'))
      throw StateError(
        'Cemu’s private portable directory could not be verified.',
      );
    await Directory(e.user).create(recursive: true);
    await Directory('${e.root}/user/mlc01').create(recursive: true);
    final file = File('${e.user}/settings.xml');
    final source = await file.exists() ? await readCemuXml(file) : '';
    await atomicText(
      file.path,
      patchCemuSettings(source, {
        'mlc_path': '${e.root}/user/mlc01',
        'check_update': false,
        'use_discord_presence': false,
        'macos_disclaimer': true,
        'gp_download': true,
        'vk_warning': true,
      }),
    );
  }

  @override
  Future<List<String>> configurationArguments(PreparedEmulator e) async {
    await settings(e);
    return ['--mlc', '${e.root}/user/mlc01'];
  }

  @override
  Future<List<String>> prepare(
    PreparedEmulator e,
    TestGame game,
    String rom,
    int commandPort,
  ) async {
    await settings(e);
    if (e.contentId == null)
      throw StateError(
        'Cemu title inspection did not establish a save identity.',
      );
    cemuTitleId(e.contentId!);
    await Directory('${e.user}/controllerProfiles').create(recursive: true);
    await atomicText(
      '${e.user}/controllerProfiles/controller0.xml',
      cemuControllerProfile(commandPort),
    );
    return [
      '--game',
      rom,
      '--mlc',
      '${e.root}/user/mlc01',
      '--account',
      '80000001',
      if (e.remoteScreen) '--fullscreen=false',
    ];
  }
}
