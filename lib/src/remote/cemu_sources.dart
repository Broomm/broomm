import 'dart:async';

import 'protocol.dart';

class CemuControllerSample {
  const CemuControllerSample(
    this.id,
    this.remote,
    this.pad,
    this.connected,
    this.at,
  );
  final int id, at;
  final bool remote, connected;
  final RemotePad pad;
}

/// IDs belong to this Broomm source namespace, not SDL, XInput or evdev.
/// Replacing a physical source or authenticated guest removes its old ID.
class CemuControllerSources {
  CemuControllerSources({int Function()? milliseconds})
    : _milliseconds = milliseconds;
  final int Function()? _milliseconds;
  final _clock = Stopwatch()..start();
  final _samples = StreamController<CemuControllerSample>.broadcast(sync: true);
  final _touches = StreamController<RemoteTouch>.broadcast(sync: true);
  final _current = <bool, (Object?, CemuControllerSample)>{};
  int _next = 1;
  bool _closed = false;
  int get milliseconds => _milliseconds?.call() ?? _clock.elapsedMilliseconds;
  Stream<CemuControllerSample> get samples => _samples.stream;
  Stream<RemoteTouch> get touches => _touches.stream;
  Iterable<CemuControllerSample> get current =>
      _current.values.map((e) => e.$2);

  void update({
    required bool remote,
    required Object? device,
    required RemotePad pad,
    required bool connected,
  }) {
    if (_closed) return;
    final previous = _current[remote];
    if (previous != null && (!connected || previous.$1 != device)) {
      _samples.add(
        CemuControllerSample(
          previous.$2.id,
          remote,
          RemotePad.neutral,
          false,
          milliseconds,
        ),
      );
      _current.remove(remote);
    }
    if (!connected) return;
    final id = previous != null && previous.$1 == device
        ? previous.$2.id
        : _next++;
    final sample = CemuControllerSample(id, remote, pad, true, milliseconds);
    _current[remote] = (device, sample);
    _samples.add(sample);
  }

  void touch(RemoteTouch value) {
    if (!_closed) _touches.add(value);
  }

  Future<void> close() async {
    if (_closed) return;
    for (final entry in _current.values) {
      _samples.add(
        CemuControllerSample(
          entry.$2.id,
          entry.$2.remote,
          RemotePad.neutral,
          false,
          milliseconds,
        ),
      );
    }
    _touches.add(RemoteTouch.released);
    _closed = true;
    _current.clear();
    await _samples.close();
    await _touches.close();
    _clock.stop();
  }
}
