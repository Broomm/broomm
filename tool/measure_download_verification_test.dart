import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:flutter_test/flutter_test.dart';

class MeasuredTransfer extends RommClient {
  MeasuredTransfer(this.payload) : super(Uri.parse('https://fixture.example'));
  final File payload;
  @override
  Future<void> downloadFile(
    RommFile file,
    File target, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    final sink = target.openWrite();
    await sink.addStream(payload.openRead());
    await sink.close();
    cancellation.check();
    onProgress(file.bytes);
  }
}

void main() {
  test('measure the production verification phase on a disposable 64 MiB transfer', () async {
    final evidence = Directory(
      '${Directory.current.path}/.tool-cache/research/downloads-status',
    );
    final data = await evidence.createTemp('verification-');
    final payload = File('${data.path}/source');
    final sink = payload.openWrite();
    for (var i = 0; i < 64; i++)
      sink.add(Uint8List(1024 * 1024)..fillRange(0, 1024 * 1024, 123));
    await sink.close();
    final bytes = await payload.length(),
        library = GameLibrary(data),
        client = MeasuredTransfer(payload);
    final results = <Map<String, Object>>[];
    try {
      var id = 0;
      for (final verify in [true, false, true]) {
        id++;
        final game = RommGame(
          id: id,
          name: 'Measured game',
          platformId: 1,
          platform: 'PS3',
          bytes: bytes,
          fsName: 'Game.iso',
          fullPath: 'roms/ps3/Game.iso',
          files: [
            RommFile(
              id: 1,
              romId: id,
              name: 'Game.iso',
              fullPath: 'roms/ps3/Game.iso',
              bytes: bytes,
            ),
          ],
        );
        final clock = Stopwatch()..start();
        int? started, finished;
        final installed = await library.install(
          serverId: '0123456789abcdef0123456789abcdef',
          userId: 1,
          game: game,
          client: client,
          cancellation: DownloadCancellation(),
          verifyChecksum: verify,
          progress: (p) {
            if (p.phase.startsWith('Verifying') ||
                p.phase.startsWith('Checking transfer'))
              started = clock.elapsedMicroseconds;
            if (p.phase == 'Finishing download')
              finished = clock.elapsedMicroseconds;
          },
        );
        expect((await library.contentFiles(installed)).length, 1);
        results.add({
          'checksum': verify,
          'bytes': bytes,
          'verificationUs': finished! - started!,
          'totalMs': clock.elapsedMilliseconds,
        });
      }
      await File('${evidence.path}/verification-timing.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'fixture': 'local stream copy, warm filesystem; not network throughput', 'results': results})}\n',
      );
      stdout.writeln(jsonEncode(results));
    } finally {
      client.close();
      await data.delete(recursive: true);
    }
  });
}
