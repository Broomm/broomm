import 'dart:io';

import '../progress/files.dart';
import '../progress/digest.dart';
import '../progress/layout.dart';
import '../progress/service.dart';
import '../progress/store.dart';
import 'emulators.dart';
import 'save_plan.dart';

/// One journaled external-folder transaction. The session holds SessionLease;
/// the user confirms emulator closure. No process probing or OS hook is used.
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
    if (value is! Map || value.length > progressMaxFiles)
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
          v['bytes'] > progressMaxFileBytes ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(v['sha256'] as String? ?? ''))
        throw const FormatException('Invalid Android save metadata');
      total += v['bytes'] as int;
      if (total > progressMaxBytes)
        throw const FormatException('Android progress exceeds its size limit');
    }
    return files;
  }

  bool same(Map a, Map b) =>
      progressEntriesDigest(a.cast<String, dynamic>()) ==
      progressEntriesDigest(b.cast<String, dynamic>());
  Future<Map<String, dynamic>> list(AndroidSavePlan plan) async => inventory(
    await manager.channel.invokeMapMethod<String, dynamic>('sharedList', {
      ...plan.arguments,
      'areas': plan.remoteAreas.map((a) => a.selector).toList(),
    }),
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
      await manager.channel.invokeMethod<void>('sharedRead', {
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
    await manager.channel.invokeMethod<void>('sharedCheck', plan.arguments);
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
      await manager.channel.invokeMethod<void>('sharedReplace', {
        ...plan.arguments,
        'path': path,
        'before': null,
        'after': after,
        'source': source.path,
        'token': '${r['transaction']}-in',
      });
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
      await manager.channel.invokeMethod<void>('sharedReplace', {
        ...plan.arguments,
        'path': path,
        'before': before[path]?['sha256'],
        'after': after[path]?['sha256'],
        'source': file?.path,
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
