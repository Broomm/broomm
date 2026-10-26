import 'dart:io';

void main() {
  final dir = Directory(
    '${Directory.current.path}/experiments/injection/sessions/dolphin/user/Config',
  );
  dir.createSync(recursive: true);
  File('${dir.path}/Dolphin.ini').writeAsStringSync('''
[Interface]
ConfirmStop = False
OnScreenDisplayMessages = True
[General]
ShowLag = True
ShowFrameCount = True
[Core]
CPUThread = True
SIDevice0 = 6
SIDevice1 = 0
SIDevice2 = 0
SIDevice3 = 0
[Display]
RenderToMain = True
Fullscreen = False
[Input]
BackgroundInput = True
[Analytics]
PermissionAsked = True
Enabled = False
''');
  File('${dir.path}/GFX.ini').writeAsStringSync('''
[Settings]
ShowFPS = True
[Hardware]
VSync = False
''');
  File('${dir.path}/GCPadNew.ini').writeAsStringSync('''
[GCPad1]
Device = SDL/0/Broomm Probe A
Buttons/A = `Button A`
Buttons/B = `Button B`
Buttons/Start = `Start`
Main Stick/Left = `Left X-`
Main Stick/Right = `Left X+`
Main Stick/Up = `Left Y+`
Main Stick/Down = `Left Y-`
''');
}
