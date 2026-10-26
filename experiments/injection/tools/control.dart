import 'dart:io';

import 'control-file.dart';

Future<void> main(List<String> args) async {
  if (args.length != 4 ||
      ![
        'retroarch',
        'dolphin',
        'rpcs3',
        'azahar',
        'ryubing',
      ].contains(args[0])) {
    throw ArgumentError(
      'Expected emulator-name mode(0..2) menu(0..1) pause(0..1)',
    );
  }
  final values = args.skip(1).map(int.parse).toList();
  if (values[0] < 0 ||
      values[0] > 2 ||
      values[1] < 0 ||
      values[1] > 1 ||
      values[2] < 0 ||
      values[2] > 1)
    throw ArgumentError('Invalid policy');
  await publishControl(
    '${Directory.current.path}/experiments/injection/sessions/${args[0]}/control.txt',
    values[0],
    values[1],
    values[2],
  );
}
