import 'dart:io';
import 'dart:async';

import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/shell/controls.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_model_test.dart' show FixtureRomm, settleModel;

void main() {
  late Directory root;
  late ShellModel model;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-shell-widgets-');
    model = ShellModel(ShellStorage(root), clientFactory: FixtureRomm.new);
    await model.start();
  });
  tearDown(() async {
    await model.finishDownloads();
    model.dispose();
    await root.delete(recursive: true);
  });
  Future<void> resize(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.binding.setSurfaceSize(size);
  }

  Future<void> press(
    WidgetTester t,
    LogicalKeyboardKey key, {
    bool io = false,
  }) async {
    if (io) {
      await t.runAsync(() async {
        await t.sendKeyEvent(key);
        await Future<void>.delayed(Duration.zero);
        if (model.busy) {
          final idle = Completer<void>();
          void listener() {
            if (!model.busy && !idle.isCompleted) idle.complete();
          }

          model.addListener(listener);
          try {
            await idle.future.timeout(const Duration(seconds: 3));
          } finally {
            model.removeListener(listener);
          }
        }
      });
    } else {
      await t.sendKeyEvent(key);
    }
    await t.pumpAndSettle();
  }

  final keyboard = find.byKey(const ValueKey('console-keyboard'));
  final keyboardText = find.byWidgetPredicate(
    (w) => w is TextField && w.showCursor == true,
  );
  Future<void> keyboardType(WidgetTester t, String value) async {
    for (final ch in value.characters) {
      Finder key() => find.byWidgetPredicate(
        (w) => w is ConsoleButton && w.label == (ch == ' ' ? 'Space' : ch),
      );
      if (key().evaluate().isEmpty) {
        await t.tap(
          find
              .byWidgetPredicate(
                (w) => w is ConsoleButton && w.label == 'Shift',
              )
              .first,
        );
        await t.pump();
      }
      await t.tap(key());
      await t.pump();
    }
  }

  Future<void> nativeInput(WidgetTester t, String action) async {
    await t.binding.defaultBinaryMessenger.handlePlatformMessage(
      'app.broomm/prototype',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('controller', action),
      ),
      (_) {},
    );
    await t.pumpAndSettle();
  }

  Future<void> openHome(
    WidgetTester t, {
    Size size = const Size(1180, 800),
  }) async {
    await resize(t, size);
    await t.runAsync(() async {
      await model.addServer('https://server.example');
      await model.login('Player', 'pass');
      await settleModel(model);
    });
    await t.pumpWidget(BroommApp(model: model));
    await t.pumpAndSettle();
  }

  testWidgets('first run and text entry are reachable with gamepad actions', (
    t,
  ) async {
    await resize(t, const Size(1180, 800));
    await t.pumpWidget(BroommApp(model: model));
    await t.pumpAndSettle();
    expect(find.text('Connect your server'), findsOneWidget);
    expect(find.text('Game Store'), findsNothing);
    await press(t, LogicalKeyboardKey.gameButtonA);
    expect(keyboard, findsOneWidget);
    await press(t, LogicalKeyboardKey.gameButtonA);
    expect(t.widget<TextField>(keyboardText).controller!.text, '1');
    await press(t, LogicalKeyboardKey.arrowRight);
    await press(t, LogicalKeyboardKey.gameButtonA);
    expect(t.widget<TextField>(keyboardText).controller!.text, '12');
    await press(t, LogicalKeyboardKey.gameButtonB);
    expect(keyboard, findsNothing);
    await press(t, LogicalKeyboardKey.gameButtonA);
    expect(keyboard, findsOneWidget);
    await press(t, LogicalKeyboardKey.gameButtonB);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'pointer and keyboard edit inline, preserve caret keys, and switch to controller on demand',
    (t) async {
      await resize(t, const Size(1180, 800));
      await t.pumpWidget(BroommApp(model: model));
      await t.pumpAndSettle();
      final address = find.byKey(const ValueKey('field-Server address'));
      await t.tap(address);
      await t.enterText(address, 'https://server.example');
      await t.pumpAndSettle();
      expect(keyboard, findsNothing);
      final field = t.widget<TextField>(address);
      await press(t, LogicalKeyboardKey.arrowLeft);
      expect(
        field.controller!.selection.baseOffset,
        field.controller!.text.length - 1,
      );
      expect(field.focusNode!.hasFocus, true);
      await press(t, LogicalKeyboardKey.home);
      expect(model.screen, ShellScreen.servers);
      await press(t, LogicalKeyboardKey.enter);
      expect(keyboard, findsNothing);
      await t.tap(address);
      await nativeInput(t, 'accept');
      expect(
        t.widget<TextField>(keyboardText).controller!.text,
        'https://server.example',
      );
      await press(t, LogicalKeyboardKey.gameButtonB);
      await t.tap(address);
      await t.enterText(address, 'https://second.example');
      await t.pumpAndSettle();
      expect(keyboard, findsNothing);
      expect(
        t.widget<TextField>(address).controller!.text,
        'https://second.example',
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'login uses native inline username and obscured password with keyboard traversal',
    (t) async {
      await resize(t, const Size(1180, 800));
      await t.runAsync(() => model.addServer('https://server.example'));
      await t.pumpWidget(BroommApp(model: model));
      await t.pumpAndSettle();
      await press(t, LogicalKeyboardKey.gameButtonA);
      final username = find.byKey(const ValueKey('field-Username'));
      final password = find.byKey(const ValueKey('field-Password'));
      await t.tap(username);
      await t.enterText(username, 'Player');
      await press(t, LogicalKeyboardKey.tab);
      expect(t.widget<TextField>(password).readOnly, true);
      expect(t.widget<TextField>(password).focusNode!.hasFocus, false);
      await press(t, LogicalKeyboardKey.enter);
      expect(t.widget<TextField>(password).focusNode!.hasFocus, true);
      await t.enterText(password, 'private-password');
      expect(t.widget<TextField>(password).obscureText, true);
      expect(keyboard, findsNothing);
      await nativeInput(t, 'accept');
      expect(t.widget<TextField>(keyboardText).obscureText, true);
      await press(t, LogicalKeyboardKey.gameButtonB);
      expect(
        t.widget<TextField>(password).controller!.text,
        'private-password',
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'store search accepts direct typing and only opens the virtual keyboard for a controller',
    (t) async {
      await openHome(t);
      model.navigate(ShellScreen.store);
      await t.pumpAndSettle();
      final search = find.byKey(const ValueKey('field-Search games'));
      await t.tap(search);
      await t.enterText(search, 'Adventure');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(model.search, 'Adventure');
      expect(keyboard, findsNothing);
      await press(t, LogicalKeyboardKey.gameButtonX);
      expect(keyboard, findsOneWidget);
      await press(t, LogicalKeyboardKey.gameButtonB);
      await t.tap(search);
      expect(keyboard, findsNothing);
      await nativeInput(t, 'accept');
      expect(t.widget<TextField>(keyboardText).controller!.text, 'Adventure');
      await press(t, LogicalKeyboardKey.gameButtonB);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'three home apps, settings and back work with controller navigation',
    (t) async {
      await openHome(t);
      expect(
        find.byWidgetPredicate(
          (w) => w is ConsoleButton && w.label == 'Broomm settings',
        ),
        findsOneWidget,
      );
      expect(find.text('Game Store'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) => w is ConsoleButton && w.label == 'Emulator Settings',
        ),
        findsOneWidget,
      );
      await press(t, LogicalKeyboardKey.arrowLeft);
      expect(model.homeIndex, 0);
      await press(t, LogicalKeyboardKey.gameButtonA);
      expect(model.screen, ShellScreen.settings);
      await press(t, LogicalKeyboardKey.gameButtonA, io: true);
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pumpAndSettle();
      expect(model.preferences.reduceMotion, true);
      await press(t, LogicalKeyboardKey.gameButtonB);
      expect(model.screen, ShellScreen.home);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'controller onboarding submits a server and account, closes login and opens Home',
    (t) async {
      await resize(t, const Size(1180, 800));
      await t.pumpWidget(BroommApp(model: model));
      await t.pumpAndSettle();
      await press(t, LogicalKeyboardKey.gameButtonA);
      await keyboardType(t, 'https://server.example');
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      await nativeInput(t, 'down');
      await press(t, LogicalKeyboardKey.gameButtonA, io: true);
      expect(model.screen, ShellScreen.profiles);
      await press(t, LogicalKeyboardKey.gameButtonA);
      expect(find.text('Sign in to RomM'), findsOneWidget);
      await press(t, LogicalKeyboardKey.gameButtonA);
      await keyboardType(t, 'Player');
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      await nativeInput(t, 'down');
      await press(t, LogicalKeyboardKey.gameButtonA);
      await keyboardType(t, 'fixture-password');
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      await nativeInput(t, 'down');
      await press(t, LogicalKeyboardKey.gameButtonA, io: true);
      expect(model.screen, ShellScreen.home);
      expect(find.text('Sign in to RomM'), findsNothing);
      expect(find.text('Game Store'), findsWidgets);
      expect(model.profile!.name, 'Player');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'native controller channel drives the same focused action as keyboard',
    (t) async {
      await openHome(t);
      Future<void> input(String action) async {
        await t.binding.defaultBinaryMessenger.handlePlatformMessage(
          'app.broomm/prototype',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('controller', action),
          ),
          (_) {},
        );
        await t.pumpAndSettle();
      }

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await input('right');
      expect(model.homeIndex, 1);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await input('right');
      expect(model.homeIndex, 2);
      await input('accept');
      expect(model.screen, ShellScreen.emulators);
      await input('back');
      expect(model.screen, ShellScreen.home);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'store has real paginated results, platform picker and controller search',
    (t) async {
      await openHome(t);
      await press(t, LogicalKeyboardKey.gameButtonA);
      expect(model.screen, ShellScreen.store);
      expect(find.text('Recently added'), findsOneWidget);
      expect(find.text('Explore your collection'), findsOneWidget);
      await press(t, LogicalKeyboardKey.gameButtonX);
      expect(keyboard, findsOneWidget);
      await press(t, LogicalKeyboardKey.gameButtonB);
      await t.tap(find.text('All platforms'));
      await t.pumpAndSettle();
      expect(find.text('Choose a platform'), findsOneWidget);
      await press(t, LogicalKeyboardKey.arrowDown);
      await press(t, LogicalKeyboardKey.gameButtonA);
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await t.pumpAndSettle();
      expect(model.platformId, 4);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'a completed Store download offers Play and Home guides it to the required managed emulator setup',
    (t) async {
      model.dispose();
      model = ShellModel(
        ShellStorage(root),
        clientFactory: _DownloadFixture.new,
        project: Directory.current.path,
      );
      await t.runAsync(model.start);
      await openHome(t);
      await press(t, LogicalKeyboardKey.gameButtonA);
      final card = find
          .byWidgetPredicate(
            (w) => w is ConsoleButton && w.label == 'Game 1, GameCube',
          )
          .first;
      await Scrollable.ensureVisible(t.element(card));
      await t.pumpAndSettle();
      await t.tap(card);
      await t.pumpAndSettle();
      expect(find.text('Download game'), findsOneWidget);
      expect(find.text('Play'), findsNothing);
      await t.runAsync(() async {
        final done = Completer<void>();
        void listener() {
          if (model.installation(1) != null &&
              !model.downloading &&
              model.queuedGame(1) == null &&
              !done.isCompleted)
            done.complete();
        }

        model.addListener(listener);
        try {
          await t.tap(find.text('Download game'));
          await done.future.timeout(const Duration(seconds: 3));
        } finally {
          model.removeListener(listener);
        }
      });
      await t.pumpAndSettle();
      expect(model.downloadError, isNull);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
      await press(t, LogicalKeyboardKey.gameButtonB);
      model.navigate(ShellScreen.home);
      await t.pumpAndSettle();
      model.homeSelection(2);
      await t.pumpAndSettle();
      final gameTile = find.byWidgetPredicate(
        (w) => w is ConsoleButton && w.label == 'Game 1',
      );
      expect(gameTile, findsOneWidget);
      await t.tap(gameTile);
      await t.pumpAndSettle();
      await t.runAsync(() async {
        for (
          var i = 0;
          i < 100 && model.emulators.plan == null && model.emulators.supported;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await t.pumpAndSettle();
      expect(
        model.screen,
        ShellScreen.emulators,
        reason:
            'Launch status: ${model.error}; active=${model.gameActive}; ${model.notice?.message}',
      );
      expect(
        find.byKey(const ValueKey('emulator-card-4:dolphin')),
        findsOneWidget,
      );
      expect(find.text('Set up tested emulators'), findsNothing);
      await press(t, LogicalKeyboardKey.gameButtonB);
      await nativeInput(t, 'accept');
      expect(model.screen, ShellScreen.emulators);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'onboarding, home, store and settings fit narrow touch and desktop layouts',
    (t) async {
      final report = FlutterError.onError!;
      FlutterError.onError = (details) {
        debugPrint(details.toString());
        report(details);
      };
      addTearDown(() {
        FlutterError.onError = report;
      });
      for (final size in [
        const Size(390, 844),
        const Size(860, 620),
        const Size(1600, 900),
      ]) {
        await resize(t, size);
        await t.pumpWidget(BroommApp(model: model));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'onboarding $size');
        await t.pumpWidget(const SizedBox());
      }
      await t.runAsync(() async {
        await model.addServer('https://server.example');
        await model.login('Player', 'pass');
        await settleModel(model);
      });
      for (final size in [
        const Size(390, 844),
        const Size(860, 620),
        const Size(1600, 900),
      ]) {
        await resize(t, size);
        await t.pumpWidget(BroommApp(model: model));
        for (final screen in [
          ShellScreen.home,
          ShellScreen.store,
          ShellScreen.settings,
          ShellScreen.emulators,
        ]) {
          model.navigate(screen);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: '$screen $size');
        }
        await t.pumpWidget(const SizedBox());
      }
    },
  );
}

class _DownloadFixture extends FixtureRomm {
  _DownloadFixture(super.server);
  @override
  Future<RommGame> game(int id) async => RommGame(
    id: id,
    name: 'Game $id',
    platformId: 4,
    platform: 'GameCube',
    bytes: 9,
    fsName: 'game.iso',
    fullPath: 'roms/game.iso',
    files: [
      RommFile(
        id: 10,
        romId: id,
        name: 'game.iso',
        fullPath: 'roms/game.iso',
        bytes: 9,
        crc: 'cbf43926',
      ),
    ],
  );
  @override
  Future<void> downloadFile(
    RommFile file,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    cancellation.check();
    await destination.writeAsString('123456789', flush: true);
    onProgress(9);
  }
}
