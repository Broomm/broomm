import 'dart:io';

void main() {
  final root =
      '${Directory.current.path}/experiments/injection/sessions/azahar/user';
  for (final path in ['nand', 'sdmc', 'config', 'log', 'sysdata']) {
    Directory('$root/$path').createSync(recursive: true);
  }
  final file = File('$root/config/qt-config.ini');
  var text = file.readAsStringSync();
  text = text
      .replaceAll('firstStart=true', 'firstStart=false')
      .replaceAll('firstStart\\default=true', 'firstStart\\default=false')
      .replaceAll('confirmClose=true', 'confirmClose=false')
      .replaceAll('confirmClose\\default=true', 'confirmClose\\default=false');
  text = text
      .replaceAll(
        'check_for_update_on_start=true',
        'check_for_update_on_start=false',
      )
      .replaceAll(
        'check_for_update_on_start\\default=true',
        'check_for_update_on_start\\default=false',
      );
  const guid = 'ff0013db5669727475616c2043007601';
  for (final entry in {'button_a': 0, 'button_b': 1}.entries) {
    final key = 'profiles\\1\\${entry.key}';
    text = text.replaceAllMapped(
      RegExp('^${RegExp.escape(key)}=.*\$', multiLine: true),
      (_) =>
          '$key="engine:sdl,api:controller,guid:$guid,port:0,button:${entry.value}"',
    );
    text = text.replaceAll('$key\\default=true', '$key\\default=false');
  }
  file.writeAsStringSync(text);
}
