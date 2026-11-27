import 'dart:async';

import 'package:flutter/services.dart';

import 'cemu_process.dart';
import 'pairing.dart';
import 'remote/cemu_input.dart';
import 'remote/cemu_sources.dart';
import 'remote/protocol.dart';
import 'session.dart' show BridgeStatus;

/// Cemu's concrete controller/pause adapter. Broomm source identities are
/// explicitly paired to one native DSU GamePad; no SDL IDs cross this boundary.
class CemuSessionControl {
  CemuSessionControl(
    this.sources,
    this.title, {
    required this.changed,
    required this.problem,
  }) : input = CemuRemoteInput(onProblem: problem);
  final CemuControllerSources sources;
  final String title;
  final void Function(BridgeStatus) changed;
  final void Function(String) problem;
  final CemuRemoteInput input;
  final _devices = <int, CemuControllerSample>{};
  StreamSubscription<CemuControllerSample>? _samples;
  StreamSubscription<RemoteTouch>? _touch;
  Timer? _timer;
  CemuControlProcess? process;
  List<PlayerAssignment> _players = [];
  bool _closed = false,
      _polling = false,
      _ready = false,
      _active = false,
      _chord = false,
      _failed = false;
  int _paused = -1, _ack = 0, _sample = 0, _request = 0, _inspected = -1000;
  String _reason = 'initial';
  int _intent = 0;
  bool _quitting = false;
  int _nativeSample = -1, _nativeAt = 0;
  Future<void> _operations = Future.value();

  Future<void> prepare() async {
    await input.start();
    for (final source in sources.current) _receive(source);
    _samples = sources.samples.listen(_receive);
    _touch = sources.touches.listen((touch) {
      input.touch(_active ? touch : RemoteTouch.released);
    });
  }

  void _receive(CemuControllerSample sample) {
    if (_closed) return;
    if (sample.connected)
      _devices[sample.id] = sample;
    else
      _devices.remove(sample.id);
  }

  Future<void> attach(CemuControlProcess child) async {
    process = child;
    await child.admit();
    await CemuProcess.channel
        .invokeMethod<void>('gameController', child.target)
        .timeout(const Duration(seconds: 2));
    _timer = Timer.periodic(
      const Duration(milliseconds: 32),
      (_) => unawaited(_poll()),
    );
    await _poll();
  }

  List<ControllerDevice> get devices => [
    for (final sample in _devices.values)
      if (sources.milliseconds - sample.at <= 350)
        ControllerDevice(
          sample.id,
          sample.remote ? 'Remote controller' : 'Local controller',
          sample.pad.buttons,
          sample.pad.axes[0],
          sample.pad.axes[1],
          rx: sample.pad.axes[2],
          ry: sample.pad.axes[3],
          lt: sample.pad.axes[4],
          rt: sample.pad.axes[5],
          sensors: 0,
        ),
  ];
  bool get _paired =>
      _players.length == 1 &&
      devices.any((d) => d.id == _players.single.deviceId);
  Future<void> _poll() async {
    final child = process;
    if (_closed || _polling || child == null) return;
    _polling = true;
    try {
      final receipt = await child.receipt();
      if (_closed) return;
      final sampledAt = sources.milliseconds;
      if (receipt == null) {
        if (_ready && sampledAt - _nativeAt > 2000)
          throw StateError(
            'Cemu’s native controller bridge stopped reporting. Close its window normally.',
          );
        return;
      }
      if (receipt['sample'] != _nativeSample) {
        _nativeSample = receipt['sample'];
        _nativeAt = sampledAt;
      }
      if (_ready && _paused != 1 && sampledAt - _nativeAt > 2000)
        throw StateError(
          'Cemu’s native controller bridge stopped updating. Close its window normally.',
        );
      if (_ready && receipt['title'] == '0000000000000000' && !_quitting) {
        _quitting = true;
        await command([], active: false, quit: true);
        return;
      }
      if (_ready && receipt['title'] != title && !_quitting)
        throw StateError(
          'Cemu changed the running title. Close it normally before continuing.',
        );
      if (!_ready && !_failed && receipt['title'] == title && input.hasReader) {
        if (!await child.state(paused: true))
          throw StateError('Cemu did not confirm startup pause.');
        _paused = 1;
        _ready = true;
        _ack = receipt['ack'];
      }
      final now = sources.milliseconds;
      if (_ready && now - _inspected >= 250) {
        _inspected = now;
        _paused = await child.state() ? 1 : 0;
      }
      if (_active && !_paired) unawaited(_requestPause('disconnect'));
      final selected = _players.isEmpty
          ? null
          : _devices[_players.single.deviceId];
      final buttons = selected?.pad.buttons ?? 0;
      final chord = (buttons & ((1 << 8) | (1 << 4))) == ((1 << 8) | (1 << 4));
      if (_active && chord && !_chord) unawaited(_requestPause('menu'));
      _chord = chord;
      if (_active && _paired && _paused == 0 && selected != null) {
        var pad = selected.pad;
        if (_players.single.swapFaces) {
          final bits = pad.buttons;
          pad = RemotePad(
            (bits & ~15) | ((bits & 5) << 1) | ((bits & 10) >> 1),
            pad.axes,
          );
        }
        input.pad(pad, true);
      } else {
        input.pad(RemotePad.neutral, false);
      }
      _emit();
    } catch (error) {
      _active = false;
      _paused = -1;
      input.pad(RemotePad.neutral, false);
      if (!_failed && !_closed) {
        _failed = true;
        problem('Cemu control needs attention. $error');
      }
      if (!_closed) _emit();
    } finally {
      _polling = false;
    }
  }

  Future<void> _requestPause(String reason) async {
    if (!_active) return;
    _active = false;
    try {
      await command(_players, active: false);
      _reason = reason;
      ++_request;
      _emit();
    } catch (error) {
      if (!_closed) problem('Could not pause Cemu. $error');
    }
  }

  Future<int> command(
    List<PlayerAssignment> players, {
    required bool active,
    bool quit = false,
  }) {
    final intent = ++_intent;
    if (quit) _quitting = true;
    if (!active) {
      _active = false;
      input.pad(RemotePad.neutral, false);
    }
    final result = Completer<int>();
    _operations = _operations.then((_) async {
      try {
        final child = process ?? (throw StateError('Cemu is not running.'));
        if (_closed) throw StateError('The Cemu session ended.');
        _active = false;
        input.pad(RemotePad.neutral, false);
        _players = List.of(players);
        if (active && (!_ready || !_paired))
          throw StateError('Pair a connected controller before starting Cemu.');
        if (active) {
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (true) {
            if (_closed || intent != _intent || !_paired)
              throw StateError(
                'Cemu resume was cancelled or its controller changed.',
              );
            final devices = this.devices.where(
              (d) => _players.any((p) => p.deviceId == d.id),
            );
            if (devices.every(
              (d) => d.buttons == 0 && d.lt < 8000 && d.rt < 8000,
            ))
              break;
            if (DateTime.now().isAfter(deadline))
              throw StateError(
                'Release the controller buttons, then try starting Cemu again.',
              );
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        }
        if (_closed || intent != _intent)
          throw StateError('The Cemu control request was replaced.');
        // The command is published before resume so a formerly frozen native
        // worker sees its new route immediately. Closure uses WM_CLOSE/AppKit.
        final revision = await child.command(active: active, quit: quit);
        if (active || quit) {
          final wasPaused = _paused != 0;
          if (await child.state(paused: false))
            throw StateError('Cemu did not confirm resume.');
          // A frozen native worker cannot advance its receipt. Give only an
          // actual resume transition time to publish; route refreshes while
          // already running must not conceal a genuinely stopped heartbeat.
          if (wasPaused) _nativeAt = sources.milliseconds;
          _paused = 0;
        } else if (_ready) {
          if (!await child.state(paused: true))
            throw StateError('Cemu did not confirm pause.');
          _paused = 1;
        }
        _ack = revision;
        _failed = false;
        _active = active && intent == _intent;
        _emit();
        result.complete(revision);
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  void _emit() {
    final child = process;
    if (_closed || child == null) return;
    final target = child.target;
    changed(
      BridgeStatus({
        'protocol': 4,
        'pid': child.pid,
        'sample': ++_sample,
        'ack': _ack,
        'requestSerial': _request,
        'request': _reason,
        'blocked': !_active,
        'paused': _paused,
        'window': <double>[],
        'inputReady': _ready,
        'connectedPorts': _active && _paired ? 1 : 0,
        'consolePorts': 1,
        'gameWindowVisible': _ready,
        if (target?['seconds'] != null)
          'macWindowBirth': [target!['seconds'], target['microseconds']],
        if (target?['birth'] != null) 'remoteBirth': target!['birth'],
        'devices': [
          for (final d in devices)
            {
              'id': d.id,
              'name': d.name,
              'buttons': d.buttons,
              'x': d.x,
              'y': d.y,
              'rx': d.rx,
              'ry': d.ry,
              'lt': d.lt,
              'rt': d.rt,
              'sensors': 0,
            },
        ],
      }),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_intent;
    _active = false;
    _timer?.cancel();
    await input.close();
    await _samples?.cancel();
    await _touch?.cancel();
    await _operations;
    try {
      await CemuProcess.channel
          .invokeMethod<void>('gameController')
          .timeout(const Duration(seconds: 2));
    } on MissingPluginException {
      /* Native fixture. */
    }
  }
}
