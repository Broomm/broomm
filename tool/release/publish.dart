// Teddy's draft -> upload all -> publish flow, with exact Broomm asset validation.
import 'dart:convert';
import 'dart:io';

import '../../lib/src/progress/digest.dart';
import 'common.dart';
import 'version.dart';

typedef GithubCommand = Future<String> Function(List<String> arguments);

Future<List<File>> validateReleaseAssets(
  Directory directory,
  String version,
  String sha,
) async {
  final expected = <String>{};
  for (final target in releaseTargets.entries) {
    final name = 'Broomm-$version-${target.key}';
    final payload = File('${directory.path}/$name.${target.value}');
    final checksum = File('${payload.path}.sha256');
    final manifest = File('${directory.path}/$name.json');
    for (final file in [payload, checksum, manifest]) {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() == 0)
        throw StateError('Missing release asset for ${target.key}.');
      expected.add(file.uri.pathSegments.last);
    }
    final record = jsonDecode(await manifest.readAsString()) as Map;
    final hash = await progressFileHash(payload);
    if (record['product'] != 'Broomm' ||
        record['version'] != version ||
        record['sha'] != sha ||
        record['target'] != target.key ||
        record['sha256'] != hash ||
        record['bytes'] != await payload.length() ||
        (await checksum.readAsString()) !=
            '$hash  ${payload.uri.pathSegments.last}\n') {
      throw StateError(
        'Release metadata/checksum does not match ${target.key}.',
      );
    }
  }
  final files = await directory.list(followLinks: false).toList();
  if (files.length != expected.length ||
      files.any(
        (f) => f is! File || !expected.contains(f.uri.pathSegments.last),
      )) {
    throw StateError(
      'Unexpected files in release staging; nothing was published.',
    );
  }
  return files.cast<File>()..sort((a, b) => a.path.compareTo(b.path));
}

Future<void> publishRelease(
  Directory directory,
  Map<String, String> env, {
  GithubCommand? invoke,
}) async {
  final gh = invoke ?? (args) => command('gh', args);
  final version = requiredEnvironment(env, 'RELEASE_VERSION');
  final tag = requiredEnvironment(env, 'RELEASE_TAG');
  final sha = requiredEnvironment(env, 'GITHUB_SHA');
  final repo = requiredEnvironment(env, 'GITHUB_REPOSITORY');
  final pre = env['PRERELEASE'] == 'true';
  if (tag != 'v$version' ||
      !releaseTagPattern.hasMatch(tag) ||
      !RegExp(r'^[0-9a-f]{40}$').hasMatch(sha) ||
      !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo) ||
      !{'true', 'false'}.contains(env['PRERELEASE']) ||
      !{'true', 'false'}.contains(env['PROMOTE'])) {
    throw const FormatException('Invalid release identity.');
  }
  final pages = jsonDecode(
    await gh(['api', 'repos/$repo/releases', '--paginate', '--slurp']),
  ) as List;
  final matches = [
    for (final page in pages)
      for (final r in page as List)
        if ((r as Map)['tag_name'] == tag) r,
  ];
  if (matches.length > 1) throw StateError('Ambiguous release record.');
  final release = matches.isEmpty ? null : matches.single;
  if (release != null && release['draft'] == false) {
    stdout.writeln('$tag is already published; its assets are unchanged.');
    return;
  }
  final files = await validateReleaseAssets(directory, version, sha);
  final notes = File('${directory.parent.path}/release-notes.txt');
  await notes.writeAsString(
    'Broomm $version\n\n'
    'Early development builds. macOS: universal app/bridges, ad-hoc signed, not notarized; '
    'the tested emulator pack is Apple Silicon. Windows: unsigned portable ZIP. '
    'Linux: x64/ARM64 tarballs; GTK 3, Secret Service and graphics drivers are host prerequisites. '
    'Android: signed universal APK, with partial external-emulator integration.\n\n'
    'Desktop managed emulator input/launch is currently verified on macOS only. '
    'Linux/Windows emulator bridges and native Android acceptance remain outstanding. '
    'Emulators, ROMs, BIOS, keys and user data are not bundled. '
    'See docs/github-releases.md and the platform support matrix for setup and limitations.\n',
  );
  if (release == null) {
    await gh([
      'release',
      'create',
      tag,
      '--repo',
      repo,
      '--target',
      sha,
      '--draft',
      '--title',
      'Broomm $version',
      '--notes-file',
      notes.path,
      if (pre) '--prerelease',
    ]);
  }
  await gh(['release', 'edit', tag, '--repo', repo, '--target', sha]);
  await gh([
    'release',
    'upload',
    tag,
    '--repo',
    repo,
    ...files.map((f) => f.path),
    '--clobber',
  ]);
  // Upload success is necessary, but also inspect the actual draft's asset set.
  final uploaded = jsonDecode(
    await gh([
      'release',
      'view',
      tag,
      '--repo',
      repo,
      '--json',
      'isDraft,assets',
    ]),
  ) as Map;
  final actual = {
    for (final a in uploaded['assets'] as List) (a as Map)['name']: a['size'],
  };
  if (uploaded['isDraft'] != true ||
      actual.length != files.length ||
      files.any((f) => actual[f.uri.pathSegments.last] != f.lengthSync())) {
    throw StateError(
      'Draft asset readback is incomplete; release remains private.',
    );
  }
  await gh([
    'release',
    'edit',
    tag,
    '--repo',
    repo,
    '--draft=false',
    '--prerelease=$pre',
    '--latest=${!pre && env['PROMOTE'] == 'true'}',
  ]);
}

Future<void> main() async {
  final env = {...Platform.environment};
  await validatePublication(
    (await File('version.txt').readAsString()).trim(),
    env,
  );
  // The publish checkout has a newer tag observation than the planning job.
  // An older rerun must not promote over a later major/minor release either.
  final tags = (await git(['tag', '--list', 'v*'])).split('\n');
  env['PROMOTE'] =
      '${env['PROMOTE'] == 'true' && canPromote(requiredEnvironment(env, 'RELEASE_VERSION'), requiredEnvironment(env, 'GITHUB_REF_NAME'), tags)}';
  await publishRelease(Directory('dist'), env);
}
