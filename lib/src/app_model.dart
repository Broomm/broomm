import 'dart:async';

import 'package:flutter/foundation.dart';

import 'catalogue.dart';
import 'host.dart';
import 'pairing.dart';
import 'pairing_gestures.dart';
import 'session.dart';

enum Screen { library, loading, pairing, playing, menu }

class PrototypeModel extends ChangeNotifier {
  PrototypeModel(String project, {DesktopHost? host, GameSession? gameSession})
    : host = host ?? DesktopHost() {
    session = gameSession ?? GameSession(project);
    session.onStatus = _status;
    session.onExit = _exited;
    session.onProblem = _problem;
    session.onControlLost = _controlLost;
    session.onFinalizingProgress = _finalizingProgress;
  }
  final DesktopHost host;
  late final GameSession session;
  Screen screen = Screen.library;
  int selected = 0;
  Pairing? pairing;
  List<ControllerDevice> devices = [];
  bool busy = false;
  String? error;
  String notice = '';
  TestGame? loadingGame;
  int _request = 0;
  final Map<int, int> _buttons = {};
  int? activeController;
  final gestures = PairingGestures();
  final _clock = Stopwatch()..start();
  double holdProgress(int id, PairingAction action) =>
      gestures.progress(id, action, _clock.elapsed);
  bool _opening = false;
  bool _initialPresentation = false;
  bool _gyroPending = false;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_lifetime;
    _clock.stop();
    session.onStatus = null;
    session.onFinalizingProgress = null;
    session.onExit = null;
    session.onProblem = null;
    session.onControlLost = null;
    super.dispose();
  }

  int _lifetime = 0;
  bool get paused => session.status?.paused == 1;
  bool get canPair =>
      !busy &&
      paused &&
      session.status?.blocked == true &&
      session.status?.inputReady == true;
  bool get canPlay => canPair && (pairing?.valid(devices) ?? false);

  Future<void> select(TestGame game) async {
    if (busy || session.running) return;
    final lifetime = ++_lifetime;
    busy = true;
    error = null;
    notice = 'Preparing ${game.emulator}…';
    loadingGame = game;
    pairing = Pairing(game.players, target: game.controllerTarget);
    gestures.reset();
    _initialPresentation = true;
    screen = Screen.loading;
    _request = 0;
    _buttons.clear();
    activeController = null;
    notifyListeners();
    try {
      await host.show(overlay: true);
      if (lifetime != _lifetime) return;
      await session.launch(game);
      if (lifetime != _lifetime) return;
      notice = 'Waiting for the game and controller input to initialize…';
    } catch (e) {
      if (lifetime != _lifetime) return;
      error = '$e';
      screen = Screen.library;
      await _show();
    } finally {
      if (lifetime == _lifetime) {
        busy = false;
        if (_initialPresentation && _startupReady) unawaited(_finishLoading());
        notifyListeners();
      }
    }
  }

  void _status(BridgeStatus status) {
    devices = status.devices;
    if (_initialPresentation && !busy && _startupReady)
      unawaited(_finishLoading());
    if (status.requestSerial > _request) {
      _request = status.requestSerial;
      if (status.request == 'gyro' &&
          screen == Screen.playing &&
          (pairing?.players.any((p) => p.deviceId == status.requestDevice) ??
              false)) {
        pairing!.toggleGyro(status.requestDevice!);
        unawaited(_applyLiveGyro());
      }
      if (screen != Screen.loading &&
          (status.request == 'menu' ||
              status.request == 'input-error' ||
              status.request == 'disconnect' ||
              status.request == 'launcher-exit')) {
        unawaited(_open(status.request));
      }
    }
    if (screen == Screen.pairing) {
      pairing?.removeDisconnected(devices);
      for (final d in devices) {
        if (d.buttons & ~(_buttons[d.id] ?? d.buttons) != 0)
          activeController = d.id;
      }
      final actions = gestures.update(
        devices,
        pairing?.players.map((p) => p.deviceId).toSet() ?? {},
        _clock.elapsed,
        enabled: canPair,
      );
      for (final (id, action) in actions) {
        switch (action) {
          case PairingAction.join:
            pairing!.join(id, device: devices.firstWhere((d) => d.id == id));
          case PairingAction.mode:
            pairing!.cycleMode(id);
          case PairingAction.layout:
            pairing!.toggleLayout(id);
          case PairingAction.gyro:
            pairing!.toggleGyro(id);
          case PairingAction.leave:
            pairing?.leave(id);
          case PairingAction.play:
            if (canPlay) unawaited(play());
        }
      }
    } else if (screen == Screen.menu) {
      final actions = gestures.update(
        devices,
        pairing?.players.map((p) => p.deviceId).toSet() ?? {},
        _clock.elapsed,
        enabled: !busy && paused,
      );
      for (final d in devices) {
        final edges = d.buttons & ~(_buttons[d.id] ?? d.buttons);
        if (edges & 1 != 0) showPairing();
      }
      for (final (id, action) in actions) {
        if (action == PairingAction.gyro) pairing?.toggleGyro(id);
      }
      if (actions.any((a) => a.$2 == PairingAction.play)) unawaited(play());
    }
    _buttons
      ..clear()
      ..addEntries(devices.map((d) => MapEntry(d.id, d.buttons)));
    notifyListeners();
  }

  bool get _startupReady =>
      screen == Screen.loading &&
      paused &&
      session.status?.blocked == true &&
      session.status?.inputReady == true;
  Future<void> _finishLoading() async {
    final lifetime = _lifetime;
    _initialPresentation = false;
    busy = true;
    try {
      await _show(overlay: true);
      if (lifetime != _lifetime || !_startupReady) return;
      gestures.reset();
      screen = Screen.pairing;
      notice = 'Press L1 + R1 to join. Test any button before you play.';
    } finally {
      if (lifetime == _lifetime) {
        busy = false;
        if (screen == Screen.loading) _initialPresentation = true;
        notifyListeners();
      }
    }
  }

  Future<void> _open(String reason) async {
    if (_opening) return;
    final lifetime = _lifetime;
    _opening = true;
    busy = true;
    error = null;
    screen = reason == 'menu' ? Screen.menu : Screen.pairing;
    gestures.reset();
    notice = reason == 'input-error'
        ? 'Controller input could not be read safely. Review pairing and try again.'
        : reason == 'disconnect'
        ? 'A paired controller disconnected. Pair a controller to continue.'
        : 'Game paused';
    // A paused frame may take longer during first boot/shader compilation.
    // Keep the input gate closed even if pause acknowledgement times out.
    try {
      await session.waitFor(
        (s) => s.blocked && s.paused == 1,
        timeout: const Duration(seconds: 15),
      );
      if (lifetime != _lifetime) return;
      await _show(overlay: true);
    } catch (e) {
      if (lifetime != _lifetime) return;
      error = '$e';
      await _show(overlay: true);
    } finally {
      if (lifetime == _lifetime) {
        _opening = false;
        busy = false;
        notifyListeners();
      }
    }
  }

  void showPairing() {
    if (screen != Screen.loading) screen = Screen.pairing;
    gestures.reset();
    error = null;
    notifyListeners();
  }

  void join(int id) {
    pairing?.join(id, device: devices.where((d) => d.id == id).firstOrNull);
    notifyListeners();
  }

  void leave(int id) {
    pairing?.leave(id);
    notifyListeners();
  }

  void layout(int id) {
    pairing?.toggleLayout(id);
    notifyListeners();
  }

  void gyro(int id) {
    pairing?.toggleGyro(id);
    notifyListeners();
  }

  Future<void> _applyLiveGyro() async {
    if (!session.running || pairing == null) return;
    if (busy) {
      _gyroPending = true;
      return;
    }
    _gyroPending = false;
    final lifetime = _lifetime, request = _request;
    final players = List<PlayerAssignment>.of(pairing!.players);
    busy = true;
    gestures.reset();
    try {
      final pause = await session.command(players, active: false);
      await session.waitFor(
        (s) => s.ack >= pause && s.blocked && s.paused == 1,
      );
      // A disconnect/menu/exit observed during the update owns recovery. Never
      // resume it as a side effect of the earlier gyro shortcut.
      if (lifetime != _lifetime ||
          screen != Screen.playing ||
          _request != request ||
          !pairing!.valid(devices))
        return;
      final resume = await session.command(players, active: true);
      await session.waitFor(
        (s) => s.ack >= resume && !s.blocked && s.paused == 0,
      );
      if (lifetime == _lifetime && screen == Screen.playing)
        notice = 'Gyro settings applied';
    } catch (e) {
      if (lifetime != _lifetime) return;
      error = 'Could not apply gyro settings: $e';
      try {
        if (session.running) await session.command(players, active: false);
      } catch (pauseError) {
        error = '$error\nCould not request pause: $pauseError';
      }
      if (lifetime != _lifetime) return;
      screen = Screen.pairing;
      gestures.reset();
      await _show(overlay: true);
    } finally {
      if (lifetime == _lifetime && screen == Screen.playing)
        busy = false;
      else if (lifetime == _lifetime && !_opening)
        busy = false;
      if (lifetime == _lifetime && screen == Screen.playing && _gyroPending)
        unawaited(_applyLiveGyro());
      notifyListeners();
    }
  }

  void wiiMode(int id, WiiMode mode) {
    pairing?.setWiiMode(id, mode);
    notifyListeners();
  }

  void cycleMode(int id) {
    pairing?.cycleMode(id);
    notifyListeners();
  }

  void move(int index, int by) {
    pairing?.move(index, by);
    notifyListeners();
  }

  Future<void> play() async {
    if (!canPlay) return;
    final lifetime = _lifetime;
    final players = List<PlayerAssignment>.of(pairing!.players);
    notice = 'Release controller buttons to continue.';
    busy = true;
    error = null;
    notifyListeners();
    try {
      final revision = await session.command(players, active: true);
      if (lifetime != _lifetime) return;
      await session.waitFor(
        (s) => s.ack >= revision && !s.blocked && s.paused == 0,
      );
      if (lifetime != _lifetime) return;
      await host.hide(session.status!.pid);
      if (lifetime != _lifetime) return;
      screen = Screen.playing;
    } catch (e) {
      if (lifetime != _lifetime) return;
      error = 'Could not resume the game: $e';
      try {
        if (session.running) await session.command(players, active: false);
      } catch (gateError) {
        error = '$error\nCould not request pause: $gateError';
      }
      if (lifetime != _lifetime) return;
      screen = Screen.pairing;
      await _show(overlay: true);
    } finally {
      if (lifetime == _lifetime) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> menu() async {
    if (!session.running || busy) return;
    final lifetime = _lifetime;
    try {
      await session.command(pairing?.players ?? [], active: false);
      if (lifetime == _lifetime) await _open('menu');
    } catch (e) {
      if (lifetime != _lifetime) return;
      error = 'Could not open the game menu: $e';
      screen = Screen.pairing;
      await _show(overlay: true);
      notifyListeners();
    }
  }

  Future<void> stop({bool close = false}) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await session.stop();
      if (close) await host.close();
    } catch (e) {
      error = '$e';
      await _show(overlay: session.running);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _exited(int code) {
    ++_lifetime; // Invalidates every pending launch, pause or resume continuation.
    _opening = false;
    _initialPresentation = false;
    _gyroPending = false;
    busy = false;
    _buttons.clear();
    gestures.reset();
    _request = 0;
    screen = Screen.library;
    devices = [];
    pairing = null;
    notice = code == 0
        ? 'Game closed. Saved data stays in ${session.managedRoot == null ? 'prototype-data' : 'this Broomm profile'}.'
        : 'Emulator exited ($code). Local progress and logs have been retained in ${session.emulator?.root ?? session.dataRoot}.';
    error = code == 0 ? null : notice;
    unawaited(_show());
    notifyListeners();
  }

  void _finalizingProgress() {
    ++_lifetime;
    busy = true;
    screen = Screen.loading;
    notice = 'Keeping a local recovery copy and syncing progress with RomM…';
    unawaited(_show());
    notifyListeners();
  }

  Future<void> _show({bool overlay = false}) async {
    try {
      await host.show(overlay: overlay);
    } catch (e) {
      _problem('Could not bring Broomm back to the foreground: $e');
    }
  }

  void _controlLost(String text) {
    if (!session.running || pairing == null) return;
    ++_lifetime;
    final lifetime = _lifetime;
    _opening = false;
    _initialPresentation = screen == Screen.loading;
    busy = false;
    gestures.reset();
    if (screen != Screen.loading) screen = Screen.pairing;
    error = text;
    // The file command can be consumed if the bridge recovers. Do not assume it
    // paused, delete progress, or release ownership while the writer is alive.
    unawaited(
      session.command(pairing!.players, active: false).catchError((Object e) {
        if (lifetime == _lifetime)
          _problem('$text\nCould not request pause: $e');
        return 0;
      }),
    );
    unawaited(_show(overlay: true));
    notifyListeners();
  }

  void _problem(String text) {
    if (error != text) {
      error = text;
      notifyListeners();
    }
  }

  void highlight(int index) {
    selected = index;
    notifyListeners();
  }

  void libraryInput(String input) {
    if (screen != Screen.library) return;
    if (input == 'up') selected = (selected - 1).clamp(0, testGames.length - 1);
    if (input == 'down')
      selected = (selected + 1).clamp(0, testGames.length - 1);
    if (input == 'accept') unawaited(select(testGames[selected]));
    notifyListeners();
  }
}
