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
import 'package:broomm/src/playstation_firmware.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session.dart';

import '../test/cloud_saves_test.dart' show SaveServer, serverId;

class _Host extends DesktopHost {
  @override
  Future<void> show({List<double>? frame, bool overlay = false}) async {}
  @override
  Future<void> hide(int pid) async {}
}

class _Server extends SaveServer {
  _Server(this.bios, this.platform);
  final Map bios;
  final int platform;
  var firmwareDownloads = 0;
  @override
  Future<List<RommFirmware>> firmware(int platformId) async => [
    RommFirmware(
      1,
      platform,
      'bios.bin',
      bios['bytes'] as int,
      bios['md5'] as String,
    ),
  ];
  @override
  Future<void> downloadFirmware(
    RommFirmware f,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    cancellation.check();
    await File(bios['path'] as String).copy(destination.path);
    firmwareDownloads++;
    onProgress(await destination.length());
  }
}

void main() {
  test('real PS1 and both PS2 emulators pair, pause/remap and round-trip private native cards/states', () async {
    final root = await Directory('.tool-cache/research/playstation')
        .createTemp('native-');
    final data = await Directory('${root.absolute.path}/data').create();
    final manager = ManagedEmulators(
      data,
      project: Directory.current.path,
      asset: (p) => File(p).readAsString(),
    );
    await manager.install(
      await manager.readPlan(only: {'duckstation', 'armsx2', 'pcsx2'}),
    );
    expect(manager.error, isNull, reason: manager.error);
    final media = (jsonDecode(
      await File('.tool-cache/research/playstation/media.json').readAsString(),
    ) as List).cast<Map>();
    final results = <Map<String, dynamic>>[], failures = <String>[];
    final servers = {
      for (final m in media)
        m['slug'] as String: _Server(
          m['bios'] as Map,
          m['slug'] == 'psx' ? 23 : 10,
        ),
    };
    final cloud = CloudSaves(data, notice: (m, p) => stdout.writeln(m));
    for (final (engine, slug) in [
      ('DuckStation', 'psx'),
      ('ARMSX2', 'ps2'),
      ('PCSX2', 'ps2'),
    ]) {
      if (Platform.environment['BROOMM_SONY_EMULATORS'] case final selected?)
        if (!selected.split(',').contains(engine)) continue;
      final fixture = media.singleWhere((m) => m['slug'] == slug);
      final api = servers[slug]!;
      final profile = (slug == 'psx' ? '1' : '2') * 32;
      final game = LaunchGame(
        '${fixture['rom']}',
        fixture['title'] as String,
        slug,
        engine,
        File(fixture['path'] as String).absolute.path,
        2,
        0xff345678,
        target: slug == 'psx' ? ControllerTarget.psx : ControllerTarget.ps2,
      );
      late CloudGame cloudGame;
      final problems = <String>[];
      final session = GameSession(
        Directory.current.path,
        managedRoot: data.path,
        testInputs: true,
        testPreconnected: true,
        resolve: (g) async {
          final resolved = await manager.resolve(g, profile);
          await ensurePlayStationFirmware(
            resolved,
            api.platform,
            api,
            DownloadCancellation(),
            stdout.writeln,
          );
          final calls = api.firmwareDownloads;
          await ensurePlayStationFirmware(
            resolved,
            api.platform,
            api,
            DownloadCancellation(),
            stdout.writeln,
          );
          expect(api.firmwareDownloads, calls);
          cloudGame = CloudGame(
            server: serverId,
            profile: profile,
            user: 3,
            rom: 42,
            client: api,
            layout: await gameProgressLayout(resolved, slug),
          );
          await cloud.beforePlay(cloudGame);
          return resolved;
        },
      );
      session.onProblem = problems.add;
      session.finalizeProgress = (exit) => cloud.afterPlay(cloudGame, exit);
      final model = PrototypeModel(
        Directory.current.path,
        host: _Host(),
        gameSession: session,
      );
      try {
        stdout.writeln('Testing $engine / ${game.title}');
        await model.select(game);
        final ready = DateTime.now().add(const Duration(seconds: 75));
        while (session.running &&
            model.screen != Screen.pairing &&
            DateTime.now().isBefore(ready))
          await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          model.screen,
          Screen.pairing,
          reason: '$engine: ${model.error} ${model.notice}',
        );
        final input = '${session.emulator!.root}/test-input.txt';
        await atomicText(input, '0 0 3');
        final neutralSample = session.status!.sample;
        await session.waitFor(
          (s) =>
              s.sample > neutralSample + 1 &&
              model.canPair &&
              s.inputReady &&
              s.testSourceIds.length == 2 &&
              s.testSourceIds.every((id) => s.devices.any((d) => d.id == id)) &&
              s.devices.every((d) => d.buttons == 0),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await atomicText(input, '1536 0 3');
        final join = DateTime.now().add(const Duration(seconds: 5));
        while (model.pairing!.players.isEmpty && DateTime.now().isBefore(join))
          await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(model.pairing!.players, hasLength(1));
        await atomicText(input, '0 0 3');
        await Future<void>.delayed(const Duration(milliseconds: 180));
        await model.play();
        expect(model.screen, Screen.playing, reason: model.error);
        final pid = session.processId;
        await model.menu();
        expect(model.paused, true);
        model.showPairing();
        model.layout(model.pairing!.players.first.deviceId);
        await model.play();
        expect(model.screen, Screen.playing, reason: model.error);
        expect(session.processId, pid);
        for (var i = 0; i < 3; i++) {
          await Future<void>.delayed(const Duration(seconds: 2));
          await atomicText(input, '64 0 3');
          await Future<void>.delayed(const Duration(milliseconds: 180));
          await atomicText(input, '0 0 3');
        }
        if (slug == 'psx') {
          // Let the native intro finish, then enter the game's own save flow.
          // A fresh DuckStation card is intentionally not flushed until dirty.
          for (var i = 0; i < 12; i++) {
            await Future<void>.delayed(const Duration(seconds: 2));
            await atomicText(input, '${i < 3 ? 64 : 2} 0 3');
            await Future<void>.delayed(const Duration(milliseconds: 180));
            await atomicText(input, '0 0 3');
          }
        }
        await atomicText(input, '0 0 3 0 2');
        await Future<void>.delayed(const Duration(seconds: 3));
        await atomicText(input, '0 0 3');
        if (slug == 'ps2') {
          await atomicText(input, '0 0 3 0 3');
          await Future<void>.delayed(const Duration(seconds: 2));
          await atomicText(input, '0 0 3');
        }
        // The assigned source disappears. Native input must gate, acknowledge
        // pause and reopen pairing before another source can take its place.
        await atomicText(input, '0 0 2');
        final disconnected = DateTime.now().add(const Duration(seconds: 6));
        while ((model.screen != Screen.pairing ||
                model.pairing!.players.isNotEmpty ||
                model.busy ||
                !model.canPair) &&
            DateTime.now().isBefore(disconnected)) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        expect(model.screen, Screen.pairing);
        expect(model.paused, true);
        expect(model.pairing!.players, isEmpty);
        // Readiness changes deliberately disarm gestures. Observe a fresh
        // neutral sample after pause has finished before pressing the chord.
        final released = session.status!.sample;
        await session.waitFor(
          (s) => s.sample > released && s.devices.every((d) => d.buttons == 0),
        );
        await atomicText(input, '0 1536 2');
        final replacement = DateTime.now().add(const Duration(seconds: 5));
        while (model.pairing!.players.isEmpty &&
            DateTime.now().isBefore(replacement))
          await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(model.pairing!.players, hasLength(1));
        await atomicText(input, '0 0 2');
        await Future<void>.delayed(const Duration(milliseconds: 180));
        await model.play();
        expect(model.screen, Screen.playing);
        expect(session.processId, pid);
        await model.stop();
        expect(problems, isEmpty, reason: problems.join('\n'));
        final store = cloud.store(cloudGame), snapshot = await store.capture();
        final cards = snapshot.entries.keys
            .where((k) => k.startsWith('save/'))
            .toList();
        results.add({
          'emulator': engine,
          'slug': slug,
          'root': session.emulator!.root,
          'saveFiles': {for (final k in cards) k: snapshot.entries[k]},
          'stateKeys': snapshot.entries.keys
              .where((k) => k.startsWith('states-'))
              .toList(),
          'uploaded': [
            for (final r in api.records.values)
              {'name': r.name, 'bytes': r.bytes},
          ],
          'uploadedStates': [
            for (final r in api.stateRecords.values)
              {'name': r.name, 'bytes': r.bytes},
          ],
          'firmwareDownloads': api.firmwareDownloads,
          'pending': (await store.state())['pending'],
        });
        expect(cards, isNotEmpty, reason: '$engine produced no ordinary save');
        expect(
          snapshot.hasStates,
          true,
          reason: '$engine produced no native state',
        );
        expect(api.records, isNotEmpty);
        expect(api.stateRecords, isNotEmpty);
        expect((await store.state())['pending'], false);
        final checkpoint = await store.state();
        final exported = await store.exportNative(snapshot);
        try {
          final imported = await store.importNative(exported.file);
          expect(imported.ordinaryDigest, snapshot.ordinaryDigest);
          for (final f in (await cloudGame.layout.files()).values)
            await f.delete();
          await store.restore(imported, checkpoint);
          expect(
            (await store.capture()).ordinaryDigest,
            snapshot.ordinaryDigest,
          );
          final full = await store.importBundle(snapshot.bundle);
          await store.restore(full, checkpoint);
          expect((await store.capture()).digest, snapshot.digest);
        } finally {
          await exported.close();
        }
        results.last['nativeExportRestoreVerified'] = true;
        results.last['pauseAndLiveRemapVerified'] = true;
        results.last['disconnectAndReassignmentVerified'] = true;
      } catch (e, st) {
        failures.add('$engine: $e');
        results.add({
          'emulator': engine,
          'error': '$e',
          'stack': '$st',
          'pid': session.processId,
          'root': session.emulator?.root,
        });
      } finally {
        // Cleanup must await the supervisor even if a UI assertion failed
        // while PrototypeModel was still applying a pause acknowledgement.
        if (session.running || session.finalizingProgress) await session.stop();
        model.dispose();
      }
    }
    expect(results, isNotEmpty);
    for (final api in servers.values) api.close();
    await File('${root.path}/results.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(results));
    manager.dispose();
    stdout.writeln('PlayStation native evidence: ${root.path}');
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
