import 'dart:io';
import 'dart:convert';

import '../romm/client.dart';
import '../romm/models.dart';
import '../romm/transfer.dart';
import '../session_lease.dart';
import 'files.dart';
import 'layout.dart';
import 'store.dart';
import 'digest.dart';

enum ProgressChoice { device, cloud, cancel }

class ProgressConflict {
  const ProgressConflict(this.reason, this.local, this.remote);
  final String reason;
  final ProgressSnapshot local;
  final ProgressSnapshot? remote;
}

typedef ProgressResolver = Future<ProgressChoice> Function(ProgressConflict);

class CloudGame {
  const CloudGame({
    required this.server,
    required this.profile,
    required this.user,
    required this.rom,
    required this.client,
    required this.layout,
  });
  final String server, profile;
  final int user, rom;
  final RommClient client;
  final ProgressLayout layout;
}

/// Every entry point owns SessionLease, or is called by the session supervisor
/// while that same lease is held. No restore or upload can race a game writer.
class CloudSaves {
  CloudSaves(this.root, {required this.notice, this.phase});
  final Directory root;
  final void Function(String, bool) notice;
  final void Function(String)? phase;
  void Function(int) _bytes(String operation, int rom) {
    final clock = Stopwatch()..start();
    var last = -1000;
    return (bytes) {
      if (clock.elapsedMilliseconds - last < 1000) return;
      last = clock.elapsedMilliseconds;
      phase?.call(
        'ROM $rom: $operation, $bytes bytes after ${clock.elapsedMilliseconds} ms.',
      );
    };
  }

  bool _busy = false;
  DownloadCancellation? _transfer;
  ProgressStore store(CloudGame game) {
    if (![
          game.server,
          game.profile,
        ].every((v) => RegExp(r'^[a-f0-9]{32}$').hasMatch(v)) ||
        game.rom < 1 ||
        game.user < 1)
      throw const FormatException('Invalid cloud save account identity');
    if (!game.layout.root
        .replaceAll('\\', '/')
        .startsWith(
          '${root.path.replaceAll('\\', '/')}/profiles/${game.profile}/emulators/',
        ))
      throw const FileSystemException(
        'Cloud save storage does not belong to this profile',
      );
    return ProgressStore(
      Directory(
        '${root.path}/cloud-saves/${game.server}/${game.profile}/${game.rom}',
      ),
      game.layout,
      game.rom,
      game.user,
      ownerRoot: root,
    );
  }

  Future<T> idle<T>(Future<T> Function() work) async {
    if (_busy)
      throw StateError(
        'Cloud saves are busy. Finish the current save operation first.',
      );
    _busy = true;
    _transfer = DownloadCancellation();
    SessionLease? lease;
    try {
      lease = await SessionLease.acquire(root);
      return await work();
    } finally {
      await lease?.release();
      _busy = false;
      _transfer = null;
    }
  }

  void cancel() => _transfer?.cancel();
  Future<List<RommSave>> list(CloudGame g) async {
    _transfer?.check();
    if ((await g.client.currentUser()).id != g.user)
      throw const RommFailure(
        'The signed-in account changed. Saves were kept.',
      );
    final saves = await g.client.saves(g.rom);
    _transfer?.check();
    if (saves.any((s) => s.userId != g.user))
      throw const RommFailure(
        'RomM returned a save for a different account. Nothing was changed.',
      );
    return saves;
  }

  Future<RommSave?> _managed(CloudGame g) async {
    final all = await list(g);
    final versions = all.where((s) => s.versioned).toList();
    if (versions.map((s) => s.name).toSet().length != versions.length)
      throw const RommFailure(
        'RomM has duplicate BROOMM version filenames. Resolve them before syncing; progress was kept.',
      );
    DateTime time(RommSave s) {
      final tag = s.name.substring(8, 27);
      return DateTime.tryParse(s.created) ??
          DateTime.tryParse(
            '${tag.substring(0, 10)}T${tag.substring(11).replaceAll('-', ':')}Z',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    versions.sort((a, b) {
      final order = time(b).compareTo(time(a));
      return order == 0 ? b.id.compareTo(a.id) : order;
    });
    if (versions.isNotEmpty) return versions.first;
    // Read-only migration fallback. New writes always append to BROOMM; never
    // rename, overwrite or delete the old single-file asset or another slot.
    final found = all.where((s) => s.legacyManaged).toList();
    if (found.length > 1)
      throw const RommFailure(
        'More than one managed broomm save exists. Resolve the duplicates in RomM before syncing.',
      );
    return found.firstOrNull;
  }

  void _owned(CloudGame g, RommSave s, {bool managed = true}) {
    if (s.romId != g.rom || s.userId != g.user || (managed && !s.managed))
      throw const RommFailure(
        'The destination save identity changed. No other save was modified.',
      );
  }

  Future<ProgressSnapshot> _download(
    CloudGame g,
    RommSave save, {
    bool native = false,
  }) async {
    _owned(g, save, managed: !native && !save.stateAsset);
    final st = store(g);
    await progressDirectory(st.directory);
    final tmp = await st.directory.createTemp('.download-');
    final cancel = _transfer ??= DownloadCancellation();
    try {
      final file = File('${tmp.path}/broomm');
      phase?.call(
        'ROM ${g.rom}: downloading save ${save.id}, ${save.bytes} bytes.',
      );
      await (save.stateAsset ? g.client.downloadState : g.client.downloadSave)(
        save,
        file,
        cancellation: cancel,
        onProgress: _bytes('save download', g.rom),
      );
      final latest = await (save.stateAsset
          ? g.client.state(save.id)
          : g.client.save(save.id));
      if (latest.revision != save.revision)
        throw const RommFailure(
          'The remote save changed during transfer. Retry; local progress was kept.',
        );
      try {
        final result = await st.importBundle(file, expectedHash: save.hash);
        cancel.check();
        return result;
      } on NotProgressBundle {
        if (!native && !save.versioned) rethrow;
        final commit = ProgressDigest.md5()
          ..add(utf8.encode('${g.server}:${g.rom}:${g.user}:${save.revision}'));
        final result = await st.importNative(
          file,
          expectedHash: save.hash,
          remoteCommit: commit.finish(),
        );
        cancel.check();
        if (save.versioned) {
          final companion = await _stateCompanion(g, save);
          if (companion != null) {
            final states = await _download(g, companion);
            if (states.ordinaryDigest != result.ordinaryDigest)
              throw const RommFailure(
                'The save and its state archive do not match. Local progress was kept.',
              );
            return states;
          }
        }
        return result;
      }
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  String _stateName(RommSave save) =>
      save.name.replaceFirst(RegExp(r'\.[^.]+$'), '.zip');
  Future<RommSave?> _stateCompanion(CloudGame g, RommSave save) async {
    final all = await g.client.states(g.rom);
    if (all.any((s) => s.userId != g.user))
      throw const RommFailure(
        'RomM returned states for another account. Progress was kept.',
      );
    final found = all
        .where((s) => s.emulator == 'Broomm' && s.name == _stateName(save))
        .toList();
    if (found.length > 1)
      throw const RommFailure(
        'This Broomm version has conflicting state archives. Progress was kept.',
      );
    return found.firstOrNull;
  }

  Future<ProgressSnapshot> _finishVersion(
    CloudGame g,
    ProgressSnapshot local,
    RommSave result,
  ) async {
    final cancel = _transfer ??= DownloadCancellation();
    if (local.hasStates &&
        local.entries.keys.any((k) => !k.startsWith('states-'))) {
      var states = await _stateCompanion(g, result);
      if (states == null) {
        states = await g.client.uploadState(
          g.rom,
          local.bundle,
          name: _stateName(result),
          cancellation: cancel,
          onProgress: _bytes('state archive upload', g.rom),
        );
        _owned(g, states, managed: false);
        if (!states.stateAsset ||
            states.name != _stateName(result) ||
            states.emulator != 'Broomm')
          throw const RommFailure(
            'RomM changed the state archive identity. Progress was kept.',
          );
      }
      final verified = await _download(g, states);
      if (verified.digest != local.digest || verified.id != local.id)
        throw const RommFailure(
          'The state archive did not match this version. Recovery copies were kept.',
        );
    }
    final readback = await _download(g, result);
    if (readback.digest != local.digest ||
        (!readback.nativeRemote && readback.id != local.id))
      throw const RommFailure(
        'The cloud version did not match the uploaded progress. Recovery copies were kept.',
      );
    return readback;
  }

  Map<String, dynamic> _ack(
    ProgressStore st,
    ProgressSnapshot s,
    RommSave remote, {
    ProgressSnapshot? pendingLocal,
    bool unclean = false,
  }) => {
    'baseline': s.digest,
    'commit': s.id,
    'snapshot': st.storageId(s),
    'remote': remote.id,
    'synced': DateTime.now().toUtc().toIso8601String(),
    'pending':
        unclean || pendingLocal != null && pendingLocal.digest != s.digest,
    if (unclean) 'unclean': true,
    if (pendingLocal != null && pendingLocal.digest != s.digest)
      'local': st.storageId(pendingLocal),
    'stateKnown': {
      for (final e in s.entries.entries)
        if (e.key.startsWith('states-')) e.key: e.value['sha256'],
      if (pendingLocal != null)
        for (final e in pendingLocal.entries.entries)
          if (e.key.startsWith('states-')) e.key: e.value['sha256'],
    },
  };
  Future<void> _upload(
    CloudGame g,
    ProgressSnapshot local,
    RommSave? remote,
    ProgressSnapshot? previous,
  ) async {
    final st = store(g), old = await st.state();
    await st.save({
      ...old,
      'pending': true,
      'upload': st.storageId(local),
      'expected': remote?.revision,
    });
    final latest = await _managed(g);
    if (latest?.revision != remote?.revision)
      throw const RommFailure(
        'The managed cloud save changed before upload. Progress was kept; retry to resolve it.',
      );
    if (latest != null) {
      final verify = await _download(g, latest);
      if (verify.digest != previous?.digest || verify.id != previous?.id)
        throw const RommFailure(
          'The managed cloud save changed before upload. Progress was kept.',
        );
    }
    final cancel = _transfer ??= DownloadCancellation();
    final exported = await st.exportNative(local);
    try {
      final result = await g.client.uploadSave(
        g.rom,
        exported.file,
        name: 'Broomm.${exported.extension}',
        slot: 'BROOMM',
        cancellation: cancel,
        onProgress: _bytes('managed save upload', g.rom),
      );
      _owned(g, result);
      if (!result.versioned || !result.name.endsWith('.${exported.extension}'))
        throw const RommFailure(
          'RomM did not create the requested BROOMM slot version with its native extension. Recovery copies were kept.',
        );
      await st.save({
        ...await st.state(),
        'uploadRemote': result.id,
        'uploadName': result.name,
      });
      final readback = await _finishVersion(g, local, result);
      if ((await _managed(g))?.id != result.id)
        throw const RommFailure(
          'Another BROOMM version arrived during synchronization. Both versions were kept; retry to review the latest progress.',
        );
      await st.save(_ack(st, readback, result));
      await _prune(st);
      notice('Progress saved as ${result.name} in BROOMM.', false);
    } finally {
      await exported.close();
    }
  }

  Future<ProgressSnapshot> _local(
    ProgressStore st,
    Map<String, dynamic> state,
  ) async {
    final retained = state['snapshot'] is String
        ? await st.load(state['snapshot'] as String)
        : null;
    final snap = await st.capture(
      knownStates: (state['stateKnown'] as Map? ?? {}).cast<String, String>(),
      parents: retained == null ? [] : [retained.id, ...retained.parents],
      retained: retained,
    );
    final primary = snap.entries.keys.where((k) => !k.startsWith('states-'));
    if (retained != null &&
        retained.entries.keys.any((k) => !k.startsWith('states-')) &&
        primary.isEmpty)
      throw const FileSystemException(
        'Previously recorded game saves are missing. Recovery copies were kept. Use an existing save explicitly to restore them.',
      );
    for (final key in ['local', 'snapshot']) {
      if (state[key] is! String) continue;
      final existing = state[key] == state['snapshot'] && retained != null
          ? retained
          : await st.load(state[key] as String);
      if (existing.digest == snap.digest) {
        await snap.directory.delete(recursive: true);
        return existing;
      }
    }
    return snap;
  }

  Future<void> sync(CloudGame g, {ProgressResolver? resolve}) async {
    final clock = Stopwatch()..start();
    phase?.call('ROM ${g.rom}: inspecting local progress and recovery.');
    final st = store(g);
    await progressDirectory(st.directory);
    await st.recover();
    final state = await st.state();
    final local = await _local(st, state);
    phase?.call(
      'ROM ${g.rom}: local snapshot verified in ${clock.elapsedMilliseconds} ms; checking managed remote progress.',
    );
    await st.save({
      ...state,
      'local': st.storageId(local),
      'pending': state['baseline'] != local.digest,
    });
    final remoteRecord = await _managed(g);
    if (state['uploadRemote'] == remoteRecord?.id &&
        remoteRecord?.versioned == true &&
        state['upload'] is String) {
      final pending = await st.load(state['upload'] as String);
      final verified = await _finishVersion(g, pending, remoteRecord!);
      if ((await _managed(g))?.id != remoteRecord.id)
        throw const RommFailure(
          'Another cloud version arrived. Both versions were kept.',
        );
      await st.save(
        _ack(
          st,
          verified,
          remoteRecord,
          pendingLocal: local,
          unclean: state['unclean'] == true,
        ),
      );
      await _prune(st);
      if (local.digest != pending.digest) await sync(g, resolve: resolve);
      return;
    }
    final remote = remoteRecord == null
        ? null
        : await _download(g, remoteRecord);
    if (remote != null &&
        remote.digest == local.digest &&
        state['unclean'] != true) {
      if (remoteRecord!.legacyManaged && !local.empty) {
        await _upload(g, local, remoteRecord, remote);
        return;
      }
      await st.save(_ack(st, remote, remoteRecord));
      await _prune(st);
      return;
    }
    final baseline = state['baseline'];
    final diverged =
        remote != null &&
        !remote.nativeRemote &&
        state['commit'] != null &&
        remote.id != state['commit'] &&
        !remote.parents.contains(state['commit']) &&
        remote.digest != baseline;
    if (state['unclean'] != true &&
        remote != null &&
        !diverged &&
        ((baseline == null && local.empty) ||
            (baseline != null && local.digest == baseline))) {
      final protected = await st.restore(
        remote,
        _ack(st, remote, remoteRecord!),
        knownStates: (state['stateKnown'] as Map? ?? {}).cast<String, String>(),
      );
      await _prune(st);
      if (remoteRecord.legacyManaged && !remote.empty)
        await _upload(g, remote, remoteRecord, remote);
      notice(
        protected == 0 ? 'Latest BROOMM progress is ready on this device.' : 'Game progress is ready. Existing states with unknown build history were left untouched; cloud states remain available through Use existing save file.',
        false,
      );
      return;
    }
    if (state['unclean'] != true &&
        ((remote == null && baseline == null) ||
            (remote != null && remote.digest == baseline))) {
      if (local.empty) {
        await st.save({
          ...await st.state(),
          'pending': false,
          'emptySynced': true,
          'synced': DateTime.now().toUtc().toIso8601String(),
        });
        return;
      }
      await _upload(g, local, remoteRecord, remote);
      return;
    }
    final reason = state['unclean'] == true
        ? 'The emulator did not close normally. Review the retained device progress before replacing the cloud save.'
        : remote == null
        ? 'The previously synced BROOMM progress was removed or renamed in RomM.'
        : baseline == null
        ? 'Both this device and RomM already have progress. Choose which one to use.'
        : 'Progress changed on another device. Both versions have been kept.';
    await st.save({
      ...await st.state(),
      'pending': true,
      'conflict': {
        'local': st.storageId(local),
        'remote': remote == null ? null : st.storageId(remote),
      },
    });
    final choice =
        await resolve?.call(ProgressConflict(reason, local, remote)) ??
        ProgressChoice.cancel;
    if (choice == ProgressChoice.cloud && remote != null) {
      await st.restore(remote, _ack(st, remote, remoteRecord!));
      await _prune(st);
      notice(
        'Using the selected cloud progress. The previous device copy was kept for recovery.',
        false,
      );
    } else if (choice == ProgressChoice.device) {
      final chosen = await st.capture(
        parents: [
          local.id,
          if (remote != null) remote.id,
          ...local.parents,
          if (remote != null) ...remote.parents,
        ],
        retained: local,
        knownStates: (state['stateKnown'] as Map? ?? {}).cast<String, String>(),
      );
      await _upload(g, chosen, remoteRecord, remote);
    } else {
      throw const RommFailure(
        'Cloud save conflict needs a choice. Both versions were kept.',
      );
    }
  }

  Future<void> beforePlay(CloudGame g, {ProgressResolver? resolve}) async {
    _transfer = DownloadCancellation();
    final st = store(g);
    // A retained active marker is evidence of an interrupted writer, even if
    // its PID was reused. SessionLease has already checked the native writer lock.
    final state = await st.state();
    if (state['active'] == true)
      await st.save({...state, 'unclean': true, 'active': false});
    try {
      await sync(g, resolve: resolve);
    } on RommFailure catch (e) {
      if (e is DownloadCancelled) rethrow;
      if ((await st.state())['conflict'] != null ||
          e.status != null && ![401, 403].contains(e.status))
        rethrow;
      notice(
        '${e.message} Progress remains on this device; cloud sync is pending.',
        true,
      );
    } on SocketException {
      notice(
        'RomM is offline. Progress stays on this device and will sync when connected.',
        true,
      );
    }
    await st.save({
      ...await st.state(),
      'active': true,
      'stateBefore': await st.stateFiles(),
    });
  }

  Future<void> _prune(ProgressStore store) async {
    try {
      await store.pruneConfirmed();
    } catch (_) {
      notice(
        'Progress synced, but older local recovery copies could not be cleaned up. They have been kept.',
        true,
      );
    }
  }

  /// Retry immutable pending progress even after its ROM was uninstalled. This
  /// path deliberately has no native restore boundary and never reads ROMs.
  Future<void> retryPending({
    required String server,
    required String profile,
    required int user,
    required int rom,
    required RommClient client,
  }) async {
    if (![
          server,
          profile,
        ].every((v) => RegExp(r'^[a-f0-9]{32}$').hasMatch(v)) ||
        rom < 1)
      throw const FormatException('Invalid pending progress identity');
    final relative = 'cloud-saves/$server/$profile/$rom';
    final stateFile = await progressFile(root, '$relative/state.json');
    final state = await progressJson(stateFile);
    if (state['active'] == true)
      await progressWrite(stateFile, {
        ...state,
        'unclean': true,
        'active': false,
      });
    if (state['active'] == true || state['unclean'] == true)
      throw const RommFailure(
        'An interrupted session needs review in the game’s Cloud saves menu. Local files were kept.',
      );
    if (state['pending'] != true || state['conflict'] != null) return;
    final id = state['local'];
    if (id is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id))
      throw const FormatException('The pending recovery snapshot is missing');
    final manifest = await progressJson(
      await progressFile(root, '$relative/snapshots/$id/manifest.json'),
    );
    final identity = manifest['identity'];
    if (identity is! String ||
        !RegExp(r'^[a-z0-9_-]+:[a-zA-Z0-9_-]+$').hasMatch(identity) ||
        manifest['files'] is! Map)
      throw const FormatException(
        'The pending recovery snapshot has an invalid game identity',
      );
    final groups = (manifest['files'] as Map).keys
        .map((k) => (k as String).split('/').first)
        .toSet();
    if (groups.any(
      (g) => !RegExp(
        r'^(save|device|card[AB]|ext-[a-f0-9]{8}|dlc-[a-f0-9]{8}|states-[a-f0-9]{16}-[a-z]+-[a-z0-9]+)$',
      ).hasMatch(g),
    ))
      throw const FormatException('Unsupported pending save area');
    final ordinary = (manifest['files'] as Map).keys
        .cast<String>()
        .where((k) => !k.startsWith('states-'))
        .toList();
    final layout = ProgressLayout(
      '${root.path}/profiles/$profile/emulators/retained',
      identity.split(':').first,
      identity.split(':').last,
      [],
      archiveOnly: true,
      rawSave:
          identity.startsWith('libretro-') &&
              ![
                'libretro-flycast-v1',
                'libretro-fbneo-v1',
                'libretro-mednafen_saturn-v1',
              ].contains(identity.split(':').first) &&
              ordinary.length == 1 &&
              ordinary.single.startsWith('save/') &&
              ordinary.single.endsWith('.srm')
          ? ordinary.single
          : null,
    );
    final game = CloudGame(
      server: server,
      profile: profile,
      user: user,
      rom: rom,
      client: client,
      layout: layout,
    );
    final st = store(game);
    final local = await st.load(id);
    final record = await _managed(game);
    final remote = record == null ? null : await _download(game, record);
    if (state['uploadRemote'] == record?.id &&
        record?.versioned == true &&
        state['upload'] is String) {
      final pending = await st.load(state['upload'] as String);
      final verified = await _finishVersion(game, pending, record!);
      if ((await _managed(game))?.id != record.id)
        throw const RommFailure(
          'Another cloud version arrived. Both versions were kept.',
        );
      await st.save(_ack(st, verified, record, pendingLocal: local));
      await _prune(st);
      if (pending.digest != local.digest) {
        await retryPending(
          server: server,
          profile: profile,
          user: user,
          rom: rom,
          client: client,
        );
      }
    } else if (remote?.digest == local.digest) {
      await st.save(_ack(st, remote!, record!));
      await _prune(st);
    } else if ((remote == null && state['baseline'] == null) ||
        remote != null && remote.digest == state['baseline']) {
      await _upload(game, local, record, remote);
    } else if (local.digest == state['baseline'] &&
        remote != null &&
        remote.parents.contains(state['commit'])) {
      // Keep the old native baseline until a verified adapter restores the
      // remote change before gameplay; there is no local edit to upload.
      await st.save({...state, 'pending': false});
    } else {
      await st.save({
        ...state,
        'pending': true,
        'conflict': {
          'local': st.storageId(local),
          'remote': remote == null ? null : st.storageId(remote),
        },
      });
      throw const RommFailure(
        'Progress changed on another device. Open this game’s Cloud saves menu to choose; both copies were kept.',
      );
    }
  }

  Future<void> afterPlay(CloudGame g, int exit) async {
    _transfer = DownloadCancellation();
    final writer = await File('${root.path}/writer.lock')
        .open(mode: FileMode.append);
    try {
      await writer.lock(FileLock.exclusive);
    } catch (_) {
      await writer.close();
      throw StateError(
        'The emulator still owns its save files. Sync will wait for it to close.',
      );
    }
    try {
      final st = store(g);
      var state = await st.state();
      final known = (state['stateKnown'] as Map? ?? {}).cast<String, String>();
      if (state['active'] == true) {
        final before = (state['stateBefore'] as Map? ?? {})
            .cast<String, String>();
        for (final e in (await st.stateFiles()).entries) {
          if (before[e.key] != e.value) known[e.key] = e.value;
        }
      }
      state = {...state, 'stateKnown': known};
      final local = await _local(st, state);
      await st.save({
        ...state,
        'local': st.storageId(local),
        'pending': true,
        'active': false,
        'unclean': exit != 0,
      });
      if (exit != 0) {
        notice(
          'The emulator exited unexpectedly. Progress was kept locally; review cloud saves before syncing.',
          true,
        );
        return;
      }
      try {
        await sync(g);
      } catch (e) {
        notice('Progress kept on this device. ${progressFailure(e)}', true);
      }
    } finally {
      await writer.close();
    }
  }

  Future<void> useExisting(CloudGame g, RommSave selected) async {
    _owned(g, selected, managed: false);
    final st = store(g);
    await progressDirectory(st.directory);
    await st.recover();
    final remoteRecord = await _managed(g);
    final previous = remoteRecord == null
        ? null
        : await _download(g, remoteRecord);
    final chosen = await _download(g, selected, native: true);
    // Re-seal under a fresh commit with both the previous cloud and selected
    // version as parents. Source assets are read only throughout this operation.
    await st.restore(chosen, {
      ...await st.state(),
      'pending': true,
      'unclean': false,
    });
    final local = await st.capture(
      parents: [
        if (previous != null) previous.id,
        chosen.id,
        if (previous != null) ...previous.parents,
        ...chosen.parents,
      ],
      retained: chosen,
    );
    await _upload(g, local, remoteRecord, previous);
    notice(
      'Selected save copied into a new BROOMM version. The source save was kept.',
      false,
    );
  }

  Future<void> backup(CloudGame g, String name) async {
    name = name.trim();
    progressRelative(name);
    if (name.contains('/') ||
        name.toLowerCase() == 'broomm' ||
        name.startsWith('.broomm-'))
      throw const FormatException('Choose a backup name other than broomm.');
    final st = store(g);
    await progressDirectory(st.directory);
    await st.recover();
    final saves = await list(g);
    final checkpoint = File('${st.directory.path}/backup.json');
    final pending = await progressExists(checkpoint.path)
        ? await progressJson(checkpoint)
        : null;
    final local = pending == null
        ? await _local(st, await st.state())
        : await st.load(pending['snapshot'] as String);
    if (local.empty)
      throw const RommFailure(
        'Play and save the game before creating a backup.',
      );
    final legacyPending =
        pending != null &&
        !(pending['staging'] as String).contains(RegExp(r'\.(sav|srm|zip)$'));
    final exported = local.hasStates || legacyPending
        ? NativeProgressExport(local.bundle, 'zip', includesStates: true)
        : await st.exportNative(local);
    try {
      name = name.replaceFirst(
        RegExp(r'\.(sav|srm|zip)$', caseSensitive: false),
        '',
      );
      name = '$name.${exported.extension}';
      // The unique staging name prevents POST's filename-upsert behavior from
      // replacing an existing user save. Rename performs RomM's collision check.
      final tempName =
          pending?['staging'] as String? ??
          '.broomm-backup-${progressNonce()}.${exported.extension}';
      if (!RegExp(r'^\.broomm-backup-[a-f0-9]{32}(\.(sav|srm|zip))?$')
          .hasMatch(tempName))
        throw const FormatException(
          'The interrupted backup record is invalid. Its local copy has been kept.',
        );
      RommSave? created;
      if (pending != null) {
        final candidates = saves
            .where((s) => s.id == pending['remote'] || s.name == tempName)
            .toList();
        if (candidates.length > 1)
          throw const RommFailure(
            'Conflicting interrupted backup identities. Existing saves were kept.',
          );
        created = candidates.firstOrNull;
        if (created != null &&
            (created.emulator != 'Broomm' ||
                created.name != tempName && created.name != pending['name']))
          throw const RommFailure(
            'The interrupted backup was renamed elsewhere. No save was replaced.',
          );
      }
      if (saves.any(
        (s) =>
            s.name.toLowerCase() == name.toLowerCase() && s.id != created?.id,
      ))
        throw const RommFailure(
          'A save with this name already exists. Choose another name; existing saves are never replaced by Backup.',
        );
      await progressWrite(checkpoint, {
        'staging': tempName,
        'name': name,
        'snapshot': st.storageId(local),
        if (created != null) 'remote': created.id,
      });
      final cancel = _transfer ??= DownloadCancellation();
      created ??= await g.client.uploadSave(
        g.rom,
        exported.file,
        name: tempName,
        cancellation: cancel,
        onProgress: _bytes('explicit backup upload', g.rom),
      );
      _owned(g, created, managed: false);
      await progressWrite(checkpoint, {
        'staging': tempName,
        'name': name,
        'snapshot': st.storageId(local),
        'remote': created.id,
      });
      final verified = await _download(g, created, native: true);
      if (verified.digest != local.digest ||
          (!verified.nativeRemote && verified.id != local.id))
        throw const RommFailure(
          'The backup failed readback. Recovery copies were kept.',
        );
      final renamed = created.name == name
          ? created
          : await g.client.renameSave(created, name);
      _owned(g, renamed, managed: false);
      if (renamed.id != created.id || renamed.name != name)
        throw const RommFailure('RomM did not confirm the backup filename.');
      await checkpoint.delete();
      notice(
        'Backup “$name” created in RomM. Automatic sync uses only the BROOMM slot.',
        false,
      );
    } finally {
      await exported.close();
    }
  }
}

String progressFailure(Object error) => error is DownloadCancelled
    ? 'Save transfer cancelled. Local progress and recovery copies were kept.'
    : error is RommFailure
    ? error.message
    : error is FormatException
    ? error.message
    : error is FileSystemException
    ? error.message
    : error is UnsupportedError
    ? error.message ?? 'This save format is not supported.'
    : error is StateError
    ? '${error.message}'
    : 'Cloud saves could not finish. Retry from the game’s Options menu.';
