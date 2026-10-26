import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/addons/files.dart';
import 'package:broomm/src/addons/profile.dart';
import 'package:broomm/src/addons/service.dart';
import 'package:broomm/src/addons/three_ds.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/shell/library.dart';

import 'support/addon_fixtures.dart';

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('broomm-addons-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test('container headers match NCCH/NCSD games with update/DLC identity and reject base or truncated packages', () async {
    for (final ncsd in [false, true]) {
      final rom = File('${root.path}/base.cci');
      await rom.writeAsBytes(base3ds(ncsd: ncsd));
      expect(await readThreeDsGameId(rom.path), baseTitle);
    }
    final cia = File('${root.path}/test.cia');
    for (final id in [updateTitle, dlcTitle]) {
      await cia.writeAsBytes(addonCia(id: id, version: 17));
      final title = await readCiaTitle(cia.path);
      expect(title.belongsTo(baseTitle), true);
      expect(title.belongsTo('00040000000abc00'), false);
      expect(title.version, 17);
    }
    await cia.writeAsBytes(addonCia(id: baseTitle));
    await expectLater(readCiaTitle(cia.path), throwsFormatException);
    await cia.writeAsBytes([0, 1, 2]);
    await expectLater(readCiaTitle(cia.path), throwsFormatException);
  });

  group('native-pack file transactions', () {
    late GameLibrary library;
    late GameAddons addons;
    late FakeCiaImport importer;
    late AddonFiles client;
    late InstalledGame entry;
    late RommGame remote;
    late Directory profile;

    Future<void> installBase({bool includesDlc = false}) async {
      final initial = {
        'Game.cci': base3ds(),
        if (includesDlc) 'dlc/Pack.cia': addonCia(),
      };
      final game = await addonGame(root, initial);
      client = filesClient(game, initial);
      entry = await library.install(
        serverId: addonServer,
        userId: 7,
        game: game,
        client: client,
        cancellation: DownloadCancellation(),
        progress: (_) {},
      );
      client.downloads.clear();
      final available = {'Game.cci': base3ds(), 'dlc/Pack.cia': addonCia()};
      remote = await addonGame(root, available);
      client.payloads.addAll(filesClient(remote, available).payloads);
      profile = (await addonRuntime(
        root,
        addonProfile,
        DownloadCancellation(),
      )).$2;
    }

    Future<AddonResult> sync({DownloadCancellation? cancellation}) =>
        addons.sync(
          serverId: addonServer,
          profileId: addonProfile,
          entry: entry,
          game: remote,
          client: client,
          cancellation: cancellation ?? DownloadCancellation(),
          progress: (_) {},
        );
    File getContent([String title = dlcTitle]) => File(
      '${azaharUserPath(profile.path)}/${titleContentPath(title)}/00000000.app',
    );
    Future<List<File>> progressFiles() async {
      final files = [
        File(
          '${azaharUserPath(profile.path)}/${titleContentPath(baseTitle).replaceFirst('/content', '/data')}/save.bin',
        ),
        File(
          '${azaharUserPath(profile.path)}/${titleContentPath(dlcTitle).replaceFirst('/content', '/data')}/save.bin',
        ),
        File('${azaharUserPath(profile.path)}/sdmc/extdata/progress.bin'),
        File('${profile.path}/states/state.bin'),
      ];
      for (final f in files) {
        await f.parent.create(recursive: true);
        await f.writeAsString('progress');
      }
      return files;
    }

    setUp(() {
      library = GameLibrary(root);
      importer = FakeCiaImport();
      addons = GameAddons(
        root,
        library,
        prepare: (id, c) => addonRuntime(root, id, c),
        importer: importer.call,
      );
    });
    tearDown(() => client.close());

    test('existing downloaded CIA is verified/reused; repeat checks avoid transfer/import and preserve progress', () async {
      await installBase(includesDlc: true);
      final saves = await progressFiles();
      expect((await sync()).installed, 1);
      expect(await getContent().readAsString(), '$dlcTitle:1');
      expect(client.downloads, isEmpty);
      expect((await sync()).installed, 0);
      expect(importer.imported.length, 1);
      for (final f in saves) {
        expect(await f.readAsString(), 'progress');
      }
    });

    test('existing base downloads only differences and supports updates, update and API categories', () async {
      await installBase();
      expect((await sync()).installed, 1);
      expect(client.downloads.length, 1);
      final files = {
        'Game.cci': base3ds(),
        'dlc/Pack.cia': addonCia(),
        'updates/Update.cia': addonCia(id: updateTitle, version: 2),
      };
      remote = await addonGame(root, files);
      client.payloads.addAll(filesClient(remote, files).payloads);
      expect((await sync()).installed, 1);
      expect(client.downloads.length, 2);
      expect(await getContent(updateTitle).readAsString(), '$updateTitle:2');
      expect(addonKind(remote.files.last, 'update/Update.cia'), 'update');
      expect(
        addonKind(
          RommFile(
            id: 20,
            romId: 18,
            name: 'x.cia',
            fullPath: '/x.cia',
            bytes: 1,
            category: 'dlc',
          ),
          'x.cia',
        ),
        'dlc',
      );
    });

    test('failed native update, corrupt transfer and cancellation cannot replace working DLC; retry installs the change', () async {
      await installBase();
      await sync();
      final files = {
        'Game.cci': base3ds(),
        'dlc/Pack.cia': addonCia(version: 2),
      };
      remote = await addonGame(root, files);
      client.payloads.addAll(filesClient(remote, files).payloads);
      importer.fail = true;
      await expectLater(sync(), throwsA(isA<RommFailure>()));
      expect(await getContent().readAsString(), '$dlcTitle:1');
      importer.fail = false;
      client.payloads[remote.files.last.fullPath] = addonCia(version: 3);
      await expectLater(sync(), throwsA(isA<RommFailure>()));
      expect(await getContent().readAsString(), '$dlcTitle:1');
      client.onDownload = (c) => c.cancel();
      await expectLater(sync(), throwsA(isA<DownloadCancelled>()));
      client.onDownload = null;
      client.payloads.addAll(filesClient(remote, files).payloads);
      expect((await sync()).installed, 1);
      expect(await getContent().readAsString(), '$dlcTitle:2');
    });

    test('foreign title/category and unsafe remote paths fail before changing an emulator', () async {
      await installBase();
      final files = {
        'Game.cci': base3ds(),
        'dlc/Pack.cia': addonCia(id: '0004008c000abc00'),
      };
      remote = await addonGame(root, files);
      client.payloads.addAll(filesClient(remote, files).payloads);
      await expectLater(sync(), throwsA(isA<RommFailure>()));
      expect(importer.imported, isEmpty);
      expect(await getContent().exists(), false);
      final bad = await addonGame(root, {
        'Game.cci': base3ds(),
        '../dlc/Pack.cia': addonCia(),
      });
      remote = bad;
      await expectLater(sync(), throwsA(isA<RommFailure>()));
      expect(importer.imported, isEmpty);
    });

    for (final missingHash in [null, '']) {
      test(
        'a ${missingHash == null ? 'missing' : 'blank'} hash triggers revalidation rather than treating same size as unchanged',
        () async {
          await installBase();
          final j = remote.toJson();
          j['files'] = [
            for (final f in remote.files)
              {
                'id': f.id,
                'rom_id': f.romId,
                'file_name': f.name,
                'full_path': f.fullPath,
                'file_size_bytes': f.bytes,
                'crc_hash': missingHash,
                'sha1_hash': missingHash,
              },
          ];
          remote = RommGame.fromJson(j);
          await sync();
          await sync();
          expect(client.downloads.length, 2);
          expect(importer.imported.length, 2);
        },
      );
    }

    test('a live game/setup lease blocks install and deletion before native/file effects', () async {
      await installBase();
      final lease = await SessionLease.acquire(root);
      try {
        await expectLater(sync(), throwsStateError);
        await expectLater(
          library.remove(
            addonServer,
            18,
            uninstallAddons: () => addons.uninstall(addonServer, 18),
          ),
          throwsStateError,
        );
        expect(importer.imported, isEmpty);
        expect(client.downloads, isEmpty);
        expect(await entry.directory.exists(), true);
      } finally {
        await lease.release();
      }
    });

    for (final damage in ['missing', 'changed']) {
      test(
        'a repeated check repairs $damage owned content from the verified shared payload without another transfer/import',
        () async {
          await installBase();
          final saves = await progressFiles();
          await sync();
          if (damage == 'missing') {
            await getContent().parent.delete(recursive: true);
          } else {
            await getContent().writeAsString('damaged owned bytes');
          }
          final imports = importer.imported.length,
              transfers = client.downloads.length;
          await sync();
          expect(await getContent().readAsString(), '$dlcTitle:1');
          expect(importer.imported.length, imports);
          expect(client.downloads.length, transfers);
          for (final f in saves) {
            expect(await f.readAsString(), 'progress');
          }
        },
      );
    }

    test('an extra untracked file in owned content blocks replacement and deletion while preserving all files', () async {
      await installBase();
      await sync();
      final extra = File('${getContent().parent.path}/user-note.txt');
      await extra.writeAsString('keep this unrelated file');
      await expectLater(sync(), throwsA(isA<FileSystemException>()));
      await expectLater(
        library.remove(
          addonServer,
          18,
          uninstallAddons: () => addons.uninstall(addonServer, 18),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await extra.readAsString(), 'keep this unrelated file');
      expect(await getContent().readAsString(), '$dlcTitle:1');
    });

    test('other profiles receive private copies on launch; deletion removes add-ons from every profile and keeps all progress', () async {
      await installBase();
      final saves = await progressFiles();
      await sync();
      final other = (await addonRuntime(
        root,
        secondAddonProfile,
        DownloadCancellation(),
      )).$2;
      final otherSave = File('${other.path}/states/progress');
      await otherSave.parent.create(recursive: true);
      await otherSave.writeAsString('other');
      final lease = await SessionLease.acquire(root);
      try {
        await addons.applyForLaunch(
          addonServer,
          18,
          secondAddonProfile,
          other,
          '${entry.directory.path}/content/Game.cci',
        );
      } finally {
        await lease.release();
      }
      final otherContent = File(
        '${azaharUserPath(other.path)}/${titleContentPath(dlcTitle)}/00000000.app',
      );
      expect(await otherContent.readAsString(), '$dlcTitle:1');
      await library.remove(
        addonServer,
        18,
        uninstallAddons: () => addons.uninstall(addonServer, 18),
      );
      expect(await getContent().exists(), false);
      expect(await otherContent.exists(), false);
      expect(await entry.directory.exists(), false);
      for (final f in saves) {
        expect(await f.readAsString(), 'progress');
      }
      expect(await otherSave.readAsString(), 'other');
      expect(
        (await Directory('${azaharUserPath(profile.path)}/nand/dbs/ticket.db')
            .list()
            .toList()),
        isEmpty,
      );
    });

    test(
      'shared native title ownership survives removing one installed version',
      () async {
        await installBase();
        await sync();
        final payloadRoot = Directory('${root.path}/addons/$addonServer/18');
        final manifest = jsonDecode(
          await File('${payloadRoot.path}/current.json').readAsString(),
        ) as Map;
        final payload = Directory(
          '${payloadRoot.path}/${manifest['generation']}/payload',
        );
        await AzaharAddonProfile(profile).apply(
          '$addonServer/19',
          payload,
          (manifest['units'] as Map).cast<String, dynamic>(),
        );
        await library.remove(
          addonServer,
          18,
          uninstallAddons: () => addons.uninstall(addonServer, 18),
        );
        expect(await getContent().exists(), true);
        await AzaharAddonProfile(profile).remove('$addonServer/19');
        expect(await getContent().exists(), false);
      },
    );

    test('interrupted replacement recovers after a held backup; committed cleanup tolerates loss of its inner journal', () async {
      await installBase();
      await sync();
      final files = {
        'Game.cci': base3ds(),
        'dlc/Pack.cia': addonCia(version: 2),
      };
      remote = await addonGame(root, files);
      client.payloads.addAll(filesClient(remote, files).payloads);
      var stopped = false;
      addons = GameAddons(
        root,
        library,
        prepare: (id, c) => addonRuntime(root, id, c),
        importer: importer.call,
        checkpoint: (p) {
          if (p == 'backed-up' && !stopped) {
            stopped = true;
            throw StateError('power loss');
          }
        },
      );
      await expectLater(sync(), throwsStateError);
      expect(await File('${profile.path}/addons-pending.json').exists(), true);
      final recovering = AzaharAddonProfile(
        profile,
        checkpoint: (p) {
          if (p == 'committed') throw StateError('cleanup failure');
        },
      );
      await expectLater(recovering.recover(), throwsStateError);
      await File('${profile.path}/.addon-transaction/journal.json').delete();
      await AzaharAddonProfile(profile).recover();
      expect(await getContent().readAsString(), '$dlcTitle:2');
      expect(await File('${profile.path}/addons-pending.json').exists(), false);
    });

    test('foreign native content and symlinked title parents are preserved, never adopted or overwritten', () async {
      await installBase();
      final foreign = getContent();
      await foreign.parent.create(recursive: true);
      await foreign.writeAsString('foreign');
      await expectLater(sync(), throwsA(isA<FileSystemException>()));
      expect(await foreign.readAsString(), 'foreign');
      await foreign.parent.delete(recursive: true);
      final outside = Directory('${root.path}/outside');
      await outside.create();
      await Link(foreign.parent.path).create(outside.path);
      await expectLater(sync(), throwsA(isA<FileSystemException>()));
      expect(await outside.list().toList(), isEmpty);
    });

    test('failed add-on removal leaves a durable game deletion intent and retries after an inner receipt is lost', () async {
      await installBase();
      final saves = await progressFiles();
      await sync();
      addons = GameAddons(
        root,
        library,
        prepare: (id, c) => addonRuntime(root, id, c),
        importer: importer.call,
        checkpoint: (p) {
          if (p == 'backed-up') throw StateError('interrupted uninstall');
        },
      );
      await expectLater(
        library.remove(
          addonServer,
          18,
          uninstallAddons: () => addons.uninstall(addonServer, 18),
        ),
        throwsStateError,
      );
      expect((await library.load(addonServer)).games.single.removing, true);
      await File('${entry.directory.path}/receipt.json').delete();
      // The outer identity survives even after a recursive cleanup loses its receipt.
      await entry.directory.rename(
        '${entry.directory.parent.path}/.deleting-18',
      );
      addons = GameAddons(
        root,
        library,
        prepare: (id, c) => addonRuntime(root, id, c),
        importer: importer.call,
      );
      await library.remove(
        addonServer,
        18,
        uninstallAddons: () => addons.uninstall(addonServer, 18),
      );
      expect((await library.load(addonServer)).games, isEmpty);
      expect(await getContent().exists(), false);
      for (final f in saves) {
        expect(await f.readAsString(), 'progress');
      }
    });
  }, skip: !Platform.isMacOS);
}
