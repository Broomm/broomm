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
Future<Map<String, String>> readAndroidSaturnOptions(
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
    if (gameSpecific) '$directory/Beetle Saturn/$stem.opt',
    if (gameSpecific) '$directory/Beetle Saturn/$folder.opt',
    if (perCore) '$directory/Beetle Saturn/Beetle Saturn.opt',
    paths['core_options_path']!,
  ]) {
    final bytes = await channel.invokeMethod<Uint8List>('rootOptions', {
      ...binding,
      'coreName': 'mednafen_saturn',
      'path': path,
    });
    if (bytes == null) continue;
    if (bytes.length > 262144)
      throw const FormatException('Saturn core options are too large.');
    final text = utf8.decode(bytes), result = <String, String>{};
    for (final line in const LineSplitter().convert(text)) {
      if (RegExp(r'^\s*#include(?:\s|$)').hasMatch(line))
        throw const FormatException(
          'Saturn options include another file. Use a self-contained core option file before rooted Play.',
        );
      final match = RegExp(
        r'^\s*(beetle_saturn_[a-z0-9_]+)\s*=\s*"([^"\x00-\x1f]*)"\s*(?:#.*)?$',
      ).firstMatch(line);
      if (match == null) {
        if (RegExp(r'^\s*beetle_saturn_').hasMatch(line))
          throw const FormatException(
            'Saturn has an unreadable core option. Existing progress was kept.',
          );
        continue;
      }
      final key = match[1]!, value = match[2]!;
      if (result.containsKey(key) && result[key] != value)
        throw const FormatException(
          'Saturn has conflicting core options. Existing progress was kept.',
        );
      result[key] = value;
    }
    return result;
  }
  return {};
}

class AndroidSaturnDisc {
  AndroidSaturnDisc._(this.file, this.bytes, this.sha256);
  final File file;
  final int bytes;
  final String sha256;
}

/// Initial Saturn media route: one self-contained image. CUE sets need their
/// complete file-set transport; they cannot be passed as a lone cartridge.
Future<AndroidSaturnDisc> inspectAndroidSaturnDisc(
  File file,
  DownloadCancellation cancellation,
  void Function(String) phase,
) async {
  cancellation.check();
  final extension = file.path.split('.').last.toLowerCase();
  if (extension != 'chd')
    throw UnsupportedError(
      'Rooted Saturn currently needs a self-contained CHD image. Multi-file CUE discs are not connected yet.',
    );
  await progressFile(file.parent, file.uri.pathSegments.last);
  final bytes = await file.length();
  if (bytes < 1 || bytes > 1024 * 1024 * 1024)
    throw const FormatException(
      'The Saturn disc image must be between 1 byte and 1 GiB.',
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
        'The Saturn CHD header is incomplete or invalid.',
      );
    final fields = ByteData.sublistView(header);
    if (fields.getUint32(8) != 124 ||
        fields.getUint32(12) != 5 ||
        fields.getUint64(32) < 1 ||
        fields.getUint64(32) > 1024 * 1024 * 1024 ||
        header.skip(104).any((b) => b != 0))
      throw const FormatException(
        'Use a self-contained version-5 Saturn CHD of at most 1 GiB, without a parent CHD.',
      );
  }
  final name = file.uri.pathSegments.last;
  phase('Verifying the Saturn disc…');
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
    throw StateError('The Saturn disc changed during inspection. Try again.');
  if (header != null) {
    final input = await file.open();
    final Uint8List after;
    try {
      after = await input.read(124);
    } finally {
      await input.close();
    }
    if (base64Encode(after) != base64Encode(header))
      throw StateError('The Saturn CHD changed during inspection. Try again.');
  }
  return AndroidSaturnDisc._(file, bytes, hash);
}

const androidSaturnFirmware = <String, (int, String)>{
  'sega_101.bin': (524288, '85ec9ca47d8f6807718151cbcca8b964'),
  'mpr-17933.bin': (524288, '3240872c70984b6cbfda1586cab68dbe'),
  'mpr-18811-mx.ic1': (2097152, '255113ba943c92a54facd25a10fd780c'),
  'mpr-19367-mx.ic1': (2097152, '1cd19988d1d72a3e7caa0b73234c96b4'),
};

class AndroidSaturnResource {
  AndroidSaturnResource._(this.name, this.file, this.sha256);
  final String name, sha256;
  final File file;
  int get bytes => androidSaturnFirmware[name]!.$1;
}

List<String> androidSaturnResourceNames(Map<String, String> options) {
  final cart = options['beetle_saturn_cart'] ?? 'Auto Detect';
  if (!{
    'Auto Detect',
    'None',
    'Backup Memory',
    'Extended RAM (1MB)',
    'Extended RAM (4MB)',
    "The King of Fighters '95",
    'Ultraman: Hikari no Kyojin Densetsu',
  }.contains(cart))
    throw const FormatException(
      'Saturn’s selected cartridge is not recognized. Existing progress was kept.',
    );
  return [
    'sega_101.bin',
    'mpr-17933.bin',
    if (cart == "The King of Fighters '95") 'mpr-18811-mx.ic1',
    if (cart == 'Ultraman: Hikari no Kyojin Densetsu') 'mpr-19367-mx.ic1',
  ];
}

String androidSaturnInternalName(Map<String, String> options, String stem) {
  final method = options['beetle_saturn_save_method'] ?? 'libretro';
  final shared = options['beetle_saturn_shared_int'] ?? 'disabled';
  if (!{'libretro', 'mednafen'}.contains(method) ||
      !{'enabled', 'disabled'}.contains(shared))
    throw const FormatException(
      'Saturn backup-memory options are not recognized. Existing progress was kept.',
    );
  return method == 'libretro'
      ? '$stem.srm'
      : '${shared == 'enabled' ? 'mednafen_saturn_libretro_shared' : stem}.bkr';
}

/// Never launch with an internal-memory filename the selected native mode ignores.
/// Historical source files remain untouched for an explicit native-mode choice.
void verifyAndroidSaturnWorking(
  Map<String, String> options,
  String stem,
  Iterable<String> paths,
) {
  final selected = androidSaturnInternalName(options, stem);
  final internal = paths.where(
    (p) => p.contains('/saves/') && (p.endsWith('.srm') || p.endsWith('.bkr')),
  );
  if (internal.isNotEmpty &&
      !internal.any((p) => p.split('/').last == selected))
    throw const FormatException(
      'The saved Saturn internal memory uses a different native mode. In RetroArch, select the matching Save Method / Shared Internal Memory option, then try Play again. All copies were kept.',
    );
  final size = options['beetle_saturn_backup_memory_size'] ?? 'Default';
  final shared = options['beetle_saturn_shared_ext'] ?? 'disabled';
  if (!{'Default', '4MB'}.contains(size) ||
      !{'enabled', 'disabled'}.contains(shared))
    throw const FormatException(
      'Saturn backup-cartridge options are not recognized. Existing progress was kept.',
    );
  final cart =
      '${shared == 'enabled' ? 'mednafen_saturn_libretro_shared' : stem}.${size == '4MB' ? '4mb.bcr' : 'bcr'}';
  final carts = paths.where((p) => p.contains('/saves/') && p.endsWith('.bcr'));
  if (carts.isNotEmpty && !carts.any((p) => p.split('/').last == cart))
    throw const FormatException(
      'The saved Saturn backup cartridge uses a different size or sharing mode. In RetroArch, select its matching Backup Memory Size / Shared Backup Memory option, then try Play again. All copies were kept.',
    );
}

/// Verify both regional BIOS images and an explicitly selected ROM cartridge.
/// Older immutable cache objects survive repair; retail firmware comes from RomM.
Future<List<AndroidSaturnResource>> ensureAndroidSaturnResources(
  Directory profileRoot,
  int platform,
  Map<String, String> options,
  RommClient client,
  DownloadCancellation cancellation,
  void Function(String) phase,
) async {
  final names = androidSaturnResourceNames(options);
  cancellation.check();
  if (names.isEmpty) return [];
  final index = await progressFile(
    profileRoot,
    'saturn-firmware/index.json',
    createParents: true,
  );
  var records = <String, dynamic>{};
  if (await progressExists(index.path)) {
    final saved = await progressJson(index);
    if (saved['version'] != 1 ||
        saved['platform'] != platform ||
        saved['resources'] is! Map)
      throw const FormatException(
        'The cached Saturn firmware record is invalid. Existing files were kept.',
      );
    records = (saved['resources'] as Map).cast<String, dynamic>();
    for (final entry in records.entries) {
      final value = entry.value;
      if (!androidSaturnFirmware.containsKey(entry.key) ||
          value is! Map ||
          !RegExp(r'^[a-f0-9]{32}$')
              .hasMatch(value['object'] as String? ?? '') ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String? ?? ''))
        throw const FormatException(
          'The cached Saturn resource identity is invalid. Existing files were kept.',
        );
    }
  }
  final result = <AndroidSaturnResource>[];
  for (final name in names) {
    cancellation.check();
    final (bytes, md5) = androidSaturnFirmware[name]!;
    final old = records[name] as Map?;
    if (old != null) {
      final file = await progressFile(index.parent, '${old['object']}.img');
      if (await file.exists() &&
          await file.length() == bytes &&
          await progressFileHash(file, md5: true) == md5 &&
          await progressFileHash(file) == old['sha256']) {
        result.add(
          AndroidSaturnResource._(name, file, old['sha256'] as String),
        );
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
        'Add exactly one matching $name to this Saturn platform in RomM, before Play. Existing firmware was kept.',
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
          'The Saturn firmware does not match its required image.',
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
          'The verified Saturn firmware changed during publication.',
        );
      cancellation.check();
      records[name] = {'object': nonce, 'sha256': hash};
      await progressWrite(index, {
        'version': 1,
        'platform': platform,
        'resources': records,
      });
      result.add(AndroidSaturnResource._(name, target, hash));
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
