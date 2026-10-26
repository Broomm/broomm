// Explicit developer capture of the reviewed official archives after private
// ad-hoc signing. This does not accept arbitrary binaries or read user data.
import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/progress/digest.dart';

Future<void> main() async {
  const expected = {
    'duckstation':
        '9d81c03e32e864a6b27ddab039556a1708306b952066171a51c0befc3273b06e',
    'pcsx2': 'b6c2cd600ddee34a50a0637b4a6f4188b5a9e29b7d8ab4aca7078c8e6f90911d',
    'armsx2':
        'ef4a528270a035080428af6a8c5c1065a35b5383952e6e7f656f8490bffe80a7',
  };
  const versions = {
    'duckstation': '0.1-12083-g00e299795',
    'pcsx2': '2.8.2 / fd9d310 · x86_64 / Rosetta',
    'armsx2': 'nightly-20261023 / 90126bdfea',
  };
  final buildFile = File('assets/setup/tested-builds.json');
  final inventory = jsonDecode(await buildFile.readAsString()) as Map;
  final setupFile = File('assets/setup/setup.json');
  final setup = jsonDecode(await setupFile.readAsString()) as Map;
  for (final (id, name) in [
    ('duckstation', 'DuckStation'),
    ('pcsx2', 'PCSX2'),
    ('armsx2', 'ARMSX2'),
  ]) {
    final bundle = Directory('prototype-data/$id/$name.app');
    final executable = '${bundle.path}/Contents/MacOS/$name';
    if (await progressFileHash(File(executable)) != expected[id])
      throw StateError('Unreviewed $id executable; nothing trusted');
    final files = <String, String>{}, links = <String, String>{};
    await for (final entry in bundle.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = entry.path.substring(bundle.path.length + 1);
      if (entry is File)
        files[relative] = await progressFileHash(entry);
      else if (entry is Link)
        links[relative] = await entry.target();
    }
    final nm = await Process.run('/usr/bin/nm', [
      '-arch',
      id == 'pcsx2' ? 'x86_64' : 'arm64',
      executable,
    ]);
    if (nm.exitCode != 0) throw StateError('Cannot inspect reviewed $id');
    final all = <String, String>{};
    for (final m in RegExp(
      r'^([0-9a-f]+) [A-Za-z] _(\S+)$',
      multiLine: true,
    ).allMatches(nm.stdout as String))
      all[m[2]!] = m[1]!;
    final wanted = {
      'g_main_window',
      '_ZNK10MainWindow10metaObjectEv',
      if (id == 'duckstation') ...{
        'g_core_thread',
        '_ZN10CoreThread15setSystemPausedEb',
        '_ZN10CoreThread9saveStateEbi',
        '_ZN10CoreThread9loadStateERK7QString',
      } else ...{
        'g_emu_thread',
        '_ZN9EmuThread11setVMPausedEb',
        '_ZN9EmuThread15saveStateToSlotEi',
        '_ZN9EmuThread17loadStateFromSlotEib',
        if (id == 'armsx2') '_ZN9VMManager8GetStateEv',
      },
    };
    if (!wanted.every(all.containsKey))
      throw StateError(
        'Missing native symbols for $id: ${wanted.where((s) => !all.containsKey(s))}',
      );
    final native = <String, String>{};
    if (id == 'duckstation') {
      // Inspected ARM64 QtHost::IsSystemValidOrStarting and
      // MainWindow::onSystemPaused/onSystemResumed in 00e299795. These are
      // UI-thread notification fields, not the non-atomic core-thread enum.
      native['BROOMM_DUCK_VALID'] = '00000001008100e5';
      native['BROOMM_DUCK_PAUSED'] = '00000001008100e6';
    } else if (id == 'pcsx2') {
      native['BROOMM_PS2_STATE'] =
          all['_ZL7s_state.0'] ??
          (throw StateError('Missing pinned PCSX2 state'));
    }
    await File('assets/setup/$id.integrity.json')
        .writeAsString(jsonEncode({'files': files, 'links': links}));
    await File('assets/setup/$id.symbols').writeAsString(
      '${[for (final key in wanted) '${all[key]} $key'].join('\n')}\n',
    );
    (inventory['builds'] as List).removeWhere((b) => b['id'] == id);
    (inventory['builds'] as List).add(<String, dynamic>{
      'id': id,
      'name': name,
      'version': versions[id],
      'host': 'macos-arm64',
      'architecture': id == 'pcsx2' ? 'x64' : 'arm64',
      'bundle': '$name.app',
      'executable': 'Contents/MacOS/$name',
      'sha256': expected[id],
      'sdl': 3,
      'sdl_library': 'Contents/Frameworks/libSDL3.0.dylib',
      'native': native,
    });
    setup['launchers'][id] = {'source': 'tested:$id'};
    stdout.writeln(
      'Captured $id: ${files.length} files, ${links.length} links',
    );
  }
  const json = JsonEncoder.withIndent('  ');
  await buildFile.writeAsString('${json.convert(inventory)}\n');
  await setupFile.writeAsString('${json.convert(setup)}\n');
}
