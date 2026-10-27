import 'dart:async';

import 'package:broomm/src/shell/quit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a stalled shutdown exposes an explicit exit without clearing or waiting for its unfinished owner',
    (t) async {
      final held = Completer<void>();
      var exits = 0, finished = false;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showQuitDialog(
                context,
                finish: (phase) async {
                  phase('Waiting for the game writer');
                  await held.future;
                  finished = true;
                },
                exit: () async {
                  exits++;
                },
              ),
              child: const Text('Quit'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Quit'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Waiting for the game writer'), findsOneWidget);
      expect(find.text('Quit Broomm now'), findsNothing);
      await t.pump(const Duration(seconds: 3));
      await t.tap(find.text('Quit Broomm now'));
      await t.pumpAndSettle();
      expect(exits, 1);
      expect(finished, false);
      held.complete();
      await t.pumpAndSettle();
      expect(exits, 1);
    },
  );
  testWidgets(
    'a failed shutdown stays visible and can be retried successfully',
    (t) async {
      var attempts = 0, exits = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showQuitDialog(
                context,
                finish: (_) async {
                  if (++attempts == 1)
                    throw StateError('The emulator is still open.');
                },
                exit: () async {
                  exits++;
                },
              ),
              child: const Text('Quit'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Quit'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(
        find.textContaining('The emulator is still open.'),
        findsOneWidget,
      );
      expect(find.text('Keep Broomm open'), findsOneWidget);
      await t.tap(find.text('Retry closing'));
      await t.pumpAndSettle();
      expect(attempts, 2);
      expect(exits, 1);
      expect(t.takeException(), isNull);
    },
  );
}
