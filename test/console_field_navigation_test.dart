import 'package:broomm/src/shell/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'the dock edits the original selection; Back keeps text without submitting, and removing its field closes safely',
    (t) async {
      var submitted = 0;
      var showField = true;
      late StateSetter update;
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => Shortcuts(
            shortcuts: consoleShortcuts,
            child: ConsoleKeyboardHost(child: child!),
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return showField
                    ? ConsoleField(
                        autofocus: true,
                        label: 'Query',
                        value: 'A😀B',
                        onChanged: (_) {},
                        onSubmitted: (_) => submitted++,
                      )
                    : const Text('Field removed');
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final field = find.byKey(const ValueKey('field-Query'));
      final text = t.widget<TextField>(field).controller!;
      text.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await t.pumpAndSettle();
      await t.tap(find.text('q'));
      expect(text.text, 'AqB');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('console-keyboard')), findsNothing);
      expect(submitted, 0);
      expect(text.text, 'AqB');
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('console-keyboard')), findsOneWidget);
      update(() => showField = false);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('console-keyboard')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'keyboard focus stays navigable; Enter edits and Escape keeps field focus without editing',
    (t) async {
      var backs = 0;
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => ConsoleKeyboardHost(child: child!),
          home: Shortcuts(
            shortcuts: consoleShortcuts,
            child: Actions(
              actions: {
                BackIntent: CallbackAction<BackIntent>(
                  onInvoke: (_) {
                    backs++;
                    return null;
                  },
                ),
              },
              child: Scaffold(
                body: SizedBox(
                  width: 600,
                  child: Column(
                    children: [
                      ConsoleField(
                        autofocus: true,
                        label: 'Search',
                        value: 'Mario',
                        onChanged: (_) {},
                      ),
                      ConsoleButton(
                        onPressed: () {},
                        child: const Text('Next action'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final field = find.byKey(const ValueKey('field-Search'));
      expect(t.widget<TextField>(field).readOnly, true);
      expect(t.widget<TextField>(field).showCursor, false);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).readOnly, false);
      expect(t.widget<TextField>(field).focusNode!.hasFocus, true);
      final selection = t
          .widget<TextField>(field)
          .controller!
          .selection
          .baseOffset;
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(
        t.widget<TextField>(field).controller!.selection.baseOffset,
        selection - 1,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).readOnly, true);
      expect(backs, 0);
      // Escape preserved the field's navigation focus; Enter can edit again.
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).readOnly, false);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(backs, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'pointer editing stays inline; controller activation opens the keyboard and returns to navigation mode',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => ConsoleKeyboardHost(child: child!),
          home: Shortcuts(
            shortcuts: consoleShortcuts,
            child: Scaffold(
              body: SizedBox(
                width: 600,
                child: ConsoleField(
                  autofocus: true,
                  label: 'Server',
                  value: '',
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final field = find.byKey(const ValueKey('field-Server'));
      await t.tap(field);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).readOnly, false);
      await t.enterText(field, 'https://server.example');
      expect(find.byKey(const ValueKey('console-keyboard')), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('console-keyboard')), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      await t.tap(find.text('q'));
      await t.pump();
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).readOnly, true);
      expect(
        t.widget<TextField>(field).controller!.text,
        'https://server.exampleq',
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
