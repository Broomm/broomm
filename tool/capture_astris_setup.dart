// Explicit capture of the inspected official release, never automatic trust of
// imported emulator replacements. The downloaded DMG is the source anchor.
import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/setup/astris.dart';

Future<void> main() async {
  const root = '.tool-cache/research/astris-citra';
  const sourceHash =
      '661f01a47816b3baeda5c6c924f92d32e7a2bf42db98483c259207f0eb5feb6f';
  const libraryHash =
      'dc0d0e6c9fc6664897cbdb21f82a5987dceac5ff1bb926b3bbefb06266532088';
  final bundle = Directory('$root/Astris.app');
  if (await progressFileHash(File('$root/Astris.dmg')) != sourceHash ||
      await progressFileHash(
            File('${bundle.path}/Contents/Frameworks/libryujinx.dylib'),
          ) !=
          libraryHash)
    throw StateError('Unreviewed Astris inputs; trusted metadata was kept.');
  await prepareAstris(bundle);
  final files = <String, String>{}, links = <String, String>{};
  await for (final entity in bundle.list(recursive: true, followLinks: false)) {
    final path = entity.path.substring(bundle.path.length + 1);
    if (entity is File) files[path] = await progressFileHash(entity);
    if (entity is Link) links[path] = await entity.target();
  }
  final hash = files['Contents/MacOS/Astris']!;
  final source = {
    'url': 'https://github.com/V380-Ori/Astris.Binaries/releases/download/astris-1.0.32/Astris-1.0.32%2B2398e7c80.dmg',
    'sha256': sourceHash,
    'bytes': 12924928,
    'format': 'dmg',
    'entry': 'Astris.app',
    'prepare': 'macos-astris',
  };
  const json = JsonEncoder.withIndent('  ');
  await File('assets/setup/astris.integrity.json')
      .writeAsString('${json.convert({'files': files, 'links': links})}\n');
  await File('assets/setup/astris.symbols').writeAsString('');
  final file = File('assets/setup/tested-builds.json'),
      builds = jsonDecode(await file.readAsString()) as Map;
  (builds['builds'] as List).removeWhere((b) => b['id'] == 'astris');
  (builds['builds'] as List).add({
    'id': 'astris',
    'name': 'Astris',
    'version': '1.0.32+2398e7c80 · macOS 15+',
    'host': 'macos-arm64',
    'architecture': 'arm64',
    'bundle': 'Astris.app',
    'executable': 'Contents/MacOS/Astris',
    'sha256': hash,
    'sdl': 0,
    'source_package': source,
    'native': <String, String>{},
  });
  await file.writeAsString('${json.convert(builds)}\n');
  final setup = File('assets/setup/setup.json'),
      manifest = jsonDecode(await setup.readAsString()) as Map;
  manifest['launchers']['astris'] = {'source': source};
  await setup.writeAsString('${json.convert(manifest)}\n');
  stdout.writeln(
    'Astris: ${files.length} files, ${links.length} links; executable $hash',
  );
}
