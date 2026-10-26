import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 2)
    throw ArgumentError('Expected firmware ZIP and supplied key directory');
  final root =
      '${Directory.current.path}/experiments/injection/sessions/ryubing/user';
  final list = await Process.run('/usr/bin/unzip', ['-Z', '-1', args[0]]);
  if (list.exitCode != 0)
    throw StateError('Cannot inspect supplied firmware ZIP');
  final entries = const LineSplitter()
      .convert(list.stdout as String)
      .where((e) => e.isNotEmpty)
      .toList();
  final valid = RegExp(r'^[0-9a-f]{32}(\.cnmt)?\.nca$');
  if (entries.isEmpty ||
      entries.length > 1000 ||
      entries.toSet().length != entries.length ||
      entries.any((e) => !valid.hasMatch(e))) {
    throw StateError('Unexpected firmware archive layout');
  }
  final stage = Directory('$root/firmware-staging');
  if (stage.existsSync())
    throw StateError(
      'Firmware staging already exists; inspect previous attempt',
    );
  stage.createSync(recursive: true);
  final extract = await Process.run('/usr/bin/unzip', [
    '-qq',
    args[0],
    '-d',
    stage.path,
  ]);
  if (extract.exitCode != 0)
    throw StateError('Private firmware extraction failed');
  for (final entry in entries) {
    final source = File('${stage.path}/$entry');
    if (FileSystemEntity.typeSync(source.path, followLinks: false) !=
            FileSystemEntityType.file ||
        source.lengthSync() > 512 * 1024 * 1024) {
      throw StateError('Invalid extracted firmware entry');
    }
    final stem = entry.substring(0, 32);
    final target = Directory('$root/bis/system/Contents/registered/$stem.nca');
    target.createSync(recursive: true);
    if (File('${target.path}/00').existsSync())
      throw StateError('Firmware target already populated');
    await source.rename('${target.path}/00');
  }
  await stage.delete();
  Directory('$root/system').createSync(recursive: true);
  for (final name in ['prod.keys', 'title.keys']) {
    await File('${args[1]}/$name').copy('$root/system/$name');
    await Process.run('/bin/chmod', ['600', '$root/system/$name']);
  }
  const id = '00112233445566778899aabbccddeeff';
  await File('$root/system/Profiles.json').writeAsString(
    jsonEncode({
      'profiles': [
        {
          'user_id': id,
          'name': 'Broomm Probe',
          'image': '',
          'account_state': 'Open',
          'online_play_state': 'Closed',
        },
      ],
      'last_opened': id,
    }),
  );
  await File('$root/Config.json')
      .writeAsString('{"version":0,"check_updates_on_start":false}\n');
  stdout.writeln(
    'Prepared ${entries.length} firmware entries in the private Ryubing root; key contents are not logged.',
  );
}
