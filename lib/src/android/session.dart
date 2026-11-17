import 'dart:io';

import 'package:flutter/foundation.dart';

import '../progress/files.dart';
import '../progress/service.dart';
import '../progress/layout.dart';
import '../session_lease.dart';
import '../romm/transfer.dart';
import 'emulators.dart';
import 'mmj_shared_saves.dart';
import 'citra_mmj.dart';
import 'root_saves.dart';
import 'save_plan.dart';
import 'shared_saves.dart';
import 'psp_root.dart';
import 'psp_session.dart';
import 'duck_root.dart';
import 'duck_session.dart';
import 'duckstation_documents.dart';
import 'melon_root.dart';
import 'dolphin_root.dart';
import 'eden_root.dart';
import 'armsx2_root.dart';

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
  Future<AndroidRetroArchState> Function()? _standaloneExit;
  bool get tracksStandaloneExit => _standaloneExit != null;
  DownloadCancellation? _preparation;
  bool get canCancelPreparation =>
      _preparation != null && !_preparation!.cancelled;
  void cancelPreparation() {
    if (!canCancelPreparation) return;
    _preparation?.cancel();
    phase = 'Cancelling preparation…';
    _emit();
  }

  bool busy = false, active = false, disposed = false;
  String phase = '', error = '';
  File get marker => File('${manager.data.path}/android/session.json');
  late final _mmj = MmjSharedSaves(manager, phase: cloud.phase);
  late final _shared = SharedAndroidSaves(manager, phase: cloud.phase);
  late final _psp = AndroidPspSession(
    manager,
    cloud,
    check: () => _preparation?.check(),
  );

  late final _duck = AndroidDuckSession(
    manager,
    cloud,
    check: () => _preparation?.check(),
    cancellation: () => _preparation,
  );

  Future<void> openEmulatorAppInfo() async {
    final record = await pending();
    final package = record?['package'];
    if (package is! String)
      throw StateError(
        'This session’s emulator package could not be verified.',
      );
    await manager.openAppInfo(package);
  }

  AndroidApp _sessionApp(Map<String, dynamic> record) {
    final emulator = androidEmulators.singleWhere(
      (item) => item.id == record['emulator'],
    );
    final package = record['package'];
    final build = record['build'];
    final app = package is String && emulator.packages.contains(package)
        ? manager.app(emulator, package: package)
        : null;
    if (app == null || build != null && app.build != build)
      throw StateError('The emulator installation changed. Recovery was kept.');
    return app;
  }

  Map<String, String> _processIdentity(AndroidApp app) => {
    'package': app.package,
    'build': app.build,
  };

  Future<void> resumeDuckGame() async {
    final record = await pending();
    if (record == null || record['emulator'] != 'duckstation')
      throw StateError('There is no DuckStation game session to return to.');
    final app = _sessionApp(record);
    final handoff = await _duck.pending
        ? await progressJson(_duck.journal)
        : null;
    final binding = handoff?['binding'], process = handoff?['process'];
    if (handoff == null ||
        handoff['version'] != 1 ||
        ![
          'server',
          'profile',
          'rom',
          'package',
          'emulator',
        ].every((key) => handoff[key] == record[key]) ||
        binding is! Map ||
        binding['build'] != app.build ||
        process is! Map)
      throw StateError(
        'DuckStation’s original game process is unavailable. Check for exit.',
      );
    await manager.channel.invokeMethod<void>('rootDuckResume', {
      ..._processIdentity(app),
      'process': process,
    });
  }

  Future<void> forceClose() async {
    if (busy) throw StateError('Wait for the current Android operation.');
    busy = true;
    _emit();
    try {
      if (!await progressExists(marker.path))
        throw StateError(
          'The original emulator session record is unavailable. Use Android App info.',
        );
      _lease ??= await SessionLease.acquire(manager.data);
      final record = await pending();
      if (record == null || !await progressExists(marker.path))
        throw StateError(
          'The original emulator session record is unavailable. Use Android App info.',
        );
      final app = _sessionApp(record);
      if (record['build'] != app.build)
        throw StateError(
          'The original emulator build is unavailable. Use Android App info.',
        );
      await manager.ensureNoWriters(closureConfirmed: true);
      // A failed or lost native reply leaves an interrupted session.
      final stopped = {...record, 'forceClosed': true}
        ..remove('forceCloseVerified')
        ..remove('forceCloseSync');
      await progressWrite(marker, stopped);
      phase = 'Force-closing the emulator…';
      _emit();
      await manager.channel.invokeMethod<void>(
        'rootEmulatorStop',
        _processIdentity(app),
      );
      await progressWrite(marker, {
        ...stopped,
        'forceCloseVerified': true,
        if (_launched || record['launched'] == true) 'forceCloseSync': true,
      });
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<Map<String, dynamic>?> pending() async {
    final Map<String, dynamic> value;
    var sharedSwap = false;
    if (await progressExists(marker.path)) {
      value = await progressJson(marker);
    } else {
      if (await _shared.pending) {
        sharedSwap = true;
        value = await progressJson(_shared.journal);
      } else {
        if (await _duck.pending) {
          value = await progressJson(_duck.journal);
        } else if (await _psp.pending) {
          value = await progressJson(_psp.journal);
        } else {
          if (!await _mmj.pending) return null;
          // A surviving swap receipt must still expose recovery if the general
          // session receipt is missing. Never mistake the shared folder for idle.
          value = {
            ...await progressJson(_mmj.journal),
            'emulator': 'citra-mmj',
          };
        }
      }
    }
    final lynxSwap =
        sharedSwap &&
        value['version'] == 2 &&
        value['emulator'] == 'retroarch' &&
        value['coreName'] == 'mednafen_lynx' &&
        value['rootPlatform'] == 'lynx' &&
        value['access'] == 'root-cartridge-v1';
    final operaSwap =
        sharedSwap &&
        value['version'] == 3 &&
        value['emulator'] == 'retroarch' &&
        value['coreName'] == 'opera' &&
        value['rootPlatform'] == '3do' &&
        value['access'] == 'root-cartridge-v1';
    final saturnSwap =
        sharedSwap &&
        value['version'] == 4 &&
        value['emulator'] == 'retroarch' &&
        value['coreName'] == 'mednafen_saturn' &&
        value['rootPlatform'] == 'saturn' &&
        value['access'] == 'root-cartridge-v1';
    final flycastSwap =
        sharedSwap &&
        value['version'] == 5 &&
        value['emulator'] == 'retroarch' &&
        value['coreName'] == 'flycast' &&
        value['rootPlatform'] == 'dc' &&
        value['access'] == 'root-cartridge-v1';
    if (value['version'] != 1 &&
            !lynxSwap &&
            !operaSwap &&
            !saturnSwap &&
            !flycastSwap ||
        !RegExp(r'^[a-f0-9]{32}$')
            .hasMatch(value['profile'] as String? ?? '') ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['server'] as String? ?? '') ||
        value['rom'] is! int ||
        (value['rom'] as int) < 1 ||
        !androidEmulators.any((e) => e.id == value['emulator']))
      throw const FormatException(
        'Android session recovery record is invalid. Progress was kept.',
      );
    if (lynxSwap ||
        operaSwap ||
        saturnSwap ||
        flycastSwap ||
        sharedSwap &&
            androidRootAccessModes.contains(value['access']) &&
            value['rootStateGroup'] != null) {
      final group = value['rootStateGroup'];
      final platform = value['rootPlatform'];
      if (value['emulator'] != 'retroarch' ||
          platform is! String ||
          androidRootRetroCore(platform) != value['coreName'] ||
          androidRootRetroAccess(platform) != value['access'] ||
          group is! String ||
          !RegExp(r'^states-[a-f0-9]{16}-android$').hasMatch(group))
        throw const FormatException(
          'The rooted state recovery identity is invalid. Progress was kept.',
        );
      return {
        ...value,
        'stateAreas': [group],
      };
    }
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
    Future<CloudGame?> Function(DownloadCancellation, void Function(String))?
    prepare,
    bool rooted = false,
    String? rootPlatform,
    bool emulatorClosed = true,
    Future<void> Function()? onStarted,
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
    phase = '';
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
      final platform = rootPlatform ?? (core == 'snes9x' ? 'snes' : 'gba');
      final pspRooted = rooted && emulator.id == 'ppsspp' && platform == 'psp';
      final duckRooted =
          rooted && emulator.id == 'duckstation' && platform == 'psx';
      if (rooted &&
          !pspRooted &&
          !duckRooted &&
          androidRootRetroCore(platform) != core)
        throw const FormatException(
          'Rooted RetroArch platform/core identity differs.',
        );
      final root = rooted && !pspRooted && !duckRooted
          ? manager.rootConnection(emulator, platform, package: app.package)
          : null;
      if (rooted && !pspRooted && !duckRooted && root == null)
        throw StateError('Reconnect RetroArch root saves before playing.');
      if (root != null) {
        phase = 'Checking whether RetroArch is closed…';
        _emit();
        await _checkRetroArchIdle(root, emulatorClosed: emulatorClosed);
      }
      // Check first-run readiness before creating a recovery journal or
      // touching cloud progress. The standalone setup has no game session.
      if (pspRooted) {
        final binding = manager.pspRoot(package: app.package);
        if (binding == null || binding['build'] != app.build)
          throw StateError('Verify PPSSPP root setup before playing.');
        await _psp.roots.restoreSettingsLoan();
        await _psp.roots.ensureClosed(binding);
      }
      if (duckRooted) {
        final binding = manager.duckRoot(package: app.package);
        if (binding == null || binding['build'] != app.build)
          throw StateError('Verify DuckStation root setup before playing.');
        await _duck.roots.restoreSettingsLoan();
        await _duck.roots.ensureClosed(binding);
      }
      final preparedGame = prepare == null
          ? game
          : rooted
          ? await _prepareRoot(prepare)
          : await prepare(DownloadCancellation(), _preparePhase);
      final layout = preparedGame?.layout;
      if (emulator.id == 'citra-mmj' &&
          app.package == androidMmjSharedPackage &&
          app.version == androidMmjSharedVersion &&
          (layout is! AndroidSavePlan || !layout.mmjRooted))
        throw StateError(
          'Verify Citra MMJ’s rooted folder setup before playing. This build needs a private game path.',
        );
      if (root != null) {
        if (layout is! AndroidSavePlan || !mapEquals(layout.binding, root))
          throw StateError(
            'The RetroArch root save route changed. Progress was kept.',
          );
        if (layout.launch['frontendSetup'] == 'true')
          throw const AndroidRetroArchSetupRequired();
      }
      if (pspRooted &&
          (layout is! AndroidPspPlan ||
              !mapEquals(
                layout.binding,
                manager.pspRoot(package: app.package),
              )))
        throw StateError(
          'The PPSSPP root save route changed. Progress was kept.',
        );
      if (duckRooted &&
          (layout is! AndroidDuckPlan ||
              !mapEquals(
                layout.binding,
                manager.duckRoot(package: app.package),
              )))
        throw StateError(
          'The DuckStation root route changed. Progress was kept.',
        );
      if (preparedGame != null &&
          (preparedGame.server != server ||
              preparedGame.profile != profile ||
              preparedGame.rom != rom))
        throw StateError(
          'Android progress belongs to another game or profile. No cloud save was changed.',
        );
      if (layout is AndroidSavePlan && layout.nativeMediaRoot)
        await manager.channel.invokeMethod<void>(
          layout.method('Check'),
          layout.arguments,
        );
      if (pspRooted || duckRooted) _preparation = DownloadCancellation();
      _launched = false;
      _retroArchProcess = null;
      _standaloneExit = null;
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
          'build': app.build,
          'selected': selected,
          if (rooted) 'rooted': true,
          if (rooted) 'rootPlatform': platform,
          if (layout is AndroidSavePlan && layout.nativeMediaRoot)
            'access': layout.binding['access'],
          if (layout != null)
            'stateAreas': [
              for (final area in layout.areas)
                if (area.id.startsWith('states-')) area.id,
            ],
        },
      );
      _game = preparedGame;
      active = true;
      if (_game != null) {
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
        if (layout is AndroidPspPlan)
          await _psp.prepare(_game!, layout, resolve: resolve);
        if (layout is AndroidDuckPlan)
          await _duck.prepare(_game!, layout, resolve: resolve);
        await cloud.beforePlay(_game!, resolve: resolve);
        if (layout is AndroidPspPlan) await _psp.cloudPrepared(_game!, layout);
        if (layout is AndroidDuckPlan)
          await _duck.cloudPrepared(_game!, layout);
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
          } else if (plan.mmjRooted) {
            phase = 'Preparing the game file for Citra MMJ…';
            _emit();
            nativeRom = await _shared.stageMmjRom(_game!, plan);
          }
        } else if (layout is AndroidPspPlan) {
          phase = 'Preparing this profile’s private PSP memory stick…';
          _emit();
          await _psp.install(_game!, layout);
        } else if (layout is AndroidDuckPlan) {
          phase = 'Preparing private PS1 cards and states…';
          _emit();
          await _duck.install(_game!, layout);
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
      final pspPlan = _game?.layout is AndroidPspPlan
          ? _game!.layout as AndroidPspPlan
          : null;
      final pspClock = pspPlan == null
          ? null
          : await _psp.launching(_game!, pspPlan);
      final duckPlan = _game?.layout is AndroidDuckPlan
          ? _game!.layout as AndroidDuckPlan
          : null;
      final duckClock = duckPlan == null
          ? null
          : await _duck.launching(_game!, duckPlan);
      if (layout is AndroidSavePlan && layout.nativeMediaRoot)
        await manager.channel.invokeMethod<void>(
          layout.method('Check'),
          layout.arguments,
        );
      _preparation?.check();
      final standaloneClock = !rooted && emulator.id != 'retroarch'
          ? await _standaloneLaunchClock(app)
          : null;
      if (emulator.id == 'duckstation' &&
          app.version == androidDuckStationDocumentVersion) {
        _preparation = DownloadCancellation();
        if (disposed) _preparation!.cancel();
      }
      await manager.launch(
        emulator,
        app,
        files,
        selected,
        core: core,
        profile: profile,
        nativeRom: nativeRom,
        rootedPsp: pspPlan != null,
        rootedDuck: duckPlan != null,
        rootedMelon: layout is AndroidSavePlan && layout.melonRooted,
        cancellation: _preparation,
        phase: _preparePhase,
        configuration: _game?.layout is AndroidSavePlan
            ? (_game!.layout as AndroidSavePlan).launch['configNative']
            : null,
      );
      _launched = true;
      await progressWrite(marker, {
        ...await progressJson(marker),
        'launched': true,
      });
      if (standaloneClock != null)
        await _identifyStandalone(app, standaloneClock);
      if (duckPlan != null && duckClock != null)
        await _duck.identify(_game!, duckPlan, duckClock);
      phase = duckPlan != null
          ? 'Save and choose Close Game in DuckStation, then return to Broomm.'
          : pspPlan != null
          ? 'Save and use PPSSPP’s Exit action, then return to Broomm.'
          : root == null
          ? 'Game handed to ${emulator.name}. Save and exit the emulator, then finish this session.'
          : 'Save and quit RetroArch, then return to Broomm.';
      if (pspPlan != null && pspClock != null)
        await _psp.identify(_game!, pspPlan, pspClock);
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
      await onStarted?.call();
    } catch (e) {
      error = '$e';
      if (e is DownloadWriterUncertain) _lease?.retainForUncertainWriter();
      if (!active) {
        await _lease?.release();
        _lease = null;
      }
      rethrow;
    } finally {
      _preparation = null;
      busy = false;
      _emit();
    }
  }

  void _preparePhase(String value) {
    phase = value;
    cloud.phase?.call(value);
    _emit();
  }

  Future<CloudGame?> _prepareRoot(
    Future<CloudGame?> Function(DownloadCancellation, void Function(String))
    prepare,
  ) async {
    final cancellation = DownloadCancellation();
    _preparation = cancellation;
    if (disposed) cancellation.cancel();
    _emit();
    try {
      cancellation.check();
      final game = await prepare(cancellation, _preparePhase);
      cancellation.check();
      return game;
    } finally {
      _preparation = null;
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
        !androidRootAccessModes.contains(record['access']) &&
        !(await _shared.pending &&
            androidRootAccessModes.contains(
              (await progressJson(_shared.journal))['access'],
            )))
      return null;
    final emulator = androidEmulators.singleWhere((e) => e.id == 'retroarch');
    final root = manager.rootConnection(
      emulator,
      record['rootPlatform'] as String? ??
          (record['access'] == 'root-snes-v1' ? 'snes' : 'gba'),
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

  Future<AndroidPspState> finishIfPspClosed() async {
    final game = _game;
    if (game == null || game.layout is! AndroidPspPlan)
      return AndroidPspState.unknown;
    var exit = AndroidPspState.unknown;
    for (var attempt = 0; attempt < 5; attempt++) {
      exit = await _psp.exitState(game, game.layout as AndroidPspPlan);
      if (exit == AndroidPspState.closed || exit == AndroidPspState.interrupted)
        break;
      if (attempt < 4)
        await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (exit != AndroidPspState.closed) {
      phase = exit == AndroidPspState.running
          ? 'PPSSPP is still running. Save and use Exit to sync progress.'
          : 'PPSSPP’s normal exit could not be verified. Recovery was kept.';
      _emit();
      return exit;
    }
    await _finish(pspAutomatic: true);
    return AndroidPspState.closed;
  }

  Future<AndroidDuckState> finishIfDuckClosed() async {
    if (busy) return AndroidDuckState.unknown;
    busy = true;
    _emit();
    try {
      final game = _game;
      if (game == null || game.layout is! AndroidDuckPlan)
        return AndroidDuckState.unknown;
      final state = await _duck.exitState(game, game.layout as AndroidDuckPlan);
      if (state == AndroidDuckState.closed) {
        busy = false;
        await _finish(duckAutomatic: true);
      } else {
        phase = state == AndroidDuckState.running
            ? 'DuckStation is still running. Save and choose Close Game.'
            : 'DuckStation closure could not be verified. Recovery was kept.';
        _emit();
      }
      return state;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<({int elapsed, int? wall})?> _standaloneLaunchClock(
    AndroidApp app,
  ) async {
    try {
      // Shared-only play reuses an authorized connection for exit evidence.
      if (await manager.channel.invokeMethod<bool>('rootSessionAvailable') !=
          true)
        return null;
      final identity = _processIdentity(app);
      if (app.package == 'org.ppsspp.ppsspp' &&
          {'v1.20.4', '1.20.4'}.contains(app.version)) {
        final report = await readAndroidPspState(
          manager,
          identity,
          shared: true,
        );
        return (elapsed: report.elapsed, wall: report.wall);
      }
      final report = await readAndroidRetroArchState(
        manager,
        identity,
        standalone: true,
      );
      final elapsed = report.elapsed;
      return report.state == AndroidRetroArchState.idle && elapsed != null
          ? (elapsed: elapsed, wall: null)
          : null;
    } catch (_) {
      cloud.phase?.call('Android emulator exit tracking was unavailable.');
      return null;
    }
  }

  Future<void> _identifyStandalone(
    AndroidApp app,
    ({int elapsed, int? wall}) clock,
  ) async {
    final identity = _processIdentity(app);
    try {
      for (var attempt = 0; attempt < 5 && !disposed; attempt++) {
        final wall = clock.wall;
        if (wall != null) {
          final report = await readAndroidPspState(
            manager,
            identity,
            launchedAfter: (elapsed: clock.elapsed, wall: wall),
            shared: true,
          );
          final process = report.process;
          if (process != null) {
            _standaloneExit = () async => AndroidRetroArchState.values.byName(
              (await readAndroidPspState(
                manager,
                identity,
                process: process,
                shared: true,
              )).state.name,
            );
            return;
          }
        } else {
          final report = await readAndroidRetroArchState(
            manager,
            identity,
            launchedAfter: clock.elapsed,
            standalone: true,
          );
          final process = report.process;
          if (process != null) {
            _standaloneExit = () async => (await readAndroidRetroArchState(
              manager,
              identity,
              process: process,
              standalone: true,
            )).state;
            return;
          }
          if (report.state == AndroidRetroArchState.unknown) break;
        }
        if (attempt < 4)
          await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } catch (_) {
      cloud.phase?.call('Android emulator process could not be tracked.');
    }
  }

  Future<AndroidRetroArchState> finishIfStandaloneClosed() async {
    final observe = _standaloneExit;
    if (observe == null || !_launched || busy)
      return AndroidRetroArchState.unknown;
    busy = true;
    _emit();
    try {
      var state = AndroidRetroArchState.unknown;
      for (var attempt = 0; attempt < 5; attempt++) {
        state = await observe();
        if (state == AndroidRetroArchState.closed ||
            state == AndroidRetroArchState.interrupted)
          break;
        if (attempt < 4)
          await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (state == AndroidRetroArchState.closed) {
        cloud.phase?.call(
          'Verified Android emulator exit. Synchronizing progress.',
        );
        busy = false;
        return await _finish(standaloneAutomatic: true);
      }
      phase = state == AndroidRetroArchState.running
          ? 'Android still has the emulator open. Save and exit, or use Force close and sync after saving.'
          : 'The emulator’s normal exit could not be verified. Recovery was kept.';
      return state;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> _requireStandaloneExit() async {
    if (await _standaloneExit?.call() != AndroidRetroArchState.closed)
      throw StateError(
        'The emulator’s exit could no longer be verified. Recovery was kept.',
      );
  }

  Future<AndroidRetroArchState> _finish({
    CloudGame? recovery,
    bool automatic = false,
    bool standaloneAutomatic = false,
    bool pspAutomatic = false,
    bool duckAutomatic = false,
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
      final forced = record['forceClosed'] == true;
      final forceCloseSync =
          forced &&
          record['forceCloseVerified'] == true &&
          record['forceCloseSync'] == true;
      if (record['emulator'] == 'duckstation' &&
          (record['rooted'] == true || await _duck.pending)) {
        final game = recovery ?? _game;
        if (game == null ||
            game.layout is! AndroidDuckPlan ||
            game.server != record['server'] ||
            game.profile != record['profile'] ||
            game.rom != record['rom'])
          throw StateError(
            'Choose the original PS1 game, profile and root setup to finish recovery.',
          );
        if (await _duck.pending)
          await _duck.finish(
            game,
            game.layout as AndroidDuckPlan,
            automatic: duckAutomatic,
            forced: forced,
            forceCloseSync: forceCloseSync,
          );
        else
          await _duck.roots.ensureClosed(
            (game.layout as AndroidDuckPlan).binding,
          );
        await manager.releaseGrants();
        if (await progressExists(marker.path)) await marker.delete();
        active = false;
        _game = null;
        _launched = false;
        phase = 'PS1 session finished. Private progress and pending cloud transfers were retained.';
        await _lease?.release();
        _lease = null;
        return AndroidRetroArchState.closed;
      }
      if (record['emulator'] == 'ppsspp' &&
          (record['rooted'] == true || await _psp.pending)) {
        final game = recovery ?? _game;
        if (game == null || game.layout is! AndroidPspPlan)
          throw StateError(
            'Choose the original PSP profile and verify its root setup before finishing. Recovery was kept.',
          );
        if (game.server != record['server'] ||
            game.profile != record['profile'] ||
            game.rom != record['rom'])
          throw StateError(
            'Choose the original PSP game and profile. Recovery was kept.',
          );
        if (await _psp.pending)
          await _psp.finish(
            game,
            game.layout as AndroidPspPlan,
            automatic: pspAutomatic,
            forced: forced,
            forceCloseSync: forceCloseSync,
          );
        else
          await _psp.roots.ensureClosed(
            (game.layout as AndroidPspPlan).binding,
          );
        await manager.releaseGrants();
        if (await progressExists(marker.path)) await marker.delete();
        active = false;
        _game = null;
        _launched = false;
        phase = 'PSP session finished. Private progress and pending cloud transfers were retained.';
        await _lease?.release();
        _lease = null;
        return AndroidRetroArchState.closed;
      }
      final root = await _recoveryRoot(record);
      final forcedApp = record['forceCloseVerified'] == true
          ? _sessionApp(record)
          : null;
      Future<void> verifyStandaloneClosure() async {
        if (standaloneAutomatic) await _requireStandaloneExit();
        if (forcedApp == null) return;
        final report = await readAndroidRetroArchState(
          manager,
          _processIdentity(forcedApp),
          standalone: true,
        );
        if (report.state != AndroidRetroArchState.idle)
          throw StateError(
            'The force-closed emulator is open again. Recovery was kept.',
          );
      }

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
        await verifyStandaloneClosure();
        final capture = sharedPending
            ? await _shared.capture(game, cloud, sharedPlan!)
            : !mmjPending || await _mmj.capture(game, cloud);
        if (capture) {
          if (root != null)
            await _checkRetroArchIdle(root, emulatorClosed: !automatic);
          await verifyStandaloneClosure();
          final unclean =
              changedBuild ||
              !forceCloseSync &&
                  (forced ||
                      _game == null ||
                      !_launched ||
                      root != null && rootExit != AndroidRetroArchState.closed);
          await cloud.afterPlay(game, unclean ? 1 : 0);
        }
        if (root != null)
          await _checkRetroArchIdle(root, emulatorClosed: !automatic);
        await verifyStandaloneClosure();
        if (mmjPending) await _mmj.restoreOriginal(game);
        if (sharedPending) await _shared.restoreOriginal(game, sharedPlan!);
      }
      await manager.releaseGrants();
      if (await progressExists(marker.path)) await marker.delete();
      active = false;
      _game = null;
      _launched = false;
      _retroArchProcess = null;
      _standaloneExit = null;
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
      final binding = manager.folder(emulator, package: package);
      if (binding?['access'] == androidPreparedFolderAccess) {
        await manager.channel.invokeMethod<void>('sharedCheck', {
          ...binding!,
          'emulator': emulator.id,
          'tree': expected,
        });
        phase = 'Emulator folder verified. Close the emulator, then finish and sync progress.';
        return;
      }
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
      if (record['emulator'] == 'duckstation' && await _duck.pending)
        throw StateError(
          'Finish the original PS1 settings loan before leaving recovery. All copies were kept.',
        );
      if (record['emulator'] == 'ppsspp' && await _psp.pending)
        throw StateError(
          'PSP owns a private memory-stick handoff. Finish its verified recovery before leaving this session. All copies were kept.',
        );
      if (await _shared.pending &&
          {
            androidMelonRootAccess,
            androidDolphinRootAccess,
            androidEdenRootAccess,
            androidArmsx2RootAccess,
          }.contains((await progressJson(_shared.journal))['access']))
        throw StateError(
          'Finish the original rooted save transaction. Recovery was kept.',
        );
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
    final preparing = _preparation != null;
    _preparation?.cancel();
    // Keep the durable marker. Releasing our coordinator is not evidence that
    // the independently owned Android emulator process has exited.
    if (!preparing) {
      _lease?.release();
      _lease = null;
    }
    super.dispose();
  }
}
