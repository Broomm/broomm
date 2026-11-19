import 'package:broomm/src/shell/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'console_keyboard_shortcuts_test.dart' show open, native;

Finder key(String label) => find.descendant(
  of: find.byKey(const ValueKey('console-keyboard')),
  matching: find.byWidgetPredicate(
    (w) => w is ConsoleButton && w.label == label,
  ),
);
FocusNode node(WidgetTester t, String label) =>
    t.widget<ConsoleButton>(key(label).first).focusNode!;
String selected(WidgetTester t) => t
    .widgetList<ConsoleButton>(
      find.descendant(
        of: find.byKey(const ValueKey('console-keyboard')),
        matching: find.byType(ConsoleButton),
      ),
    )
    .singleWhere((w) => w.focusNode!.hasPrimaryFocus)
    .label!;
Future<void> move(
  WidgetTester t,
  TraversalDirection direction, {
  bool controller = false,
}) async {
  if (controller) {
    Actions.maybeInvoke(
      FocusManager.instance.primaryFocus!.context!,
      ControllerDirectionIntent(direction),
    );
  } else {
    await t.sendKeyEvent(switch (direction) {
      TraversalDirection.up => LogicalKeyboardKey.arrowUp,
      TraversalDirection.down => LogicalKeyboardKey.arrowDown,
      TraversalDirection.left => LogicalKeyboardKey.arrowLeft,
      TraversalDirection.right => LogicalKeyboardKey.arrowRight,
    });
  }
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'character columns and control boundaries share one grid at desktop and compact sizes',
    (t) async {
      t.view.devicePixelRatio = 1;
      for (final size in [const Size(1180, 800), const Size(390, 844)]) {
        t.view.physicalSize = size;
        await t.binding.setSurfaceSize(size);
        await open(t);
        final first = t.getRect(key('`')), q = t.getRect(key('q'));
        final cell = q.width + 4;
        for (final shift in key('Shift').evaluate()) {
          expect(
            t.getSize(find.byElementPredicate((e) => e == shift)).width + 4,
            closeTo(cell * 2, .01),
          );
        }
        for (final column in [
          '1qa',
          '2wsz',
          '3edx',
          '4rfc',
          '5tgv',
          '6yhb',
          '7ujn',
        ]) {
          final rect = t.getRect(key(column[0]));
          for (final ch in column.split('')) {
            final other = t.getRect(key(ch));
            expect(other.center.dx, closeTo(rect.center.dx, .01));
            expect(other.width, closeTo(rect.width, .01));
          }
        }
        for (final button in t.widgetList<ConsoleButton>(
          find.descendant(
            of: find.byKey(const ValueKey('console-keyboard')),
            matching: find.byType(ConsoleButton),
          ),
        )) {
          final rect = t.getRect(find.byWidget(button));
          final start = (rect.left - first.left) / cell;
          final span = (rect.width + 4) / cell;
          expect(start, closeTo(start.roundToDouble(), .001));
          expect(span, closeTo(span.roundToDouble(), .001));
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'vertical navigation preserves the character column through Space and wide controls',
    (t) async {
      await open(t);
      expect(selected(t), '1');
      for (final label in ['q', 'a', 'Shift', 'Space']) {
        await move(t, TraversalDirection.down, controller: true);
        expect(selected(t), label);
      }
      await move(
        t,
        TraversalDirection.left,
      ); // Left edge must preserve the lane.
      for (final label in ['Shift', 'a', 'q', '1']) {
        await move(t, TraversalDirection.up);
        expect(selected(t), label);
      }
      node(t, '=').requestFocus();
      await t.pumpAndSettle();
      for (final label in [']', 'Enter', 'Shift', 'Done']) {
        await move(t, TraversalDirection.down);
        expect(selected(t), label);
      }
      for (final label in ['Shift', 'Enter', ']', '=']) {
        await move(t, TraversalDirection.up, controller: true);
        expect(selected(t), label);
      }
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'rapid directions, shifted symbols and resize keep stable columns and focus',
    (t) async {
      await open(t);
      final initial = node(t, '1');
      for (var i = 0; i < 4; i++) {
        Actions.maybeInvoke(
          initial.context!,
          const ControllerDirectionIntent(TraversalDirection.down),
        );
      }
      await t.pumpAndSettle();
      expect(selected(t), 'Space');
      for (var i = 0; i < 4; i++) {
        Actions.maybeInvoke(
          FocusManager.instance.primaryFocus!.context!,
          const ControllerDirectionIntent(TraversalDirection.up),
        );
      }
      await t.pumpAndSettle();
      expect(selected(t), '1');
      native('shift-down');
      await t.pumpAndSettle();
      expect(selected(t), '!');
      expect(identical(node(t, '!'), initial), true);
      await move(t, TraversalDirection.down);
      expect(selected(t), 'Q');
      await move(t, TraversalDirection.down);
      expect(selected(t), 'A');
      native('shift-up');
      await t.pumpAndSettle();
      expect(selected(t), 'a');
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      await t.binding.setSurfaceSize(const Size(390, 844));
      await t.pumpAndSettle();
      await move(t, TraversalDirection.up);
      expect(selected(t), 'q');
      await move(t, TraversalDirection.right);
      expect(selected(t), 'w');
      await move(t, TraversalDirection.down);
      expect(selected(t), 's');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
}
