import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'digest.dart';
import 'files.dart';
import 'layout.dart';
import 'zip.dart';
import '../playstation.dart';

part 'native_export.dart';

class NotProgressBundle extends FormatException {
  const NotProgressBundle() : super('This is not a Broomm save bundle');
}

class ProgressSnapshot {
  const ProgressSnapshot(this.directory, this.manifest);
  final Directory directory;
  final Map<String, dynamic> manifest;
  String get id => manifest['commit'] as String;
  String get digest => manifest['digest'] as String;
  Map<String, dynamic> get entries =>
      (manifest['files'] as Map).cast<String, dynamic>();
  List<String> get parents => (manifest['parents'] as List).cast<String>();
  File get bundle => File('${directory.path}/broomm');
  bool get empty => entries.isEmpty;
  bool get hasStates => entries.keys.any((k) => k.startsWith('states-'));
  bool get nativeRemote => manifest['nativeRemote'] == true;
  String get ordinaryDigest => progressEntriesDigest({
    for (final e in entries.entries)
      if (!e.key.startsWith('states-')) e.key: e.value,
  });
}

String progressEntriesDigest(Map<String, dynamic> entries) {
  final keys = entries.keys.toList()..sort();
  final digest = ProgressDigest.sha256()
    ..add(
      utf8.encode(
        jsonEncode([
          for (final k in keys) [k, entries[k]['bytes'], entries[k]['sha256']],
        ]),
      ),
    );
  return digest.finish();
}

class ProgressStore {
  const ProgressStore(
    this.directory,
    this.layout,
    this.romId,
    this.userId, {
    this.ownerRoot,
  });
  final Directory? ownerRoot;
  final Directory directory;
  final ProgressLayout layout;
  final int romId, userId;
  File get stateFile => File('${directory.path}/state.json');
  File get journal => File('${directory.path}/restore.json');
  Future<void> _check() async {
    final anchor = ownerRoot;
    if (anchor != null) {
      if (!directory.path.startsWith('${anchor.path}/'))
        throw const FileSystemException('Invalid progress storage owner');
      await progressFile(
        anchor,
        '${directory.path.substring(anchor.path.length + 1)}/.probe',
        createParents: true,
      );
    } else {
      await progressDirectory(directory);
    }
  }

  Future<Map<String, dynamic>> state() async {
    await _check();
    return await progressExists(stateFile.path)
        ? progressJson(stateFile)
        : <String, dynamic>{};
  }

  Future<void> save(Map<String, dynamic> state) async {
    await _check();
    await progressWrite(stateFile, state);
  }

  /// Only prune after a confirmed common version or explicit conflict choice.
  /// Pending uploads, an interrupted backup, and the newest ten copies survive.
  Future<void> pruneConfirmed() => Isolate.run(() async {
    final current = await state();
    if (current['pending'] != false || current['conflict'] != null) return;
    final keep = <String>{
      for (final key in ['snapshot', 'local', 'upload'])
        if (current[key] is String) current[key] as String,
    };
    final backup = File('${directory.path}/backup.json');
    if (await progressExists(backup.path)) {
      final record = await progressJson(backup);
      if (record['snapshot'] is String) keep.add(record['snapshot'] as String);
    }
    final snapshots = <(DateTime, String, Directory)>[];
    final base = Directory('${directory.path}/snapshots');
    await progressFile(directory, 'snapshots/.probe');
    await for (final entry in base.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final id = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) continue;
      final record = File('${entry.path}/manifest.json');
      if (!await progressExists(record.path)) continue;
      final manifest = await progressJson(record);
      if (manifest['version'] != 1 ||
          manifest['rom'] != romId ||
          manifest['user'] != userId ||
          manifest['identity'] != layout.identity)
        continue;
      snapshots.add(((await record.stat()).modified, id, entry));
    }
    snapshots.sort((a, b) {
      final time = b.$1.compareTo(a.$1);
      return time != 0 ? time : b.$2.compareTo(a.$2);
    });
    for (final entry in snapshots.take(10)) {
      keep.add(entry.$2);
    }
    for (final entry in snapshots) {
      if (!keep.contains(entry.$2)) await entry.$3.delete(recursive: true);
    }
  });

  Future<Directory> _new() async {
    await _check();
    await progressFile(directory, 'snapshots/.probe', createParents: true);
    final dest = Directory('${directory.path}/snapshots/${progressNonce()}');
    await dest.create();
    await Directory('${dest.path}/files').create();
    return dest;
  }

  Future<ProgressSnapshot> _stage(
    Future<ProgressSnapshot> Function(Directory) work,
  ) async {
    final dir = await _new();
    try {
      return await work(dir);
    } catch (_) {
      // Only this attempt's private, exclusively named staging copy is removed.
      // Native files and completed recovery versions are never part of cleanup.
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        /* Retain on storage failure. */
      }
      rethrow;
    }
  }

  Future<ProgressSnapshot> capture({
    List<String> parents = const [],
    ProgressSnapshot? retained,
    Map<String, String>? knownStates,
  }) => Isolate.run(
    () => _stage((dir) async {
      final files = <String, dynamic>{};
      final native = await layout.files();
      for (final e in native.entries) {
        final out = await progressFile(
          Directory('${dir.path}/files'),
          e.key,
          createParents: true,
        );
        final before = await progressFileHash(e.value);
        if (e.key.startsWith('states-') &&
            knownStates != null &&
            knownStates[e.key] != before) {
          // Keep a remote compatible state when a legacy local file occupies
          // its path. Unknown native bytes must not be attributed to this build.
          if (retained?.entries.containsKey(e.key) == true) {
            await _copy(
              await progressFile(
                Directory('${retained!.directory.path}/files'),
                e.key,
              ),
              out,
            );
            files[e.key] = retained.entries[e.key];
          }
          continue;
        }
        await _copy(e.value, out);
        final hash = await progressFileHash(out);
        if (hash != before || await progressFileHash(e.value) != before)
          throw const FileSystemException(
            'Game progress changed during its recovery snapshot. Nothing was uploaded.',
          );
        files[e.key] = {'sha256': hash, 'bytes': await out.length()};
      }
      // Preserve states belonging to other hosts/builds in the same managed file.
      if (retained != null) {
        for (final e in retained.entries.entries) {
          if (layout.areas.any((a) => e.key.startsWith('${a.id}/'))) continue;
          if (!e.key.startsWith('states-'))
            throw const FormatException('Unsupported progress area');
          await _copy(
            await progressFile(
              Directory('${retained.directory.path}/files'),
              e.key,
            ),
            await progressFile(
              Directory('${dir.path}/files'),
              e.key,
              createParents: true,
            ),
          );
          files[e.key] = e.value;
        }
      }
      return _seal(dir, files, parents);
    }),
  );
  Future<ProgressSnapshot> _seal(
    Directory dir,
    Map<String, dynamic> entries,
    List<String> parents, {
    String? remoteCommit,
  }) async {
    if (entries.length >= progressMaxFiles)
      throw const FormatException(
        'A save bundle supports at most 4095 progress files',
      );
    final keys = entries.keys.toList()..sort();
    final d = ProgressDigest.sha256();
    d.add(
      utf8.encode(
        jsonEncode([
          for (final key in keys)
            [key, entries[key]['bytes'], entries[key]['sha256']],
        ]),
      ),
    );
    final m = <String, dynamic>{
      'version': 1,
      'rom': romId,
      'user': userId,
      'identity': layout.identity,
      'commit':
          remoteCommit ?? dir.uri.pathSegments.where((s) => s.isNotEmpty).last,
      if (remoteCommit != null) 'nativeRemote': true,
      'parents': parents.toSet().take(256).toList(),
      'created': DateTime.now().toUtc().toIso8601String(),
      'digest': d.finish(),
      'files': entries,
    };
    await progressWrite(File('${dir.path}/files/broomm.json'), m);
    await ProgressZip.write(
      File('${dir.path}/broomm'),
      Directory('${dir.path}/files'),
      ['broomm.json', ...keys],
    );
    await progressWrite(File('${dir.path}/manifest.json'), m);
    return ProgressSnapshot(dir, m);
  }

  Future<ProgressSnapshot> load(String id) => Isolate.run(() => _load(id));
  Future<ProgressSnapshot> _load(String id) async {
    await _check();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id))
      throw const FormatException('Invalid save recovery identity');
    final dir = Directory('${directory.path}/snapshots/$id');
    final m = await progressJson(
      await progressFile(directory, 'snapshots/$id/manifest.json'),
    );
    await _verify(dir, m);
    return ProgressSnapshot(dir, m);
  }

  Future<void> _verify(Directory dir, Map<String, dynamic> m) async {
    if (m['version'] != 1 ||
        m['rom'] != romId ||
        m['user'] != userId ||
        m['identity'] != layout.identity ||
        m['created'] is! String ||
        (m['created'] as String).length > 40 ||
        DateTime.tryParse(m['created'] as String) == null ||
        m['commit'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(m['commit'] as String) ||
        m['parents'] is! List ||
        (m['parents'] as List).length > 256 ||
        (m['parents'] as List).any(
          (p) => p is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(p),
        ) ||
        m['files'] is! Map ||
        (m['files'] as Map).length > progressMaxFiles)
      throw const FormatException(
        'This save does not match the selected account, game or supported format',
      );
    var total = 0;
    final entries = (m['files'] as Map).cast<String, dynamic>();
    final keys = entries.keys.toList()..sort();
    final d = ProgressDigest.sha256();
    for (final key in keys) {
      progressRelative(key);
      final v = entries[key];
      if (v is! Map ||
          v['bytes'] is! int ||
          v['bytes'] < 0 ||
          v['bytes'] > progressMaxFileBytes ||
          v['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(v['sha256']))
        throw const FormatException('Invalid save file inventory');
      final group = key.split('/').first;
      final area = layout.areas.where((a) => a.id == group).firstOrNull;
      if (area == null) {
        if (!(layout.archiveOnly &&
                RegExp(
                  r'^(save|device|card[AB]|ext-[a-f0-9]{8}|dlc-[a-f0-9]{8})$',
                ).hasMatch(group)) &&
            !RegExp(r'^states-[a-f0-9]{16}-[a-z]+-[a-z0-9]+$').hasMatch(group))
          throw const FormatException('Unsupported save area');
      } else {
        final native = area.native(key.substring(group.length + 1));
        if (!area.accepts(native))
          throw const FormatException('Save belongs to another game');
      }
      final file = await progressFile(Directory('${dir.path}/files'), key);
      if (await file.length() != v['bytes'] ||
          await progressFileHash(file) != v['sha256'])
        throw const FormatException('Save data failed its integrity check');
      if (area?.gciId != null && !await progressGciMatches(file, area!.gciId!))
        throw const FormatException('GameCube save belongs to another game');
      total += v['bytes'] as int;
      if (total > progressMaxBytes)
        throw const FormatException('Save bundle is too large');
    }
    d.add(
      utf8.encode(
        jsonEncode([
          for (final k in keys) [k, entries[k]['bytes'], entries[k]['sha256']],
        ]),
      ),
    );
    if (d.finish() != m['digest'])
      throw const FormatException('Save inventory failed its integrity check');
  }

  Future<ProgressSnapshot> importBundle(File bundle, {String? expectedHash}) =>
      Isolate.run(() async {
        final header = await bundle
            .openRead(0, 4)
            .fold<List<int>>([], (a, b) => a..addAll(b));
        if (header.length != 4 ||
            header[0] != 0x50 ||
            header[1] != 0x4b ||
            !((header[2] == 3 && header[3] == 4) ||
                (header[2] == 5 && header[3] == 6)))
          throw const NotProgressBundle();
        final zip = await ProgressZip.read(bundle);
        if (!zip.entries.any((e) => e.name == 'broomm.json'))
          throw const NotProgressBundle();
        return _stage((dir) async {
          final extracted = await zip.extract(Directory('${dir.path}/files'));
          if (expectedHash != null && rommZipHash(extracted) != expectedHash)
            throw const FormatException(
              'RomM save checksum did not match. Nothing was restored.',
            );
          final manifest = File('${dir.path}/files/broomm.json');
          final m = await progressJson(manifest);
          final expected = {'broomm.json', ...(m['files'] as Map).keys};
          if (extracted.length != expected.length ||
              extracted.keys.any((k) => !expected.contains(k)))
            throw const FormatException('The save has unrecognized files');
          await _verify(dir, m);
          // Give the local immutable copy its own storage ID; preserve remote commit in manifest.
          await _copy(bundle, File('${dir.path}/broomm'));
          await progressWrite(File('${dir.path}/manifest.json'), m);
          return ProgressSnapshot(dir, m);
        });
      });

  /// Explicit import only. A native ZIP is a title's data directory, never a
  /// whole emulator home. Unrecognized binary .sav containers are not guessed.
  Future<ProgressSnapshot> importNative(
    File file, {
    String? expectedHash,
    String? remoteCommit,
  }) => Isolate.run(
    () => _stage((dir) async {
      final entries = <String, dynamic>{};
      final bytes = await file
          .openRead(0, 4)
          .fold<List<int>>([], (a, b) => a..addAll(b));
      final raw = Directory('${dir.path}/native');
      await raw.create();
      if (bytes.length == 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4b &&
          ((bytes[2] == 3 && bytes[3] == 4) ||
              (bytes[2] == 5 && bytes[3] == 6))) {
        final extracted = await (await ProgressZip.read(file)).extract(raw);
        if (expectedHash != null && rommZipHash(extracted) != expectedHash)
          throw const FormatException('RomM save checksum did not match');
      } else if (layout.rawSaveKey != null) {
        if (expectedHash != null &&
            await progressFileHash(file, md5: true) != expectedHash)
          throw const FormatException('RomM save checksum did not match');
        if (layout.format == 'libretro-opera-v1' &&
            await file.length() != 32768)
          throw const FormatException(
            'Select a raw 32 KiB Opera NVRAM .srm or a complete native save ZIP',
          );
        if ({'duckstation-cards-v1', 'ps2-cards-v1'}.contains(layout.format) &&
            !await isPlayStationMemoryCard(
              file,
              ps2: layout.format == 'ps2-cards-v1',
            ))
          throw const FormatException(
            'Select a native whole PlayStation memory card. Individual game exports and headered containers require conversion first.',
          );
        final key = layout.rawSaveKey!;
        progressRelative(key);
        if (!key.startsWith('save/'))
          throw const FormatException('Invalid raw save area');
        await _copy(
          file,
          await progressFile(raw, key.substring(5), createParents: true),
        );
      } else if (layout.format == 'dolphin-gci-v1' &&
          await progressGciMatches(file, layout.game)) {
        if (expectedHash != null &&
            await progressFileHash(file, md5: true) != expectedHash)
          throw const FormatException('RomM save checksum did not match');
        await _copy(file, File('${raw.path}/imported.gci'));
      } else {
        throw const FormatException(
          'Use a Broomm backup or a ZIP of this emulator’s exported game save directory. Raw console .sav containers need conversion first.',
        );
      }
      await for (final e in raw.list(recursive: true, followLinks: false)) {
        if (e is Directory) continue;
        if (e is! File)
          throw const FormatException('Unsupported native save entry');
        var rel = e.path
            .substring(raw.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        if (rel.startsWith('data/') && layout.format == 'azahar-data-v1')
          rel = rel.substring(5);
        if (layout.format == 'ppsspp-savedata-v1') {
          if (rel.startsWith('PSP/SAVEDATA/'))
            rel = rel.substring(13);
          else if (rel.startsWith('SAVEDATA/'))
            rel = rel.substring(9);
        }
        var group = layout.format == 'dolphin-gci-v1' ? 'cardA' : 'save';
        final slash = rel.indexOf('/');
        if (slash > 0 &&
            (layout.areas.any(
                  (a) =>
                      a.id == rel.substring(0, slash) &&
                      !a.id.startsWith('states-'),
                ) ||
                layout.archiveOnly &&
                    RegExp(
                      r'^(save|device|card[AB]|ext-[a-f0-9]{8}|dlc-[a-f0-9]{8})$',
                    ).hasMatch(rel.substring(0, slash)))) {
          group = rel.substring(0, slash);
          rel = rel.substring(slash + 1);
        }
        final a = layout.archiveOnly ? null : layout.area(group);
        if ({'duckstation-cards-v1', 'ps2-cards-v1'}.contains(layout.format)) {
          final ps2 = layout.format == 'ps2-cards-v1';
          if (group != 'save' || !await isPlayStationMemoryCard(e, ps2: ps2))
            throw const FormatException(
              'Select a ZIP containing only this game’s native whole memory cards.',
            );
          final allowed = ps2
              ? {'slot1.ps2', 'slot2.ps2'}
              : {'card1.mcd', 'card2.mcd'};
          if (!allowed.contains(rel)) {
            if (entries.isNotEmpty)
              throw const FormatException(
                'Name both imported cards by their Broomm slots or import one raw card.',
              );
            rel = ps2 ? 'slot1.ps2' : 'card1.mcd';
          }
        }
        if (layout.format == 'libretro-flycast-v1' && group == 'save') {
          final vmu = RegExp(r'^.+\.([A-D][12])\.bin$').firstMatch(rel);
          if (rel.contains('/') ||
              vmu == null ||
              await e.length() != 128 * 1024)
            throw const FormatException(
              'Select a ZIP of this game’s raw 128 KiB Flycast VMU cards (.A1.bin, .B1.bin, and other ports). Firmware and console flash are not game saves.',
            );
          // This build uses the disc product ID (not its filename). Preserve
          // that native name inside the already isolated per-game directory.
        }
        if (layout.format == 'snes9x-sram-v1' ||
            layout.format.startsWith('libretro-') &&
                a?.prefix != null &&
                layout.format != 'libretro-flycast-v1') {
          if (layout.format == 'snes9x-sram-v1' &&
              (!rel.endsWith('.srm') || entries.isNotEmpty))
            throw const FormatException('Select a single Snes9x SRAM save');
          if (layout.format == 'snes9x-sram-v1' ||
              rel.toLowerCase().endsWith('.srm') ||
              rel.toLowerCase().endsWith('.sav'))
            rel = 'game.srm';
          else if (rel.toLowerCase().endsWith('.rtc'))
            rel = 'game.rtc';
        }
        if (layout.format == 'melonds-sav-v1') {
          if (!rel.toLowerCase().endsWith('.sav') ||
              entries.isNotEmpty ||
              !{
                512,
                8192,
                65536,
                131072,
                262144,
                524288,
                1048576,
                8388608,
              }.contains(await e.length()))
            throw const FormatException(
              'Select one raw DS .sav. Export DeSmuME/Drastic containers to raw .sav first.',
            );
          rel = 'game.sav';
        }
        if (a != null && !a.accepts(a.native(rel)))
          throw const FormatException(
            'The selected archive is not a save directory for this game',
          );
        final dest = await progressFile(
          Directory('${dir.path}/files'),
          '$group/$rel',
          createParents: true,
        );
        await _copy(e, dest);
        entries['$group/$rel'] = {
          'sha256': await progressFileHash(dest),
          'bytes': await dest.length(),
        };
      }
      if (entries.isEmpty)
        throw const FormatException('The selected save is empty');
      if (layout.format == 'azahar-data-v1' &&
          (!entries.containsKey('save/00000001.metadata') ||
              !entries.keys.any((k) => k.startsWith('save/00000001/'))))
        throw const FormatException(
          'Export Azahar’s whole title data directory, including 00000001.metadata and 00000001/, into one ZIP. Raw .sav files and a lone inner save folder are not compatible imports.',
        );
      final snapshot = await _seal(
        dir,
        entries,
        [],
        remoteCommit: remoteCommit,
      );
      await _verify(dir, snapshot.manifest);
      return snapshot;
    }),
  );

  String storageId(ProgressSnapshot s) =>
      s.directory.uri.pathSegments.where((p) => p.isNotEmpty).last;
  Future<Map<String, String>> stateFiles() => Isolate.run(() async {
    final result = <String, String>{};
    for (final e in (await layout.files()).entries) {
      if (e.key.startsWith('states-'))
        result[e.key] = await progressFileHash(e.value);
    }
    return result;
  });
  Future<int> restore(
    ProgressSnapshot next,
    Map<String, dynamic> nextState, {
    Map<String, String>? knownStates,
  }) async {
    final before = await capture();
    final protected = [
      if (knownStates != null)
        for (final e in before.entries.entries)
          if (e.key.startsWith('states-') &&
              knownStates[e.key] != e.value['sha256'])
            e.key,
    ];
    await progressWrite(journal, {
      'before': storageId(before),
      'after': storageId(next),
      'state': nextState,
      'protected': protected,
    });
    await recover();
    return protected.length;
  }

  Future<void> recover() => Isolate.run(() async {
    if (!await progressExists(journal.path)) return;
    final j = await progressJson(journal);
    final before = await load(j['before'] as String),
        after = await load(j['after'] as String);
    final keys = {...before.entries.keys, ...after.entries.keys};
    final protected = (j['protected'] as List? ?? []).cast<String>().toSet();
    if (protected.any(
      (k) => !k.startsWith('states-') || !before.entries.containsKey(k),
    ))
      throw const FormatException('Invalid protected state recovery inventory');
    for (final key in keys) {
      if (protected.contains(key)) continue;
      if (!layout.areas.any((a) => key.startsWith('${a.id}/'))) continue;
      final target = await layout.target(key);
      final current = await target.exists()
          ? await progressFileHash(target)
          : null;
      final oldHash = before.entries[key]?['sha256'],
          newHash = after.entries[key]?['sha256'];
      if (current != oldHash && current != newHash)
        throw const FileSystemException(
          'Game progress changed during restore. Recovery copies were kept; close all emulators and retry.',
        );
      if (current == newHash) continue;
      if (newHash == null) {
        await target.delete();
        continue;
      }
      final stage = await target.parent.createTemp('.broomm-save-');
      try {
        final temp = File('${stage.path}/file');
        await _copy(
          await progressFile(Directory('${after.directory.path}/files'), key),
          temp,
        );
        if (await progressFileHash(temp) != newHash)
          throw const FileSystemException('Save restore failed readback');
        await temp.rename(target.path);
      } finally {
        await stage.delete(recursive: true);
      }
    }
    await save((j['state'] as Map).cast<String, dynamic>());
    await journal.delete();
  });
}

Future<void> _copy(File source, File dest) async {
  if (await source.length() > progressMaxBytes)
    throw const FileSystemException('Save file is too large');
  await dest.create(exclusive: true);
  final f = await dest.open(mode: FileMode.writeOnly);
  try {
    await for (final b in source.openRead()) {
      await f.writeFrom(b);
    }
    await f.flush();
  } finally {
    await f.close();
  }
}
