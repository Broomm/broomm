import 'dart:async';

import 'package:broomm/src/app_model.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/shell/game_session_screen.dart';
import 'package:broomm/src/shell/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overlay_state_test.dart' show PausedSession, RecordingHost;

class NavigationSession extends PausedSession {
  int stops = 0;
  @override
  Future<void> stop() async {
    stops++;
    exit(0);
  }
}

class PreparingSession extends PausedSession {
  final release = Completer<void>();
  @override
  Future<void> launch(TestGame selected) async {
    await release.future;
    await super.launch(selected);
  }
}

void main() {
  testWidgets(
    'RPCS3 loading shows native phase progress and returns to indeterminate between phases without enabling pairing',
    (t) async {
      final session = NavigationSession()..alive = false;
      final model = PrototypeModel(
        '/unused',
        host: RecordingHost(),
        gameSession: session,
      );
      final game = LaunchGame(
        'rpc',
        'Game',
        'PlayStation 3',
        'RPCS3',
        '/unused.iso',
        4,
        0,
        target: ControllerTarget.ps3,
      );
      await t.pumpWidget(
        MaterialApp(
          home: GameSessionScreen(model: model, game: game),
        ),
      );
      await t.pump();
      session.emit(
        inputReady: false,
        paused: -1,
        loading: {
          'filesTotal': 10,
          'filesDone': 2,
          'modulesTotal': 100,
          'modulesDone': 25,
          'totalBits': 0,
          'knownBits': 0,
        },
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Files 2 / 10 · Modules 25 / 100'), findsOneWidget);
      expect(
        t
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .25,
      );
      expect(model.screen, Screen.loading);
      expect(model.canPair, false);
      session.emit(inputReady: false, paused: -1);
      await t.pump();
      expect(
        t
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
      expect(model.canPair, false);
      await t.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  testWidgets(
    'controller navigation reaches launcher dialogs before an emulator exists and after it exits, while live pairing keeps its own input',
    (t) async {
      final session = PreparingSession()..alive = false;
      final host = RecordingHost();
      final model = PrototypeModel('/unused', host: host, gameSession: session);
      final events = <String>[];
      var cancels = 0;
      session.cancelProgressTransfer = () => cancels++;
      await t.pumpWidget(
        MaterialApp(
          home: GameSessionScreen(
            model: model,
            game: testGames.first,
            launcherController: events.add,
          ),
        ),
      );
      await t.pump();
      Future<void> controller(String value) async {
        await t.binding.defaultBinaryMessenger.handlePlatformMessage(
          'app.broomm/prototype',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('controller', value),
          ),
          (_) {},
        );
        await t.pump();
      }

      expect(model.screen, Screen.loading);
      await controller('down');
      expect(events, ['down']);
      session.release.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      session.emit();
      await t.pumpAndSettle();
      expect(model.screen, Screen.pairing);
      await controller('accept');
      expect(events, ['down']);
      session.alive = false;
      session.finalizingProgress = true;
      session.onFinalizingProgress!();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await controller('accept');
      expect(events, ['down', 'accept']);
      expect(find.text('Syncing progress…'), findsOneWidget);
      final cancel = find.widgetWithText(
        ConsoleButton,
        'Keep local save and finish later',
      );
      await t.ensureVisible(cancel);
      await t.tap(cancel);
      await t.pump();
      expect(cancels, 1);
      expect(host.shown, greaterThan(1));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  for (final action in ['Cancel game', 'Apply & play']) {
    testWidgets('pairing Enter activates the focused $action action', (
      t,
    ) async {
      final session = NavigationSession()..alive = false;
      final model = PrototypeModel(
        '/unused',
        host: RecordingHost(),
        gameSession: session,
      );
      await t.binding.setSurfaceSize(const Size(640, 480));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        GameSessionScreen(model: model, game: testGames.first),
                  ),
                ),
                child: const Text('Home game'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Home game'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Loading RetroArch…'), findsOneWidget);
      expect(
        t.takeException(),
        isNull,
        reason: 'short loading window must scroll',
      );
      session.emit();
      await t.pumpAndSettle();
      model.join(10);
      await t.pumpAndSettle();
      expect(model.canPlay, true);
      final button = find.widgetWithText(ConsoleButton, action);
      t
          .widget<FocusableActionDetector>(
            find.descendant(
              of: button,
              matching: find.byType(FocusableActionDetector),
            ),
          )
          .focusNode!
          .requestFocus();
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      if (action == 'Cancel game') {
        expect(session.stops, 1);
        expect(session.applied.any((command) => command.$2), false);
        expect(find.text('Home game'), findsOneWidget);
      } else {
        expect(session.stops, 0);
        expect(session.applied.any((command) => command.$2), true);
        expect(model.screen, Screen.playing);
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      model.dispose();
      await t.binding.setSurfaceSize(null);
    });
  }
  testWidgets(
    'the Home session route gates pairing on readiness and returns after a real exit observation',
    (t) async {
      final session = PausedSession()..alive = false;
      final model =
          PrototypeModel('/unused', host: RecordingHost(), gameSession: session)
            ..screen = Screen.loading
            ..loadingGame = testGames.first;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        GameSessionScreen(model: model, game: testGames.first),
                  ),
                ),
                child: const Text('Home game'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Home game'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Loading RetroArch…'), findsOneWidget);
      expect(find.text('PLAYER 1'), findsNothing);
      session.emit(inputReady: false);
      await t.pump();
      expect(find.text('PLAYER 1'), findsNothing);
      session.emit(inputReady: true, paused: 1, blocked: true);
      await t.pumpAndSettle();
      expect(find.text('Controller pairing'), findsOneWidget);
      expect(find.text('CONTROLLER LAB'), findsNothing);
      expect(find.text('PLAYER 1'), findsOneWidget);
      expect(find.text('PLAYER 2'), findsNothing);
      model.join(10);
      await t.pump();
      expect(find.text('PLAYER 2'), findsOneWidget);
      session.exit(0);
      await t.pumpAndSettle();
      expect(find.text('Home game'), findsOneWidget);
      expect(find.text('Controller pairing'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  testWidgets(
    'the redesigned Wii pairing route remains usable at phone and desktop sizes and survives emulator failure',
    (t) async {
      final session = PausedSession()..alive = false;
      const game = LaunchGame(
        'catalogue-wii',
        'Catalogue Wii game',
        'Nintendo Wii',
        'Dolphin',
        '/local/game.rvz',
        4,
        0xff539388,
        target: ControllerTarget.wii,
      );
      final model =
          PrototypeModel('/unused', host: RecordingHost(), gameSession: session)
            ..screen = Screen.loading
            ..loadingGame = game;
      await t.binding.setSurfaceSize(const Size(1180, 800));
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GameSessionScreen(model: model, game: game),
                  ),
                ),
                child: const Text('Home game'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Home game'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      session.emit();
      await t.pumpAndSettle();
      model.join(10);
      for (final size in [
        const Size(390, 844),
        const Size(1180, 800),
        const Size(1600, 900),
      ]) {
        await t.binding.setSurfaceSize(size);
        await t.pumpAndSettle();
        expect(find.text('PLAYER 1'), findsOneWidget);
        expect(find.text('PLAYER 2'), findsOneWidget);
        expect(find.text('PLAYER 3'), findsNothing);
        expect(t.takeException(), isNull, reason: 'pairing $size');
      }
      session.exit(17);
      await t.pumpAndSettle();
      expect(model.error, contains('17'));
      expect(find.text('Home game'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      model.dispose();
      await t.binding.setSurfaceSize(null);
    },
  );
}
