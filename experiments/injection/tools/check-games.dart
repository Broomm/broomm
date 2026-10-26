import 'dart:io';

// Re-run the already prepared private fixtures. Firmware setup is explicit and
// separate; this never discovers/downloads keys, firmware, ROMs or emulators.
Future<void> main(List<String> args) async {
  if (args.length != 1 || !File(args[0]).existsSync()) {
    throw ArgumentError('Expected the existing Snes9x libretro core path');
  }
  final root = Directory.current.path;
  final tool = '$root/experiments/injection/tools';
  final runs = <String, List<String>>{
    'RetroArch': [
      '-v',
      '-c',
      '$root/experiments/injection/sessions/retroarch/retroarch.cfg',
      '-L',
      File(args[0]).absolute.path,
      '$root/roms/snes/Super Mario World (USA).sfc',
    ],
    'Dolphin': [
      '--exec',
      '$root/roms/ngc/Super Smash Bros. Melee (USA) (En,Ja).rvz',
    ],
    'RPCS3': [
      '$root/roms/ps3/Rayman Legends BLUS31183/PS3_GAME/USRDIR/EBOOT.BIN',
    ],
    'Azahar': ['$root/roms/n3ds/Mario Kart 7 (USA) (En,Fr,Es) (Rev 1).cci'],
    'Ryubing': ['$root/roms/switch/Super Mario 3D World + Bowsers Fury.nsp'],
  };
  for (final entry in runs.entries) {
    final child = await Process.start(Platform.resolvedExecutable, [
      '$tool/run.dart',
      'run',
      entry.key,
      ...entry.value,
    ]);
    final streams = [
      stdout.addStream(child.stdout),
      stderr.addStream(child.stderr),
    ];
    final status = await child.exitCode;
    await Future.wait(streams);
    if (status != 0)
      throw StateError('${entry.key} fixture supervisor failed: $status');
  }
}
