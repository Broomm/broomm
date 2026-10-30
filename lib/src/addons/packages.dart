import 'dart:convert';
import 'dart:io';

import '../game_launch.dart';
import '../managed_emulators.dart' show ownedDirectory, sha256File;
import '../romm/client.dart';
import '../romm/models.dart';
import '../romm/transfer.dart';
import '../session_lease.dart';
import '../shell/library.dart';
import 'files.dart';
import 'package_import.dart';
import 'package_profile.dart';
import 'service.dart';
import 'wii.dart';
import 'wii_shared.dart';
import 'psp.dart';
import 'eden.dart';
import '../switch_content.dart';
import '../psp.dart';

typedef WiiImporter = Future<void> Function(
  String,
  String,
  Directory,
  Directory,
  DownloadCancellation,
);
typedef SwitchInspector = Future<SwitchPackages> Function(
  String,
  String,
  Directory,
  Directory,
  Directory,
  Directory,
  DownloadCancellation,
);

/// Shared download/checkpoint mechanics, with concrete Wii, Switch and PSP native
/// import contracts. Immutable packages remain alive while any private profile
/// can reference their generation. No native writer sees a partial update.
class GamePackages {
  GamePackages(
    this.data,
    this.library,
    this.platform, {
    required this.prepare,
    this.wiiImporter = importWiiWad,
    this.switchInspector = inspectSwitchPackages,
    this.checkpoint,
    this.provision,
    this.switchEmulator = 'Ryubing',
  });
  final Directory data;
  final GameLibrary library;
  final String platform;
  final String switchEmulator;
  String get packageEngine => engine == 'eden' ? 'eden' : platform;
  String get storageId => engine == 'eden' ? 'switch-eden' : platform;
  final PrepareAddonProfile prepare;
  final WiiImporter wiiImporter;
  final SwitchInspector switchInspector;
  final void Function(String)? checkpoint;
  final Future<void> Function(
    String,
    int,
    RommClient,
    DownloadCancellation,
    SessionLease,
    void Function(String),
  )?
  provision;
  String get engine => switch (platform) {
    'wii' => 'dolphin',
    'psp' => 'ppsspp',
    _ => switchEmulator == 'Eden' ? 'eden' : 'ryubing',
  };

  Future<Directory> _directory(String server, int game) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(server) ||
        game < 1 ||
        !{'wii', 'switch', 'psp'}.contains(platform) ||
        platform == 'switch' && !{'Ryubing', 'Eden'}.contains(switchEmulator)) {
      throw const FormatException('Invalid native package owner');
    }
    return File(
      await addonPath(
        data,
        'addons/$server/$game/$storageId/current.json',
        createParents: true,
      ),
    ).parent;
  }

  Future<Map<String, dynamic>?> _current(
    Directory dir,
    String server,
    int game,
  ) async {
    final file = File('${dir.path}/current.json');
    if (!await addonExists(file.path)) return null;
    final j = await addonJson(file);
    if (j['version'] != 1 ||
        j['server'] != server ||
        j['game'] != game ||
        j['platform'] != platform ||
        j['sources'] is! Map ||
        j['units'] is! Map ||
        j['base'] is! String ||
        j['generation'] is! String ||
        !RegExp(r'^generation-[a-zA-Z0-9_-]+$')
            .hasMatch(j['generation'] as String)) {
      throw const FormatException('Invalid native package checkpoint');
    }
    final saved = await addonJson(
      File(await addonPath(dir, '${j['generation']}/manifest.json')),
    );
    if (jsonEncode(saved) != jsonEncode(j))
      throw const FileSystemException(
        'Native package checkpoint differs from its generation',
      );
    return j;
  }

  String? _crc(RommFile file) =>
      file.rawCrc &&
          file.crc != null &&
          RegExp(r'^[a-fA-F0-9]{1,8}$').hasMatch(file.crc!)
      ? file.crc!.toLowerCase().padLeft(8, '0')
      : null;
  Map<String, dynamic> _remote(RommFile file, String path) => {
    'id': file.id,
    'path': path,
    'bytes': file.bytes,
    'crc': _crc(file),
    'sha1': file.sha1,
    'modified': file.modified,
  };

  Future<void> _profile(Directory profile, String id) async {
    final record = await addonJson(
      File(await addonPath(profile, 'profile.json')),
    );
    if (record['version'] != 1 ||
        record['profile'] != id ||
        record['emulator'] != engine ||
        await profile.resolveSymbolicLinks() !=
            await Directory('${data.path}/profiles/$id/emulators/$engine')
                .resolveSymbolicLinks()) {
      throw const FileSystemException(
        'Native package profile belongs to another account',
      );
    }
    await addonPath(
      profile,
      '${engine == 'eden' ? 'data/eden' : 'user'}/.probe',
    );
  }

  /// A new Switch default needs its own native content, including when the
  /// shared game was downloaded with the other emulator selected. This uses
  /// the installed receipt, rather than the lightweight catalogue metadata
  /// (which deliberately does not persist RomM's downloadable file list).
  Future<bool> needsSwitchSelection(String server, InstalledGame entry) async {
    if (platform != 'switch') return false;
    final dir = await _directory(server, entry.game.id);
    if (await addonExists('${dir.path}/deleting.json'))
      throw const RommFailure('Finish deleting this game before playing.');
    if (await _current(dir, server, entry.game.id) != null) return false;
    final all = await library.contentFiles(entry);
    final base = await library.contentFiles(entry, excludeAddons: true);
    return all.length != base.length;
  }

  Future<AddonResult> sync({
    required String serverId,
    required String profileId,
    required InstalledGame entry,
    required RommGame game,
    required RommClient client,
    required DownloadCancellation cancellation,
    required void Function(DownloadProgress) progress,
    SessionLease? owner,
  }) async {
    if (owner != null &&
        (!owner.active || owner.key != await data.resolveSymbolicLinks())) {
      throw StateError('Native package installation has no session owner');
    }
    final lease = owner ?? await SessionLease.acquire(data);
    try {
      cancellation.check();
      if (entry.game.id != game.id ||
          gamePlatform(game, const [])?.slug != platform)
        throw const FormatException('Native package platform differs');
      if (platform == 'switch' && game.files.isEmpty) {
        // A different Switch backend may need to import an old installation's
        // packages. Resolve real remote file identities only in that case;
        // normal launches with a published generation remain local.
        final detail = await client.game(game.id);
        cancellation.check();
        if (detail.id != game.id ||
            detail.platformId != game.platformId ||
            gamePlatform(detail, const [])?.slug != platform)
          throw const FormatException('Native package platform differs');
        game = detail;
      }
      final dir = await _directory(serverId, game.id);
      if (await addonExists('${dir.path}/deleting.json'))
        throw const RommFailure(
          'Finish deleting this game before installing content.',
        );
      final previous = await _current(dir, serverId, game.id);
      final paths = gameFilePaths(game);
      final remote = <(RommFile, String, String)>[];
      for (var i = 0; i < paths.length; i++) {
        final kind =
            addonKind(game.files[i], paths[i]) ??
            (platform == 'wii' && paths[i].toLowerCase().endsWith('.wad')
                ? 'base'
                : null);
        if (kind == null) continue;
        if (platform != 'psp' &&
            RegExp(
              r'\.(txt|nfo|md|url|png|jpg|jpeg)$',
              caseSensitive: false,
            ).hasMatch(paths[i]))
          continue;
        final ext = platform == 'wii' ? '.wad' : '.nsp';
        if (platform != 'psp' && !paths[i].toLowerCase().endsWith(ext))
          throw RommFailure(
            'Extract ${game.files[i].name} to $ext in RomM before installing it. Existing content was kept.',
          );
        if (game.files[i].bytes < 1 ||
            game.files[i].bytes > 64 * 1024 * 1024 * 1024)
          throw const FormatException(
            'Native package size exceeds the supported limit',
          );
        remote.add((game.files[i], paths[i], kind));
      }
      if (remote.length > 1024)
        throw const FormatException('Too many native packages');
      if (remote.isEmpty && previous == null) return const AddonResult(0, 0);
      final local = await library.contentFiles(entry);
      final candidates = gameCandidates(
        playablePlatforms.firstWhere((p) => p.slug == platform),
        local
            .where(
              (file) => !remote.any(
                (r) =>
                    r.$3 != 'base' &&
                    file == '${entry.directory.path}/content/${r.$2}',
              ),
            )
            .toList(),
      );
      if (candidates.length != 1)
        throw const RommFailure(
          'Keep one base game per RomM entry so its updates and DLC can be verified.',
        );
      final baseFile = candidates.single;
      final (executable, profile) = await prepare(profileId, cancellation);
      await _profile(profile, profileId);
      await provision?.call(
        profileId,
        game.platformId,
        client,
        cancellation,
        lease,
        (phase) => progress(DownloadProgress(game, phase, 0, 0)),
      );
      if (previous != null) await _verify(dir, previous);
      final old = previous?['sources'] as Map? ?? {};
      final unchanged =
          remote.length == old.length &&
          remote.every(
            (r) =>
                jsonEncode((old['${r.$1.id}'] as Map?)?['remote']) ==
                jsonEncode(_remote(r.$1, r.$2)),
          );
      if (unchanged && previous != null) {
        if (platform == 'wii' &&
            await wiiGameIdentity(baseFile) != previous['base'])
          throw const FormatException('Wii base title changed');
        if (platform == 'psp' &&
            (await pspGameMetadata(baseFile))['DISC_ID'] != previous['base'])
          throw const FormatException('PSP base title changed');
        if (engine == 'eden') {
          final key = await switchHeaderKey(
            await addonFile(
              Directory('${profile.path}/data/eden'),
              'keys/prod.keys',
            ),
          );
          try {
            if (await switchBaseIdentity(File(baseFile), key) !=
                previous['base'])
              throw const FormatException('Switch base title changed');
          } finally {
            key.fillRange(0, key.length, 0);
          }
        }
        await _apply(dir, previous, profile);
        return AddonResult(0, remote.where((r) => r.$3 != 'base').length);
      }
      final stage = await dir.createTemp('.packages-');
      final generation =
          'generation-${stage.uri.pathSegments.where((p) => p.isNotEmpty).last.substring(10)}';
      var published = false;
      try {
        await addonWrite(File('${stage.path}/owner.json'), {
          'version': 1,
          'server': serverId,
          'game': game.id,
          'platform': platform,
        });
        final packages = Directory('${stage.path}/packages'),
            payload = Directory('${stage.path}/payload');
        await ownedDirectory(packages);
        await ownedDirectory(payload);
        final sources = <String, dynamic>{};
        var transferred = 0, installed = 0;
        final total = remote.fold<int>(0, (n, r) => n + r.$1.bytes);
        for (final r in remote) {
          cancellation.check();
          final f = r.$1,
              name =
                  '${r.$1.id}${platform == 'wii'
                      ? '.wad'
                      : platform == 'psp'
                      ? '.psp'
                      : '.nsp'}';
          final target = File('${packages.path}/$name');
          final before = old['${f.id}'] as Map?;
          final same =
              before != null &&
              jsonEncode(before['remote']) == jsonEncode(_remote(f, r.$2));
          if (r.$3 == 'base') {
            final source = '${entry.directory.path}/content/${r.$2}';
            if (!local.contains(source))
              throw const FormatException(
                'The installed Wii base WAD is missing',
              );
            await File(source).copy(target.path);
          } else if (same) {
            await File(
              await addonPath(dir, '${previous!['generation']}/packages/$name'),
            ).copy(target.path);
          } else if (local.contains(
                '${entry.directory.path}/content/${r.$2}',
              ) &&
              (_crc(f) == null && platform == 'switch' ||
                  _crc(f) != null &&
                      await cancellableCrc32(
                            '${entry.directory.path}/content/${r.$2}',
                            cancellation,
                          ) ==
                          _crc(f))) {
            await File('${entry.directory.path}/content/${r.$2}')
                .copy(target.path);
            installed++;
          } else {
            progress(
              DownloadProgress(
                game,
                'Downloading ${r.$3}: ${f.name}',
                transferred,
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
                  transferred + n,
                  total,
                ),
              ),
            );
            installed++;
          }
          if (await target.length() != f.bytes ||
              _crc(f) != null &&
                  await cancellableCrc32(target.path, cancellation) != _crc(f))
            throw const RommFailure(
              'An update/DLC download did not match RomM; existing content was kept.',
            );
          sources['${f.id}'] = {'remote': _remote(f, r.$2), 'file': name};
          transferred += f.bytes;
        }
        progress(
          DownloadProgress(
            game,
            'Validating and installing updates and DLC',
            total,
            total,
          ),
        );
        final units = <String, dynamic>{};
        final shared = <String, dynamic>{};
        late String base;
        if (platform == 'psp') {
          base = (await pspGameMetadata(baseFile))['DISC_ID']!;
          final ownership = await PackageProfile(
            profile,
            packageEngine,
          ).ownership();
          var version = DateTime.now().toUtc().microsecondsSinceEpoch;
          for (final row in (ownership['files'] as Map).values)
            if ((row['version'] as int) >= version)
              version = (row['version'] as int) + 1;
          await stagePspContent(
            base,
            remote.map((r) => ('${packages.path}/${r.$1.id}.psp', r.$2)),
            stage,
            payload,
            units,
            version,
            cancellation,
          );
        } else if (engine == 'eden') {
          final ownership = await PackageProfile(
            profile,
            packageEngine,
          ).ownership();
          var version = DateTime.now().toUtc().microsecondsSinceEpoch;
          for (final row in (ownership['files'] as Map).values)
            if ((row['version'] as int) >= version)
              version = (row['version'] as int) + 1;
          base = await stageEdenContent(
            File(baseFile),
            remote.map((r) => (File('${packages.path}/${r.$1.id}.nsp'), r.$3)),
            profile,
            payload,
            units,
            version,
            cancellation,
          );
        } else if (platform == 'wii') {
          base = await _importWii(
            executable,
            baseFile,
            remote.map((r) => ('${packages.path}/${r.$1.id}.wad', r.$3)),
            stage,
            payload,
            units,
            shared,
            cancellation,
          );
        } else {
          final ownership = await PackageProfile(
            profile,
            packageEngine,
          ).ownership();
          var sequence = DateTime.now().toUtc().microsecondsSinceEpoch;
          for (final row in (ownership['files'] as Map).values) {
            if ((row['version'] as int) >= sequence)
              sequence = (row['version'] as int) + 1;
          }
          final native = Directory('${stage.path}/native');
          await ownedDirectory(native);
          if (remote.isEmpty && previous != null) {
            base = previous['base'] as String;
          } else {
            final found = await switchInspector(
              executable,
              baseFile,
              packages,
              native,
              profile,
              data,
              cancellation,
            );
            base = found.title;
            final replacements = {
              for (final s in sources.values)
                switchPackagePathIdentity(
                  '${packages.path}/${s['file']}',
                ): File('${dir.path}/$generation/packages/${s['file']}')
                    .absolute
                    .uri
                    .toFilePath(),
            };

            for (final e in {
              'updates': found.updates,
              'dlc': found.dlc,
            }.entries) {
              if (e.value == null) continue;
              final path = 'games/$base/${e.key}.json',
                  file = await addonFile(
                    payload,
                    'games/$base/${e.key}.json',
                    createParents: true,
                  );
              await addonWrite(
                file,
                relocateSwitchPackagePaths(e.value, replacements),
              );
              units[path] = {
                'version': sequence,
                'files': {'': await sha256File(file.path)},
              };
            }
          }
          await native.delete(recursive: true);
        }
        if (previous != null && base != previous['base'])
          throw const FormatException(
            'The installed base game changed; previous content was kept',
          );
        final record = <String, dynamic>{
          'version': 1,
          'server': serverId,
          'game': game.id,
          'platform': platform,
          'base': base,
          'generation': generation,
          'sources': sources,
          'units': units,
          'shared': shared,
        };
        await addonWrite(File('${stage.path}/manifest.json'), record);
        cancellation.check();
        await stage.rename('${dir.path}/$generation');
        published = true;
        await addonWrite(File('${dir.path}/current.json'), record);
        checkpoint?.call('generation-published');
        await _apply(dir, record, profile);
        return AddonResult(
          installed,
          remote.where((r) => r.$3 != 'base').length,
        );
      } finally {
        if (!published && await stage.exists())
          await stage.delete(recursive: true);
      }
    } finally {
      if (owner == null) await lease.release();
    }
  }

  Future<String> _importWii(
    String executable,
    String baseFile,
    Iterable<(String, String)> inputs,
    Directory stage,
    Directory payload,
    Map<String, dynamic> units,
    Map<String, dynamic> shared,
    DownloadCancellation cancellation,
  ) async {
    final base = await wiiGameIdentity(baseFile);
    final selected = <String, (String, WiiWad)>{};
    for (final r in inputs) {
      final path = r.$1, wad = await readWiiWad(path);
      if (r.$2 == 'base' && (wad.type != '00010001' || wad.title != base))
        throw const FormatException(
          'A Wii base WAD must be a matching game channel',
        );
      matchWiiContent(base, wad, r.$2);
      if (selected[wad.title] == null ||
          selected[wad.title]!.$2.version < wad.version)
        selected[wad.title] = (path, wad);
    }
    final native = Directory('${stage.path}/native');
    await ownedDirectory(native);
    for (final p in selected.values) {
      cancellation.check();
      await wiiImporter(executable, p.$1, native, data, cancellation);
      final user = Directory('${native.path}/user'), title = p.$2.title;
      final content =
          'Wii/title/${title.substring(0, 8)}/${title.substring(8)}/content';
      final inventory = await addonInventory(
        Directory(await addonPath(user, content)),
      );
      if (!inventory.containsKey('title.tmd') ||
          inventory.keys.where((p) => p.endsWith('.app')).length !=
              p.$2.regularContents)
        throw const RommFailure(
          'Dolphin did not produce all WAD contents; existing content was kept.',
        );
      final ticket =
          'Wii/ticket/${title.substring(0, 8)}/${title.substring(8)}.tik';
      final files = <String, String>{
        ...{for (final e in inventory.entries) '$content/${e.key}': e.value},
        ticket: await sha256File(await addonPath(user, ticket)),
      };
      for (final f in files.entries) {
        final target = await addonFile(payload, f.key, createParents: true);
        await File(await addonPath(user, f.key)).copy(target.path);
        units[f.key] = {
          'version': p.$2.version,
          'files': {'': f.value},
        };
      }
      if (p.$2.shared) {
        final rows = readWiiContentMap(
          await File(await addonPath(user, 'Wii/shared1/content.map'))
              .readAsBytes(),
        );
        for (final hash in p.$2.sharedHashes) {
          final id = rows.entries.where((r) => r.value == hash).single.key;
          final source = await addonFile(user, 'Wii/shared1/$id.app');
          final h = await sha256File(source.path);
          final target = await addonFile(
            payload,
            'shared/$hash.app',
            createParents: true,
          );
          if (!await target.exists())
            await source.copy(target.path);
          else if (await sha256File(target.path) != h)
            throw const FormatException('Conflicting Wii shared contents');
          shared[hash] = {'hash': h};
        }
      }
    }
    await native.delete(recursive: true);
    return base;
  }

  Future<void> _verify(Directory dir, Map record) async {
    final payload = Directory(
      await addonPath(dir, '${record['generation']}/payload/.probe'),
    );
    final root = payload.parent;
    final expected = <String, String>{};
    for (final e in (record['units'] as Map).entries) {
      if (!PackageProfile(
            Directory('.'),
            packageEngine,
          ).acceptsUnit(e.key as String) ||
          (e.value as Map)['files'] is! Map)
        throw const FormatException('Invalid native content path');
      expected[e.key as String] =
          ((e.value as Map)['files'] as Map)[''] as String;
    }
    for (final e in (record['shared'] as Map? ?? {}).entries) {
      if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(e.key as String) ||
          platform != 'wii')
        throw const FormatException('Invalid shared Wii content');
      expected['shared/${e.key}.app'] = (e.value as Map)['hash'] as String;
    }
    if (!sameAddonInventory(await addonInventory(root), expected))
      throw const FileSystemException(
        'Native package content changed; existing files were kept',
      );
    for (final s in (record['sources'] as Map).values) {
      final f = await addonFile(
        dir,
        '${record['generation']}/packages/${s['file']}',
      );
      if (await f.length() != (s['remote'] as Map)['bytes'])
        throw const FileSystemException('A managed package is incomplete');
    }
  }

  Future<void> _apply(Directory dir, Map record, Directory profile) async {
    final owner = '${record['server']}/${record['game']}';
    final canonical = Directory('${dir.path}/${record['generation']}/payload');
    final units = (record['units'] as Map).cast<String, dynamic>();
    if (platform != 'wii') {
      await PackageProfile(
        profile,
        packageEngine,
        checkpoint: checkpoint,
      ).apply(owner, canonical, units);
      return;
    }
    final content = WiiSharedContent(profile);
    await content.preserveNativeReferences(owner);
    final stage = await profile.createTemp('.wii-apply-');
    try {
      final ready = await content.materialize(
        canonical,
        stage,
        units,
        (record['shared'] as Map? ?? {}).cast<String, dynamic>(),
      );
      await PackageProfile(
        profile,
        packageEngine,
        checkpoint: checkpoint,
      ).apply(owner, stage, ready);
    } finally {
      await stage.delete(recursive: true);
    }
  }

  /// Called under the session lease, before cloud restore and native launch.
  Future<void> applyForLaunch(
    String server,
    int game,
    String profileId,
    Directory profile,
    String rom, {
    InstalledGame? entry,
  }) async {
    await _profile(profile, profileId);
    await PackageProfile(profile, packageEngine).recover();
    final dir = await _directory(server, game);
    if (await addonExists('${dir.path}/deleting.json'))
      throw const RommFailure('Finish deleting this game before playing.');
    var record = await _current(dir, server, game);
    if (record == null &&
        platform == 'wii' &&
        rom.toLowerCase().endsWith('.wad')) {
      if (entry == null ||
          entry.game.id != game ||
          !(await library.contentFiles(entry)).contains(rom))
        throw const FormatException(
          'The Wii base WAD is outside its installed game',
        );
      final cancellation = DownloadCancellation(),
          prepared = await prepare(profileId, DownloadCancellation());
      final stage = await dir.createTemp('.packages-');
      final generation =
          'generation-${stage.uri.pathSegments.where((p) => p.isNotEmpty).last.substring(10)}';
      var published = false;
      try {
        await addonWrite(File('${stage.path}/owner.json'), {
          'version': 1,
          'server': server,
          'game': game,
          'platform': platform,
        });
        final payload = Directory('${stage.path}/payload');
        await ownedDirectory(payload);
        final units = <String, dynamic>{}, shared = <String, dynamic>{};
        final base = await _importWii(
          prepared.$1,
          rom,
          [(rom, 'base')],
          stage,
          payload,
          units,
          shared,
          cancellation,
        );
        await ownedDirectory(Directory('${stage.path}/packages'));
        record = {
          'version': 1,
          'server': server,
          'game': game,
          'platform': platform,
          'base': base,
          'generation': generation,
          'sources': <String, dynamic>{},
          'units': units,
          'shared': shared,
        };
        await addonWrite(File('${stage.path}/manifest.json'), record);
        await stage.rename('${dir.path}/$generation');
        published = true;
        await addonWrite(File('${dir.path}/current.json'), record);
      } finally {
        if (!published && await stage.exists())
          await stage.delete(recursive: true);
      }
    }
    if (record == null) return;
    if (engine == 'eden') {
      final key = await switchHeaderKey(
        File('${profile.path}/data/eden/keys/prod.keys'),
      );
      try {
        if (await switchBaseIdentity(File(rom), key) != record['base'])
          throw const FormatException(
            'Selected Switch base differs from its Eden content',
          );
      } finally {
        key.fillRange(0, key.length, 0);
      }
    }
    if (platform == 'wii' && await wiiGameIdentity(rom) != record['base'])
      throw const FormatException('Selected Wii base differs from its content');
    if (platform == 'psp' &&
        (await pspGameMetadata(rom))['DISC_ID'] != record['base'])
      throw const FormatException('Selected PSP game differs from its content');
    await _verify(dir, record);
    await _apply(dir, record, profile);
  }

  /// References include inactive profiles and retained native preimages. Keeping
  /// a shared update for another installed release must keep its NSP bytes too.
  Future<Set<Uri>> _switchReferences() async {
    final references = <Uri>{};
    var count = 0;
    Future<void> inspect(File file) async {
      final checked = await addonFile(file.parent, file.uri.pathSegments.last);
      if (++count > 100000 || await checked.length() > 12 * 1024 * 1024)
        throw const FormatException(
          'Switch references exceed supported limits',
        );
      final value = jsonDecode(await checked.readAsString());
      void visit(Object? v) {
        if (v is String && v.endsWith('.nsp'))
          references.add(switchPackagePathIdentity(v));
        if (v is Map) v.values.forEach(visit);
        if (v is List) v.forEach(visit);
      }

      visit(value);
    }

    final profiles = Directory('${data.path}/profiles');
    if (await profiles.exists()) {
      await for (final p in profiles.list(followLinks: false)) {
        final id = p.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) continue;
        if (p is! Directory)
          throw const FileSystemException('Linked profile was kept');
        final native = Directory('${p.path}/emulators/ryubing');
        if (!await addonExists(native.path)) continue;
        await _profile(native, id);
        for (final rel in [
          'user/games',
          '.switch-addon-originals',
          '.switch-addon-transaction',
        ]) {
          final path = '${native.path}/$rel';
          if (!await addonExists(path)) continue;
          final root = Directory(await addonPath(native, '$rel/.probe')).parent;
          await for (final f in root.list(
            recursive: true,
            followLinks: false,
          )) {
            if (f is Directory) continue;
            if (f is! File)
              throw const FileSystemException(
                'Linked Switch metadata was kept',
              );
            if (rel == 'user/games' &&
                !{'updates.json', 'dlc.json'}.contains(f.uri.pathSegments.last))
              continue;
            await inspect(f);
          }
        }
      }
    }
    final addons = Directory('${data.path}/addons');
    if (await addons.exists()) {
      // Inspect only this concrete service's current, non-deleting generations.
      await for (final server in addons.list(followLinks: false)) {
        final sid = server.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(sid)) continue;
        if (server is! Directory)
          throw const FileSystemException('Linked add-on server was kept');
        await for (final game in server.list(followLinks: false)) {
          final gid = int.tryParse(
            game.uri.pathSegments.where((s) => s.isNotEmpty).last,
          );
          if (gid == null || gid < 1) continue;
          if (game is! Directory)
            throw const FileSystemException('Linked add-on game was kept');
          final dir = Directory('${game.path}/switch');
          if (!await addonExists(dir.path) ||
              await addonExists('${dir.path}/deleting.json'))
            continue;
          final current = await _current(dir, sid, gid);
          if (current == null) continue;
          for (final unit in (current['units'] as Map).keys.cast<String>()) {
            if (!PackageProfile(Directory('.'), 'switch').acceptsUnit(unit))
              throw const FormatException('Invalid Switch content reference');
            await inspect(
              await addonFile(dir, '${current['generation']}/payload/$unit'),
            );
          }
        }
      }
    }
    return references;
  }

  bool _referencesPackages(Set<Uri> references, String path) {
    final prefix = Directory('$path/packages').absolute.uri
        .normalizePath()
        .toString();
    return references.any((r) => r.toString().startsWith(prefix));
  }

  Future<void> _collectRetained(Set<Uri> references) async {
    final addons = Directory('${data.path}/addons');
    if (!await addons.exists()) return;
    await for (final server in addons.list(followLinks: false)) {
      final sid = server.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(sid) || server is! Directory)
        continue;
      await for (final game in server.list(followLinks: false)) {
        final gid = int.tryParse(
          game.uri.pathSegments.where((s) => s.isNotEmpty).last,
        );
        if (gid == null || gid < 1 || game is! Directory) continue;
        final dir = Directory('${game.path}/switch');
        final marker = File('${dir.path}/retained.json');
        if (!await addonExists(marker.path)) continue;
        final kept = await addonJson(marker);
        if (kept['version'] != 1 ||
            kept['owner'] != '$sid/$gid' ||
            kept['generations'] is! List)
          throw const FormatException('Invalid retained Switch packages');
        final next = <String>[];
        for (final name in (kept['generations'] as List).cast<String>()) {
          if (!RegExp(r'^generation-[a-zA-Z0-9_-]+$').hasMatch(name))
            throw const FormatException('Invalid retained Switch generation');
          final path = await addonPath(dir, name);
          if (_referencesPackages(references, path)) {
            next.add(name);
          } else if (await addonExists(path)) {
            await ownedDirectory(Directory(path));
            // retained.json is the durable deletion authority even after an
            // interrupted recursive delete has removed manifest.json.
            await Directory(path).delete(recursive: true);
            checkpoint?.call('retained-generation-removed');
          }
        }
        if (next.isEmpty)
          await marker.delete();
        else
          await addonWrite(marker, {...kept, 'generations': next});
      }
    }
  }

  /// The library's durable deletion intent and session lease remain in force.
  /// Names are validated before deleting, so retry survives missing inner files.
  Future<void> uninstall(String server, int game) async {
    final dir = await _directory(server, game);
    final intent = File('${dir.path}/deleting.json');
    late Map<String, dynamic> deleting;
    if (await addonExists(intent.path)) {
      deleting = await addonJson(intent);
      if (deleting['version'] != 2 ||
          deleting['owner'] != '$server/$game' ||
          deleting['platform'] != platform ||
          deleting['generations'] is! List ||
          deleting['stages'] is! List)
        throw const FormatException('Invalid native package deletion intent');
    } else {
      await _current(dir, server, game);
      final generations = <String>[], stages = <String>[];
      final retained = File('${dir.path}/retained.json');
      final kept = await addonExists(retained.path)
          ? await addonJson(retained)
          : null;
      if (kept != null &&
          (kept['version'] != 1 ||
              kept['owner'] != '$server/$game' ||
              kept['generations'] is! List))
        throw const FormatException('Invalid retained native packages');
      for (final e in await dir.list(followLinks: false).toList()) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (e is Directory &&
            RegExp(r'^generation-[a-zA-Z0-9_-]+$').hasMatch(name)) {
          if (!((kept?['generations'] as List?) ?? []).contains(name)) {
            final j = await addonJson(File('${e.path}/manifest.json'));
            if (j['server'] != server ||
                j['game'] != game ||
                j['platform'] != platform ||
                j['generation'] != name)
              throw const FormatException(
                'Unrecognized package generation was kept',
              );
          }
          generations.add(name);
        } else if (e is Directory &&
            RegExp(r'^\.packages-[a-zA-Z0-9_-]+$').hasMatch(name)) {
          final owner = await addonJson(File('${e.path}/owner.json'));
          if (owner['version'] != 1 ||
              owner['server'] != server ||
              owner['game'] != game ||
              owner['platform'] != platform)
            throw const FormatException(
              'Unrecognized package staging was kept',
            );
          stages.add(name);
        } else if (!{'current.json', 'retained.json'}.contains(name) ||
            e is! File) {
          throw const FileSystemException(
            'Unrecognized native package data was kept',
          );
        }
      }
      deleting = {
        'version': 2,
        'owner': '$server/$game',
        'platform': platform,
        'generations': generations,
        'stages': stages,
      };
      await addonWrite(intent, deleting);
      checkpoint?.call('deletion-prepared');
    }
    final profiles = Directory('${data.path}/profiles');
    if (await profiles.exists()) {
      await for (final p in profiles.list(followLinks: false)) {
        final id = p.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) continue;
        if (p is! Directory)
          throw const FileSystemException(
            'A private profile is linked; native cleanup was kept pending',
          );
        final native = Directory('${p.path}/emulators/$engine');
        if (!await addonExists(native.path)) continue;
        await _profile(native, id);
        if (platform == 'wii')
          await WiiSharedContent(native)
              .preserveNativeReferences('$server/$game');
        await PackageProfile(
          native,
          packageEngine,
          checkpoint: checkpoint,
        ).remove('$server/$game');
      }
    }
    final current = File('${dir.path}/current.json');
    if (await addonExists(current.path)) await current.delete();
    final references = engine == 'ryubing'
        ? await _switchReferences()
        : <Uri>{};
    final kept = <String>[];
    for (final name in (deleting['generations'] as List).cast<String>()) {
      if (!RegExp(r'^generation-[a-zA-Z0-9_-]+$').hasMatch(name))
        throw const FormatException('Invalid deleting generation');
      final path = await addonPath(dir, name);
      if (_referencesPackages(references, path)) {
        kept.add(name);
      } else if (await addonExists(path)) {
        await ownedDirectory(Directory(path));
        await Directory(path).delete(recursive: true);
        checkpoint?.call('generation-removed');
      }
    }
    for (final name in (deleting['stages'] as List).cast<String>()) {
      if (!RegExp(r'^\.packages-[a-zA-Z0-9_-]+$').hasMatch(name))
        throw const FormatException('Invalid deleting stage');
      final path = await addonPath(dir, name);
      if (await addonExists(path)) {
        await ownedDirectory(Directory(path));
        await Directory(path).delete(recursive: true);
      }
    }
    final retained = File('${dir.path}/retained.json');
    if (kept.isNotEmpty)
      await addonWrite(retained, {
        'version': 1,
        'owner': '$server/$game',
        'generations': kept,
      });
    else if (await addonExists(retained.path))
      await retained.delete();
    await intent.delete();
    if (engine == 'ryubing') await _collectRetained(references);
  }
}
