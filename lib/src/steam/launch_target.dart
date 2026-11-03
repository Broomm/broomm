import 'dart:io';

class SteamLaunchTarget {
  const SteamLaunchTarget(this.executable, this.directory);
  final String executable;
  final String directory;

  static void validate(String value) {
    if (value.isEmpty ||
        value.length > 4096 ||
        value.contains(RegExp(r'[\x00-\x1f\x7f"]')))
      throw StateError(
        'The Broomm path contains characters Steam cannot launch. Move the full application bundle to another folder and retry.',
      );
  }

  static Future<SteamLaunchTarget> resolve({
    String? executable,
    String? operatingSystem,
  }) async {
    final os = operatingSystem ?? Platform.operatingSystem;
    if (!const ['linux', 'macos', 'windows'].contains(os))
      throw UnsupportedError('Add to Steam is available on desktop systems.');
    final file = File(executable ?? Platform.resolvedExecutable);
    if (!file.isAbsolute)
      throw StateError('Broomm must run from an absolute application path.');
    final resolved = await file.resolveSymbolicLinks();
    validate(resolved);
    if (os != 'windows' && (await File(resolved).stat()).mode & 0x49 == 0)
      throw StateError(
        'The Broomm executable is not runnable. Extract the full bundle and retry.',
      );
    if (os == 'macos') {
      final binary = File(resolved);
      final bundle = binary.parent.parent.parent;
      if (binary.parent.uri.pathSegments.where((s) => s.isNotEmpty).last !=
              'MacOS' ||
          !bundle.path.endsWith('.app') ||
          !await File('${bundle.path}/Contents/Info.plist').exists())
        throw StateError(
          'Run the packaged Broomm .app before adding it to Steam.',
        );
      validate(bundle.path);
      return SteamLaunchTarget(bundle.path, bundle.parent.path);
    }
    return SteamLaunchTarget(resolved, File(resolved).parent.path);
  }
}
