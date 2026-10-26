import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/ps3_disc.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/shell/library.dart';

import 'ps3_addons_test.dart' show ps3Sfo, serial;
import 'support/addon_fixtures.dart' show addonGame, filesClient, addonServer;

Uint8List discFixture({
  bool duplicate = false,
  bool badExtent = false,
  bool multipartData = false,
  bool multipartMetadata = false,
}) {
  final b = Uint8List(64 * 2048), d = ByteData.sublistView(b);
  void both(int at, int value, int size) {
    if (size == 2) {
      d.setUint16(at, value, Endian.little);
      d.setUint16(at + 2, value, Endian.big);
    } else {
      d.setUint32(at, value, Endian.little);
      d.setUint32(at + 4, value, Endian.big);
    }
  }

  Uint8List record(List<int> name, int sector, int length, bool folder) {
    final r = Uint8List((33 + name.length + 1) & ~1),
        x = ByteData.sublistView(r);
    r[0] = r.length;
    x.setUint32(2, sector, Endian.little);
    x.setUint32(6, sector, Endian.big);
    x.setUint32(10, length, Endian.little);
    x.setUint32(14, length, Endian.big);
    r[25] = folder ? 2 : 0;
    x.setUint16(28, 1, Endian.little);
    x.setUint16(30, 1, Endian.big);
    r[32] = name.length;
    r.setRange(33, 33 + name.length, name);
    return r;
  }

  void directory(int sector, List<Uint8List> entries) {
    var p = sector * 2048;
    for (final e in entries) {
      b.setRange(p, p + e.length, e);
      p += e.length;
    }
  }

  final p = 16 * 2048;
  b[p] = 1;
  b.setRange(p + 1, p + 6, ascii.encode('CD001'));
  b[p + 6] = 1;
  both(p + 80, 64, 4);
  both(p + 128, 2048, 2);
  final root = record([0], 20, 2048, true);
  b.setRange(p + 156, p + 156 + root.length, root);
  directory(20, [
    record([0], 20, 2048, true),
    record([1], 20, 2048, true),
    record(ascii.encode('PS3_GAME'), 21, 2048, true),
  ]);
  final sfo = ps3Sfo();
  directory(21, [
    record(ascii.encode('USRDIR'), 22, 2048, true),
    record(ascii.encode('PARAM.SFO;1'), badExtent ? 90 : 24, sfo.length, false)
      ..[25] = multipartMetadata ? 128 : 0,
    if (duplicate) record(ascii.encode('PARAM.SFO;1'), 24, sfo.length, false),
  ]);
  directory(22, [
    record(ascii.encode('EBOOT.BIN;1'), 23, 128, false),
    if (multipartData) ...[
      record(ascii.encode('GT.VOL;1'), 27, 4096, false)..[25] = 128,
      record(ascii.encode('GT.VOL;1'), 29, 4096, false)..[25] = 128,
      record(ascii.encode('GT.VOL;1'), 31, 512, false),
    ],
  ]);
  b.setRange(24 * 2048, 24 * 2048 + sfo.length, sfo);
  return b;
}

void main() {
  late Directory data;
  late File iso;
  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-ps3-disc-');
    iso = File('${data.path}/Game.iso');
  });
  tearDown(() async => data.delete(recursive: true));
  test('unrelated multi-extent data does not prevent PS3 title inspection, but multipart metadata remains rejected', () async {
    final bytes = discFixture(multipartData: true);
    await iso.writeAsBytes(bytes);
    expect((await readPs3GameMetadata(iso.path))['TITLE_ID'], serial);
    expect(await iso.readAsBytes(), bytes);
    await iso.writeAsBytes(discFixture(multipartMetadata: true));
    await expectLater(ps3DiscMetadata(iso), throwsFormatException);
  });
  test('ISO metadata selects a title without extracting and the matching native sidecar stays beside the boot image', () async {
    final bytes = discFixture();
    await iso.writeAsBytes(bytes);
    final key = File('${data.path}/Game.dkey');
    await key.writeAsString('0' * 32);
    expect((await readPs3GameMetadata(iso.path))['TITLE_ID'], serial);
    expect(await ps3DiscKey(iso), key.path);
    for (final platform in playablePlatforms.where((p) => p.slug == 'ps3'))
      expect(
        gameCandidates(platform, [
          iso.path,
          key.path,
          '${data.path}/readme.bin',
        ]),
        [iso.path],
        reason: platform.emulator,
      );
    expect(await iso.readAsBytes(), bytes);
    expect(await key.readAsString(), '0' * 32);
  });
  test('ambiguous, out-of-bounds and truncated ISO metadata fail without modifying the image', () async {
    for (final bytes in [
      discFixture(duplicate: true),
      discFixture(badExtent: true),
      Uint8List(100),
    ]) {
      await iso.writeAsBytes(bytes);
      await expectLater(ps3DiscMetadata(iso), throwsA(isA<FormatException>()));
      expect(await iso.readAsBytes(), bytes);
    }
  });
  test('a complete RomM manifest downloads the ISO and its adjacent key into the same verified installation', () async {
    final payloads = {
      'Game.iso': discFixture(),
      'Game.dkey': ascii.encode('a' * 32),
    };
    final template = await addonGame(data, payloads);
    final game = RommGame(
      id: template.id,
      name: 'PS3 fixture',
      platformId: 3,
      platform: 'PlayStation 3',
      platformSlug: 'ps3',
      fullPath: template.fullPath,
      fsName: template.fsName,
      files: template.files,
    );
    final client = filesClient(game, payloads);
    try {
      final library = GameLibrary(data);
      final installed = await library.install(
        serverId: addonServer,
        userId: 3,
        game: game,
        client: client,
        cancellation: DownloadCancellation(),
        progress: (_) {},
      );
      final files = await library.contentFiles(installed);
      final candidate = files.singleWhere((p) => p.endsWith('.iso'));
      final key = await ps3DiscKey(File(candidate));
      expect(key, '${File(candidate).parent.path}/Game.dkey');
      expect(await File(key!).readAsBytes(), payloads['Game.dkey']);
      expect(client.downloads, hasLength(2));
      expect((await readPs3GameMetadata(candidate))['TITLE_ID'], serial);
    } finally {
      client.close();
    }
  });
  test('RPCS3 sidecars accept native text/binary formats and invalid keys never enter an error message', () async {
    expect(await ps3DiscKey(iso), isNull);
    final key = File('${data.path}/Game.dkey');
    for (final bytes in [
      ascii.encode('${'a' * 32}\r\n'),
      List<int>.generate(16, (i) => i),
    ]) {
      await key.writeAsBytes(bytes);
      expect(await ps3DiscKey(iso), key.path);
    }
    await key.writeAsString('invalid-secret');
    await expectLater(
      ps3DiscKey(iso),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'safe message',
          isNot(contains('invalid-secret')),
        ),
      ),
    );
  });
}
