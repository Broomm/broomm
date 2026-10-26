// Explicit developer capture for the reviewed official v1.20.4 private copy.
// Never run automatically to trust an arbitrary user replacement executable.
import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/progress/digest.dart';

Future<void> main() async {
  const bundle = 'prototype-data/ppsspp/PPSSPPSDL.app';
  const executable = 'Contents/MacOS/PPSSPPSDL';
  const expected =
      'eb7b2c26a2796176249cefcc5f83991d054ca16e029a45a95ea9dc09b3b294d1';
  if (await progressFileHash(File('$bundle/$executable')) != expected)
    throw StateError('Unreviewed PPSSPP executable; metadata was kept.');
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
  if (nm.exitCode != 0) throw StateError('PPSSPP symbols unavailable');
  final all = {
    for (final m in RegExp(
      r'^([0-9a-f]+) [A-Za-z] _(\S+)$',
      multiLine: true,
    ).allMatches(nm.stdout as String))
      m[2]!: m[1]!,
  };
  const wanted = {
    '_Z16PSP_GetBootStatev',
    'g_screenManager',
    '_ZTV9EmuScreen',
    '_Z10GetUIStatev',
    '_ZN13ScreenManager3keyERK8KeyInput',
    '_ZN9EmuScreen15ProcessGameBootERK4Path',
    '_Z15Core_IsSteppingv',
    '_Z15Core_IsInactivev',
    '_Z13Core_IsActivev',
    '_Z10Core_Break11BreakReasonj',
    '_Z11Core_Resumev',
    '_Z17__CtrlPeekButtonsv',
  };
  if (!wanted.every(all.containsKey))
    throw StateError('Missing reviewed PPSSPP symbols');
  await File('assets/setup/ppsspp.integrity.json')
      .writeAsString(jsonEncode({'files': files, 'links': links}));
  await File('assets/setup/ppsspp.symbols').writeAsString(
    '${[for (final key in wanted) '${all[key]} $key'].join('\n')}\n',
  );
  const json = JsonEncoder.withIndent('  ');
  final build = File('assets/setup/tested-builds.json'),
      inventory = jsonDecode(
        await File('assets/setup/tested-builds.json').readAsString(),
      ) as Map;
  (inventory['builds'] as List).removeWhere((b) => b['id'] == 'ppsspp');
  (inventory['builds'] as List).add({
    'id': 'ppsspp',
    'name': 'PPSSPP',
    'version': '1.20.4 / 3a31057',
    'host': 'macos-arm64',
    'architecture': 'arm64',
    'bundle': 'PPSSPPSDL.app',
    'executable': executable,
    'sha256': expected,
    'sdl': 2,
    'sdl_library': 'Contents/Frameworks/SDL2.framework/Versions/A/SDL2',
    'native': <String, String>{},
  });
  await build.writeAsString('${json.convert(inventory)}\n');
  final setup = File('assets/setup/setup.json'),
      manifest = jsonDecode(
        await File('assets/setup/setup.json').readAsString(),
      ) as Map;
  manifest['launchers']['ppsspp'] = {'source': 'tested:ppsspp'};
  await setup.writeAsString('${json.convert(manifest)}\n');
  stdout.writeln(
    'Captured PPSSPP: ${files.length} files and ${links.length} links',
  );
}
