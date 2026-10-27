import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/ps3_disc.dart';
import 'package:broomm/src/progress/layout.dart' show readPs3GameMetadata;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Gran Turismo 6 title inspection accepts its unrelated multi-part data records without changing the encrypted ISO', () async {
    final iso = File(
      'broomm-data/library/506d439865d8f46267001bdd3a1fe0e5/8010/content/Gran Turismo 6 (USA).iso',
    );
    final before = await iso.stat(), clock = Stopwatch()..start();
    final meta = await readPs3GameMetadata(iso.path);
    expect(meta['TITLE_ID'], 'BCUS98296');
    expect(await ps3DiscKey(iso), isNotNull);
    final after = await iso.stat();
    expect(after.size, before.size);
    expect(after.modified, before.modified);
    await File('.tool-cache/research/downloads-status/gt6-metadata.json')
        .writeAsString(
          jsonEncode({
            'titleId': meta['TITLE_ID'],
            'bytes': after.size,
            'metadataMs': clock.elapsedMilliseconds,
            'sizeAndMtimeUnchanged': true,
          }),
        );
  });
  test('both pinned RPCS3 architectures expose changing native loading counters and close with the writer observed', () async {
    final project = Directory.current.path,
        evidence = Directory('$project/.tool-cache/research/downloads-status');
    final data = await evidence.createTemp('native-loading-');
    final manager = ManagedEmulators(
      data,
      project: project,
      asset: (p) => File(p).readAsString(),
    );
    const profile = 'f223456789abcdef0123456789abcdef';
    final results = <Map<String, dynamic>>[];
    await manager.load();
    await manager.install(
      await manager.readPlan(
        file: 'tool/setup-development.json',
        only: {'rpcs3', 'rpcs3-intel'},
      ),
    );
    expect(manager.error, isNull, reason: manager.error);
    try {
      for (final name in ['RPCS3', 'RPCS3 Intel']) {
        final samples = <String>{};
        final values = <Map<String, Object?>>[];
        final problems = <String>[];
        final session = GameSession(
          project,
          managedRoot: data.absolute.path,
          testInputs: true,
          resolve: (g) => manager.resolve(g, profile),
          onProblem: problems.add,
          onStatus: (s) {
            if (s.loading case final progress?) {
              samples.add(progress.description);
              if (values.length < 200)
                values.add({
                  'files': progress.filesTotal,
                  'filesDone': progress.filesDone,
                  'modules': progress.modulesTotal,
                  'modulesDone': progress.modulesDone,
                  'fraction': progress.fraction,
                });
            }
          },
        );
        final game = LaunchGame(
          '8002',
          '3D Dot Game Heroes',
          'PlayStation 3',
          name,
          '$project/broomm-data/library/506d439865d8f46267001bdd3a1fe0e5/8002/content/3D Dot Game Heroes (USA).iso',
          4,
          0,
          target: ControllerTarget.ps3,
        );
        try {
          await session.launch(game);
          await session.waitFor(
            (s) => s.inputReady && s.paused == 1,
            timeout: const Duration(minutes: 10),
          );
          expect(samples.length, greaterThanOrEqualTo(3));
          expect(values.any((v) => (v['modules'] as int) > 0), true);
          await session.stop();
          expect(problems, isEmpty, reason: problems.join('\n'));
          results.add({
            'emulator': name,
            'distinctCounters': samples.length,
            'values': values,
            'normalClose': true,
          });
          stdout.writeln(
            '$name exposed ${samples.length} different native progress samples.',
          );
        } finally {
          await File(
            '${evidence.path}/loading-${name == 'RPCS3' ? 'arm' : 'intel'}.json',
          ).writeAsString(
            jsonEncode({
              'root': data.path,
              'distinct': samples.length,
              'values': values,
            }),
          );
          if (session.running) await session.stop();
        }
      }
      await File('${evidence.path}/native-loading.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'root': data.absolute.path, 'results': results, 'ownerDataWritten': false, 'completeGameBoot': false})}\n',
      );
    } finally {
      manager.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 24)));
}
