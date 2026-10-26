import 'dart:convert';
import 'dart:io';

import '../game_launch.dart';
import '../managed_emulators.dart'
    show ownedDirectory, sha256File, runOwnedTool;
import '../romm/client.dart';
import '../romm/models.dart';
import '../romm/transfer.dart';
import '../session_lease.dart';
import '../shell/library.dart';
import 'azahar_import.dart';
import 'files.dart';
import 'profile.dart';
import 'three_ds.dart';

typedef PrepareAddonProfile = Future<(String, Directory)> Function(
  String,
  DownloadCancellation,
);
typedef ImportCia = Future<void> Function(
  String,
  String,
  Directory,
  DownloadCancellation,
);

class AddonResult {
  const AddonResult(this.installed, this.available);
  final int installed, available;
  String get message => available == 0
      ? 'No updates or DLC are available for this game in RomM.'
      : installed == 0
      ? 'Updates and DLC are up to date.'
      : 'Installed $installed update/DLC ${installed == 1 ? 'package' : 'packages'}.';
}

String? addonKind(RommFile f, String relative) {
  final first = relative.split('/').first.toLowerCase();
  if (first == 'updates' || first == 'update') return 'update';
  if (first == 'dlc') return 'dlc';
  return f.category == 'update' || f.category == 'dlc' ? f.category : null;
}

/// One concrete integration, with shared immutable payloads and private native
/// copies. The session lease covers downloads, import, profile publication and
/// recovery; no emulator writer can observe a partially applied installation.
class GameAddons {
  GameAddons(
    this.data,
    this.library, {
    required this.prepare,
    ImportCia? importer,
    this.phase,
    this.checkpoint,
  }) : importer = importer ?? installAzaharCia;
  final Directory data;
  final GameLibrary library;
  final PrepareAddonProfile prepare;
  final ImportCia importer;
  final void Function(String)? phase, checkpoint;

  Future<Directory> _game(String server, int game, {bool create = true}) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(server) || game < 1)
      throw const FormatException('Invalid add-on game identity');
    final path = await addonPath(
      data,
      'addons/$server/$game/current.json',
      createParents: create,
    );
    return File(path).parent;
  }

  Future<Map<String, dynamic>?> _current(
    Directory dir,
    String server,
    int id,
  ) async {
    final file = File('${dir.path}/current.json');
    if (!await addonExists(file.path)) return null;
    final j = await addonJson(file);
    if (j['version'] != 1 ||
        j['server'] != server ||
        j['game'] != id ||
        j['base'] is! String ||
        !RegExp(r'^00040000[0-9a-f]{8}$').hasMatch(j['base'] as String) ||
        j['generation'] is! String ||
        !RegExp(r'^generation-[a-zA-Z0-9_-]+$')
            .hasMatch(j['generation'] as String) ||
        j['sources'] is! Map ||
        (j['sources'] as Map).length > 1024 ||
        j['units'] is! Map)
      throw const FormatException('Invalid shared add-on record');
    await addonPath(dir, '${j['generation']}/manifest.json');
    final generation = await addonJson(
      File('${dir.path}/${j['generation']}/manifest.json'),
    );
    if (jsonEncode(generation) != jsonEncode(j))
      throw const FileSystemException(
        'Shared add-on ownership record is inconsistent',
      );
    return j;
  }

  String? _crc(RommFile f) =>
      f.rawCrc &&
          f.crc != null &&
          RegExp(r'^[0-9a-fA-F]{1,8}$').hasMatch(f.crc!)
      ? f.crc!.toLowerCase().padLeft(8, '0')
      : null;
  String? _sha1(RommFile f) =>
      f.sha1 != null && RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(f.sha1!)
      ? f.sha1!.toLowerCase()
      : null;
  Map<String, dynamic> _remote(RommFile f, String path) => {
    'id': f.id,
    'path': path,
    'bytes': f.bytes,
    'crc': _crc(f),
    'sha1': _sha1(f),
    'modified': f.modified,
    'category': f.category,
  };
  bool _sameSource(Map? old, Map remote) =>
      old != null &&
      (remote['crc'] != null || remote['sha1'] != null) &&
      [
        'id',
        'path',
        'bytes',
        'category',
        'crc',
        'sha1',
      ].every((k) => old[k] == remote[k]);

  Future<AddonResult> sync({
    required String serverId,
    required String profileId,
    required InstalledGame entry,
    required RommGame game,
    required RommClient client,
    required DownloadCancellation cancellation,
    required void Function(DownloadProgress) progress,
  }) async {
    final lease = await SessionLease.acquire(data);
    try {
      cancellation.check();
      if (game.id != entry.game.id ||
          gamePlatform(game, const [])?.slug != '3ds')
        throw const RommFailure(
          'Updates and DLC installation currently supports Nintendo 3DS games only.',
        );
      final paths = gameFilePaths(game);
      final remote = <(RommFile, String, String)>[];
      for (var i = 0; i < paths.length; i++) {
        final kind = addonKind(game.files[i], paths[i]);
        if (kind == null) continue;
        if (game.files[i].bytes > 16 * 1024 * 1024 * 1024)
          throw const RommFailure(
            'This 3DS add-on exceeds the supported 16 GiB package limit.',
          );
        if (!paths[i].toLowerCase().endsWith('.cia'))
          throw RommFailure(
            'The $kind file ${game.files[i].name} is not an unpacked CIA. Extract it in RomM and retry; the downloaded game is kept.',
          );
        remote.add((game.files[i], paths[i], kind));
      }
      if (remote.length > 1024)
        throw const RommFailure('Too many add-on packages for one game.');
      final dir = await _game(serverId, game.id);
      if (await addonExists('${dir.path}/deleting.json'))
        throw const RommFailure(
          'Finish deleting this game before installing its updates and DLC.',
        );
      final previous = await _current(dir, serverId, game.id);
      await _finishRetired(dir, serverId, game.id);
      if (remote.isEmpty && previous == null) return const AddonResult(0, 0);
      final local = await library.contentFiles(entry);
      final baseFiles = gameCandidates(
        playablePlatforms.singleWhere((p) => p.slug == '3ds'),
        local,
      );
      if (baseFiles.isEmpty)
        throw const RommFailure(
          'A supported 3DS base ROM is required to verify its updates and DLC.',
        );
      final ids = <String>{};
      for (final rom in baseFiles) {
        ids.add(await readThreeDsGameId(rom));
      }
      if (ids.length != 1)
        throw const RommFailure(
          'The installed folder contains different 3DS titles. Keep each title in its own RomM game folder.',
        );
      final base = ids.single;
      if (previous != null && previous['base'] != base)
        throw const RommFailure(
          'The base game title changed. Existing add-on records were kept.',
        );
      phase?.call('Verifying managed Azahar for ROM ${game.id}');
      progress(
        DownloadProgress(game, 'Preparing Azahar add-on installation', 0, 0),
      );
      final (executable, profile) = await prepare(profileId, cancellation);
      await _validateProfile(profileId, profile);
      final oldSources = previous?['sources'] as Map? ?? {};
      final changed = remote
          .where(
            (r) => !_sameSource(
              (oldSources['${r.$1.id}'] as Map?)?['remote'] as Map?,
              _remote(r.$1, r.$2),
            ),
          )
          .toList();
      // Verify canonical payload on every apply, even an unchanged remote list.
      if (previous != null) await _verifyPayload(dir, previous);
      if (changed.isEmpty) {
        if (previous != null)
          await _apply(serverId, game.id, profile, dir, previous);
        return AddonResult(0, remote.length);
      }
      final stage = await dir.createTemp('.import-');
      var published = false;
      try {
        final sources =
            jsonDecode(jsonEncode(oldSources)) as Map<String, dynamic>;
        final packages = Directory('${stage.path}/packages');
        await ownedDirectory(packages);
        // Immutable generations are self-contained; previous CIAs remain
        // recoverable until a replacement generation is fully committed.
        if (previous != null) {
          final oldPackages = Directory(
            '${dir.path}/${previous['generation']}/packages',
          );
          for (final e in sources.entries) {
            if (!RegExp(r'^[1-9][0-9]*$').hasMatch(e.key))
              throw const FormatException('Invalid add-on file identity');
            final source = await addonFile(oldPackages, '${e.key}.cia');
            if (await sha256File(source.path) != (e.value as Map)['sha256'])
              throw const FileSystemException(
                'A cached add-on package changed. Existing installations have been kept.',
              );
            await source.copy('${packages.path}/${e.key}.cia');
          }
        }
        final total = changed.fold<int>(0, (n, f) => n + f.$1.bytes);
        var completed = 0;
        final imports = <(String, ThreeDsTitle)>[];
        for (final r in changed) {
          cancellation.check();
          final f = r.$1,
              path = r.$2,
              target = File('${packages.path}/${r.$1.id}.cia');
          // Deletion here is confined to an unpublished, Broomm-created copy.
          if (await target.exists()) await target.delete();
          final original = '${entry.directory.path}/content/$path';
          final expected = _crc(f);
          var reused = false;
          if (expected != null && local.contains(original)) {
            progress(
              DownloadProgress(
                game,
                'Verifying downloaded ${r.$3}',
                completed,
                total,
              ),
            );
            if (await File(original).length() == f.bytes &&
                await cancellableCrc32(original, cancellation) == expected) {
              await File(original).copy(target.path);
              reused = true;
            }
          }
          if (!reused) {
            progress(
              DownloadProgress(
                game,
                'Downloading ${r.$3}: ${f.name}',
                completed,
                total,
              ),
            );
            await target.create(exclusive: true);
            await client.downloadFile(
              f,
              target,
              cancellation: cancellation,
              onProgress: (n) => progress(
                DownloadProgress(
                  game,
                  'Downloading ${r.$3}: ${f.name}',
                  completed + n,
                  total,
                ),
              ),
            );
          }
          cancellation.check();
          progress(
            DownloadProgress(
              game,
              'Verifying ${r.$3}: ${f.name}',
              completed + f.bytes,
              total,
            ),
          );
          if (await target.length() != f.bytes ||
              (expected != null &&
                  await cancellableCrc32(target.path, cancellation) !=
                      expected))
            throw const RommFailure(
              'An update/DLC download did not match RomM. Existing installed content was kept; retry.',
            );
          if (_sha1(f) != null) {
            final hash = (await runOwnedTool('/usr/bin/shasum', [
              '-a',
              '1',
              target.path,
            ])).split(' ').first;
            if (hash != f.sha1!.toLowerCase())
              throw const RommFailure(
                'The downloaded CIA did not match RomM\'s SHA-1. Existing content was kept.',
              );
          }
          final title = await readCiaTitle(target.path);
          if (title.kind != r.$3 || !title.belongsTo(base))
            throw RommFailure(
              '${f.name} belongs to a different 3DS title/region or content category. Nothing was installed; check its RomM folder.',
            );
          sources['${f.id}'] = {
            'remote': _remote(f, path),
            'title': title.id,
            'version': title.version,
            'sha256': await sha256File(target.path),
          };
          imports.add((target.path, title));
          completed += f.bytes;
        }
        cancellation.check();
        final native = Directory('${stage.path}/native');
        await ownedDirectory(native);
        final user = Directory(azaharUserPath(native.path));
        await ownedDirectory(user);
        if (previous != null) {
          final payload = Directory(
            '${dir.path}/${previous['generation']}/payload',
          );
          for (final path in (previous['units'] as Map).keys.cast<String>()) {
            await _copyUnit(
              payload,
              user,
              path,
              (previous['units'] as Map)[path] as Map,
            );
          }
        }
        imports.sort((a, b) => a.$2.version.compareTo(b.$2.version));
        var installed = 0;
        final titleVersions = <String, int>{};
        for (final value in oldSources.values.cast<Map>()) {
          final id = value['title'] as String,
              version = value['version'] as int;
          if (version > (titleVersions[id] ?? -1)) titleVersions[id] = version;
        }
        for (final item in imports) {
          cancellation.check();
          if (item.$2.version < (titleVersions[item.$2.id] ?? -1)) continue;
          progress(
            DownloadProgress(
              game,
              'Installing ${item.$2.kind} in Azahar (${installed + 1}/${imports.length})',
              total,
              total,
            ),
          );
          phase?.call('Azahar import ${item.$2.kind} for ROM ${game.id}');
          await importer(executable, item.$1, native, cancellation);
          titleVersions[item.$2.id] = item.$2.version;
          installed++;
        }
        cancellation.check();
        final units = await _collect(user, titleVersions);
        final payload = Directory('${stage.path}/payload');
        await ownedDirectory(payload);
        for (final e in units.entries) {
          await _copyUnit(user, payload, e.key, e.value as Map);
        }
        // Native temporary configuration/logs never enter a managed profile.
        await native.delete(recursive: true);
        final generation =
            'generation-${stage.uri.pathSegments.where((s) => s.isNotEmpty).last.substring(8)}';
        final manifest = <String, dynamic>{
          'version': 1,
          'server': serverId,
          'game': game.id,
          'base': base,
          'generation': generation,
          'sources': sources,
          'units': units,
        };
        await addonWrite(File('${stage.path}/manifest.json'), manifest);
        cancellation.check();
        if (await addonExists('${dir.path}/$generation'))
          throw const FileSystemException('Add-on generation already exists');
        await stage.rename('${dir.path}/$generation');
        published = true;
        await addonWrite(File('${dir.path}/current.json'), manifest);
        if (previous != null) {
          await addonWrite(File('${dir.path}/retired.json'), {
            'version': 1,
            'server': serverId,
            'game': game.id,
            'generation': previous['generation'],
          });
        }
        // Once committed, finish the small transaction even if cancellation
        // arrives. The next request can safely repeat it without another CIA import.
        progress(
          DownloadProgress(
            game,
            'Applying updates and DLC to your profile',
            total,
            total,
          ),
        );
        await _apply(serverId, game.id, profile, dir, manifest);
        await _finishRetired(dir, serverId, game.id);
        return AddonResult(installed, remote.length);
      } finally {
        if (!published && await stage.exists())
          await stage.delete(recursive: true);
      }
    } finally {
      await lease.release();
    }
  }

  Future<void> _copyUnit(
    Directory from,
    Directory to,
    String path,
    Map unit,
  ) async {
    if (!isAddonUnit(path)) throw const FormatException('Invalid add-on unit');
    final files = (unit['files'] as Map).cast<String, String>();
    final source = await addonPath(from, path),
        target = await addonPath(to, path, createParents: true);
    if (path.endsWith('/content')) {
      await copyAddonFiles(Directory(source), Directory(target), files);
    } else {
      final file = await addonFile(from, path);
      if (await sha256File(file.path) != files[''])
        throw const FileSystemException('Add-on ticket changed');
      await file.copy(target);
      if (await sha256File(target) != files[''])
        throw const FileSystemException('Add-on ticket copy failed');
    }
  }

  Future<Map<String, dynamic>> _collect(
    Directory user,
    Map<String, int> titles,
  ) async {
    final units = <String, dynamic>{};
    for (final title in titles.entries) {
      if (!RegExp(r'^000400(0e|8c)[0-9a-f]{8}$').hasMatch(title.key))
        throw const FormatException('Invalid add-on title');
      final path = titleContentPath(title.key);
      final files = await addonInventory(
        Directory(await addonPath(user, path)),
      );
      if (!files.keys.any((p) => p.endsWith('.tmd')) ||
          !files.keys.any((p) => p.endsWith('.app')))
        throw const RommFailure(
          'Azahar did not produce complete installed title content. Existing data was kept.',
        );
      units[path] = {'files': files, 'version': title.value};
    }
    final tickets = Directory(await addonPath(user, 'nand/dbs/ticket.db'));
    await for (final ticket in tickets.list(followLinks: false)) {
      final name = ticket.uri.pathSegments.last;
      final path = 'nand/dbs/ticket.db/$name';
      if (!isAddonUnit(path) ||
          !titles.containsKey(name.substring(0, 16).toLowerCase()))
        throw const RommFailure(
          'Azahar produced an unexpected ticket. Nothing was copied to a player profile.',
        );
      if (ticket is! File)
        throw const FileSystemException('Invalid installed ticket');
      units[path] = {
        'files': {'': await sha256File(ticket.path)},
        'version': titles[name.substring(0, 16).toLowerCase()],
      };
    }
    for (final id in titles.keys) {
      if (!units.keys.any(
        (s) => s.startsWith('nand/dbs/ticket.db/${id.toUpperCase()}.'),
      ))
        throw const RommFailure(
          'Azahar did not produce the expected title ticket.',
        );
    }
    return units;
  }

  Future<void> _verifyPayload(Directory dir, Map j) async {
    final payload = Directory('${dir.path}/${j['generation']}/payload');
    final expected = <String, String>{};
    for (final e in (j['units'] as Map).entries) {
      if (!isAddonUnit(e.key as String))
        throw const FormatException('Invalid shared add-on location');
      for (final file in ((e.value as Map)['files'] as Map).entries) {
        expected['${e.key}${file.key == '' ? '' : '/${file.key}'}'] =
            file.value as String;
      }
    }
    if (!sameAddonInventory(await addonInventory(payload), expected))
      throw const FileSystemException(
        'The shared add-on installation is incomplete or changed. Existing progress has been kept.',
      );
  }

  Future<void> _validateProfile(
    String id,
    Directory profile, {
    bool checkStorage = true,
  }) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id))
      throw const FormatException('Invalid add-on profile identity');
    final expected = await addonPath(
      data,
      'profiles/$id/emulators/azahar/profile.json',
    );
    if (File(expected).parent.absolute.path != profile.absolute.path)
      throw const FormatException(
        'Azahar add-ons must stay in Broomm-owned profile storage',
      );
    final j = await addonJson(File(expected));
    if (j['version'] != 1 || j['profile'] != id || j['emulator'] != 'azahar')
      throw const FormatException('Invalid Azahar profile ownership');
    if (!checkStorage) return;
    await addonPath(
      profile,
      'home/Library/Application Support/Azahar/config/qt-config.ini',
    );
    final config = await File(
      '${azaharUserPath(profile.path)}/config/qt-config.ini',
    ).readAsString();
    if (checkStorage &&
        RegExp(
          r'^use_custom_storage\s*=\s*true\s*$',
          multiLine: true,
          caseSensitive: false,
        ).hasMatch(config))
      throw const RommFailure(
        'Azahar custom storage is enabled. Restore Broomm-local default storage before installing updates/DLC.',
      );
  }

  Future<void> _apply(
    String server,
    int game,
    Directory profile,
    Directory dir,
    Map j,
  ) async {
    await AzaharAddonProfile(profile, checkpoint: checkpoint).apply(
      '$server/$game',
      Directory('${dir.path}/${j['generation']}/payload'),
      (j['units'] as Map).cast<String, dynamic>(),
    );
  }

  /// Launch already owns SessionLease; catalogue permissions were checked by
  /// the shell. Other profiles receive private copies only when they play.
  Future<void> applyForLaunch(
    String server,
    int game,
    String profileId,
    Directory profile,
    String baseRom,
  ) async {
    await _validateProfile(profileId, profile);
    final target = AzaharAddonProfile(profile, checkpoint: checkpoint);
    await target.recover();
    final dir = await _game(server, game);
    final j = await _current(dir, server, game);
    if (j == null) return;
    if (await readThreeDsGameId(baseRom) != j['base'])
      throw const RommFailure(
        'The selected ROM does not match the installed updates/DLC title. Existing data was kept.',
      );
    await _verifyPayload(dir, j);
    await _apply(server, game, profile, dir, j);
  }

  /// Called under GameLibrary.remove's session + library leases, after its
  /// external deletion intent. Keep the shared checkpoint until every profile
  /// has completed cleanup, so a failed deletion can be retried safely.
  Future<void> uninstall(String server, int game) async {
    final dir = await _game(server, game);
    await _finishRetired(dir, server, game);
    final intent = File('${dir.path}/deleting.json');
    Map<String, dynamic> deletion;
    if (await addonExists(intent.path)) {
      deletion = await addonJson(intent);
    } else {
      await _current(dir, server, game);
      final generations = <String>[];
      await for (final entry in dir.list(followLinks: false)) {
        final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!RegExp(r'^generation-[a-zA-Z0-9_-]+$').hasMatch(name)) continue;
        if (entry is! Directory)
          throw const FileSystemException('Invalid shared add-on generation');
        final j = await addonJson(File('${entry.path}/manifest.json'));
        if (j['version'] != 1 ||
            j['server'] != server ||
            j['game'] != game ||
            j['generation'] != name)
          throw const FormatException('Unrecognized shared add-on ownership');
        generations.add(name);
      }
      deletion = {
        'version': 1,
        'server': server,
        'game': game,
        'generations': generations,
      };
      await addonWrite(intent, deletion);
    }
    if (deletion['version'] != 1 ||
        deletion['server'] != server ||
        deletion['game'] != game ||
        deletion['generations'] is! List ||
        (deletion['generations'] as List).length > 10000 ||
        !(deletion['generations'] as List).every(
          (s) =>
              s is String && RegExp(r'^generation-[a-zA-Z0-9_-]+$').hasMatch(s),
        ))
      throw const FormatException('Invalid add-on deletion checkpoint');
    final profiles = Directory('${data.path}/profiles');
    if (await addonExists(profiles.path)) {
      await addonPath(data, 'profiles/.probe');
      await for (final p in profiles.list(followLinks: false)) {
        final id = p.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) continue;
        if (p is! Directory)
          throw const FileSystemException(
            'A profile directory is linked or invalid',
          );
        final runtime = Directory('${p.path}/emulators/azahar');
        if (!await addonExists(runtime.path)) continue;
        if (!await addonExists('${runtime.path}/addons.json') &&
            !await addonExists('${runtime.path}/addons-pending.json') &&
            !await addonExists('${runtime.path}/.addon-transaction'))
          continue;
        await _validateProfile(id, runtime, checkStorage: false);
        await AzaharAddonProfile(
          runtime,
          checkpoint: checkpoint,
        ).remove('$server/$game');
      }
    }
    // This checkpoint stays outside recursive cleanup, including when an
    // interrupted delete has already removed an inner generation manifest.
    for (final name in (deletion['generations'] as List).cast<String>()) {
      final path = await addonPath(dir, name);
      if (await addonExists(path)) {
        if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.directory)
          throw const FileSystemException('Invalid add-on cleanup directory');
        await Directory(path).delete(recursive: true);
      }
    }
    final current = await addonFile(dir, 'current.json');
    if (await addonExists(current.path)) await current.delete();
    await intent.delete();
  }

  Future<void> _finishRetired(Directory dir, String server, int game) async {
    final file = File('${dir.path}/retired.json');
    if (!await addonExists(file.path)) return;
    final j = await addonJson(file);
    final current = await addonJson(File('${dir.path}/current.json'));
    final name = j['generation'];
    if (j['version'] != 1 ||
        j['server'] != server ||
        j['game'] != game ||
        name is! String ||
        !RegExp(r'^generation-[a-zA-Z0-9_-]+$').hasMatch(name) ||
        current['version'] != 1 ||
        current['server'] != server ||
        current['game'] != game ||
        current['generation'] == name)
      throw const FormatException('Invalid retired add-on checkpoint');
    final path = await addonPath(dir, name);
    if (await addonExists(path)) {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.directory)
        throw const FileSystemException('Invalid retired add-on directory');
      await Directory(path).delete(recursive: true);
    }
    await file.delete();
  }
}
