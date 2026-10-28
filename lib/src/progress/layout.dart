import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../addons/three_ds.dart';
import '../session.dart';
import '../romm/transfer.dart';
import 'files.dart';
import 'digest.dart';
import 'ryubing.dart';
import 'eden.dart';
import '../nintendo_ds.dart';
import '../ps3_disc.dart';
import '../retroarch.dart';
import '../retroarch_saves.dart';
import '../playstation.dart';
import '../psp.dart';
import '../sony_sfo.dart';
import '../addons/wii.dart';
import '../addons/package_profile.dart';

/// A native save boundary, derived from the actual game rather than its title.
/// Remote paths are never used as native paths without passing this boundary.
class ProgressArea {
  const ProgressArea(
    this.id,
    this.path, {
    this.prefix,
    this.suffix,
    this.folderPrefix,
    this.exact,
    this.gciId,
    this.pattern,
    this.excluded = const {},
  });
  final String id, path;
  final Set<String> excluded;
  final String? prefix, suffix, folderPrefix, exact, gciId, pattern;
  bool accepts(String relative) =>
      !excluded.contains(relative) &&
      (prefix == null ||
          (!relative.contains('/') && relative.startsWith(prefix!))) &&
      (suffix == null || relative.endsWith(suffix!)) &&
      (pattern == null || RegExp(pattern!).hasMatch(relative)) &&
      (exact == null || relative == exact) &&
      (gciId == null || !relative.contains('/')) &&
      (folderPrefix == null ||
          (relative.contains('/') &&
              relative.split('/').first.startsWith(folderPrefix!)));
  String logical(String native) =>
      prefix == null ? native : 'game${native.substring(prefix!.length)}';
  String native(String logical) => prefix == null
      ? logical
      : logical.startsWith('game')
      ? '$prefix${logical.substring(4)}'
      : throw const FormatException('Invalid game save name');
}

class ProgressLayout {
  const ProgressLayout(
    this.root,
    this.format,
    this.game,
    this.areas, {
    this.note,
    this.archiveOnly = false,
    this.rawSave,
  });
  final String root, format, game;
  final List<ProgressArea> areas;
  final String? note;
  final bool archiveOnly;
  final String? rawSave;
  String? get rawSaveKey =>
      rawSave ??
      switch (format) {
        'melonds-sav-v1' => 'save/game.sav',
        'snes9x-sram-v1' => 'save/game.srm',
        'duckstation-cards-v1' => 'save/card1.mcd',
        'ps2-cards-v1' => 'save/slot1.ps2',
        _
            when format.startsWith('libretro-') &&
                areas.any((a) => a.id == 'save' && a.prefix != null) &&
                format != 'libretro-flycast-v1' =>
          'save/game.srm',
        _ => null,
      };
  String get identity => '$format:$game';
  ProgressArea area(String id) => areas.firstWhere(
    (a) => a.id == id,
    orElse: () => throw const FormatException(
      'This save contains an unsupported progress area',
    ),
  );
  Future<File> target(String key) async {
    if (archiveOnly)
      throw StateError(
        'A retained snapshot cannot write native emulator files',
      );
    progressRelative(key);
    final slash = key.indexOf('/');
    if (slash < 1) throw const FormatException('Invalid progress entry');
    final a = area(key.substring(0, slash));
    final relative = a.native(key.substring(slash + 1));
    progressRelative(relative);
    if (!a.accepts(relative))
      throw const FormatException('Save does not belong to this game');
    return progressFile(
      Directory(root),
      '${a.path}/$relative',
      createParents: true,
    );
  }

  Future<Map<String, File>> files() async {
    if (archiveOnly)
      throw StateError(
        'A retained snapshot cannot inspect native emulator files',
      );
    final result = <String, File>{};
    var total = 0;
    for (final a in areas) {
      final path = await progressFile(
        Directory(root),
        '${a.path}/.probe',
        createParents: true,
      );
      final dir = path.parent;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        final relative = e.path
            .substring(dir.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        if (e is Directory) continue;
        if (!a.accepts(relative)) continue;
        progressRelative(relative);
        if (e is! File ||
            await FileSystemEntity.type(e.path, followLinks: false) !=
                FileSystemEntityType.file)
          throw const FileSystemException(
            'A game save contains a link or unsupported file',
          );
        if (a.gciId != null && !await progressGciMatches(e, a.gciId!)) continue;
        final n = await e.length();
        total += n;
        if (n > progressMaxFileBytes ||
            total > progressMaxBytes ||
            result.length >= progressMaxFiles)
          throw const FileSystemException(
            'Game progress exceeds the supported save bundle limits',
          );
        result['${a.id}/${a.logical(relative)}'] = e;
      }
    }
    return result;
  }
}

Future<ProgressLayout> gameProgressLayout(
  ResolvedSession session,
  String platform, {
  DownloadCancellation? cancellation,
}) async {
  cancellation?.check();
  final e = session.emulator;
  final root = Directory(e.root);
  final ownership = await progressJson(File('${root.path}/profile.json'));
  if (ownership['version'] != 1 ||
      ownership['emulator'] !=
          (isPs2Emulator(e.name) ? 'ps2' : e.name.toLowerCase()))
    throw const FileSystemException(
      'The private emulator profile is not recognized',
    );
  final user = e.user.replaceAll('\\', '/');
  final base = root.path.replaceAll('\\', '/');
  if (!user.startsWith('$base/'))
    throw const FileSystemException('Emulator save storage is outside Broomm');
  final u = user.substring(base.length + 1);
  final psp = e.name == 'PPSSPP' ? await pspGameMetadata(session.rom) : null;
  final stateBuild = ProgressDigest.sha256()
    ..add(
      utf8.encode(
        '${session.buildHash}:${session.coreHash ?? 'integrated'}${psp == null ? '' : ':${psp['DISC_VERSION']}'}',
      ),
    );
  final state =
      'states-${stateBuild.finish().substring(0, 16)}-${Platform.operatingSystem}-${Platform.version.contains('arm64') ? 'arm64' : 'native'}';
  switch (e.name) {
    case 'PPSSPP':
      if (platform != 'psp')
        throw const FormatException('PSP game platform differs');
      final id = psp!['DISC_ID']!, version = psp['DISC_VERSION'] ?? '1.00';
      if (!RegExp(r'^[0-9]{1,2}\.[0-9]{2}$').hasMatch(version))
        throw const FormatException(
          'The PSP game has no supported native disc version',
        );
      if (await progressExists('${root.path}/.psp-addon-transaction'))
        throw const FileSystemException(
          'Finish installing PSP updates/DLC before synchronizing saves. Progress was kept.',
        );
      final owned = await PackageProfile(root, 'psp').ownership();
      final excluded = <String>{
        for (final path in (owned['files'] as Map).keys.cast<String>())
          if (path.startsWith('PSP/SAVEDATA/'))
            path.substring('PSP/SAVEDATA/'.length),
      };
      return ProgressLayout(
        root.path,
        'ppsspp-savedata-v1',
        id,
        [
          ProgressArea(
            'save',
            '$u/PSP/SAVEDATA',
            folderPrefix: id,
            excluded: excluded,
          ),
          ProgressArea(
            state,
            '$u/PSP/PPSSPP_STATE',
            prefix: '${id}_${version}_',
            pattern: r'^[^/]+\.(?:undo\.)?(?:ppst|jpg)$',
          ),
        ],
        note: 'PSP saves are native SAVEDATA directories in a ZIP. Installed DLC files are excluded. States require the same PPSSPP build, host and disc version.',
      );
    case 'DuckStation':
      if (platform != 'psx' || e.contentId == null)
        throw const FormatException('PS1 game identity differs');
      final dir = playStationGameDirectory(e.contentId!);
      return ProgressLayout(
        root.path,
        'duckstation-cards-v1',
        e.contentId!,
        [
          ProgressArea('save', '$dir/cards', pattern: r'^card[12]\.mcd$'),
          ProgressArea(
            state,
            '$dir/states',
            pattern: r'^[^/]+\.sav(?:\.bak)?$',
          ),
        ],
        note: 'Private whole PS1 memory cards (.mcd). Individual game exports need conversion. Save states require the exact DuckStation build.',
      );
    case 'PCSX2':
    case 'ARMSX2':
      if (platform != 'ps2' || e.contentId == null)
        throw const FormatException('PS2 game identity differs');
      final dir = playStationGameDirectory(e.contentId!);
      return ProgressLayout(
        root.path,
        'ps2-cards-v1',
        e.contentId!,
        [
          ProgressArea('save', '$dir/cards', pattern: r'^slot[12]\.ps2$'),
          ProgressArea(
            state,
            '$dir/states/${e.name.toLowerCase()}',
            pattern: r'^[^/]+\.p2s(?:\.backup)?$',
          ),
        ],
        note: 'Private whole PS2 cards (.ps2), shared between PCSX2 and ARMSX2 for this profile/game. States remain specific to the exact emulator/build. Individual .psu/.psv exports require conversion.',
      );
    case 'Eden':
      if (platform != 'switch')
        throw const FormatException('Switch game platform differs');
      return edenProgressLayout(session, u, cancellation: cancellation);
    case 'Ryubing':
      return ryubingProgressLayout(session, u, cancellation: cancellation);
    case 'melonDS':
      final file = File(session.rom);
      final id = await dsSaveIdentity(session.rom);
      final stem = file.uri.pathSegments.last.replaceFirst(
        RegExp(r'\.[^.]+$'),
        '',
      );
      return ProgressLayout(
        root.path,
        'melonds-sav-v1',
        id,
        [
          ProgressArea('save', 'saves/$id', prefix: stem, exact: '$stem.sav'),
          ProgressArea(state, 'states/$id', prefix: '$stem.ml'),
        ],
        note: 'Imports accept a raw Nintendo DS .sav or a ZIP containing one raw .sav. DeSmuME/Drastic containers must be exported to raw first.',
      );
    case 'RetroArch':
      if (e.coreId != null) {
        final spec = retroSystem(platform);
        if (spec == null || spec.core != e.coreId || session.coreHash == null) {
          throw const FormatException(
            'RetroArch platform/core identity differs',
          );
        }
        final dir = retroGameDirectory(e.coreId!, e.contentId!);
        final simple = {
          'gambatte',
          'mgba',
          'mesen',
          'genesis_plus_gx',
          'picodrive',
          'stella',
          'virtualjaguar',
          'mednafen_lynx',
          'mupen64plus_next',
          'mednafen_pce_fast',
        }.contains(e.coreId);
        final stem = simple
            ? await retroSaveStem(session.rom, e.coreId!)
            : null;
        return ProgressLayout(
          root.path,
          'libretro-${e.coreId}-v1',
          e.contentId!,
          [
            ProgressArea(
              'save',
              '$dir/saves',
              prefix: stem,
              suffix: e.coreId == 'flycast' ? '.bin' : null,
              pattern: e.coreId == 'flycast'
                  ? r'^[^/]+\.[A-D][12]\.bin$'
                  : null,
            ),
            ProgressArea(
              state,
              e.retroStateDirectory ?? '$dir/states',
              prefix: e.retroNativeStateNames
                  ? '${retroStateStem(session.rom)}.state'
                  : e.coreId == 'flycast'
                  ? '${await retroSaveStem(session.rom, e.coreId!)}.state'
                  : 'game.state',
            ),
          ],
          rawSave: e.coreId == 'opera'
              ? await operaRawSaveKey(root.path, session.rom)
              : null,
          note: 'Native Libretro save data; multi-file saves and RTC/VMU data are kept together. States require this exact core build.',
        );
      }
      if (platform != 'snes')
        throw UnsupportedError(
          'Cloud saves are not validated for this RetroArch core yet.',
        );
      final filename = File(session.rom).uri.pathSegments.last;
      if (filename.toLowerCase().endsWith('.zip'))
        throw UnsupportedError(
          'Cloud save filenames for packed SNES games are not validated. Use an unpacked .sfc/.smc; local progress is retained.',
        );
      final stem = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final legacy = await progressExists('${root.path}/saves/$stem.srm');
      if (legacy)
        throw UnsupportedError(
          'A legacy Snes9x save exists outside the tested Snes9x folder. It has been kept; reconcile that file before enabling cloud sync.',
        );
      return ProgressLayout(root.path, 'snes9x-sram-v1', 'snes', [
        ProgressArea('save', 'saves/Snes9x', prefix: stem, exact: '$stem.srm'),
        if (session.coreHash != null)
          ProgressArea(state, 'states/Snes9x', prefix: '$stem.state'),
      ]);
    case 'Azahar':
      final id = await readThreeDsGameId(session.rom);
      const zeros = '00000000000000000000000000000000';
      final sd = '$u/sdmc/Nintendo 3DS/$zeros/$zeros';
      final ext = await _threeDsExtdata(session.rom, id);
      return ProgressLayout(root.path, 'azahar-data-v1', id, [
        ProgressArea('save', '$sd/title/00040000/${id.substring(8)}/data'),
        for (final eid in ext)
          ProgressArea('ext-$eid', '$sd/extdata/00000000/$eid'),
        ProgressArea(
          state,
          '$u/states',
          prefix: '${id.toUpperCase()}.',
          suffix: '.cst',
        ),
      ]);
    case 'Dolphin':
      if (platform == 'wii' && session.rom.toLowerCase().endsWith('.wad')) {
        final wad = await readWiiWad(session.rom);
        final title = wad.title;
        final nativeId = String.fromCharCodes([
          for (var i = 8; i < 16; i += 2)
            int.parse(title.substring(i, i + 2), radix: 16),
        ]);
        return ProgressLayout(root.path, 'dolphin-wii-channel-v1', title, [
          ProgressArea(
            'save',
            '$u/Wii/title/${title.substring(0, 8)}/${title.substring(8)}/data',
          ),
          ...await _wiiDlcAreas(root, u, e.contentId),
          if (RegExp(r'^[A-Za-z0-9]{4}$').hasMatch(nativeId))
            ProgressArea(state, '$u/StateSaves', prefix: '$nativeId.'),
        ]);
      }
      final id = platform == 'wii'
          ? await wiiDiscId(session.rom)
          : await _dolphinId(session.rom);
      final stateArea = ProgressArea(state, '$u/StateSaves', prefix: '$id.');
      if (platform == 'wii') {
        final title = ascii
            .encode(id.substring(0, 4))
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        return ProgressLayout(root.path, 'dolphin-wii-data-v1', id, [
          ProgressArea('save', '$u/Wii/title/00010000/$title/data'),
          ...await _wiiDlcAreas(root, u, e.contentId),
          stateArea,
        ]);
      }
      final region = switch (id[3]) {
        'E' => 'USA',
        'J' => 'JAP',
        _ => 'EUR',
      };
      final areas = [
        for (final slot in ['A', 'B'])
          ProgressArea(
            'card$slot',
            '$u/GC/$region/Card $slot',
            suffix: '.gci',
            gciId: id,
          ),
      ];
      // A game may not have created a GCI yet. Import resolves its header/name separately.
      return ProgressLayout(
        root.path,
        'dolphin-gci-v1',
        id,
        [...areas, stateArea],
        note: 'GameCube cloud saves require Dolphin GCI folder memory cards. Raw shared memory cards are not uploaded.',
      );
    case 'RPCS3':
      final sfo = await readPs3GameMetadata(session.rom);
      final id = sfo['TITLE_ID'];
      if (id == null || !RegExp(r'^[A-Z]{4}[0-9]{5}$').hasMatch(id))
        throw const FormatException('No verified PS3 title ID');
      return ProgressLayout(root.path, 'rpcs3-savedata-v1', id, [
        ProgressArea(
          'save',
          '$u/dev_hdd0/home/00000001/savedata',
          folderPrefix: id,
        ),
      ], note: 'RPCS3 save states are not supported.');
    default:
      throw UnsupportedError(
        'Cloud save access is not yet validated for ${e.name}. Local progress is kept.',
      );
  }
}

Future<List<ProgressArea>> _wiiDlcAreas(
  Directory root,
  String user,
  String? game,
) async {
  if (game == null || !RegExp(r'^[1-9][0-9]*$').hasMatch(game)) return [];
  final registry = await PackageProfile(root, 'wii').ownership();
  final titles = <String>{};
  for (final e in (registry['files'] as Map).entries) {
    final match = RegExp(
      r'^Wii/title/00010005/([a-f0-9]{8})/content/title\.tmd$',
    ).firstMatch(e.key as String);
    if (match != null &&
        ((e.value as Map)['owners'] as List).cast<String>().any(
          (o) => o.endsWith('/$game'),
        ))
      titles.add(match[1]!);
  }
  final sorted = titles.toList()..sort();
  return [
    for (final id in sorted)
      ProgressArea('dlc-$id', '$user/Wii/title/00010005/$id/data'),
  ];
}

Future<bool> progressGciMatches(File file, String id) async {
  final f = await file.open();
  try {
    final h = await f.read(0x40);
    return h.length == 0x40 &&
        ascii.decode(h.sublist(0, 6), allowInvalid: true) == id;
  } finally {
    await f.close();
  }
}

Future<String> _dolphinId(String path) async {
  final f = await File(path).open();
  try {
    var data = await f.read(0x80);
    if (data.length < 0x80)
      throw const FormatException('Truncated Dolphin game header');
    if (['RVZ\x01', 'WIA\x01'].contains(latin1.decode(data.sublist(0, 4)))) {
      await f.setPosition(0x58);
      data = await f.read(0x80);
    }
    final h = ByteData.sublistView(Uint8List.fromList(data));
    if (h.getUint32(0x18) != 0x5d1c9ea3 && h.getUint32(0x1c) != 0xc2339f3d)
      throw const FormatException('Unsupported Dolphin game container');
    final id = ascii.decode(data.sublist(0, 6));
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(id))
      throw const FormatException('Invalid Dolphin game identity');
    return id;
  } finally {
    await f.close();
  }
}

Future<List<String>> _threeDsExtdata(String path, String id) async {
  final f = await File(path).open();
  try {
    var h = await f.read(0x200);
    if (h.length != 0x200) throw const FormatException('Truncated 3DS header');
    var start = 0;
    if (ByteData.sublistView(Uint8List.fromList(h)).getUint32(0x100) ==
        0x4e435344)
      start =
          ByteData.sublistView(Uint8List.fromList(h))
              .getUint32(0x120, Endian.little) *
          0x200;
    await f.setPosition(start + 0x400);
    h = await f.read(0x50);
    if (h.length != 0x50)
      throw const FormatException('Missing 3DS save access metadata');
    final d = ByteData.sublistView(Uint8List.fromList(h));
    if (d.getUint64(0, Endian.little).toRadixString(16).padLeft(16, '0') != id)
      throw const FormatException(
        'Cloud saves need a decrypted 3DS extended header to identify extdata safely',
      );
    if ((h[0x4f] >> 1) != 0)
      throw const FormatException(
        'Extended 3DS extdata access is not supported yet',
      );
    final value = d.getUint64(0x30, Endian.little);
    if (value > 0xffffffff)
      throw const FormatException('Unsupported 3DS extdata identity');
    return value == 0 ? [] : [value.toRadixString(16).padLeft(8, '0')];
  } finally {
    await f.close();
  }
}

Future<Map<String, String>> readPs3Sfo(File file) async {
  if (await file.length() > 1024 * 1024)
    throw const FormatException('PS3 metadata too large');
  final b = await file.readAsBytes();
  return parsePs3Sfo(b);
}

Future<Map<String, String>> readPs3GameMetadata(String entry) async =>
    entry.toLowerCase().endsWith('.iso')
    ? parsePs3Sfo(await ps3DiscMetadata(File(entry)))
    : readPs3Sfo(File('${File(entry).parent.parent.path}/PARAM.SFO'));

Map<String, String> parsePs3Sfo(Uint8List b) => parseSonySfo(b);
