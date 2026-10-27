import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/ps3_firmware.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';

class FirmwareFixture extends RommClient {
  FirmwareFixture(this.source, this.record)
    : super(Uri.parse('https://fixture.example'));
  final File source;
  final RommFirmware record;
  int transfers = 0, lists = 0;
  @override
  Future<List<RommFirmware>> firmware(int platformId) async {
    lists++;
    return [record];
  }

  @override
  Future<void> downloadFirmware(
    RommFirmware file,
    File dest, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    transfers++;
    cancellation.check();
    await source.copy(dest.path);
    onProgress(file.bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final intel = Platform.environment['BROOMM_RPCS3_VARIANT'] == 'intel';
  final emulator = intel ? 'RPCS3 Intel' : 'RPCS3';
  test('real RPCS3 installs the supplied PUP privately and reuses verified firmware for another profile', () async {
    final project = Directory.current.path,
        evidence = Directory(
          intel
              ? '.tool-cache/research/rpcs3-intel'
              : '.tool-cache/research/library-followup',
        ).absolute;
    final data = await evidence.createTemp('native-ps3-firmware-');
    final manager = ManagedEmulators(
      data,
      project: project,
      asset: (p) => File(p).readAsString(),
    );
    await manager.load();
    final source = await manager.readPlan(
      file: 'tool/setup-development.json',
      only: {intel ? 'rpcs3-intel' : 'rpcs3'},
    );
    final item = source.items.single;
    await manager.install(
      SetupPlan([SetupItem(item.build, item.source, item.core, {})]),
    );
    expect(manager.error, isNull);
    final pup = File(
      '/Users/ptrschneider/Projects/pgcs/firmware/ps3/PS3UPDAT.PUP',
    );
    final api = FirmwareFixture(
      pup,
      RommFirmware(
        5,
        11,
        'PS3UPDAT.PUP',
        await pup.length(),
        await progressFileHash(pup, md5: true),
      ),
    );
    final phases = <String>[];
    final lease = await SessionLease.acquire(data);
    try {
      const a = 'a123456789abcdef0123456789abcdef',
          b = 'b123456789abcdef0123456789abcdef';
      await ensurePs3Firmware(
        manager,
        a,
        11,
        api,
        DownloadCancellation(),
        phases.add,
        lease: lease,
        emulator: emulator,
      );
      await ensurePs3Firmware(
        manager,
        a,
        11,
        api,
        DownloadCancellation(),
        phases.add,
        lease: lease,
        emulator: emulator,
      );
      await ensurePs3Firmware(
        manager,
        b,
        11,
        api,
        DownloadCancellation(),
        phases.add,
        lease: lease,
        emulator: emulator,
      );
      expect(api.transfers, 1);
      expect(api.lists, 1);
      for (final p in [a, b])
        expect(
          await File(
            '${data.path}/profiles/$p/emulators/rpcs3/portable/dev_flash/sys/external/liblv2.sprx',
          ).exists(),
          true,
        );
      await File('${evidence.path}/native-ps3-firmware.json').writeAsString(
        jsonEncode({
          'root': data.path,
          'build': item.build.hash,
          'pupMd5': api.record.md5,
          'transfers': api.transfers,
          'profiles': 2,
          'phases': phases,
          'source': 'existing owner-provided PUP via fixture API, no owner server writes',
        }),
      );
    } finally {
      await lease.release();
      api.close();
      manager.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
