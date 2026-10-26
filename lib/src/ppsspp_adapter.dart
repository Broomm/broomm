part of 'emulators.dart';

class PpssppAdapter extends EmulatorAdapter {
  const PpssppAdapter();
  @override
  Future<List<String>> prepare(
    PreparedEmulator e,
    TestGame game,
    String rom,
    int commandPort,
  ) async {
    final system = Directory('${e.user}/PSP/SYSTEM');
    await system.create(recursive: true);
    final config = File('${system.path}/ppsspp.ini');
    await atomicText(
      config.path,
      _patchPreferences(await _sonyPreferences(config), {
        'General': {
          'FirstRun': 'False',
          'CheckForNewVersion': 'False',
          'PauseOnLostFocus': 'False',
          'Enable Logging': 'True',
          'AutoRun': 'True',
          'AutoLoadSaveState': '0',
        },
        'Control': {'ShowTouchControls': 'False'},
      }),
    );
    // These are PPSSPP's own SDL keycodes. Device 10 is logical SDL port zero,
    // verified by this build's filtered same-runtime enumeration in the bridge.
    await atomicText('${system.path}/controls.ini', '''
[ControlMapping]
Cross = 10-189
Circle = 10-190
Square = 10-191
Triangle = 10-188
Up = 10-19
Down = 10-20
Left = 10-21
Right = 10-22
Start = 10-197
Select = 10-196
L = 10-193
R = 10-192
An.Left = 10-4001
An.Right = 10-4000
An.Up = 10-4003
An.Down = 10-4002
Pause = 1-111
Save State = 1-132
Load State = 1-134
''');
    return ['--windowed', '--pause-menu-exit', rom];
  }
}
