// Development-only: pin the exact already-validated local distributions.
// This reads binaries/metadata, never emulator user settings or saves.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final inventory = jsonDecode(
    await File('prototype-data/installations.json').readAsString(),
  ) as Map;
  const versions = {
    'RetroArch': '1.22.2 / 20261001 + Snes9x 1.63',
    'Dolphin': '2609',
    'RPCS3': '0.0.42-20031 d08d568d',
    'Azahar': '2126.1.2',
    'Ryubing': '1.3.3',
  };
  final builds = <Map<String, dynamic>>[];
  final launchers = <String, dynamic>{};
  for (final name in versions.keys) {
    final j = inventory['emulators'][name] as Map;
    final id = name.toLowerCase(), source = j['bundle'] as String;
    final files = <String, String>{}, links = <String, String>{};
    final paths = <String>[];
    await for (final entry in Directory(
      source,
    ).list(recursive: true, followLinks: false)) {
      final relative = entry.path.substring(source.length + 1);
      if (entry is File) {
        paths.add(entry.path);
      } else if (entry is Link) {
        links[relative] = await entry.target();
      }
    }
    for (var i = 0; i < paths.length; i += 80) {
      final result = await Process.run('/usr/bin/shasum', [
        '-a',
        '256',
        ...paths.skip(i).take(80),
      ]);
      if (result.exitCode != 0) throw StateError('Cannot hash $name');
      for (final line in const LineSplitter().convert(
        result.stdout as String,
      )) {
        final path = line.substring(66);
        files[path.substring(source.length + 1)] = line.substring(0, 64);
      }
    }
    await File('assets/setup/$id.integrity.json')
        .writeAsString(jsonEncode({'files': files, 'links': links}));
    builds.add({
      'id': id,
      'name': name,
      'version': versions[name],
      'host': 'macos-arm64',
      'bundle': Directory(source).uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last,
      'executable': (j['executable'] as String).substring(source.length + 1),
      'sha256': j['executable_sha256'],
      'sdl': j['sdl_major'],
      if (j['sdl_library'] != null)
        'sdl_library': (j['sdl_library'] as String).substring(
          source.length + 1,
        ),
      'native': j['native'],
      if (name == 'RetroArch')
        'core_sha256':
            '8ed333ac04544cc6ab67ceb445d095f7600bb17586d4887d99117fbd1ef776f6',
    });
    launchers[id] = {
      'source': 'tested:$id',
      if (name == 'RetroArch') 'core': 'tested:snes9x',
      if (name == 'RPCS3') 'resources': {'ps3_firmware': 'tested:ps3_firmware'},
      if (name == 'Ryubing')
        'resources': {
          'switch_firmware': 'tested:switch_firmware',
          'prod_keys': 'tested:prod_keys',
          'title_keys': 'tested:title_keys',
        },
    };
  }
  await File('assets/setup/tested-builds.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'schema_version': 1, 'builds': builds})}\n',
  );
  await File('assets/setup/setup.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'schema_version': 1, 'host': 'macos-arm64', 'launchers': launchers})}\n',
  );
  stdout.writeln(
    'Captured five tested application bundles and their integrity manifests.',
  );
}
