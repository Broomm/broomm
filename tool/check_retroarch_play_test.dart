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
import 'package:broomm/src/retroarch.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/session_lease.dart';

class _Host extends DesktopHost {
  @override
  Future<void> show({List<double>? frame, bool overlay = false}) async {}
  @override
  Future<void> hide(int pid) async {}
}

void main() {
  test('new cores play cached RomM games, pause/remap, and use isolated native SRAM/state paths', () async {
    final evidence = await Directory('.tool-cache/research/ra-wii-switch')
        .createTemp('native-retro-play-');
    final data = Directory('${evidence.absolute.path}/data');
    await data.create();
    const profile = 'a123456789abcdef0123456789abcdef';
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
    final results = <Map<String, dynamic>>[], failures = <String>[];
    for (final fixture in [
      ('gb', '1650.gb'),
      ('gba', '2518.gba'),
      ('nes', '3931.nes'),
      ('genesis', '6296.zip'),
      ('atari2600', '9916.a26'),
      ('jaguar', '6450.j64'),
      ('n64', '3439.z64'),
      ('sega32', '6826.32x'),
      ('gamegear', '11006.zip'),
      ('sms', '6842.zip'),
      ('tg16', '962.pce'),
      ('arcade', '10519.zip'),
      ('gbc', '2884.gbc'),
    ]) {
      final spec = retroSystem(fixture.$1)!;
      var rom = File('.tool-cache/research/ra-wii-switch/media/${fixture.$2}')
          .absolute
          .path;
      if (fixture.$1 == 'arcade') {
        // FBNeo selects its driver using the original ROMset archive name.
        final j = jsonDecode(
          await File('.tool-cache/research/ra-wii-switch/media/433.json')
              .readAsString(),
        ) as Map;
        final target = File(
          '${evidence.path}/${(j['files'] as List).single['file_name']}',
        );
        await File(rom).copy(target.path);
        rom = target.absolute.path;
      }
      final game = LaunchGame(
        fixture.$1,
        fixture.$1,
        fixture.$1,
        'RetroArch',
        rom,
        spec.players,
        0xff345678,
        target: spec.target,
        retroCore: spec.core,
      );
      final session = GameSession(
        Directory.current.path,
        managedRoot: data.path,
        testInputs: true,
        resolve: (g) async {
          final r = await manager.resolve(g, profile);
          await File('${r.emulator.root}/retroarch.cfg')
              .writeAsString('log_verbosity = "true"\n', mode: FileMode.append);
          return r;
        },
      );
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
          reason: '${game.id}: ${model.error} ${model.notice}',
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
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await atomicText(input, '1536 0 3');
        final joined = DateTime.now().add(const Duration(seconds: 5));
        while (model.pairing!.players.isEmpty &&
            DateTime.now().isBefore(joined))
          await Future<void>.delayed(const Duration(milliseconds: 32));
        expect(model.pairing!.players, hasLength(1));
        await atomicText(input, '0 0 3');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await model.play();
        expect(model.screen, Screen.playing, reason: model.error);
        await model.menu();
        expect(model.paused, true);
        model.showPairing();
        model.layout(model.pairing!.players.first.deviceId);
        await model.play();
        expect(model.screen, Screen.playing, reason: model.error);
        // Ask the actual frontend to serialize this core, rather than planting
        // a synthetic .state. Its configured filename must match cloud capture.
        final socket = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        socket.send(
          utf8.encode('SAVE_STATE'),
          InternetAddress.loopbackIPv4,
          int.parse(
            RegExp(r'network_cmd_port = "([0-9]+)"').firstMatch(
              await File('${session.emulator!.root}/retroarch.cfg')
                  .readAsString(),
            )![1]!,
          ),
        );
        socket.close();
        await Future<void>.delayed(const Duration(seconds: 2));
        await model.stop();
        final resolved = await manager.resolveProgress(game, profile),
            layout = await gameProgressLayout(resolved, spec.slug);
        final files = await layout.files();
        final states = files.keys
            .where((k) => k.startsWith('states-'))
            .toList();
        expect(
          states,
          isNotEmpty,
          reason: '${spec.core}: native state location differs: ${files.keys}',
        );
        final lease = await SessionLease.acquire(data);
        try {
          final store = ProgressStore(
            Directory('${data.path}/roundtrip/${game.id}'),
            layout,
            1,
            1,
            ownerRoot: data,
          );
          final snap = await store.capture();
          final saves = snap.entries.keys
              .where((k) => k.startsWith('save/'))
              .toList();
          if ({'gb', 'gba'}.contains(spec.slug))
            expect(
              saves,
              isNotEmpty,
              reason: 'Battery-backed test cartridge must produce native SRAM',
            );
          if (saves.isNotEmpty) {
            final exported = await store.exportNative(snap);
            try {
              final imported = await store.importNative(exported.file);
              expect(imported.ordinaryDigest, snap.ordinaryDigest);
            } finally {
              await exported.close();
            }
          }
          results.add({
            'platform': spec.slug,
            'core': spec.core,
            'saveKeys': saves,
            'stateKeys': states,
            'play': true,
            'liveRemap': true,
            'cloudNativeRoundTrip': saves.isNotEmpty,
          });
        } finally {
          await lease.release();
        }
      } catch (e) {
        failures.add('${spec.slug}: $e');
        results.add({'platform': spec.slug, 'error': '$e'});
      } finally {
        if (session.running) await model.stop();
        model.dispose();
      }
    }
    await File('${evidence.path}/results.json')
        .writeAsString(jsonEncode(results));
    manager.dispose();
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
