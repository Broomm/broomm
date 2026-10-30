import 'dart:io';

import 'package:flutter/foundation.dart';

import '../progress/files.dart';
import '../progress/service.dart';
import '../progress/layout.dart';
import '../session_lease.dart';
import 'emulators.dart';
import 'mmj_shared_saves.dart';
import 'save_plan.dart';
import 'shared_saves.dart';

/// A separate supervisor for external Android activities. Activity resume/result
/// is not writer-exit evidence. The owner explicitly confirms emulator closure.
/// A durable marker blocks new sessions after process/activity destruction.
class AndroidGameSession extends ChangeNotifier {
  AndroidGameSession(this.manager, this.cloud);
  final AndroidEmulators manager;
  final CloudSaves cloud;
  SessionLease? _lease;
  CloudGame? _game;
  bool _launched = false;
  bool busy = false, active = false, disposed = false;
  String phase = '', error = '';
  File get marker => File('${manager.data.path}/android/session.json');
  late final _mmj = MmjSharedSaves(manager, phase: cloud.phase);
  late final _shared = SharedAndroidSaves(manager, phase: cloud.phase);

  Future<Map<String, dynamic>?> pending() async {
    final Map<String, dynamic> value;
    if (await progressExists(marker.path)) {
      value = await progressJson(marker);
    } else {
      if (await _shared.pending) {
        value = await progressJson(_shared.journal);
      } else {
        if (!await _mmj.pending) return null;
        // A surviving swap receipt must still expose recovery if the general
        // session receipt is missing. Never mistake the shared folder for idle.
        value = {...await progressJson(_mmj.journal), 'emulator': 'citra-mmj'};
      }
    }
    if (value['version'] != 1 ||
        !RegExp(r'^[a-f0-9]{32}$')
            .hasMatch(value['profile'] as String? ?? '') ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['server'] as String? ?? '') ||
        value['rom'] is! int ||
        (value['rom'] as int) < 1 ||
        !androidEmulators.any((e) => e.id == value['emulator']))
      throw const FormatException(
        'Android session recovery record is invalid. Progress was kept.',
      );
    return value;
  }

  Future<void> start({
    required String server,
    required String profile,
    required int rom,
    required AndroidEmulator emulator,
    required AndroidApp app,
    required List<String> files,
    required String selected,
    String? core,
    CloudGame? game,
    ProgressResolver? resolve,
    Future<CloudGame?> Function()? prepare,
  }) async {
    if (![
          server,
          profile,
        ].every((v) => RegExp(r'^[a-f0-9]{32}$').hasMatch(v)) ||
        rom < 1)
      throw const FormatException('Invalid Android session identity');
    if (busy || active)
      throw StateError('An Android game session is already active.');
    busy = true;
    error = '';
    _emit();
    try {
      _lease = await SessionLease.acquire(manager.data);
      if (await pending() != null)
        throw StateError(
          'Close the previous Android emulator and finish its session before launching another game.',
        );
      if (await _mmj.pending)
        throw StateError(
          'MMJ has an unfinished shared-folder restore. Finish its original game session before starting another game.',
        );
      await manager.ensureNoWriters(closureConfirmed: true);
      _game = game;
      _launched = false;
      // Publish before sync or handoff. An exception/unknown platform reply
      // keeps the marker until closure is confirmed; it cannot be a false exit.
      await progressWrite(
        await progressFile(
          manager.data,
          'android/session.json',
          createParents: true,
        ),
        {
          'version': 1,
          'server': server,
          'profile': profile,
          'rom': rom,
          'emulator': emulator.id,
          'package': app.package,
          'selected': selected,
        },
      );
      active = true;
      _game = prepare == null ? game : await prepare();
      if (_game != null) {
        if (_game!.server != server ||
            _game!.profile != profile ||
            _game!.rom != rom)
          throw StateError(
            'Android progress belongs to another game or profile. No cloud save was changed.',
          );
        await progressWrite(marker, {
          ...(await pending())!,
          'stateAreas': [
            for (final area in _game!.layout.areas)
              if (area.id.startsWith('states-')) area.id,
          ],
        });
        phase = 'Checking BROOMM cloud saves…';
        _emit();
        await cloud.beforePlay(_game!, resolve: resolve);
        if (_game!.layout case final AndroidSavePlan plan) {
          phase = 'Preparing ${emulator.name}’s connected save folder…';
          _emit();
          await _shared.begin(_game!, plan, app.build, selected: selected);
        } else if (emulator.id == 'citra-mmj') {
          phase = 'Preparing MMJ’s shared save folder…';
          _emit();
          await _mmj.begin(_game!, app.build);
        }
      }
      phase = 'Opening ${emulator.name}…';
      _emit();
      await manager.launch(
        emulator,
        app,
        files,
        selected,
        core: core,
        profile: profile,
        configuration: _game?.layout is AndroidSavePlan
            ? (_game!.layout as AndroidSavePlan).launch['configNative']
            : null,
      );
      _launched = true;
      phase =
          'Game handed to ${emulator.name}. Save and exit the emulator, then finish this session.';
    } catch (e) {
      error = '$e';
      if (!active) {
        await _lease?.release();
        _lease = null;
      }
      rethrow;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> finish({
    required bool emulatorClosed,
    CloudGame? recovery,
  }) async {
    if (!emulatorClosed)
      throw StateError('Close the emulator before synchronizing progress.');
    if (busy) throw StateError('The Android session is still busy.');
    busy = true;
    error = '';
    _emit();
    try {
      final record = await pending();
      if (record == null) {
        if (active)
          throw StateError(
            'The Android recovery record is missing. Progress was kept; do not launch another emulator.',
          );
        active = false;
        await _lease?.release();
        _lease = null;
        return;
      }
      _lease ??= await SessionLease.acquire(manager.data);
      await manager.ensureNoWriters(closureConfirmed: emulatorClosed);
      var game = recovery ?? _game;
      final sharedPending = await _shared.pending;
      final sharedPlan = game?.layout is AndroidSavePlan
          ? game!.layout as AndroidSavePlan
          : null;
      if (sharedPending && sharedPlan == null)
        throw StateError(
          'Reconnect the original emulator folder and profile before finishing. Recovery copies were kept.',
        );
      final mmjPending = await _mmj.pending;
      if (mmjPending && (record['emulator'] != 'citra-mmj' || game == null))
        throw StateError(
          'Choose the original MMJ profile and reconnect its shared folder before finishing recovery. All save copies were kept.',
        );
      var changedBuild = false;
      if (game != null) {
        if (game.profile != record['profile'] ||
            game.server != record['server'] ||
            game.rom != record['rom'])
          throw StateError(
            'Choose the original Android game profile before synchronizing its session.',
          );
        final recorded = (record['stateAreas'] as List? ?? []).toSet();
        final current = game.layout.areas
            .where((a) => a.id.startsWith('states-'))
            .map((a) => a.id)
            .toSet();
        changedBuild =
            recorded.length != current.length || !recorded.containsAll(current);
        if (changedBuild) {
          final layout = game.layout;
          game = CloudGame(
            server: game.server,
            profile: game.profile,
            user: game.user,
            rom: game.rom,
            client: game.client,
            layout: ProgressLayout(
              layout.root,
              layout.format,
              layout.game,
              layout.areas.where((a) => !a.id.startsWith('states-')).toList(),
              note: layout.note,
              rawSave: layout.rawSave,
            ),
          );
        }
        phase = 'Keeping your progress safe…';
        _emit();
        // A restart is unclean recovery, requiring the existing explicit
        // conflict/review flow. Mere resume never certifies a clean shutdown.
        final capture = sharedPending
            ? await _shared.capture(game, cloud, sharedPlan!)
            : !mmjPending || await _mmj.capture(game, cloud);
        if (capture)
          await cloud.afterPlay(
            game,
            _game == null || !_launched || changedBuild ? 1 : 0,
          );
        if (mmjPending) await _mmj.restoreOriginal(game);
        if (sharedPending) await _shared.restoreOriginal(game, sharedPlan!);
      }
      await manager.releaseGrants();
      if (await progressExists(marker.path)) await marker.delete();
      active = false;
      _game = null;
      _launched = false;
      phase = game == null
          ? 'Session finished. Progress remains in the external emulator.'
          : 'Session finished. Local recovery and pending cloud transfers were retained.';
      await _lease?.release();
      _lease = null;
    } catch (e) {
      error = '$e';
      rethrow;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> reconnectFolder() async {
    if (busy) throw StateError('Wait for the current save operation.');
    busy = true;
    _emit();
    try {
      final record = await pending();
      if (record == null)
        throw StateError('There is no Android session to reconnect.');
      final emulator = androidEmulators.singleWhere(
        (e) => e.id == record['emulator'],
      );
      final package =
          record['package'] as String? ?? manager.app(emulator)?.package;
      final expected = await _shared.pending
          ? (await progressJson(_shared.journal))['tree'] as String?
          : manager.tree(record['profile'] as String, emulator);
      if (expected == null)
        throw StateError('This session has no external folder to reconnect.');
      final selected = await manager.chooseFolder(emulator, package: package);
      if (selected == null) return;
      if (selected != expected)
        throw StateError(
          'Choose the original emulator folder. Recovery copies and the connection were kept unchanged.',
        );
      await manager.channel.invokeMethod<void>('sharedCheck', {
        'emulator': emulator.id,
        'package': package,
        'tree': selected,
      });
      phase = 'Original save folder reconnected. Close the emulator, then finish and sync progress.';
    } finally {
      busy = false;
      _emit();
    }
  }

  /// The UI explicitly confirms closure and retaining the shared folder. This
  /// escape path never adopts unknown external bytes into a cloud profile.
  Future<void> keepMmjFolder({required bool emulatorClosed}) async {
    if (!emulatorClosed || busy)
      throw StateError('Close MMJ and wait for the current operation first.');
    busy = true;
    _emit();
    try {
      final record = await pending();
      if (record == null)
        throw StateError('There is no Android session to finish.');
      _lease ??= await SessionLease.acquire(manager.data);
      await manager.ensureNoWriters(closureConfirmed: emulatorClosed);
      // Do not inspect potentially incomplete native/shadow working files here.
      // Existing sealed snapshots remain authoritative until explicit review.
      final stateFile = await progressFile(
        manager.data,
        'cloud-saves/${record['server']}/${record['profile']}/${record['rom']}/state.json',
        createParents: true,
      );
      if (await stateFile.exists())
        await progressWrite(stateFile, {
          ...await progressJson(stateFile),
          'active': false,
          'unclean': true,
        });
      if (await _mmj.pending)
        await _mmj.keepSharedFolder(
          record['server'] as String,
          record['profile'] as String,
          record['rom'] as int,
        );
      if (await _shared.pending)
        await _shared.keepFolder(
          record['server'] as String,
          record['profile'] as String,
          record['rom'] as int,
        );
      await manager.releaseGrants();
      if (await progressExists(marker.path)) await marker.delete();
      active = false;
      _game = null;
      _launched = false;
      error = '';
      phase = 'MMJ’s shared folder was left unchanged. Recovery copies were kept; no further progress was uploaded.';
      await _lease?.release();
      _lease = null;
    } finally {
      busy = false;
      _emit();
    }
  }

  void _emit() {
    if (!disposed) notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    // Keep the durable marker. Releasing our coordinator is not evidence that
    // the independently owned Android emulator process has exited.
    _lease?.release();
    _lease = null;
    super.dispose();
  }
}
