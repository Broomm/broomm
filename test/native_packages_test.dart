import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/addons/files.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/addons/package_profile.dart';
import 'package:broomm/src/addons/package_import.dart';
import 'package:broomm/src/addons/packages.dart';
import 'package:broomm/src/addons/wii.dart';
import 'package:broomm/src/addons/wii_shared.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/shell/library.dart';

import 'support/addon_fixtures.dart';

Uint8List _wad(String id, {bool shared = false}) {
  final bytes = Uint8List(0x40 + 0x2c0 + 0x140 + 0xa4 + 36),
      d = ByteData.sublistView(bytes);
  d.setUint32(0, 0x20);
  d.setUint16(4, 0x4973);
  d.setUint32(16, 0x2a4);
  d.setUint32(20, 0x140 + 0xa4 + 36);
  const t = 0x300;
  d.setUint32(t, 0x10001);
  d.setUint64(t + 0x140 + 0x4c, int.parse(id, radix: 16));
  d.setUint16(t + 0x140 + 0x9e, 1);
  d.setUint16(t + 0x140 + 0x9c, 2);
  d.setUint16(t + 0x140 + 0xa4 + 6, shared ? 0x8001 : 1);
  return bytes;
}

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('broomm-native-packages-'),
  );
  tearDown(() async => root.delete(recursive: true));
  test('Wii game metadata excludes system titles and mismatched regions/channel DLC', () async {
    final f = File('${root.path}/game.wad');
    await f.writeAsBytes(_wad('0001000577464345', shared: true));
    final dlc = await readWiiWad(f.path);
    expect(dlc.shared, true);
    expect(dlc.regularContents, 0);
    matchWiiContent('0001000157464345', dlc, 'dlc');
    expect(
      () => matchWiiContent('0001000157464350', dlc, 'dlc'),
      throwsFormatException,
    );
    expect(
      () => matchWiiContent('0001000157463245', dlc, 'dlc'),
      throwsFormatException,
    );
    await f.writeAsBytes(_wad('0000000100000002'));
    await expectLater(readWiiWad(f.path), throwsFormatException);
    await f.writeAsBytes([1, 2]);
    await expectLater(readWiiWad(f.path), throwsFormatException);
  });
  test(
    'Wii disc identity validates the console header and WBFS sector geometry',
    () async {
      final header = Uint8List(0x80);
      header.setRange(0, 6, ascii.encode('RSBE01'));
      ByteData.sublistView(header).setUint32(0x18, 0x5d1c9ea3);
      final iso = File('${root.path}/game.iso');
      await iso.writeAsBytes(header);
      expect(await wiiDiscId(iso.path), 'RSBE01');
      final wbfs = Uint8List(1024);
      wbfs.setRange(0, 4, ascii.encode('WBFS'));
      wbfs[8] = 9;
      wbfs[9] = 21;
      wbfs[12] = 1;
      wbfs.setRange(512, 640, header);
      final f = File('${root.path}/game.wbfs');
      await f.writeAsBytes(wbfs);
      expect(await wiiDiscId(f.path), 'RSBE01');
      header[0x18] = 0;
      await iso.writeAsBytes(header);
      await expectLater(wiiDiscId(iso.path), throwsFormatException);
    },
  );
  test(
    'Wii shared map retains existing IDs and rejects ambiguous identities',
    () {
      final rows = {'00000009': 'a' * 40, '00000010': 'b' * 40};
      expect(readWiiContentMap(writeWiiContentMap(rows)), rows);
      expect(
        () => writeWiiContentMap({'00000000': 'a' * 40, '00000001': 'a' * 40}),
        throwsFormatException,
      );
      expect(() => readWiiContentMap(Uint8List(29)), throwsFormatException);
    },
  );
  test('Switch schema uses native is_enabled/path, validates title association and preserves disabled existing DLC', () {
    const base = '01005d100807a000', p = '/private/package.nsp';
    Map<String, dynamic> n() => {
      'path': '/${'a' * 32}.nca',
      'title_id': int.parse('01005d100807b001', radix: 16),
      'is_enabled': true,
    };
    List<dynamic> dlc(Map v) => [
      {
        'path': p,
        'dlc_nca_list': [v],
      },
    ];
    validateSwitchPackages(base, null, dlc(n()), {p});
    validateSwitchPackages(base, null, dlc({...n(), 'is_enabled': false}), {p});
    expect(
      () =>
          validateSwitchPackages(base, null, dlc({...n(), 'title_id': 1}), {p}),
      throwsFormatException,
    );
    expect(
      () => validateSwitchPackages(
        base,
        {
          'selected': '/foreign',
          'paths': [p],
        },
        null,
        {p},
      ),
      throwsFormatException,
    );
    expect(
      () => validateSwitchPackages(
        base,
        null,
        dlc({
          'enabled': true,
          'full_path': '/${'a' * 32}.nca',
          'title_id': n()['title_id'],
        }),
        {p},
      ),
      throwsFormatException,
    );
  });
  test('library receipts retain API content roles so root-level packages cannot appear as base games', () async {
    final basic = await addonGame(root, {
      'game.nsp': [1],
      'extra.nsp': [2],
    });
    final game = RommGame(
      id: basic.id,
      name: 'Game',
      platformId: 8,
      platform: 'Switch',
      platformSlug: 'switch',
      fullPath: basic.fullPath,
      files: [
        basic.files.first,
        RommFile(
          id: basic.files.last.id,
          romId: basic.id,
          name: basic.files.last.name,
          fullPath: basic.files.last.fullPath,
          bytes: 1,
          category: 'dlc',
        ),
      ],
    );
    final client = filesClient(game, {
      'game.nsp': [1],
      'extra.nsp': [2],
    });
    final library = GameLibrary(root);
    try {
      final entry = await library.install(
        serverId: addonServer,
        userId: 1,
        game: game,
        client: client,
        cancellation: DownloadCancellation(),
        progress: (_) {},
      );
      expect(await library.contentFiles(entry), hasLength(2));
      expect(
        (await library.contentFiles(entry, excludeAddons: true)).single,
        endsWith('/game.nsp'),
      );
    } finally {
      client.close();
    }
  });
  test('native file transaction recovers an interrupted replacement and refuses changed foreign content', () async {
    final user = Directory('${root.path}/user');
    await user.create();
    const path = 'games/01005d100807a000/updates.json';
    final target = await addonFile(user, path, createParents: true);
    await target.writeAsString('{"original":true}');
    final payload = Directory('${root.path}/payload');
    await payload.create();
    final source = await addonFile(payload, path, createParents: true);
    await source.writeAsString('{"paths":["one"]}');
    final hash = await rawHash(source);
    final broken = PackageProfile(
      root,
      'switch',
      checkpoint: (p) {
        if (p == 'backed-up') throw StateError('power loss');
      },
    );
    await expectLater(
      broken.apply('$addonServer/1', payload, {
        path: {
          'version': 1,
          'files': {'': hash},
        },
      }),
      throwsStateError,
    );
    final profile = PackageProfile(root, 'switch');
    await profile.recover();
    expect(await target.readAsString(), await source.readAsString());
    await profile.apply('$addonServer/2', payload, {
      path: {
        'version': 1,
        'files': {'': hash},
      },
    });
    await profile.remove('$addonServer/1');
    expect(await target.exists(), true);
    await target.writeAsString('foreign');
    await expectLater(
      profile.remove('$addonServer/2'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await target.readAsString(), 'foreign');
    await source.copy(target.path);
    await profile.remove('$addonServer/2');
    expect(jsonDecode(await target.readAsString()), {'original': true});
  });
  test('Wii channel and owned DLC progress round trip without capturing installed content or another title', () async {
    await Directory('${root.path}/user').create();
    await File('${root.path}/profile.json')
        .writeAsString(jsonEncode({'version': 1, 'emulator': 'dolphin'}));
    final rom = File('${root.path}/base.wad');
    await rom.writeAsBytes(_wad('0001000157464345'));
    const path = 'Wii/title/00010005/77464345/content/title.tmd';
    final payload = Directory('${root.path}/payload');
    await payload.create();
    final native = await addonFile(payload, path, createParents: true);
    await native.writeAsString('content');
    await PackageProfile(root, 'wii').apply('$addonServer/1', payload, {
      path: {
        'version': 1,
        'files': {'': await rawHash(native)},
      },
    });
    final layout = await gameProgressLayout(
      ResolvedSession(
        PreparedEmulator(
          'Dolphin',
          root.path,
          'unused',
          2,
          null,
          null,
          contentId: '1',
        ),
        rom.path,
        'a' * 64,
        {},
      ),
      'wii',
    );
    await (await layout.target('save/progress')).writeAsString('base progress');
    await (await layout.target('dlc-77464345/progress'))
        .writeAsString('DLC progress');
    final files = await layout.files();
    expect(files.keys, containsAll(['save/progress', 'dlc-77464345/progress']));
    expect(files.keys.any((k) => k.contains('content')), false);
    final store = ProgressStore(Directory('${root.path}/store'), layout, 1, 1),
        snapshot = await store.capture();
    final out = await store.exportNative(snapshot);
    try {
      expect(
        (await store.importNative(out.file)).ordinaryDigest,
        snapshot.ordinaryDigest,
      );
      final retained = ProgressStore(
        Directory('${root.path}/retained'),
        ProgressLayout(
          root.path,
          layout.format,
          layout.game,
          [],
          archiveOnly: true,
        ),
        1,
        1,
      );
      expect(
        (await retained.importNative(out.file)).ordinaryDigest,
        snapshot.ordinaryDigest,
      );
    } finally {
      await out.close();
    }
    await PackageProfile(root, 'wii').remove('$addonServer/1');
    expect(
      await (await layout.target('dlc-77464345/progress')).readAsString(),
      'DLC progress',
    );
  });
  group('Switch packages', () {
    late GameLibrary library;
    late GamePackages service;
    late AddonFiles client;
    Future<(String, Directory)> prepare(
      String id,
      DownloadCancellation c,
    ) async {
      final p = Directory('${root.path}/profiles/$id/emulators/ryubing');
      await Directory('${p.path}/user').create(recursive: true);
      await File('${p.path}/profile.json').writeAsString(
        jsonEncode({'version': 1, 'profile': id, 'emulator': 'ryubing'}),
      );
      return ('unused', p);
    }

    Future<RommGame> game(int id, {bool dlc = true}) async {
      final made = await addonGame(root, {
        'game.nsp': [1],
        if (dlc) 'dlc/extra.nsp': [2],
      }, id: id);
      return RommGame(
        id: id,
        name: 'Game',
        platformId: 8,
        platform: 'Nintendo Switch',
        platformSlug: 'switch',
        fullPath: made.fullPath,
        files: [
          for (final f in made.files)
            RommFile(
              id: f.id,
              romId: id,
              name: f.name,
              fullPath: f.fullPath,
              bytes: f.bytes,
              crc: '',
            ),
        ],
      );
    }

    Future<InstalledGame> install(int id) async {
      final base = await game(id, dlc: false);
      client.payloads.addAll(
        filesClient(base, {
          'game.nsp': [1],
        }).payloads,
      );
      return library.install(
        serverId: addonServer,
        userId: 7,
        game: base,
        client: client,
        cancellation: DownloadCancellation(),
        progress: (_) {},
      );
    }

    Future<void> sync(InstalledGame entry) async {
      final remote = await game(entry.game.id);
      client.payloads.addAll(
        filesClient(remote, {
          'game.nsp': [1],
          'dlc/extra.nsp': [2],
        }).payloads,
      );
      await service.sync(
        serverId: addonServer,
        profileId: addonProfile,
        entry: entry,
        game: remote,
        client: client,
        cancellation: DownloadCancellation(),
        progress: (_) {},
      );
    }

    setUp(() {
      library = GameLibrary(root);
      client = AddonFiles({});
      service = GamePackages(
        root,
        library,
        'switch',
        prepare: prepare,
        switchInspector:
            (exe, base, packages, stage, profile, data, cancel) async {
              final paths = await packages
                  .list()
                  .where((f) => f is File)
                  .map((f) => f.absolute.path)
                  .toList();
              return SwitchPackages('01005d100807a000', null, [
                for (final path in paths)
                  {
                    'path': path,
                    'dlc_nca_list': [
                      {
                        'is_enabled': true,
                        'title_id': int.parse('01005d100807b001', radix: 16),
                        'path': '/${'a' * 32}.nca',
                      },
                    ],
                  },
              ]);
            },
      );
    });
    tearDown(() => client.close());
    test('restarted base-only Switch installations need no downloadable manifest or package import', () async {
      await install(1);
      final restored = (await GameLibrary(root).load(addonServer)).games.single;
      expect(restored.game.files, isEmpty);
      client.problem = const RommFailure('Offline');
      expect(await service.needsSwitchSelection(addonServer, restored), false);
      expect(await library.contentFiles(restored, excludeAddons: true), [
        endsWith('/game.nsp'),
      ]);
    });
    test('restarted Switch content reuses its checkpoint for both profiles without a remote manifest and rejects a damaged checkpoint', () async {
      final entry = await install(1);
      await sync(entry);
      final restored = (await GameLibrary(root).load(addonServer)).games.single;
      expect(restored.game.files, isEmpty);
      client.problem = const RommFailure('Offline');
      final transfers = client.downloads.length;
      expect(await service.needsSwitchSelection(addonServer, restored), false);
      final first = (await prepare(addonProfile, DownloadCancellation())).$2;
      final second = (await prepare(
        secondAddonProfile,
        DownloadCancellation(),
      )).$2;
      final save = File('${second.path}/user/bis/user/save/progress');
      await save.parent.create(recursive: true);
      await save.writeAsString('retained');
      final lease = await SessionLease.acquire(root);
      try {
        for (final (id, profile) in [
          (addonProfile, first),
          (secondAddonProfile, second),
        ]) {
          await service.applyForLaunch(
            addonServer,
            1,
            id,
            profile,
            (await library.contentFiles(restored, excludeAddons: true)).single,
            entry: restored,
          );
        }
      } finally {
        await lease.release();
      }
      const selection = 'user/games/01005d100807a000/dlc.json';
      expect(
        await File('${first.path}/$selection').readAsString(),
        await File('${second.path}/$selection').readAsString(),
      );
      expect(client.downloads.length, transfers);
      expect(await save.readAsString(), 'retained');
      final checkpoint = File(
        '${root.path}/addons/$addonServer/1/switch/current.json',
      );
      final changed = jsonDecode(await checkpoint.readAsString()) as Map;
      changed['base'] = '0100000000000000';
      await checkpoint.writeAsString(jsonEncode(changed));
      await expectLater(
        service.needsSwitchSelection(addonServer, restored),
        throwsA(isA<FileSystemException>()),
      );
      expect(await save.readAsString(), 'retained');
    });
    test('first Switch package import after restart resolves real file identities and reuses installed folder or root-role DLC', () async {
      for (final path in ['dlc/extra.nsp', 'extra.nsp']) {
        final id = path.contains('/') ? 10 : 11;
        final payloads = {
          'game.nsp': [1],
          path: [2],
        };
        final made = await addonGame(
          root,
          payloads,
          id: id,
          categories: {path: 'dlc'},
        );
        final remote = RommGame(
          id: id,
          name: 'Game',
          platformId: 8,
          platform: 'Nintendo Switch',
          platformSlug: 'switch',
          fullPath: made.fullPath,
          files: made.files,
        );
        client.payloads.addAll(filesClient(remote, payloads).payloads);
        final entry = await library.install(
          serverId: addonServer,
          userId: 7,
          game: remote,
          client: client,
          cancellation: DownloadCancellation(),
          progress: (_) {},
        );
        // Legacy folder receipts may not have an API category at all.
        if (path.contains('/')) {
          final receipt = File('${entry.directory.path}/receipt.json');
          final record = jsonDecode(await receipt.readAsString()) as Map;
          for (final file in record['files'] as List) {
            (file as Map).remove('category');
          }
          await receipt.writeAsString(jsonEncode(record));
        }
        final restored = (await GameLibrary(root).load(addonServer)).games
            .singleWhere((e) => e.game.id == id);
        expect(restored.game.files, isEmpty);
        expect(await service.needsSwitchSelection(addonServer, restored), true);
        client.detail = remote;
        final transfers = client.downloads.length;
        await service.sync(
          serverId: addonServer,
          profileId: addonProfile,
          entry: restored,
          game: restored.game,
          client: client,
          cancellation: DownloadCancellation(),
          progress: (_) {},
        );
        expect(client.downloads.length, transfers);
        expect(
          await service.needsSwitchSelection(addonServer, restored),
          false,
        );
      }
    });
    test('failed or mismatched Switch manifest recovery preserves installed media without publishing content', () async {
      final entry = await install(1);
      final restored = (await GameLibrary(root).load(addonServer)).games.single;
      final checkpoint = File(
        '${root.path}/addons/$addonServer/1/switch/current.json',
      );
      Future<void> attempt() => service.sync(
        serverId: addonServer,
        profileId: addonProfile,
        entry: restored,
        game: restored.game,
        client: client,
        cancellation: DownloadCancellation(),
        progress: (_) {},
      );
      client.problem = const RommFailure('Unavailable', status: 503);
      await expectLater(attempt(), throwsA(isA<RommFailure>()));
      client.problem = null;
      client.detail = await game(2);
      await expectLater(attempt(), throwsFormatException);
      client.detail = restored.game;
      await expectLater(attempt(), throwsA(isA<RommFailure>()));
      expect(await checkpoint.exists(), false);
      expect(
        await File('${entry.directory.path}/content/game.nsp').readAsBytes(),
        [1],
      );
      expect(await Directory('${root.path}/profiles').exists(), false);
    });
    test('empty API checksums permit transfer; repeat avoids it; package bytes survive another owner until its removal', () async {
      final a = await install(1), b = await install(2);
      await sync(a);
      final count = client.downloads.length;
      await sync(a);
      expect(client.downloads.length, count);
      await sync(b);
      final profile = (await prepare(addonProfile, DownloadCancellation())).$2;
      final dlcFile = File(
        '${profile.path}/user/games/01005d100807a000/dlc.json',
      );
      final path =
          (jsonDecode(await dlcFile.readAsString()) as List).single['path']
              as String;
      final lease = await SessionLease.acquire(root);
      try {
        await service.uninstall(addonServer, 2);
        expect(await File(path).exists(), true);
        expect(await dlcFile.exists(), true);
        await service.uninstall(addonServer, 1);
        expect(await File(path).exists(), false);
        expect(await dlcFile.exists(), false);
      } finally {
        await lease.release();
      }
    });
    for (final keepReference in [false, true]) {
      test(
        'native Switch references ${keepReference ? 'retain package bytes until explicitly removed' : 'outside the package directory cannot retain a generation'}',
        () async {
          final entry = await install(1);
          await sync(entry);
          final profile = (await prepare(
            addonProfile,
            DownloadCancellation(),
          )).$2;
          final original = File(
            '${profile.path}/user/games/01005d100807a000/dlc.json',
          );
          final path =
              (jsonDecode(await original.readAsString()) as List).single['path']
                  as String;
          // Native enumeration uses host separators, unlike the joined setup
          // paths. A user-managed emulator entry must still protect its bytes.
          final package =
              (await File(
                    path,
                  ).parent.list().where((e) => e is File).toList()).single
                  as File;
          final external = File(
            '${profile.path}/user/games/0100000000000000/updates.json',
          );
          await external.parent.create();
          final reference = keepReference
              ? package.path
              : '${package.parent.path}-other/not-owned.nsp';
          final text = jsonEncode([
            {'path': reference},
          ]);
          await external.writeAsString(text);
          final lease = await SessionLease.acquire(root);
          try {
            await service.uninstall(addonServer, 1);
            expect(await File(path).exists(), keepReference);
            expect(await external.readAsString(), text);
            if (keepReference) {
              await external.delete();
              await service.uninstall(addonServer, 1);
              expect(await File(path).exists(), false);
            }
          } finally {
            await lease.release();
          }
        },
      );
    }
    test('durable deletion resumes after an inner manifest is lost and preserves game progress', () async {
      final entry = await install(1);
      await sync(entry);
      final profile = (await prepare(addonProfile, DownloadCancellation())).$2;
      final save = File('${profile.path}/user/bis/user/save/progress');
      await save.parent.create(recursive: true);
      await save.writeAsString('keep');
      final broken = GamePackages(
        root,
        library,
        'switch',
        prepare: prepare,
        checkpoint: (p) {
          if (p == 'deletion-prepared') throw StateError('power loss');
        },
      );
      final lease = await SessionLease.acquire(root);
      try {
        await expectLater(broken.uninstall(addonServer, 1), throwsStateError);
        final dir = Directory('${root.path}/addons/$addonServer/1/switch');
        for (final g in await dir.list().where((e) => e is Directory).toList())
          await File('${g.path}/manifest.json').delete();
        await service.uninstall(addonServer, 1);
        expect(await save.readAsString(), 'keep');
        expect(await File('${dir.path}/deleting.json').exists(), false);
      } finally {
        await lease.release();
      }
    });
    test('cancelled transfer leaves current selection and bytes intact and can be retried', () async {
      final entry = await install(1);
      final remote = await game(1);
      client.payloads.addAll(
        filesClient(remote, {
          'game.nsp': [1],
          'dlc/extra.nsp': [2],
        }).payloads,
      );
      client.onDownload = (c) => c.cancel();
      await expectLater(
        service.sync(
          serverId: addonServer,
          profileId: addonProfile,
          entry: entry,
          game: remote,
          client: client,
          cancellation: DownloadCancellation(),
          progress: (_) {},
        ),
        throwsA(isA<DownloadCancelled>()),
      );
      expect(
        await File('${root.path}/addons/$addonServer/1/switch/current.json')
            .exists(),
        false,
      );
      client.onDownload = null;
      await sync(entry);
      expect(
        await File('${root.path}/addons/$addonServer/1/switch/current.json')
            .exists(),
        true,
      );
    });
  });
}

Future<String> rawHash(File file) async {
  return progressFileHash(file);
}
