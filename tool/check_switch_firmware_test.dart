@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/zip.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/switch_firmware.dart';

class _Client extends RommClient {
  _Client(this.files, this.local) : super(Uri.parse('https://fixture.invalid'));
  final List<RommFirmware> files;
  final Map<int, File> local;
  final transfers = <int>[];
  @override
  Future<List<RommFirmware>> firmware(int p) async => files;
  @override
  Future<void> downloadFirmware(
    RommFirmware f,
    File out, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    cancellation.check();
    transfers.add(f.id);
    await local[f.id]!.copy(out.path);
    onProgress(f.bytes);
  }
}

void main() {
  test('automatic Switch firmware ZIP and keys initialize a new private native emulator without changing supplied resources', () async {
    final evidence = await Directory('.tool-cache/research/ra-wii-switch')
        .createTemp('native-switch-firmware-');
    final data = Directory('${evidence.absolute.path}/data');
    await data.create();
    final manager = ManagedEmulators(
      data,
      project: Directory.current.path,
      asset: (p) async {
        if (p.endsWith('/setup.json'))
          return jsonEncode({
            'schema_version': 1,
            'host': 'macos-arm64',
            'launchers': {
              'ryubing': {'source': 'tested:ryubing'},
            },
          });
        return File(p).readAsString();
      },
    );
    await manager.install(
      await manager.readPlan(
        file: 'tool/setup-development.json',
        only: {'ryubing'},
      ),
    );
    expect(manager.error, isNull, reason: manager.error);
    final firmware = Directory(
      'prototype-data/ryubing/user/bis/system/Contents/registered',
    );
    final archive = File('${evidence.path}/firmware.zip');
    final names = <String>[];
    await for (final f in firmware.list(recursive: true, followLinks: false)) {
      if (f is File) names.add(f.path.substring(firmware.path.length + 1));
    }
    await ProgressZip.write(archive, firmware, names);
    final local = {
      1: archive,
      2: File('prototype-data/ryubing/user/system/prod.keys'),
      3: File('prototype-data/ryubing/user/system/title.keys'),
    };
    final records = [
      for (final e in local.entries)
        RommFirmware(
          e.key,
          9,
          {1: 'firmware.zip', 2: 'prod.keys', 3: 'title.keys'}[e.key]!,
          await e.value.length(),
          await progressFileHash(e.value, md5: true),
        ),
    ];
    final client = _Client(records, local);
    const profile = 'c123456789abcdef0123456789abcdef';
    final lease = await SessionLease.acquire(data);
    try {
      await ensureSwitchFirmware(
        manager,
        profile,
        9,
        client,
        DownloadCancellation(),
        (_) {},
        lease: lease,
      );
      expect(client.transfers.toSet(), {1, 2, 3});
      await ensureSwitchFirmware(
        manager,
        profile,
        9,
        client,
        DownloadCancellation(),
        (_) {},
        lease: lease,
      );
      expect(client.transfers.length, 3);
    } finally {
      await lease.release();
      client.close();
    }
    final game = LaunchGame(
      'firmware-check',
      '3D World',
      'Nintendo Switch',
      'Ryubing',
      File('roms/switch/Super Mario 3D World + Bowsers Fury.nsp').absolute.path,
      4,
      0xff345678,
      target: ControllerTarget.switchPro,
    );
    final session = GameSession(
      Directory.current.path,
      managedRoot: data.path,
      testInputs: true,
      resolve: (g) => manager.resolve(g, profile),
    );
    try {
      await session.launch(game);
      await session.waitFor(
        (s) => s.inputReady && s.paused == 1,
        timeout: const Duration(seconds: 90),
      );
      await session.stop();
      await File('${evidence.path}/result.json').writeAsString(
        jsonEncode({
          'nativeReady': true,
          'ncas': names.length,
          'rommLayout': ['firmware.zip', 'prod.keys', 'title.keys'],
          'transfers': client.transfers,
          'secondCallNoTransfers': true,
          'originalProfilesChanged': false,
        }),
      );
    } finally {
      if (session.running) await session.stop();
      manager.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
