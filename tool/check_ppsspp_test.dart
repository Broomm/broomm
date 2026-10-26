@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/app_model.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/host.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/session.dart';

import '../test/cloud_saves_test.dart' show SaveServer, serverId;

class _Host extends DesktopHost {
  @override
  Future<void> show({List<double>? frame, bool overlay = false}) async {}
  @override
  Future<void> hide(int pid) async {}
}

void main() {
  test('native PPSSPP pairs in its SDL runtime, pauses/remaps, recovers disconnects and syncs PSP progress', () async {
    final root = await Directory('.tool-cache/research/psp')
            .createTemp('native-'),
        data = await Directory('${root.absolute.path}/data').create();
    final manager = ManagedEmulators(
      data,
      project: Directory.current.path,
      asset: (p) => File(p).readAsString(),
    );
    await manager.install(await manager.readPlan(only: {'ppsspp'}));
    expect(manager.error, isNull, reason: manager.error);
    final media = (jsonDecode(
      await File('.tool-cache/research/psp/media.json').readAsString(),
    ) as List).cast<Map>();
    final results = <Map<String, dynamic>>[];
    for (final fixture in media.reversed.where(
      (f) =>
          Platform.environment['BROOMM_PSP_ONLY'] == null ||
          '${f['rom']}' == Platform.environment['BROOMM_PSP_ONLY'],
    )) {
      final profile = '${media.indexOf(fixture) + 1}'.padLeft(32, '0');
      final api = SaveServer(),
          cloud = CloudSaves(data, notice: (m, p) => stdout.writeln(m));
      final game = LaunchGame(
        '${fixture['rom']}',
        fixture['name'] as String,
        'psp',
        'PPSSPP',
        fixture['path'] as String,
        1,
        0xff304858,
        target: ControllerTarget.psp,
      );
      late CloudGame g;
      final problems = <String>[];
      final session = GameSession(
        Directory.current.path,
        managedRoot: data.path,
        testInputs: true,
        testPreconnected: true,
        resolve: (game) async {
          final r = await manager.resolve(game, profile);
          g = CloudGame(
            server: serverId,
            profile: profile,
            user: 3,
            rom: 42,
            client: api,
            layout: await gameProgressLayout(r, 'psp'),
          );
          await cloud.beforePlay(g);
          return r;
        },
      );
      session.onProblem = problems.add;
      session.finalizeProgress = (exit) => cloud.afterPlay(g, exit);
      final model = PrototypeModel(
        Directory.current.path,
        host: _Host(),
        gameSession: session,
      );
      final presentProblem = session.onProblem;
      session.onProblem = (message) {
        problems.add(message);
        presentProblem?.call(message);
      };
      var lastGate = '';
      model.addListener(() {
        final gate =
            '${model.screen}/${model.busy}/${model.canPair}/${session.status?.paused}';
        if (gate != lastGate) {
          stdout.writeln('PSP gate $gate');
          lastGate = gate;
        }
      });
      try {
        stdout.writeln('Testing PPSSPP / ${game.title}');
        await model.select(game);
        final ready = DateTime.now().add(const Duration(seconds: 60));
        while (session.running &&
            model.screen != Screen.pairing &&
            DateTime.now().isBefore(ready))
          await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(
          model.screen,
          Screen.pairing,
          reason: '${model.error} ${model.notice}',
        );
        final input = '${session.emulator!.root}/test-input.txt';
        Future<void> controls(String text) {
          final fields = text.split(' ');
          while (fields.length < 5) fields.add('0');
          return atomicText(
            input,
            '${fields.join(' ')} 0 0 -32768 0 0 -32768 0 0 0 0',
          );
        }

        final available = DateTime.now().add(const Duration(seconds: 8));
        while (!model.canPair && DateTime.now().isBefore(available)) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        expect(model.canPair, true);
        await controls('0 0 3');
        var sample = session.status!.sample;
        await session.waitFor(
          (s) =>
              s.sample > sample + 1 &&
              model.canPair &&
              s.devices.every((d) => d.buttons == 0),
        );
        await controls('1536 0 3');
        final joined = DateTime.now().add(const Duration(seconds: 5));
        while (model.pairing!.players.isEmpty &&
            DateTime.now().isBefore(joined))
          await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          model.pairing!.players,
          hasLength(1),
          reason:
              'screen=${model.screen} busy=${model.busy} canPair=${model.canPair} error=${model.error} notice=${model.notice} devices=${model.devices.map((d) => '${d.id}:${d.buttons}').join(',')}',
        );
        await controls('0 0 3');
        await Future<void>.delayed(const Duration(milliseconds: 180));
        final settled = DateTime.now().add(const Duration(seconds: 8));
        while (model.busy && DateTime.now().isBefore(settled)) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        await model.play();
        expect(model.screen, Screen.playing, reason: model.error);
        final pid = session.processId;
        await controls('1 0 3');
        await session.waitFor((s) => s.pspButtons & 0x4000 != 0);
        await controls('0 0 3');
        await session.waitFor((s) => s.pspButtons == 0);
        await model.menu();
        expect(model.paused, true);
        model.showPairing();
        model.layout(model.pairing!.players.first.deviceId);
        await model.play();
        await controls('1 0 3');
        await session.waitFor((s) => s.pspButtons & 0x2000 != 0);
        await controls('0 0 3');
        await model.menu();
        model.showPairing();
        model.layout(model.pairing!.players.first.deviceId);
        await model.play();
        // Native title/menu input: enter and confirm the game's initial save
        // prompts without writing a fabricated save into its native directory.
        for (var i = 0; i < 45; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
          await controls(
            '${i < 3
                ? 64
                : fixture['rom'] == 5973
                ? 2
                : 1} 0 3',
          );
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await controls('0 0 3');
        }
        await controls('0 0 3 0 2');
        await Future<void>.delayed(const Duration(seconds: 3));
        await controls('0 0 3');
        await controls('0 0 3 0 3');
        await Future<void>.delayed(const Duration(seconds: 2));
        await controls('0 0 2');
        final detached = DateTime.now().add(const Duration(seconds: 6));
        while ((model.screen != Screen.pairing ||
                model.busy ||
                !model.canPair ||
                model.pairing!.players.isNotEmpty) &&
            DateTime.now().isBefore(detached))
          await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(model.screen, Screen.pairing);
        expect(model.paused, true);
        expect(model.pairing!.players, isEmpty);
        sample = session.status!.sample;
        await session.waitFor(
          (s) =>
              s.sample > sample + 1 &&
              model.canPair &&
              s.devices.every((d) => d.buttons == 0),
        );
        await controls('0 1536 2');
        final replacement = DateTime.now().add(const Duration(seconds: 5));
        while (model.pairing!.players.isEmpty &&
            DateTime.now().isBefore(replacement))
          await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(model.pairing!.players, hasLength(1));
        await controls('0 0 2');
        await Future<void>.delayed(const Duration(milliseconds: 180));
        await model.play();
        expect(session.processId, pid);
        await model.stop();
        expect(problems, isEmpty, reason: problems.join('\n'));
        final store = cloud.store(g),
            snap = await store.capture(),
            checkpoint = await store.state();
        // N+ creates savedata during its initial setup and is the required
        // ordinary-save fixture. Puzzle Bobble saves after gameplay results;
        // its random bubbles/timing do not guarantee a cleared round here.
        // With only states, the existing cloud protocol publishes the full
        // state bundle as the BROOMM version, without inventing savedata or a
        // separate ordinary-save/state companion pair.
        final ordinary = snap.entries.keys.any((k) => k.startsWith('save/'));
        if (fixture['rom'] == 5953)
          expect(ordinary, true, reason: 'N+ did not create native savedata');
        expect(snap.hasStates, true);
        expect(api.records, isNotEmpty);
        expect(api.stateRecords.isNotEmpty, ordinary);
        expect(
          api.readIds.toSet(),
          containsAll({...api.records.keys, ...api.stateRecords.keys}),
        );
        expect(checkpoint['pending'], false);
        final exported = await store.exportNative(snap);
        try {
          final imported = exported.includesStates
              ? await store.importBundle(exported.file)
              : await store.importNative(exported.file);
          for (final file in (await g.layout.files()).values)
            await file.delete();
          await store.restore(imported, checkpoint);
          expect((await store.capture()).ordinaryDigest, snap.ordinaryDigest);
        } finally {
          await exported.close();
        }
        await store.restore(await store.importBundle(snap.bundle), checkpoint);
        expect((await store.capture()).digest, snap.digest);
        results.add({
          'rom': fixture['rom'],
          'title': game.title,
          'root': session.emulator!.root,
          'files': snap.entries,
          'ordinaryRoundTrip': ordinary,
          'stateOnlyBundle': !ordinary,
          'stateSaveLoadAndRestore': true,
          'nativeButtonReadbackAndFaceSwap': true,
          'disconnectReassignment': true,
          'pending': false,
        });
      } finally {
        if (session.running || session.finalizingProgress) await session.stop();
        model.dispose();
        api.close();
        await File('${root.path}/results.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(results));
      }
    }
    manager.dispose();
    stdout.writeln('PPSSPP native evidence: ${root.path}');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
