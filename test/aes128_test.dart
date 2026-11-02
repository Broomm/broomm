import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:broomm/src/aes128.dart';
import 'package:broomm/src/macos_aes.dart';
import 'package:broomm/src/switch_content.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List hex(String text) => Uint8List.fromList([
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
]);
void main() {
  test('FIPS 197 and SP 800-38A multi-block AES vectors encrypt and decrypt independently', () {
    final key = hex('2b7e151628aed2a6abf7158809cf4f3c');
    final plain = hex(
      '6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710',
    );
    final cipher = hex(
      '3ad77bb40d7a3660a89ecaf32466ef97'
      'f5d3d58503b9699de785895a96fdbaaf'
      '43b1cd7f598ece23881b00e3ed030688'
      '7b0c785e27e8ad3f8223207104725dd4',
    );
    expect(aes128Ecb(plain, key, decrypt: false), cipher);
    expect(aes128Ecb(cipher, key, decrypt: true), plain);
    expect(
      aes128Ecb(
        hex('00112233445566778899aabbccddeeff'),
        hex('000102030405060708090a0b0c0d0e0f'),
        decrypt: false,
      ),
      hex('69c4e0d86a7b0430d8cdb78070b4c55a'),
    );
  });
  test(
    'media AES rejects invalid boundaries and XTS preserves sector identity',
    () {
      final key = Uint8List(16),
          data = Uint8List.fromList(List.generate(512, (i) => i & 255));
      for (final size in [0, 15, 17, 65552]) {
        expect(
          () => aes128Ecb(Uint8List(size), key, decrypt: true),
          throwsFormatException,
        );
      }
      expect(
        () => aes128Ecb(data, Uint8List(32), decrypt: false),
        throwsFormatException,
      );
      final xts = Uint8List.fromList(List.generate(32, (i) => i));
      final encrypted = switchXtsSector(data, xts, 1, decrypt: false);
      expect(switchXtsSector(encrypted, xts, 1), data);
      expect(switchXtsSector(encrypted, xts, 2), isNot(data));
    },
  );
  test(
    'Dart media AES matches independent Apple crypto at block and maximum bounds',
    () {
      final random = Random(42);
      for (final size in [16, 512, 65536]) {
        final key = Uint8List.fromList(
          List.generate(16, (_) => random.nextInt(256)),
        );
        final input = Uint8List.fromList(
          List.generate(size, (_) => random.nextInt(256)),
        );
        final encrypted = macosAesEcb(input, key, decrypt: false);
        expect(aes128Ecb(input, key, decrypt: false), encrypted);
        expect(aes128Ecb(encrypted, key, decrypt: true), input);
      }
    },
    skip: !Platform.isMacOS
        ? 'Independent Apple primitive comparison runs on macOS.'
        : false,
  );
}
