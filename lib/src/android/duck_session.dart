import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../progress/digest.dart';
import '../progress/files.dart';
import '../progress/layout.dart';
import '../progress/service.dart';
import '../progress/store.dart';
import '../romm/transfer.dart';
import 'emulators.dart';
import 'duck_root.dart';
import 'duck_root_store.dart';
import 'save_plan.dart';
import 'duck_states.dart';
import '../playstation.dart';

/// Concrete PS1 session transaction. Native code provides bounded file effects;
/// ownership, reconciliation, launch checkpoints and recovery remain in Dart.
class AndroidDuckSession {
  AndroidDuckSession(this.manager, this.cloud, {this.check, this.cancellation});
  final AndroidEmulators manager;
  final CloudSaves cloud;
  final void Function()? check;
  final DownloadCancellation? Function()? cancellation;
  late final roots = AndroidDuckRootStore(manager, check: check);
  File get journal => File('${manager.data.path}/android/duck-swap.json');
  Future<bool> get pending => progressExists(journal.path);
  final _nonce = RegExp(r'^[a-f0-9]{32}$');
  Future<void> validate(AndroidDuckPlan plan, String key, File file) async {
    if (key.startsWith('save/')) {
      if (!await isPlayStationMemoryCard(file, ps2: false))
        throw const FormatException(
          'Incomplete native whole PS1 card. Progress was kept.',
        );
    } else if (key.startsWith('${plan.stateGroup}/')) {
      await validateAndroidDuckState(file, plan.publication);
    } else {
      throw const FormatException('PS1 progress is outside its game/build.');
    }
  }

  Future<Map<String, dynamic>> record(
    CloudGame game,
    AndroidDuckPlan plan,
  ) async {
    final r = await progressJson(
      await progressFile(manager.data, 'android/duck-swap.json'),
    );
    if (r['version'] != 1 ||
        r['emulator'] != 'duckstation' ||
        r['server'] != game.server ||
        r['profile'] != game.profile ||
        r['rom'] != game.rom ||
        r['user'] != game.user ||
        r['game'] != plan.game ||
        r['publication'] != plan.publication ||
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
        'The PS1 recovery belongs to another game, profile or installation. All copies were kept.',
      );
    return r;
  }

  Map<String, dynamic> arguments(Map r, AndroidDuckPlan plan) => {
    ...plan.arguments,
    'server': r['server'],
    'profile': r['profile'],
    'ownerNonce': r['ownerNonce'],
  };
  Future<Directory> directory(Map r) async {
    final nonce = r['transaction'] as String;
    if (!_nonce.hasMatch(nonce))
      throw const FormatException('Invalid PS1 transaction.');
    return (await progressFile(
      manager.data,
      'android/shared-session/$nonce/.probe',
      createParents: true,
    )).parent;
  }

  Future<File> baseline(CloudGame game, AndroidDuckPlan plan) => progressFile(
    Directory(plan.root),
    'root-games/${plan.game}-${plan.publication}.json',
    createParents: true,
  );
  Future<Map<String, dynamic>> list(Map r, AndroidDuckPlan plan) =>
      readAndroidDuckInventory(
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
        'Private PS1 source is missing or damaged. Recovery was kept.',
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
        'Private PS1 copy was not verified. Recovery was kept.',
      );
  }

  Future<String> hold(
    Map<String, dynamic> r,
    AndroidDuckPlan plan,
    Map<String, dynamic> files,
  ) async {
    final retained = List<dynamic>.from(r['captures'] as List? ?? []);
    if (retained.length >= 8)
      throw StateError(
        'Several incomplete PS1 captures were kept. Review recovery before retrying.',
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
      await manager.channel.invokeMethod<void>('rootDuckRead', {
        ...arguments(r, plan),
        'path': e.key,
        ...e.value as Map,
        'target': target.path,
      });
      if (await target.length() != e.value['bytes'] ||
          await progressFileHash(target) != e.value['sha256'])
        throw const FileSystemException(
          'PS1 save capture was not verified. Native progress was kept.',
        );
    }
    if (!duckInventorySame(files, await list(r, plan)))
      throw StateError(
        'PS1 saves changed during capture. The private copies were kept.',
      );
    return name;
  }

  Future<ProgressSnapshot> seal(
    CloudGame game,
    AndroidDuckPlan plan,
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
        throw const FormatException('PS1 capture includes unrelated data.');
      final source = await progressFile(base, '$capture/${e.key}');
      await validate(plan, key, source);
      await copy(source, await layout.target(key), e.value as Map);
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
    AndroidDuckPlan plan, {
    ProgressResolver? resolve,
  }) async {
    if (await pending)
      throw StateError('Finish the previous PS1 transaction first.');
    await roots.restoreSettingsLoan();
    final profile = await roots.profile(
      game.server,
      game.profile,
      plan.binding,
    );
    await roots.ensureFirmware(
      profile,
      plan.platformId,
      game.client,
      cancellation?.call() ?? DownloadCancellation(),
    );
    await roots.backup(profile);
    final r = <String, dynamic>{
      'version': 1,
      'emulator': 'duckstation',
      'package': plan.binding['package'],
      'rooted': true,
      'rootPlatform': 'psx',
      'server': game.server,
      'profile': game.profile,
      'rom': game.rom,
      'user': game.user,
      'game': plan.game,
      'publication': plan.publication,
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
        'android/duck-swap.json',
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
          known['game'] != plan.game ||
          known['publication'] != plan.publication ||
          known['files'] is! Map ||
          known['local'] is! Map)
        throw const FormatException(
          'PS1 reconciliation baseline is damaged. All copies were kept.',
        );
      if (known['ownerNonce'] != profile['ownerNonce'])
        known = null; // Fresh, explicitly restored installation generation.
    }
    final compatible = known == null || known['stateGroup'] == plan.stateGroup;
    final reconciled = <String, dynamic>{
      for (final e in native.entries)
        if (compatible || e.key.endsWith('.mcd')) e.key: e.value,
    };
    final knownFiles = <String, dynamic>{
      for (final e in (known?['files'] as Map? ?? {}).entries)
        if (compatible || (e.key as String).endsWith('.mcd'))
          e.key as String: e.value,
    };
    final nativeChanged = known == null
        ? reconciled.isNotEmpty
        : !duckInventorySame(knownFiles, reconciled, metadata: false);
    if (known != null &&
        (known['files'] as Map).keys.any((p) => !native.containsKey(p)))
      throw StateError(
        'A known PS1 save or state is missing. Restore it before synchronizing. Recovery was kept.',
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
          : !duckInventorySame(
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
                  'Broomm and this profile’s private DuckStation workspace both changed. Choose which progress to use before cloud synchronization.',
                  local,
                  held,
                  localLabel: 'Broomm',
                  remoteLabel: 'DuckStation',
                ),
              );
        if (choice == ProgressChoice.cancel)
          throw StateError(
            'PS1 progress choice was cancelled. Both copies were kept.',
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

  Future<void> replay(Map<String, dynamic> r, AndroidDuckPlan plan) async {
    check?.call();
    final operation = r['pending'] as Map?;
    if (operation == null) return;
    final path = operation['path'] as String;
    if (plan.key(path) == null)
      throw const FormatException('PS1 publication is outside this game.');
    final source = operation['after'] == null
        ? null
        : await progressFile(await directory(r), 'working/$path');
    if (source != null &&
        (await source.length() != (r['working'] as Map)[path]['bytes'] ||
            await progressFileHash(source) != operation['after']))
      throw const FileSystemException(
        'Pending PS1 publication source is damaged. Recovery was kept.',
      );
    await manager.channel.invokeMethod<Object?>('rootDuckReplace', {
      ...arguments(r, plan),
      ...operation,
      if (source != null) 'source': source.path,
    });
    (r['done'] as List).add(path);
    r['pending'] = null;
    await progressWrite(journal, r);
  }

  Future<void> cloudPrepared(CloudGame game, AndroidDuckPlan plan) async {
    final r = await record(game, plan);
    r['cloudPrepared'] = true;
    await progressWrite(journal, r);
  }

  Future<void> install(CloudGame game, AndroidDuckPlan plan) async {
    final r = await record(game, plan);
    if (r['phase'] == 'reconciled') {
      final snapshot = await cloud.store(game).capture(),
          base = await directory(r);
      final working = <String, dynamic>{};
      for (final e in snapshot.entries.entries) {
        if (!plan.areas.any((a) => e.key.startsWith('${a.id}/'))) continue;
        final path = plan.nativePath(e.key);
        await validate(
          plan,
          e.key,
          await progressFile(
            Directory('${snapshot.directory.path}/files'),
            e.key,
          ),
        );
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
      r.addAll({'working': working, 'done': <String>[], 'phase': 'installing'});
      await progressWrite(journal, r);
    }
    if (r['phase'] != 'installing')
      throw StateError('PS1 preparation is incomplete. Finish recovery first.');
    await replay(r, plan);
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
    if (!duckInventorySame(await list(r, plan), working, metadata: false))
      throw StateError(
        'PS1 working progress was not confirmed. Recovery was kept.',
      );
    r['phase'] = 'installed';
    await progressWrite(journal, r);
    final profile = await roots.profile(
      game.server,
      game.profile,
      plan.binding,
    );
    await roots.borrow(
      profile,
      kind: 'game',
      transaction: r['transaction'],
      plan: plan,
    );
  }

  Future<int> launching(CloudGame game, AndroidDuckPlan plan) async {
    final r = await record(game, plan),
        clock = await roots.ensureClosed(plan.binding);
    if (r['phase'] != 'installed')
      throw StateError('PS1 working workspace is not ready.');
    r.addAll({'phase': 'launching', 'launchElapsed': clock});
    await progressWrite(
      journal,
      r,
    ); // A lost activity-launch reply is still a possible writer.
    return clock;
  }

  Future<void> identify(CloudGame game, AndroidDuckPlan plan, int clock) async {
    final r = await record(game, plan);
    for (var attempt = 0; attempt < 40; attempt++) {
      final report = await readAndroidDuckState(
        manager,
        plan.binding,
        launchedAfter: clock,
      );
      if (report.process != null) {
        r.addAll({'process': report.process, 'phase': 'launched'});
        await progressWrite(journal, r);
        return;
      }
      if (attempt < 39)
        await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    cloud.phase?.call(
      'DuckStation process is not yet identified. Recovery was retained.',
    );
  }

  Future<AndroidDuckState> exitState(
    CloudGame game,
    AndroidDuckPlan plan,
  ) async {
    final r = await record(game, plan);
    if (r['normalClosed'] == true)
      return (await readAndroidDuckState(manager, plan.binding)).state ==
              AndroidDuckState.idle
          ? AndroidDuckState.closed
          : AndroidDuckState.unknown;
    final process = (r['process'] as Map?)?.cast<String, int>();
    if (process == null) return AndroidDuckState.unknown;
    final clock = Stopwatch()..start();
    var reported = false;
    var status = await readAndroidDuckState(
      manager,
      plan.binding,
      process: process,
    );
    while ({
          AndroidDuckState.menu,
          AndroidDuckState.settling,
        }.contains(status.state) &&
        status.process != null) {
      if (clock.elapsed >= const Duration(seconds: 2))
        return AndroidDuckState.unknown;
      if (!reported) {
        roots.phase('Waiting for the game to finish closing.');
        reported = true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      status = await readAndroidDuckState(
        manager,
        plan.binding,
        process: process,
      );
    }
    if (status.state == AndroidDuckState.quiescent) {
      await roots.ensureClosed(plan.binding, process: process);
      r['normalClosed'] = true;
      await progressWrite(journal, r);
      return AndroidDuckState.closed;
    }
    return status.state;
  }

  Future<void> finish(
    CloudGame game,
    AndroidDuckPlan plan, {
    required bool automatic,
  }) async {
    final r = await record(game, plan);
    final launched = {
      'launching',
      'launched',
      'captured',
      'finishing',
    }.contains(r['phase']);
    final exit = await exitState(game, plan);
    r.addAll(await record(game, plan));
    if (launched &&
        !{AndroidDuckState.closed, AndroidDuckState.interrupted}.contains(exit))
      throw StateError(
        'DuckStation closure could not be verified. Recovery was kept.',
      );
    await roots.ensureClosed(plan.binding);
    if (automatic && (exit != AndroidDuckState.closed || !launched))
      throw StateError(
        'DuckStation normal exit was not verified. Recovery was kept.',
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
          'The PS1 game settings handoff is missing. Recovery was kept.',
        );
      final config = await roots.report(plan.binding);
      final routes = (loan['routes'] as Map).cast<String, String>();
      final parsed = androidIni(utf8.decode(config['config'] as List<int>));
      if (routes.entries.any((e) => parsed[e.key] != e.value))
        throw StateError(
          'DuckStation changed its save routes. Native progress was kept.',
        );
      final files = await list(r, plan), working = r['working'] as Map;
      if (working.keys
          .where((p) => plan.key(p as String) != null)
          .any((p) => !files.containsKey(p)))
        throw StateError(
          'An installed PS1 save or state is missing. Recovery was kept.',
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
      await cloud.afterPlay(game, exit == AndroidDuckState.closed ? 0 : 1);
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
      if (!duckInventorySame(
        r['captured'] as Map,
        await list(r, plan),
        metadata: false,
      )) {
        // A reopened native app can produce a newer closed copy while an
        // earlier upload/backup is retried. Keep the loan until it is sealed.
        r['phase'] = 'launched';
        await progressWrite(journal, r);
        throw StateError(
          'DuckStation saves changed after capture. The newer copy was kept; retry to synchronize it after Exit.',
        );
      }
      final local = await cloud.store(game).capture();
      await progressWrite(await baseline(game, plan), {
        'version': 1,
        'server': game.server,
        'profile': game.profile,
        'game': plan.game,
        'publication': plan.publication,
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
