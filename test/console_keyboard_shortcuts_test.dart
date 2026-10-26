import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/shell/controls.dart';

Future<TextEditingController> open(
  WidgetTester t, {
  String initial = '',
  int maxLength = 64,
  ValueChanged<String>? submit,
}) async {
  await t.pumpWidget(
    MaterialApp(
      builder: (context, child) => Shortcuts(
        shortcuts: consoleShortcuts,
        child: ConsoleKeyboardHost(child: child!),
      ),
      home: Scaffold(
        body: ConsoleField(
          autofocus: true,
          label: 'Query',
          value: initial,
          maxLength: maxLength,
          onChanged: (_) {},
          onSubmitted: submit,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
  await t.pumpAndSettle();
  expect(find.byKey(const ValueKey('console-keyboard')), findsOneWidget);
  return t
      .widget<TextField>(find.byKey(const ValueKey('field-Query')))
      .controller!;
}

bool native(String action) => ConsoleKeyboardHost.controller(
  FocusManager.instance.primaryFocus!.context!,
  action,
);

void main() {
  testWidgets(
    'controller shortcuts insert space, erase, hold shift across characters, toggle caps and submit the original field',
    (t) async {
      var submitted = 0;
      final text = await open(t, submit: (_) => submitted++);
      await t.sendKeyDownEvent(LogicalKeyboardKey.gameButtonLeft2);
      await t.pump();
      await t.tap(find.text('Q'));
      await t.pump();
      await t.tap(find.text('W'));
      await t.pump();
      expect(text.text, 'QW');
      await t.sendKeyUpEvent(LogicalKeyboardKey.gameButtonLeft2);
      await t.pump();
      await t.tap(find.text('e'));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonThumbLeft);
      await t.pump();
      await t.tap(find.text('R'));
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.gameButtonLeft2);
      await t.pump();
      await t.tap(find.text('t'));
      await t.pump();
      await t.sendKeyUpEvent(LogicalKeyboardKey.gameButtonLeft2);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
      await t.pump();
      expect(text.text, 'QWeRt ');
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonX);
      await t.pump();
      expect(text.text, 'QWeRt');
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonRight2);
      await t.pumpAndSettle();
      expect(submitted, 1);
      expect(find.byKey(const ValueKey('console-keyboard')), findsNothing);
      expect(
        t.widget<TextField>(find.byKey(const ValueKey('field-Query'))).readOnly,
        true,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'native shortcuts use the original selection, preserve Unicode and length limits, and stop editing when the dock closes',
    (t) async {
      final text = await open(t, initial: 'A😀B', maxLength: 4);
      text.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
      expect(native('space'), true);
      await t.pump();
      expect(text.text, 'A B');
      native('caret-right');
      native('caret-left');
      native('search');
      await t.pump();
      expect(text.text, 'AB');
      native('shift-down');
      await t.pump();
      await t.tap(find.text('Q'));
      await t.pump();
      await t.tap(find.text('W'));
      await t.pump();
      await t.tap(find.text('E'));
      await t.pump();
      expect(text.text, 'AQWB');
      native('shift-up');
      native('home');
      await t.pumpAndSettle();
      expect(native('space'), false);
      expect(native('search'), false);
      expect(text.text, 'AQWB');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'losing app focus or releasing L2 behind a modal cannot leave shift stuck or edit the covered field',
    (t) async {
      final text = await open(t);
      native('shift-down');
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await t.tap(find.text('q'));
      await t.pump();
      native('shift-down');
      await t.pump();
      final context = t.element(find.byKey(const ValueKey('field-Query')));
      final modal = showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          content: const Text('Covered'),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () {},
              child: const Text('Wait'),
            ),
          ],
        ),
      );
      await t.pumpAndSettle();
      expect(native('space'), false);
      expect(native('search'), false);
      Actions.maybeInvoke(
        FocusManager.instance.primaryFocus!.context!,
        const SearchIntent(),
      );
      expect(text.text, 'q');
      native('shift-up');
      await t.pump();
      Navigator.of(context, rootNavigator: true).pop();
      await modal;
      await t.pumpAndSettle();
      await t.tap(find.text('w'));
      await t.pump();
      expect(text.text, 'qw');
      expect(t.takeException(), isNull);
    },
  );
}
