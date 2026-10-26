import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/zip.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/emulators.dart';

void main() {
  test('streaming SHA-256 and RomM MD5 match standard vectors across padding/chunk boundaries', () {
    for (final v in [
      (
        '',
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'd41d8cd98f00b204e9800998ecf8427e',
      ),
      (
        'abc',
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        '900150983cd24fb0d6963f7d28e17f72',
      ),
      (
        'a' * 1000000,
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
        '7707d6ae4e027c70eea2a935c2296f21',
      ),
    ]) {
      final b = utf8.encode(v.$1),
          sha = ProgressDigest.sha256(),
          md5 = ProgressDigest.md5();
      for (var i = 0; i < b.length; i += 37) {
        final chunk = b.sublist(i, (i + 37).clamp(0, b.length));
        sha.add(chunk);
        md5.add(chunk);
      }
      expect(sha.finish(), v.$2);
      expect(md5.finish(), v.$3);
    }
  });
  test('CRC matches the standard raw reference vector', () {
    final crc = ProgressCrc()..add(utf8.encode('123456789'));
    expect(crc.value, 0xcbf43926);
  });
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('broomm-save-zip-'),
  );
  tearDown(() async => root.delete(recursive: true));
  test(
    'ZIP snapshots stream nested files and match a standard ZIP reader',
    () async {
      final source = Directory('${root.path}/source');
      await source.create();
      await Directory('${source.path}/save/nested').create(recursive: true);
      await File('${source.path}/save/nested/account.bin')
          .writeAsBytes(List.generate(250000, (i) => i % 251));
      await File('${source.path}/broomm.json').writeAsString('{"test":true}');
      final zip = File('${root.path}/snapshot.zip');
      await ProgressZip.write(zip, source, [
        'save/nested/account.bin',
        'broomm.json',
      ]);
      final read = await ProgressZip.read(zip);
      final target = Directory('${root.path}/target');
      final files = await read.extract(target);
      expect(
        files.keys,
        containsAll(['broomm.json', 'save/nested/account.bin']),
      );
      expect(
        await File('${target.path}/save/nested/account.bin').readAsBytes(),
        await File('${source.path}/save/nested/account.bin').readAsBytes(),
      );
      if (Platform.isMacOS) {
        final validation = await Process.run('/usr/bin/unzip', [
          '-t',
          zip.path,
        ]);
        expect(
          validation.exitCode,
          0,
          reason: '${validation.stdout}\n${validation.stderr}',
        );
      }
    },
  );
  test(
    'corrupted data and unsafe names cannot publish over an existing file',
    () async {
      final source = Directory('${root.path}/source');
      await source.create();
      await File('${source.path}/save').writeAsString('progress');
      final zip = File('${root.path}/snapshot.zip');
      await ProgressZip.write(zip, source, ['save']);
      final target = Directory('${root.path}/target');
      await target.create();
      await File('${target.path}/save').writeAsString('keep');
      await expectLater(
        (await ProgressZip.read(zip)).extract(target),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File('${target.path}/save').readAsString(), 'keep');
      final bytes = await zip.readAsBytes();
      final d = ByteData.sublistView(bytes);
      for (var i = 0; i < bytes.length - 46; i++) {
        if (d.getUint32(i, Endian.little) == 0x02014b50) {
          d.setUint32(i + 24, 0xffffffff, Endian.little);
          break;
        }
      }
      await zip.writeAsBytes(bytes);
      await expectLater(ProgressZip.read(zip), throwsFormatException);
      await expectLater(
        ProgressZip.write(File('${root.path}/bad.zip'), source, ['../save']),
        throwsFormatException,
      );
    },
  );

  test('a core change alters the state compatibility boundary and an unknown core cannot authorize state capture', () async {
    await File('${root.path}/profile.json')
        .writeAsString(jsonEncode({'version': 1, 'emulator': 'retroarch'}));
    final emulator = PreparedEmulator(
      'RetroArch',
      root.path,
      'unused',
      3,
      null,
      null,
    );
    Future<ProgressLayout> layout(String? core) => gameProgressLayout(
      ResolvedSession(
        emulator,
        '/unused/game.sfc',
        'a' * 64,
        {},
        coreHash: core,
      ),
      'snes',
    );
    final first = await layout('b' * 64),
        second = await layout('c' * 64),
        unknown = await layout(null);
    final a = first.areas.singleWhere((a) => a.id.startsWith('states-')).id;
    final b = second.areas.singleWhere((a) => a.id.startsWith('states-')).id;
    expect(a, isNot(b));
    expect(first.identity, second.identity);
    expect(unknown.areas.any((a) => a.id.startsWith('states-')), false);
  });
}
