import 'package:broomm/main.dart';
import 'package:broomm/src/app_model.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/widgets/controller_tester.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'loading never presents join slots or disabled controller chips',
    (tester) async {
      final model = PrototypeModel('/unused')
        ..screen = Screen.loading
        ..loadingGame = testGames.first
        ..notice = 'Initializing controller input…';
      model.pairing = Pairing(2);
      model.devices = [const ControllerDevice(1, 'Connected pad', 0, 0, 0)];
      await tester.pumpWidget(BroommPrototype(model: model));
      expect(find.text('Loading RetroArch…'), findsOneWidget);
      expect(find.text('Initializing controller input…'), findsOneWidget);
      expect(find.text('PLAYER 1'), findsNothing);
      expect(find.textContaining('Press L1 + R1 to join'), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('Cancel launch'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('library includes all six supplied ROMs and keyboard selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 800));
    final model = PrototypeModel('/nonexistent-test-project');
    await tester.pumpWidget(BroommPrototype(model: model));
    expect(find.text('Choose a game'), findsOneWidget);
    for (final game in testGames) expect(find.text(game.title), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(model.selected, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets(
    'Wii shows one active live tester and the four bottom choices with independent controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 800));
      final model = PrototypeModel('/unused')..screen = Screen.pairing;
      model.pairing = Pairing(4, target: ControllerTarget.wii)..join(10);
      model.devices = [
        const ControllerDevice(
          10,
          'Pad',
          1,
          0,
          0,
          sensors: 3,
          sensorReady: 3,
          accel: [0, 9.8, 0],
        ),
      ];
      await tester.pumpWidget(BroommPrototype(model: model));
      final active = find.byWidgetPredicate(
        (w) => w is ControllerTester && !w.miniature,
      );
      final previews = find.byWidgetPredicate(
        (w) => w is ControllerTester && w.miniature,
      );
      for (var i = 0; i < 4; i++) {
        final mode = model.pairing!.players.single.wiiMode;
        expect(active, findsOneWidget);
        expect(previews, findsNWidgets(4));
        final live = tester.widget<ControllerTester>(active);
        expect(live.assignment.wiiMode, mode);
        expect(live.device?.buttons, 1);
        expect(live.values.values.any((v) => v > 0), true);
        final thumbnailRects = [
          for (final element in previews.evaluate())
            tester.getRect(find.byWidget(element.widget)),
        ];
        for (final rect in thumbnailRects) {
          expect(rect.top, greaterThanOrEqualTo(tester.getRect(active).bottom));
          expect(rect.bottom, lessThan(690));
        }
        expect(thumbnailRects.map((r) => r.top).toSet().length, 1);
        for (final mode in WiiMode.values) {
          expect(
            tester.getRect(find.text(mode.label).last).bottom,
            lessThan(tester.getRect(find.text('Hold Select')).top),
          );
        }
        await tester.tap(find.byTooltip('Next controller type (L1 + R1)'));
        await tester.pump();
        expect(model.pairing!.players.single.swapFaces, false);
        expect(model.pairing!.players.single.wiiMode, isNot(mode));
      }
      expect(model.pairing!.players.single.wiiMode, WiiMode.nunchuk);
      await tester.tap(find.byTooltip('Swap face buttons (L3 + R1)'));
      await tester.pump();
      expect(model.pairing!.players.single.wiiMode, WiiMode.nunchuk);
      expect(model.pairing!.players.single.swapFaces, true);
      await tester.ensureVisible(find.text(WiiMode.classic.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(WiiMode.classic.label));
      await tester.pump();
      expect(model.pairing!.players.single.wiiMode, WiiMode.classic);
      expect(model.pairing!.players.single.swapFaces, true);
      expect(active, findsOneWidget);
      expect(previews, findsNWidgets(4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'progressive slots and all target controller testers stay readable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 800));
      final model = PrototypeModel('/nonexistent-test-project');
      model.screen = Screen.pairing;
      model.pairing = Pairing(4);
      model.devices = [
        const ControllerDevice(10, 'Pad A', 0, 0, 0),
        const ControllerDevice(11, 'Pad B', 0, 0, 0),
      ];
      await tester.pumpWidget(BroommPrototype(model: model));
      expect(find.text('PLAYER 1'), findsOneWidget);
      expect(find.text('PLAYER 2'), findsNothing);
      model.join(10);
      await tester.pump();
      expect(find.text('PLAYER 2'), findsOneWidget);
      expect(find.text('PLAYER 3'), findsNothing);
      model.join(11);
      await tester.pump();
      expect(find.text('PLAYER 3'), findsOneWidget);
      expect(find.text('PLAYER 4'), findsNothing);
      model.move(1, -1);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(model.pairing!.players.first.deviceId, 11);
      model.devices.addAll([
        const ControllerDevice(12, 'Pad C', 0, 0, 0),
        const ControllerDevice(13, 'Pad D', 0, 0, 0),
      ]);
      model.join(12);
      model.join(13);
      model.activeController = 13;
      model.notifyListeners();
      await tester.pumpAndSettle();
      final fourth = find.byKey(const ValueKey('player-4'));
      expect(
        tester.getRect(fourth).overlaps(const Rect.fromLTWH(0, 180, 1180, 500)),
        true,
      );
      expect(tester.takeException(), isNull);
      for (final target in ControllerTarget.values) {
        for (final mode
            in target == ControllerTarget.wii
                ? WiiMode.values
                : [WiiMode.nunchuk]) {
          model.pairing = Pairing(4, target: target)..join(10);
          model.wiiMode(10, mode);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$target $mode');
          final live = tester
              .widgetList<ControllerTester>(find.byType(ControllerTester))
              .first;
          expect(live.target, target);
          model.devices = [
            const ControllerDevice(
              10,
              'Pad A',
              1,
              0,
              -32767,
              rx: 32767,
              lt: 32767,
            ),
          ];
          model.notifyListeners();
          await tester.pump();
          final pressed = tester
              .widgetList<ControllerTester>(find.byType(ControllerTester))
              .first;
          expect(pressed.values.values.any((v) => v > 0), true);
        }
      }
      model.screen = Screen.menu;
      model.notifyListeners();
      await tester.pump();
      await tester.tap(find.text('Controller pairing'));
      await tester.pump();
      expect(model.screen, Screen.pairing);
      expect(model.pairing!.players.length, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    },
  );
}
