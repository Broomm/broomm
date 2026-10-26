import 'dart:convert';
import 'dart:io';

import '../managed_emulators.dart'
    show ownedDirectory, sha256File, runOwnedTool;
import '../progress/layout.dart' show readPs3Sfo, readPs3GameMetadata;
import '../romm/client.dart';
import '../romm/models.dart';
import '../romm/transfer.dart';
import '../session_lease.dart';
import '../shell/library.dart';
import '../game_launch.dart';
import 'files.dart';
import 'rpcs3_profile.dart';
import 'rpcs3_import.dart';
import 'service.dart' show AddonResult, PrepareAddonProfile, addonKind;

typedef ImportPs3 = Future<Directory> Function(
  String executable,
  String input,
  Directory stage,
  DownloadCancellation cancellation, {
  required bool firmware,
  required Directory data,
});

/// Concrete PS3 packages: immutable canonical game content, deployed through
/// the same journaled owned-unit transaction as 3DS. Savedata is never a unit.
class Ps3Addons {
  Ps3Addons(
    this.data,
    this.library, {
    required this.prepare,
    ImportPs3? importer,
    this.checkpoint,
    this.diagnosticProblem,
  }) : importer = importer ?? installRpcs3Content;
  final Directory data;
  final GameLibrary library;
  final PrepareAddonProfile prepare;
  final ImportPs3 importer;
  final void Function(String)? checkpoint;
  final void Function(String)? diagnosticProblem;
  Future<void> _cleanPending(Directory root, String server, int game) async {
    await for (final entry in root.list(followLinks: false)) {
      final name = entry.uri.pathSegments.where((v) => v.isNotEmpty).last;
      if (!name.startsWith('.pending-')) continue;
      if (entry is! Directory)
        throw const FileSystemException('Unknown PS3 staging data was kept.');
      final j = await addonJson(File('${entry.path}/owner.json'));
      if (j['version'] != 1 ||
          j['server'] != server ||
          j['game'] != game ||
          j['kind'] != 'ps3-addon-generation')
        throw const FormatException('Unrecognized PS3 staging owner');
      await entry.delete(recursive: true);
    }
  }

  Future<Directory> _root(String server, int id) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(server) || id < 1)
      throw const FormatException('Invalid PS3 add-on owner');
    return File(
      await addonPath(
        data,
        'addons-ps3/$server/$id/current.json',
        createParents: true,
      ),
    ).parent;
  }

  Future<Map<String, dynamic>?> _current(
    Directory root,
    String server,
    int id,
  ) async {
    if (!await addonExists('${root.path}/current.json')) return null;
    final j = await addonJson(File('${root.path}/current.json'));
    if (j['version'] != 1 ||
        j['server'] != server ||
        j['game'] != id ||
        j['base'] is! String ||
        !RegExp(r'^[A-Z]{4}[0-9]{5}$').hasMatch(j['base'] as String) ||
        j['generation'] is! String ||
        !RegExp(r'^generation-[A-Za-z0-9_-]+$')
            .hasMatch(j['generation'] as String) ||
        j['sources'] is! Map ||
        (j['sources'] as Map).length > 1024 ||
        j['units'] is! Map)
      throw const FormatException('Unrecognized PS3 add-on ownership');
    final manifest = await addonJson(
      File(await addonPath(root, '${j['generation']}/manifest.json')),
    );
    if (jsonEncode(manifest) != jsonEncode(j))
      throw const FormatException(
        'PS3 add-on checkpoint differs from its generation',
      );
    return j;
  }

  Future<void> _verify(Directory root, Map j) async {
    final base = Directory('${root.path}/${j['generation']}/payload');
    final owner = await addonJson(File('${base.parent.path}/owner.json'));
    if (owner['version'] != 1 ||
        owner['server'] != j['server'] ||
        owner['game'] != j['game'] ||
        owner['kind'] != 'ps3-addon-generation')
      throw const FormatException('Invalid PS3 generation staging owner');
    final expected = <String, String>{};
    for (final e in (j['units'] as Map).entries) {
      final path = e.key as String;
      final checker = Rpcs3AddonProfile(root);
      if (!checker.acceptsUnit(path))
        throw const FormatException('Invalid PS3 content path');
      final files = (e.value['files'] as Map).cast<String, String>();
      if (files.isEmpty || files.length > 100000)
        throw const FormatException('Invalid PS3 content inventory');
      for (final f in files.entries) {
        final relative = checker.directoryUnit(path) ? '$path/${f.key}' : path;
        addonRelative(relative);
        if ((!checker.directoryUnit(path) && f.key != '') ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(f.value) ||
            expected.containsKey(relative))
          throw const FormatException('Invalid PS3 content inventory');
        expected[relative] = f.value;
      }
    }
    if (!sameAddonInventory(await addonInventory(base), expected))
      throw const FileSystemException(
        'Shared PS3 content is damaged or contains untracked files. Existing data was kept.',
      );
    await for (final e in base.parent.list(followLinks: false)) {
      if (![
        'payload',
        'manifest.json',
        'owner.json',
      ].contains(e.uri.pathSegments.where((v) => v.isNotEmpty).last))
        throw const FileSystemException(
          'The shared PS3 generation contains untracked files.',
        );
    }
  }

  Map<String, dynamic> _remote(RommFile f, String path) => {
    'id': f.id,
    'path': path,
    'bytes': f.bytes,
    'sha1': RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(f.sha1 ?? '')
        ? f.sha1!.toLowerCase()
        : null,
    'crc': f.rawCrc && RegExp(r'^[a-fA-F0-9]{1,8}$').hasMatch(f.crc ?? '')
        ? f.crc!.toLowerCase().padLeft(8, '0')
        : null,
  };
  Future<void> _checkSource(
    File file,
    RommFile f,
    DownloadCancellation cancellation,
  ) async {
    if (await file.length() != f.bytes)
      throw const RommFailure('PS3 package size did not match RomM.');
    final r = _remote(f, '');
    if (r['sha1'] != null) {
      final hash = (await runOwnedTool('/usr/bin/shasum', [
        '-a',
        '1',
        file.path,
      ])).split(' ').first;
      if (hash != r['sha1'])
        throw const RommFailure('PS3 package checksum did not match RomM.');
    } else if (r['crc'] != null) {
      if (await cancellableCrc32(file.path, cancellation) != r['crc'])
        throw const RommFailure('PS3 package checksum did not match RomM.');
    }
  }

  Future<String> _packageId(File file) async {
    final h = await file
        .openRead(0, 0x60)
        .fold<List<int>>([], (a, b) => a..addAll(b));
    if (h.length != 0x60 ||
        h[0] != 0x7f ||
        latin1.decode(h.sublist(1, 4)) != 'PKG')
      throw const RommFailure('This PS3 add-on is not a PKG file.');
    final id = latin1.decode(h.sublist(0x30, 0x60)).split('\x00').first;
    if (!RegExp(r'^[A-Z]{2}[0-9]{4}-[A-Z]{4}[0-9]{5}_00-[A-Za-z0-9_]{16}$')
        .hasMatch(id))
      throw const RommFailure(
        'The PS3 package has no verified content identity.',
      );
    return id;
  }

  Future<void> _profile(Directory root, String id) async {
    final j = await addonJson(File(await addonPath(root, 'profile.json')));
    if (root.absolute.uri !=
            Directory('${data.path}/profiles/$id/emulators/rpcs3')
                .absolute
                .uri ||
        j['version'] != 1 ||
        j['profile'] != id ||
        j['emulator'] != 'rpcs3')
      throw const FormatException('Invalid RPCS3 profile ownership');
  }

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
      if (game.id != entry.game.id ||
          gamePlatform(game, const [])?.slug != 'ps3')
        throw const FormatException('Wrong PS3 game identity');
      final paths = gameFilePaths(game);
      final files = <(RommFile, String)>[];
      for (var i = 0; i < paths.length; i++)
        if (addonKind(game.files[i], paths[i]) != null) {
          if (!RegExp(
                r'\.(pkg|rap)$',
                caseSensitive: false,
              ).hasMatch(paths[i]) ||
              game.files[i].bytes > 16 * 1024 * 1024 * 1024)
            throw const RommFailure(
              'PS3 updates/DLC must be unpacked PKG files with optional RAP licenses.',
            );
          files.add((game.files[i], paths[i]));
        }
      if (files.length > 1024)
        throw const FormatException('Too many PS3 packages');
      final root = await _root(serverId, game.id),
          old = await _current(
            await _root(serverId, game.id),
            serverId,
            game.id,
          );
      if (await addonExists('${root.path}/deleting.json'))
        throw StateError(
          'Finish deleting this game before installing PS3 add-ons.',
        );
      await _cleanPending(root, serverId, game.id);
      if (files.isEmpty && old == null) return const AddonResult(0, 0);
      final candidates = gameCandidates(
        gamePlatform(game, const [])!,
        await library.contentFiles(entry),
      );
      if (candidates.length != 1)
        throw const RommFailure(
          'PS3 updates require one PS3 ISO or extracted PS3_GAME/USRDIR/EBOOT.BIN.',
        );
      final base = (await readPs3GameMetadata(candidates.single))['TITLE_ID'];
      if (base == null ||
          !RegExp(r'^[A-Z]{4}[0-9]{5}$').hasMatch(base) ||
          (old != null && old['base'] != base))
        throw const FormatException('PS3 base title identity changed');
      final changed =
          files.where((f) {
            final r = _remote(f.$1, f.$2),
                prior = (old?['sources'] as Map?)?['${f.$1.id}'];
            return (r['sha1'] == null && r['crc'] == null) ||
                jsonEncode(prior) != jsonEncode(r);
          }).toList()..sort((a, b) {
            int priority((RommFile, String) v) =>
                v.$2.toLowerCase().endsWith('.rap')
                ? 2
                : addonKind(v.$1, v.$2) == 'update'
                ? 0
                : 1;
            final order = priority(a).compareTo(priority(b));
            return order == 0 ? a.$2.compareTo(b.$2) : order;
          });
      if (old != null) await _verify(root, old);
      progress(DownloadProgress(game, 'Preparing RPCS3 updates and DLC', 0, 0));
      final (exe, profile) = await prepare(profileId, cancellation);
      await _profile(profile, profileId);
      if (changed.isEmpty) {
        if (old != null) await _apply(root, old, profile);
        return AddonResult(0, files.length);
      }
      final stage = await root.createTemp('.pending-');
      try {
        await addonWrite(File('${stage.path}/owner.json'), {
          'version': 1,
          'server': serverId,
          'game': game.id,
          'kind': 'ps3-addon-generation',
        });
        final native = Directory('${stage.path}/native');
        await native.create();
        final user = Directory(
          '${native.path}/home/Library/Application Support/rpcs3',
        );
        await ownedDirectory(user);
        if (old != null)
          await copyAddonFiles(
            Directory('${root.path}/${old['generation']}/payload'),
            user,
            await addonInventory(
              Directory('${root.path}/${old['generation']}/payload'),
            ),
          );
        final sources = <String, dynamic>{
          ...?((old?['sources'] as Map?)?.cast<String, dynamic>()),
        };
        // Updates precede DLC; every package overlays the same private staging.
        for (final (file, path) in changed) {
          cancellation.check();
          final input = File(
            '${stage.path}/${file.id}.${path.split('.').last.toLowerCase()}',
          );
          final local = File('${entry.directory.path}/content/$path');
          progress(
            DownloadProgress(
              game,
              'Downloading PS3 updates and DLC',
              0,
              file.bytes,
            ),
          );
          if (await local.exists()) {
            await local.copy(input.path);
            await _checkSource(input, file, cancellation);
          } else {
            await client.downloadFile(
              file,
              input,
              cancellation: cancellation,
              onProgress: (n) => progress(
                DownloadProgress(
                  game,
                  'Downloading PS3 updates and DLC',
                  n,
                  file.bytes,
                ),
              ),
            );
            await _checkSource(input, file, cancellation);
          }
          final content = path.toLowerCase().endsWith('.rap')
              ? File(path).uri.pathSegments.last
                    .replaceFirst(RegExp(r'\.rap$', caseSensitive: false), '')
              : await _packageId(input);
          if (!RegExp(
                r'^[A-Z]{2}[0-9]{4}-[A-Z]{4}[0-9]{5}_00-[A-Za-z0-9_]{16}$',
              ).hasMatch(content) ||
              content.substring(7, 16) != base)
            throw const RommFailure(
              'This PS3 package belongs to a different title/region. Existing games and progress were kept.',
            );
          if (path.toLowerCase().endsWith('.rap')) {
            if (file.bytes != 16)
              throw const FormatException('Invalid RAP license size');
            final target = File(
              await addonPath(
                user,
                'dev_hdd0/home/00000001/exdata/$content.rap',
                createParents: true,
              ),
            );
            await input.copy(target.path);
          } else {
            progress(
              DownloadProgress(
                game,
                'Installing PS3 package',
                file.bytes,
                file.bytes,
              ),
            );
            try {
              await importer(
                exe,
                input.path,
                native,
                cancellation,
                firmware: false,
                data: data,
              );
            } finally {
              await retainRpcs3InstallLog(
                native,
                data,
                onProblem: diagnosticProblem,
              );
            }
          }
          sources['${file.id}'] = _remote(file, path);
        }
        final units = <String, dynamic>{};
        final gameDir = Directory('${user.path}/dev_hdd0/game/$base');
        if (await gameDir.exists()) {
          final meta = await readPs3Sfo(File('${gameDir.path}/PARAM.SFO'));
          if (meta['TITLE_ID'] != base)
            throw const FormatException('Installed PS3 title identity differs');
          final version = (meta['APP_VER'] ?? '00.00').split('.');
          final v =
              (int.tryParse(version.first) ?? 0) * 100 +
              (int.tryParse(version.last) ?? 0);
          units['dev_hdd0/game/$base'] = {
            'version': v,
            'files': await addonInventory(gameDir),
          };
        }
        final exdata = Directory('${user.path}/dev_hdd0/home/00000001/exdata');
        if (await exdata.exists())
          await for (final file in exdata.list(followLinks: false)) {
            final rel =
                'dev_hdd0/home/00000001/exdata/${file.uri.pathSegments.last}';
            if (file is! File || !Rpcs3AddonProfile(profile).acceptsUnit(rel))
              throw const FormatException('Unexpected PS3 license data');
            units[rel] = {
              'version': 0,
              'files': {'': await sha256File(file.path)},
            };
          }
        if (units.isEmpty)
          throw const RommFailure(
            'RPCS3 produced no installable content for this game.',
          );
        final payload = Directory('${stage.path}/payload');
        await payload.create();
        for (final e in units.entries) {
          if (e.key.startsWith('dev_hdd0/game/'))
            await copyAddonFiles(
              Directory('${user.path}/${e.key}'),
              Directory('${payload.path}/${e.key}'),
              (e.value['files'] as Map).cast<String, String>(),
            );
          else {
            final dest = File(
              await addonPath(payload, e.key, createParents: true),
            );
            await File('${user.path}/${e.key}').copy(dest.path);
          }
        }
        final generation =
            'generation-${stage.uri.pathSegments.where((p) => p.isNotEmpty).last.substring(9)}';
        final record = {
          'version': 1,
          'server': serverId,
          'game': game.id,
          'base': base,
          'generation': generation,
          'sources': sources,
          'units': units,
        };
        await addonWrite(File('${stage.path}/manifest.json'), record);
        cancellation.check();
        // Installer scratch and packages are private; canonical payload has only
        // validated game content/license paths. One rename publishes the set.
        await native.delete(recursive: true);
        for (final f in changed) {
          final input = File(
            '${stage.path}/${f.$1.id}.${f.$2.split('.').last.toLowerCase()}',
          );
          if (await input.exists()) await input.delete();
        }
        await stage.rename('${root.path}/$generation');
        await addonWrite(File('${root.path}/current.json'), record);
        await _apply(root, record, profile);
        return AddonResult(
          changed.where((f) => f.$2.toLowerCase().endsWith('.pkg')).length,
          files.length,
        );
      } finally {
        if (await stage.exists()) await stage.delete(recursive: true);
      }
    } finally {
      await lease.release();
    }
  }

  Future<void> _apply(Directory root, Map j, Directory profile) async {
    await _verify(root, j);
    await Rpcs3AddonProfile(profile, checkpoint: checkpoint).apply(
      '${j['server']}/${j['game']}',
      Directory('${root.path}/${j['generation']}/payload'),
      (j['units'] as Map).cast<String, dynamic>(),
    );
  }

  Future<void> applyForLaunch(String server, int game, String profileId) async {
    final root = await _root(server, game),
        j = await _current(await _root(server, game), server, game);
    final (_, profile) = await prepare(profileId, DownloadCancellation());
    await _profile(profile, profileId);
    await Rpcs3AddonProfile(profile).recover();
    if (j != null) await _apply(root, j, profile);
  }

  Future<void> uninstall(String server, int game) async {
    final root = await _root(server, game);
    await _cleanPending(root, server, game);
    final marker = File('${root.path}/deleting.json');
    Map<String, dynamic> deletion;
    if (await addonExists(marker.path)) {
      deletion = await addonJson(marker);
      if (deletion['version'] != 1 ||
          deletion['server'] != server ||
          deletion['game'] != game ||
          deletion['generations'] is! Map)
        throw const FormatException('Invalid PS3 deletion checkpoint');
    } else {
      final generations = <String, dynamic>{};
      await for (final entry in root.list(followLinks: false)) {
        final name = entry.uri.pathSegments.where((v) => v.isNotEmpty).last;
        if (!name.startsWith('generation-')) continue;
        if (entry is! Directory ||
            !RegExp(r'^generation-[A-Za-z0-9_-]+$').hasMatch(name))
          throw const FormatException('Invalid PS3 generation');
        final j = await addonJson(File('${entry.path}/manifest.json'));
        if (j['version'] != 1 ||
            j['server'] != server ||
            j['game'] != game ||
            j['generation'] != name)
          throw const FormatException('Invalid PS3 generation owner');
        await _verify(root, j);
        generations[name] = await addonInventory(entry);
      }
      deletion = {
        'version': 1,
        'server': server,
        'game': game,
        'generations': generations,
      };
      await addonWrite(marker, deletion);
      checkpoint?.call('ps3-deletion-prepared');
    }
    final profiles = Directory('${data.path}/profiles');
    if (await profiles.exists())
      await for (final entry in profiles.list(followLinks: false)) {
        if (entry is! Directory ||
            !RegExp(
              r'^[a-f0-9]{32}$',
            ).hasMatch(entry.uri.pathSegments.where((v) => v.isNotEmpty).last))
          continue;
        final profile = Directory('${entry.path}/emulators/rpcs3');
        if (!await profile.exists()) continue;
        await _profile(
          profile,
          entry.uri.pathSegments.where((v) => v.isNotEmpty).last,
        );
        await Rpcs3AddonProfile(profile).remove('$server/$game');
      }
    // Ownership stays outside recursive retirement, so interrupted cleanup is
    // retryable even after an immutable generation's inner manifest is gone.
    for (final entry in (deletion['generations'] as Map).entries) {
      final name = entry.key as String;
      if (!RegExp(r'^generation-[A-Za-z0-9_-]+$').hasMatch(name))
        throw const FormatException('Invalid PS3 retirement path');
      final dir = Directory(await addonPath(root, name));
      if (await addonExists(dir.path)) {
        final expected = (entry.value as Map).cast<String, String>(),
            actual = await addonInventory(dir);
        if (actual.entries.any((f) => expected[f.key] != f.value))
          throw const FileSystemException(
            'PS3 cleanup found unrelated or changed files. Existing data was kept.',
          );
        await dir.delete(recursive: true);
        checkpoint?.call('ps3-generation-removed');
      }
    }
    final current = File('${root.path}/current.json');
    if (await addonExists(current.path)) await current.delete();
    await marker.delete();
  }
}
