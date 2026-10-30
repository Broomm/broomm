import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../emulators.dart';
import '../game_launch.dart';
import '../nintendo_ds.dart';
import '../progress/digest.dart';
import '../progress/files.dart';
import '../progress/layout.dart';
import '../psp.dart';
import '../retroarch.dart';
import '../session.dart';
import '../switch_content.dart';
import 'emulators.dart';

/// Concrete correspondence between one native save boundary and its private
/// profile copy. The cloud format/keys retain the desktop ordinary-save contract.
class AndroidSaveArea {
  const AndroidSaveArea(this.local, this.remote, {this.rename});
  final ProgressArea local;
  final String remote;
  final String? rename;
  Map<String, String> get selector => {
    'path': remote,
    if (rename != null) 'exact': rename!,
    if (rename == null) ...{
      if (local.prefix != null) 'prefix': local.prefix!,
      if (local.suffix != null) 'suffix': local.suffix!,
      if (local.exact != null) 'exact': local.exact!,
      if (local.pattern != null) 'pattern': local.pattern!,
      if (local.folderPrefix != null) 'folderPrefix': local.folderPrefix!,
      if (local.gciId != null) 'gciId': local.gciId!,
      if (local.excluded.isNotEmpty)
        'excluded': jsonEncode(local.excluded.toList()),
    },
  };
  String? key(String path) {
    if (!path.startsWith('$remote/')) return null;
    final name = path.substring(remote.length + 1);
    if (rename != null && name != rename) return null;
    final native = rename == null ? name : local.exact!;
    return local.accepts(native)
        ? '${local.id}/${local.logical(native)}'
        : null;
  }

  String path(String key) {
    final native = local.native(key.substring(local.id.length + 1));
    if (!key.startsWith('${local.id}/') || !local.accepts(native))
      throw const FormatException('Save is outside its Android boundary');
    return '$remote/${rename ?? native}';
  }
}

class AndroidSavePlan extends ProgressLayout {
  AndroidSavePlan(
    ProgressLayout layout,
    this.emulator,
    this.binding,
    this.remoteAreas, {
    this.launch = const {},
  }) : super(
         layout.root,
         layout.format,
         layout.game,
         layout.areas,
         note: layout.note,
         rawSave: layout.rawSave,
       );
  final AndroidEmulator emulator;
  final Map<String, String> binding;
  final List<AndroidSaveArea> remoteAreas;
  final Map<String, String> launch;
  Map<String, String> get arguments => {...binding, 'emulator': emulator.id};
  String remotePath(String key) => remoteAreas
      .singleWhere(
        (a) =>
            key.startsWith('${a.local.id}/') &&
            a.local.accepts(
              a.local.native(key.substring(a.local.id.length + 1)),
            ),
      )
      .path(key);
  String? localKey(String remote) {
    final found = remoteAreas
        .map((a) => a.key(remote))
        .whereType<String>()
        .toList();
    if (found.length > 1)
      throw const FormatException('Ambiguous Android save boundary');
    return found.firstOrNull;
  }
}

class AndroidFolderReader {
  AndroidFolderReader(this.manager, this.emulator, {this.package});
  final AndroidEmulators manager;
  final AndroidEmulator emulator;
  final String? package;
  Map<String, String> get arguments =>
      manager.folderArguments(emulator, package: package);
  Future<Uint8List?> bytes(String path) => manager.channel
      .invokeMethod<Uint8List>('sharedBytes', {...arguments, 'path': path});
  Future<String?> text(String path) async {
    final value = await bytes(path);
    return value == null ? null : utf8.decode(value);
  }

  Future<List<String>> directories(String path) async {
    final rows = await manager.channel.invokeListMethod<Object?>(
      'sharedChildren',
      {...arguments, 'path': path},
    );
    if (rows == null)
      throw StateError('The emulator folder could not be inspected.');
    return rows
        .cast<Map>()
        .where((r) => r['directory'] == true)
        .map((r) => r['name'] as String)
        .toList();
  }

  /// Resolve a configured native path only when it belongs to the granted tree.
  String relative(String value) {
    var path = value.replaceAll('\\', '/');
    final tree = Uri.parse(arguments['tree']!), id = tree.pathSegments[1];
    if (path.startsWith('content://')) {
      final u = Uri.parse(path);
      if (u.authority != tree.authority)
        throw StateError(
          'The emulator uses a folder outside its Broomm grant.',
        );
      path = u.pathSegments.last;
      if (!path.startsWith('$id/'))
        throw StateError(
          'The emulator uses a different folder. Reconfigure saves.',
        );
      path = path.substring(id.length + 1);
    } else if (path.startsWith('/')) {
      final prefixes = <String>[
        if (id.startsWith('/')) id,
        if (tree.authority == 'com.android.externalstorage.documents')
          id.startsWith('primary:')
              ? '/storage/emulated/0/${id.substring(8)}'
              : '/storage/${id.replaceFirst(':', '/')}',
        if (tree.authority == '${arguments['package']}.user')
          '/storage/emulated/0/Android/data/${arguments['package']}/files',
      ];
      final matching = prefixes.where((p) => path.startsWith('$p/')).toList();
      if (matching.length != 1)
        throw StateError(
          'A configured save path is outside the connected emulator folder.',
        );
      path = path.substring(matching.single.length + 1);
    }
    progressRelative(path);
    return path;
  }
}

Map<String, String> androidIni(String text) {
  final result = <String, String>{};
  var section = '';
  for (final line in const LineSplitter().convert(text)) {
    final v = line.trim();
    if (v.startsWith('[') && v.endsWith(']')) {
      section = v.substring(1, v.length - 1);
      continue;
    }
    if (v.startsWith('#') || v.startsWith(';')) continue;
    final split = v.indexOf('=');
    if (split < 1) continue;
    final key =
            '${section.isEmpty ? '' : '$section/'}${v.substring(0, split).trim()}',
        raw = v.substring(split + 1).trim();
    final value = raw.startsWith('"') && raw.endsWith('"')
        ? raw.substring(1, raw.length - 1)
        : raw;
    if (result.containsKey(key) && result[key] != value)
      throw const FormatException('Conflicting emulator folder settings');
    result[key] = value;
  }
  return result;
}

String androidRetroConfig(String text, Map<String, String> values) {
  final assignment = RegExp(r'^\s*([a-zA-Z0-9_]+)\s*=');
  final retained = const LineSplitter()
      .convert(text)
      .where((line) => !values.containsKey(assignment.firstMatch(line)?[1]))
      .join('\n');
  return '$retained\n${values.entries.map((e) => '${e.key} = ${jsonEncode(e.value)}').join('\n')}\n';
}

Future<AndroidSavePlan> connectedAndroidProgress(
  AndroidEmulators manager,
  String profile,
  AndroidEmulator emulator,
  GamePlatform platform,
  String rom,
  String content, {
  String? package,
}) async {
  final root = await manager.privateRoot(profile, emulator),
      reader = AndroidFolderReader(manager, emulator, package: package);
  final app = manager.app(emulator, package: package)!;
  final build = await manager.fingerprint(app);
  String state(String extra) {
    final hash = ProgressDigest.sha256()..add(utf8.encode('$build:$extra'));
    return 'states-${hash.finish().substring(0, 16)}-android';
  }

  final remote = <AndroidSaveArea>[];
  void bind(ProgressLayout layout, {String Function(ProgressArea)? path}) {
    for (final a in layout.areas)
      remote.add(
        AndroidSaveArea(a, path?.call(a) ?? a.path.substring('user/'.length)),
      );
  }

  late ProgressLayout layout;
  final launch = <String, String>{};
  switch (emulator.id) {
    case 'ppsspp':
      final metadata = await pspGameMetadata(rom),
          version = metadata['DISC_VERSION'] ?? '1.00';
      final existing = await gameProgressLayout(
        ResolvedSession(
          PreparedEmulator('PPSSPP', root.path, '', 0, null, null),
          rom,
          build,
          const {},
        ),
        'psp',
      );
      layout = ProgressLayout(root.path, 'ppsspp-savedata-v1', existing.game, [
        ...existing.areas.where((a) => !a.id.startsWith('states-')),
        ProgressArea(
          state(version),
          'user/PSP/PPSSPP_STATE',
          prefix: '${existing.game}_${version}_',
          pattern: r'^[^/]+\.(?:undo\.)?(?:ppst|jpg)$',
        ),
      ]);
      bind(layout);
    case 'melonds':
      final stem = retroStateStem(rom);
      layout = ProgressLayout(
        root.path,
        'melonds-sav-v1',
        await dsSaveIdentity(rom),
        [
          ProgressArea('save', 'user', prefix: stem, exact: '$stem.sav'),
          ProgressArea(
            state('melonDS-android'),
            'user',
            prefix: '$stem.ml',
            pattern: r'^[^/]+\.ml[0-8]$',
          ),
        ],
      );
      // Pick the custom save folder itself, with states set to the save folder.
      for (final a in layout.areas) remote.add(AndroidSaveArea(a, '@root'));
    case 'azahar':
    case 'citra-mmj':
      layout = await threeDsProgressLayout(
        root.path,
        'user',
        rom,
        state: state(emulator.id),
      );
      const zeros = '00000000000000000000000000000000';
      var id0 = zeros, id1 = zeros;
      final first = (await reader.directories('sdmc/Nintendo 3DS'))
          .where((p) => RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(p))
          .toList();
      if (first.length > 1)
        throw StateError(
          'The 3DS folder has multiple console identities. Select the active user folder.',
        );
      if (first.isNotEmpty) {
        id0 = first.single;
        final second = (await reader.directories('sdmc/Nintendo 3DS/$id0'))
            .where((p) => RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(p))
            .toList();
        if (second.length > 1)
          throw StateError(
            'The 3DS folder has multiple SD identities. Reconnect the active folder.',
          );
        if (second.isNotEmpty) id1 = second.single;
      }
      bind(
        layout,
        path: (a) =>
            a.path.substring(5).replaceFirst('$zeros/$zeros', '$id0/$id1'),
      );
    case 'dolphin':
      layout = await gameProgressLayout(
        ResolvedSession(
          PreparedEmulator(
            'Dolphin',
            root.path,
            '',
            0,
            null,
            null,
            contentId: content,
          ),
          rom,
          build,
          const {},
        ),
        platform.slug,
      );
      final ordinary = layout.areas
          .where((a) => !a.id.startsWith('states-'))
          .toList();
      layout = ProgressLayout(root.path, layout.format, layout.game, [
        ...ordinary,
        for (final a in layout.areas.where((a) => a.id.startsWith('states-')))
          ProgressArea(state('Dolphin'), a.path, prefix: a.prefix),
      ], note: layout.note);
      final config = androidIni(await reader.text('Config/Dolphin.ini') ?? '');
      if (platform.slug == 'ngc' &&
          ['SlotA', 'SlotB'].any((key) => config['Core/$key'] != '8'))
        throw StateError(
          'Set Dolphin’s GameCube memory cards to GCI Folder for both slots before using cloud saves.',
        );
      bind(layout);
    case 'duckstation':
    case 'armsx2':
      final ps2 = emulator.id == 'armsx2';
      final text = await reader.text(
        ps2 ? 'PCSX2-Android.ini' : 'settings.ini',
      );
      if (text == null && ps2)
        throw StateError(
          'Initialize ${emulator.name}, connect its full data folder, and close it before setting up saves.',
        );
      final config = androidIni(text ?? '');
      final cards = ps2 ? 'memcards' : 'memcards',
          states = ps2 ? 'sstates' : 'savestates';
      final cardDir = reader.relative(
        config[ps2 ? 'Folders/MemoryCards' : 'MemoryCards/Directory'] ?? cards,
      );
      final stateDir = reader.relative(
        config[ps2 ? 'Folders/Savestates' : 'Folders/SaveStates'] ?? states,
      );
      for (var slot = 1; slot <= 2; slot++) {
        if (!ps2 &&
            (config['MemoryCards/Card${slot}Type'] ?? 'Shared') != 'Shared')
          throw StateError(
            'Set DuckStation memory-card slots to Shared Between All Games. Broomm will swap profile/game cards and restore your standalone cards afterward.',
          );
        final native =
            config[ps2
                ? 'MemoryCards/Slot${slot}_Filename'
                : 'MemoryCards/Card${slot}Path'] ??
            (ps2 ? 'Mcd00$slot.ps2' : 'shared_card_$slot.mcd');
        final path = native.contains('/')
            ? reader.relative(native)
            : '$cardDir/$native';
        progressRelative(path);
        final a = ProgressArea(
          'save',
          'user/cards',
          exact: ps2 ? 'slot$slot.ps2' : 'card$slot.mcd',
        );
        // Separate selectors share the public ordinary-save area.
        remote.add(
          AndroidSaveArea(
            a,
            path.substring(0, path.lastIndexOf('/')),
            rename: path.split('/').last,
          ),
        );
      }
      final cardArea = ProgressArea(
        'save',
        'user/cards',
        pattern: ps2 ? r'^slot[12]\.ps2$' : r'^card[12]\.mcd$',
      );
      final statesArea = ProgressArea(
        state(emulator.id),
        'user/states',
        pattern: ps2 ? r'^[^/]+\.p2s(?:\.backup)?$' : r'^[^/]+\.sav(?:\.bak)?$',
      );
      remote.add(AndroidSaveArea(statesArea, stateDir));
      layout = ProgressLayout(
        root.path,
        ps2 ? 'ps2-cards-v1' : 'duckstation-cards-v1',
        content,
        [cardArea, statesArea],
      );
    case 'retroarch':
      final spec = retroSystem(platform.slug),
          core =
              platform.retroCore ??
              (platform.slug == 'snes' ? 'snes9x' : spec?.core);
      if (core == null)
        throw StateError('No supported RetroArch core for this game.');
      final tree = Uri.parse(reader.arguments['tree']!),
          native = tree.pathSegments[1];
      if (tree.authority != '${app.package}.documents' ||
          !RegExp('^/data/(?:data|user/[0-9]+)/${RegExp.escape(app.package)}\$')
              .hasMatch(native))
        throw StateError(
          'Select RetroArch’s Core Data/app-data provider root, not its shared saves subfolder.',
        );
      final corePath = 'cores/${core}_libretro_android.so';
      Future<Map<String, dynamic>?> stat() =>
          manager.channel.invokeMapMethod<String, dynamic>('sharedStat', {
            ...reader.arguments,
            'path': corePath,
          });
      final observed = await stat();
      if (observed == null)
        throw StateError('Install the $core core inside RetroArch first.');
      final key = ProgressDigest.sha256()
        ..add(
          utf8.encode(
            jsonEncode({
              'build': app.build,
              ...reader.arguments,
              'core': core,
              'stat': observed,
            }),
          ),
        );
      Future<String> inspectCore() async {
        final cores = await manager.channel.invokeMapMethod<String, dynamic>(
          'sharedList',
          {
            ...reader.arguments,
            'areas': [
              {'path': 'cores', 'exact': '${core}_libretro_android.so'},
            ],
          },
        );
        if (cores == null || cores.length != 1)
          throw StateError('Install the $core core inside RetroArch first.');
        if (jsonEncode(await stat()) != jsonEncode(observed))
          throw StateError(
            'The RetroArch core changed during inspection. Retry after its installation finishes.',
          );
        return (cores.values.single as Map)['sha256'] as String;
      }
      final coreHash =
          observed['modified'] is int && (observed['modified'] as int) > 0
          ? await manager.resourceFingerprint(key.finish(), inspectCore)
          : await inspectCore();
      final cfg =
          await reader.text('files/retroarch.cfg') ??
          await reader.text('retroarch.cfg');
      if (cfg == null)
        throw StateError(
          'Open RetroArch and save its configuration before connecting its data provider.',
        );
      final base = 'files/Broomm/$profile/$content',
          stem = retroStateStem(rom),
          configName = progressNonce();
      final a = ProgressArea(
        'save',
        'user/saves',
        prefix: ['opera', 'fbneo', 'flycast', 'mednafen_saturn'].contains(core)
            ? null
            : stem,
      );
      final b = ProgressArea(
        state(coreHash),
        'user/states',
        prefix: '$stem.state',
      );
      layout = ProgressLayout(
        root.path,
        core == 'snes9x' ? 'snes9x-sram-v1' : 'libretro-$core-v1',
        core == 'snes9x' ? 'snes' : content,
        [a, b],
        rawSave: core == 'opera' ? 'save/opera/per_game/$stem.0.srm' : null,
      );
      remote.addAll([
        AndroidSaveArea(a, '$base/saves'),
        AndroidSaveArea(b, '$base/states'),
      ]);
      final overrides = {
        'savefile_directory': '$native/$base/saves',
        'savestate_directory': '$native/$base/states',
        'sort_savefiles_enable': 'false',
        'sort_savestates_enable': 'false',
        'sort_savefiles_by_content_enable': 'false',
        'sort_savestates_by_content_enable': 'false',
        'savefiles_in_content_dir': 'false',
        'savestates_in_content_dir': 'false',
        'config_save_on_exit': 'false',
        'auto_overrides_enable': 'false',
      };
      final special = switch (core) {
        'flycast' => {'reicast_per_content_vmus': 'All VMUs'},
        'opera' => {
          'opera_nvram_storage': 'per game',
          'opera_nvram_version': '0',
        },
        _ => <String, String>{},
      };
      var options = '';
      if (special.isNotEmpty) {
        final originalPath = androidIni(cfg)['core_options_path'];
        if (originalPath != null && originalPath.isNotEmpty) {
          try {
            options = await reader.text(reader.relative(originalPath)) ?? '';
          } on StateError {
            manager.phase?.call(
              'RetroArch $core options are outside the connected root; this Broomm session uses core defaults with its private save settings. Standalone options were kept.',
            );
          }
        }
        overrides.addAll({
          'core_options_path': '$native/$base/$configName.opt',
          'game_specific_options': 'false',
          'global_core_options': 'true',
        });
      }
      launch.addAll({
        'configPath': '$base/$configName.cfg',
        'configText': androidRetroConfig(cfg, overrides),
        'configNative': '$native/$base/$configName.cfg',
        if (special.isNotEmpty) ...{
          'optionsPath': '$base/$configName.opt',
          'optionsText': androidRetroConfig(options, special),
        },
      });
    case 'eden':
      final profileData = await reader.bytes(
        'nand/system/save/8000000000000010/su/avators/profiles.dat',
      );
      if (profileData == null || profileData.length != 0x650)
        throw StateError(
          'Open Eden once and initialize its console account, then reconnect its data folder.',
        );
      final accounts = <Uint8List>[];
      for (var i = 0; i < 8; i++) {
        final bytes = Uint8List.sublistView(
          profileData,
          0x10 + 0xc8 * i,
          0x20 + 0xc8 * i,
        );
        if (bytes.any((n) => n != 0)) {
          if (!List.generate(
            16,
            (n) => bytes[n] == profileData[0x20 + 0xc8 * i + n],
          ).every((v) => v))
            throw const FormatException(
              'Eden console account identity is inconsistent',
            );
          accounts.add(bytes);
        }
      }
      if (accounts.length != 1)
        throw StateError(
          'Eden must have one active console account for this save setup; existing accounts were kept.',
        );
      final keyText = await reader.text('keys/prod.keys');
      final keyMatch = keyText == null
          ? null
          : RegExp(
              r'^\s*header_key\s*=\s*([a-fA-F0-9]{64})\s*$',
              multiLine: true,
            ).firstMatch(keyText);
      if (keyMatch == null)
        throw StateError(
          'Configure Eden’s prod.keys inside Eden before synchronizing saves. Automatic firmware/keys setup is deferred.',
        );
      final hex = keyMatch[1]!,
          key = Uint8List.fromList([
            for (var i = 0; i < 64; i += 2)
              int.parse(hex.substring(i, i + 2), radix: 16),
          ]);
      final title = await switchBaseIdentity(
        File(rom),
        key,
        decryptSector: (bytes, key, sector) =>
            androidXts(manager, bytes, key, sector),
      );
      final account = accounts.single
          .map((n) => n.toRadixString(16).padLeft(2, '0'))
          .join();
      final d = ByteData.sublistView(accounts.single),
          legacy =
              '${d.getUint64(8, Endian.little).toRadixString(16).padLeft(16, '0')}${d.getUint64(0, Endian.little).toRadixString(16).padLeft(16, '0')}'
                  .toUpperCase();
      layout = ProgressLayout(root.path, 'ryubing-directory-v1', title, [
        ProgressArea('save', 'user/save'),
        ProgressArea('device', 'user/device'),
      ]);
      // Eden prefers the future path only when this title's complete path
      // exists. Another title's account directory must not change first-save
      // placement. Otherwise native 0.2.1 creates the legacy path.
      final futureSave = (await reader.directories(
        'nand/user/save/account/$account/${title.toUpperCase()}',
      )).contains('0');
      final futureDevice = (await reader.directories(
        'nand/user/save/device/${title.toUpperCase()}',
      )).contains('0');
      remote.addAll([
        AndroidSaveArea(
          layout.areas[0],
          futureSave
              ? 'nand/user/save/account/$account/${title.toUpperCase()}/0'
              : 'nand/user/save/0000000000000000/$legacy/${title.toUpperCase()}',
        ),
        AndroidSaveArea(
          layout.areas[1],
          futureDevice
              ? 'nand/user/save/device/${title.toUpperCase()}/0'
              : 'nand/user/save/0000000000000000/${'0' * 32}/${title.toUpperCase()}',
        ),
      ]);
    default:
      throw UnsupportedError(
        'Missing Android save adapter for ${emulator.name}.',
      );
  }
  ProgressArea isolated(ProgressArea a) => !a.id.startsWith('states-')
      ? a
      : ProgressArea(
          a.id,
          'state-builds/${a.id}/${a.path}',
          prefix: a.prefix,
          suffix: a.suffix,
          folderPrefix: a.folderPrefix,
          exact: a.exact,
          gciId: a.gciId,
          pattern: a.pattern,
          excluded: a.excluded,
        );
  final privateLayout = ProgressLayout(
    layout.root,
    layout.format,
    layout.game,
    layout.areas.map(isolated).toList(),
    note: layout.note,
    rawSave: layout.rawSave,
  );
  return AndroidSavePlan(
    privateLayout,
    emulator,
    manager.folderArguments(emulator, package: app.package),
    [
      for (final a in remote)
        AndroidSaveArea(isolated(a.local), a.remote, rename: a.rename),
    ],
    launch: launch,
  );
}

/// Android supplies only the OS AES primitive; title/file interpretation stays
/// in Dart. This is used to identify encrypted Switch media, not install firmware.
Future<Uint8List> androidXts(
  AndroidEmulators manager,
  Uint8List bytes,
  Uint8List key,
  int sector,
) async {
  final iv = Uint8List(16);
  ByteData.sublistView(iv).setUint64(8, sector);
  Future<Uint8List> aes(Uint8List b, Uint8List k, bool decrypt) async =>
      (await manager.channel.invokeMethod<Uint8List>('aesEcb', {
        'bytes': b,
        'key': k,
        'decrypt': decrypt,
      }))!;
  final tweak = await aes(iv, Uint8List.sublistView(key, 16), false),
      input = Uint8List(512),
      tweaks = Uint8List(512);
  for (var at = 0; at < 512; at += 16) {
    for (var i = 0; i < 16; i++) {
      tweaks[at + i] = tweak[i];
      input[at + i] = bytes[at + i] ^ tweak[i];
    }
    var carry = 0;
    for (var i = 0; i < 16; i++) {
      final n = tweak[i];
      tweak[i] = ((n << 1) & 255) | carry;
      carry = n >> 7;
    }
    if (carry != 0) tweak[0] ^= 0x87;
  }
  final out = await aes(input, Uint8List.sublistView(key, 0, 16), true);
  for (var i = 0; i < 512; i++) out[i] ^= tweaks[i];
  return out;
}
