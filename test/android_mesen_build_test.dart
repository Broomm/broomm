import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../tool/android/build_mesen.dart';

void main() {
  final archive = File('$mesenVendor/source.tar.gz');
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('broomm-mesen-build-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test(
    'fixed source extracts completely without changing its archive',
    () async {
      final before = await archive.readAsBytes();
      final source = await prepareMesenSource(
        archive,
        Directory('${temporary.path}/source'),
      );
      final manifest = await mesenSourceManifest(source);
      expect(manifest, contains('Libretro/jni/Android.mk'));
      expect(manifest, contains('Core/Console.cpp'));
      expect(
        await File('${source.path}/LICENSE').readAsString(),
        contains('GNU'),
      );
      expect(await archive.readAsBytes(), before);
    },
  );

  test(
    'changed source and existing staging are refused before writes',
    () async {
      final changed = File('${temporary.path}/changed.tar.gz');
      final bytes = await archive.readAsBytes();
      bytes[bytes.length ~/ 2] ^= 1;
      await changed.writeAsBytes(bytes);
      final stage = Directory('${temporary.path}/stage');
      await expectLater(
        prepareMesenSource(changed, stage),
        throwsFormatException,
      );
      expect(stage.existsSync(), false);
      await stage.create();
      await File('${stage.path}/owner').writeAsString('preserve');
      await expectLater(prepareMesenSource(archive, stage), throwsStateError);
      expect(await File('${stage.path}/owner').readAsString(), 'preserve');
    },
  );

  test('output accepts only the selected shared-library ABI', () {
    final elf = Uint8List(20);
    elf.setRange(0, 6, [127, 69, 76, 70, 2, 1]);
    final data = ByteData.sublistView(elf);
    data.setUint16(16, 3, Endian.little);
    data.setUint16(18, 183, Endian.little);
    validateMesenElf(elf, 'arm64-v8a');
    expect(() => validateMesenElf(elf, 'x86_64'), throwsFormatException);
    data.setUint16(16, 2, Endian.little);
    expect(() => validateMesenElf(elf, 'arm64-v8a'), throwsFormatException);
    expect(
      () => validateMesenElf(Uint8List(19), 'arm64-v8a'),
      throwsFormatException,
    );
  });
}
