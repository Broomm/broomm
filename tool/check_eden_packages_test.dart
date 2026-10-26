@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/addons/files.dart';
import 'package:broomm/src/addons/packages.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/shell/library.dart';

class _Cache extends RommClient {
  _Cache() : super(Uri.parse('https://fixture.invalid'));
  final calls = <int>[];
  @override
  Future<void> downloadFile(
    RommFile file,
    File target, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    cancellation.check();
    calls.add(file.id);
    await File('.tool-cache/research/ra-wii-switch/media/${file.id}.nsp')
        .copy(target.path);
    onProgress(file.bytes);
  }
}

void main() {
  test('real Eden NSP update and five DLC packages reconcile in two private profiles and uninstall with progress retained', () async {
    final root = await Directory('.tool-cache/research/eden')
            .createTemp('packages-'),
        data = await Directory('${root.absolute.path}/data').create();
    final manager = ManagedEmulators(
          data,
          project: Directory.current.path,
          asset: (p) => File(p).readAsString(),
        ),
        client = _Cache(),
        library = GameLibrary(data);
    await manager.install(await manager.readPlan(only: {'eden'}));
    expect(manager.error, isNull, reason: manager.error);
    final raw = jsonDecode(
          await File('.tool-cache/research/ra-wii-switch/media/8082.json')
              .readAsString(),
        ) as Map<String, dynamic>,
        game = RommGame.fromJson(raw),
        base = RommGame.fromJson({
          ...raw,
          'files': (raw['files'] as List)
              .where((f) => f['category'] == 'game')
              .toList(),
        });
    const server = 'a123456789abcdef0123456789abcdef',
        first = '0123456789abcdef0123456789abcdef',
        second = '1123456789abcdef0123456789abcdef';
    final entry = await library.install(
      serverId: server,
      userId: 3,
      game: base,
      client: client,
      cancellation: DownloadCancellation(),
      progress: (_) {},
    );
    final service = GamePackages(
      data,
      library,
      'switch',
      switchEmulator: 'Eden',
      prepare: (p, c) =>
          manager.preparePackages('switch', p, c, emulator: 'Eden'),
    );
    try {
      expect(
        await service.needsSwitchSelection(
          server,
          InstalledGame(game, entry.directory, 3),
        ),
        true,
      );
      final result = await service.sync(
        serverId: server,
        profileId: first,
        entry: entry,
        game: game,
        client: client,
        cancellation: DownloadCancellation(),
        progress: (_) {},
      );
      expect(result.available, 6);
      expect(result.installed, 6);
      expect(
        await service.needsSwitchSelection(
          server,
          InstalledGame(game, entry.directory, 3),
        ),
        false,
      );
      final current = await addonJson(
        File('${data.path}/addons/$server/8082/switch-eden/current.json'),
      );
      expect(current['base'], '01005d100807a000');
      expect((current['units'] as Map).length, 14);
      final reads = client.calls.length;
      final repeated = await service.sync(
        serverId: server,
        profileId: first,
        entry: entry,
        game: game,
        client: client,
        cancellation: DownloadCancellation(),
        progress: (_) {},
      );
      expect(repeated.installed, 0);
      expect(client.calls.length, reads);
      // Native load proves Eden consumes the generated NAND, separately from
      // file ownership/readback and from in-game recognition of each DLC.
      final launch = LaunchGame(
        'check',
        'Pokémon Quest',
        'switch',
        'Eden',
        (await library.contentFiles(entry)).single,
        4,
        0,
        target: ControllerTarget.switchPro,
      );
      final session = GameSession(
        Directory.current.path,
        managedRoot: data.path,
        testInputs: true,
        testPreconnected: true,
        resolve: (g) => manager.resolve(g, first),
      );
      try {
        await session.launch(launch);
        await session.waitFor(
          (s) => s.inputReady && s.paused == 1,
          timeout: const Duration(seconds: 90),
        );
        await session.stop();
        final log = File('${session.emulator!.user}/log/eden_log.txt');
        final text = await log.readAsString();
        expect(text, contains('ExeFS: Update'));
        expect(text, contains('applied successfully'));
      } finally {
        if (session.running) await session.stop();
      }
      final lease = await SessionLease.acquire(data);
      try {
        final (_, profile) = await manager.preparePackages(
          'switch',
          second,
          DownloadCancellation(),
          emulator: 'Eden',
        );
        await service.applyForLaunch(
          server,
          game.id,
          second,
          profile,
          (await library.contentFiles(entry)).single,
          entry: entry,
        );
        for (final id in [first, second]) {
          final root = Directory('${data.path}/profiles/$id/emulators/eden');
          final owned = await addonJson(File('${root.path}/eden-addons.json'));
          expect((owned['files'] as Map).length, 14);
          final save = File(
            '${root.path}/data/eden/nand/user/save/0000000000000000/$id/01005D100807A000/save-check',
          );
          await save.parent.create(recursive: true);
          await save.writeAsString('retained');
        }
        await service.uninstall(server, game.id);
        for (final id in [first, second]) {
          final root = Directory('${data.path}/profiles/$id/emulators/eden');
          expect(
            (await addonInventory(
              Directory('${root.path}/data/eden/nand/user/Contents/registered'),
            )),
            isEmpty,
          );
          expect(
            await File(
              '${root.path}/data/eden/nand/user/save/0000000000000000/$id/01005D100807A000/save-check',
            ).readAsString(),
            'retained',
          );
        }
      } finally {
        await lease.release();
      }
      await File('${root.path}/results.json').writeAsString(
        jsonEncode({
          'base': current['base'],
          'sources': 6,
          'ncas': 14,
          'repeatedWithoutTransfer': true,
          'twoProfiles': true,
          'uninstallRetainedProgress': true,
          'nativeUpdateLoad': true,
        }),
      );
      stdout.writeln('Eden package evidence: ${root.path}');
    } finally {
      manager.dispose();
      client.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
