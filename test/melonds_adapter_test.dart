import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/emulators.dart';

void main() {
  const values = {
    'Emu': {'DirectBoot': 'true', 'ExternalBIOSEnable': 'false'},
    'Instance0': {'JoystickID': '0', 'SaveFilePath': '"private saves"'},
    'Instance0.Joystick': {'A': '1', 'B': '0'},
  };
  test('melonDS preparation preserves native preferences while replacing only managed input and storage settings', () {
    const original = '''# Native user preferences
[Video]
Renderer = 2
[Emu]
DirectBoot = false
ExternalBIOSEnable = true
[Instance0]
JoystickID = 4
SaveFilePath = "other saves"
Volume = 98
[Instance0.Joystick]
A = 5
B = 7
''';
    final result = patchMelonDsConfig(original, values);
    expect(result, contains('[Video]\nRenderer = 2'));
    expect(result, contains('Volume = 98'));
    expect(result, contains('DirectBoot = false'));
    expect(result, contains('ExternalBIOSEnable = true'));
    expect(result, contains('JoystickID = 0'));
    expect(result, contains('SaveFilePath = "private saves"'));
    expect(patchMelonDsConfig(result, values), result);
  });
  test('ambiguous native managed tables or keys fail before a replacement can be written', () {
    for (final original in [
      '[Instance0]\nJoystickID = 1\nJoystickID = 2\n',
      '[Instance0]\nJoystickID = 1\n[Instance0]\nJoystickID = 2\n',
    ]) {
      expect(() => patchMelonDsConfig(original, values), throwsStateError);
    }
  });
}
