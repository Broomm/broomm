@TestOn('mac-os')
library;

import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/ryubing.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/addons/eden.dart';
import 'package:broomm/src/addons/package_profile.dart';
import 'package:broomm/src/romm/transfer.dart';

import '../test/cloud_saves_test.dart' show SaveServer, serverId;

void main() {
  test('native Eden isolated launch, input, pause, live remap and Switch progress', () async {
    final root = await Directory('.tool-cache/research/eden')
        .createTemp('native-');
    final data = await Directory('${root.absolute.path}/data').create();
    final manager = ManagedEmulators(
      data,
      project: Directory.current.path,
      asset: (p) => File(p).readAsString(),
    );
    await manager.install(
      await manager.readPlan(
        file: 'tool/setup-development.json',
        only: {'eden'},
      ),
    );
    expect(manager.error, isNull, reason: manager.error);
    const profile = '0123456789abcdef0123456789abcdef';
    final game = LaunchGame(
      'test',
      'Pokémon Quest',
      'switch',
      'Eden',
      '${Directory.current.path}/.tool-cache/research/ra-wii-switch/media/11690.nsp',
      4,
      0xff304858,
      target: ControllerTarget.switchPro,
    );
    final api = SaveServer(),
        cloud = CloudSaves(
          data,
          notice: (message, problem) => stdout.writeln(message),
        );
    late CloudGame g;
    final problems = <String>[];
    // Use the supplied game's matching update, as the normal Broomm download
    // flow does. The unpatched Quest build can hit a native guest Break 0xE401
    // and spin in Eden's shutdown scheduler; that is upstream compatibility,
    // not an input acknowledgment. Package ownership is verified separately.
    final preparationLease = await SessionLease.acquire(data);
    try {
      final resolved = await manager.resolve(game, profile),
          payload = await root.createTemp('native-content-'),
          units = <String, dynamic>{};
      await stageEdenContent(
        File(game.rom),
        [
          (
            File(
              '${Directory.current.path}/.tool-cache/research/ra-wii-switch/media/11696.nsp',
            ),
            'update',
          ),
        ],
        Directory(resolved.emulator.root),
        payload,
        units,
        DateTime.now().toUtc().microsecondsSinceEpoch,
        DownloadCancellation(),
      );
      await PackageProfile(
        Directory(resolved.emulator.root),
        'eden',
      ).apply('$serverId/42', payload, units);
    } finally {
      await preparationLease.release();
    }
    final session = GameSession(
      Directory.current.path,
      managedRoot: data.path,
      testInputs: true,
      testPreconnected: true,
      resolve: (game) => manager.resolve(game, profile),
    );
    session.onProblem = problems.add;
    try {
      await session.launch(game);
      await session.waitFor(
        (s) => s.inputReady && s.paused == 1 && session.nativeProgramId != null,
        timeout: const Duration(seconds: 90),
      );
      final input = '${session.emulator!.root}/test-input.txt';
      Future<void> controls(String value) async {
        final f = value.split(' ');
        while (f.length < 5) f.add('0');
        await atomicText(input, '${f.join(' ')} 0 0 -32768 0 0 -32768 0 0 0 0');
      }

      await controls('0 0 3');
      final pairing = Pairing(4, target: ControllerTarget.switchPro)
        ..join(session.status!.testSourceIds.first)
        ..join(session.status!.testSourceIds.last);
      await session.command(pairing.players, active: true);
      await session.waitFor((s) => s.paused == 0 && !s.blocked);
      await session.waitFor((s) => s.paused == 0 && s.consolePorts == 3);
      await controls('2 0 3');
      await session.waitFor((s) => s.switchButtons & 1 != 0);
      await controls('0 0 3');
      await session.waitFor((s) => s.switchButtons == 0);
      await session.command(pairing.players, active: false);
      await session.waitFor((s) => s.paused == 1);
      expect(session.status!.paused, 1);
      pairing.toggleLayout(pairing.players.first.deviceId);
      await session.command(pairing.players, active: true);
      await session.waitFor((s) => s.paused == 0 && !s.blocked);
      await controls('2 0 3');
      await session.waitFor((s) => s.switchButtons & 2 != 0);
      await controls('0 0 3');
      await session.waitFor((s) => s.switchButtons == 0);
      await controls('0 0 2');
      await session.waitFor((s) => s.paused == 1 && s.request == 'disconnect');
      final program = session.nativeProgramId!,
          resolved = await manager.resolveProgress(game, profile);
      final identity = (await switchSourceIdentity(resolved)).$1;
      await session.stop();
      expect(problems, isEmpty, reason: problems.join('\n'));
      final lease = await SessionLease.acquire(data);
      try {
        await recordRyubingGame(resolved, program, identity);
        final layout = await gameProgressLayout(resolved, 'switch');
        g = CloudGame(
          server: serverId,
          profile: profile,
          user: 3,
          rom: 42,
          client: api,
          layout: layout,
        );
        await cloud.beforePlay(g);
        // Explicit fixture marker tests export/storage compatibility, not an in-game save point.
        await (await layout.target('save/broomm-integration-check'))
            .writeAsString('native Eden directory');
        await cloud.afterPlay(g, 0);
        final store = cloud.store(g), snap = await store.capture();
        expect(snap.entries.keys, contains('save/broomm-integration-check'));
        final exported = await store.exportNative(snap);
        try {
          final imported = await store.importNative(exported.file);
          expect(imported.ordinaryDigest, snap.ordinaryDigest);
        } finally {
          await exported.close();
        }
        expect((await store.state())['pending'], false);
      } finally {
        await lease.release();
      }
      await File('${root.path}/results.json').writeAsString(
        jsonEncode({
          'profileRoot': session.emulator!.root,
          'program': program,
          'nativeButtons': true,
          'twoConsolePorts': true,
          'liveRemap': true,
          'disconnectPause': true,
          'saveFixtureRoundTrip': true,
        }),
      );
      stdout.writeln('Eden evidence: ${root.path}');
    } finally {
      if (session.running) await session.stop();
      manager.dispose();
      api.close();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
