@TestOn('linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/emulator_configuration.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/cloud_saves_test.dart' show SaveServer, serverId, profileId;

void main() {
  test('native Linux setup, pairing, pause, disconnect and native progress', () async {
    final fixture = Directory('.tool-cache/research/linux').absolute;
    final root = await fixture.createTemp('integration-');
    final data = await Directory('${root.path}/data').create();
    final manager = ManagedEmulators(
      data,
      asset: (p) => File(p).readAsString(),
    );
    final problems = <String>[];
    GameSession? session;
    Future<void> Function()? closeConfiguration;
    final checks = <String>[];
    try {
      await manager.load();
      expect(manager.host, 'linux-x64');
      final full = await manager.readPlan();
      final plan = SetupPlan(
        full.items.where((i) => i.build.id == 'retroarch').toList(),
      );
      expect(plan.items.single.build.id, 'retroarch');
      // Public reviewed archives were acquired separately. Seed only private
      // completed download caches; the production path still hashes/extracts.
      for (final p in plan.items.single.downloads.values) {
        final dir = await Directory(
          '${data.path}/setup-downloads/.download-${p.sha256}',
        ).create(recursive: true);
        final name = p.entry == 'RetroArch'
            ? 'retroarch-linux-x64.zip'
            : 'cores/${p.entry.replaceFirst('_libretro.so', '')}.zip';
        await File('${fixture.path}/$name').copy('${dir.path}/payload');
        await File('${dir.path}/download.json').writeAsString(
          jsonEncode({
            'product': 'Broomm setup',
            'format': 1,
            'state': 'complete',
            'sha256': p.sha256,
            'bytes': p.bytes,
          }),
        );
      }
      await manager.install(plan);
      expect(manager.error, isNull, reason: manager.error);
      expect(manager.ready('RetroArch'), isTrue);
      expect(manager.installedCores.length, 14);
      checks.add(
        'bundled recipe: frontend and all 15 pinned cores installed/verified',
      );
      final generated = await Process.run('python3', [
        'tool/fixtures/nes_fixture.py',
        '${root.path}/Broomm.nes',
      ]);
      expect(generated.exitCode, 0, reason: generated.stderr.toString());
      final game = LaunchGame(
        '42',
        'Broomm native fixture',
        'nes',
        'RetroArch',
        '${root.path}/Broomm.nes',
        2,
        0xff123456,
        target: ControllerTarget.nes,
        retroCore: 'mesen',
      );
      late ResolvedSession resolved;
      late CloudGame cloudGame;
      final notices = <String>[];
      final client = SaveServer();
      addTearDown(client.close);
      final cloud = CloudSaves(
        data,
        notice: (message, problem) {
          if (problem) notices.add(message);
        },
      );
      session = GameSession(
        Directory.current.path,
        managedRoot: data.path,
        testInputs: true,
        testPreconnected: true,
        resolve: (g) async {
          resolved = await manager.resolve(g, profileId);
          cloudGame = CloudGame(
            server: serverId,
            profile: profileId,
            user: 3,
            rom: 42,
            client: client,
            layout: await gameProgressLayout(resolved, 'nes'),
          );
          await cloud.beforePlay(cloudGame);
          return resolved;
        },
      );
      session.finalizeProgress = (exit) => cloud.afterPlay(cloudGame, exit);
      session.onProblem = problems.add;
      Future<void> launch() async {
        await session!.launch(game);
        await session!.waitFor(
          (s) => s.inputReady && s.paused == 1 && s.testSourceIds.length == 2,
          timeout: const Duration(seconds: 30),
        );
      }

      Future<String> query(String command, {bool reply = true}) async {
        final text = await File('${resolved.emulator.root}/retroarch.cfg')
            .readAsString();
        final port = int.parse(
          RegExp(r'network_cmd_port\s*=\s*"(\d+)"').firstMatch(text)![1]!,
        );
        final socket = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        try {
          final answer = Completer<String>();
          socket.listen((event) {
            if (event != RawSocketEvent.read) return;
            final data = socket.receive();
            if (data?.port == port &&
                data!.address.isLoopback &&
                !answer.isCompleted)
              answer.complete(utf8.decode(data.data));
          });
          socket.send(utf8.encode(command), InternetAddress.loopbackIPv4, port);
          return reply
              ? await answer.future.timeout(const Duration(seconds: 2))
              : '';
        } finally {
          socket.close();
        }
      }

      Future<List<int>> memory() async {
        final reply = await query('READ_CORE_MEMORY 6000 64');
        expect(
          reply.startsWith('READ_CORE_MEMORY 6000 '),
          isTrue,
          reason: reply,
        );
        return reply
            .trim()
            .split(' ')
            .skip(2)
            .map((s) => int.parse(s, radix: 16))
            .toList();
      }

      Future<void> input(int bits, {int present = 3}) => atomicText(
        '${resolved.emulator.root}/test-input.txt',
        '$bits 0 $present',
      );
      Future<void> steady(int paused) async {
        closeConfiguration = () async {
          await query('QUIT', reply: false);
        };
        final until = DateTime.now().add(const Duration(milliseconds: 550));
        while (DateTime.now().isBefore(until)) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          expect(session!.status!.paused, paused);
        }
      }

      await launch();
      final id = session.status!.testSourceIds.first;
      var players = [PlayerAssignment(id)];
      var rev = await session.command(players, active: true);
      await session.waitFor((s) => s.ack >= rev && !s.blocked && s.paused == 0);
      final initial = await memory();
      expect(initial[0], 0xb7);
      expect(initial[1], 1);
      Future<void> logicalTriggers(bool down) async {
        final until = DateTime.now().add(const Duration(seconds: 2));
        while (DateTime.now().isBefore(until)) {
          final j = jsonDecode(
            await File('${resolved.emulator.root}/bridge-status.json')
                .readAsString(),
          ) as Map;
          final pair = ((j['testLogicalTriggers'] as List).first as List)
              .cast<int>();
          if (pair.every((v) => down ? v >= 32760 : v == 0)) return;
          await Future<void>.delayed(const Duration(milliseconds: 32));
        }
        fail(
          'Logical SDL trigger readback did not reach ${down ? "pressed" : "neutral"}.',
        );
      }

      await logicalTriggers(false);
      await atomicText('${resolved.emulator.root}/test-input.txt', '0 0 3 3');
      await logicalTriggers(true);
      await input(0);
      await logicalTriggers(false);
      checks.add(
        'logical SDL triggers read neutral/full/release, without a phantom half press',
      );
      await input(1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      var ram = await memory();
      expect(ram[0x21], 1);
      expect(ram[0x20], 0);
      await input(0);
      players = [PlayerAssignment(id, swapFaces: true)];
      rev = await session.command(players, active: true);
      await session.waitFor((s) => s.ack >= rev);
      await input(1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      ram = await memory();
      expect(ram[0x20], 1);
      expect(ram[0x21], 0);
      checks.add(
        'same SDL device identity reaches real Mesen core; live face orientation changes',
      );
      await input(0);
      await query('PAUSE_TOGGLE', reply: false);
      await session.waitFor((s) => s.paused == 1);
      final paused = await memory();
      await steady(1);
      expect((await memory())[0x10], paused[0x10]);
      rev = await session.command(players, active: true);
      await session.waitFor((s) => s.ack >= rev);
      await steady(1);
      await query('PAUSE_TOGGLE', reply: false);
      await session.waitFor((s) => s.paused == 0);
      await steady(0);
      checks.add(
        'native pause/resume remains independent of Broomm polling/routing',
      );
      await input((1 << 4) | (1 << 8));
      await session.waitFor(
        (s) => s.request == 'menu' && s.blocked && s.paused == 1,
      );
      await input(0);
      rev = await session.command(players, active: true);
      await session.waitFor((s) => s.ack >= rev && !s.blocked && s.paused == 0);
      await query('SAVE_STATE', reply: false);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await input(0, present: 2);
      await session.waitFor(
        (s) => s.request == 'disconnect' && s.blocked && s.paused == 1,
      );
      checks.add(
        'menu chord and assigned-controller disconnect pause the game',
      );
      await session.stop();
      expect(problems, isEmpty, reason: problems.join('\n'));
      final layout = cloudGame.layout;
      expect(notices, isEmpty, reason: notices.join('\n'));
      expect(client.records.length, 1);
      expect(client.records.values.single.name, endsWith('.srm'));
      final saveFile = File(
        '${layout.root}/${layout.areas.first.path}/Broomm.srm',
      );
      final save = await saveFile.readAsBytes();
      expect(save.length, 8192);
      expect(save[0], 0xb7);
      expect(save[1], 1);
      expect(
        client.contents.values.any(
          (bytes) => bytes.length == 8192 && bytes[0] == 0xb7,
        ),
        isTrue,
      );
      expect(client.stateRecords, isEmpty);
      final localState = await cloud.store(cloudGame).stateFiles();
      expect(localState, isNotEmpty);
      checks.add(
        'native NES .srm uploaded and matching save state kept locally',
      );
      await saveFile.writeAsBytes(List<int>.filled(8192, 0));
      await cloud.idle(
        () => cloud.useExisting(cloudGame, client.records.values.single),
      );
      expect(await saveFile.readAsBytes(), save);
      expect(await cloud.store(cloudGame).stateFiles(), localState);
      checks.add(
        'explicit cloud restore preserves native save bytes and matching state',
      );
      await launch();
      rev = await session.command([
        PlayerAssignment(session.status!.testSourceIds.first),
      ], active: true);
      await session.waitFor((s) => s.ack >= rev && !s.blocked && s.paused == 0);
      expect((await memory())[1], 2);
      await session.stop();
      checks.add(
        'second launch restores native battery progress and accepts input',
      );
      // Open emulator hands off immediately. Only this test observes its locks
      // and closes it using the frontend's normal native Quit command.
      final configuration = EmulatorConfiguration(data, Directory.current.path);
      await configuration.start(
        () => manager.resolveConfiguration('RetroArch', profileId),
      );
      final until = DateTime.now().add(const Duration(seconds: 8));
      var held = false;
      while (DateTime.now().isBefore(until)) {
        try {
          final lease = await SessionLease.acquire(data);
          await lease.release();
        } on StateError {
          held = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(held, isTrue);
      var ready = false;
      while (!ready && DateTime.now().isBefore(until)) {
        try {
          ready = (await query('GET_STATUS')).contains('CONTENTLESS');
        } on TimeoutException {
          /* Native initialization still owns its locks. */
        }
      }
      expect(ready, isTrue);
      await query('QUIT', reply: false);
      held = true;
      while (held && DateTime.now().isBefore(until)) {
        try {
          final lease = await SessionLease.acquire(data);
          await lease.release();
          held = false;
        } on StateError {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      expect(held, isFalse);
      closeConfiguration = null;
      checks.add(
        'independent no-game configuration retains native locks and releases them on ordinary Quit',
      );
      await launch();
      final exited = Completer<int>();
      session.onExit = exited.complete;
      session.finalizeProgress = null;
      // Simulate loss of the launcher's coordinator, while the native writer
      // survives. The production pidfd recovery adapter then closes RetroArch.
      await session.ownerLease.release();
      final recovered = await Process.run(
        'build/native-linux-checks/host-probe',
        ['--stop', data.path, '${session.processId}'],
      );
      expect(recovered.exitCode, 0, reason: recovered.stderr.toString());
      expect(await exited.future.timeout(const Duration(seconds: 10)), 0);
      expect((await saveFile.readAsBytes())[1], 3);
      checks.add(
        'production recovery targets the real native writer and graceful SIGTERM flushes its save',
      );
    } finally {
      await closeConfiguration?.call();
      if (session?.running == true) await session!.stop();
      manager.dispose();
      await File('${root.path}/observations.json').writeAsString(
        '${jsonEncode({'checks': checks, 'problems': problems, 'physical_controller_check': false, 'commercial_rom': false, 'owner_data_changed': false, 'real_romm_writes': false})}\n',
      );
      stdout.writeln(
        'Linux fixture observations: ${root.path}/observations.json',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
