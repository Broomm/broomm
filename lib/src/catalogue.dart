import 'pairing.dart';

class LaunchGame {
  const LaunchGame(
    this.id,
    this.title,
    this.platform,
    this.emulator,
    this.rom,
    this.players,
    this.color, {
    this.target,
    this.retroCore,
  });
  final String id, title, platform, emulator, rom;
  final int players, color;
  final ControllerTarget? target;
  final String? retroCore;
  ControllerTarget get controllerTarget =>
      target ??
      switch (id) {
        'smw' => ControllerTarget.snes,
        'melee' => ControllerTarget.gamecube,
        'brawl' => ControllerTarget.wii,
        'rayman' => ControllerTarget.ps3,
        'mk7' => ControllerTarget.n3ds,
        '3dworld' => ControllerTarget.switchPro,
        _ => throw UnsupportedError('Unknown test controller: $id'),
      };
}

typedef TestGame = LaunchGame;

const testGames = [
  TestGame(
    'smw',
    'Super Mario World',
    'Super Nintendo',
    'RetroArch',
    'snes/Super Mario World (USA).sfc',
    2,
    0xff679953,
  ),
  TestGame(
    'melee',
    'Super Smash Bros. Melee',
    'Nintendo GameCube',
    'Dolphin',
    'ngc/Super Smash Bros. Melee (USA) (En,Ja).rvz',
    4,
    0xffae6647,
  ),
  TestGame(
    'brawl',
    'Super Smash Bros. Brawl',
    'Nintendo Wii',
    'Dolphin',
    'wii/Super Smash Bros. Brawl (USA, Canada) (Rev 2).rvz',
    4,
    0xff7975b4,
  ),
  TestGame(
    'rayman',
    'Rayman Legends',
    'PlayStation 3',
    'RPCS3',
    'ps3/Rayman Legends BLUS31183/PS3_GAME/USRDIR/EBOOT.BIN',
    4,
    0xff339c9e,
  ),
  TestGame(
    'mk7',
    'Mario Kart 7',
    'Nintendo 3DS',
    'Azahar',
    'n3ds/Mario Kart 7 (USA) (En,Fr,Es) (Rev 1).cci',
    1,
    0xff4272b1,
  ),
  TestGame(
    '3dworld',
    'Super Mario 3D World + Bowser’s Fury',
    'Nintendo Switch',
    'Ryubing',
    'switch/Super Mario 3D World + Bowsers Fury.nsp',
    4,
    0xffbc5669,
  ),
];
