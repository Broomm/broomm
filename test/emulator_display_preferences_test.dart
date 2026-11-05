import 'dart:io';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-display-preferences-');
  });
  tearDown(() async => root.delete(recursive: true));

  for (final mode in [true, false, null]) {
    test(
      'game launch preserves ${mode == null
          ? 'unspecified'
          : mode
          ? 'fullscreen'
          : 'windowed'} display preferences and required integration',
      () async {
        for (final name in [
          'Eden',
          'Dolphin',
          'RPCS3',
          'DuckStation',
          'PCSX2',
          'ARMSX2',
        ]) {
          final e = PreparedEmulator(
            name,
            '${root.path}/$name',
            'unused',
            3,
            null,
            null,
          );
          final (
            path,
            original,
            expectedArgs,
            inputPath,
            inputBinding,
          ) = switch (name) {
            'Eden' => (
              '${e.root}/config/eden/qt-config.ini',
              '[UI]\n${mode == null ? '' : 'fullscreen=$mode\nfullscreen\\default=false\n'}',
              ['-g', '/games/title with spaces.nsp', '-u', '0'],
              '${e.root}/config/eden/qt-config.ini',
              'player_0_button_a = engine:sdl,',
            ),
            'Dolphin' => (
              '${e.user}/Config/Dolphin.ini',
              '[Display]\n${mode == null ? '' : 'Fullscreen = ${mode ? 'True' : 'False'}\n'}',
              ['-u', e.user, '--exec', '/games/title with spaces.iso'],
              '${e.user}/Config/GCPadNew.ini',
              'Device = SDL/0/${portNames.first}',
            ),
            'RPCS3' => (
              '${e.user}/config.yml',
              '# Native preferences\nVideo:\n${mode == null ? '' : '  Start games in fullscreen mode: $mode\n'}  Resolution: 1280x720\n',
              ['/games/title with spaces/EBOOT.BIN'],
              '${e.user}/input_configs/global/Default.yml',
              'Device: ${portNames.first} 1',
            ),
            'DuckStation' => (
              '${e.user}/settings.ini',
              '[Main]\n${mode == null ? '' : 'StartFullscreen=$mode\n'}',
              ['-batch', '--', '/games/title with spaces.chd'],
              '${e.user}/settings.ini',
              'Cross = SDL-0/A',
            ),
            _ => (
              '${e.user}/inis/PCSX2.ini',
              '[UI]\n${mode == null ? '' : 'StartFullscreen=$mode\n'}',
              [
                '-datapath',
                Directory(e.user).parent.path,
                '-batch',
                '--',
                '/games/title with spaces.chd',
              ],
              '${e.user}/inis/PCSX2.ini',
              'Cross = SDL-0/A',
            ),
          };
          final settings = File(path);
          await settings.parent.create(recursive: true);
          await settings.writeAsString(original);
          if (name == 'RPCS3') {
            final gui = File('${e.user}/GuiConfigs/CurrentSettings.ini');
            await gui.parent.create(recursive: true);
            await gui.writeAsString('[main_window]\n');
          }
          final game = LaunchGame(
            '42',
            'Title',
            'test',
            name,
            expectedArgs.firstWhere((arg) => arg.startsWith('/games/')),
            1,
            0,
            target: ControllerTarget.gamecube,
          );
          final args = await EmulatorAdapter.forName(name)
              .prepare(e, game, game.rom, 12345);
          expect(args, expectedArgs, reason: name);
          final after = await settings.readAsString();
          if (name == 'RPCS3') {
            expect(after, original, reason: name);
          } else if (mode == null) {
            expect(
              after.toLowerCase(),
              isNot(contains('fullscreen')),
              reason: name,
            );
          } else {
            expect(after, contains(original.trim()), reason: name);
          }
          expect(
            await File(inputPath).readAsString(),
            contains(inputBinding),
            reason: name,
          );
        }
      },
    );
  }

  test('melonDS launches only its literal game path and retains native window geometry', () async {
    final e = PreparedEmulator(
      'melonDS',
      root.path,
      'unused',
      2,
      null,
      null,
      userDirectory: '${root.path}/launcher/portable',
      armadaDualScreen: true,
    );
    final rom = File('${root.path}/title with spaces.nds');
    final header = List<int>.filled(0x20, 0)
      ..setRange(12, 16, 'ABCD'.codeUnits);
    await rom.writeAsBytes(header);
    final config = File('${e.user}/melonDS.toml');
    await config.parent.create(recursive: true);
    const window =
        '[Instance0.Window0]\nWidth = 1200\nHeight = 800\nWindowState = 2\n';
    await config.writeAsString(window);
    final game = LaunchGame(
      '42',
      'Title',
      'nds',
      'melonDS',
      rom.path,
      1,
      0,
      target: ControllerTarget.nds,
    );
    expect(await const MelonDsAdapter().prepare(e, game, rom.path, 0), [
      rom.path,
    ]);
    expect(await config.readAsString(), contains(window.trim()));
    expect(await config.readAsString(), contains('JoystickID = 0'));
  });
}
