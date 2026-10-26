import 'dart:async';
import 'dart:io';

import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/controls.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/navigation.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_model_test.dart' show FixtureRomm, settleModel;

class NavigationRomm extends FixtureRomm {
  NavigationRomm(super.server);
  @override
  Future<RommGame> game(int id) async => RommGame(
    id: id,
    name: 'Game $id',
    platformId: 4,
    platform: 'GameCube',
    summary: List.generate(
      35,
      (i) =>
          'Chapter $i. Explore a distant world, meet its inhabitants, and find the route home.',
    ).join('\n\n'),
  );
}

FocusNode buttonNode(WidgetTester t, Finder button) => t
    .widget<FocusableActionDetector>(
      find
          .descendant(
            of: button,
            matching: find.byType(FocusableActionDetector),
          )
          .first,
    )
    .focusNode!;

Finder labelled(String label) =>
    find.byWidgetPredicate((w) => w is ConsoleButton && w.label == label);

Future<void> arrow(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(key);
  await t.pumpAndSettle();
}

Future<void> native(WidgetTester t, String value) async {
  await t.binding.defaultBinaryMessenger.handlePlatformMessage(
    'app.broomm/prototype',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('controller', value),
    ),
    (_) {},
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'a horizontal center zone scrolls a still-visible selection toward the middle in either direction',
    (t) async {
      final scroll = ScrollController();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Shortcuts(
              shortcuts: consoleShortcuts,
              child: FocusTraversalGroup(
                policy: ConsoleTraversalPolicy(),
                child: SizedBox(
                  width: 600,
                  height: 120,
                  child: ConsoleScrollView(
                    controller: scroll,
                    scrollDirection: Axis.horizontal,
                    centerZone: .18,
                    child: Row(
                      children: [
                        for (var i = 0; i < 10; i++)
                          SizedBox(
                            width: 100,
                            child: ConsoleButton(
                              autofocus: i == 0,
                              label: 'Tile $i',
                              onPressed: () {},
                              child: Text('$i'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.getRect(labelled('Tile 4')).right, lessThan(600));
      buttonNode(t, labelled('Tile 4')).requestFocus();
      await t.pumpAndSettle();
      final forward = scroll.offset;
      expect(forward, greaterThan(0));
      expect(t.getCenter(labelled('Tile 4')).dx, inInclusiveRange(245, 355));
      buttonNode(t, labelled('Tile 2')).requestFocus();
      await t.pumpAndSettle();
      expect(scroll.offset, lessThan(forward));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
  testWidgets(
    'focus scrolls smoothly in both directions and leaves visible controls still',
    (t) async {
      final scroll = ScrollController();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Shortcuts(
              shortcuts: consoleShortcuts,
              child: FocusTraversalGroup(
                policy: ConsoleTraversalPolicy(),
                child: SizedBox(
                  height: 220,
                  width: 300,
                  child: ConsoleScrollView(
                    controller: scroll,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const SizedBox(
                          height: 40,
                          child: Text('Section heading'),
                        ),
                        for (var i = 0; i < 8; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ConsoleButton(
                              autofocus: i == 0,
                              onPressed: () {},
                              label: 'Action $i',
                              child: Text('Action $i'),
                            ),
                          ),
                        const SizedBox(
                          height: 45,
                          child: Text('End of section'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await arrow(t, LogicalKeyboardKey.arrowDown);
      expect(scroll.offset, 0);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      await t.pump(); // Start the ticker scheduled by the focus reveal.
      final before = scroll.offset;
      await t.pump(const Duration(milliseconds: 70));
      final during = scroll.offset;
      await t.pumpAndSettle();
      expect(during, greaterThan(before));
      expect(during, lessThan(scroll.offset));
      for (var i = 0; i < 5; i++) {
        await arrow(t, LogicalKeyboardKey.arrowDown);
      }
      expect(buttonNode(t, labelled('Action 7')).hasFocus, true);
      expect(scroll.offset, scroll.position.maxScrollExtent);
      expect(
        t.getRect(find.text('End of section')).bottom,
        lessThanOrEqualTo(220),
      );
      for (var i = 0; i < 7; i++) {
        await arrow(t, LogicalKeyboardKey.arrowUp);
      }
      expect(buttonNode(t, labelled('Action 0')).hasFocus, true);
      expect(scroll.offset, scroll.position.minScrollExtent);
      expect(
        t.getRect(find.text('Section heading')).top,
        greaterThanOrEqualTo(0),
      );
      expect(t.getRect(labelled('Action 0')).top, greaterThanOrEqualTo(0));
      requestConsoleFocus(buttonNode(t, labelled('Action 5')));
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      final interrupted = scroll.offset;
      final visible = labelled('Action 2');
      expect(t.getRect(visible).top, greaterThanOrEqualTo(0));
      expect(t.getRect(visible).bottom, lessThanOrEqualTo(220));
      requestConsoleFocus(buttonNode(t, visible));
      await t.pumpAndSettle();
      expect(
        scroll.offset,
        closeTo(interrupted, .01),
        reason: 'An obsolete animation must not scroll the new selection away.',
      );
      expect(buttonNode(t, visible).hasFocus, true);
      await t.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );

  testWidgets(
    'an async action cannot reclaim focus after navigation or accept duplicate activation',
    (t) async {
      final pending = Completer<void>();
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Shortcuts(
            shortcuts: consoleShortcuts,
            child: Scaffold(
              body: Row(
                children: [
                  ConsoleButton(
                    autofocus: true,
                    onPressed: () async {
                      calls++;
                      await pending.future;
                    },
                    child: const Text('Run'),
                  ),
                  ConsoleButton(onPressed: () {}, child: const Text('Other')),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await arrow(t, LogicalKeyboardKey.enter);
      await arrow(t, LogicalKeyboardKey.enter);
      expect(calls, 1);
      await arrow(t, LogicalKeyboardKey.arrowRight);
      final other = find.widgetWithText(ConsoleButton, 'Other');
      expect(buttonNode(t, other).hasFocus, true);
      pending.complete();
      await t.pumpAndSettle();
      expect(buttonNode(t, other).hasFocus, true);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a busy action that fails recovers its focus for retry when no newer control owns it',
    (t) async {
      var busy = false;
      var calls = 0;
      final pending = Completer<void>();
      await t.pumpWidget(
        MaterialApp(
          home: Shortcuts(
            shortcuts: consoleShortcuts,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => ConsoleButton(
                  autofocus: true,
                  onPressed: busy
                      ? null
                      : () async {
                          calls++;
                          update(() => busy = true);
                          await pending.future;
                          update(() => busy = false);
                        },
                  child: Text(busy ? 'Working' : 'Retry'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await arrow(t, LogicalKeyboardKey.enter);
      expect(find.text('Working'), findsOneWidget);
      pending.complete();
      await t.pumpAndSettle();
      expect(
        buttonNode(t, find.widgetWithText(ConsoleButton, 'Retry')).hasFocus,
        true,
      );
      await arrow(t, LogicalKeyboardKey.enter);
      expect(calls, 2);
      await t.pumpWidget(const SizedBox());
    },
  );

  group('application navigation', () {
    late Directory root;
    late ShellModel model;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('broomm-navigation-');
      model = ShellModel(ShellStorage(root), clientFactory: NavigationRomm.new);
      await model.start();
      await model.addServer('https://one.example');
      await model.login('Player', 'fixture');
      await settleModel(model);
    });
    tearDown(() async {
      model.dispose();
      await root.delete(recursive: true);
    });

    Future<void> open(
      WidgetTester t, {
      Size size = const Size(860, 620),
    }) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = size;
      await t.binding.setSurfaceSize(size);
      addTearDown(() async {
        await t.binding.setSurfaceSize(null);
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await t.pumpWidget(BroommApp(model: model));
      await t.pumpAndSettle();
    }

    testWidgets(
      'Home action returns to its selected tile, rail edges stop, and Back restores selection',
      (t) async {
        await open(t, size: const Size(390, 844));
        await native(t, 'right');
        expect(model.homeIndex, 2);
        final tile = labelled('Emulator Settings');
        await native(t, 'up');
        expect(buttonNode(t, tile).hasFocus, true);
        await native(t, 'down');
        await native(t, 'down');
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          startsWith('Footer'),
        );
        await native(t, 'right');
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'Footer profile',
        );
        await native(t, 'up');
        await native(t, 'up');
        expect(buttonNode(t, tile).hasFocus, true);
        await native(t, 'down');
        expect(
          buttonNode(t, find.widgetWithText(ConsoleButton, 'Open')).hasFocus,
          true,
        );
        await arrow(t, LogicalKeyboardKey.arrowUp);
        expect(buttonNode(t, tile).hasFocus, true);
        await native(t, 'right');
        expect(buttonNode(t, tile).hasFocus, true);
        expect(t.getRect(tile).right, lessThanOrEqualTo(390));
        await arrow(t, LogicalKeyboardKey.arrowLeft);
        await arrow(t, LogicalKeyboardKey.arrowLeft);
        await arrow(t, LogicalKeyboardKey.arrowLeft);
        expect(buttonNode(t, labelled('Broomm settings')).hasFocus, true);
        await native(t, 'accept');
        expect(model.screen, ShellScreen.settings);
        await native(t, 'back');
        expect(buttonNode(t, labelled('Broomm settings')).hasFocus, true);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'a narrow Store grid reaches unbuilt rows, stops at row edges and focuses newly loaded games',
      (t) async {
        await model.browse(term: 'Game');
        model.navigate(ShellScreen.store);
        await open(t, size: const Size(390, 620));
        final first = labelled('Game 0, GameCube');
        expect(first, findsOneWidget);
        expect(labelled('Game 22, GameCube'), findsNothing);
        requestConsoleFocus(buttonNode(t, first));
        await t.pumpAndSettle();
        await arrow(t, LogicalKeyboardKey.arrowLeft);
        expect(buttonNode(t, first).hasFocus, true);
        // Two columns at this width; alternate native and keyboard input.
        for (var i = 1; i <= 11; i++) {
          if (i.isEven) {
            await native(t, 'down');
          } else {
            await arrow(t, LogicalKeyboardKey.arrowDown);
          }
          final card = labelled('Game ${i * 2}, GameCube');
          expect(card, findsOneWidget, reason: 'row $i must materialize');
          expect(
            buttonNode(t, card).hasFocus,
            true,
            reason: 'row $i must retain its column',
          );
          expect(t.getRect(card).bottom, lessThan(590));
        }
        await native(t, 'right');
        final last = labelled('Game 23, GameCube');
        expect(buttonNode(t, last).hasFocus, true);
        await native(t, 'right');
        expect(buttonNode(t, last).hasFocus, true);
        // A footer excursion retains the scrolled selection in its scope.
        requestConsoleFocus(buttonNode(t, labelled('Switch profile')));
        await t.pumpAndSettle();
        await native(t, 'up');
        expect(buttonNode(t, last).hasFocus, true);
        await native(t, 'down');
        expect(
          buttonNode(
            t,
            find.widgetWithText(ConsoleButton, 'Load more games'),
          ).hasFocus,
          true,
        );
        await native(t, 'accept');
        expect(model.page!.games.length, 26);
        expect(buttonNode(t, labelled('Game 24, GameCube')).hasFocus, true);
        await native(t, 'down');
        expect(buttonNode(t, labelled('Game 24, GameCube')).hasFocus, true);
        final store = find.byKey(const PageStorageKey('store-scroll'));
        final scroll = t.widget<CustomScrollView>(store).controller!;
        expect(scroll.offset, scroll.position.maxScrollExtent);
        expect(
          t.getRect(find.text('You’re all caught up')).bottom,
          lessThanOrEqualTo(t.getRect(store).bottom),
        );
        for (var i = 0; i < 12; i++) {
          await native(t, 'up');
        }
        expect(buttonNode(t, first).hasFocus, true);
        final field = find.byKey(const ValueKey('field-Search games'));
        final fieldFocus = t
            .widgetList<Focus>(
              find.ancestor(of: field, matching: find.byType(Focus)),
            )
            .firstWhere(
              (w) =>
                  w.focusNode != null &&
                  w.focusNode!.canRequestFocus &&
                  !w.focusNode!.skipTraversal,
            )
            .focusNode!;
        for (var i = 0; i < 4 && !fieldFocus.hasFocus; i++) {
          await arrow(t, LogicalKeyboardKey.arrowUp);
        }
        expect(fieldFocus.hasFocus, true);
        expect(scroll.offset, scroll.position.minScrollExtent);
        expect(
          t.getRect(find.text('Game Store')).top,
          greaterThanOrEqualTo(t.getRect(store).top),
        );
        expect(
          t.getRect(find.text('Search games')).top,
          greaterThanOrEqualTo(t.getRect(store).top),
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'the recent rail reveals both edges and details returns to the selected card',
      (t) async {
        model.navigate(ShellScreen.store);
        await open(t, size: const Size(390, 844));
        final first = labelled('Game 0, GameCube').first;
        requestConsoleFocus(buttonNode(t, first));
        await t.pumpAndSettle();
        for (var i = 0; i < 9; i++) {
          await native(t, 'right');
        }
        final last = labelled('Game 9, GameCube').first;
        expect(buttonNode(t, last).hasFocus, true);
        expect(t.getRect(last).right, lessThan(390));
        await native(t, 'right');
        expect(buttonNode(t, last).hasFocus, true);
        await native(t, 'accept');
        expect(find.text('Add to your library'), findsOneWidget);
        await native(t, 'back');
        expect(buttonNode(t, last).hasFocus, true);
        for (var i = 0; i < 9; i++) {
          await arrow(t, LogicalKeyboardKey.arrowLeft);
        }
        expect(buttonNode(t, first).hasFocus, true);
        expect(t.getRect(first).left, greaterThanOrEqualTo(0));
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'saved server startup has focus and native Back ends inline editing before leaving a form',
      (t) async {
        model.changeServer();
        await open(t);
        final saved = find.widgetWithText(ConsoleButton, 'one.example');
        expect(buttonNode(t, saved).hasFocus, true);
        final field = find.byKey(const ValueKey('field-Server address'));
        await native(t, 'down');
        await arrow(t, LogicalKeyboardKey.enter);
        await t.enterText(field, 'https://two.example');
        await native(t, 'back');
        expect(t.widget<TextField>(field).readOnly, true);
        expect(model.screen, ShellScreen.servers);
        await arrow(t, LogicalKeyboardKey.enter);
        expect(t.widget<TextField>(field).readOnly, false);
        expect(
          t.widget<TextField>(field).controller!.text,
          'https://two.example',
        );
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'native controller activation operates standard password visibility controls and restores form focus',
      (t) async {
        model.switchAccount();
        await open(t);
        await native(t, 'down');
        await native(t, 'accept');
        await native(t, 'down');
        await native(t, 'accept');
        final text = find.byKey(const ValueKey('field-Password'));
        expect(t.widget<TextField>(text).obscureText, true);
        final visibility = find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Show password',
        );
        t.widget<IconButton>(visibility).focusNode!.requestFocus();
        await t.pumpAndSettle();
        await native(t, 'accept');
        expect(t.widget<TextField>(text).obscureText, false);
        await native(t, 'accept');
        expect(t.widget<TextField>(text).obscureText, true);
        await native(t, 'back');
        final password = find.byKey(const ValueKey('field-Password'));
        expect(t.widget<TextField>(password).readOnly, true);
        await arrow(t, LogicalKeyboardKey.enter);
        expect(t.widget<TextField>(password).readOnly, false);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'held arrows traverse unbuilt rows without losing input and held Enter activates only once',
      (t) async {
        await model.browse(term: 'Game');
        model.navigate(ShellScreen.store);
        await open(t, size: const Size(390, 620));
        requestConsoleFocus(buttonNode(t, labelled('Game 0, GameCube')));
        await t.pumpAndSettle();
        await t.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await t.pump(const Duration(milliseconds: 30));
        for (var i = 0; i < 5; i++) {
          await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
          await t.pump(const Duration(milliseconds: 30));
        }
        await t.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await t.pumpAndSettle();
        expect(buttonNode(t, labelled('Game 12, GameCube')).hasFocus, true);
        expect(t.getRect(labelled('Game 12, GameCube')).bottom, lessThan(590));
        model.navigate(ShellScreen.home);
        await t.pumpAndSettle();
        await arrow(t, LogicalKeyboardKey.arrowLeft);
        await t.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        expect(model.screen, ShellScreen.settings);
        await t.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(model.preferences.reduceMotion, false);
        await t.sendKeyUpEvent(LogicalKeyboardKey.enter);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'an async action completing behind a modal leaves navigation with the dialog',
      (t) async {
        final pending = Completer<void>();
        final navigator = GlobalKey<NavigatorState>();
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: Shortcuts(
              shortcuts: consoleShortcuts,
              child: Scaffold(
                body: ConsoleButton(
                  autofocus: true,
                  onPressed: () => pending.future,
                  child: const Text('Begin'),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await arrow(t, LogicalKeyboardKey.enter);
        final dialog = showConsoleDialog<void>(
          context: navigator.currentContext!,
          builder: (context) => Dialog(
            child: ConsoleButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('Close dialog'),
            ),
          ),
        );
        await t.pumpAndSettle();
        pending.complete();
        await t.pumpAndSettle();
        expect(
          buttonNode(
            t,
            find.widgetWithText(ConsoleButton, 'Close dialog'),
          ).hasFocus,
          true,
        );
        await t.tap(find.text('Close dialog'));
        await t.pumpAndSettle();
        await dialog;
        expect(
          buttonNode(t, find.widgetWithText(ConsoleButton, 'Begin')).hasFocus,
          true,
        );
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'long game descriptions scroll with arrows and controller then return to the actions',
      (t) async {
        model.navigate(ShellScreen.store);
        await open(t, size: const Size(390, 620));
        requestConsoleFocus(buttonNode(t, labelled('Game 0, GameCube').first));
        await t.pumpAndSettle();
        await native(t, 'accept');
        await arrow(t, LogicalKeyboardKey.arrowUp);
        final description = find.byKey(
          const ValueKey('game-description-scroll'),
        );
        final scroll = t.widget<SingleChildScrollView>(description).controller!;
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'Game description',
        );
        expect(scroll.offset, 0);
        await native(t, 'down');
        expect(scroll.offset, greaterThan(0));
        await arrow(t, LogicalKeyboardKey.arrowUp);
        expect(scroll.offset, 0);
        final steps =
            (scroll.position.maxScrollExtent /
                    (scroll.position.viewportDimension * .7))
                .ceil() +
            1;
        for (
          var i = 0;
          i < steps && scroll.offset < scroll.position.maxScrollExtent;
          i++
        ) {
          await native(t, 'down');
        }
        expect(scroll.offset, scroll.position.maxScrollExtent);
        await native(t, 'down');
        expect(
          buttonNode(
            t,
            find.widgetWithText(ConsoleButton, 'Download game'),
          ).hasFocus,
          true,
        );
        await native(t, 'back');
        expect(
          buttonNode(t, labelled('Game 0, GameCube').first).hasFocus,
          true,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'platform dialog reveals the current platform and traverses a long list without escaping',
      (t) async {
        model.platforms = [
          for (var i = 0; i < 60; i++)
            RommPlatform(i, 'Platform $i', 'platform-$i', i),
        ];
        model.platformId = 59;
        model.navigate(ShellScreen.store);
        await open(t, size: const Size(390, 620));
        await t.tap(find.widgetWithText(ConsoleButton, 'Platform 59'));
        await t.pumpAndSettle();
        final last = find.byKey(const ValueKey('platform-choice-59'));
        expect(buttonNode(t, last).hasFocus, true);
        expect(t.getRect(last).bottom, lessThan(560));
        await native(t, 'up');
        expect(
          buttonNode(
            t,
            find.byKey(const ValueKey('platform-choice-58')),
          ).hasFocus,
          true,
        );
        for (var i = 0; i < 59; i++) {
          await arrow(t, LogicalKeyboardKey.arrowUp);
        }
        final all = find.widgetWithText(ConsoleButton, 'All platforms');
        expect(buttonNode(t, all).hasFocus, true);
        await native(t, 'up');
        expect(buttonNode(t, all).hasFocus, true);
        expect(t.getRect(all).top, greaterThan(0));
        await native(t, 'back');
        expect(model.platformId, 59);
        expect(find.text('Choose a platform'), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'rapid screen changes remove outgoing focus immediately and reduced motion is instant',
      (t) async {
        await t.runAsync(
          () =>
              model.savePreferences(model.preferences.copy(reduceMotion: true)),
        );
        await open(t);
        model.navigate(ShellScreen.settings);
        await t.pump();
        expect(labelled('Game Store'), findsNothing);
        final reduce = find.widgetWithText(ConsoleButton, 'Reduce motion');
        expect(buttonNode(t, reduce).hasFocus, true);
        for (var i = 0; i < 5; i++) {
          await arrow(t, LogicalKeyboardKey.arrowDown);
        }
        final selected = FocusManager.instance.primaryFocus!;
        final rect = t.getRect(find.byWidget(selected.context!.widget));
        expect(rect.top, greaterThanOrEqualTo(70));
        expect(rect.bottom, lessThanOrEqualTo(580));
        expect(t.binding.transientCallbackCount, 0);
        model.navigate(ShellScreen.home);
        await t.pump();
        expect(buttonNode(t, labelled('Game Store')).hasFocus, true);
        await t.pump(); // Flush zero-duration implicit focus decoration.
        expect(t.binding.transientCallbackCount, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  });
}
