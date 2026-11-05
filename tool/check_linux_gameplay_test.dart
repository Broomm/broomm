@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ffi';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/linux_runtime.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = [
    ('Dolphin', 'gc', 'gc.dol', ControllerTarget.gamecube),
    ('Dolphin', 'wii', 'wii.dol', ControllerTarget.wii),
    ('Azahar', '3ds', '3ds.3dsx', ControllerTarget.n3ds),
    ('melonDS', 'nds', 'ds.nds', ControllerTarget.nds),
    ('DuckStation', 'psx', 'psx.exe', ControllerTarget.psx),
    if (Abi.current() == Abi.linuxArm64)
      ('ARMSX2', 'ps2', 'ps2.elf', ControllerTarget.ps2)
    else
      ('PCSX2', 'ps2', 'ps2.elf', ControllerTarget.ps2),
    ('PPSSPP', 'psp', 'psp.pbp', ControllerTarget.psp),
    if (Platform.environment['BROOMM_LINUX_TEST_PS3'] == '1')
      (
        'RPCS3',
        'ps3',
        Platform.environment['BROOMM_LINUX_PS3_FIXTURE'] ??
            'basicwater.fake.self',
        ControllerTarget.ps3,
      ),
  ];
  final selected = Platform.environment['BROOMM_LINUX_TEST_EMULATOR'];
  for (final item in cases.where((c) => selected == null || selected == c.$1)) {
    test(
      'native ${item.$1} launch, pairing, remap, menu, reconnect and shutdown',
      () async {
        final fixture = Directory(
          Platform.environment['BROOMM_LINUX_FIXTURE_ROOT'] ??
              '.tool-cache/research/linux-standalone',
        ).absolute;
        final installed = (await File(
          '${fixture.path}/current-integration.txt',
        ).readAsString()).trim();
        expect(installed.startsWith('${fixture.path}/integration-'), isTrue);
        final data = Directory('$installed/data');
        final manager = ManagedEmulators(
          data,
          asset: (p) => File(p).readAsString(),
        );
        addTearDown(manager.dispose);
        final prepared = await manager.resolveConfiguration(item.$1, 'e' * 32);
        final e = prepared.emulator;
        if (item.$1 == 'RPCS3') {
          // Optional host font for firmware-free original CPU-loop fixtures.
          // No production profile or firmware preference is changed.
          final font = File('${fixture.path}/inputs/ps3-font.ttf');
          if (await font.exists()) {
            await Directory('${e.root}/data/fonts').create(recursive: true);
            await font.copy('${e.root}/data/fonts/Arial.ttf');
          }
          // Keep the x64 interpreter fixture local to this disposable profile.
          // ARM64 checks retain the production LLVM decoder configuration.
          final config = File('${e.user}/config.yml');
          if (Abi.current() != Abi.linuxArm64)
            await config.writeAsString(
              (await config.readAsString())
                  .replaceAll(
                    RegExp(r'PPU Decoder: .*'),
                    'PPU Decoder: Interpreter (static)',
                  )
                  .replaceAll(
                    RegExp(r'SPU Decoder: .*'),
                    'SPU Decoder: Interpreter (static)',
                  ),
            );
        }
        if (item.$2 == 'psx' || item.$2 == 'ps2') {
          await File('${fixture.path}/inputs/${item.$2}-bios.bin')
              .copy('${e.root}/system/bios.bin');
        }
        if (item.$1 == 'Dolphin') {
          await Directory('${e.user}/Config').create(recursive: true);
          await File('${e.user}/Config/Logger.ini').writeAsString(
            '[Options]\nVerbosity=4\nWriteToConsole=True\nWriteToFile=True\n[Logs]\nBOOT=True\nCORE=True\nCOMMON=True\nVIDEO=True\n',
          );
        }
        final rom = '${fixture.path}/inputs/${item.$3}';
        final resolved = ResolvedSession(e, rom, prepared.executableHash, {
          ...prepared.native,
          'VK_LOADER_DEBUG': 'error,warn',
          'XDG_DATA_DIRS': '/usr/local/share:/usr/share',
          if (Platform.environment['BROOMM_LINUX_TEST_X11'] == '1') ...{
            'QT_QPA_PLATFORM': 'xcb',
            'SDL_VIDEODRIVER': 'x11',
          },
        }, home: prepared.home);
        final game = LaunchGame(
          '42',
          'Broomm native fixture',
          item.$2,
          item.$1,
          rom,
          {'gc', 'wii'}.contains(item.$2) ? 4 : 1,
          0xff234567,
          target: item.$4,
        );
        final problems = <String>[], observations = <String>[];
        final session = GameSession(
          Directory.current.path,
          managedRoot: data.path,
          testInputs: true,
          testPreconnected: true,
          resolve: (_) async => resolved,
        );
        session.onProblem = problems.add;
        Future<void> input(int buttons, [int present = 3]) =>
            atomicText('${e.root}/test-input.txt', '$buttons 0 $present');
        Future<void> logical(int bits) async {
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (DateTime.now().isBefore(deadline)) {
            final snapshot = jsonDecode(
              await File('${e.root}/bridge-status.json').readAsString(),
            ) as Map;
            if (snapshot['pid'] == session.processId &&
                (((snapshot['logicalButtons'] as List).first as int) & bits) !=
                    0)
              return;
            await Future<void>.delayed(const Duration(milliseconds: 32));
          }
          fail(
            'The native logical controller did not acknowledge button $bits',
          );
        }

        try {
          await input(0);
          await session.launch(game);
          await session.waitFor(
            (s) => s.inputReady && s.paused == 1 && s.testSourceIds.length == 2,
            timeout: const Duration(seconds: 25),
          );
          observations.add(
            'same-runtime input and native CPU pause acknowledged',
          );
          final id = session.status!.testSourceIds.first;
          var revision = await session.command([
            PlayerAssignment(id),
          ], active: true);
          await session.waitFor(
            (s) => s.ack >= revision && !s.blocked && s.paused == 0,
          );
          await input(1);
          await logical(1);
          await input(0);
          if (item.$1 != 'PPSSPP') {
            await atomicText('${e.root}/test-input.txt', '0 0 3 0 4');
            await session.waitFor((s) => s.paused == 1 && !s.blocked);
            revision = await session.command([
              PlayerAssignment(id),
            ], active: true);
            await session.waitFor(
              (s) => s.ack >= revision && s.paused == 1 && !s.blocked,
            );
            await Future<void>.delayed(const Duration(milliseconds: 400));
            expect(session.status!.paused, 1);
            await atomicText('${e.root}/test-input.txt', '0 0 3 0 5');
            await session.waitFor((s) => s.paused == 0 && !s.blocked);
            await input(0);
            observations.add(
              'native pause survives steady gameplay and active-route republication',
            );
          }
          revision = await session.command([
            PlayerAssignment(id),
          ], active: false);
          await session.waitFor((s) => s.ack >= revision && s.paused == 1);
          revision = await session.command([
            PlayerAssignment(id, swapFaces: true),
          ], active: true);
          await session.waitFor(
            (s) => s.ack >= revision && s.paused == 0 && !s.blocked,
          );
          await input(1);
          await logical(2);
          observations.add('logical face mapping changed without restarting');
          await input(0);
          if (item.$4 == ControllerTarget.wii) {
            for (final mode in WiiMode.values) {
              final player = PlayerAssignment(id, wiiMode: mode);
              revision = await session.command([player], active: false);
              await session.waitFor((s) => s.ack >= revision && s.paused == 1);
              revision = await session.command([player], active: true);
              await session.waitFor(
                (s) => s.ack >= revision && !s.blocked && s.paused == 0,
              );
              final raw = jsonDecode(
                await File('${e.root}/bridge-status.json').readAsString(),
              ) as Map;
              expect((raw['wiiApplied'] as int) >= revision, isTrue);
              expect(raw['wiiSources'], 1);
              expect(
                (raw['wiiSelected'] as List).first,
                mode == WiiMode.classic
                    ? 2
                    : mode == WiiMode.nunchuk
                    ? 1
                    : 0,
              );
              expect(
                (raw['wiiOrientation'] as List).first,
                mode == WiiMode.upright
                    ? 1
                    : mode == WiiMode.sideways
                    ? 2
                    : 0,
              );
            }
            observations.add(
              'all four Wii layouts applied with native source/extension/orientation readback',
            );
          }

          await input(0);
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await input((1 << 4) | (1 << 8));
          await session.waitFor(
            (s) => s.blocked && s.paused == 1 && s.request == 'menu',
          );
          observations.add('R3 + Select gate/native pause acknowledged');
          await input(0);
          revision = await session.command([
            PlayerAssignment(id),
          ], active: true);
          await session.waitFor(
            (s) => s.ack >= revision && !s.blocked && s.paused == 0,
          );
          await input(0, 2);
          await session.waitFor(
            (s) => s.blocked && s.paused == 1 && s.request == 'disconnect',
          );
          await input(0);
          await session.waitFor((s) => s.devices.length == 2);
          final newId = session.status!.devices
              .singleWhere((d) => d.id == session.status!.testSourceIds.first)
              .id;
          revision = await session.command([
            PlayerAssignment(newId),
          ], active: true);
          await session.waitFor(
            (s) => s.ack >= revision && !s.blocked && s.paused == 0,
          );
          observations.add(
            'physical-source reconnect routes to existing logical device',
          );
          await session.stop();
          observations.add('normal native shutdown released writer');
          expect(problems, isEmpty, reason: problems.join('\n'));
        } finally {
          if (session.running) {
            final pid = session.processId!;
            final result = await Process.run('python3', [
              'tool/fixtures/stop_linux_fixture.py',
              '$pid',
              e.root,
              linuxLaunchExecutable(e),
            ]);
            expect(result.exitCode, 0, reason: '${result.stderr}');
            for (var i = 0; i < 100 && session.running; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 30));
            }
          }
          await File('${e.root}/linux-observations.json').writeAsString(
            jsonEncode({
              'emulator': item.$1,
              'checks': observations,
              'problems': problems,
            }),
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
