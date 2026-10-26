import 'dart:io';

import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late GameSession session;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-command-test-');
    session = GameSession(root.path)
      ..emulator = PreparedEmulator('test', root.path, '', 3, null, null);
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'overlapping apply and recovery publish complete commands in order',
    () async {
      final apply = session.command([const PlayerAssignment(10)], active: true);
      final pause = session.command([
        const PlayerAssignment(10),
      ], active: false);
      final stop = session.command([], active: false, quit: true);
      final revisions = await Future.wait([apply, pause, stop]);
      final values = (await File(
        '${root.path}/bridge-command.txt',
      ).readAsString()).trim().split(RegExp(r'\s+')).map(int.parse).toList();
      expect(revisions, orderedEquals([1, 2, 3]));
      expect(values, [
        3,
        0,
        0,
        4294967295,
        4294967295,
        4294967295,
        4294967295,
        0,
        0,
        0,
        0,
        1,
        2,
        2,
        2,
        2,
        0,
        0,
        0,
        0,
      ]);
    },
  );

  test(
    'publication failure reaches its caller without poisoning recovery',
    () async {
      final destination = '${root.path}/bridge-command.txt';
      await Directory(destination)
          .create(); // Exclusive file publication fails.
      await expectLater(
        session.command([], active: true),
        throwsA(isA<FileSystemException>()),
      );
      await Directory(destination).delete();
      final revision = await session.command([], active: false);
      final values = (await File(destination).readAsString()).trim().split(' ');
      expect(int.parse(values.first), revision);
      expect(values[1], '0');
      expect(values[2], '1');
    },
  );
}
