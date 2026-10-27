import 'dart:io';

import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/file_hash.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('broomm-hash-'),
  );
  tearDown(() async => root.delete(recursive: true));
  test('native or SDK worker matches SHA-256 vectors and streaming boundaries without changing the input', () async {
    final file = File('${root.path}/file with [literal] characters');
    for (final bytes in [
      <int>[],
      [97, 98, 99],
      List.generate(131089, (i) => i % 251),
    ]) {
      await file.writeAsBytes(bytes);
      final before = await file.stat();
      final reference = ProgressDigest.sha256()..add(bytes);
      expect(await gameFileHash(file.path), reference.finish());
      final after = await file.stat();
      expect(after.modified, before.modified);
      expect(after.size, bytes.length);
    }
  });
  test('cancelling after real read progress never publishes a digest; the input and next check remain usable', () async {
    final file = File('${root.path}/large');
    final output = await file.open(mode: FileMode.write);
    final chunk = List<int>.filled(1048576, 42);
    for (var i = 0; i < 64; i++) await output.writeFrom(chunk);
    await output.close();
    final token = DownloadCancellation();
    var entered = false;
    await expectLater(
      gameFileHash(
        file.path,
        cancellation: token,
        progress: (bytes) {
          // The worker sends an initial ready checkpoint before hashing. Cancellation
          // is deterministic even on hosts that finish this fixture in <150 ms.
          entered = true;
          token.cancel();
        },
      ),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(entered, true);
    expect(await file.length(), 64 * 1048576);
    await file.writeAsString('abc');
    expect(
      await gameFileHash(file.path),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
  test('cancelled requests do no file IO; a missing input reports a file failure instead of leaving a worker busy', () async {
    final file = File('${root.path}/missing');
    final token = DownloadCancellation()..cancel();
    await expectLater(
      gameFileHash(file.path, cancellation: token),
      throwsA(isA<DownloadCancelled>()),
    );
    await expectLater(
      gameFileHash(file.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.exists(), false);
  });
}
