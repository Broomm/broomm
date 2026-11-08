import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../progress/digest.dart';
import '../progress/file_hash.dart';
import '../progress/files.dart';
import '../retroarch.dart';
import '../romm/client.dart';
import '../romm/models.dart';
import '../romm/transfer.dart';
import 'lynx_firmware.dart';
import 'opera.dart' show androidRetroOptionPaths;

/// The pinned frontend selects game, actual content-folder, core, then global
/// options. An absent core file inherits global values; files are not merged.
Future<Map<String, String>> readAndroidFlycastOptions(
  MethodChannel channel,
  Map<String, String> binding,
  Map<String, String> preferences,
  String rom,
  String folder,
) async {
  final paths = androidRetroOptionPaths(preferences, binding['package']!);
  final stem = retroStateStem(rom), directory = paths['rgui_config_directory']!;
  final gameSpecific = preferences['game_specific_options'] != 'false';
  final perCore = preferences['global_core_options'] != 'true';
  for (final path in [
    if (gameSpecific) '$directory/Flycast/$stem.opt',
    if (gameSpecific) '$directory/Flycast/$folder.opt',
    if (perCore) '$directory/Flycast/Flycast.opt',
    paths['core_options_path']!,
  ]) {
    final bytes = await channel.invokeMethod<Uint8List>('rootOptions', {
      ...binding,
      'coreName': 'flycast',
      'path': path,
    });
    if (bytes == null) continue;
    return parseAndroidFlycastOptions(bytes);
  }
  return {};
}

Map<String, String> parseAndroidFlycastOptions(Uint8List bytes) {
  if (bytes.length > 262144)
    throw const FormatException('Flycast core options are too large.');
  final text = utf8.decode(bytes), result = <String, String>{};
  for (final line in const LineSplitter().convert(text)) {
    if (RegExp(r'^\s*#include(?:\s|$)').hasMatch(line))
      throw const FormatException(
        'Flycast options include another file. Use a self-contained core option file before rooted Play.',
      );
    final match = RegExp(
      r'^\s*((?:reicast|flycast)_[a-z0-9_]+)\s*=\s*"([^"\x00-\x1f]*)"\s*(?:#.*)?$',
    ).firstMatch(line);
    if (match == null) {
      if (RegExp(r'^\s*(?:reicast|flycast)_').hasMatch(line))
        throw const FormatException(
          'Flycast has an unreadable core option. Existing progress was kept.',
        );
      continue;
    }
    final key = match[1]!, value = match[2]!;
    if (result.containsKey(key) && result[key] != value)
      throw const FormatException(
        'Flycast has conflicting core options. Existing progress was kept.',
      );
    result[key] = value;
  }
  return result;
}

const androidFlycastRequiredOptions = {
  // The reviewed official Android binaries use the historical reicast prefix;
  // other Flycast builds use flycast. Supply both concrete names, preserving
  // native preferences and checking both on return instead of guessing by label.
  'reicast_per_content_vmus': 'All VMUs',
  'reicast_linked_vmu_storage': 'disabled',
  'flycast_per_content_vmus': 'All VMUs',
  'flycast_linked_vmu_storage': 'disabled',
};

/// The pinned core loads a legacy content-name VMU, then fullSave writes it to
/// its native game-ID name and removes the old name. Both inventories already
/// belong to this locked profile/game boundary. Only an unambiguous, new native
/// name for the same port can account for that disappearance; missing states,
/// existing game-ID cards and competing destinations remain damaged recovery.
void validateAndroidFlycastWorkingProgress(
  String selected,
  Map<String, dynamic> working,
  Map<String, dynamic> actual,
) {
  final missing = working.keys.where((p) => !actual.containsKey(p)).toList();
  if (missing.isEmpty) return;
  Never damaged() => throw StateError(
    'An installed Flycast save or state is missing or its VMU migration is ambiguous. All recovery copies were kept.',
  );
  final stem = retroStateStem(selected);
  final card = RegExp(r'^(.*)/saves/([^/]+)\.([A-D][12])\.bin$');
  final destinations = <String>{};
  for (final path in missing) {
    final old = card.firstMatch(path);
    if (old == null || old[2] != stem) damaged();
    final candidates = actual.keys.where((p) {
      final next = card.firstMatch(p);
      return next != null && next[1] == old[1] && next[3] == old[3];
    }).toList();
    if (candidates.length != 1 || working.containsKey(candidates.single))
      damaged();
    final next = candidates.single;
    if (working[path]['bytes'] != 131072 || actual[next]['bytes'] != 131072)
      damaged();
    destinations.add(card.firstMatch(next)![2]!);
  }
  // One disc has one native game ID across every port. Do not select among
  // historical cards or let an unrelated extra name resolve a missing input.
  for (final path in actual.keys.where((p) => !working.containsKey(p))) {
    final next = card.firstMatch(path);
    if (next != null) destinations.add(next[2]!);
  }
  if (destinations.length != 1 || destinations.single == stem) damaged();
}

String androidFlycastOptionsText(Map<String, String> values) {
  final options = {...values, ...androidFlycastRequiredOptions};
  for (final entry in options.entries) {
    if (!RegExp(r'^(?:reicast|flycast)_[a-z0-9_]+$').hasMatch(entry.key) ||
        entry.value.length > 1024 ||
        RegExp(r'["\x00-\x1f\x7f]').hasMatch(entry.value)) {
      throw const FormatException('Invalid private Flycast core option.');
    }
  }
  final keys = options.keys.toList()..sort();
  final text = keys.map((k) => '$k = "${options[k]}"\n').join();
  if (utf8.encode(text).length > 262144) {
    throw const FormatException('Flycast core options are too large.');
  }
  return text;
}

/// Only the caller holding the production session lease may publish preferences.
/// Core options are local configuration, separate from cloud game progress.
Future<Map<String, String>> readAndroidFlycastPreferences(
  Directory profileRoot,
  String game,
) async {
  progressRelative('root-dc/$game/options.json');
  final file = await progressFile(
    profileRoot,
    'root-dc/$game/options.json',
    createParents: true,
  );
  if (!await progressExists(file.path)) return {};
  final saved = await progressJson(file);
  if (saved['version'] != 1 || saved['options'] is! Map) {
    throw const FormatException(
      'The private Flycast option record is invalid.',
    );
  }
  final options = (saved['options'] as Map).cast<String, String>();
  androidFlycastOptionsText(options);
  return options;
}

Future<void> writeAndroidFlycastPreferences(
  Directory profileRoot,
  String game,
  Map<String, String> options,
) async {
  androidFlycastOptionsText(options);
  await progressWrite(
    await progressFile(
      profileRoot,
      'root-dc/$game/options.json',
      createParents: true,
    ),
    {
      'version': 1,
      'options': {
        for (final entry in options.entries)
          if (!androidFlycastRequiredOptions.containsKey(entry.key))
            entry.key: entry.value,
      },
    },
  );
}

/// Called only after verified uninstall while the emulator-removal lease is
/// held. Remove concrete configuration files, retaining every progress/console
/// object and historical session recovery copy.
Future<void> clearAndroidFlycastPreferences(Directory data) async {
  final profiles = Directory('${data.path}/profiles');
  final type = await FileSystemEntity.type(profiles.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (type != FileSystemEntityType.directory) {
    throw const FileSystemException('Profile settings are linked or invalid.');
  }
  var count = 0;
  await for (final profile in profiles.list(followLinks: false)) {
    if (++count > 4096)
      throw const FormatException('Too many profile settings.');
    final id = profile.uri.pathSegments.where((p) => p.isNotEmpty).last;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) continue;
    if (await FileSystemEntity.type(profile.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('Linked profile settings were kept.');
    }
    final relative = 'profiles/$id/emulators/retroarch';
    final root = Directory('${data.path}/$relative');
    final rootType = await FileSystemEntity.type(root.path, followLinks: false);
    if (rootType == FileSystemEntityType.notFound) continue;
    final owner = await progressJson(
      await progressFile(data, '$relative/profile.json'),
    );
    if (rootType != FileSystemEntityType.directory ||
        owner['version'] != 1 ||
        owner['profile'] != id ||
        owner['emulator'] != 'retroarch') {
      throw const FileSystemException(
        'Unrecognized emulator settings were kept.',
      );
    }
    final games = Directory('${root.path}/root-dc');
    final gameType = await FileSystemEntity.type(
      games.path,
      followLinks: false,
    );
    if (gameType == FileSystemEntityType.notFound) continue;
    if (gameType != FileSystemEntityType.directory)
      throw const FileSystemException(
        'Dreamcast settings are linked or invalid.',
      );
    var entries = 0;
    await for (final entry in games.list(followLinks: false)) {
      if (++entries > 65536)
        throw const FormatException('Too many Dreamcast settings.');
      final game = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
      if (!RegExp(r'^[1-9][0-9]*$').hasMatch(game)) continue;
      final file = await progressFile(
        data,
        '$relative/root-dc/$game/options.json',
      );
      if (!await progressExists(file.path)) continue;
      await file.delete();
      if (await progressExists(file.path))
        throw StateError('Dreamcast preferences changed during removal.');
    }
  }
}

class AndroidFlycastConsole {
  AndroidFlycastConsole(this.file, this.object, this.sha256);
  final File file;
  final String object, sha256;
  Map<String, dynamic> get record => {
    'object': object,
    'sha256': sha256,
    'bytes': 131072,
  };
}

/// Dreamcast console identity belongs to a profile across games. It is never
/// published as a game's VMU or treated as immutable canonical firmware.
Future<AndroidFlycastConsole?> readAndroidFlycastConsole(
  Directory profileRoot,
) async {
  final index = await progressFile(
    profileRoot,
    'flycast-console/index.json',
    createParents: true,
  );
  if (!await progressExists(index.path)) return null;
  final saved = await progressJson(index);
  if (saved['version'] != 1 ||
      saved['bytes'] != 131072 ||
      !RegExp(r'^[a-f0-9]{32}$').hasMatch(saved['object'] as String? ?? '') ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(saved['sha256'] as String? ?? '')) {
    throw const FormatException(
      'The Flycast console identity record is invalid.',
    );
  }
  final file = await progressFile(index.parent, '${saved['object']}.bin');
  if (!await progressExists(file.path) ||
      await file.length() != 131072 ||
      await progressFileHash(file) != saved['sha256']) {
    throw const FormatException(
      'The saved Flycast console identity is missing or damaged. All copies were kept.',
    );
  }
  return AndroidFlycastConsole(file, saved['object'], saved['sha256']);
}

/// SessionLease serializes the compare/publication with other app processes.
/// Immutable old console objects survive interruption and later publication.
Future<void> publishAndroidFlycastConsole(
  Directory profileRoot,
  Map<String, dynamic>? before,
  File captured,
  String expected,
) async {
  if (await captured.length() != 131072 ||
      await progressFileHash(captured) != expected) {
    throw const FormatException(
      'The captured Flycast console identity changed.',
    );
  }
  final current = await readAndroidFlycastConsole(profileRoot);
  if (current?.sha256 == expected)
    return; // An earlier reply may have been lost.
  if ((before == null) != (current == null) ||
      current != null &&
          (before!['object'] != current.object ||
              before['sha256'] != current.sha256 ||
              before['bytes'] != 131072)) {
    throw StateError(
      'The Flycast console identity changed before publication.',
    );
  }
  final object = progressNonce();
  final target = await progressFile(profileRoot, 'flycast-console/$object.bin');
  await target.create(exclusive: true);
  await target.writeAsBytes(await captured.readAsBytes(), flush: true);
  if (await target.length() != 131072 ||
      await progressFileHash(target) != expected ||
      await progressFileHash(captured) != expected) {
    throw const FileSystemException(
      'Flycast console publication failed verification.',
    );
  }
  await progressWrite(
    await progressFile(profileRoot, 'flycast-console/index.json'),
    {'version': 1, 'object': object, 'sha256': expected, 'bytes': 131072},
  );
  final verified = await readAndroidFlycastConsole(profileRoot);
  if (verified?.object != object || verified?.sha256 != expected) {
    throw StateError('Flycast console publication could not be confirmed.');
  }
}

class AndroidFlycastDisc {
  AndroidFlycastDisc._(this.file, this.bytes, this.sha256);
  final File file;
  final int bytes;
  final String sha256;
}

/// Initial Flycast media route: one self-contained image. CUE/GDI sets need their
/// complete file-set transport; they cannot be passed as a lone cartridge.
Future<AndroidFlycastDisc> inspectAndroidFlycastDisc(
  File file,
  DownloadCancellation cancellation,
  void Function(String) phase,
) async {
  cancellation.check();
  final extension = file.path.split('.').last.toLowerCase();
  if (extension != 'chd')
    throw UnsupportedError(
      'Rooted Flycast currently needs a self-contained CHD image. Multi-file CUE/GDI discs are not connected yet.',
    );
  await progressFile(file.parent, file.uri.pathSegments.last);
  final bytes = await file.length();
  if (bytes < 1 || bytes > 2 * 1024 * 1024 * 1024)
    throw const FormatException(
      'The Flycast disc image must be between 1 byte and 2 GiB.',
    );
  Uint8List? header;
  if (extension == 'chd') {
    final input = await file.open();
    try {
      header = await input.read(124);
    } finally {
      await input.close();
    }
    if (header.length != 124 ||
        ascii.decode(header.take(8).toList(), allowInvalid: true) != 'MComprHD')
      throw const FormatException(
        'The Flycast CHD header is incomplete or invalid.',
      );
    final fields = ByteData.sublistView(header);
    if (fields.getUint32(8) != 124 ||
        fields.getUint32(12) != 5 ||
        fields.getUint64(32) < 1 ||
        fields.getUint64(32) > 2 * 1024 * 1024 * 1024 ||
        header.skip(104).any((b) => b != 0))
      throw const FormatException(
        'Use a self-contained version-5 Flycast CHD of at most 2 GiB, without a parent CHD.',
      );
  }
  final name = file.uri.pathSegments.last;
  phase('Verifying the Flycast disc…');
  final hash = await gameFileHash(
    file.path,
    cancellation: cancellation,
    expectedPrefix: header,
    progress: (n) => phase(
      'Verifying $name · ${n ~/ (1024 * 1024)} / ${bytes ~/ (1024 * 1024)} MiB',
    ),
  );
  cancellation.check();
  await progressFile(file.parent, name);
  if (await file.length() != bytes)
    throw StateError('The Flycast disc changed during inspection. Try again.');
  if (header != null) {
    final input = await file.open();
    final Uint8List after;
    try {
      after = await input.read(124);
    } finally {
      await input.close();
    }
    if (base64Encode(after) != base64Encode(header))
      throw StateError('The Flycast CHD changed during inspection. Try again.');
  }
  return AndroidFlycastDisc._(file, bytes, hash);
}

const androidFlycastFirmware = <String, (int, String)>{
  'dc_boot.bin': (2097152, 'e10c53c2f8b90bab96ead2d368858623'),
};

class AndroidFlycastResource {
  AndroidFlycastResource._(this.name, this.file, this.sha256);
  final String name, sha256;
  final File file;
  int get bytes => androidFlycastFirmware[name]!.$1;
}

/// Verify an optional Dreamcast boot ROM; confirmed native HLE is cached too.
/// Failed discovery or a damaged known image must not become an empty result.
/// Older immutable cache objects survive repair; retail firmware comes from RomM.
Future<List<AndroidFlycastResource>> ensureAndroidFlycastResources(
  Directory profileRoot,
  int platform,
  RommClient client,
  DownloadCancellation cancellation,
  void Function(String) phase,
) async {
  const names = ['dc_boot.bin'];
  cancellation.check();
  if (names.isEmpty) return [];
  final index = await progressFile(
    profileRoot,
    'flycast-firmware/index.json',
    createParents: true,
  );
  var records = <String, dynamic>{};
  if (await progressExists(index.path)) {
    final saved = await progressJson(index);
    if (saved['version'] != 1 ||
        saved['platform'] != platform ||
        saved['resources'] is! Map)
      throw const FormatException(
        'The cached Flycast firmware record is invalid. Existing files were kept.',
      );
    records = (saved['resources'] as Map).cast<String, dynamic>();
    final boot = saved['boot'];
    if (boot != null && boot != 'rom' && boot != 'hle-fallback' ||
        boot == 'hle-fallback' && records.isNotEmpty ||
        boot == 'rom' && records.isEmpty) {
      throw const FormatException(
        'The cached Flycast boot choice conflicts with its firmware. Existing files were kept.',
      );
    }
    for (final entry in records.entries) {
      final value = entry.value;
      if (!androidFlycastFirmware.containsKey(entry.key) ||
          value is! Map ||
          !RegExp(r'^[a-f0-9]{32}$')
              .hasMatch(value['object'] as String? ?? '') ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String? ?? ''))
        throw const FormatException(
          'The cached Flycast resource identity is invalid. Existing files were kept.',
        );
    }
    if (boot == 'hle-fallback') {
      cancellation.check();
      return [];
    }
  }
  final result = <AndroidFlycastResource>[];
  for (final name in names) {
    cancellation.check();
    final (bytes, md5) = androidFlycastFirmware[name]!;
    final old = records[name] as Map?;
    if (old != null) {
      final file = await progressFile(index.parent, '${old['object']}.img');
      if (await file.exists() &&
          await file.length() == bytes &&
          await progressFileHash(file, md5: true) == md5 &&
          await progressFileHash(file) == old['sha256']) {
        result.add(
          AndroidFlycastResource._(name, file, old['sha256'] as String),
        );
        continue;
      }
    }
    phase('Checking RomM for $name…');
    final matches = (await client.firmware(platform))
        .where((f) => f.platformId == platform && f.name.toLowerCase() == name)
        .toList();
    cancellation.check();
    if (matches.isEmpty && old == null) {
      // A confirmed choice is reusable offline, like a verified boot image.
      // Missing/failed discovery never writes this marker. Later firmware
      // changes remain explicit rather than silently changing the boot mode.
      cancellation.check();
      await progressWrite(index, {
        'version': 1,
        'platform': platform,
        'boot': 'hle-fallback',
        'resources': <String, dynamic>{},
      });
      phase(
        'No Dreamcast boot ROM configured · Flycast will use its built-in HLE BIOS.',
      );
      continue;
    }
    if (matches.length != 1 ||
        matches.single.bytes != bytes ||
        matches.single.md5 != md5)
      throw RommFailure(
        'Add exactly one matching $name to this Flycast platform in RomM, before Play. Existing firmware was kept.',
      );
    final stage = await index.parent.createTemp('incoming-');
    var uncertain = false, timedOut = false;
    final timer = Timer(const Duration(seconds: 60), () {
      timedOut = true;
      cancellation.cancel();
    });
    try {
      phase('Downloading and verifying $name…');
      final incoming = File('${stage.path}/$name');
      await downloadAndroidFirmware(
        client,
        matches.single,
        incoming,
        cancellation,
      );
      if (await progressFileHash(incoming, md5: true) != md5 ||
          await incoming.length() != bytes)
        throw const FormatException(
          'The Flycast firmware does not match its required image.',
        );
      final hash = await progressFileHash(incoming), nonce = progressNonce();
      final target = await progressFile(index.parent, '$nonce.img');
      cancellation.check();
      await target.create(exclusive: true);
      await target.writeAsBytes(await incoming.readAsBytes(), flush: true);
      if (await target.length() != bytes ||
          await progressFileHash(target) != hash ||
          await progressFileHash(target, md5: true) != md5)
        throw const FileSystemException(
          'The verified Flycast firmware changed during publication.',
        );
      cancellation.check();
      records[name] = {'object': nonce, 'sha256': hash};
      await progressWrite(index, {
        'version': 1,
        'platform': platform,
        'resources': records,
      });
      result.add(AndroidFlycastResource._(name, target, hash));
    } on DownloadWriterUncertain {
      uncertain = true;
      rethrow;
    } on DownloadCancelled {
      if (timedOut)
        throw RommFailure('The $name download timed out. Try Play again.');
      rethrow;
    } finally {
      timer.cancel();
      if (!uncertain) await stage.delete(recursive: true);
    }
  }
  cancellation.check();
  return result;
}
