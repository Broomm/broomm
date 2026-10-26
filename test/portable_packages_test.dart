import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/addons/eden.dart';
import 'package:broomm/src/addons/packages.dart';
import 'package:broomm/src/addons/service.dart' show AddonResult;
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/zip.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/shell/library.dart';

import 'psp_test.dart' show pspPbp;
import 'support/addon_fixtures.dart';

Uint8List _nca(String title, int type) {
  final b = Uint8List(0xc00), d = ByteData.sublistView(b);
  b.setRange(0x200, 0x204, ascii.encode('NCA3'));
  b[0x205] = type;
  d.setUint64(0x208, b.length, Endian.little);
  d.setUint64(0x210, int.parse(title, radix: 16), Endian.little);
  return b;
}

Uint8List _nsp(Map<String, Uint8List> files) {
  final strings = BytesBuilder(), offsets = <int>[];
  for (final name in files.keys) {
    offsets.add(strings.length);
    strings.add(utf8.encode('$name\x00'));
  }
  final names = strings.takeBytes(),
      header = Uint8List(16 + files.length * 24 + names.length),
      d = ByteData.sublistView(header),
      out = BytesBuilder();
  header.setRange(0, 4, ascii.encode('PFS0'));
  d.setUint32(4, files.length, Endian.little);
  d.setUint32(8, names.length, Endian.little);
  var offset = 0, i = 0;
  for (final b in files.values) {
    d.setUint64(16 + i * 24, offset, Endian.little);
    d.setUint64(24 + i * 24, b.length, Endian.little);
    d.setUint32(32 + i * 24, offsets[i], Endian.little);
    offset += b.length;
    i++;
  }
  header.setRange(16 + files.length * 24, header.length, names);
  out.add(header);
  for (final b in files.values) out.add(b);
  return out.takeBytes();
}

String _id(List<int> bytes) =>
    (ProgressDigest.sha256()..add(bytes)).finish().substring(0, 32);

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp(
      'broomm-portable-packages-',
    ),
  );
  tearDown(() async => root.delete(recursive: true));

  test('PSP downloads native DLC once, retries cancellation, and uninstalls content while preserving new saved progress', () async {
    final archiveRoot = await root.createTemp('zip-'),
        dlc = File(
          '${archiveRoot.path}/PSP/SAVEDATA/ULUS10340DLC/CONTENT.EDAT',
        );
    await dlc.parent.create(recursive: true);
    await dlc.writeAsBytes([1, 2, 3]);
    final zip = File('${root.path}/dlc.zip');
    await ProgressZip.write(zip, archiveRoot, [
      'PSP/SAVEDATA/ULUS10340DLC/CONTENT.EDAT',
    ]);
    final files = {
          'game.pbp': pspPbp(),
          'dlc/pack.zip': await zip.readAsBytes(),
        },
        basic = await addonGame(root, files),
        game = RommGame(
          id: basic.id,
          name: 'PSP',
          platformId: 11,
          platform: 'PlayStation Portable',
          platformSlug: 'psp',
          fullPath: basic.fullPath,
          files: basic.files,
        ),
        client = filesClient(game, files),
        library = GameLibrary(root);
    Future<(String, Directory)> prepare(
      String id,
      DownloadCancellation c,
    ) async {
      c.check();
      final p = Directory('${root.path}/profiles/$id/emulators/ppsspp');
      await Directory('${p.path}/user/PSP/SYSTEM').create(recursive: true);
      await File('${p.path}/profile.json').writeAsString(
        jsonEncode({'version': 1, 'profile': id, 'emulator': 'ppsspp'}),
      );
      return ('unused', p);
    }

    final service = GamePackages(root, library, 'psp', prepare: prepare);
    try {
      final entry = await library.install(
        serverId: addonServer,
        userId: 1,
        game: game,
        client: client,
        cancellation: DownloadCancellation(),
        progress: (_) {},
      );
      Future<AddonResult> sync({DownloadCancellation? cancellation}) =>
          service.sync(
            serverId: addonServer,
            profileId: addonProfile,
            entry: entry,
            game: game,
            client: client,
            cancellation: cancellation ?? DownloadCancellation(),
            progress: (_) {},
          );
      await expectLater(
        sync(cancellation: DownloadCancellation()..cancel()),
        throwsA(isA<DownloadCancelled>()),
      );
      // Local CRC-verified files are reusable without a second transfer.
      await File('${entry.directory.path}/content/dlc/pack.zip').delete();
      // An incomplete library is an error, rather than proof of no DLC.
      await expectLater(sync(), throwsA(isA<FileSystemException>()));
      await File('${entry.directory.path}/content/dlc/pack.zip')
          .writeAsBytes(files['dlc/pack.zip']!);
      final result = await sync();
      expect(result.available, 1);
      final downloads = client.downloads.length;
      expect((await sync()).installed, 0);
      expect(client.downloads.length, downloads);
      final (_, p) = await prepare(addonProfile, DownloadCancellation());
      final content = File(
            '${p.path}/user/PSP/SAVEDATA/ULUS10340DLC/CONTENT.EDAT',
          ),
          save = File('${p.path}/user/PSP/SAVEDATA/ULUS10340DLC/USER.DAT');
      expect(await content.readAsBytes(), [1, 2, 3]);
      await save.writeAsBytes([7]);
      final lease = await SessionLease.acquire(root);
      try {
        await service.uninstall(addonServer, game.id);
      } finally {
        await lease.release();
      }
      expect(await content.exists(), false);
      expect(await save.readAsBytes(), [7]);
    } finally {
      client.close();
    }
  });

  test('Eden refuses foreign titles, ambiguous updates, corrupt duplicate content and oversized tickets before native publication', () async {
    const base = '01005d100807a000', update = '01005d100807a800';
    final program = _nca(base, 0),
        meta = _nca(update, 1),
        game = File('${root.path}/game.nsp'),
        profile = Directory('${root.path}/profile');
    await game.writeAsBytes(_nsp({'${_id(program)}.nca': program}));
    final keys = File('${profile.path}/data/eden/keys/prod.keys');
    await keys.parent.create(recursive: true);
    await keys.writeAsString('header_key = ${'1' * 64}\n');
    Future<File> package(String name, Map<String, Uint8List> entries) async {
      final f = File('${root.path}/$name.nsp');
      await f.writeAsBytes(_nsp(entries));
      return f;
    }

    final good = await package('good', {'${_id(meta)}.cnmt.nca': meta}),
        wrong = _nca('0100123400000800', 1),
        foreign = await package('foreign', {'${_id(wrong)}.nca': wrong}),
        corrupt = Uint8List.fromList(meta)..[0xbff] = 1,
        duplicate = await package('duplicate', {
          '${_id(meta)}.nca': meta,
          '${_id(meta)}.cnmt.nca': corrupt,
        }),
        largeTicket = await package('ticket', {
          '${_id(meta)}.nca': meta,
          'ticket.tik': Uint8List(4097),
        });
    for (final inputs in [
      [(foreign, 'update')],
      [(good, 'update'), (good, 'update')],
      [(duplicate, 'update')],
      [(largeTicket, 'update')],
    ]) {
      final stage = await root.createTemp('payload-');
      await expectLater(
        stageEdenContent(
          game,
          inputs,
          profile,
          stage,
          {},
          1,
          DownloadCancellation(),
        ),
        throwsFormatException,
      );
      expect(await Directory('${profile.path}/data/eden/nand').exists(), false);
      expect(
        await File('${keys.parent.path}/title.keys_autogenerated').exists(),
        false,
      );
    }
    final cancelled = DownloadCancellation()..cancel();
    await expectLater(
      stageEdenContent(
        game,
        [(good, 'update')],
        profile,
        await root.createTemp('cancel-'),
        {},
        1,
        cancelled,
      ),
      throwsA(isA<DownloadCancelled>()),
    );
  });
}
