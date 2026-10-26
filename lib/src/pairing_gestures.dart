import 'pairing.dart';

enum PairingAction { join, mode, layout, gyro, leave, play }

class PairingGestures {
  static const hold = Duration(seconds: 1);
  final Map<int, _Gesture> _devices = {};
  void reset() => _devices.clear();
  double progress(int id, PairingAction action, Duration now) {
    final from = action == PairingAction.play
        ? _devices[id]?.start
        : _devices[id]?.select;
    return from == null
        ? 0
        : ((now - from).inMicroseconds / hold.inMicroseconds).clamp(0, 1);
  }

  List<(int, PairingAction)> update(
    List<ControllerDevice> devices,
    Set<int> paired,
    Duration now, {
    required bool enabled,
  }) {
    _devices.removeWhere((id, _) => !devices.any((d) => d.id == id));
    final actions = <(int, PairingAction)>[];
    for (final d in devices) {
      final g = _devices.putIfAbsent(d.id, () => _Gesture());
      // Analog trigger hysteresis prevents a noisy R2 from repeating a chord.
      if (d.rt >= 16384) g.trigger = true;
      if (d.rt <= 8192) g.trigger = false;
      // Discovery and readiness changes require a fresh release.
      if (!enabled) {
        g.disarm();
        continue;
      }
      if (!d.pressed(9) && !d.pressed(10)) g.joinReady = true;
      if (!d.pressed(7) && !d.pressed(10)) g.layoutReady = true;
      if (!d.pressed(7) && !g.trigger) g.gyroReady = true;
      if (!d.pressed(6)) {
        g.startReady = true;
        g.start = null;
      }
      if (!d.pressed(4)) {
        g.selectReady = true;
        g.select = null;
      }
      if (g.joinReady && d.pressed(9) && d.pressed(10)) {
        if (!d.pressed(7))
          actions.add((
            d.id,
            paired.contains(d.id) ? PairingAction.mode : PairingAction.join,
          ));
        g.joinReady = false;
      }
      if (g.layoutReady && d.pressed(7) && d.pressed(10)) {
        if (paired.contains(d.id) &&
            !d.pressed(9) &&
            !g.trigger &&
            !d.pressed(4) &&
            !d.pressed(8)) {
          actions.add((d.id, PairingAction.layout));
        }
        g.layoutReady = false;
        g.gyroReady = false;
      }
      if (g.gyroReady && d.pressed(7) && g.trigger) {
        if (paired.contains(d.id) &&
            !d.pressed(9) &&
            !d.pressed(10) &&
            !d.pressed(4) &&
            !d.pressed(8)) {
          actions.add((d.id, PairingAction.gyro));
        }
        g.gyroReady = false;
        g.layoutReady = false;
      }
      if (!paired.contains(d.id)) continue;
      // L3 chords cannot inherit a Start hold; require a fresh solo Start.
      // Select+R3 and Select+Start retain their overlay/Home meanings.
      final startOnly =
          d.pressed(6) && !d.pressed(4) && !d.pressed(7) && !d.pressed(8);
      final selectOnly = d.pressed(4) && !d.pressed(6) && !d.pressed(8);
      if (!startOnly) {
        g.start = null;
        if (d.pressed(6)) g.startReady = false;
      }
      if (!selectOnly) {
        g.select = null;
        if (d.pressed(4)) g.selectReady = false;
      }
      if (startOnly && g.startReady) {
        g.start ??= now;
        if (now - g.start! >= hold) {
          actions.add((d.id, PairingAction.play));
          g.startReady = false;
          g.start = null;
        }
      }
      if (selectOnly && g.selectReady) {
        g.select ??= now;
        if (now - g.select! >= hold) {
          actions.add((d.id, PairingAction.leave));
          g.selectReady = false;
          g.select = null;
        }
      }
    }
    return actions;
  }
}

class _Gesture {
  bool joinReady = false,
      layoutReady = false,
      gyroReady = false,
      startReady = false,
      selectReady = false;
  Duration? start, select;
  bool trigger = false;
  void disarm() {
    joinReady = layoutReady = gyroReady = startReady = selectReady = false;
    start = select = null;
  }
}
