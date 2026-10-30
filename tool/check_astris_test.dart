@TestOn('mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart' show atomicText;
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/progress/ryubing.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/store.dart';

void main() {
  test('Astris pinned installation boots supplied Switch game in private storage', () async {
    final root = Platform.environment['BROOMM_ASTRIS_FIXTURE'] == null
        ? await Directory('.tool-cache/research/astris-citra/resumed')
              .createTemp('native-')
        : Directory(Platform.environment['BROOMM_ASTRIS_FIXTURE']!);
    final data = await Directory('${root.absolute.path}/data').create();
    final manager = ManagedEmulators(
      data,
      project: Directory.current.path,
      asset: (p) => File(p).readAsString(),
    );
    manager.addListener(() => stdout.writeln(manager.phase));
    await manager.load();
    if (!manager.ready('Astris')) {
      final plan = await manager.readPlan(only: {'astris'});
      final resourceRoot = Platform.environment['BROOMM_ASTRIS_RESOURCES']!;
      final lockRoot = Platform.environment['BROOMM_ASTRIS_LOCK_ROOT'];
      final lease = lockRoot == null
          ? null
          : await SessionLease.acquire(Directory(lockRoot));
      final item = plan.items.single;
      try {
        await manager.install(
          SetupPlan([
            SetupItem(item.build, item.source, item.core, {
              for (final name in ['switch_firmware', 'prod_keys', 'title_keys'])
                name: '$resourceRoot/$name',
            }, downloads: item.downloads),
          ]),
        );
      } finally {
        await lease?.release();
      }
    }
    expect(manager.error, isNull, reason: manager.error);
    final profile =
        Platform.environment['BROOMM_ASTRIS_PROFILE'] ??
        '0123456789abcdef0123456789abcdef';
    final game = LaunchGame(
      'astris-check',
      'Super Smash Bros Ultimate',
      'switch',
      'Astris',
      Platform.environment['BROOMM_ASTRIS_ROM']!,
      4,
      0xff304858,
      target: ControllerTarget.switchPro,
    );
    final session = GameSession(
      Directory.current.path,
      managedRoot: data.path,
      testInputs: true,
      onProblem: (p) => stdout.writeln('PROBLEM: $p'),
      resolve: (g) => manager.resolve(g, profile),
    );
    try {
      await session.launch(game);
      await session.waitFor(
        (s) => s.inputReady && s.paused == 1,
        timeout: const Duration(seconds: 90),
      );
      stdout.writeln(
        'Astris ready, paused, program=${session.nativeProgramId}, root=${session.emulator!.root}',
      );
      expect(session.nativeProgramId, isNotNull);
      final pairing = Pairing(4, target: ControllerTarget.switchPro)
        ..join(session.status!.testSourceIds.first)
        ..join(session.status!.testSourceIds.last);
      await session.command(pairing.players, active: true);
      await session.waitFor(
        (s) => s.paused == 0 && !s.blocked && s.connectedPorts == 3,
      );
      await atomicText('${session.emulator!.root}/test-input.txt', '1 0 3');
      await session.waitFor((s) => s.switchButtons != 0);
      stdout.writeln('native pressed bits=${session.status!.switchButtons}');
      await atomicText('${session.emulator!.root}/test-input.txt', '0 0 3');
      await session.waitFor((s) => s.switchButtons == 0);
      await session.command(pairing.players, active: false);
      await session.waitFor((s) => s.paused == 1 && s.blocked);
      pairing.toggleLayout(pairing.players.first.deviceId);
      await session.command(pairing.players, active: true);
      await session.waitFor((s) => s.paused == 0 && !s.blocked);
      await atomicText('${session.emulator!.root}/test-input.txt', '1 0 3');
      await session.waitFor((s) => s.switchButtons == 4);
      await atomicText('${session.emulator!.root}/test-input.txt', '0 0 3');
      await session.waitFor((s) => s.switchButtons == 0);
      await atomicText(
        '${session.emulator!.root}/test-input.txt',
        '${(1 << 4) | (1 << 8)} 0 3',
      );
      await session.waitFor((s) => s.paused == 1 && s.request == 'menu');
      await atomicText('${session.emulator!.root}/test-input.txt', '0 0 3');
      await session.command(pairing.players, active: true);
      await session.waitFor((s) => s.paused == 0 && !s.blocked);
      await atomicText('${session.emulator!.root}/test-input.txt', '0 1 3');
      await session.waitFor((s) => s.paused == 1 && s.request == 'disconnect');
      final resolved = await manager.resolveProgress(game, profile);
      final identity = (await switchSourceIdentity(resolved)).$1;
      final program = session.nativeProgramId!;
      await session.stop();
      final lease = await SessionLease.acquire(data);
      try {
        await recordRyubingGame(resolved, program, identity);
        final layout = await gameProgressLayout(resolved, 'switch');
        final store = ProgressStore(
          Directory('${root.path}/save-export'),
          layout,
          1,
          1,
        );
        final snapshot = await store.capture();
        expect(snapshot.entries, isNotEmpty);
        final exported = await store.exportNative(snapshot);
        try {
          expect(
            (await store.importNative(exported.file)).ordinaryDigest,
            snapshot.ordinaryDigest,
          );
        } finally {
          await exported.close();
        }
        stdout.writeln('Native Astris save ZIP round-trip passed.');
      } finally {
        await lease.release();
      }
    } finally {
      if (session.running) await session.stop();
      manager.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
