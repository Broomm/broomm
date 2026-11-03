import 'dart:io';

import 'package:broomm/src/addons/verification.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('broomm-content-receipt-'),
  );
  tearDown(() => root.delete(recursive: true));
  test('verified copies and directory publication retain receipts across restart; later writes are freshly inspected', () async {
    final cache = AddonVerification(root, 'eden');
    final source = await File('${root.path}/source')
        .writeAsString('native content');
    final hash = await progressFileHash(source);
    final stage = await Directory('${root.path}/stage').create();
    await cache.remember(source, hash);
    await cache.copy(source.path, '${stage.path}/ready', hash);
    await stage.rename('${root.path}/transaction');
    await cache.relocated(stage.absolute.path, '${root.path}/transaction');
    await cache.rename(
      '${root.path}/transaction/ready',
      '${root.path}/installed',
      hash,
    );
    final restarted = AddonVerification(root, 'eden');
    expect(await restarted.fingerprint('${root.path}/installed'), hash);
    await File('${root.path}/installed').writeAsString('different bytes');
    expect(await restarted.fingerprint('${root.path}/installed'), isNot(hash));
    await expectLater(
      restarted.copy('${root.path}/installed', '${root.path}/refused', hash),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File('${root.path}/refused').exists(), isFalse);
  });
  test('equal timestamps and sizes on different paths never share a verification receipt', () async {
    final a = await File('${root.path}/a').writeAsString('AAAA');
    final b = await File('${root.path}/b').writeAsString('BBBB');
    final time = DateTime.utc(2020);
    await a.setLastModified(time);
    await b.setLastModified(time);
    final cache = AddonVerification(root, 'eden');
    await cache.remember(a, await progressFileHash(a));
    expect(await cache.fingerprint(b.path), await progressFileHash(b));
    expect(
      await cache.fingerprint(a.path),
      isNot(await cache.fingerprint(b.path)),
    );
  });
  test(
    'missing files and linked replacements cannot reuse verified content',
    () async {
      final a = await File('${root.path}/file').writeAsString('content');
      final cache = AddonVerification(root, 'eden');
      await cache.fingerprint(a.path);
      await a.delete();
      expect(await cache.fingerprint(a.path), isNull);
      if (!Platform.isWindows) {
        final b = await File('${root.path}/outside').writeAsString('content');
        await Link(a.path).create(b.path);
        await expectLater(
          cache.fingerprint(a.path),
          throwsA(isA<FileSystemException>()),
        );
      }
    },
  );
}
