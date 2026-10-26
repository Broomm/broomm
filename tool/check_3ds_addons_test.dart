import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/addons/files.dart';
import 'package:broomm/src/addons/service.dart';
import 'package:broomm/src/addons/three_ds.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/shell/library.dart';

class CachedRommFiles extends RommClient {
  CachedRommFiles() : super(Uri.parse('https://fixture.invalid'));
  int requests = 0;
  @override
  Future<void> downloadFile(
    RommFile file,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    requests++;
    throw StateError(
      'The existing verified CIA should be reused without a server transfer',
    );
  }
}

void main() {
  test('real Smash CIA installs through managed Azahar, repeats without import and uninstalls without progress loss', () async {
    if (!Platform.isMacOS)
      throw UnsupportedError('Requires the tested macOS ARM64 native pack');
    final project = Directory.current.path;
    final ownerRoot = Directory(
      Platform.environment['BROOMM_ADDON_SOURCE'] ?? '$project/broomm-data',
    );
    final sourceLibrary = GameLibrary(ownerRoot);
    // Read only installed game metadata; never open owner credentials or saves.
    File? sourceReceipt;
    await for (final file in sourceLibrary.root.list(
      recursive: true,
      followLinks: false,
    )) {
      if (file is! File || !file.path.endsWith('/receipt.json')) continue;
      final j = jsonDecode(await file.readAsString()) as Map;
      final game = j['game'] as Map?;
      if (game?['name'] == 'Super Smash Bros. for Nintendo 3DS' &&
          ['3ds', 'n3ds'].contains(game?['platform_slug'])) {
        sourceReceipt = file;
        break;
      }
    }
    expect(
      sourceReceipt,
      isNotNull,
      reason: 'Download the provided Smash Bros. game first',
    );
    final original = jsonDecode(await sourceReceipt!.readAsString()) as Map;
    final server = original['serverId'] as String,
        gameId = (original['game'] as Map)['id'] as int;
    final evidence = Directory('$project/.tool-cache/research/3ds-addons');
    await evidence.create(recursive: true);
    final root = await evidence.createTemp('native-workflow-');
    final data = Directory(await root.resolveSymbolicLinks());
    final buildJson = jsonDecode(
      await File('$project/assets/setup/tested-builds.json').readAsString(),
    ) as Map;
    final build = TestedBuild(
      (buildJson['builds'] as List).cast<Map>().singleWhere(
        (b) => b['id'] == 'azahar',
      ),
    );
    final targetRelease = Directory(
      '${data.path}/emulators/azahar/${build.hash}',
    );
    await targetRelease.parent.create(recursive: true);
    await runOwnedTool('/bin/cp', [
      '-cR',
      '${ownerRoot.path}/emulators/azahar/${build.hash}',
      targetRelease.path,
    ]);
    await File('${data.path}/emulators/selected.json').writeAsString(
      jsonEncode({
        'schema_version': 1,
        'selected': {'azahar': build.hash},
      }),
      flush: true,
    );
    final libraryParent = Directory('${data.path}/library/$server');
    await libraryParent.create(recursive: true);
    // APFS clones keep the supplied real CCI/CIA intact without duplicating a
    // two-gigabyte ROM. Every subsequent write stays inside this test root.
    await runOwnedTool('/bin/cp', [
      '-cR',
      sourceReceipt.parent.path,
      '${libraryParent.path}/$gameId',
    ]);
    final library = GameLibrary(data);
    final entry = (await library.load(server)).games.single;
    final j = entry.game.toJson();
    final receiptFiles = (original['files'] as List).cast<Map>();
    j['files'] = [
      for (var i = 0; i < receiptFiles.length; i++)
        {
          'id': 1000 + i,
          'rom_id': gameId,
          'file_name': (receiptFiles[i]['path'] as String).split('/').last,
          'full_path': '${entry.game.fullPath}/${receiptFiles[i]['path']}',
          'file_size_bytes': receiptFiles[i]['bytes'],
          'crc_hash': receiptFiles[i]['crc32'],
        },
    ];
    final remote = RommGame.fromJson(j);
    final manager = ManagedEmulators(
      data,
      project: project,
      asset: (p) => File('$project/$p').readAsString(),
    );
    final phases = <Map<String, Object>>[];
    final stopwatch = Stopwatch()..start();
    final addons = GameAddons(
      data,
      library,
      prepare: manager.prepareAzaharAddons,
      phase: (p) {
        phases.add({'phase': p, 'ms': stopwatch.elapsedMilliseconds});
        stdout.writeln(p);
      },
    );
    final client = CachedRommFiles();
    const profile = 'e123456789abcdef0123456789abcdef';
    const other = 'e223456789abcdef0123456789abcdef';
    try {
      final result = await addons.sync(
        serverId: server,
        profileId: profile,
        entry: entry,
        game: remote,
        client: client,
        cancellation: DownloadCancellation(),
        progress: (_) {},
      );
      expect(result.installed, greaterThan(0));
      expect(client.requests, 0);
      final installedAt = stopwatch.elapsedMilliseconds;
      final manifest = await addonJson(
        File('${data.path}/addons/$server/$gameId/current.json'),
      );
      final unitRecords = manifest['units'] as Map;
      final contentFiles = unitRecords.values.cast<Map>().fold<int>(
        0,
        (n, u) => n + (u['files'] as Map).length,
      );
      final romFiles = await library.contentFiles(entry);
      final baseRom = romFiles.singleWhere((p) => p.endsWith('.cci'));
      final title = await readThreeDsGameId(baseRom);
      expect(title, manifest['base']);
      final privateRoot = Directory(
        '${data.path}/profiles/$profile/emulators/azahar',
      );
      final saves = [
        File('${azaharUserPath(privateRoot.path)}/sdmc/extdata/preserve.bin'),
        File(
          '${azaharUserPath(privateRoot.path)}/${titleContentPath(title).replaceFirst('/content', '/data')}/save.bin',
        ),
        File('${privateRoot.path}/states/preserve.bin'),
      ];
      for (final file in saves) {
        await file.parent.create(recursive: true);
        await file.writeAsString('keep progress');
      }
      final again = await addons.sync(
        serverId: server,
        profileId: profile,
        entry: entry,
        game: remote,
        client: client,
        cancellation: DownloadCancellation(),
        progress: (_) {},
      );
      expect(again.installed, 0);
      final repeatedAt = stopwatch.elapsedMilliseconds;
      final lease = await SessionLease.acquire(data);
      try {
        final (_, otherRoot) = await manager.prepareAzaharAddons(
          other,
          DownloadCancellation(),
        );
        await addons.applyForLaunch(server, gameId, other, otherRoot, baseRom);
      } finally {
        await lease.release();
      }
      final replicatedAt = stopwatch.elapsedMilliseconds;
      await library.remove(
        server,
        gameId,
        uninstallAddons: () => addons.uninstall(server, gameId),
      );
      expect(await entry.directory.exists(), false);
      for (final id in [profile, other]) {
        final record = await addonJson(
          File('${data.path}/profiles/$id/emulators/azahar/addons.json'),
        );
        expect(record['units'], isEmpty);
      }
      for (final file in saves) {
        expect(await file.readAsString(), 'keep progress');
      }
      final report = {
        'timeUtc': DateTime.now().toUtc().toIso8601String(),
        'host': manager.host,
        'azaharVersion': build.version,
        'azaharSha256': build.hash,
        'baseTitle': title,
        'installedPackages': result.installed,
        'importedFiles': contentFiles,
        'remoteTransfers': client.requests,
        'repeatImports': again.installed,
        'secondProfileApplied': true,
        'allProfilesUninstalled': true,
        'progressSentinelsKept': saves.length,
        'ownerGameAndProgressModified': false,
        'timingsMs': {
          'install': installedAt,
          'repeat': repeatedAt - installedAt,
          'secondProfile': replicatedAt - repeatedAt,
          'remove': stopwatch.elapsedMilliseconds - replicatedAt,
        },
        'phases': phases,
        'testData': data.path,
        'limitations': [
          'Remote manifest reconstructed from a copied local RomM receipt; no live authenticated API request.',
          'Actual native CIA import and filesystem cleanup verified; in-game DLC visibility remains an owner check.',
        ],
      };
      await File('${evidence.path}/native-workflow.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
      stdout.writeln(
        'Real Azahar add-on workflow passed. Report: ${evidence.path}/native-workflow.json',
      );
    } finally {
      client.close();
      manager.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
