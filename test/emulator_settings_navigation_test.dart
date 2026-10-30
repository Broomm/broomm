import 'dart:io';
import 'dart:convert';

import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/controls.dart';
import 'package:broomm/src/shell/emulator_settings_screen.dart';
import 'package:broomm/src/shell/navigation.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_model_test.dart' show FixtureRomm, settleModel;
import 'navigation_test.dart' show buttonNode, native;
import 'support/review_emulators.dart';

class PlatformRomm extends FixtureRomm {
  PlatformRomm(super.server);
  @override
  Future<List<RommPlatform>> platforms() async => [
    const RommPlatform(10, 'A Nintendo GameCube', 'ngc', 4),
    const RommPlatform(11, 'B Nintendo Wii', 'wii', 7),
    const RommPlatform(12, 'C Unimplemented system', 'unknown-platform', 1),
  ];
}

void main() {
  late Directory root;
  late ShellModel model;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-platform-settings-');
    model = ShellModel(
      ShellStorage(root),
      project: Directory.current.path,
      clientFactory: PlatformRomm.new,
      emulatorManager: ReviewEmulators(root, project: Directory.current.path),
    );
    await model.start();
    await model.addServer('https://server.example');
    await model.login('Player', 'fixture');
    await settleModel(model);
    model.navigate(ShellScreen.emulators);
  });
  tearDown(() async {
    model.dispose();
    await root.delete(recursive: true);
  });
  Future<void> open(WidgetTester t, {Size size = const Size(1180, 800)}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    await t.binding.setSurfaceSize(size);
    await t.pumpWidget(
      BroommApp(model: model, project: Directory.current.path),
    );
    await t.pumpAndSettle();
  }

  Future<void> key(WidgetTester t, LogicalKeyboardKey key) async {
    await t.sendKeyEvent(key);
    await t.pumpAndSettle();
  }

  bool focused(WidgetTester t, String key) {
    final f = find.byKey(ValueKey(key));
    final node = t
        .widget<FocusableActionDetector>(
          find.descendant(
            of: f,
            matching: find.byType(FocusableActionDetector),
          ),
        )
        .focusNode!;
    return node.hasFocus;
  }

  Finder getScroll() => find
      .descendant(
        of: find.byType(EmulatorSettingsScreen),
        matching: find.byType(Scrollable),
      )
      .first;

  void fullyVisible(WidgetTester t, Finder element) {
    final viewport = t.getRect(getScroll());
    final rect = t.getRect(element);
    expect(
      rect.top,
      greaterThanOrEqualTo(viewport.top),
      reason: 'The card header must be visible, not just its actions.',
    );
    expect(
      rect.bottom,
      lessThanOrEqualTo(viewport.bottom),
      reason: 'The complete card and bottom padding must be visible.',
    );
  }

  testWidgets(
    'wide emulator rows use spatial directions and reveal whole cards in both directions',
    (t) async {
      final b = model.emulators.buildFor('Dolphin')!;
      model.emulators.installed[b.id] = b.hash;
      await open(t);
      expect(find.text('A Nintendo GameCube'), findsOneWidget);
      expect(find.text('B Nintendo Wii'), findsOneWidget);
      expect(
        find.text('No supported emulators for this platform yet.'),
        findsOneWidget,
      );
      await key(t, LogicalKeyboardKey.arrowRight);
      expect(
        buttonNode(
          t,
          find.widgetWithText(ConsoleButton, 'Import setup JSON'),
        ).hasFocus,
        true,
      );
      await key(t, LogicalKeyboardKey.arrowLeft);
      expect(
        buttonNode(
          t,
          find.widgetWithText(ConsoleButton, 'Refresh status'),
        ).hasFocus,
        true,
      );
      await key(t, LogicalKeyboardKey.arrowDown); // First platform's setup
      expect(focused(t, 'setup-10:dolphin'), true);
      fullyVisible(t, find.byKey(const ValueKey('emulator-card-10:dolphin')));
      await native(t, 'right');
      expect(focused(t, 'remove-10:dolphin'), true);
      await native(t, 'down');
      expect(focused(t, 'remove-11:dolphin'), true);
      fullyVisible(t, find.byKey(const ValueKey('emulator-card-11:dolphin')));
      await native(t, 'up');
      expect(focused(t, 'remove-10:dolphin'), true);
      fullyVisible(t, find.byKey(const ValueKey('emulator-card-10:dolphin')));
      await native(t, 'left');
      await key(t, LogicalKeyboardKey.arrowDown);
      expect(focused(t, 'setup-11:dolphin'), true);
      await key(t, LogicalKeyboardKey.arrowUp);
      expect(focused(t, 'setup-10:dolphin'), true);
      await t.runAsync(() async {
        await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
        for (var i = 0; i < 100 && model.emulators.plan == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await t.pumpAndSettle();
      final card = find.byKey(const ValueKey('emulator-card-10:dolphin'));
      expect(
        focused(t, 'setup-10:dolphin'),
        true,
        reason: 'review should retain setup focus',
      );
      expect(
        find.descendant(of: card, matching: find.text('Start setup')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('emulator-card-11:dolphin')),
          matching: find.text('Start setup'),
        ),
        findsNothing,
      );
      await t.binding.defaultBinaryMessenger.handlePlatformMessage(
        'app.broomm/prototype',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('controller', 'down'),
        ),
        (_) {},
      );
      await t.pumpAndSettle();
      expect(
        focused(t, 'confirm-10:dolphin'),
        true,
        reason:
            'lifecycle=${t.binding.lifecycleState}, setup=${focused(t, 'setup-10:dolphin')}, next=${focused(t, 'setup-11:dolphin')}, primary=${FocusManager.instance.primaryFocus}',
      );
      await key(t, LogicalKeyboardKey.arrowRight); // Inline Cancel, same row
      expect(
        buttonNode(t, find.widgetWithText(ConsoleButton, 'Cancel')).hasFocus,
        true,
      );
      await key(t, LogicalKeyboardKey.arrowLeft);
      await key(t, LogicalKeyboardKey.arrowDown); // Next platform
      expect(focused(t, 'setup-11:dolphin'), true);
      await key(t, LogicalKeyboardKey.arrowDown);
      expect(
        focused(t, 'setup-11:dolphin'),
        true,
        reason: 'the bottom card must not loop back to the header',
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'wrapped rows follow their actual layout and oversized setup keeps the active action visible',
    (t) async {
      final b = model.emulators.buildFor('Dolphin')!;
      model.emulators.installed[b.id] = b.hash;
      model.platforms = [
        ...model.platforms,
        for (var i = 0; i < 5; i++)
          RommPlatform(100 + i, 'Z unsupported $i', 'unknown-$i', 1),
      ];
      await open(t, size: const Size(390, 620));
      await native(t, 'down');
      expect(
        buttonNode(
          t,
          find.widgetWithText(ConsoleButton, 'Import setup JSON'),
        ).hasFocus,
        true,
      );
      await native(t, 'down');
      expect(focused(t, 'setup-10:dolphin'), true);
      fullyVisible(t, find.byKey(const ValueKey('emulator-card-10:dolphin')));
      await key(t, LogicalKeyboardKey.arrowDown);
      expect(focused(t, 'remove-10:dolphin'), true);
      await key(t, LogicalKeyboardKey.arrowDown);
      expect(focused(t, 'open-10:dolphin'), true);
      await key(t, LogicalKeyboardKey.arrowDown);
      expect(focused(t, 'setup-11:dolphin'), true);
      fullyVisible(t, find.byKey(const ValueKey('emulator-card-11:dolphin')));
      await key(t, LogicalKeyboardKey.arrowUp);
      expect(focused(t, 'open-10:dolphin'), true);
      await key(t, LogicalKeyboardKey.arrowUp);
      expect(focused(t, 'remove-10:dolphin'), true);
      fullyVisible(t, find.byKey(const ValueKey('emulator-card-10:dolphin')));
      await native(t, 'up');
      expect(focused(t, 'setup-10:dolphin'), true);
      await t.runAsync(() async {
        await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
        for (var i = 0; i < 100 && model.emulators.plan == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await t.pumpAndSettle();
      final card = find.byKey(const ValueKey('emulator-card-10:dolphin'));
      expect(
        t.getSize(card).height,
        greaterThan(t.getSize(getScroll()).height),
      );
      // Reviewing re-inspects the isolated empty installation records. The
      // configured-card shape above was synthetic; no real emulator is removed.
      await native(t, 'down'); // Start setup, without installing anything.
      expect(focused(t, 'confirm-10:dolphin'), true);
      fullyVisible(t, find.byKey(const ValueKey('confirm-10:dolphin')));
      await native(t, 'down'); // Wrapped inline Cancel
      final cancel = find.widgetWithText(ConsoleButton, 'Cancel');
      expect(buttonNode(t, cancel).hasFocus, true);
      fullyVisible(t, cancel);
      await native(t, 'accept');
      expect(focused(t, 'setup-10:dolphin'), true);
      fullyVisible(t, card);
      final refresh = find.widgetWithText(ConsoleButton, 'Refresh status');
      requestConsoleFocus(buttonNode(t, refresh));
      await t.pumpAndSettle();
      fullyVisible(t, refresh);
      // At 390x620 the explanatory header itself exceeds the available height.
      // Resize so both the heading and first control can fit before checking
      // an exact top edge; the short window must prioritize the active control.
      t.view.physicalSize = const Size(390, 844);
      await t.binding.setSurfaceSize(const Size(390, 844));
      await t.pumpAndSettle();
      requestConsoleFocus(buttonNode(t, refresh));
      await t.pumpAndSettle();
      final position = t.state<ScrollableState>(getScroll()).position;
      expect(position.pixels, position.minScrollExtent);
      expect(
        t.getRect(find.text('Emulator Settings').last).top,
        greaterThanOrEqualTo(t.getRect(getScroll()).top),
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'configured emulators expose a shared-install removal confirmation that can be cancelled without changing data',
    (t) async {
      final b = model.emulators.buildFor('Dolphin')!;
      model.emulators.installed[b.id] = b.hash;
      await open(t);
      final remove = find.byKey(const ValueKey('remove-10:dolphin'));
      expect(remove, findsOneWidget);
      await t.tap(remove);
      await t.pumpAndSettle();
      expect(find.text('Remove Dolphin?'), findsOneWidget);
      expect(
        find.textContaining('A Nintendo GameCube, B Nintendo Wii'),
        findsOneWidget,
      );
      expect(
        find.textContaining('saves, save states and downloaded games are kept'),
        findsOneWidget,
      );
      await key(
        t,
        LogicalKeyboardKey.gameButtonA,
      ); // Cancel is initially selected.
      expect(find.text('Remove Dolphin?'), findsNothing);
      expect(model.emulators.ready('Dolphin'), true);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'unconfigured cards have no default badge, including stale saved preferences',
    (t) async {
      final p = model.platforms.first;
      model.records = (await t.runAsync(
        () => model.storage.emulatorDefault(model.server!.id, 'ngc', 'dolphin'),
      ))!;
      expect(model.defaultEmulator(p), isNull);
      await open(t);
      expect(find.text('Default'), findsNothing);
      final b = model.emulators.buildFor('Dolphin')!;
      model.emulators.installed[b.id] = b.hash;
      expect(model.defaultEmulator(p), 'dolphin');
      model.emulators.installed.clear();
      expect(model.defaultEmulator(p), isNull);
      await t.pumpWidget(const SizedBox());
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
  test('default selection is per server, survives other preference changes, and rejects unavailable choices', () async {
    final p = model.platforms.first;
    final b = model.emulators.buildFor('Dolphin')!;
    model.emulators.installed[b.id] = b.hash;
    await model.setDefaultEmulator(p, 'dolphin');
    final server = model.server!;
    expect(model.records.emulatorDefaults['${server.id}:ngc'], 'dolphin');
    await model.savePreferences(model.preferences.copy(reduceMotion: true));
    expect(
      (await model.storage.load()).emulatorDefaults['${server.id}:ngc'],
      'dolphin',
    );
    await model.setDefaultEmulator(p, 'unsupported');
    expect(model.error, isNotNull);
    model.changeServer();
    await model.addServer('https://other.example');
    await model.login('Player', 'fixture');
    await settleModel(model);
    expect(
      model.records.emulatorDefaults.containsKey('${model.server!.id}:ngc'),
      false,
    );
    expect(model.defaultEmulator(model.platforms.first), 'dolphin');
    final record = jsonDecode(
      await File('${root.path}/accounts.json').readAsString(),
    );
    expect((record['emulatorDefaults'] as Map).length, 1);
  });
  test('malformed or foreign-server defaults fail at storage load and preserve the original settings', () async {
    final document = (await model.storage.load()).toJson();
    final file = File('${root.path}/accounts.json');
    document.remove('emulatorDefaults');
    await file.writeAsString(jsonEncode(document));
    expect((await model.storage.load()).emulatorDefaults, isEmpty);
    for (final defaults in [
      {'${model.server!.id}:ngc': 7},
      {'${'f' * 32}:ngc': 'dolphin'},
    ]) {
      document['emulatorDefaults'] = defaults;
      final original = jsonEncode(document);
      await file.writeAsString(original);
      await expectLater(
        model.storage.load(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.readAsString(), original);
    }
  });
  testWidgets(
    'platform fetch failures retain known sections and compact layouts stay usable',
    (t) async {
      for (final size in [const Size(390, 844), const Size(860, 620)]) {
        await open(t, size: size);
        model.discoveryError = 'Platforms could not be loaded';
        model.reportProblem('Retained known platforms');
        await t.pumpAndSettle();
        expect(find.text('A Nintendo GameCube'), findsOneWidget);
        expect(find.text('Platforms could not be loaded'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
}
