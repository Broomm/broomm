import 'dart:io';

import 'package:flutter/foundation.dart';

import '../progress/files.dart';
import '../progress/service.dart';
import '../progress/layout.dart';
import '../session_lease.dart';
import 'emulators.dart';
import 'mmj_shared_saves.dart';
import 'root_saves.dart';
import 'save_plan.dart';
import 'shared_saves.dart';

class AndroidClosureUnverified implements Exception {
  const AndroidClosureUnverified();
  @override
  String toString() =>
      'Could not verify RetroArch is closed. Quit it before continuing.';
}

class AndroidRetroArchSetupRequired implements Exception {
  const AndroidRetroArchSetupRequired();
  @override
  String toString() =>
      'Open RetroArch to install its bundled resources. Wait for its main menu, quit RetroArch, then try Play again.';
}

/// A separate supervisor for external Android activities. Rooted RetroArch can
/// supply process evidence. Other sessions use explicit closure confirmation.
/// A durable marker blocks new sessions after process/activity destruction.
class AndroidGameSession extends ChangeNotifier {
  AndroidGameSession(this.manager, this.cloud);
  final AndroidEmulators manager;
  final CloudSaves cloud;
  SessionLease? _lease;
  CloudGame? _game;
  bool _launched = false;
  Map<String, int>? _retroArchProcess;
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
    bool rooted = false,
    bool emulatorClosed = true,
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
      String? nativeRom;
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
      final root = rooted
          ? manager.rootConnection(
              emulator,
              core == 'snes9x' ? 'snes' : 'gba',
              package: app.package,
            )
          : null;
      if (rooted && root == null)
        throw StateError('Reconnect RetroArch root saves before playing.');
      if (root != null) {
        phase = 'Checking whether RetroArch is closed…';
        _emit();
        await _checkRetroArchIdle(root, emulatorClosed: emulatorClosed);
      }
      // Check first-run readiness before creating a recovery journal or
      // touching cloud progress. The standalone setup has no game session.
      final rootedGame = root != null && prepare != null
          ? await prepare()
          : game;
      if (root != null) {
        final layout = rootedGame?.layout;
        if (layout is! AndroidSavePlan || !mapEquals(layout.binding, root))
          throw StateError(
            'The RetroArch root save route changed. Progress was kept.',
          );
        if (layout.launch['frontendSetup'] == 'true')
          throw const AndroidRetroArchSetupRequired();
      }
      _game = game;
      _launched = false;
      _retroArchProcess = null;
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
          if (rooted) 'rooted': true,
          if (rooted) 'rootPlatform': core == 'snes9x' ? 'snes' : 'gba',
        },
      );
      active = true;
      _game = root != null || prepare == null ? rootedGame : await prepare();
      final layout = _game?.layout;
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
        if (layout is AndroidSavePlan &&
            layout.rooted &&
            layout.launch['prepareControllerProfiles'] == 'true') {
          phase = 'Preparing RetroArch controller profiles…';
          _emit();
          await manager.channel.invokeMethod<void>(
            'rootControllerProfiles',
            layout.arguments,
          );
        }
        phase = 'Checking BROOMM cloud saves…';
        _emit();
        await cloud.beforePlay(_game!, resolve: resolve);
        if (_game!.layout case final AndroidSavePlan plan) {
          phase = 'Preparing ${emulator.name}’s connected save folder…';
          _emit();
          if (root != null)
            await _checkRetroArchIdle(root, emulatorClosed: emulatorClosed);
          await _shared.begin(_game!, plan, app.build, selected: selected);
          if (plan.rooted) {
            phase = 'Preparing the game file for RetroArch…';
            _emit();
            nativeRom = await _shared.stageRootRom(_game!, plan);
          }
        } else if (emulator.id == 'citra-mmj') {
          phase = 'Preparing MMJ’s shared save folder…';
          _emit();
          await _mmj.begin(_game!, app.build);
        }
      }
      phase = 'Opening ${emulator.name}…';
      _emit();
      final launchClock = root == null
          ? null
          : await _checkRetroArchIdle(root, emulatorClosed: emulatorClosed);
      await manager.launch(
        emulator,
        app,
        files,
        selected,
        core: core,
        profile: profile,
        nativeRom: nativeRom,
        configuration: _game?.layout is AndroidSavePlan
            ? (_game!.layout as AndroidSavePlan).launch['configNative']
            : null,
      );
      _launched = true;
      phase = root == null
          ? 'Game handed to ${emulator.name}. Save and exit the emulator, then finish this session.'
          : 'Save and quit RetroArch, then return to Broomm.';
      if (root != null && launchClock != null) {
        try {
          for (var attempt = 0; attempt < 6 && !disposed; attempt++) {
            final report = await readAndroidRetroArchState(
              manager,
              root,
              launchedAfter: launchClock,
            );
            if (report.process != null) {
              _retroArchProcess = report.process;
              cloud.phase?.call(
                'RetroArch process identified for this session.',
              );
              break;
            }
            if (report.state == AndroidRetroArchState.unknown) break;
            if (attempt < 5)
              await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        } catch (_) {
          cloud.phase?.call(
            'RetroArch process could not be tracked. Recovery remains available.',
          );
        }
      }
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

  Future<int?> _checkRetroArchIdle(
    Map<String, String> root, {
    required bool emulatorClosed,
  }) async {
    final report = await readAndroidRetroArchState(manager, root);
    if (report.state == AndroidRetroArchState.running)
      throw StateError(
        'RetroArch is still running. Save and quit RetroArch, then try again.',
      );
    if (report.state == AndroidRetroArchState.idle && report.elapsed != null)
      return report.elapsed;
    if (!emulatorClosed) throw const AndroidClosureUnverified();
    return null;
  }

  Future<Map<String, String>?> _recoveryRoot(Map record) async {
    if (record['emulator'] != 'retroarch') return null;
    if (record['rooted'] != true &&
        !{'root-gba-v1', 'root-snes-v1'}.contains(record['access']) &&
        !(await _shared.pending &&
            {
              'root-gba-v1',
              'root-snes-v1',
            }.contains((await progressJson(_shared.journal))['access'])))
      return null;
    final emulator = androidEmulators.singleWhere((e) => e.id == 'retroarch');
    final root = manager.rootConnection(
      emulator,
      record['rootPlatform'] == 'snes' || record['access'] == 'root-snes-v1'
          ? 'snes'
          : 'gba',
      package: record['package'] as String?,
    );
    if (root == null)
      throw StateError(
        'Reconnect the original RetroArch root save route before finishing.',
      );
    return root;
  }

  Future<void> finish({
    required bool emulatorClosed,
    CloudGame? recovery,
  }) async {
    if (!emulatorClosed)
      throw StateError('Close the emulator before synchronizing progress.');
    await _finish(recovery: recovery);
  }

  Future<AndroidRetroArchState> finishIfRetroArchClosed() =>
      _finish(automatic: true);

  Future<AndroidRetroArchState> _finish({
    CloudGame? recovery,
    bool automatic = false,
  }) async {
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
        return AndroidRetroArchState.closed;
      }
      _lease ??= await SessionLease.acquire(manager.data);
      await manager.ensureNoWriters(closureConfirmed: true);
      final root = await _recoveryRoot(record);
      var rootExit = AndroidRetroArchState.unknown;
      if (root != null) {
        final process = _retroArchProcess;
        if (process != null) {
          // The emulator can still be shutting down when Broomm resumes.
          // Give both the process and its exit record a bounded settling time.
          const checks = 5;
          for (var attempt = 0; attempt < (automatic ? checks : 1); attempt++) {
            rootExit = (await readAndroidRetroArchState(
              manager,
              root,
              process: process,
            )).state;
            if (!automatic ||
                rootExit == AndroidRetroArchState.closed ||
                rootExit == AndroidRetroArchState.interrupted)
              break;
            if (attempt < checks - 1)
              await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        } else {
          rootExit = (await readAndroidRetroArchState(manager, root)).state;
        }
        if (rootExit == AndroidRetroArchState.running) {
          phase =
              'RetroArch is still running. Save and quit it to sync progress.';
          if (automatic) return rootExit;
          throw StateError(phase);
        }
      }
      if (automatic &&
          (rootExit != AndroidRetroArchState.closed ||
              !_launched ||
              _game == null)) {
        phase = 'RetroArch’s normal exit could not be verified. Progress was kept for recovery.';
        return rootExit == AndroidRetroArchState.interrupted
            ? rootExit
            : AndroidRetroArchState.unknown;
      }
      if (automatic)
        cloud.phase?.call('Verified RetroArch exit. Synchronizing progress.');
      var game = recovery ?? _game;
      final sharedPending = await _shared.pending;
      var sharedPlan = game?.layout is AndroidSavePlan
          ? game!.layout as AndroidSavePlan
          : null;
      if (sharedPending && sharedPlan == null)
        throw StateError(
          'Reconnect the original emulator folder and profile before finishing. Recovery copies were kept.',
        );
      if (sharedPending && sharedPlan != null)
        sharedPlan = await _shared.recoveryPlan(game!, sharedPlan);
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
        if (root != null)
          await _checkRetroArchIdle(root, emulatorClosed: !automatic);
        final capture = sharedPending
            ? await _shared.capture(game, cloud, sharedPlan!)
            : !mmjPending || await _mmj.capture(game, cloud);
        if (capture) {
          if (root != null)
            await _checkRetroArchIdle(root, emulatorClosed: !automatic);
          final unclean =
              _game == null ||
              !_launched ||
              changedBuild ||
              root != null && rootExit != AndroidRetroArchState.closed;
          await cloud.afterPlay(game, unclean ? 1 : 0);
        }
        if (root != null)
          await _checkRetroArchIdle(root, emulatorClosed: !automatic);
        if (mmjPending) await _mmj.restoreOriginal(game);
        if (sharedPending) await _shared.restoreOriginal(game, sharedPlan!);
      }
      await manager.releaseGrants();
      if (await progressExists(marker.path)) await marker.delete();
      active = false;
      _game = null;
      _launched = false;
      _retroArchProcess = null;
      phase = game == null
          ? 'Session finished. Progress remains in the external emulator.'
          : 'Session finished. Local recovery and pending cloud transfers were retained.';
      await _lease?.release();
      _lease = null;
      return AndroidRetroArchState.closed;
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
      final root = await _recoveryRoot(record);
      if (root != null) await _checkRetroArchIdle(root, emulatorClosed: true);
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
      _retroArchProcess = null;
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
