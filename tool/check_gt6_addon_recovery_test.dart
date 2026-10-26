@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/addons/files.dart';
import 'package:broomm/src/addons/ps3.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/shell/download_queue.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:flutter_test/flutter_test.dart';

const _server = '506d439865d8f46267001bdd3a1fe0e5',
    _profile = '15770cf1430ff66c406582cc4245ae63',
    _serial = 'BCUS98296';

void main() {
  test('the owner’s GT6 game-created data and cached native DLC install and uninstall exactly in an isolated profile', () async {
    final project = Directory.current;
    final evidence = Directory(
      '${project.path}/.tool-cache/research/cloud-queue-gt6',
    );
    await evidence.create(recursive: true);
    final data = await evidence.createTemp('gt6-files-');
    final owner = Directory('${project.path}/broomm-data');
    final source = Directory(
      '${owner.path}/profiles/$_profile/emulators/rpcs3',
    );
    final target = Directory('${data.path}/profiles/$_profile/emulators/rpcs3');
    const relative = 'portable/dev_hdd0/game/$_serial';
    late Map<String, String> ownerBefore;
    late String registryBefore;
    final ownerLease = await SessionLease.acquire(owner);
    try {
      ownerBefore = await addonInventory(Directory('${source.path}/$relative'));
      registryBefore = await File('${source.path}/addons.json').readAsString();
      await target.create(recursive: true);
      await Directory('${target.path}/portable/dev_hdd0/game')
          .create(recursive: true);
      await Directory('${data.path}/addons-ps3/$_server')
          .create(recursive: true);
      for (final (from, to) in [
        ('${source.path}/$relative', '${target.path}/$relative'),
        (
          '${owner.path}/addons-ps3/$_server/8010',
          '${data.path}/addons-ps3/$_server/8010',
        ),
      ]) {
        final copy = await Process.run('/bin/cp', ['-cR', from, to]);
        expect(copy.exitCode, 0, reason: '${copy.stderr}');
      }
      for (final file in ['addons.json', 'profile.json']) {
        await File('${source.path}/$file').copy('${target.path}/$file');
      }
      expect(
        await addonInventory(Directory('${source.path}/$relative')),
        ownerBefore,
      );
    } finally {
      await ownerLease.release();
    }
    final before = await addonInventory(Directory('${target.path}/$relative'));
    expect(before, ownerBefore);
    final metadata = await File('${target.path}/$relative/PARAM.SFO')
        .readAsBytes();
    final service = Ps3Addons(
      data,
      GameLibrary(data),
      prepare: (p, c) async {
        expect(p, _profile);
        c.check();
        return ('never-executed', target);
      },
    );
    final lease = await SessionLease.acquire(data);
    final clock = Stopwatch()..start();
    final timings = <String, int>{};
    late Map<String, String> installed;
    try {
      await service.applyForLaunch(_server, 8010, _profile);
      timings['installMs'] = clock.elapsedMilliseconds;
      installed = await addonInventory(Directory('${target.path}/$relative'));
      expect(installed['USRDIR/vou/vou26.edat'], isNotNull);
      for (final e in before.entries.where((e) => e.key != 'PARAM.SFO')) {
        expect(installed[e.key], e.value, reason: e.key);
      }
      clock.reset();
      await service.applyForLaunch(_server, 8010, _profile);
      timings['reuseMs'] = clock.elapsedMilliseconds;
      expect(
        await addonInventory(Directory('${target.path}/$relative')),
        installed,
      );
      clock.reset();
      await service.uninstall(_server, 8010);
      timings['uninstallMs'] = clock.elapsedMilliseconds;
      expect(
        await addonInventory(Directory('${target.path}/$relative')),
        before,
      );
      expect(
        await File('${target.path}/$relative/PARAM.SFO').readAsBytes(),
        metadata,
      );
    } finally {
      await lease.release();
    }
    // Inspection and all package effects used the clone. No owner registry was
    // migrated and no owner game-created/save files were deleted or rewritten.
    final finalOwnerLease = await SessionLease.acquire(owner);
    try {
      expect(
        await File('${source.path}/addons.json').readAsString(),
        registryBefore,
      );
      expect(
        await addonInventory(Directory('${source.path}/$relative')),
        ownerBefore,
      );
    } finally {
      await finalOwnerLease.release();
    }
    await File('${evidence.path}/gt6-file-roundtrip.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'utc': DateTime.now().toUtc().toIso8601String(),
        'host': Platform.operatingSystem,
        'title': _serial,
        'rom': 8010,
        'isolatedData': data.path,
        'originalFiles': before.length,
        'installedFiles': installed.length,
        'originalInventorySha256':
            (ProgressDigest.sha256()..add(utf8.encode(jsonEncode(before))))
                .finish(),
        'metadataRestored': true,
        'ownerInventoryAndRegistryUnchanged': true,
        'usesCachedNativePkgOutput': true,
        'timings': timings,
      }),
      flush: true,
    );
  });

  test('the real download checkpoint remains readable while a running owner retains its queue writer', () async {
    final queue = DownloadQueueStore(
      Directory('${Directory.current.path}/broomm-data'),
      _server,
      _profile,
    );
    final jobs = await queue.readSnapshot();
    expect(jobs.any((j) => j.game.id == 8010), true);
    var inUse = false;
    try {
      await queue.open();
    } on DownloadQueueInUse {
      inUse = true;
      expect((await queue.readSnapshot()).any((j) => j.game.id == 8010), true);
    } finally {
      await queue.close();
    }
    final evidence = Directory(
      '${Directory.current.path}/.tool-cache/research/cloud-queue-gt6',
    );
    await evidence.create(recursive: true);
    await File('${evidence.path}/owner-queue.json').writeAsString(
      jsonEncode({
        'utc': DateTime.now().toUtc().toIso8601String(),
        'liveWriter': inUse,
        'gt6CheckpointReadable': true,
        'mutated': false,
      }),
      flush: true,
    );
  });
}
