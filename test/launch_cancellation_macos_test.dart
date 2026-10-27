@TestOn('mac-os')
library;

import 'dart:async';
import 'dart:io';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancel during launch preparation drains its owner before releasing the production lease and permits a fresh attempt', () async {
    final root = await Directory.systemTemp.createTemp('broomm-cancel-launch-');
    addTearDown(() => root.delete(recursive: true));
    final rom = await File('${root.path}/game.nsp').writeAsString('fixture');
    final game = LaunchGame(
      'fixture',
      'Game',
      'Switch',
      'Ryubing',
      rom.path,
      4,
      0,
    );
    final entered = Completer<void>(),
        cancelled = Completer<void>(),
        release = Completer<void>();
    late GameSession session;
    session = GameSession(
      '',
      managedRoot: root.path,
      resolve: (_) async {
        entered.complete();
        await session.cancellation.whenCancelled;
        cancelled.complete();
        await release.future;
        session.cancellation.check();
        throw StateError('Cancelled work cannot prepare a process.');
      },
    );
    final launch = session.launch(game);
    final expected = expectLater(launch, throwsA(isA<DownloadCancelled>()));
    await entered.future;
    final stopped = session.stop();
    await cancelled.future;
    await expectLater(SessionLease.acquire(root), throwsStateError);
    expect(session.preparing, true);
    release.complete();
    await expected;
    await stopped;
    expect(session.preparing, false);
    expect(session.running, false);
    final lease = await SessionLease.acquire(root);
    await lease.release();
    final retry = GameSession(
      '',
      managedRoot: root.path,
      resolve: (_) async => throw StateError('fresh attempt reached resolver'),
    );
    await expectLater(retry.launch(game), throwsA(isA<StateError>()));
    final after = await SessionLease.acquire(root);
    await after.release();
  });
}
