import 'dart:ffi';

const broommReleaseVersion = String.fromEnvironment(
  'BROOMM_RELEASE_VERSION',
  defaultValue: '0.1.0-dev',
);
const broommReleaseTarget = String.fromEnvironment('BROOMM_RELEASE_TARGET');
const broommRepository = 'Broomm/broomm';

class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.rc]);
  final int major, minor, patch;
  final int? rc;
  static AppVersion? parse(String text) {
    if (text.length > 80) return null;
    final m = RegExp(
      r'^v?(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})(?:-rc([1-9][0-9]{0,8}))?$',
    ).firstMatch(text);
    return m == null
        ? null
        : AppVersion(
            int.parse(m[1]!),
            int.parse(m[2]!),
            int.parse(m[3]!),
            m[4] == null ? null : int.parse(m[4]!),
          );
  }

  @override
  int compareTo(AppVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final n = pair.$1.compareTo(pair.$2);
      if (n != 0) return n;
    }
    if (rc == other.rc) return 0;
    if (rc == null) return 1;
    if (other.rc == null) return -1;
    return rc!.compareTo(other.rc!);
  }

  @override
  String toString() => '$major.$minor.$patch${rc == null ? '' : '-rc$rc'}';
}

String? updateTarget(String os, Abi abi) => switch (os) {
  'macos' => 'macos-universal',
  'android' => 'android-universal',
  'windows' when abi == Abi.windowsX64 => 'windows-x64',
  'linux' when abi == Abi.linuxX64 => 'linux-x64',
  'linux' when abi == Abi.linuxArm64 => 'linux-arm64',
  _ => null,
};
String updatePackage(String version, String target) =>
    'Broomm-$version-$target.${target.startsWith('linux-')
        ? 'tar.gz'
        : target == 'android-universal'
        ? 'apk'
        : 'zip'}';

class ReleaseAsset {
  const ReleaseAsset(this.name, this.uri, this.bytes);
  final String name;
  final Uri uri;
  final int bytes;
}

class AppUpdate {
  const AppUpdate(
    this.version,
    this.target,
    this.package,
    this.checksum,
    this.record,
  );
  final AppVersion version;
  final String target;
  final ReleaseAsset package, checksum, record;
}

/// Match Teddy's stable/RC ordering and repository confinement. Broomm has no
/// Teddy/TED compatibility-family restriction: newer major/minor releases count.
AppUpdate? selectUpdate(
  List<dynamic> releases,
  String current,
  bool candidates,
  String target,
) {
  final installed = AppVersion.parse(current);
  if (installed == null) return null;
  AppUpdate? best;
  for (final release in releases) {
    if (release is! Map ||
        release['draft'] != false ||
        release['tag_name'] is! String ||
        release['assets'] is! List)
      continue;
    final version = AppVersion.parse(release['tag_name'] as String);
    if (version == null ||
        version.compareTo(installed) <= 0 ||
        best != null && version.compareTo(best.version) <= 0 ||
        !candidates && (version.rc != null || release['prerelease'] != false))
      continue;
    final assets = <String, ReleaseAsset>{};
    final duplicates = <String>{};
    for (final a in release['assets'] as List) {
      if (a is! Map ||
          a['state'] != 'uploaded' ||
          a['name'] is! String ||
          a['browser_download_url'] is! String ||
          a['size'] is! int)
        continue;
      final uri = Uri.tryParse(a['browser_download_url'] as String),
          name = a['name'] as String,
          size = a['size'] as int;
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.port != 443 ||
          size <= 0 ||
          size > 2 * 1024 * 1024 * 1024 ||
          uri.pathSegments.join('/') !=
              '$broommRepository/releases/download/v$version/$name')
        continue;
      if (assets.containsKey(name)) duplicates.add(name);
      assets[name] = ReleaseAsset(name, uri, size);
    }
    final base = 'Broomm-$version-$target',
        name = updatePackage('$version', target);
    // Broomm publishes adjacent payload.ext.sha256 and base.json records.
    final names = [name, '$name.sha256', '$base.json'];
    if (names.any((n) => !assets.containsKey(n) || duplicates.contains(n)))
      continue;
    best = AppUpdate(
      version,
      target,
      assets[name]!,
      assets['$name.sha256']!,
      assets['$base.json']!,
    );
  }
  return best;
}

String parseUpdateChecksum(String body, String name) {
  final matches = body
      .split('\n')
      .map(
        (line) => RegExp(r'^([a-fA-F0-9]{64})  (.+)$').firstMatch(line.trim()),
      )
      .where((m) => m != null && m[2] == name)
      .toList();
  if (matches.length != 1)
    throw const UpdateFailure('The release checksum is missing or ambiguous.');
  return matches.single![1]!.toLowerCase();
}
