import 'dart:async';

import 'package:broomm/src/app_model.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/shell/game_session_screen.dart';
import 'package:broomm/src/shell/controls.dart';
import 'package:broomm/src/shell/quit_dialog.dart';
import 'package:broomm/src/widgets/pairing_screen.dart';
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
  for (final action in ['pairing', 'close', 'resume']) {
    testWidgets(
      'settings overlay can $action through native controller input',
      (t) async {
        final session = NavigationSession()..alive = false;
        final model = PrototypeModel(
          '/unused',
          host: RecordingHost(),
          gameSession: session,
        );
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
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
        );
        Future<void> controller(String input) async {
          await t.binding.defaultBinaryMessenger.handlePlatformMessage(
            'app.broomm/prototype',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('controller', input),
            ),
            (_) {},
          );
          await t.pump();
        }

        await t.tap(find.text('Home game'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        session.emit();
        await t.pumpAndSettle();
        model.join(10);
        await model.play();
        session.pauseAck = Completer<void>();
        session.emit(request: 'menu', serial: 1);
        await t.pumpAndSettle();
        await controller('down');
        await controller('accept');
        expect(session.stops, 0);
        expect(model.screen, Screen.menu);
        session.pauseAck!.complete();
        await t.pumpAndSettle();
        expect(find.text('Settings overlay'), findsOneWidget);
        if (action == 'pairing') {
          await controller('down');
          await controller('up');
          await controller('accept');
          expect(model.screen, Screen.pairing);
          final commands = session.commands;
          await controller('home');
          expect(session.commands, commands);
        } else if (action == 'close') {
          await controller('down');
          await controller('accept');
          await t.pumpAndSettle();
          expect(session.stops, 1);
          expect(find.text('Home game'), findsOneWidget);
        } else {
          await controller('home');
          await t.pumpAndSettle();
          expect(model.screen, Screen.playing);
          expect(session.stops, 0);
        }
        await t.pumpWidget(const SizedBox());
        model.dispose();
      },
    );
  }

  testWidgets(
    'native Quit is acknowledged immediately and game exit leaves the closing dialog available above Home',
    (t) async {
      final session = NavigationSession()..alive = false;
      final model = PrototypeModel(
        '/unused',
        host: RecordingHost(),
        gameSession: session,
      );
      final finish = Completer<void>();
      var exits = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (routeContext) => GameSessionScreen(
                    model: model,
                    game: testGames.first,
                    closeRequested: () => showQuitDialog(
                      context,
                      finish: (_) => finish.future,
                      exit: () async {
                        exits++;
                      },
                    ),
                  ),
                ),
              ),
              child: const Text('Home game'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Home game'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      session.emit();
      await t.pumpAndSettle();
      final reply = Completer<Object?>();
      await t.binding.defaultBinaryMessenger.handlePlatformMessage(
        'app.broomm/prototype',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('closeRequested'),
        ),
        (data) =>
            reply.complete(const StandardMethodCodec().decodeEnvelope(data!)),
      );
      expect(await reply.future, true);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Closing Broomm'), findsOneWidget);
      session.exit(0);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Closing Broomm'), findsOneWidget);
      expect(exits, 0);
      finish.complete();
      await t.pumpAndSettle();
      expect(find.text('Home game'), findsOneWidget);
      expect(exits, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

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
        const Size(600, 340),
        const Size(1180, 800),
        const Size(1600, 900),
      ]) {
        await t.binding.setSurfaceSize(size);
        await t.pumpAndSettle();
        expect(find.text('PLAYER 1'), findsOneWidget);
        expect(find.text('PLAYER 2'), findsOneWidget);
        expect(find.text('PLAYER 3'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(PairingScreen),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );
        expect(find.text('Apply & play').hitTestable(), findsOneWidget);
        expect(find.text('Cancel game').hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull, reason: 'pairing $size');
      }
      await t.binding.setSurfaceSize(const Size(573, 413));
      session.emit(
        devices: [
          for (var id = 10; id < 14; id++)
            {
              'id': id,
              'name': 'Controller with a long name $id',
              'buttons': 0,
              'x': 0,
              'y': 0,
              'sensors': 3,
              'sensorReady': 3,
            },
        ],
      );
      for (var id = 11; id < 14; id++) {
        model.join(id);
      }
      await t.pumpAndSettle();
      for (var player = 1; player <= 4; player++) {
        expect(find.text('PLAYER $player'), findsOneWidget);
      }
      expect(find.text('Apply & play').hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'four Wii motion controllers');
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
