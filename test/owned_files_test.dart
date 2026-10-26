import 'dart:io';

import 'package:broomm/src/addons/files.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root, source;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-owned-files-');
    source = await Directory('${root.path}/source').create();
    await Directory('${source.path}/nested folder').create();
    await File('${source.path}/nested folder/content.bin').writeAsString('abc');
    await File('${source.path}/empty').writeAsBytes([]);
  });
  tearDown(() => root.delete(recursive: true));

  test('native inventories and copies retain portable identities and exact bytes, including a trailing source separator', () async {
    const expected = {
      'empty':
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      'nested folder/content.bin':
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    };
    expect(await addonInventory(Directory('${source.path}/')), expected);
    final target = Directory('${root.path}/copy');
    await copyTree('${source.path}/', target.path, DownloadCancellation());
    expect(await addonInventory(target), expected);
    expect(
      await File('${target.path}/nested folder/content.bin').readAsString(),
      'abc',
    );
    // Stored/API paths remain strict; only native enumeration is normalized.
    expect(
      () => addonRelative(r'nested folder\content.bin'),
      throwsFormatException,
    );
    expect(() => addonRelative('../foreign'), throwsFormatException);
  });

  test('copy refuses an existing destination and cancellation leaves source and destination untouched', () async {
    final target = File('${root.path}/existing');
    await target.writeAsString('foreign data');
    await expectLater(
      copyTree(source.path, target.path, DownloadCancellation()),
      throwsStateError,
    );
    expect(await target.readAsString(), 'foreign data');
    final cancellation = DownloadCancellation()..cancel();
    final cancelled = '${root.path}/cancelled';
    await expectLater(
      copyTree(source.path, cancelled, cancellation),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(await Directory(cancelled).exists(), false);
    expect(
      await File('${source.path}/nested folder/content.bin').readAsString(),
      'abc',
    );
  });

  test(
    'linked input is never inventoried or copied into an ordinary owned tree',
    () async {
      final foreign = File('${root.path}/foreign');
      await foreign.writeAsString('keep');
      await Link('${source.path}/linked').create(foreign.path);
      await expectLater(
        addonInventory(source),
        throwsA(isA<FileSystemException>()),
      );
      final target = '${root.path}/copy';
      await expectLater(
        copyTree(source.path, target, DownloadCancellation()),
        throwsStateError,
      );
      expect(await Directory(target).exists(), false);
      expect(await foreign.readAsString(), 'keep');
    },
  );
}
