import 'pairing.dart';

import 'dart:io';

import 'progress/zip.dart';

/// Concrete Libretro recipes. Core binaries are pinned separately from the
/// frontend: changing a core must also change the save-state compatibility key.
class RetroSystem {
  const RetroSystem(
    this.slug,
    this.core,
    this.label,
    this.target,
    this.players,
    this.extensions,
  );
  final String slug, core, label;
  final ControllerTarget target;
  final int players;
  final List<String> extensions;
}

const retroSystems = [
  RetroSystem('3do', 'opera', 'Opera', ControllerTarget.pad3do, 2, [
    'iso',
    'bin',
    'chd',
    'cue',
  ]),
  RetroSystem('arcade', 'fbneo', 'FinalBurn Neo', ControllerTarget.arcade, 4, [
    'zip',
    '7z',
  ]),
  RetroSystem('atari2600', 'stella', 'Stella', ControllerTarget.atari, 2, [
    'a26',
    'bin',
    'zip',
  ]),
  RetroSystem(
    'jaguar',
    'virtualjaguar',
    'Virtual Jaguar',
    ControllerTarget.jaguar,
    2,
    ['j64', 'jag', 'rom', 'abs', 'cof', 'bin', 'prg', 'zip'],
  ),
  RetroSystem(
    'atari-jaguar-cd',
    'virtualjaguar',
    'Virtual Jaguar',
    ControllerTarget.jaguar,
    2,
    ['cue', 'cdi', 'chd'],
  ),
  RetroSystem(
    'lynx',
    'mednafen_lynx',
    'Beetle Lynx',
    ControllerTarget.lynx,
    1,
    ['lnx', 'lyx', 'bll', 'o', 'zip'],
  ),
  RetroSystem('dc', 'flycast', 'Flycast', ControllerTarget.dreamcast, 4, [
    'chd',
    'cdi',
    'gdi',
    'cue',
    'm3u',
  ]),
  RetroSystem('gb', 'gambatte', 'Gambatte', ControllerTarget.gameboy, 1, [
    'gb',
    'dmg',
    'zip',
  ]),
  RetroSystem('gbc', 'gambatte', 'Gambatte', ControllerTarget.gameboy, 1, [
    'gbc',
    'gb',
    'zip',
  ]),
  RetroSystem('gba', 'mgba', 'mGBA', ControllerTarget.gba, 1, ['gba', 'zip']),
  RetroSystem(
    'n64',
    'mupen64plus_next',
    'Mupen64Plus-Next',
    ControllerTarget.n64,
    4,
    ['n64', 'v64', 'z64', 'zip'],
  ),
  RetroSystem('nes', 'mesen', 'Mesen', ControllerTarget.nes, 2, [
    'nes',
    'fds',
    'unf',
    'unif',
    'zip',
  ]),
  RetroSystem(
    'sega32',
    'picodrive',
    'PicoDrive',
    ControllerTarget.megadrive,
    2,
    ['32x', 'bin', 'gen', 'smd', 'md', 'zip'],
  ),
  RetroSystem(
    'gamegear',
    'genesis_plus_gx',
    'Genesis Plus GX',
    ControllerTarget.masterSystem,
    1,
    ['gg', 'zip'],
  ),
  RetroSystem(
    'sms',
    'genesis_plus_gx',
    'Genesis Plus GX',
    ControllerTarget.masterSystem,
    2,
    ['sms', 'sg', 'zip'],
  ),
  RetroSystem(
    'genesis',
    'genesis_plus_gx',
    'Genesis Plus GX',
    ControllerTarget.megadrive,
    2,
    ['md', 'gen', 'smd', 'bin', 'zip'],
  ),
  RetroSystem(
    'saturn',
    'mednafen_saturn',
    'Beetle Saturn',
    ControllerTarget.saturn,
    2,
    ['chd', 'cue', 'ccd', 'toc', 'm3u'],
  ),
  RetroSystem(
    'tg16',
    'mednafen_pce_fast',
    'Beetle PCE Fast',
    ControllerTarget.pcengine,
    2,
    ['pce', 'chd', 'cue', 'ccd', 'm3u', 'zip'],
  ),
];

RetroSystem? retroSystem(String slug) =>
    retroSystems.where((s) => s.slug == slug).firstOrNull;

String retroSystemByCore(String core) =>
    retroSystems.firstWhere((s) => s.core == core).label;

String retroGameDirectory(String core, String content) {
  if (!retroSystems.any((s) => s.core == core) ||
      !RegExp(r'^[a-zA-Z0-9_-]{1,96}$').hasMatch(content)) {
    throw const FormatException('Invalid RetroArch content identity');
  }
  return 'core-data/$core/$content';
}

/// This pinned frontend names save RAM after the supplied outer archive even
/// when it loads an inner ROM. Inspect ZIP members only to reject ambiguity.
Future<String> retroSaveStem(String rom, String core) async {
  if (!rom.toLowerCase().endsWith('.zip')) return retroStateStem(rom);
  final extensions =
      retroSystems
          .where((s) => s.core == core)
          .expand((s) => s.extensions)
          .toSet()
        ..remove('zip');
  final zip = await ProgressZip.read(
    File(rom),
    maxBytes: 2 * 1024 * 1024 * 1024,
    maxEntryBytes: 2 * 1024 * 1024 * 1024,
  );
  final entries = zip.entries
      .where((e) => extensions.contains(e.name.split('.').last.toLowerCase()))
      .toList();
  if (entries.length != 1)
    throw const FormatException(
      'Use one playable ROM per ZIP or unpack this game before enabling its save integration.',
    );
  return retroStateStem(rom);
}

// State files use the outer content basename, including multi-chip arcade ZIPs.
// They do not require the single-ROM inspection used for ordinary SRAM import.
String retroStateStem(String rom) => rom
    .replaceAll('\\', '/')
    .split('/')
    .last
    .replaceFirst(RegExp(r'\.[^.]+$'), '');
