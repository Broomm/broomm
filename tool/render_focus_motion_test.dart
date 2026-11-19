// Offscreen focus-motion fixtures only; no accounts, emulators or saved games.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:broomm/src/shell/controls.dart';
import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/home_screen.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/navigation.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/shell_model_test.dart' show FixtureRomm, settleModel;

Future<void> _loadFixtureFonts() async {
  final font = File('/System/Library/Fonts/HelveticaNeue.ttc');
  if (await font.exists()) {
    await (FontLoader(
      'Helvetica Neue',
    )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
  }
  await (FontLoader('MaterialIcons')..addFont(
        File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
            .readAsBytes()
            .then(ByteData.sublistView),
      ))
      .load();
}

void main() {
  testWidgets(
    'render circle focus during actual Home growth and Store vertical scrolling',
    (t) async {
      final output =
          Platform.environment['BROOMM_FOCUS_RENDER_ROOT'] ??
          '.tool-cache/research/focus-circle/previews';
      late Directory data;
      late ShellModel model;
      await t.runAsync(() async {
        data = await Directory.systemTemp.createTemp('broomm-focus-scroll-');
        model = ShellModel(ShellStorage(data), clientFactory: FixtureRomm.new);
        await model.start();
        await model.addServer('https://fixture.example');
        await model.login('Fixture player', 'fixture');
        await settleModel(model);
        await Directory(output).create(recursive: true);
        await _loadFixtureFonts();
      });
      model.installed = [
        for (var i = 1; i <= 8; i++)
          InstalledGame(
            RommGame(
              id: i,
              name: 'Adventure $i',
              platformId: 4,
              platform: 'GameCube',
            ),
            data,
            7,
          ),
      ];
      final boundary = GlobalKey();
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1180, 780);
      await t.binding.setSurfaceSize(const Size(1180, 780));
      await t.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: BroommApp(model: model),
        ),
      );
      Future<void> save(String name) async {
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$output/$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      Future<void> frames(String prefix) async {
        var previous = 0;
        for (final ms in [0, 50, 100, 170, 260, 380, 560]) {
          await t.pump(Duration(milliseconds: ms - previous));
          previous = ms;
          await save('$prefix-${ms.toString().padLeft(3, '0')}');
        }
        await t.pumpAndSettle();
      }

      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      final home = t.state<HomeScreenState>(find.byType(HomeScreen));
      final oldOffset = home.rail.offset;
      final oldSize = t.getSize(find.byKey(const ValueKey(1)));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await frames('home-scroll');
      expect(home.rail.offset, greaterThan(oldOffset + 20));
      expect(
        t.getSize(find.byKey(const ValueKey(1))).width,
        lessThan(oldSize.width),
      );
      // Retarget while the rail is moving in the other direction.
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      await t.pump(const Duration(milliseconds: 70));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await frames('home-reverse');
      model.navigate(ShellScreen.store);
      await t.pumpAndSettle();
      final first = find
          .byWidgetPredicate(
            (w) => w is ConsoleButton && w.label == 'Game 0, GameCube',
          )
          .last;
      final detector = find
          .descendant(of: first, matching: find.byType(FocusableActionDetector))
          .first;
      requestConsoleFocus(
        t.widget<FocusableActionDetector>(detector).focusNode!,
      );
      await t.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pumpAndSettle();
      }
      final storeScroll = t
          .widget<CustomScrollView>(find.byType(CustomScrollView).first)
          .controller!;
      storeScroll.jumpTo(
        (storeScroll.offset + 140).clamp(
          storeScroll.position.minScrollExtent,
          storeScroll.position.maxScrollExtent,
        ),
      );
      await t.pumpAndSettle();
      final storeOffset = storeScroll.offset;
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await frames('store-up');
      expect(storeScroll.offset, lessThan(storeOffset - 20));
      await t.pumpWidget(const SizedBox());
      model.dispose();
      await t.runAsync(() async {
        await model.finishDownloads();
        await model.finishCloud();
        await data.delete(recursive: true);
      });
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'render the shared outline moving through the controller keyboard',
    (t) async {
      final output =
          Platform.environment['BROOMM_FOCUS_RENDER_ROOT'] ??
          '.tool-cache/research/focus-circle/previews';
      final boundary = GlobalKey();
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1000, 650);
      await t.binding.setSurfaceSize(const Size(1000, 650));
      await t.runAsync(() async {
        await Directory(output).create(recursive: true);
        await _loadFixtureFonts();
      });
      await t.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: const Color(0xff09131d),
              textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: 'Helvetica Neue',
              ),
            ),
            builder: (context, navigator) => Shortcuts(
              shortcuts: consoleShortcuts,
              child: ConsoleKeyboardHost(child: navigator!),
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Game Store', style: TextStyle(fontSize: 30)),
                    const SizedBox(height: 32),
                    ConsoleField(
                      autofocus: true,
                      label: 'Search games',
                      value: '',
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await t.pumpAndSettle();

      Future<void> save(String name) async {
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$output/$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      await save('keyboard-000');
      for (var i = 0; i < 4; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await t.pump();
      for (var i = 1; i <= 8; i++) {
        await t.pump(const Duration(milliseconds: 45));
        await save('keyboard-${(i * 45).toString().padLeft(3, '0')}');
      }
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      await t.pump(const Duration(milliseconds: 90));
      await save('keyboard-vertical');
      await t.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      }
      await t.pump();
      await t.pump(const Duration(milliseconds: 90));
      await save('keyboard-left');
      await t.pumpWidget(const SizedBox());
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'render circle travel, interrupted expansion and a living resting outline',
    (t) async {
      final output =
          Platform.environment['BROOMM_FOCUS_RENDER_ROOT'] ??
          '.tool-cache/research/focus-circle/previews';
      final boundary = GlobalKey(), store = FocusNode(), settings = FocusNode();
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(760, 440);
      await t.binding.setSurfaceSize(const Size(760, 440));
      await t.runAsync(() async {
        await Directory(output).create(recursive: true);
        await _loadFixtureFonts();
      });
      await t.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: const Color(0xff0b1721),
              textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: 'Helvetica Neue',
              ),
            ),
            builder: (context, navigator) =>
                ConsoleKeyboardHost(child: navigator!),
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    left: 40,
                    top: 160,
                    width: 156,
                    height: 156,
                    child: ConsoleButton(
                      focusNode: store,
                      autofocus: true,
                      onPressed: () {},
                      radius: 20,
                      fill: const Color(0xff396360),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_bag_outlined, size: 42),
                          SizedBox(height: 12),
                          Text('Game Store'),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 304,
                    top: 70,
                    width: 244,
                    height: 56,
                    child: ConsoleButton(
                      focusNode: settings,
                      onPressed: () {},
                      radius: 20,
                      fill: const Color(0xff303c50),
                      child: const ActionLabel(
                        'Emulator Settings',
                        icon: Icons.memory,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Future<void> save(String name) async {
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$output/$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      await t.pumpAndSettle();
      await save('tile-000');
      settings.requestFocus();
      await t.pump();
      var previous = 0;
      for (final ms in [20, 70, 130, 210, 320, 440, 560]) {
        await t.pump(Duration(milliseconds: ms - previous));
        previous = ms;
        await save('tile-${ms.toString().padLeft(3, '0')}');
      }
      await t.pumpAndSettle();
      await save('gradient-rest-000');
      await t.pump(const Duration(seconds: 2));
      await save('gradient-rest-2000');
      store.requestFocus();
      await t.pump();
      await t
          .pump(); // Apply the focus listener's rebuild before advancing time.
      await t.pump(const Duration(milliseconds: 350));
      await save('redirect-expanding');
      settings.requestFocus();
      await t.pump();
      await t.pump();
      await save('redirect-000');
      var elapsed = 0;
      for (final ms in [40, 180, 520]) {
        await t.pump(Duration(milliseconds: ms - elapsed));
        elapsed = ms;
        await save('redirect-${ms.toString().padLeft(3, '0')}');
      }
      await t.pumpWidget(const SizedBox());
      store.dispose();
      settings.dispose();
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
}
