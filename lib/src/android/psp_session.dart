import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../addons/package_profile.dart';
import '../progress/digest.dart';
import '../progress/files.dart';
import '../progress/layout.dart';
import '../progress/service.dart';
import '../progress/store.dart';
import 'emulators.dart';
import 'psp_root.dart';
import 'psp_root_store.dart';

/// Concrete PSP session transaction. Native code provides bounded file effects;
/// ownership, reconciliation, launch checkpoints and recovery remain in Dart.
class AndroidPspSession {
  AndroidPspSession(this.manager, this.cloud, {this.check});
  final AndroidEmulators manager;
  final CloudSaves cloud;
  final void Function()? check;
  late final roots = AndroidPspRootStore(manager, check: check);
  File get journal => File('${manager.data.path}/android/psp-swap.json');
  Future<bool> get pending => progressExists(journal.path);
  final _nonce = RegExp(r'^[a-f0-9]{32}$');

  Future<Map<String, dynamic>> record(
    CloudGame game,
    AndroidPspPlan plan,
  ) async {
    final r = await progressJson(
      await progressFile(manager.data, 'android/psp-swap.json'),
    );
    if (r['version'] != 1 ||
        r['emulator'] != 'ppsspp' ||
        r['server'] != game.server ||
        r['profile'] != game.profile ||
        r['rom'] != game.rom ||
        r['user'] != game.user ||
        r['discId'] != plan.game ||
        r['discVersion'] != plan.version ||
        r['stateGroup'] != plan.stateGroup ||
        !mapEquals(
          (r['binding'] as Map?)?.cast<String, String>(),
          plan.binding,
        ) ||
        ![
          'transaction',
          'ownerNonce',
        ].every((k) => _nonce.hasMatch(r[k] as String? ?? '')) ||
        !{
          'preparing',
          'reconciled',
          'installing',
          'installed',
          'launching',
          'launched',
          'captured',
          'finishing',
        }.contains(r['phase']))
      throw const FormatException(
        'The PSP recovery belongs to another game, profile or installation. All copies were kept.',
      );
    return r;
  }

  Map<String, dynamic> arguments(Map r, AndroidPspPlan plan) => {
    ...plan.arguments,
    'server': r['server'],
    'profile': r['profile'],
    'ownerNonce': r['ownerNonce'],
    'excluded': jsonEncode(plan.excluded.toList()..sort()),
  };
  Future<Directory> directory(Map r) async {
    final nonce = r['transaction'] as String;
    if (!_nonce.hasMatch(nonce))
      throw const FormatException('Invalid PSP transaction.');
    return (await progressFile(
      manager.data,
      'android/shared-session/$nonce/.probe',
      createParents: true,
    )).parent;
  }

  Future<File> baseline(CloudGame game, AndroidPspPlan plan) => progressFile(
    Directory(plan.root),
    'root-games/${plan.game}-${plan.version}.json',
    createParents: true,
  );
  Future<Map<String, dynamic>> list(Map r, AndroidPspPlan plan) =>
      readAndroidPspInventory(
        manager,
        plan.binding,
        arguments(r, plan),
        accepts: (path) => plan.key(path) != null,
        check: check,
      );

  Future<void> copy(File from, File to, Map expected) async {
    check?.call();
    if (!await from.exists() ||
        await from.length() != expected['bytes'] ||
        await progressFileHash(from) != expected['sha256'])
      throw const FileSystemException(
        'Private PSP source is missing or damaged. Recovery was kept.',
      );
    if (!await to.exists()) {
      await to.create(exclusive: true);
      final out = await to.open(mode: FileMode.writeOnly);
      try {
        await for (final chunk in from.openRead()) {
          await out.writeFrom(chunk);
        }
        await out.flush();
      } finally {
        await out.close();
      }
    }
    if (await to.length() != expected['bytes'] ||
        await progressFileHash(to) != expected['sha256'] ||
        await progressFileHash(from) != expected['sha256'])
      throw const FileSystemException(
        'Private PSP copy was not verified. Recovery was kept.',
      );
  }

  Future<String> hold(
    Map<String, dynamic> r,
    AndroidPspPlan plan,
    Map<String, dynamic> files,
  ) async {
    final retained = List<dynamic>.from(r['captures'] as List? ?? []);
    if (retained.length >= 8)
      throw StateError(
        'Several incomplete PSP captures were kept. Review recovery before retrying.',
      );
    final name = 'captures/${progressNonce()}';
    retained.add(name);
    r['captures'] = retained;
    await progressWrite(journal, r);
    final base = await directory(r);
    await progressWrite(
      await progressFile(base, '$name/manifest.json', createParents: true),
      {'files': files},
    );
    for (final e in files.entries) {
      check?.call();
      final target = await progressFile(
        base,
        '$name/${e.key}',
        createParents: true,
      );
      await manager.channel.invokeMethod<void>('rootPspRead', {
        ...arguments(r, plan),
        'path': e.key,
        ...e.value as Map,
        'target': target.path,
      });
      if (await target.length() != e.value['bytes'] ||
          await progressFileHash(target) != e.value['sha256'])
        throw const FileSystemException(
          'PSP save capture was not verified. Native progress was kept.',
        );
    }
    if (!pspInventorySame(files, await list(r, plan)))
      throw StateError(
        'PSP saves changed during capture. The private copies were kept.',
      );
    return name;
  }

  Future<ProgressSnapshot> seal(
    CloudGame game,
    AndroidPspPlan plan,
    Map r,
    Map files,
    String capture,
  ) async {
    final base = await directory(r),
        target = Directory(
          '${(await directory(r)).path}/canonical/${progressNonce()}',
        );
    final layout = ProgressLayout(
      target.path,
      plan.format,
      plan.game,
      plan.areas,
    );
    for (final e in files.entries) {
      final key = plan.key(e.key as String);
      if (key == null)
        throw const FormatException('PSP capture includes unrelated data.');
      await copy(
        await progressFile(base, '$capture/${e.key}'),
        await layout.target(key),
        e.value as Map,
      );
    }
    return ProgressStore(
      cloud.store(game).directory,
      layout,
      game.rom,
      game.user,
      ownerRoot: manager.data,
    ).capture();
  }

  /// Reconcile changes made through detached Open emulator before cloud sync.
  /// Both sides are sealed before any choice; a missing known writer file is
  /// damaged recovery rather than a confirmed empty native save.
  Future<void> prepare(
    CloudGame game,
    AndroidPspPlan plan, {
    ProgressResolver? resolve,
  }) async {
    if (await pending)
      throw StateError('Finish the previous PSP transaction first.');
    await roots.restoreSettingsLoan();
    final profile = await roots.profile(
      game.server,
      game.profile,
      plan.binding,
    );
    await roots.backup(profile);
    final r = <String, dynamic>{
      'version': 1,
      'emulator': 'ppsspp',
      'package': plan.binding['package'],
      'rooted': true,
      'rootPlatform': 'psp',
      'server': game.server,
      'profile': game.profile,
      'rom': game.rom,
      'user': game.user,
      'discId': plan.game,
      'discVersion': plan.version,
      'stateGroup': plan.stateGroup,
      'stateAreas': [plan.stateGroup],
      'binding': plan.binding,
      'ownerNonce': profile['ownerNonce'],
      'transaction': progressNonce(),
      'phase': 'preparing',
      'captures': <dynamic>[],
      'pending': null,
    };
    await progressWrite(
      await progressFile(
        manager.data,
        'android/psp-swap.json',
        createParents: true,
      ),
      r,
    );
    final native = await list(r, plan), file = await baseline(game, plan);
    Map<String, dynamic>? known;
    if (await file.exists()) {
      known = await progressJson(file);
      if (known['version'] != 1 ||
          known['server'] != game.server ||
          known['profile'] != game.profile ||
          known['discId'] != plan.game ||
          known['discVersion'] != plan.version ||
          known['files'] is! Map ||
          known['local'] is! Map)
        throw const FormatException(
          'PSP reconciliation baseline is damaged. All copies were kept.',
        );
      if (known['ownerNonce'] != profile['ownerNonce'])
        known = null; // Fresh, explicitly restored installation generation.
    }
    final compatible = known == null || known['stateGroup'] == plan.stateGroup;
    final reconciled = <String, dynamic>{
      for (final e in native.entries)
        if (compatible || e.key.startsWith('PSP/SAVEDATA/')) e.key: e.value,
    };
    final knownFiles = <String, dynamic>{
      for (final e in (known?['files'] as Map? ?? {}).entries)
        if (compatible || (e.key as String).startsWith('PSP/SAVEDATA/'))
          e.key as String: e.value,
    };
    final nativeChanged = known == null
        ? reconciled.isNotEmpty
        : !pspInventorySame(knownFiles, reconciled, metadata: false);
    if (known != null &&
        (known['files'] as Map).keys.any((p) => !native.containsKey(p)))
      throw StateError(
        'A known PSP save or state is missing. Restore it before synchronizing. Recovery was kept.',
      );
    final store = cloud.store(game);
    await store.recover();
    final local = await store.capture();
    r['localBefore'] = store.storageId(local);
    r['before'] = native;
    await progressWrite(journal, r);
    if (nativeChanged) {
      final capture = await hold(r, plan, native),
          held = await seal(game, plan, r, reconciled, capture);
      final localChanged = known == null
          ? !local.empty
          : !pspInventorySame(
              {
                for (final e in (known['local'] as Map).entries)
                  if (plan.areas.any(
                    (a) => (e.key as String).startsWith('${a.id}/'),
                  ))
                    e.key: e.value,
              },
              local.entries,
              metadata: false,
            );
      var adopt = !localChanged || held.digest == local.digest;
      if (!adopt) {
        final choice = resolve == null
            ? ProgressChoice.cancel
            : await resolve(
                ProgressConflict(
                  'Broomm and this profile’s private PPSSPP memory stick both changed. Choose which progress to use before cloud synchronization.',
                  local,
                  held,
                  localLabel: 'Broomm',
                  remoteLabel: 'PPSSPP',
                ),
              );
        if (choice == ProgressChoice.cancel)
          throw StateError(
            'PSP progress choice was cancelled. Both copies were kept.',
          );
        adopt = choice == ProgressChoice.cloud;
      }
      if (adopt) {
        final state = await store.state(),
            knownStates = (state['stateKnown'] as Map? ?? {})
                .cast<String, String>();
        for (final e in held.entries.entries) {
          if (e.key.startsWith('${plan.stateGroup}/'))
            knownStates[e.key] = e.value['sha256'] as String;
        }
        await store.restore(held, {
          ...state,
          'stateKnown': knownStates,
          'pending': true,
        });
      }
    }
    r['phase'] = 'reconciled';
    await progressWrite(journal, r);
  }

  Future<void> replay(Map<String, dynamic> r, AndroidPspPlan plan) async {
    check?.call();
    final operation = r['pending'] as Map?;
    if (operation == null) return;
    final path = operation['path'] as String;
    final static = plan.key(path) == null;
    if (static &&
        !RegExp(
          '^PSP/(?:GAME|SAVEDATA)/${RegExp.escape(plan.game)}[A-Za-z0-9_-]{0,80}/.+\$',
        ).hasMatch(path))
      throw const FormatException(
        'PSP publication is outside this game and its installed add-ons.',
      );
    final source = operation['after'] == null
        ? null
        : await progressFile(await directory(r), 'working/$path');
    if (source != null &&
        (await source.length() != (r['working'] as Map)[path]['bytes'] ||
            await progressFileHash(source) != operation['after']))
      throw const FileSystemException(
        'Pending PSP publication source is damaged. Recovery was kept.',
      );
    await manager.channel.invokeMethod<Object?>(
      static ? 'rootPspProfileReplace' : 'rootPspReplace',
      {
        ...arguments(r, plan),
        ...operation,
        if (source != null) 'source': source.path,
      },
    );
    (r['done'] as List).add(path);
    r['pending'] = null;
    await progressWrite(journal, r);
  }

  Future<void> cloudPrepared(CloudGame game, AndroidPspPlan plan) async {
    final r = await record(game, plan);
    r['cloudPrepared'] = true;
    await progressWrite(journal, r);
  }

  Future<void> install(CloudGame game, AndroidPspPlan plan) async {
    final r = await record(game, plan);
    if (r['phase'] == 'reconciled') {
      final snapshot = await cloud.store(game).capture(),
          base = await directory(r);
      final working = <String, dynamic>{};
      for (final e in snapshot.entries.entries) {
        if (!plan.areas.any((a) => e.key.startsWith('${a.id}/'))) continue;
        final path = plan.nativePath(e.key);
        await copy(
          await progressFile(
            Directory('${snapshot.directory.path}/files'),
            e.key,
          ),
          await progressFile(base, 'working/$path', createParents: true),
          e.value as Map,
        );
        working[path] = e.value;
      }
      final owned = await PackageProfile(
        Directory(plan.root),
        'psp',
      ).ownership();
      for (final e in (owned['files'] as Map).entries) {
        final path = e.key as String;
        if (!RegExp(
          '^PSP/(?:GAME|SAVEDATA)/${plan.game}[A-Za-z0-9_-]{0,80}/.+\$',
        ).hasMatch(path))
          continue;
        final source = await progressFile(Directory(plan.root), 'user/$path');
        final expected = {
          'sha256': e.value['hash'],
          'bytes': await source.length(),
        };
        await copy(
          source,
          await progressFile(base, 'working/$path', createParents: true),
          expected,
        );
        working[path] = expected;
      }
      // All working bytes are held before the first native replacement.
      final full = await roots.nativeFiles(r);
      final before = Map<String, dynamic>.from(r['before'] as Map);
      final knownFile = await baseline(game, plan);
      final known = await knownFile.exists()
          ? await progressJson(knownFile)
          : null;
      final oldStatic = known?['static'] as Map? ?? {};
      var total = full.values.fold<int>(
        0,
        (sum, entry) => sum + (entry['bytes'] as int),
      );
      for (final path in {
        ...before.keys.cast<String>(),
        ...oldStatic.keys.cast<String>(),
        ...working.keys,
      }) {
        total -= (full[path]?['bytes'] as int? ?? 0);
        total += (working[path]?['bytes'] as int? ?? 0);
        if ((working[path]?['bytes'] as int? ?? 0) >
            (plan.key(path) == null ? 1024 : 256) * 1024 * 1024)
          throw StateError(
            'PSP working file exceeds its size limit. Nothing was published.',
          );
      }
      if (total > 2048 * 1024 * 1024)
        throw StateError(
          'The private PSP memory stick would exceed its backup limit. Nothing was published.',
        );
      for (final path in {
        ...oldStatic.keys.cast<String>(),
        ...working.keys.where((p) => plan.key(p) == null),
      }) {
        if (oldStatic[path] != null &&
            full[path]?['sha256'] != oldStatic[path]['sha256'])
          throw StateError(
            'A previously installed PSP add-on changed. Its native data was kept.',
          );
        if (full[path] != null) before[path] = full[path];
      }
      r.addAll({
        'working': working,
        'before': before,
        'done': <String>[],
        'phase': 'installing',
      });
      await progressWrite(journal, r);
    }
    if (r['phase'] != 'installing')
      throw StateError('PSP preparation is incomplete. Finish recovery first.');
    await replay(
      r,
      plan,
    ); // A linked-but-unacknowledged file must be replayed before inventory.
    final before = r['before'] as Map, working = r['working'] as Map;
    for (final path in {
      ...before.keys.cast<String>(),
      ...working.keys.cast<String>(),
    }.toList()..sort()) {
      if ((r['done'] as List).contains(path)) continue;
      r['pending'] = {
        'path': path,
        'before': before[path]?['sha256'],
        'metadata': before[path]?['metadata'],
        'after': working[path]?['sha256'],
        'token': progressNonce(),
      };
      await progressWrite(journal, r);
      await replay(r, plan);
    }
    final current = await list(r, plan),
        expected = <String, dynamic>{
          for (final e in working.entries)
            if (plan.key(e.key as String) != null) e.key as String: e.value,
        };
    if (!pspInventorySame(current, expected, metadata: false))
      throw StateError(
        'PSP working progress was not confirmed. Recovery was kept.',
      );
    r['phase'] = 'installed';
    await progressWrite(journal, r);
    final profile = await roots.profile(
      game.server,
      game.profile,
      plan.binding,
    );
    await roots.borrow(profile, kind: 'game', transaction: r['transaction']);
  }

  Future<({int elapsed, int wall})> launching(
    CloudGame game,
    AndroidPspPlan plan,
  ) async {
    final r = await record(game, plan),
        clock = await roots.ensureClosed(plan.binding);
    if (r['phase'] != 'installed')
      throw StateError('PSP working memory stick is not ready.');
    r.addAll({
      'phase': 'launching',
      'launchElapsed': clock.elapsed,
      'launchWall': clock.wall,
    });
    await progressWrite(
      journal,
      r,
    ); // A lost activity-launch reply is still a possible writer.
    return clock;
  }

  Future<void> identify(
    CloudGame game,
    AndroidPspPlan plan,
    ({int elapsed, int wall}) clock,
  ) async {
    final r = await record(game, plan);
    for (var attempt = 0; attempt < 8; attempt++) {
      final report = await readAndroidPspState(
        manager,
        plan.binding,
        launchedAfter: clock,
      );
      if (report.process != null) {
        r.addAll({'process': report.process, 'phase': 'launched'});
        await progressWrite(journal, r);
        return;
      }
      if (attempt < 7)
        await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    cloud.phase?.call(
      'PPSSPP process is not yet identified. Recovery was retained.',
    );
  }

  Future<AndroidPspState> exitState(CloudGame game, AndroidPspPlan plan) async {
    final r = await record(game, plan);
    return (await readAndroidPspState(
      manager,
      plan.binding,
      process: (r['process'] as Map?)?.cast<String, int>(),
      launchedAfter: r['launchElapsed'] is int && r['launchWall'] is int
          ? (elapsed: r['launchElapsed'] as int, wall: r['launchWall'] as int)
          : null,
    )).state;
  }

  Future<void> finish(
    CloudGame game,
    AndroidPspPlan plan, {
    required bool automatic,
  }) async {
    final r = await record(game, plan);
    await roots.ensureClosed(plan.binding);
    final launched = {
      'launching',
      'launched',
      'captured',
      'finishing',
    }.contains(r['phase']);
    final exit = await exitState(game, plan);
    if (automatic && (exit != AndroidPspState.closed || !launched))
      throw StateError(
        'PPSSPP normal exit was not verified. Recovery was kept.',
      );
    if (r['phase'] == 'installing') {
      // Complete only the already journaled working publication, while closed.
      await install(game, plan);
      r.addAll(await record(game, plan));
    }
    if (launched && !{'captured', 'finishing'}.contains(r['phase'])) {
      final loan = await roots.loan();
      if (loan == null ||
          loan['kind'] != 'game' ||
          loan['transaction'] != r['transaction'])
        throw StateError(
          'The PSP game memory-stick handoff is missing. Recovery was kept.',
        );
      final selection = await manager.channel.invokeMapMethod<String, dynamic>(
        'rootPspSelection',
        roots.arguments(loan),
      );
      if (selection?['selection'] != 'profile' ||
          selection?['sha256'] != loan['selected'])
        throw StateError(
          'PPSSPP’s selected memory stick changed during play. Nothing was adopted.',
        );
      final files = await list(r, plan), working = r['working'] as Map;
      if (working.keys
          .where((p) => plan.key(p as String) != null)
          .any((p) => !files.containsKey(p)))
        throw StateError(
          'An installed PSP save or state is missing. Recovery was kept.',
        );
      final capture = await hold(r, plan, files),
          snapshot = await seal(game, plan, r, files, capture);
      final store = cloud.store(game);
      var state = await store.state();
      if (state['active'] != true)
        state = {
          ...state,
          'active': true,
          'stateBefore': await store.stateFiles(),
        };
      await store.restore(snapshot, state);
      r.addAll({'phase': 'captured', 'captured': files});
      await progressWrite(journal, r);
    }
    if (r['phase'] == 'captured') {
      // Capture/restore the sealed snapshot is idempotent after a lost reply.
      await cloud.afterPlay(game, exit == AndroidPspState.closed ? 0 : 1);
      r['phase'] = 'finishing';
      await progressWrite(journal, r);
    } else if (!launched) {
      // No activity launch was attempted. Clearing our own preparation is not
      // an emulator crash, and must neither upload a cancelled source choice
      // nor manufacture an unclean-exit conflict on the next Play.
      final store = cloud.store(game), state = await cloud.store(game).state();
      if (state['active'] == true)
        await store.save({
          ...state,
          'active': false,
          if (r['cloudPrepared'] != true) 'unclean': true,
        });
    }
    final profile = await roots.profile(
      game.server,
      game.profile,
      plan.binding,
    );
    await roots.backup(profile);
    if (r['captured'] != null) {
      if (!pspInventorySame(
        r['captured'] as Map,
        await list(r, plan),
        metadata: false,
      )) {
        // A reopened native app can produce a newer closed copy while an
        // earlier upload/backup is retried. Keep the loan until it is sealed.
        r['phase'] = 'launched';
        await progressWrite(journal, r);
        throw StateError(
          'PPSSPP saves changed after capture. The newer copy was kept; retry to synchronize it after Exit.',
        );
      }
      final local = await cloud.store(game).capture();
      await progressWrite(await baseline(game, plan), {
        'version': 1,
        'server': game.server,
        'profile': game.profile,
        'discId': plan.game,
        'discVersion': plan.version,
        'stateGroup': plan.stateGroup,
        'ownerNonce': r['ownerNonce'],
        'files': r['captured'],
        'local': local.entries,
        'static': {
          for (final e in (r['working'] as Map).entries)
            if (plan.key(e.key as String) == null) e.key: e.value,
        },
      });
    }
    await roots.restoreLoan(transaction: r['transaction']);
    await progressWrite(
      await progressFile(await directory(r), 'completed.json'),
      r,
    );
    await journal.delete();
    // Private capture directories are retained for interrupted-session review;
    // they are not exported as another game or account's progress.
  }
}
