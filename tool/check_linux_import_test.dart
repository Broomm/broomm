@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/addons/azahar_import.dart';
import 'package:broomm/src/addons/rpcs3_import.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native Linux firmware and CIA imports use only private staging',
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
      final lease = await SessionLease.acquire(data);
      try {
        final ps3 = await manager.resolveConfiguration('RPCS3', 'e' * 32);
        final stage = await fixture.createTemp('firmware-');
        final user = await installRpcs3Content(
          ps3.emulator.executable,
          '${fixture.path}/inputs/PS3UPDAT.PUP',
          stage,
          DownloadCancellation(),
          firmware: true,
          data: data,
        );
        expect(
          await File('${user.path}/dev_flash/sys/external/liblv2.sprx')
              .length(),
          greaterThan(1024),
        );
        final flash = '${ps3.emulator.user}/dev_flash';
        if (!await File('$flash/sys/external/liblv2.sprx').exists())
          await copyTree(
            '${user.path}/dev_flash',
            flash,
            DownloadCancellation(),
          );
        expect(
          await sha256File('$flash/sys/external/liblv2.sprx'),
          await sha256File('${user.path}/dev_flash/sys/external/liblv2.sprx'),
        );
        if (Platform.environment['BROOMM_LINUX_TEST_FIRMWARE_ONLY'] == '1') {
          await File('${fixture.path}/firmware-observations.json')
              .writeAsString(
                jsonEncode({
                  'firmware': 'native PUP install and liblv2 readback',
                  'firmwareStage': stage.path,
                }),
              );
          return;
        }
        final azahar = await manager.resolveConfiguration('Azahar', 'e' * 32);
        final cia = await fixture.createTemp('cia-');
        await installAzaharCia(
          azahar.emulator.executable,
          '${fixture.path}/inputs/FBI.cia',
          cia,
          DownloadCancellation(),
          writer: '${data.path}/writer.lock',
        );
        final files = await cia
            .list(recursive: true, followLinks: false)
            .where((f) => f is File && f.path.endsWith('.app'))
            .toList();
        expect(files, isNotEmpty);
        await File('${fixture.path}/import-observations.json').writeAsString(
          jsonEncode({
            'firmware': 'native PUP install and liblv2 readback',
            'cia': 'native CIA install and title content readback',
            'firmwareStage': stage.path,
            'ciaStage': cia.path,
          }),
        );
      } finally {
        await lease.release();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
