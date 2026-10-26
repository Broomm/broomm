part of 'emulators.dart';

Future<String> _sonyPreferences(File file) async {
  final kind = await FileSystemEntity.type(file.path, followLinks: false);
  if (kind == FileSystemEntityType.notFound) return '';
  if (kind != FileSystemEntityType.file || await file.length() > 1024 * 1024)
    throw const FileSystemException('Invalid private PlayStation settings');
  return file.readAsString();
}

Map<String, String> _sonyButtons(int port, {required bool ps2}) {
  const axes = {
    'LLeft': '-LeftX',
    'LRight': '+LeftX',
    'LUp': '-LeftY',
    'LDown': '+LeftY',
    'RLeft': '-RightX',
    'RRight': '+RightX',
    'RUp': '-RightY',
    'RDown': '+RightY',
  };
  return {
    'Type': ps2 ? 'DualShock2' : 'AnalogController',
    for (final e in {
      'Cross': 'A',
      'Circle': 'B',
      'Square': 'X',
      'Triangle': 'Y',
      'Up': 'DPadUp',
      'Down': 'DPadDown',
      'Left': 'DPadLeft',
      'Right': 'DPadRight',
      'Select': 'Back',
      'Start': 'Start',
      'L1': 'LeftShoulder',
      'R1': 'RightShoulder',
      'L2': '+LeftTrigger',
      'R2': '+RightTrigger',
      'L3': 'LeftStick',
      'R3': 'RightStick',
      ...axes,
    }.entries)
      e.key: 'SDL-$port/${e.value}',
  };
}

class DuckStationAdapter extends EmulatorAdapter {
  const DuckStationAdapter();
  @override
  Future<List<String>> configurationArguments(PreparedEmulator e) async => [];

  @override
  Future<List<String>> prepare(
    PreparedEmulator e,
    TestGame game,
    String rom,
    int commandPort,
  ) async {
    final dir = playStationGameDirectory(game.id);
    final config = File('${e.user}/settings.ini');
    final text = await _sonyPreferences(config);
    for (final path in ['$dir/cards', '$dir/states'])
      await Directory('${e.root}/$path').create(recursive: true);
    await atomicText(
      config.path,
      _patchPreferences(text, {
        'Main': {
          'SetupWizardIncomplete': 'false',
          'ConfirmPowerOff': 'false',
          'PauseOnFocusLoss': 'false',
          'PauseOnControllerDisconnection': 'false',
          'DisableBackgroundInput': 'false',
          'ApplyGameSettings': 'false',
        },
        'MemoryCards': {
          'Directory': '${e.root}/$dir/cards',
          'Card1Type': 'Shared',
          'Card1Path': 'card1.mcd',
          'Card2Type': 'Shared',
          'Card2Path': 'card2.mcd',
        },
        'Folders': {'SaveStates': '${e.root}/$dir/states'},
        'ControllerPorts': {'MultitapMode': 'Disabled'},
        'InputSources': {'SDL': 'true'},
        'Pad1': _sonyButtons(0, ps2: false),
        'Pad2': _sonyButtons(1, ps2: false),
      }),
    );
    return ['-batch', '-nofullscreen', '--', rom];
  }
}

class Ps2Adapter extends EmulatorAdapter {
  const Ps2Adapter();
  @override
  Future<List<String>> configurationArguments(PreparedEmulator e) async => [
    '-datapath',
    Directory(e.user).parent.path,
  ];

  @override
  Future<List<String>> prepare(
    PreparedEmulator e,
    TestGame game,
    String rom,
    int commandPort,
  ) async {
    final dir = playStationGameDirectory(game.id);
    final config = File('${e.user}/inis/PCSX2.ini');
    final text = await _sonyPreferences(config);
    for (final path in ['$dir/cards', '$dir/states/${e.name.toLowerCase()}'])
      await Directory('${e.root}/$path').create(recursive: true);
    await atomicText(
      config.path,
      _patchPreferences(text, {
        'UI': {
          'SettingsVersion': '1',
          'SetupWizardIncomplete': 'false',
          'ConfirmShutdown': 'false',
          'PauseOnFocusLoss': 'false',
          'PauseOnControllerDisconnection': 'false',
        },
        'Folders': {
          'MemoryCards': '${e.root}/$dir/cards',
          'Savestates': '${e.root}/$dir/states/${e.name.toLowerCase()}',
        },
        'MemoryCards': {
          'Slot1_Enable': 'true',
          'Slot1_Filename': 'slot1.ps2',
          'Slot2_Enable': 'true',
          'Slot2_Filename': 'slot2.ps2',
        },
        'Pad': {'MultitapPort1': 'false', 'MultitapPort2': 'false'},
        'InputSources': {'SDL': 'true'},
        'Pad1': _sonyButtons(0, ps2: true),
        'Pad2': _sonyButtons(1, ps2: true),
      }),
    );
    return [
      '-datapath',
      Directory(e.user).parent.path,
      '-batch',
      '-nofullscreen',
      '--',
      rom,
    ];
  }
}
