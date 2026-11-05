@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter_test/flutter_test.dart';

/// Explicit local upstream downloads. No account/profile or library is copied.
/// This opt-in integration check is separate from the ordinary offline tests.
void main() {
  test(
    'native standalone downloads install and resolve private Linux profiles',
    () async {
      final fixture = Directory(
        Platform.environment['BROOMM_LINUX_FIXTURE_ROOT'] ??
            '.tool-cache/research/linux-standalone',
      ).absolute;
      final input = File('${fixture.path}/all-downloads.json');
      expect(
        await input.exists(),
        isTrue,
        reason: 'Acquire the pinned official archives first.',
      );
      final downloaded = jsonDecode(await input.readAsString()) as Map;
      final root = await fixture.createTemp('integration-');
      final data = await Directory('${root.path}/data').create();
      final manager = ManagedEmulators(
        data,
        asset: (p) => File(p).readAsString(),
      );
      addTearDown(manager.dispose);
      await File('${fixture.path}/current-integration.txt')
          .writeAsString(root.path);
      String previous = '';
      manager.addListener(() {
        if (manager.phase != previous) {
          previous = manager.phase;
          // ignore: avoid_print
          print(manager.phase);
        }
      });
      final full = await manager.readPlan();
      final plan = SetupPlan(
        full.items
            .where(
              (i) => manager.host == 'linux-arm64'
                  ? {
                      'dolphin',
                      'rpcs3',
                      'duckstation',
                      'armsx2',
                      'ppsspp',
                      'eden',
                    }.contains(i.build.id)
                  : i.build.id != 'retroarch',
            )
            .toList(),
      );
      expect(plan.items.length, manager.host == 'linux-arm64' ? 6 : 9);
      for (final item in plan.items) {
        for (final package in item.downloads.values) {
          final upstream = downloaded[item.build.id] as Map;
          expect(upstream['sha256'], package.sha256);
          final cache = await Directory(
            '${data.path}/setup-downloads/.download-${package.sha256}',
          ).create(recursive: true);
          await File('${fixture.path}/${upstream['filename']}')
              .copy('${cache.path}/payload');
          await File('${cache.path}/download.json').writeAsString(
            jsonEncode({
              'product': 'Broomm setup',
              'format': 1,
              'state': 'complete',
              'sha256': package.sha256,
              'bytes': package.bytes,
            }),
          );
        }
      }
      await manager.install(plan);
      expect(manager.error, isNull, reason: manager.error);
      final observations = <Map<String, Object?>>[];
      for (final item in plan.items) {
        expect(manager.ready(item.build.name), isTrue);
        final lease = await SessionLease.acquire(data);
        try {
          final before = Stopwatch()..start();
          final a = await manager.resolveConfiguration(
            item.build.name,
            'e' * 32,
          );
          final b = await manager.resolveConfiguration(
            item.build.name,
            'f' * 32,
          );
          expect(a.emulator.executable, b.emulator.executable);
          expect(a.emulator.root, isNot(b.emulator.root));
          expect(await File(a.emulator.executable).exists(), isTrue);
          expect(await Directory(a.emulator.user).exists(), isTrue);
          observations.add({
            'id': item.build.id,
            'version': item.build.version,
            'resolveTwoProfilesMs': before.elapsedMilliseconds,
            'privateRoot': a.emulator.root,
            'executable': a.emulator.executable,
          });
        } finally {
          await lease.release();
        }
      }
      await File('${root.path}/installation.json')
          .writeAsString(jsonEncode(observations));
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
