import 'dart:async';

import 'package:broomm/src/app_model.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/host.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/pairing_gestures.dart';
import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingHost extends DesktopHost {
  int shown = 0, hidden = 0;
  @override
  Future<void> show({List<double>? frame, bool overlay = false}) async {
    shown++;
  }

  @override
  Future<void> hide(int pid) async {
    hidden++;
  }
}

class PausedSession extends GameSession {
  PausedSession() : super('/unused');
  Completer<void>? pauseAck;
  int commands = 0;
  final applied = <(List<PlayerAssignment>, bool)>[];
  bool alive = true, failCommands = false;
  @override
  bool get running => alive;
  @override
  Future<void> launch(TestGame selected) async {
    alive = true;
    game = selected;
    status = null;
  }

  @override
  Future<void> waitFor(
    bool Function(BridgeStatus) ready, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await pauseAck?.future;
  }

  @override
  Future<int> command(
    List<PlayerAssignment> players, {
    required bool active,
    bool quit = false,
  }) async {
    commands++;
    applied.add((List.of(players), active));
    if (failCommands) throw StateError('Command file is unavailable');
    return commands;
  }

  void exit(int code) {
    alive = false;
    onExit?.call(code);
  }

  void emit({
    String request = 'initial',
    int serial = 0,
    int paused = 1,
    List<Map<String, dynamic>>? devices,
    int? requestDevice,
    bool inputReady = true,
    bool blocked = true,
    Map<String, dynamic>? loading,
  }) {
    status = BridgeStatus({
      'inputReady': inputReady,
      'protocol': 4,
      'pid': 123,
      'sample': 1,
      'ack': 1,
      'requestSerial': serial,
      'request': request,
      'requestDevice': requestDevice,
      'blocked': blocked,
      'paused': paused,
      'window': [0, 0, 1000, 720],
      'devices':
          devices ??
          [
            {'id': 10, 'name': 'Pad', 'buttons': 0, 'x': 0, 'y': 0},
          ],
      if (loading != null) 'loading': loading,
    });
    onStatus?.call(status!);
  }
}

void main() {
  test(
    'startup waits for input discovery and pause before exposing join actions',
    () async {
      final session = PausedSession()..alive = false;
      final host = RecordingHost();
      final model = PrototypeModel('/unused', host: host, gameSession: session);
      await model.select(testGames.first);
      expect(model.screen, Screen.loading);
      expect(model.canPair, false);
      session.emit(inputReady: false, paused: -1);
      expect(model.screen, Screen.loading);
      session.emit(inputReady: true, paused: 0);
      expect(model.screen, Screen.loading);
      session.emit(inputReady: true, paused: 1, blocked: false);
      expect(model.screen, Screen.loading);
      final held = [
        {
          'id': 10,
          'name': 'Pad',
          'buttons': (1 << 9) | (1 << 10),
          'x': 0,
          'y': 0,
        },
      ];
      session.emit(devices: held);
      await Future<void>.delayed(Duration.zero);
      expect(model.screen, Screen.pairing);
      expect(model.canPair, true);
      session.emit(devices: held);
      expect(model.pairing!.players, isEmpty);
      session.emit();
      session.emit(devices: held);
      expect(model.pairing!.players.single.deviceId, 10);
    },
  );
  test('initial control failure stays on loading and recovers only after readiness', () async {
    final session = PausedSession()..alive = false;
    final model = PrototypeModel(
      '/unused',
      host: RecordingHost(),
      gameSession: session,
    );
    await model.select(testGames.first);
    session.onControlLost?.call('Bridge unavailable');
    expect(model.screen, Screen.loading);
    expect(model.canPair, false);
    session.emit(inputReady: false);
    await Future<void>.delayed(Duration.zero);
    expect(model.screen, Screen.loading);
    session.emit();
    await Future<void>.delayed(Duration.zero);
    expect(model.screen, Screen.pairing);
    expect(model.canPair, true);
  });
  test(
    'exit before startup readiness cannot reveal stale pairing afterward',
    () async {
      final session = PausedSession()..alive = false;
      final model = PrototypeModel(
        '/unused',
        host: RecordingHost(),
        gameSession: session,
      );
      await model.select(testGames.first);
      session.exit(1);
      session.emit();
      await Future<void>.delayed(Duration.zero);
      expect(model.screen, Screen.library);
      expect(model.busy, false);
      expect(model.pairing, isNull);
    },
  );
  test('native gyro request applies once while playing and keeps accelerometer policy independent', () async {
    final session = PausedSession(), host = RecordingHost();
    final model = PrototypeModel('/unused', host: host, gameSession: session)
      ..screen = Screen.playing;
    model.pairing = Pairing(2, target: ControllerTarget.wii)..join(10);
    session.emit(paused: 0);
    session.emit(request: 'gyro', serial: 1, requestDevice: 10);
    await Future<void>.delayed(Duration.zero);
    expect(model.pairing!.players.single.gyroEnabled, false);
    expect(session.applied.map((a) => a.$2), [false, true]);
    expect(session.applied.every((a) => !a.$1.single.gyroEnabled), true);
    expect(host.shown, 0);
    expect(model.screen, Screen.playing);
    session.emit(request: 'gyro', serial: 1, requestDevice: 10);
    expect(session.commands, 2);
  });
  test(
    'disconnect during a gyro update never resumes the interrupted game',
    () async {
      final session = PausedSession()..pauseAck = Completer<void>();
      final model = PrototypeModel(
        '/unused',
        host: RecordingHost(),
        gameSession: session,
      )..screen = Screen.playing;
      model.pairing = Pairing(2, target: ControllerTarget.wii)..join(10);
      session.emit(request: 'gyro', serial: 1, requestDevice: 10);
      session.emit(request: 'disconnect', serial: 2, devices: []);
      session.pauseAck!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(session.applied.any((a) => a.$2), false);
      expect(model.screen, Screen.pairing);
      expect(model.busy, false);
    },
  );
  test('failed gyro publication remains in recoverable pairing', () async {
    final session = PausedSession()..failCommands = true;
    final host = RecordingHost();
    final model = PrototypeModel('/unused', host: host, gameSession: session)
      ..screen = Screen.playing;
    model.pairing = Pairing(2)..join(10);
    session.emit(request: 'gyro', serial: 1, requestDevice: 10);
    await Future<void>.delayed(Duration.zero);
    expect(model.screen, Screen.pairing);
    expect(model.error, contains('Could not apply gyro'));
    expect(model.busy, false);
    expect(host.shown, 1);
  });
  for (final target in [ControllerTarget.wii, ControllerTarget.ps3]) {
    test(
      'raw pairing chords keep face swaps and supported controller types independent for $target',
      () {
        final session = PausedSession();
        final model = PrototypeModel(
          '/unused',
          host: RecordingHost(),
          gameSession: session,
        )..screen = Screen.pairing;
        model.pairing = Pairing(4, target: target);
        void input(int bits, {int rt = 0}) => session.emit(
          devices: [
            {
              'id': 10,
              'name': 'Pad',
              'buttons': bits,
              'x': 0,
              'y': 0,
              'rt': rt,
            },
          ],
        );
        input(0);
        input((1 << 9) | (1 << 10));
        expect(model.pairing!.players.length, 1);
        final face = model.pairing!.players.single.swapFaces;
        input(0);
        input((1 << 9) | (1 << 10));
        final mode = model.pairing!.players.single.wiiMode;
        expect(
          mode,
          target == ControllerTarget.wii ? WiiMode.sideways : WiiMode.nunchuk,
        );
        expect(model.pairing!.players.single.swapFaces, face);
        input(0);
        input((1 << 7) | (1 << 10));
        expect(model.pairing!.players.single.wiiMode, mode);
        expect(model.pairing!.players.single.swapFaces, !face);
        input(0);
        input(1 << 7, rt: 32767);
        expect(model.pairing!.players.single.gyroEnabled, false);
        expect(model.pairing!.players.single.swapFaces, !face);
        expect(model.pairing!.players.single.wiiMode, mode);
        expect(session.commands, 0);
      },
    );
  }
  test(
    'input uncertainty opens pairing without removing a connected player',
    () async {
      final host = RecordingHost(), session = PausedSession();
      final model = PrototypeModel('/unused', host: host, gameSession: session);
      model.screen = Screen.playing;
      model.pairing = Pairing(4)..join(10);
      session.emit(request: 'input-error', serial: 1);
      await Future<void>.delayed(Duration.zero);
      expect(model.screen, Screen.pairing);
      expect(model.pairing!.players.single.deviceId, 10);
      expect(model.notice, contains('could not be read safely'));
      expect(host.shown, 1);
    },
  );
  test(
    'lost bridge clears an unfinished hold before a held controller recovers',
    () {
      final session = PausedSession();
      final model = PrototypeModel(
        '/unused',
        host: RecordingHost(),
        gameSession: session,
      );
      model.screen = Screen.pairing;
      model.pairing = Pairing(1)..join(10);
      const neutral = ControllerDevice(10, 'Pad', 0, 0, 0),
          held = ControllerDevice(10, 'Pad', 64, 0, 0);
      model.gestures.update([neutral], {10}, Duration.zero, enabled: true);
      model.gestures.update(
        [held],
        {10},
        const Duration(milliseconds: 100),
        enabled: true,
      );
      session.onControlLost!('Controller bridge lost');
      expect(
        model.gestures.update(
          [held],
          {10},
          const Duration(seconds: 10),
          enabled: true,
        ),
        isEmpty,
      );
      model.gestures.update(
        [neutral],
        {10},
        const Duration(seconds: 11),
        enabled: true,
      );
      model.gestures.update(
        [held],
        {10},
        const Duration(seconds: 12),
        enabled: true,
      );
      expect(
        model.gestures.update(
          [held],
          {10},
          const Duration(seconds: 13),
          enabled: true,
        ),
        [(10, PairingAction.play)],
      );
    },
  );
  test(
    'lost bridge returns pairing without claiming pause or ending the writer',
    () async {
      final host = RecordingHost(), session = PausedSession();
      final model = PrototypeModel('/unused', host: host, gameSession: session);
      model.screen = Screen.playing;
      model.pairing = Pairing(2)..join(10);
      session.status = null;
      session.onControlLost?.call('Pause could not be confirmed');
      await Future<void>.delayed(Duration.zero);
      expect(model.screen, Screen.pairing);
      expect(model.canPlay, isFalse);
      expect(session.running, isTrue);
      expect(model.pairing!.players.single.deviceId, 10);
      expect(host.shown, 1);
      expect(session.commands, 1);
    },
  );
  test(
    'logging failures are visible without stealing gameplay focus',
    () async {
      final host = RecordingHost(), session = PausedSession();
      final model = PrototypeModel('/unused', host: host, gameSession: session);
      model.screen = Screen.playing;
      session.onProblem?.call('Session logging failed');
      expect(model.screen, Screen.playing);
      expect(model.error, contains('logging'));
      expect(host.shown, 0);
    },
  );
  for (final code in [0, 1]) {
    test(
      'exit $code during a pending pause returns to a usable library',
      () async {
        final host = RecordingHost(), session = PausedSession();
        final model = PrototypeModel(
          '/unused',
          host: host,
          gameSession: session,
        );
        model.screen = Screen.playing;
        model.pairing = Pairing(4)..join(10);
        session.pauseAck = Completer<void>();
        session.emit(request: 'menu', serial: 1);
        session.exit(code);
        session.pauseAck!.completeError(StateError('The emulator exited'));
        await Future<void>.delayed(Duration.zero);
        expect(model.screen, Screen.library);
        expect(model.busy, isFalse);
        expect(model.pairing, isNull);
        expect(host.shown, 1);
        expect(model.error != null, code != 0);
        await model.select(testGames.first);
        expect(model.screen, Screen.loading);
        expect(model.error, isNull);
        session.emit();
        await Future<void>.delayed(Duration.zero);
        expect(model.screen, Screen.pairing);
      },
    );
  }
  test(
    'exit during Apply cannot hide the library or send a stale rollback',
    () async {
      final host = RecordingHost(), session = PausedSession();
      final model = PrototypeModel('/unused', host: host, gameSession: session);
      model.screen = Screen.pairing;
      model.pairing = Pairing(1)..join(10);
      session.emit();
      session.pauseAck = Completer<void>();
      final applying = model.play();
      await Future<void>.delayed(Duration.zero);
      session.exit(1);
      session.pauseAck!.completeError(StateError('The emulator exited'));
      await applying;
      expect(model.screen, Screen.library);
      expect(model.busy, isFalse);
      expect(session.commands, 1);
      expect(host.hidden, 0);
      expect(host.shown, 1);
    },
  );
  test('failed Apply and failed pause rollback leave pairing usable', () async {
    final host = RecordingHost(), session = PausedSession();
    final model = PrototypeModel('/unused', host: host, gameSession: session);
    model.screen = Screen.pairing;
    model.pairing = Pairing(1)..join(10);
    session.emit();
    session.failCommands = true;
    await model.play();
    expect(model.screen, Screen.pairing);
    expect(model.busy, isFalse);
    expect(model.error, contains('Could not request pause'));
    expect(host.shown, 1);
    session.failCommands = false;
    await model.play();
    expect(model.screen, Screen.playing);
    expect(host.hidden, 1);
  });
  test('menu presentation waits for pause acknowledgement and ignores duplicate events', () async {
    final host = RecordingHost(), session = PausedSession();
    final model = PrototypeModel('/unused', host: host, gameSession: session);
    model.screen = Screen.playing;
    model.pairing = Pairing(4)..join(10);
    session.pauseAck = Completer<void>();
    session.emit(request: 'menu', serial: 1);
    expect(model.busy, isTrue);
    expect(host.shown, 0);
    session.pauseAck!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(model.screen, Screen.menu);
    expect(host.shown, 1);
    expect(model.busy, isFalse);
    session.emit(request: 'menu', serial: 1);
    await Future<void>.delayed(Duration.zero);
    expect(host.shown, 1);
  });
  test(
    'disconnect opens shared pairing and retains the connected player',
    () async {
      final host = RecordingHost(), session = PausedSession();
      final model = PrototypeModel('/unused', host: host, gameSession: session);
      model.screen = Screen.playing;
      model.pairing = Pairing(4)
        ..join(10)
        ..join(11);
      session.emit(
        request: 'disconnect',
        serial: 1,
        devices: [
          {'id': 11, 'name': 'Other pad', 'buttons': 0, 'x': 0, 'y': 0},
        ],
      );
      await Future<void>.delayed(Duration.zero);
      expect(model.screen, Screen.pairing);
      expect(model.pairing!.players.single.deviceId, 11);
      expect(model.notice, contains('disconnected'));
      expect(session.commands, 0);
      expect(host.shown, 1);
    },
  );
  test('Start cannot launch or apply while native pause is unknown', () async {
    final session = PausedSession();
    final model = PrototypeModel(
      '/unused',
      host: RecordingHost(),
      gameSession: session,
    );
    model.screen = Screen.pairing;
    model.pairing = Pairing(1)..join(10);
    session.emit(paused: -1);
    session.emit(
      paused: -1,
      devices: [
        {'id': 10, 'name': 'Pad', 'buttons': 64, 'x': 0, 'y': 0},
      ],
    );
    await Future<void>.delayed(Duration.zero);
    expect(model.canPlay, isFalse);
    expect(session.commands, 0);
  });
}
