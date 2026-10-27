// Capture only the official extracted application; no system settings/progress.
import 'dart:convert';
import 'dart:io';

Future<String> sha256File(String path) async {
  final r = await Process.run('/usr/bin/shasum', ['-a', '256', path]);
  if (r.exitCode != 0) throw StateError('Cannot hash bundle');
  return (r.stdout as String).split(' ').first;
}

Future<void> main(List<String> args) async {
  final bundle = Directory(args.single).absolute;
  final exe = '${bundle.path}/Contents/MacOS/melonDS';
  final hash = await sha256File(exe);
  final files = <String, String>{}, links = <String, String>{};
  await for (final entry in bundle.list(recursive: true, followLinks: false)) {
    final rel = entry.path.substring(bundle.path.length + 1);
    if (entry is File)
      files[rel] = await sha256File(entry.path);
    else if (entry is Link)
      links[rel] = await entry.target();
  }
  await File('assets/setup/melonds.integrity.json')
      .writeAsString(jsonEncode({'files': files, 'links': links}));
  final nm = await Process.run('/usr/bin/nm', ['-arch', 'arm64', exe]);
  if (nm.exitCode != 0) throw StateError('Cannot inspect melonDS');
  final symbols = RegExp(
    r'^([0-9a-f]+) [tT] _(SDL_\S+|_ZN\S*(?:QApplication|QWidget|QCoreApplication|MainWindow)\S*)$',
    multiLine: true,
  ).allMatches(nm.stdout as String).map((m) => '${m[1]} ${m[2]}').join('\n');
  await File('assets/setup/melonds.symbols').writeAsString(symbols);
  final file = File('assets/setup/tested-builds.json');
  final j = jsonDecode(await file.readAsString()) as Map;
  (j['builds'] as List).removeWhere((v) => v['id'] == 'melonds');
  (j['builds'] as List).add({
    'id': 'melonds',
    'name': 'melonDS',
    'version': '1.1',
    'host': 'macos-arm64',
    'bundle': 'melonDS.app',
    'executable': 'Contents/MacOS/melonDS',
    'sha256': hash,
    'sdl': 2,
    'native': <String, String>{},
  });
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(j)}\n',
  );
  final setup = File('tool/setup-development.json');
  final s = jsonDecode(await setup.readAsString()) as Map;
  s['launchers']['melonds'] = {'source': 'tested:melonds'};
  await setup.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(s)}\n',
  );
  stdout.writeln(
    'melonDS 1.1 $hash; ${files.length} files, ${symbols.split('\n').length} symbols',
  );
}
