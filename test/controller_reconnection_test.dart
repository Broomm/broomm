import 'dart:async';

import 'package:broomm/src/app_model.dart';
import 'package:broomm/src/pairing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overlay_state_test.dart' show PausedSession, RecordingHost;

class HeldHideHost extends RecordingHost {
  final hideEntered = Completer<void>(), releaseHide = Completer<void>();
  bool visible = true;
  @override
  Future<void> show({List<double>? frame, bool overlay = false}) async {
    visible = true;
    await super.show(frame: frame, overlay: overlay);
  }

  @override
  Future<void> hide(int pid) async {
    if (!hideEntered.isCompleted) hideEntered.complete();
    await releaseHide.future;
    visible = false;
    await super.hide(pid);
  }
}

Future<void> idle(PrototypeModel model) {
  if (!model.busy) return Future.value();
  final done = Completer<void>();
  void listener() {
    if (!model.busy) {
      model.removeListener(listener);
      done.complete();
    }
  }

  model.addListener(listener);
  return done.future;
}

List<Map<String, dynamic>> dualSense(int id) => [
  {
    'id': id,
    'name': 'DualSense Wireless Controller',
    'buttons': 0,
    'x': 0,
    'y': 0,
    'family': 2,
  },
];
void main() {
  test('disconnect before resume acknowledgement keeps pairing open and never hides it', () async {
    final session = PausedSession()..pauseAck = Completer<void>();
    final host = RecordingHost();
    final model = PrototypeModel('/unused', host: host, gameSession: session)
      ..screen = Screen.pairing;
    addTearDown(model.dispose);
    model.pairing = Pairing(2)..join(10);
    session.emit(devices: dualSense(10));
    final resume = model.play();
    expect(session.applied.single.$2, isTrue);
    session.emit(request: 'disconnect', serial: 1, devices: []);
    final recovered = idle(model);
    session.pauseAck!.complete();
    await resume;
    await recovered;
    expect(model.screen, Screen.pairing);
    expect(model.pairing!.players, isEmpty);
    expect(host.hidden, 0);
    expect(host.shown, 1);
  });
  test('disconnect during an in-flight hide wins; explicit pairing with a new instance can resume', () async {
    final session = PausedSession();
    final host = HeldHideHost();
    final model = PrototypeModel('/unused', host: host, gameSession: session)
      ..screen = Screen.pairing;
    addTearDown(model.dispose);
    model.pairing = Pairing(2)..join(10);
    session.emit(devices: dualSense(10));
    final oldResume = model.play();
    await host.hideEntered.future;
    session.emit(request: 'disconnect', serial: 1, devices: []);
    await idle(model);
    session.emit(request: 'disconnect', serial: 1, devices: dualSense(72));
    model.join(72);
    host.releaseHide.complete();
    await oldResume;
    expect(model.screen, Screen.pairing);
    expect(host.visible, isTrue);
    expect(model.pairing!.players.single.deviceId, 72);
    expect(model.error, isNull);
    await model.play();
    expect(model.screen, Screen.playing);
    expect(host.visible, isFalse);
    expect(session.applied.last.$1.single.deviceId, 72);
  });
  test('a battery disconnect supersedes a pending menu presentation', () async {
    final session = PausedSession()..pauseAck = Completer<void>();
    final host = RecordingHost();
    final model = PrototypeModel('/unused', host: host, gameSession: session)
      ..screen = Screen.playing;
    addTearDown(model.dispose);
    model.pairing = Pairing(2)..join(10);
    session.emit(request: 'menu', serial: 1, devices: dualSense(10));
    expect(model.screen, Screen.menu);
    session.emit(request: 'disconnect', serial: 2, devices: []);
    expect(model.screen, Screen.pairing);
    expect(model.pairing!.players, isEmpty);
    final recovered = idle(model);
    session.pauseAck!.complete();
    await recovered;
    expect(model.screen, Screen.pairing);
    expect(host.shown, 1);
  });
}
