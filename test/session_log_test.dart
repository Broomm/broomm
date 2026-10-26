import 'dart:async';
import 'dart:io';

import 'package:broomm/src/session_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'background logging retains bounded newest segments and clean records',
    () async {
      final root = await Directory.systemTemp.createTemp('broomm-log-');
      final problems = <String>[];
      final log = SessionLog(
        '${root.path}/session.log',
        onProblem: problems.add,
      );
      try {
        for (var i = 0; i < 365; i++) {
          log.write('Record $i ${'x' * 32768}');
          if (i % 40 == 39) await log.flush();
        }
        log.output([
          27,
          91,
          51,
          49,
          109,
          ...'Latest output'.codeUnits,
          27,
          91,
          48,
          109,
        ]);
        await log.close();
        final files = await root
            .list()
            .where((f) => f is File)
            .cast<File>()
            .toList();
        expect(files.length, 10);
        for (final file in files)
          expect(await file.length(), lessThanOrEqualTo(1024 * 1024));
        final all = (await Future.wait(files.map((f) => f.readAsString())))
            .join('\n');
        expect(all, contains('Latest output'));
        expect(all, contains('Record 364 '));
        expect(all, isNot(contains('Record 0 ')));
        expect(all, isNot(contains('\x1b')));
        expect(problems, isEmpty);
        for (final line in all.split('\n').where((s) => s.isNotEmpty))
          expect(
            line,
            matches(r'^\d{4}-\d{2}-\d{2}T[^ ]+Z info session\.dart '),
          );
      } finally {
        await log.close();
        await root.delete(recursive: true);
      }
    },
  );
  test('failed log writes surface once and recover without losing the queued record', () async {
    final root = await Directory.systemTemp.createTemp('broomm-log-retry-');
    final blocked = File('${root.path}/blocked');
    await blocked.writeAsString('file');
    final observed = Completer<void>(), problems = <String>[];
    final log = SessionLog(
      '${blocked.path}/session.log',
      onProblem: (p) {
        problems.add(p);
        if (!observed.isCompleted) observed.complete();
      },
    );
    try {
      log.write('Queued record');
      await observed.future.timeout(const Duration(seconds: 5));
      await blocked.delete();
      await Directory(blocked.path).create();
      await log.flush().timeout(const Duration(seconds: 5));
      await log.close();
      expect(problems.length, 1);
      final content = await File('${blocked.path}/session.log').readAsString();
      expect('Queued record'.allMatches(content).length, 1);
    } finally {
      await log.close();
      await root.delete(recursive: true);
    }
  });
  test(
    'oversized output is bounded and cannot prevent subsequent logging',
    () async {
      final root = await Directory.systemTemp.createTemp('broomm-log-bound-');
      final problems = <String>[];
      final log = SessionLog(
        '${root.path}/session.log',
        onProblem: problems.add,
      );
      try {
        final oversized = 'x' * (3 * 1024 * 1024);
        log.write(oversized);
        log.write(oversized);
        log.write('Still recording');
        await log.close();
        expect(problems.length, 1);
        expect(
          await File('${root.path}/session.log').readAsString(),
          contains('Still recording'),
        );
      } finally {
        await log.close();
        await root.delete(recursive: true);
      }
    },
  );
}
