import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_download_test.dart' show fixture, serverId, bytes;

void main() {
  late Directory root;
  late HttpServer server;
  late RommClient client;
  late Future<void> Function(HttpRequest) serve;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-worker-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = RommClient(Uri.parse('http://127.0.0.1:${server.port}'));
    server.listen((r) async {
      try {
        if (r.uri.path == '/api/token') {
          r.response.headers.contentType = ContentType.json;
          r.response.write(
            jsonEncode({
              'access_token': 'fixture',
              'token_type': 'bearer',
              'expires': 900,
            }),
          );
        } else if (r.uri.path == '/api/users/me') {
          r.response.headers.contentType = ContentType.json;
          r.response.write(
            jsonEncode({'id': 1, 'username': 'fixture', 'enabled': true}),
          );
        } else {
          expect(
            r.headers.value(HttpHeaders.authorizationHeader),
            'Bearer fixture',
          );
          r.response.bufferOutput = false;
          await serve(r);
        }
        await r.response.close();
      } on IOException {
        /* Cancellation closes only the worker's connection. */
      }
    });
    await client.login('fixture', 'fixture');
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
    await root.delete(recursive: true);
  });
  Future<void> download(
    File file,
    int bytes, {
    int id = 1,
    DownloadCancellation? cancellation,
    void Function(int)? progress,
  }) => client.downloadFile(
    RommFile(
      id: id,
      romId: id,
      name: 'payload.bin',
      fullPath: 'payload.bin',
      bytes: bytes,
    ),
    file,
    cancellation: cancellation ?? DownloadCancellation(),
    onProgress: progress ?? (_) {},
  );

  test('default worker preserves fragmented bytes and closes before completion; truncated/oversized data fails', () async {
    final body = Uint8List.fromList(
      List.generate(1024 * 1024 + 137, (i) => i % 251),
    );
    serve = (r) async {
      for (var offset = 0; offset < body.length; offset += 1024) {
        r.response.add(
          body.sublist(offset, (offset + 1024).clamp(0, body.length)),
        );
        await r.response.flush();
      }
    };
    final file = File('${root.path}/payload');
    final progress = <int>[];
    await download(file, body.length, progress: progress.add);
    expect(await file.readAsBytes(), body);
    expect(progress.last, body.length);
    expect(progress, orderedEquals(progress.toList()..sort()));
    await file.rename('${root.path}/closed-file');
    for (final size in [4000, 10001]) {
      serve = (r) async {
        r.response.add(List.filled(size, 5));
      };
      await expectLater(
        download(File('${root.path}/bad-$size'), 10000),
        throwsA(isA<RommFailure>()),
      );
    }
  });
  test('cancelling a stalled worker drains it without cancelling another transfer on the same client', () async {
    final observed = Completer<void>(),
        release = Completer<void>(),
        done = Completer<void>();
    serve = (r) async {
      if (r.uri.path.contains('/roms/2/')) {
        r.response.add(bytes);
        return;
      }
      try {
        r.response.add(List.filled(16384, 7));
        await r.response.flush();
        await release.future;
      } finally {
        done.complete();
      }
    };
    final file = File('${root.path}/cancelled'),
        cancel = DownloadCancellation();
    final work = download(
      file,
      100000,
      cancellation: cancel,
      progress: (_) {
        if (!observed.isCompleted) observed.complete();
      },
    );
    final assertion = expectLater(work, throwsA(isA<DownloadCancelled>()));
    try {
      await observed.future;
      final other = File('${root.path}/other');
      final complete = download(other, bytes.length, id: 2);
      cancel.cancel();
      await assertion;
      await complete;
      expect(await other.readAsBytes(), bytes);
      final renamed = await file.rename('${root.path}/cancelled-closed');
      final size = await renamed.length();
      release.complete();
      await done.future;
      expect(await renamed.length(), size);
    } finally {
      if (!release.isCompleted) release.complete();
    }
  });
  test('closing the owning client drains its background writer', () async {
    final observed = Completer<void>(), release = Completer<void>();
    serve = (r) async {
      r.response.add(List.filled(16384, 1));
      await r.response.flush();
      await release.future;
    };
    final file = File('${root.path}/closed-owner');
    final work = download(
      file,
      100000,
      progress: (_) {
        if (!observed.isCompleted) observed.complete();
      },
    );
    final assertion = expectLater(work, throwsA(isA<DownloadCancelled>()));
    try {
      await observed.future;
      client.close();
      await assertion;
      await file.rename('${root.path}/writer-drained');
    } finally {
      release.complete();
    }
  });
  test('an unacknowledged writer retains its stage and cross-process lock until restart', () async {
    final data = Directory('${root.path}/data');
    final child = await Process.start('dart', [
      'test/support/uncertain_download.dart',
      data.path,
    ]);
    try {
      final ready = jsonDecode(
        await child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
      ) as Map;
      expect(ready['retained'], isTrue);
      expect(ready['retryBlocked'], isTrue);
      expect(ready['sessionBlocked'], isTrue);
      await expectLater(SessionLease.acquire(data), throwsStateError);
      await expectLater(
        GameLibrary(data).install(
          serverId: serverId,
          userId: 1,
          game: fixture(),
          client: client,
          cancellation: DownloadCancellation(),
          progress: (_) {},
          verifyChecksum: false,
        ),
        throwsA(isA<RommFailure>()),
      );
      final stages = await Directory('${data.path}/library/$serverId')
          .list()
          .where((e) => e is Directory)
          .toList();
      expect(stages, hasLength(1));
      expect(
        await File('${stages.single.path}/content/Game.iso').readAsString(),
        'retained partial',
      );
    } finally {
      child.stdin.writeln('exit');
      await child.stdin.close();
      expect(await child.exitCode, 0);
    }
    serve = (r) async {
      r.response.add(bytes);
    };
    final recovered = await SessionLease.acquire(data);
    await recovered.release();
    final installed = await GameLibrary(data).install(
      serverId: serverId,
      userId: 1,
      game: fixture(),
      client: client,
      cancellation: DownloadCancellation(),
      progress: (_) {},
      verifyChecksum: false,
    );
    expect(
      await File('${installed.directory.path}/content/Game.iso').readAsBytes(),
      bytes,
    );
  });
}
