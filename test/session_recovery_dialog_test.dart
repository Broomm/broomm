import 'package:broomm/src/host.dart';
import 'package:broomm/src/shell/session_recovery_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class WriterHost extends DesktopHost {
  Map<String, dynamic>? writer = {
    'status': 'emulator',
    'name': 'Fixture',
    'token': 'first',
    'message': 'The previous emulator still owns this session.',
  };
  bool failInspection = false;
  final commands = <(String, String)>[];
  @override
  Future<Map<String, dynamic>?> gameWriter(String root) async {
    if (failInspection) throw StateError('Inspection unavailable');
    return writer;
  }

  @override
  Future<void> controlGameWriter(String token, String action) async {
    if (token != writer?['token'])
      throw StateError('Writer changed; no process was signalled.');
    commands.add((token, action));
  }
}

void main() {
  testWidgets(
    'force quit requires confirmation and a stale writer is refused; releasing the real writer completes recovery',
    (t) async {
      final host = WriterHost();
      bool? result;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await recoverGameSession(
                context,
                '/fixture',
                host: host,
              ),
              child: const Text('Recover'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Recover'));
      await t.pumpAndSettle();
      await t.tap(find.text('Show Fixture'));
      await t.pumpAndSettle();
      expect(host.commands, [('first', 'show')]);
      await t.tap(find.text('Force quit emulator…'));
      await t.pumpAndSettle();
      expect(host.commands.length, 1);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      await t.tap(find.text('Force quit emulator…'));
      await t.pumpAndSettle();
      host.writer = {...host.writer!, 'token': 'replacement'};
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Force quit emulator'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Writer changed; no process was signalled.'),
        findsOneWidget,
      );
      expect(host.commands.length, 1);
      await t.tap(find.text('Close emulator normally'));
      await t.pumpAndSettle();
      expect(host.commands.last, ('replacement', 'stop'));
      expect(result, isNull);
      host.writer = null;
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(result, true);
      expect(find.text('Recover game session'), findsNothing);
    },
  );

  testWidgets(
    'failed inspection remains unknown and never exposes termination or treats it as no writer',
    (t) async {
      final host = WriterHost()..failInspection = true;
      bool? result;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await recoverGameSession(
                context,
                '/fixture',
                host: host,
              ),
              child: const Text('Recover'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Recover'));
      await t.pumpAndSettle();
      expect(result, isNull);
      expect(find.textContaining('Inspection unavailable'), findsOneWidget);
      expect(find.text('Close emulator normally'), findsNothing);
      expect(find.text('Force quit emulator…'), findsNothing);
      await t.tap(find.text('Back'));
      await t.pumpAndSettle();
      expect(result, false);
      expect(host.commands, isEmpty);
    },
  );
}
