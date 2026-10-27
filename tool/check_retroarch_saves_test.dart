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
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/retroarch.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';

import '../test/cloud_saves_test.dart' show SaveServer, serverId;

class _Host extends DesktopHost {
  @override
  Future<void> show({List<double>? frame, bool overlay = false}) async {}
  @override
  Future<void> hide(int pid) async {}
}

void main() {
  test('real save-capable RA titles flush, upload, verify and restore native data after the writer exits', () async {
    final evidence = await Directory('.tool-cache/research/ra-save-followup')
        .createTemp('native-');
    final data = Directory('${evidence.absolute.path}/data');
    await data.create();
    final manager = ManagedEmulators(
      data,
      project: Directory.current.path,
      asset: (p) => File(p).readAsString(),
    );
    await manager.install(
      await manager.readPlan(
        file: 'tool/setup-development.json',
        only: {'retroarch'},
      ),
    );
    expect(manager.error, isNull, reason: manager.error);
    final media = (jsonDecode(
      await File('.tool-cache/research/ra-save-followup/media.json')
          .readAsString(),
    ) as List).cast<Map>();
    final owner = Directory('${Directory.current.path}/broomm-data');
    const ownerProfile = '15770cf1430ff66c406582cc4245ae63';
    final originals = Directory('${evidence.path}/originals');
    await originals.create();
    final sourceHashes = <String, String>{};
    final lease = await SessionLease.acquire(owner);
    try {
      for (final name in [
        'system/panafz1.bin',
        'system/panafz1-kanji.bin',
        'system/lynxboot.img',
        for (final p in ['A1', 'B1', 'C1', 'D1']) 'system/dc/vmu_save_$p.bin',
        'core-data/opera/6027/saves/opera/per_game/Crash n Burn.0.srm',
      ]) {
        final file = File(
          '${owner.path}/profiles/$ownerProfile/emulators/retroarch/$name',
        );
        if (!await file.exists()) continue;
        final before = await progressFileHash(file),
            target = File('${originals.path}/$name');
        await target.parent.create(recursive: true);
        await file.copy(target.path);
        expect(await progressFileHash(file), before);
        expect(await progressFileHash(target), before);
        sourceHashes[name] = before;
      }
    } finally {
      await lease.release();
    }
    final fixtures = <Map>[
      for (final m in media)
        {
          ...m,
          if (m['slug'] == 'lynx') 'statesOnly': true,
          if (m['slug'] == 'sega32') 'eepromSeed': true,
        },
      if (await File('.tool-cache/research/saturn/fixture.json').exists())
        jsonDecode(
          await File('.tool-cache/research/saturn/fixture.json').readAsString(),
        ) as Map,
      {
        'slug': '3do',
        'rom': 6027,
        'name': "Crash 'n Burn",
        'path': 'broomm-data/library/506d439865d8f46267001bdd3a1fe0e5/6027/content/Crash n Burn.chd',
      },
      {
        'slug': 'dc',
        'rom': 6900,
        'name': 'Crazy Taxi',
        'legacyVmus': true,
        'path': 'broomm-data/library/506d439865d8f46267001bdd3a1fe0e5/6900/content/Crazy Taxi.chd',
      },
      {
        'slug': 'nes',
        'rom': 3745,
        'name': '1943',
        'path': 'broomm-data/library/506d439865d8f46267001bdd3a1fe0e5/3745/content/1943 - The Battle of Midway (USA).nes',
        'noSave': true,
      },
      {
        'slug': 'dc',
        'rom': 6900,
        'name': 'Crazy Taxi (fresh VMUs)',
        'path': 'broomm-data/library/506d439865d8f46267001bdd3a1fe0e5/6900/content/Crazy Taxi.chd',
      },
    ];
    final results = <Map<String, dynamic>>[], failures = <String>[];
    var index = 0;
    for (final fixture in fixtures) {
      final selected = Platform.environment['BROOMM_SAVE_PLATFORMS']?.split(
        ',',
      );
      if (selected != null && !selected.contains(fixture['slug'])) continue;
      final profile = (++index).toRadixString(16).padLeft(32, '0');
      final slug = fixture['slug'] as String, spec = retroSystem(slug)!;
      final game = LaunchGame(
        '${fixture['rom']}',
        fixture['name'] as String,
        slug,
        'RetroArch',
        File(fixture['path'] as String).absolute.path,
        spec.players,
        0xff345678,
        target: spec.target,
        retroCore: spec.core,
      );
      final api = SaveServer(),
          c = CloudSaves(data, notice: (m, p) => stdout.writeln('$slug: $m'));
      late CloudGame cloudGame;
      final problems = <String>[];
      final session = GameSession(
        Directory.current.path,
        managedRoot: data.path,
        testInputs: true,
        resolve: (g) async {
          // Establish profile/firmware and legacy fixtures before the resolver's
          // production VMU migration, without changing normal user progress.
          if (slug == 'dc' && fixture['legacyVmus'] == true) {
            await manager.resolveConfiguration('RetroArch', profile);
            final root = '${data.path}/profiles/$profile/emulators/retroarch';
            for (final p in ['A1', 'B1', 'C1', 'D1']) {
              final target = File('$root/system/dc/vmu_save_$p.bin');
              await target.parent.create(recursive: true);
              await File('${originals.path}/system/dc/vmu_save_$p.bin')
                  .copy(target.path);
            }
          }
          final r = await manager.resolve(g, profile);
          if (slug == 'saturn') {
            for (final bios in (fixture['bios'] as List).cast<Map>()) {
              final target = File('${r.emulator.root}/system/${bios['name']}');
              await target.parent.create(recursive: true);
              await File(bios['path'] as String).copy(target.path);
              expect(await progressFileHash(target), bios['sha256']);
            }
          }
          for (final file in [
            if (slug == '3do') ...['panafz1.bin', 'panafz1-kanji.bin'],
            if (slug == 'lynx') 'lynxboot.img',
          ]) {
            final target = File('${r.emulator.root}/system/$file');
            await target.parent.create(recursive: true);
            await File('${originals.path}/system/$file').copy(target.path);
          }
          if (slug == '3do') {
            const name =
                'core-data/opera/6027/saves/opera/per_game/Crash n Burn.0.srm';
            final target = File('${r.emulator.root}/$name');
            await target.parent.create(recursive: true);
            await File('${originals.path}/$name').copy(target.path);
          }
          if (slug == 'dc') {
            final options = File(
              '${r.emulator.root}/config/Flycast/Flycast.opt',
            );
            await options.parent.create(recursive: true);
            await options.writeAsString(
              'reicast_per_content_vmus = "disabled"\n',
            );
          }
          if (fixture['eepromSeed'] == true) {
            // PicoDrive suppresses an all-zero EEPROM until a game writes it.
            // This tests native load/flush separately from a completed match.
            final stem = await retroSaveStem(g.rom, spec.core);
            final target = File(
              '${r.emulator.root}/${retroGameDirectory(spec.core, g.id)}/saves/$stem.srm',
            );
            await target.parent.create(recursive: true);
            await target.writeAsBytes(List.generate(8192, (i) => i % 251));
          }
          await File('${r.emulator.root}/retroarch.cfg')
              .writeAsString('log_verbosity = "true"\n', mode: FileMode.append);
          cloudGame = CloudGame(
            server: serverId,
            profile: profile,
            user: 3,
            rom: 42,
            client: api,
            layout: await gameProgressLayout(r, slug),
          );
          await c.beforePlay(cloudGame);
          return r;
        },
      );
      session.onProblem = problems.add;
      session.finalizeProgress = (exit) => c.afterPlay(cloudGame, exit);
      final model = PrototypeModel(
        Directory.current.path,
        host: _Host(),
        gameSession: session,
      );
      try {
        await model.select(game);
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (DateTime.now().isBefore(deadline) &&
            session.running &&
            model.screen != Screen.pairing)
          await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          model.screen,
          Screen.pairing,
          reason: '${game.title}: ${model.error} ${model.notice}',
        );
        final input = '${session.emulator!.root}/test-input.txt';
        await atomicText(input, '0 0 3');
        await session.waitFor(
          (s) =>
              s.inputReady &&
              s.testSourceIds.length == 2 &&
              s.paused == 1 &&
              s.devices.every((d) => d.buttons == 0),
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await atomicText(input, '1536 0 3');
        final joined = DateTime.now().add(const Duration(seconds: 5));
        while (model.pairing!.players.isEmpty &&
            DateTime.now().isBefore(joined))
          await Future<void>.delayed(const Duration(milliseconds: 32));
        expect(model.pairing!.players, hasLength(1));
        await atomicText(input, '0 0 3');
        await Future<void>.delayed(const Duration(milliseconds: 180));
        await model.play();
        expect(model.screen, Screen.playing, reason: model.error);
        if (slug == 'saturn') {
          final pid = session.processId;
          await model.menu();
          expect(model.paused, true);
          model.showPairing();
          model.layout(model.pairing!.players.first.deviceId);
          await model.play();
          expect(model.screen, Screen.playing, reason: model.error);
          expect(session.processId, pid);
        }
        if (slug == 'dc') {
          final opened = await Process.run('/usr/sbin/lsof', [
            '-a',
            '-p',
            '${session.processId}',
            '-Fn',
          ]);
          expect(opened.exitCode, 0, reason: '${opened.stderr}');
          final vmu = (opened.stdout as String)
              .split('\n')
              .where(
                (s) =>
                    s.endsWith('.bin') &&
                    (s.contains('vmu_save_') ||
                        RegExp(r'\.[A-D][12]\.bin$').hasMatch(s)),
              )
              .toList();
          expect(vmu, hasLength(4));
          expect(
            vmu.every(
              (s) => s.contains('/core-data/flycast/${game.id}/saves/'),
            ),
            true,
            reason: vmu.join('\n'),
          );
        }
        for (var i = 0; i < 3; i++) {
          await Future<void>.delayed(const Duration(seconds: 3));
          await atomicText(input, '64 0 3');
          await Future<void>.delayed(const Duration(milliseconds: 180));
          await atomicText(input, '0 0 3');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        if (fixture['statesOnly'] == true ||
            {'3do', 'dc', 'saturn'}.contains(slug)) {
          final port = int.parse(
            RegExp(r'network_cmd_port = "([0-9]+)"').firstMatch(
              await File('${session.emulator!.root}/retroarch.cfg')
                  .readAsString(),
            )![1]!,
          );
          final socket = await RawDatagramSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          socket.send(
            utf8.encode('SAVE_STATE'),
            InternetAddress.loopbackIPv4,
            port,
          );
          try {
            await Future<void>.delayed(const Duration(seconds: 1));
            if (slug == 'saturn') {
              final area = cloudGame.layout.areas.singleWhere(
                (a) => a.id.startsWith('states-'),
              );
              final state = File(
                '${session.emulator!.root}/${area.path}/${area.native('game')}',
              );
              expect(await state.exists(), true);
              expect(await state.length(), greaterThan(0));
              socket.send(
                utf8.encode('LOAD_STATE'),
                InternetAddress.loopbackIPv4,
                port,
              );
              await Future<void>.delayed(const Duration(seconds: 1));
            }
          } finally {
            socket.close();
          }
        }
        await model.stop();
        expect(problems, isEmpty, reason: problems.join('\n'));
        if (slug == 'saturn') {
          final log = await File('${session.emulator!.root}/broomm.log')
              .readAsString();
          expect(log, contains('[State] Loading state'));
          expect(log, isNot(contains('Failed to load state')));
        }
        final store = c.store(cloudGame), snapshot = await store.capture();
        final saves = snapshot.entries.keys
            .where((k) => !k.startsWith('states-'))
            .toList();
        results.add({
          'slug': slug,
          'rom': fixture['rom'],
          'title': game.title,
          'root': session.emulator!.root,
          'saveFiles': {for (final key in saves) key: snapshot.entries[key]},
          'stateKeys': snapshot.entries.keys
              .where((k) => k.startsWith('states-'))
              .toList(),
          'uploaded': [
            for (final s in api.records.values)
              {'name': s.name, 'bytes': s.bytes},
          ],
          'pending': (await store.state())['pending'],
          if (fixture['eepromSeed'] == true) 'source': 'test EEPROM sentinel; native load/flush, not game-created progress',
        });
        if (fixture['noSave'] == true) {
          expect(saves, isEmpty);
          expect(api.records, isEmpty);
        } else if (fixture['statesOnly'] == true) {
          expect(saves, isEmpty);
          expect(snapshot.hasStates, true);
          expect(api.records, isNotEmpty);
          expect((await store.state())['pending'], false);
          final restored = await store.importBundle(snapshot.bundle);
          expect(restored.digest, snapshot.digest);
          results.last['matchedStateVerified'] = true;
        } else {
          if (fixture['eepromSeed'] == true) {
            final log = await File('${session.emulator!.root}/broomm.log')
                .readAsString();
            expect(log, contains('[SRAM] Saved successfully'));
          }
          expect(
            saves,
            isNotEmpty,
            reason: '${game.title}: no native save produced',
          );
          expect((await store.state())['pending'], false);
          expect(api.records, isNotEmpty);
          final exported = await store.exportNative(snapshot);
          try {
            final imported = await store.importNative(exported.file);
            expect(imported.ordinaryDigest, snapshot.ordinaryDigest);
            for (final f in (await cloudGame.layout.files()).values)
              await f.delete();
            await store.restore(imported, {});
            expect(
              (await store.capture()).ordinaryDigest,
              snapshot.ordinaryDigest,
            );
            results.last['nativeExportRestoreVerified'] = true;
            if (slug == 'saturn') {
              expect(snapshot.hasStates, true);
              final importedState = await store.importBundle(snapshot.bundle);
              expect(importedState.digest, snapshot.digest);
              await store.restore(importedState, {});
              expect((await store.capture()).digest, snapshot.digest);
              results.last['pauseAndLiveRemapVerified'] = true;
              results.last['matchedStateRestoreVerified'] = true;
            }
          } finally {
            await exported.close();
          }
        }
      } catch (e, st) {
        failures.add('${game.title}: $e');
        results.add({
          'slug': slug,
          'rom': fixture['rom'],
          'error': '$e',
          'stack': '$st',
        });
      } finally {
        if (session.running) await model.stop();
        model.dispose();
        api.close();
      }
    }
    expect(
      results,
      isNotEmpty,
      reason: 'No cached fixture matches BROOMM_SAVE_PLATFORMS',
    );
    await File('${evidence.path}/results.json').writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert({'fixtures': results, 'sourceHashes': sourceHashes}),
    );
    manager.dispose();
    stdout.writeln('Native save evidence: ${evidence.path}');
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
