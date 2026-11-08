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

/// Match the original Android frontend's paths even though the session uses a
/// disposable configuration elsewhere. Explicit native paths remain unchanged.
Map<String, String> androidRetroOptionPaths(
  Map<String, String> preferences,
  String package,
) {
  final original = '/storage/emulated/0/Android/data/$package/files';
  String path(String key, String fallback) {
    final value = preferences[key];
    if (value == null || value.isEmpty || value == 'default') return fallback;
    return value.startsWith('/') ? value : '$original/$value';
  }

  return {
    'rgui_config_directory': path('rgui_config_directory', original),
    'core_options_path': path(
      'core_options_path',
      '$original/retroarch-core-options.cfg',
    ),
  };
}

/// The pinned frontend selects game, actual content-folder, core, then global
/// options. An absent core file inherits global values; files are not merged.
Future<Map<String, String>> readAndroidOperaOptions(
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
    if (gameSpecific) '$directory/Opera/$stem.opt',
    if (gameSpecific) '$directory/Opera/$folder.opt',
    if (perCore) '$directory/Opera/Opera.opt',
    paths['core_options_path']!,
  ]) {
    final bytes = await channel.invokeMethod<Uint8List>('rootOptions', {
      ...binding,
      'coreName': 'opera',
      'path': path,
    });
    if (bytes == null) continue;
    if (bytes.length > 262144)
      throw const FormatException('Opera core options are too large.');
    final text = utf8.decode(bytes), result = <String, String>{};
    for (final line in const LineSplitter().convert(text)) {
      if (RegExp(r'^\s*#include(?:\s|$)').hasMatch(line))
        throw const FormatException(
          'Opera options include another file. Use a self-contained core option file before rooted Play.',
        );
      final match = RegExp(
        r'^\s*(opera_[a-z0-9_]+)\s*=\s*"([^"\x00-\x1f]*)"\s*(?:#.*)?$',
      ).firstMatch(line);
      if (match == null) {
        if (RegExp(r'^\s*opera_').hasMatch(line))
          throw const FormatException(
            'Opera has an unreadable core option. Existing progress was kept.',
          );
        continue;
      }
      final key = match[1]!, value = match[2]!;
      if (result.containsKey(key) && result[key] != value)
        throw const FormatException(
          'Opera has conflicting core options. Existing progress was kept.',
        );
      result[key] = value;
    }
    return result;
  }
  return {};
}

String androidOperaRawSaveKey(Map<String, String> options, String stem) {
  final storage = options['opera_nvram_storage'] ?? 'per game';
  final version = options['opera_nvram_version'] ?? '0';
  if (!{'per game', 'shared'}.contains(storage) ||
      !RegExp(r'^[0-9]$').hasMatch(version))
    throw const FormatException(
      'Opera NVRAM options are not recognized. Existing progress was kept.',
    );
  final key = storage == 'shared'
      ? 'save/opera/shared/nvram.$version.srm'
      : 'save/opera/per_game/$stem.$version.srm';
  progressRelative(key);
  return key;
}

class AndroidOperaDisc {
  AndroidOperaDisc._(this.file, this.bytes, this.sha256);
  final File file;
  final int bytes;
  final String sha256;
}

/// Initial Opera media route: one self-contained image. CUE sets need their
/// complete file-set transport; they cannot be passed as a lone cartridge.
Future<AndroidOperaDisc> inspectAndroidOperaDisc(
  File file,
  DownloadCancellation cancellation,
  void Function(String) phase,
) async {
  cancellation.check();
  final extension = file.path.split('.').last.toLowerCase();
  if (!{'chd', 'iso', 'bin'}.contains(extension))
    throw UnsupportedError(
      'Rooted Opera currently needs a self-contained CHD, ISO or BIN image. Multi-file CUE discs are not connected yet.',
    );
  await progressFile(file.parent, file.uri.pathSegments.last);
  final bytes = await file.length();
  if (bytes < 1 || bytes > 1024 * 1024 * 1024)
    throw const FormatException(
      'The 3DO disc image must be between 1 byte and 1 GiB.',
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
        'The 3DO CHD header is incomplete or invalid.',
      );
    final fields = ByteData.sublistView(header);
    if (fields.getUint32(8) != 124 ||
        fields.getUint32(12) != 5 ||
        fields.getUint64(32) < 1 ||
        fields.getUint64(32) > 1024 * 1024 * 1024 ||
        header.skip(104).any((b) => b != 0))
      throw const FormatException(
        'Use a self-contained version-5 3DO CHD of at most 1 GiB, without a parent CHD.',
      );
  } else if (extension == 'bin') {
    final base = file.path.substring(0, file.path.length - 4);
    for (final suffix in ['.cue', '.CUE']) {
      if (await progressExists('$base$suffix'))
        throw UnsupportedError(
          'This BIN belongs to a CUE disc. Convert the complete disc to CHD before rooted Opera Play.',
        );
    }
  }
  final name = file.uri.pathSegments.last;
  phase('Verifying the 3DO disc…');
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
    throw StateError('The 3DO disc changed during inspection. Try again.');
  if (header != null) {
    final input = await file.open();
    final Uint8List after;
    try {
      after = await input.read(124);
    } finally {
      await input.close();
    }
    if (base64Encode(after) != base64Encode(header))
      throw StateError('The 3DO CHD changed during inspection. Try again.');
  }
  return AndroidOperaDisc._(file, bytes, hash);
}

const androidOperaFirmware = <String, (int, String)>{
  'opera-boot.bin': (131072, 'ad43f7905ba53da48c0b8d9643fb8cec'),
  'panafz1.bin': (1048576, 'f47264dd47fe30f73ab3c010015c155b'),
  'panafz1j.bin': (1048576, 'a496cfdded3da562759be3561317b605'),
  'panafz1j-norsa.bin': (1048576, 'f6c71de7470d16abe4f71b1444883dc8'),
  'panafz10.bin': (1048576, '51f2f43ae2f3508a14d9f56597e2d3ce'),
  'panafz10-norsa.bin': (1048576, '1477bda80dc33731a65468c1f5bcbee9'),
  'panafz10e-anvil.bin': (1048576, 'a48e6746bd7edec0f40cff078f0bb19f'),
  'panafz10e-anvil-norsa.bin': (1048576, 'cf11bbb5a16d7af9875cca9de9a15e09'),
  'goldstar.bin': (1048576, '8639fd5e549bd6238cfee79e3e749114'),
  'sanyotry.bin': (1048576, '35fa1a1ebaaeea286dc5cd15487c13ea'),
  '3do_arcade_saot.bin': (524288, '8970fc987ab89a7f64da9f8a8c4333ff'),
  'panafz1-kanji.bin': (933636, 'b8dc97f778a6245c58e064b0312e8281'),
  'panafz1j-kanji.bin': (1048576, 'c23fb5d5e6bb1c240d02cf968972be37'),
  'panafz10ja-anvil-kanji.bin': (1048576, '428577250f43edc902ea239c50d2240d'),
};

class AndroidOperaResource {
  AndroidOperaResource._(this.name, this.file, this.sha256);
  final String name, sha256;
  final File file;
  int get bytes => androidOperaFirmware[name]!.$1;
}

List<String> androidOperaResourceNames(Map<String, String> options) {
  final bios = options['opera_bios'] ?? 'opera-boot-internal';
  final font = options['opera_font'] ?? 'disabled';
  final names = <String>[];
  if (bios != 'opera-boot-internal') {
    if (!androidOperaFirmware.containsKey(bios) || bios.contains('kanji'))
      throw const FormatException(
        'Opera’s selected BIOS is not recognized. Select its built-in boot ROM or a supported BIOS.',
      );
    names.add(bios);
  }
  if (font != 'disabled') {
    if (!androidOperaFirmware.containsKey(font) || !font.contains('kanji'))
      throw const FormatException(
        'Opera’s selected font ROM is not recognized.',
      );
    names.add(font);
  }
  return names;
}

/// Only explicitly selected external resources are fetched. The default built-in
/// boot ROM requires no catalogue access. Older cache objects survive repair.
Future<List<AndroidOperaResource>> ensureAndroidOperaResources(
  Directory profileRoot,
  int platform,
  Map<String, String> options,
  RommClient client,
  DownloadCancellation cancellation,
  void Function(String) phase,
) async {
  final names = androidOperaResourceNames(options);
  cancellation.check();
  if (names.isEmpty) return [];
  final index = await progressFile(
    profileRoot,
    'opera-firmware/index.json',
    createParents: true,
  );
  var records = <String, dynamic>{};
  if (await progressExists(index.path)) {
    final saved = await progressJson(index);
    if (saved['version'] != 1 ||
        saved['platform'] != platform ||
        saved['resources'] is! Map)
      throw const FormatException(
        'The cached Opera firmware record is invalid. Existing files were kept.',
      );
    records = (saved['resources'] as Map).cast<String, dynamic>();
    for (final entry in records.entries) {
      final value = entry.value;
      if (!androidOperaFirmware.containsKey(entry.key) ||
          value is! Map ||
          !RegExp(r'^[a-f0-9]{32}$')
              .hasMatch(value['object'] as String? ?? '') ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String? ?? ''))
        throw const FormatException(
          'The cached Opera resource identity is invalid. Existing files were kept.',
        );
    }
  }
  final result = <AndroidOperaResource>[];
  for (final name in names) {
    cancellation.check();
    final (bytes, md5) = androidOperaFirmware[name]!;
    final old = records[name] as Map?;
    if (old != null) {
      final file = await progressFile(index.parent, '${old['object']}.img');
      if (await file.exists() &&
          await file.length() == bytes &&
          await progressFileHash(file, md5: true) == md5 &&
          await progressFileHash(file) == old['sha256']) {
        result.add(AndroidOperaResource._(name, file, old['sha256'] as String));
        continue;
      }
    }
    phase('Checking RomM for $name…');
    final matches = (await client.firmware(platform))
        .where((f) => f.platformId == platform && f.name.toLowerCase() == name)
        .toList();
    cancellation.check();
    if (matches.length != 1 ||
        matches.single.bytes != bytes ||
        matches.single.md5 != md5)
      throw RommFailure(
        'Add exactly one matching $name to this 3DO platform in RomM, or select Opera’s built-in boot ROM. Existing firmware was kept.',
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
          'The Opera firmware does not match its required image.',
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
          'The verified Opera firmware changed during publication.',
        );
      cancellation.check();
      records[name] = {'object': nonce, 'sha256': hash};
      await progressWrite(index, {
        'version': 1,
        'platform': platform,
        'resources': records,
      });
      result.add(AndroidOperaResource._(name, target, hash));
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
