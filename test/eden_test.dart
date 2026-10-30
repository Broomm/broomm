import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/macos_aes.dart';
import 'package:broomm/src/switch_content.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/managed_profile.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/ryubing.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/romm/models.dart';

Uint8List _hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);
void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('broomm-eden-'),
  );
  tearDown(() async => root.delete(recursive: true));
  test('Eden is a separate selectable Switch backend and preserves native renderer settings', () async {
    final choices = platformEmulators(
      const RommPlatform(30, 'Switch', 'switch', 1),
    );
    expect(choices.map((c) => c.emulator).toList(), [
      'Ryubing',
      'Eden',
      if (Platform.isMacOS) 'Astris',
    ]);
    final e = PreparedEmulator(
      'Eden',
      root.path,
      'unused',
      2,
      null,
      null,
      userDirectory: '${root.path}/data/eden',
    );
    final ini = File('${root.path}/config/eden/qt-config.ini');
    await ini.parent.create(recursive: true);
    await ini.writeAsString(
      '[Renderer]\nresolution_setup=5\nresolution_setup\\default=false\n',
    );
    final game = LaunchGame(
      '42',
      'Switch',
      'switch',
      'Eden',
      '/private/game.nsp',
      4,
      0,
      target: ControllerTarget.switchPro,
    );
    expect(await const EdenAdapter().prepare(e, game, game.rom, 0), [
      '-g',
      game.rom,
      '-u',
      '0',
    ]);
    final config = await ini.readAsString();
    expect(config, contains('resolution_setup=5'));
    expect(config, contains('guid:ff0000005669727475616c2043007601,port:3'));
    expect(config, contains('player_7_connected = false'));
    expect(config, contains('confirmStop = 2'));
  });
  test('Eden shares Switch native directory exports while retaining its own console account and excluding NAND content', () async {
    final b = TestedBuild({
      'id': 'eden',
      'name': 'Eden',
      'version': 'test',
      'host': 'macos-arm64',
      'bundle': 'eden.app',
      'executable': 'eden',
      'sha256': 'a' * 64,
      'sdl': 2,
      'native': <String, String>{},
    });
    final native = await prepareManagedProfile(
          root,
          'b' * 32,
          b,
          Directory('${root.path}/release'),
        ),
        e = PreparedEmulator(
          'Eden',
          native.path,
          'unused',
          2,
          null,
          null,
          userDirectory: '${native.path}/data/eden',
        ),
        rom = File('${root.path}/game.nsp');
    await rom.writeAsBytes([1, 2, 3]);
    final r = ResolvedSession(e, rom.path, 'a' * 64, {});
    await expectLater(
      gameProgressLayout(r, 'switch'),
      throwsA(isA<SwitchNeedsInitialization>()),
    );
    await recordRyubingGame(
      r,
      '01005d100807a000',
      (await switchSourceIdentity(r)).$1,
    );
    final account = File(
          '${e.user}/nand/system/save/8000000000000010/su/avators/profiles.dat',
        ),
        bytes = Uint8List(0x650);
    bytes[0x10] = 1;
    bytes[0x20] = 1;
    await account.parent.create(recursive: true);
    await account.writeAsBytes(bytes);
    final layout = await gameProgressLayout(r, 'switch');
    expect(layout.format, 'ryubing-directory-v1');
    expect(await Directory('${e.user}/nand/user/save/account').exists(), false);
    final save = await layout.target('save/game.dat');
    expect(
      save.path,
      contains('/00000000000000000000000000000001/01005D100807A000/'),
    );
    await save.writeAsBytes([9]);
    final content = File(
      '${e.user}/nand/user/Contents/registered/${'a' * 32}.nca',
    );
    await content.parent.create(recursive: true);
    await content.writeAsBytes([8]);
    final store = ProgressStore(
          Directory('${root.path}/snapshot'),
          layout,
          42,
          3,
        ),
        snapshot = await store.capture();
    expect(snapshot.entries.keys.toList(), ['save/game.dat']);
    final exported = await store.exportNative(snapshot);
    try {
      expect(
        (await store.importNative(exported.file)).ordinaryDigest,
        snapshot.ordinaryDigest,
      );
    } finally {
      await exported.close();
    }
    // Native migrations invalidate the old boundary; probing must neither
    // create a new save tree nor follow a linked future account directory.
    final future = Directory(
      '${e.user}/nand/user/save/account/${'01'.padRight(32, '0')}/01005D100807A000/0',
    );
    await future.create(recursive: true);
    await expectLater(layout.files(), throwsFormatException);
    final migrated = await gameProgressLayout(r, 'switch');
    expect((await migrated.target('save/game.dat')).parent.path, future.path);
    await future.delete(recursive: true);
    await Link(future.path).create(save.parent.path);
    await expectLater(
      gameProgressLayout(r, 'switch'),
      throwsA(isA<FileSystemException>()),
    );
    await Link(future.path).delete();
    bytes[0x10] = 2;
    bytes[0x20] = 2;
    await account.writeAsBytes(bytes);
    await expectLater(layout.files(), throwsFormatException);
  });
  test('Switch metadata rejects traversal, duplicate and overlapping PFS entries before extraction', () async {
    Uint8List archive(String names) {
      final encoded = names.codeUnits,
          b = Uint8List(16 + 48 + encoded.length + 32),
          d = ByteData.sublistView(b);
      b.setRange(0, 4, [80, 70, 83, 48]);
      d.setUint32(4, 2, Endian.little);
      d.setUint32(8, encoded.length, Endian.little);
      for (var i = 0; i < 2; i++) {
        d.setUint64(16 + i * 24, i * 16, Endian.little);
        d.setUint64(24 + i * 24, 16, Endian.little);
        d.setUint32(
          32 + i * 24,
          i == 0 ? 0 : names.indexOf('\x00') + 1,
          Endian.little,
        );
      }
      b.setRange(64, 64 + encoded.length, encoded);
      return b;
    }

    final f = File('${root.path}/test.nsp');
    await f.writeAsBytes(archive('../a\x00b\x00'));
    await expectLater(switchArchiveEntries(f), throwsFormatException);
    await f.writeAsBytes(archive('a\x00A\x00'));
    await expectLater(switchArchiveEntries(f), throwsFormatException);
    final overlap = archive('a\x00b\x00');
    ByteData.sublistView(overlap).setUint64(40, 1, Endian.little);
    await f.writeAsBytes(overlap);
    await expectLater(switchArchiveEntries(f), throwsFormatException);
  });
  test(
    'native macOS AES matches the NIST ECB vector; XTS round trips keep Nintendo sector identities separate',
    () {
      final key = _hex('000102030405060708090a0b0c0d0e0f'),
          plain = _hex('00112233445566778899aabbccddeeff'),
          cipher = _hex('69c4e0d86a7b0430d8cdb78070b4c55a');
      expect(macosAesEcb(plain, key, decrypt: false), cipher);
      expect(macosAesEcb(cipher, key, decrypt: true), plain);
      final xts = Uint8List.fromList([...key, ...key.reversed]),
          sector = Uint8List.fromList(List.generate(512, (i) => i & 255)),
          encrypted = switchXtsSector(sector, xts, 1, decrypt: false);
      expect(switchXtsSector(encrypted, xts, 1), sector);
      expect(switchXtsSector(encrypted, xts, 2), isNot(sector));
    },
    skip: !Platform.isMacOS
        ? 'macOS crypto adapter; other hosts require their own native package'
        : false,
  );
}
