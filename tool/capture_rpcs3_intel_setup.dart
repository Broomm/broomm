// Development-only inventory of the reviewed official Intel counterpart of
// RPCS3 d08d568d. This never trusts arbitrary replacements or reads user data.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final bundle = Directory(args.single).absolute;
  final executable = '${bundle.path}/Contents/MacOS/rpcs3';
  const expected =
      '6149f4458f3de4b087dc9aa7e8d0e951ce2ad64527d8ac545f30ff16a01f0a42';
  final files = <String, String>{}, links = <String, String>{};
  final paths = <String>[];
  await for (final entry in bundle.list(recursive: true, followLinks: false)) {
    final relative = entry.path.substring(bundle.path.length + 1);
    if (entry is File) paths.add(entry.path);
    if (entry is Link) links[relative] = await entry.target();
  }
  paths.sort();
  for (var i = 0; i < paths.length; i += 80) {
    final result = await Process.run('/usr/bin/shasum', [
      '-a',
      '256',
      ...paths.skip(i).take(80),
    ]);
    if (result.exitCode != 0) throw StateError('Cannot inventory Intel RPCS3');
    for (final line in const LineSplitter().convert(result.stdout as String))
      files[line.substring(66 + bundle.path.length + 1)] = line.substring(
        0,
        64,
      );
  }
  if (files['Contents/MacOS/rpcs3'] != expected)
    throw StateError(
      'This is not the reviewed d08d568d Intel build. Nothing was trusted.',
    );
  final nm = await Process.run('/usr/bin/nm', ['-arch', 'x86_64', executable]);
  if (nm.exitCode != 0) throw StateError('Cannot inspect Intel RPCS3');
  final symbols = nm.stdout as String;
  final wanted = [
    '_ZN11main_window13OnPlayOrPauseEv',
    '_ZNK11main_window10metaObjectEv',
  ];
  final addresses = <String, String>{};
  for (final match in RegExp(
    r'^([0-9a-f]+) [TS] _(\S+)$',
    multiLine: true,
  ).allMatches(symbols))
    if ([...wanted, 'Emu'].contains(match[2])) addresses[match[2]!] = match[1]!;
  if (addresses.length != 3)
    throw StateError('Reviewed Qt/state symbols are missing');
  await File('assets/setup/rpcs3-intel.integrity.json')
      .writeAsString(jsonEncode({'files': files, 'links': links}));
  await File('assets/setup/rpcs3-intel.symbols').writeAsString(
    '${wanted.map((name) => '${addresses[name]} $name').join('\n')}\n',
  );
  final tested = File('assets/setup/tested-builds.json');
  final j = jsonDecode(await tested.readAsString()) as Map;
  (j['builds'] as List).removeWhere((b) => b['id'] == 'rpcs3-intel');
  (j['builds'] as List).add({
    'id': 'rpcs3-intel',
    'name': 'RPCS3 Intel',
    'version': '0.0.42-20031 d08d568d · x86_64 / Rosetta',
    'host': 'macos-arm64',
    'architecture': 'x64',
    'bundle': 'RPCS3.app',
    'executable': 'Contents/MacOS/rpcs3',
    'sha256': expected,
    'sdl': 3,
    'sdl_library': 'Contents/Frameworks/libSDL3.0.dylib',
    'native': {'BROOMM_EMU_STATUS': addresses['Emu']},
  });
  const encoder = JsonEncoder.withIndent('  ');
  await tested.writeAsString('${encoder.convert(j)}\n');
  final setup = File('tool/setup-development.json');
  final plan = jsonDecode(await setup.readAsString()) as Map;
  plan['launchers']['rpcs3-intel'] = {
    'source': 'tested:rpcs3-intel',
    'resources': {'ps3_firmware': 'tested:ps3_firmware'},
  };
  await setup.writeAsString('${encoder.convert(plan)}\n');
  stdout.writeln(
    'Inventoried official Intel RPCS3: ${files.length} files, ${links.length} links.',
  );
}
