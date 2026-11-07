import 'dart:io';

import '../progress/files.dart';
import '../progress/digest.dart';
import '../progress/layout.dart';
import '../progress/service.dart';
import '../progress/store.dart';
import '../progress/zip.dart';
import '../retroarch.dart';
import 'emulators.dart';
import 'save_plan.dart';

/// One journaled external-folder transaction. The session holds SessionLease;
/// the session supplies emulator-closure evidence before save operations.
class SharedAndroidSaves {
  SharedAndroidSaves(this.manager, {this.phase});
  final AndroidEmulators manager;
  final void Function(String)? phase;
  File get journal => File('${manager.data.path}/android/shared-swap.json');
  Future<bool> get pending => progressExists(journal.path);
  Directory directory(Map record) => Directory(
    '${manager.data.path}/android/shared-session/${record['transaction']}',
  );
  Map<String, dynamic> inventory(Object? value, AndroidSavePlan plan) {
    if (value is! Map || value.length > (plan.rooted ? 128 : progressMaxFiles))
      throw const FormatException('Invalid Android save inventory');
    final files = value.cast<String, dynamic>();
    var total = 0;
    for (final e in files.entries) {
      progressRelative(e.key);
      if (plan.localKey(e.key) == null)
        throw const FormatException(
          'Android save is outside the selected game',
        );
      final v = e.value;
      if (v is! Map ||
          v['bytes'] is! int ||
          v['bytes'] < 0 ||
          v['bytes'] >
              (plan.rooted
                  ? _rootProgressLimit(plan, e.key)
                  : progressMaxFileBytes) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(v['sha256'] as String? ?? ''))
        throw const FormatException('Invalid Android save metadata');
      if (plan.rooted &&
          (v['metadata'] is! String ||
              !RegExp(
                '^${plan.binding['uid']} [0-9]+ [0-7]{3} ${RegExp.escape(plan.binding['label']!)}\$',
              ).hasMatch(v['metadata'] as String)))
        throw const FormatException(
          'Root save ownership metadata is incomplete.',
        );
      total += v['bytes'] as int;
      if (total > (plan.rooted ? 64 * 1024 * 1024 : progressMaxBytes))
        throw const FormatException('Android progress exceeds its size limit');
    }
    return files;
  }

  bool same(Map a, Map b) =>
      progressEntriesDigest(a.cast<String, dynamic>()) ==
          progressEntriesDigest(b.cast<String, dynamic>()) &&
      a.keys.every((key) => a[key]['metadata'] == b[key]['metadata']);
  Future<Map<String, dynamic>> list(AndroidSavePlan plan) async => inventory(
    await manager.channel.invokeMapMethod<String, dynamic>(
      plan.method('List'),
      {
        ...plan.arguments,
        'areas': plan.remoteAreas.map((a) => a.selector).toList(),
      },
    ),
    plan,
  );
  Future<Map<String, dynamic>> record(
    CloudGame game,
    AndroidSavePlan plan,
  ) async {
    final r = await progressJson(journal);
    if (r['version'] != 1 ||
        r['server'] != game.server ||
        r['profile'] != game.profile ||
        r['rom'] != game.rom ||
        r['title'] != plan.game ||
        r['emulator'] != plan.emulator.id ||
        r['tree'] != plan.binding['tree'] ||
        r['package'] != plan.binding['package'] ||
        (r['rootPlatform'] != null &&
            r['rootPlatform'] != plan.launch['platform']) ||
        plan.binding.entries.any((e) => r[e.key] != e.value) ||
        !RegExp(r'^[a-f0-9]{32}$')
            .hasMatch(r['transaction'] as String? ?? '') ||
        !{
          'installing',
          'installed',
          'captured',
          'restoring',
          'restored',
        }.contains(r['phase']))
      throw const FormatException(
        'Android save recovery identity changed. Reconnect the original emulator/profile.',
      );
    inventory(r['original'], plan);
    inventory(r['working'], plan);
    if (r['captured'] != null) inventory(r['captured'], plan);
    return r;
  }

  Future<void> copy(File from, File to, Map metadata) async {
    await to.create(exclusive: true);
    final out = await to.open(mode: FileMode.writeOnly);
    try {
      await for (final b in from.openRead()) await out.writeFrom(b);
      await out.flush();
    } finally {
      await out.close();
    }
    if (await to.length() != metadata['bytes'] ||
        await progressFileHash(to) != metadata['sha256'] ||
        await progressFileHash(from) != metadata['sha256'])
      throw StateError('A private Android recovery copy changed.');
  }

  Future<void> read(
    Map r,
    AndroidSavePlan plan,
    Map<String, dynamic> files,
    String where,
  ) async {
    phase?.call(
      '${plan.emulator.name}: keeping ${files.length} save files in private recovery.',
    );
    for (final e in files.entries) {
      final target = await progressFile(
        directory(r),
        '$where/${e.key}',
        createParents: true,
      );
      await manager.channel.invokeMethod<void>(plan.method('Read'), {
        ...plan.arguments,
        'path': e.key,
        'target': target.path,
        ...e.value as Map,
      });
      if (await target.length() != e.value['bytes'] ||
          await progressFileHash(target) != e.value['sha256'])
        throw StateError('Android snapshot failed verification.');
    }
    if (!same(await list(plan), files))
      throw StateError(
        'Emulator saves changed during capture. Close it and retry; recovery copies were kept.',
      );
  }

  Future<void> begin(
    CloudGame game,
    AndroidSavePlan plan,
    String build, {
    required String selected,
  }) async {
    if (await pending)
      throw StateError('Finish the previous connected-folder game first.');
    if (plan.root !=
        '${manager.data.path}/profiles/${game.profile}/emulators/${plan.emulator.id}')
      throw const FormatException(
        'Android save root belongs to another profile',
      );
    await manager.channel.invokeMethod<void>(
      plan.method('Check'),
      plan.arguments,
    );
    final r = <String, dynamic>{
      'version': 1,
      'transaction': progressNonce(),
      ...plan.arguments,
      'server': game.server,
      'profile': game.profile,
      'rom': game.rom,
      'title': plan.game,
      'build': build,
      'selected': selected,
      if (plan.rooted) 'rootConfigPath': plan.launch['configPath'],
      if (plan.rooted && plan.launch['platform'] != null)
        'rootPlatform': plan.launch['platform'],
      if (plan.rooted && plan.launch['stateGroup'] != null)
        'rootStateGroup': plan.launch['stateGroup'],
      'phase': 'installing',
      'original': await list(plan),
      'working': <String, dynamic>{},
    };
    await progressDirectory(directory(r));
    await read(r, plan, r['original'] as Map<String, dynamic>, 'original');
    final working = r['working'] as Map<String, dynamic>;
    for (final e in (await plan.files()).entries) {
      final remote = plan.remotePath(e.key),
          metadata = {
            'bytes': await e.value.length(),
            'sha256': await progressFileHash(e.value),
            if (plan.rooted)
              'metadata':
                  (r['original'] as Map)[remote]?['metadata'] ??
                  '${plan.binding['uid']} ${plan.binding['uid']} 600 ${plan.binding['label']}',
          };
      if (working.containsKey(remote))
        throw const FormatException('Ambiguous Android save mapping');
      working[remote] = metadata;
      await copy(
        e.value,
        await progressFile(
          directory(r),
          'working/$remote',
          createParents: true,
        ),
        metadata,
      );
    }
    inventory(working, plan);
    await progressWrite(
      await progressFile(
        manager.data,
        'android/shared-swap.json',
        createParents: true,
      ),
      r,
    );
    await apply(r, plan, 'original', 'working', 'working');
    await configure(r, plan);
    r['phase'] = 'installed';
    await progressWrite(journal, r);
  }

  /// A pending native session keeps its original physical state group. A newer
  /// core may capture those bytes for recovery but cannot relabel them as its own.
  Future<AndroidSavePlan> recoveryPlan(
    CloudGame game,
    AndroidSavePlan current,
  ) async {
    if (!current.rooted) return current;
    final r = await progressJson(journal);
    final group = r['rootStateGroup'];
    if (group != null &&
        (group is! String ||
            !RegExp(r'^states-[a-f0-9]{16}-android$').hasMatch(group)))
      throw const FormatException('Invalid rooted state recovery group.');
    final save = current.remoteAreas.singleWhere((a) => a.local.id == 'save');
    final base = save.remote.substring(0, save.remote.length - '/saves'.length);
    final config = r['rootConfigPath'] ?? current.launch['configPath'];
    if (config is! String ||
        !RegExp('^${RegExp.escape(base)}/config-[a-f0-9]{32}\\.cfg\$')
            .hasMatch(config))
      throw const FormatException(
        'Invalid rooted configuration recovery path.',
      );
    final localBase = save.local.path.substring(
      0,
      save.local.path.length - '/saves'.length,
    );
    final state = group == null
        ? null
        : ProgressArea(
            group as String,
            '$localBase/$group',
            prefix: save.local.prefix,
            pattern:
                '^${RegExp.escape(save.local.prefix!)}\\.state(?:[0-9]{1,10}|\\.auto)?(?:\\.png)?\$',
          );
    final plan = AndroidSavePlan(
      ProgressLayout(current.root, current.format, current.game, [
        save.local,
        if (state != null) state,
      ]),
      current.emulator,
      current.binding,
      [save, if (state != null) AndroidSaveArea(state, '$base/states/$group')],
      launch: {
        ...current.launch,
        'configPath': config,
        'configNative': '${current.binding['dataDir']}/$config',
        if (group != null) 'stateGroup': group as String,
      },
    );
    await record(game, plan);
    return plan;
  }

  Future<void> configure(Map<String, dynamic> r, AndroidSavePlan plan) async {
    for (final name in ['config', 'options']) {
      final path = plan.launch['${name}Path'],
          text = plan.launch['${name}Text'];
      if (path == null || text == null) continue;
      final source = await progressFile(
        directory(r),
        'configuration/$name',
        createParents: true,
      );
      await source.writeAsString(text, flush: true);
      final after = await progressFileHash(source);
      if (plan.rooted) {
        if (path != r['rootConfigPath'])
          throw const FormatException('Invalid rooted session configuration.');
        r['configuration'] = {path: after};
        // Retain the exact owned bytes before publication, including when the
        // native write succeeds but its reply or the next checkpoint is lost.
        await progressWrite(journal, r);
      }
      await manager.channel.invokeMethod<void>(plan.method('Replace'), {
        ...plan.arguments,
        'path': path,
        if (plan.launch['stateGroup'] case final group?) 'stateGroup': group,
        'before': null,
        'after': after,
        'source': source.path,
        'token': '${r['transaction']}-in',
      });
    }
  }

  Future<String> stageRootRom(CloudGame game, AndroidSavePlan plan) async {
    final r = await record(game, plan);
    var source = File(r['selected'] as String);
    var name = source.uri.pathSegments.last;
    progressRelative(name);
    final extensions = _rootRomExtensions(plan);
    final extension = name.split('.').last.toLowerCase();
    if ((!extensions.contains(extension) && extension != 'zip') ||
        extensions.isEmpty ||
        !plan.rooted ||
        r['phase'] != 'installed')
      throw StateError(
        'Rooted RetroArch requires one supported cartridge, uncompressed or in a ZIP.',
      );
    Directory? extraction;
    try {
      if (extension == 'zip') {
        phase?.call('Checking and extracting the cartridge…');
        final before = await progressFileHash(source);
        final zip = await ProgressZip.read(
          source,
          maxBytes: _rootRomLimit(plan) * 2,
          maxEntryBytes: _rootRomLimit(plan),
        );
        final cartridges = zip.entries
            .where(
              (e) => extensions.contains(e.name.split('.').last.toLowerCase()),
            )
            .toList();
        if (cartridges.length != 1)
          throw StateError(
            'The ZIP must contain exactly one supported cartridge.',
          );
        extraction = await directory(r).createTemp('cartridge-');
        final contents = Directory('${extraction.path}/contents');
        await zip.extract(contents);
        if (await progressFileHash(source) != before)
          throw StateError(
            'The game archive changed during extraction. Try again.',
          );
        final cartridge = cartridges.single;
        source = await progressFile(contents, cartridge.name);
        final rawExtension = cartridge.name.split('.').last.toLowerCase();
        // Keep the original archive's save/state stem, independently of its
        // internal filename. Existing profile and desktop progress still match.
        name = '${retroStateStem(r['selected'] as String)}.$rawExtension';
        progressRelative(name);
        source = await source.rename(
          (await progressFile(extraction, name)).path,
        );
        r['romStageExtension'] = rawExtension;
      }
      final config = plan.launch['configPath']!;
      final parent = config.substring(0, config.lastIndexOf('/'));
      final path = '$parent/rom-${r['transaction']}/$name';
      final bytes = await source.length();
      if (bytes < 1 || bytes > _rootRomLimit(plan))
        throw StateError(
          'The RetroArch game file must be between 1 byte and ${_rootRomLimit(plan) ~/ (1024 * 1024)} MiB.',
        );
      final hash = await progressFileHash(source);
      r['romStage'] = path;
      r['romStageSha256'] = hash;
      await progressWrite(journal, r);
      return (await manager.channel.invokeMethod<String>('rootStageRom', {
        ...plan.arguments,
        'path': path,
        'source': source.path,
        'sha256': hash,
        if (extension == 'zip') 'preparedCartridge': true,
      }))!;
    } finally {
      // Native staging has finished (or failed) before its private source goes.
      // The durable native path/hash already covers a lost staging reply.
      await extraction?.delete(recursive: true);
    }
  }

  Future<void> apply(
    Map<String, dynamic> r,
    AndroidSavePlan plan,
    String beforeKey,
    String afterKey,
    String source,
  ) async {
    final before = inventory(r[beforeKey], plan),
        after = inventory(r[afterKey], plan),
        paths = {...before.keys, ...after.keys}.toList()..sort();
    for (final path in paths) {
      final file = after[path] == null
          ? null
          : await progressFile(directory(r), '$source/$path');
      if (file != null && await progressFileHash(file) != after[path]['sha256'])
        throw StateError(
          'Android recovery copy is damaged. Native files were kept.',
        );
      await manager.channel.invokeMethod<void>(plan.method('Replace'), {
        ...plan.arguments,
        'path': path,
        'before': before[path]?['sha256'],
        'after': after[path]?['sha256'],
        'source': file?.path,
        if (plan.rooted) 'metadata': after[path]?['metadata'],
        'token': '${r['transaction']}-${afterKey == 'working' ? 'in' : 'out'}',
      });
    }
    if (!same(await list(plan), after))
      throw StateError(
        'Emulator files changed during replacement. Recovery copies were kept.',
      );
  }

  Future<bool> capture(
    CloudGame game,
    CloudSaves cloud,
    AndroidSavePlan plan,
  ) async {
    final r = await record(game, plan);
    if (r['phase'] == 'restoring' || r['phase'] == 'restored') return false;
    if (r['phase'] == 'installing') {
      await apply(r, plan, 'original', 'working', 'working');
      r.addAll({
        'captured': r['working'],
        'capture': 'working',
        'phase': 'restoring',
      });
      await progressWrite(journal, r);
      return false;
    }
    final files = await list(plan), capture = 'captures/${progressNonce()}';
    if (plan.rooted &&
        (r['working'] as Map).keys.any((path) => !files.containsKey(path)))
      throw StateError(
        'An installed RetroArch save or state is missing. Recovery copies were kept; restore the working file before syncing.',
      );
    if (files.isEmpty)
      cloud.notice(
        'No save files were found in ${plan.emulator.name}’s connected folder. If you saved in-game, check its folder and memory-card settings.',
        false,
      );
    await read(r, plan, files, '$capture/native');
    final canonical = Directory('${directory(r).path}/$capture/profile');
    final layout = ProgressLayout(
      canonical.path,
      game.layout.format,
      game.layout.game,
      game.layout.areas,
      rawSave: game.layout.rawSave,
    );
    for (final e in files.entries) {
      final key = plan.localKey(e.key)!;
      if (!game.layout.areas.any((a) => key.startsWith('${a.id}/')))
        continue; // Changed-build states stay in retained native capture.
      await copy(
        await progressFile(directory(r), '$capture/native/${e.key}'),
        await layout.target(key),
        e.value as Map,
      );
    }
    final store = cloud.store(game);
    await store.recover();
    final snapshot = await ProgressStore(
      store.directory,
      layout,
      game.rom,
      game.user,
      ownerRoot: manager.data,
    ).capture();
    await store.restore(snapshot, await store.state());
    r.addAll({
      'captured': files,
      'capture': '$capture/native',
      'phase': 'captured',
    });
    await progressWrite(journal, r);
    return true;
  }

  Future<void> restoreOriginal(CloudGame game, AndroidSavePlan plan) async {
    final r = await record(game, plan);
    if (r['phase'] == 'captured') {
      if (!same(await list(plan), inventory(r['captured'], plan)))
        throw StateError(
          'The emulator wrote more progress after capture. Close it and finish again.',
        );
      r['phase'] = 'restoring';
      await progressWrite(journal, r);
    }
    if (r['phase'] == 'restoring') {
      await apply(r, plan, 'captured', 'original', 'original');
      r['phase'] = 'restored';
      await progressWrite(journal, r);
    }
    if (r['phase'] != 'restored')
      throw StateError('Capture progress before restoring standalone saves.');
    if (r['romStage'] case final String path when plan.rooted) {
      final config = plan.launch['configPath']!;
      final parent = config.substring(0, config.lastIndexOf('/'));
      final selected = r['selected'] as String;
      var name = File(selected).uri.pathSegments.last;
      if (r['romStageExtension'] case final Object extension) {
        if (!name.toLowerCase().endsWith('.zip') ||
            extension is! String ||
            !_rootRomExtensions(plan).contains(extension))
          throw const FormatException(
            'Rooted cartridge staging identity changed.',
          );
        name = '${retroStateStem(selected)}.$extension';
      }
      final hash = r['romStageSha256'];
      if (path != '$parent/rom-${r['transaction']}/$name' ||
          hash is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))
        throw const FormatException(
          'Rooted cartridge staging identity changed.',
        );
      await manager.channel.invokeMethod<void>('rootRemoveRom', {
        ...plan.arguments,
        'path': path,
        'sha256': hash,
      });
    }
    if (plan.rooted && r['configuration'] != null) {
      final configuration = r['configuration'];
      if (configuration is! Map ||
          configuration.length != 1 ||
          configuration.entries.any(
            (e) =>
                e.key != r['rootConfigPath'] ||
                e.key != plan.launch['configPath'] ||
                e.value is! String ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(e.value as String),
          ))
        throw const FormatException('Invalid rooted configuration cleanup.');
      for (final e in configuration.entries) {
        await manager.channel.invokeMethod<void>(plan.method('Replace'), {
          ...plan.arguments,
          'path': e.key,
          'before': e.value,
          'after': null,
          'token': '${r['transaction']}-out',
        });
      }
    }
    await progressWrite(await progressFile(directory(r), 'completed.json'), r);
    await journal.delete();
  }

  Future<void> keepFolder(String server, String profile, int rom) async {
    final r = await progressJson(journal);
    if (r['server'] != server ||
        r['profile'] != profile ||
        r['rom'] != rom ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(r['transaction'] as String? ?? ''))
      throw const FormatException('Android recovery identity changed');
    await progressWrite(
      await progressFile(directory(r), 'kept-shared-folder.json'),
      {
        ...r,
        'resolution': 'user-kept-folder',
        'resolved': DateTime.now().toUtc().toIso8601String(),
      },
    );
    await journal.delete();
  }
}

Set<String> _rootRomExtensions(AndroidSavePlan plan) =>
    switch (plan.binding['access']) {
      'root-gba-v1' => {'gba'},
      'root-snes-v1' => {'sfc', 'smc'},
      'root-gameboy-v1' => {'gb', 'gbc', 'dmg'},
      'root-cartridge-v1' => switch (plan.launch['platform']) {
        'atari2600' => {'a26', 'bin'},
        'tg16' => {'pce'},
        'genesis' => {'md', 'gen', 'smd', 'bin'},
        'sms' => {'sms', 'sg'},
        'gamegear' => {'gg'},
        'sega32' => {'32x', 'bin', 'gen', 'smd', 'md'},
        'n64' => {'z64', 'v64', 'n64'},
        'nes' => {'nes', 'unf', 'unif'},
        'jaguar' => {'j64', 'jag', 'rom', 'abs', 'cof', 'bin', 'prg'},
        _ => {},
      },
      _ => {},
    };

int _rootRomLimit(AndroidSavePlan plan) =>
    (plan.launch['platform'] == 'n64' ? 64 : 32) * 1024 * 1024;

int _rootProgressLimit(AndroidSavePlan plan, String path) {
  final n64 = plan.launch['coreName'] == 'mupen64plus_next';
  if (path.contains('/states/')) return (n64 ? 32 : 16) * 1024 * 1024;
  return n64 ? 296960 : 262144;
}
