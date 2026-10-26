import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';

Future<Map<String, Map<String, Object>>> cacheInventory(
  Directory profile,
) async {
  final result = <String, Map<String, Object>>{};
  final roots = [
    Directory('${profile.path}/home/Library/Caches/rpcs3/cache'),
    Directory('${profile.path}/cache'),
  ];
  for (final root in roots) {
    if (!await root.exists()) continue;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final stat = await e.stat();
      result[e.path.substring(profile.path.length + 1)] = {
        'bytes': stat.size,
        'modified': stat.modified.toUtc().toIso8601String(),
        'kind': e.path.endsWith('.obj.gz')
            ? 'ppu-object'
            : e.path.contains('/shaders_cache/')
            ? 'shader'
            : 'other',
      };
    }
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('two RPCS3 boots reuse the same private compiled objects and shader cache without modifying the normal profile', () async {
    final project = Directory.current.path;
    final evidence = Directory(
      '$project/.tool-cache/research/loading-keyboard',
    );
    await evidence.create(recursive: true);
    final data = await evidence.createTemp('native-cache-');
    final owner = Directory('$project/broomm-data');
    const profile = '15770cf1430ff66c406582cc4245ae63';
    final source = Directory('${owner.path}/profiles/$profile/emulators/rpcs3');
    final lease = await SessionLease.acquire(owner);
    late Map<String, Map<String, Object>> ownerBefore;
    try {
      ownerBefore = await cacheInventory(source);
      for (final relative in [
        'emulators/rpcs3',
        for (final area in [
          'profile.json',
          'user',
          'portable',
          'saves',
          'states',
          'cache',
          'config',
          'data',
          'system',
          'screenshots',
          'home/Library/Application Support',
          'home/Library/Caches/rpcs3/cache',
        ])
          'profiles/$profile/emulators/rpcs3/$area',
      ]) {
        if (await FileSystemEntity.type(
              '${owner.path}/$relative',
              followLinks: false,
            ) ==
            FileSystemEntityType.notFound)
          continue;
        final target = File('${data.path}/$relative');
        await target.parent.create(recursive: true);
        final copied = await Process.run('/bin/cp', [
          '-cpR',
          '${owner.path}/$relative',
          target.path,
        ]);
        expect(copied.exitCode, 0, reason: '${copied.stderr}');
      }
    } finally {
      await lease.release();
    }
    final builds =
        (jsonDecode(
              await File('assets/setup/tested-builds.json').readAsString(),
            ) as Map)['builds']
            as List;
    final build = builds.cast<Map>().singleWhere((b) => b['id'] == 'rpcs3');
    await File('${data.path}/emulators/selected.json').writeAsString(
      jsonEncode({
        'schema_version': 1,
        'selected': {'rpcs3': build['sha256']},
      }),
    );
    final manager = ManagedEmulators(
      data,
      project: project,
      asset: (p) => File(p).readAsString(),
    );
    await manager.load();
    final game = LaunchGame(
      '8002',
      '3D Dot Game Heroes',
      'PlayStation 3',
      'RPCS3',
      '$project/broomm-data/library/506d439865d8f46267001bdd3a1fe0e5/8002/content/3D Dot Game Heroes (USA).iso',
      4,
      0xff539388,
      target: ControllerTarget.ps3,
    );
    final privateProfile = Directory(
      '${data.path}/profiles/$profile/emulators/rpcs3',
    );
    final first = await cacheInventory(privateProfile);
    expect(first.values.where((f) => f['kind'] == 'ppu-object'), isNotEmpty);
    final passes = <Map<String, Object>>[];
    for (var n = 0; n < 2; n++) {
      final before = await cacheInventory(privateProfile);
      final session = GameSession(
        project,
        managedRoot: data.path,
        testInputs: true,
        resolve: (g) => manager.resolve(g, profile),
      );
      final problems = <String>[];
      session.onProblem = problems.add;
      try {
        final watch = Stopwatch()..start();
        await session.launch(game);
        await session.waitFor(
          (s) => s.inputReady && s.paused == 1,
          timeout: const Duration(minutes: 8),
        );
        final ready = watch.elapsedMilliseconds;
        final pairing = Pairing(4, target: ControllerTarget.ps3)
          ..join(session.status!.testSourceIds.first);
        await session.command(pairing.players, active: true);
        await session.waitFor(
          (s) => s.paused == 0,
          timeout: const Duration(seconds: 15),
        );
        await Future<void>.delayed(const Duration(seconds: 3));
        await session.stop();
        expect(problems, isEmpty);
        final after = await cacheInventory(privateProfile);
        var reused = 0, changed = 0, added = 0;
        for (final e in after.entries) {
          if (e.value['kind'] != 'ppu-object') continue;
          if (!before.containsKey(e.key))
            added++;
          else if (jsonEncode(e.value) == jsonEncode(before[e.key]))
            reused++;
          else
            changed++;
        }
        passes.add({
          'pass': n + 1,
          'readyMilliseconds': ready,
          'ppuObjectsUnchanged': reused,
          'ppuObjectsModified': changed,
          'ppuObjectsAdded': added,
          'shaderFiles': after.values
              .where((f) => f['kind'] == 'shader')
              .length,
        });
        await File('${evidence.path}/cache-pass-${n + 1}.json')
            .writeAsString(jsonEncode(after));
        stdout.writeln(jsonEncode(passes.last));
        expect(reused, greaterThan(0));
        expect(
          changed,
          0,
          reason: 'Previously compiled modules must not be rewritten on a normal cached boot.',
        );
      } finally {
        if (session.running) await session.stop();
      }
    }
    manager.dispose();
    await File('${evidence.path}/native-cache.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'root': data.path,
        'host': Platform.operatingSystem,
        'build': build['sha256'],
        'initialPpuObjects': first.values
            .where((f) => f['kind'] == 'ppu-object')
            .length,
        'runs': passes,
        'sourceReadOnlyCopy': true,
      }),
    );
    // Normal source progress is never passed to the child; a fresh lease also
    // avoids comparing while an owner emulator could be writing new caches.
    final finalLease = await SessionLease.acquire(owner);
    try {
      expect(await cacheInventory(source), ownerBefore);
    } finally {
      await finalLease.release();
    }
  }, timeout: const Timeout(Duration(minutes: 18)));
}
