import 'dart:io';

import 'catalogue.dart';
import 'pairing.dart';
import 'romm/models.dart';
import 'retroarch.dart';

class GamePlatform {
  const GamePlatform(
    this.slug,
    this.emulatorId,
    this.emulator,
    this.target,
    this.players,
    this.extensions, {
    this.retroCore,
  });
  final String slug, emulatorId, emulator;
  final ControllerTarget target;
  final int players;
  final List<String> extensions;
  final String? retroCore;
}

final playablePlatforms = [
  for (final s in retroSystems)
    GamePlatform(
      s.slug,
      'retroarch',
      'RetroArch',
      s.target,
      s.players,
      s.extensions,
      retroCore: s.core,
    ),
  GamePlatform('nds', 'melonds', 'melonDS', ControllerTarget.nds, 1, ['nds']),
  GamePlatform('psp', 'ppsspp', 'PPSSPP', ControllerTarget.psp, 1, [
    'iso',
    'cso',
    'pbp',
  ]),
  GamePlatform('psx', 'duckstation', 'DuckStation', ControllerTarget.psx, 2, [
    'chd',
    'cue',
    'ccd',
    'm3u',
    'pbp',
    'iso',
    'bin',
    'exe',
  ]),
  GamePlatform('ps2', 'armsx2', 'ARMSX2', ControllerTarget.ps2, 2, [
    'chd',
    'iso',
    'cso',
    'bin',
    'gz',
    'elf',
  ]),
  GamePlatform('ps2', 'pcsx2', 'PCSX2', ControllerTarget.ps2, 2, [
    'chd',
    'iso',
    'cso',
    'bin',
    'gz',
    'elf',
  ]),
  GamePlatform('snes', 'retroarch', 'RetroArch', ControllerTarget.snes, 2, [
    'sfc',
    'smc',
    'zip',
  ]),
  GamePlatform('ngc', 'dolphin', 'Dolphin', ControllerTarget.gamecube, 4, [
    'rvz',
    'iso',
    'gcm',
    'ciso',
  ]),
  GamePlatform('wii', 'dolphin', 'Dolphin', ControllerTarget.wii, 4, [
    'rvz',
    'iso',
    'wbfs',
    'wia',
    'wad',
  ]),
  GamePlatform('ps3', 'rpcs3', 'RPCS3', ControllerTarget.ps3, 4, [
    'bin',
    'iso',
  ]),
  GamePlatform('ps3', 'rpcs3-intel', 'RPCS3 Intel', ControllerTarget.ps3, 4, [
    'bin',
    'iso',
  ]),
  GamePlatform('3ds', 'azahar', 'Azahar', ControllerTarget.n3ds, 1, [
    'cci',
    '3ds',
    'cxi',
    'app',
  ]),
  GamePlatform('switch', 'ryubing', 'Ryubing', ControllerTarget.switchPro, 4, [
    'nsp',
    'xci',
    'nro',
  ]),
  GamePlatform('3ds', 'citra-mmj', 'Citra MMJ', ControllerTarget.n3ds, 1, [
    'cci',
    '3ds',
    'cxi',
    'app',
  ]),
  GamePlatform('switch', 'eden', 'Eden', ControllerTarget.switchPro, 4, [
    'nsp',
    'xci',
    'nro',
  ]),
  GamePlatform('switch', 'astris', 'Astris', ControllerTarget.switchPro, 4, [
    'nsp',
    'xci',
    'nro',
  ]),
];
GamePlatform? gamePlatform(RommGame game, List<RommPlatform> platforms) {
  final slug = game.platformSlug.isNotEmpty
      ? game.platformSlug
      : platforms.where((p) => p.id == game.platformId).firstOrNull?.slug ?? '';
  const aliases = {
    'ds': 'nds',
    'nintendo-ds': 'nds',
    'n3ds': '3ds',
    'gamecube': 'ngc',
    'nintendo-gamecube': 'ngc',
    'nintendo-switch': 'switch',
    'super-nintendo-entertainment-system': 'snes',
    'super-nintendo': 'snes',
    'ps1': 'psx',
    'playstation': 'psx',
    'playstation-2': 'ps2',
    'playstation-portable': 'psp',
  };
  final canonical = aliases[slug] ?? slug;
  final match = playablePlatforms.where((p) => p.slug == canonical).firstOrNull;
  if (match != null) return match;
  if (slug.isNotEmpty) return null;
  const names = {
    'nintendo ds': 'nds',
    'super nintendo': 'snes',
    'super nintendo entertainment system': 'snes',
    'snes': 'snes',
    'gamecube': 'ngc',
    'nintendo gamecube': 'ngc',
    'wii': 'wii',
    'nintendo wii': 'wii',
    'playstation 3': 'ps3',
    'sony playstation 3': 'ps3',
    'playstation': 'psx',
    'sony playstation': 'psx',
    'playstation 2': 'ps2',
    'sony playstation 2': 'ps2',
    'playstation portable': 'psp',
    'sony playstation portable': 'psp',
    'nintendo 3ds': '3ds',
    'nintendo switch': 'switch',
  };
  return playablePlatforms
      .where((p) => p.slug == names[game.platform.toLowerCase()])
      .firstOrNull;
}

List<GamePlatform> platformEmulators(RommPlatform platform) {
  final target = gamePlatform(
    RommGame(
      id: 0,
      name: '',
      platformId: platform.id,
      platform: platform.name,
      platformSlug: platform.slug,
    ),
    [platform],
  );
  return target == null
      ? []
      : playablePlatforms
            .where(
              (p) =>
                  p.slug == target.slug &&
                  (p.emulatorId != 'rpcs3-intel' || Platform.isMacOS) &&
                  (p.emulatorId != 'astris' || Platform.isMacOS),
            )
            .toList();
}

List<String> gameCandidates(GamePlatform platform, List<String> files) {
  files = files
      .where(
        (p) => !p
            .replaceAll('\\', '/')
            .split('/')
            .any(
              (part) =>
                  {'dlc', 'updates', 'update'}.contains(part.toLowerCase()),
            ),
      )
      .toList();
  if (platform.slug == 'ps3')
    return files
        .where(
          (p) =>
              p.toLowerCase().endsWith('.iso') ||
              p.toUpperCase().endsWith('/PS3_GAME/USRDIR/EBOOT.BIN'),
        )
        .toList();
  final matching = files
      .where(
        (p) => platform.extensions.contains(p.split('.').last.toLowerCase()),
      )
      .toList();
  if (platform.retroCore != null || platform.slug == 'psx') {
    for (final extension in ['m3u', 'cue', 'gdi', 'ccd']) {
      final sets = matching
          .where((p) => p.toLowerCase().endsWith('.$extension'))
          .toList();
      if (sets.isNotEmpty) return sets;
    }
  }
  return matching;
}

LaunchGame launchDescriptor(
  RommGame game,
  GamePlatform platform,
  String file,
) => LaunchGame(
  '${game.id}',
  game.name,
  game.platform,
  platform.emulator,
  file,
  platform.players,
  0xff539388,
  target: platform.target,
  retroCore: platform.retroCore,
);
