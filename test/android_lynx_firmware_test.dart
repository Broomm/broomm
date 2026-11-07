import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/android/lynx_firmware.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client extends RommClient {
  _Client() : super(Uri.parse('https://fixture.invalid'));
  List<RommFirmware> records = [];
  List<int> payload = [];
  int lookups = 0, downloads = 0;
  bool unavailable = false, cancelTransfer = false, writerUncertain = false;
  @override
  Future<List<RommFirmware>> firmware(int platformId) async {
    lookups++;
    if (unavailable) throw const RommFailure('Firmware catalogue unavailable.');
    return records;
  }

  @override
  Future<void> downloadFirmware(
    RommFirmware source,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    downloads++;
    await destination.writeAsBytes(payload, flush: true);
    if (writerUncertain) throw const DownloadWriterUncertain();
    if (cancelTransfer) cancellation.cancel();
    cancellation.check();
    onProgress(payload.length);
  }
}

void main() {
  late Directory root;
  late _Client client;
  const platform = 4;
  const nonce = '123456789abcdef0123456789abcdef0';
  RommFirmware bios({
    int id = 1,
    int p = platform,
    String name = 'lynxboot.img',
    int bytes = 512,
    String md5 = androidLynxBootMd5,
  }) => RommFirmware(id, p, name, bytes, md5);
  Future<AndroidLynxBootImage> ensure([DownloadCancellation? cancel]) =>
      ensureAndroidLynxBoot(
        root,
        platform,
        client,
        cancel ?? DownloadCancellation(),
        (_) {},
      );
  Future<File> damagedCache() async {
    final cache = await Directory('${root.path}/lynx-firmware').create();
    final file = await File('${cache.path}/$nonce.img').writeAsBytes([1, 2, 3]);
    await File('${cache.path}/index.json').writeAsString(
      jsonEncode({
        'version': 1,
        'platform': platform,
        'object': nonce,
        'bytes': 512,
        'md5': androidLynxBootMd5,
        'sha256': 'a' * 64,
      }),
    );
    return file;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-lynx-bios-');
    client = _Client();
  });
  tearDown(() async {
    client.close();
    await root.delete(recursive: true);
  });

  test('RomM firmware transfer verifies actual size/hash and refuses an existing destination', () async {
    client.payload = List.generate(512, (i) => i % 251);
    final md5 = (ProgressDigest.md5()..add(client.payload)).finish();
    final source = bios(md5: md5);
    final target = File('${root.path}/verified');
    await downloadAndroidFirmware(
      client,
      source,
      target,
      DownloadCancellation(),
    );
    expect(await target.readAsBytes(), client.payload);
    await expectLater(
      downloadAndroidFirmware(client, source, target, DownloadCancellation()),
      throwsA(isA<FileSystemException>()),
    );
    expect(client.downloads, 1);
    for (final payload in [List.filled(511, 9), List.filled(512, 9)]) {
      client.payload = payload;
      await expectLater(
        downloadAndroidFirmware(
          client,
          source,
          File('${root.path}/bad-${payload.length}'),
          DownloadCancellation(),
        ),
        throwsA(isA<RommFailure>()),
      );
    }
  });

  test(
    'Lynx requires one matching platform/name and canonical BIOS metadata',
    () async {
      for (final records in <List<RommFirmware>>[
        [],
        [bios(p: 99)],
        [bios(name: 'other.img')],
        [bios(), bios(id: 2, name: 'LYNXBOOT.IMG')],
        [bios(bytes: 513)],
        [bios(md5: 'b' * 32)],
      ]) {
        client.records = records;
        await expectLater(ensure(), throwsA(isA<RommFailure>()));
      }
      expect(client.downloads, 0);
      expect(
        await File('${root.path}/lynx-firmware/index.json').exists(),
        false,
      );
    },
  );

  test('damaged BIOS repair preserves its old bytes/index when catalogue or content verification fails', () async {
    final original = await damagedCache();
    final index = File('${root.path}/lynx-firmware/index.json');
    final before = await index.readAsBytes();
    client.unavailable = true;
    await expectLater(ensure(), throwsA(isA<RommFailure>()));
    expect(client.downloads, 0);
    client.unavailable = false;
    client.records = [bios(name: 'LYNXBOOT.IMG')];
    client.payload = List.filled(512, 9);
    await expectLater(ensure(), throwsA(isA<RommFailure>()));
    expect(client.downloads, 1);
    expect(await original.readAsBytes(), [1, 2, 3]);
    expect(await index.readAsBytes(), before);
    expect((await index.parent.list().toList()).length, 2);
  });

  test('cancelled BIOS transfer cleans only private incoming data and retains damaged cache', () async {
    final original = await damagedCache();
    client.records = [bios()];
    client.payload = List.filled(512, 9);
    client.cancelTransfer = true;
    await expectLater(ensure(), throwsA(isA<DownloadCancelled>()));
    expect(await original.readAsBytes(), [1, 2, 3]);
    expect((await original.parent.list().toList()).length, 2);
  });

  test(
    'invalid and linked cache records fail before firmware discovery',
    () async {
      final old = await damagedCache();
      final index = File('${old.parent.path}/index.json');
      await index.writeAsString('{invalid');
      await expectLater(ensure(), throwsFormatException);
      expect(client.lookups, 0);
      await index.delete();
      await Link(index.path).create(old.path);
      await expectLater(ensure(), throwsA(isA<FileSystemException>()));
      expect(client.lookups, 0);
      expect(await old.readAsBytes(), [1, 2, 3]);
    },
  );

  test('an unacknowledged firmware writer retains private staging and the original cache', () async {
    final original = await damagedCache();
    client.records = [bios()];
    client.payload = [4, 5];
    client.writerUncertain = true;
    await expectLater(ensure(), throwsA(isA<DownloadWriterUncertain>()));
    expect(await original.readAsBytes(), [1, 2, 3]);
    final incoming = (await original.parent.list().toList())
        .whereType<Directory>()
        .single;
    expect(await File('${incoming.path}/lynxboot.img').readAsBytes(), [4, 5]);
  });
}
