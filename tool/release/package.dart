import 'dart:convert';
import 'dart:io';

import '../../lib/src/progress/digest.dart';
import 'common.dart';
import 'version.dart';

Future<void> validateFlutterPin() async {
  final config = jsonDecode(await File('devbox.json').readAsString()) as Map;
  final pin = ((config['packages'] as Map)['flutter'] as String).replaceFirst(
    '-sdk-links',
    '',
  );
  final sdk =
      jsonDecode(await command('flutter', ['--version', '--machine'])) as Map;
  if (sdk['frameworkVersion'] != pin)
    throw StateError('Flutter does not match devbox.json ($pin).');
}

Future<void> main() async {
  final env = Platform.environment;
  final version = requiredEnvironment(env, 'RELEASE_VERSION');
  final core = requiredEnvironment(env, 'BUILD_CORE');
  final number = requiredEnvironment(env, 'BUILD_NUMBER');
  final target =
      '${requiredEnvironment(env, 'TARGET_PLATFORM')}-${requiredEnvironment(env, 'TARGET_ARCH')}';
  final sha = requiredEnvironment(env, 'GITHUB_SHA');
  if (!releaseTargets.containsKey(target) ||
      !RegExp(
        r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(?:rc[1-9][0-9]*|pr[1-9][0-9]*\.[1-9][0-9]*))?$',
      ).hasMatch(version) ||
      core != version.split('-').first ||
      !RegExp(r'^[1-9][0-9]*$').hasMatch(number) ||
      !RegExp(r'^[0-9a-f]{40}$').hasMatch(sha))
    throw const FormatException('Invalid build identity/target.');
  await validateFlutterPin();
  final dist = Directory('dist');
  if (await dist.exists() && !await dist.list().isEmpty) {
    throw StateError(
      'dist must be empty; preserve or remove the previous build first.',
    );
  }
  await dist.create(recursive: true);
  final name = 'Broomm-$version-$target';
  final artifact = File('dist/$name.${releaseTargets[target]}');
  final args = [
    '--release',
    '--no-pub',
    '--build-name',
    core,
    '--build-number',
    number,
    '--dart-define=BROOMM_RELEASE_VERSION=$version',
    '--dart-define=BROOMM_RELEASE_TARGET=$target',
  ];
  if (target == 'macos-universal') {
    if (!Platform.isMacOS) throw StateError('A native macOS host is required.');
    await buildCommand('bash', ['tool/build_bridges.sh']);
    await buildCommand('bash', [
      'tool/build_app.sh',
      '--release',
      '--portable',
      ...args.skip(1),
    ]);
    const app = 'build/macos/Build/Products/Release/broomm.app';
    final paths = [
      'Contents/MacOS/broomm',
      'Contents/Resources/native/broomm-sdl2.dylib',
      'Contents/Resources/native/broomm-sdl3.dylib',
      'Contents/Resources/native/broomm-installer-guard.dylib',
      'Contents/Resources/native/broomm-astris.dylib',
    ];
    for (final path in paths) {
      final arches = (await command('/usr/bin/lipo', [
        '-archs',
        '$app/$path',
      ])).split(' ');
      if (!arches.contains('arm64') || !arches.contains('x86_64')) {
        throw StateError('Missing universal architecture: $path');
      }
      await command('/usr/bin/codesign', [
        '--verify',
        '--strict',
        '--all-architectures',
        '$app/$path',
      ]);
    }
    await writeBuildRecord(
      Directory('$app/Contents/Resources'),
      version,
      number,
      sha,
      target,
    );
    await command('/usr/bin/codesign', [
      '--force',
      '--sign',
      '-',
      '--preserve-metadata=entitlements,requirements,flags',
      app,
    ]);
    await command('/usr/bin/codesign', ['--verify', '--deep', '--strict', app]);
    await command('/usr/bin/ditto', [
      '-c',
      '-k',
      '--sequesterRsrc',
      '--keepParent',
      app,
      artifact.path,
    ]);
    await command('/usr/bin/unzip', ['-tq', artifact.path]);
  } else if (target.startsWith('linux-')) {
    if (!Platform.isLinux) throw StateError('A native Linux host is required.');
    final arch = target.substring(6);
    await buildCommand('bash', [
      'tool/ci/build_linux.sh',
      ...args,
      '--target-platform',
      'linux-$arch',
    ]);
    final bundle = Directory('build/linux/$arch/release/bundle');
    await buildCommand('bash', ['tool/ci/check_linux_bundle.sh', bundle.path]);
    await writeBuildRecord(bundle, version, number, sha, target);
    await command('tar', [
      '--format=ustar',
      '-czf',
      artifact.path,
      '-C',
      bundle.parent.path,
      'bundle',
    ]);
    await command('tar', ['-tzf', artifact.path]);
  } else if (target == 'windows-x64') {
    if (!Platform.isWindows)
      throw StateError('A native Windows host is required.');
    await buildCommand('flutter', [
      '--suppress-analytics',
      'build',
      'windows',
      ...args,
    ]);
    final bundle = Directory('build/windows/x64/runner/Release');
    if (!await File('${bundle.path}/broomm.exe').exists() ||
        !await File('${bundle.path}/flutter_windows.dll').exists() ||
        !await Directory('${bundle.path}/data').exists())
      throw StateError('Incomplete Windows bundle.');
    await writeBuildRecord(bundle, version, number, sha, target);
    await command(
      'pwsh',
      ['-NoProfile', '-File', 'tool/ci/archive_windows.ps1'],
      environment: {
        'BROOMM_ARCHIVE_SOURCE': bundle.absolute.path,
        'BROOMM_ARCHIVE_OUTPUT': artifact.absolute.path,
      },
    );
  } else {
    if (!Platform.isLinux)
      throw StateError('The Android CI recipe uses Linux.');
    if (env['PUBLISH_RELEASE'] == 'true') await configureAndroidSigning(env);
    await buildCommand('flutter', [
      '--suppress-analytics',
      'build',
      'apk',
      ...args,
      '--target-platform',
      'android-arm,android-arm64,android-x64',
    ]);
    final apk = File('build/app/outputs/flutter-apk/app-release.apk');
    await apk.copy(artifact.path);
    // Test builds use the existing debug key; publication requires the four secrets.
    final sdk = requiredEnvironment(env, 'ANDROID_HOME');
    await command('$sdk/build-tools/36.1.0/apksigner', [
      'verify',
      '--verbose',
      artifact.path,
    ]);
  }
  final hash = await progressFileHash(artifact);
  await File('${artifact.path}.sha256')
      .writeAsString('$hash  ${artifact.uri.pathSegments.last}\n');
  await File('dist/$name.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'schema_version': 1, 'product': 'Broomm', 'version': version, 'core': core, 'build_number': number, 'sha': sha, 'target': target, 'sha256': hash, 'bytes': await artifact.length()})}\n',
  );
  stdout.writeln(
    'Packaged ${artifact.path} (${await artifact.length()} bytes).',
  );
}

Future<void> writeBuildRecord(
  Directory directory,
  String version,
  String number,
  String sha,
  String target,
) async {
  await File('experiments/injection/SOURCES.md')
      .copy('${directory.path}/NATIVE-SOURCES.md');
  final entries = [
    'broomm-release.json',
    await for (final e in directory.list(followLinks: false))
      if (e.uri.pathSegments.where((s) => s.isNotEmpty).last !=
          'broomm-release.json')
        e.uri.pathSegments.where((s) => s.isNotEmpty).last,
  ]..sort();
  await File('${directory.path}/broomm-release.json').writeAsString(
    '${jsonEncode({'product': 'Broomm', 'version': version, 'build_number': number, 'sha': sha, 'target': target, 'entries': entries})}\n',
    flush: true,
  );
}

String javaProperty(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r')
    .replaceAll('\t', r'\t')
    .replaceAll('=', r'\=')
    .replaceAll(':', r'\:')
    .replaceAll(' ', r'\ ');

Future<void> configureAndroidSigning(Map<String, String> env) async {
  final names = [
    'ANDROID_KEYSTORE_BASE64',
    'ANDROID_KEYSTORE_PASSWORD',
    'ANDROID_KEY_ALIAS',
    'ANDROID_KEY_PASSWORD',
  ];
  if (names.any((k) => env[k] == null || env[k]!.isEmpty)) {
    throw StateError(
      'Publishing requires all four ANDROID signing secrets; see docs/github-releases.md.',
    );
  }
  final bytes = base64Decode(env[names[0]]!);
  if (bytes.isEmpty || bytes.length > 1024 * 1024)
    throw const FormatException('Invalid signing keystore.');
  final key = File('android/app/release.jks'),
      properties = File('android/key.properties');
  if (await key.exists() || await properties.exists())
    throw StateError('Signing files already exist; refusing to replace them.');
  await key.writeAsBytes(bytes, flush: true);
  await command('chmod', ['600', key.path]);
  final values = {
    'storeFile': 'release.jks',
    'storePassword': env[names[1]]!,
    'keyAlias': env[names[2]]!,
    'keyPassword': env[names[3]]!,
  };
  await properties.writeAsString(
    values.entries.map((e) => '${e.key}=${javaProperty(e.value)}\n').join(),
    flush: true,
  );
  await command('chmod', ['600', properties.path]);
}
