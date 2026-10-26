import 'dart:io';

Future<void> publishControl(String path, int mode, int menu, int pause) async {
  final stage = File('$path.$pid.tmp');
  await stage.writeAsString('$mode $menu $pause\n', flush: true);
  await stage.rename(path);
}
