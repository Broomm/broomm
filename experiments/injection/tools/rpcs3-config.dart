import 'dart:io';

void main() {
  final root =
      '${Directory.current.path}/experiments/injection/sessions/rpcs3/portable';
  final dir = Directory('$root/input_configs/global');
  dir.createSync(recursive: true);
  File('${dir.path}/Default.yml').writeAsStringSync('''
Player 1 Input:
  Handler: SDL
  Device: Broomm Probe A 1
  Config:
    Cross: A
    Circle: B
    Start: Start
Player 2 Input:
  Handler: Null
Player 3 Input:
  Handler: Null
Player 4 Input:
  Handler: Null
Player 5 Input:
  Handler: Null
Player 6 Input:
  Handler: Null
Player 7 Input:
  Handler: Null
''');
  File('$root/input_configs.yml').writeAsStringSync('''
Active Configurations:
  global: Default
''');
}
