// Explicit developer capture for the reviewed official v0.2.1 private copy.
// Never run automatically to trust an arbitrary user replacement executable.
import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/progress/digest.dart';

Future<void> main() async {
  const bundle = 'prototype-data/eden/eden.app';
  const executable = 'Contents/MacOS/eden';
  const expected =
      '18de303111bf6181d80af8b365f27aa5b04f9ee7d28f13ce4eaa161d85cc00b7';
  if (await progressFileHash(File('$bundle/$executable')) != expected)
    throw StateError('Unreviewed Eden executable; metadata was kept.');
  final files = <String, String>{}, links = <String, String>{};
  await for (final e in Directory(
    bundle,
  ).list(recursive: true, followLinks: false)) {
    final relative = e.path.substring(bundle.length + 1);
    if (e is File) files[relative] = await progressFileHash(e);
    if (e is Link) links[relative] = await e.target();
  }
  final nm = await Process.run('/usr/bin/nm', [
    '-arch',
    'arm64',
    '$bundle/$executable',
  ]);
  if (nm.exitCode != 0) throw StateError('Eden symbols unavailable');
  final all = {
    for (final m in RegExp(
      r'^([0-9a-f]+) [A-Za-z] _(\S+)$',
      multiLine: true,
    ).allMatches(nm.stdout as String))
      m[2]!: m[1]!,
  };
  final wanted = {
    ...all.keys.where((k) => k.startsWith('SDL_') && !k.endsWith('_REAL')),
    '_ZN8QtCommon10rootObjectE',
    '_ZN8QtCommon6systemE',
    '_ZN10MainWindow11OnPauseGameEv',
    '_ZN10MainWindow11OnStartGameEv',
    '_ZN10MainWindow14OnLoadCompleteEv',
    '_ZN9EmuThread10SetRunningEb',
    '_ZN10MainWindow15UpdateMenuStateEv',
    '_ZN13LoadingScreen14OnLoadProgressEN9VideoCore17LoadCallbackStageEmm',
    '_ZNK7QWidget11isVisibleToEPKS_',
    '_ZN4Core3HID18EmulatedController7ConnectEb',
    '_ZN4Core3HID18EmulatedController10DisconnectEv',
    '_ZNK4Core3HID18EmulatedController14GetNpadButtonsEv',
    '_ZN7QWidget5closeEv',
    '_ZN16QCoreApplication4quitEv',
  };
  if (!wanted.every(all.containsKey))
    throw StateError('Missing reviewed Eden symbols');
  await File('assets/setup/eden.integrity.json')
      .writeAsString(jsonEncode({'files': files, 'links': links}));
  await File('assets/setup/eden.symbols').writeAsString(
    '${[for (final key in wanted) '${all[key]} $key'].join('\n')}\n',
  );
  const json = JsonEncoder.withIndent('  ');
  final build = File('assets/setup/tested-builds.json'),
      inventory = jsonDecode(
        await File('assets/setup/tested-builds.json').readAsString(),
      ) as Map;
  (inventory['builds'] as List).removeWhere((b) => b['id'] == 'eden');
  (inventory['builds'] as List).add({
    'id': 'eden',
    'name': 'Eden',
    'version': '0.2.1 (experimental macOS)',
    'host': 'macos-arm64',
    'architecture': 'arm64',
    'bundle': 'eden.app',
    'executable': executable,
    'sha256': expected,
    'sdl': 2,
    'sdl_library': null,
    'native': <String, String>{},
  });
  await build.writeAsString('${json.convert(inventory)}\n');
  final setup = File('tool/setup-development.json'),
      manifest = jsonDecode(
        await File('tool/setup-development.json').readAsString(),
      ) as Map;
  manifest['launchers']['eden'] = {
    'source': 'tested:eden',
    'resources': {
      'switch_firmware': 'tested:switch_firmware',
      'prod_keys': 'tested:prod_keys',
      'title_keys': 'tested:title_keys',
    },
  };
  await setup.writeAsString('${json.convert(manifest)}\n');
  stdout.writeln(
    'Captured Eden: ${files.length} files and ${links.length} links',
  );
}
