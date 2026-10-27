import 'dart:async';
import 'dart:io';

import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/setup/package.dart';
import 'package:flutter_test/flutter_test.dart';

// Only the transport endpoint changes. Production URL/redirect validation still
// sees HTTPS provider URLs; actual byte streaming and socket cancellation run.
class _Transport implements HttpClient {
  _Transport(this.port, this.seen);
  final int port;
  final List<Uri> seen;
  final HttpClient inner = HttpClient();
  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    seen.add(url);
    return inner.getUrl(Uri.parse('http://127.0.0.1:$port${url.path}'));
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailedTransport extends _Transport {
  _FailedTransport(super.port, super.seen, this.error);
  final Object error;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => throw error;
}

void main() {
  late Directory root;
  late HttpServer server;
  late SetupDownloads downloads;
  late List<Uri> seen;
  late List<int> bytes;
  late String hash;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-setup-transfer-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    seen = [];
    downloads = SetupDownloads(
      root,
      client: () => _Transport(server.port, seen),
    );
    bytes = List.generate(32768, (i) => i % 251);
    final payload = await File('${root.path}/expected').writeAsBytes(bytes);
    hash = await progressFileHash(payload);
  });
  tearDown(() async {
    await server.close(force: true);
    await root.delete(recursive: true);
  });
  SetupPackage package() => SetupPackage.fromJson({
    'url': 'https://provider.example/fixture.zip',
    'sha256': hash,
    'bytes': bytes.length,
    'format': 'zip',
    'entry': 'Fixture.app',
  });
  void progress(String phase, double? fraction) {}

  test('exact HTTPS download is reusable across restart; altered cached bytes are preserved and fetched again', () async {
    server.listen((request) async {
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
    final file = await downloads.archive(
      package(),
      DownloadCancellation(),
      progress,
    );
    expect(await file.readAsBytes(), bytes);
    expect(seen, hasLength(1));
    final restarted = SetupDownloads(
      root,
      client: () => throw StateError('Cache should avoid networking'),
    );
    expect(
      (await restarted.archive(
        package(),
        DownloadCancellation(),
        progress,
      )).path,
      file.path,
    );
    final changed = [...bytes]..[0] = 255;
    await file.writeAsBytes(changed);
    final repaired = await downloads.archive(
      package(),
      DownloadCancellation(),
      progress,
    );
    expect(seen, hasLength(2));
    expect(repaired.path, isNot(file.path));
    expect(await file.readAsBytes(), changed);
    expect(await repaired.readAsBytes(), bytes);
  });

  test('truncation and wrong checksums never complete the cache; retry downloads cleanly', () async {
    var attempt = 0;
    server.listen((request) async {
      attempt++;
      final data = attempt == 1
          ? bytes.take(10).toList()
          : attempt == 2
          ? List<int>.filled(bytes.length, 0)
          : bytes;
      if (attempt == 1) {
        request.response.contentLength = bytes.length;
        final socket = await request.response.detachSocket(writeHeaders: true);
        socket.add(data);
        await socket.flush();
        socket.destroy();
        return;
      }
      request.response.contentLength = data.length;
      request.response.add(data);
      await request.response.close();
    });
    for (var i = 0; i < 2; i++) {
      await expectLater(
        downloads.archive(package(), DownloadCancellation(), progress),
        throwsStateError,
      );
      expect(await downloads.cache.list().toList(), isEmpty);
    }
    final complete = await downloads.archive(
      package(),
      DownloadCancellation(),
      progress,
    );
    expect(await progressFileHash(complete), hash);
  });
  test('transport failures never expose signed redirect URLs or private error details', () async {
    final secret = Uri.parse(
      'https://assets.example/a?token=private-value&signature=private-value',
    );
    for (final error in [
      HttpException('connection closed private-value', uri: secret),
      const HandshakeException('private-value'),
      TimeoutException('private-value'),
    ]) {
      final failing = SetupDownloads(
        root,
        client: () => _FailedTransport(server.port, seen, error),
      );
      Object? actual;
      try {
        await failing.archive(package(), DownloadCancellation(), progress);
      } catch (e) {
        actual = e;
      }
      expect(actual, isA<StateError>());
      expect('$actual', isNot(contains('private-value')));
      expect('$actual', isNot(contains('assets.example')));
      expect(await downloads.cache.list().toList(), isEmpty);
    }
  });

  test('cancel closes a held HTTP stream and preserves existing progress; retry is independent', () async {
    final started = Completer<void>(), release = Completer<void>();
    var attempt = 0;
    server.listen((request) async {
      try {
        request.response.contentLength = bytes.length;
        if (++attempt == 1) {
          request.response.add(bytes.take(1024).toList());
          await request.response.flush();
          started.complete();
          await release.future;
        } else {
          request.response.add(bytes);
        }
        await request.response.close();
      } catch (_) {
        /* Expected peer closure on Cancel. */
      }
    });
    final save = await File('${root.path}/progress.sav').writeAsString('keep');
    final cancellation = DownloadCancellation();
    final work = downloads.archive(package(), cancellation, progress);
    final assertion = expectLater(work, throwsA(isA<DownloadCancelled>()));
    await started.future;
    cancellation.cancel();
    await assertion;
    release.complete();
    expect(await downloads.cache.list().toList(), isEmpty);
    expect(await save.readAsString(), 'keep');
    expect(
      await progressFileHash(
        await downloads.archive(package(), DownloadCancellation(), progress),
      ),
      hash,
    );
  });

  test('unsafe redirect is rejected before a second request and credentials never enter a recipe', () async {
    var location = 'http://other.example/payload';
    server.listen((request) async {
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(HttpHeaders.locationHeader, location);
      await request.response.close();
    });
    await expectLater(
      downloads.archive(package(), DownloadCancellation(), progress),
      throwsFormatException,
    );
    expect(seen, hasLength(1));
    location = 'https://[broken]/file?token=private-value';
    await expectLater(
      downloads.archive(package(), DownloadCancellation(), progress),
      throwsA(
        isA<FormatException>().having(
          (e) => '$e',
          'safe diagnostic',
          isNot(contains('private-value')),
        ),
      ),
    );
    expect(seen, hasLength(2));
    for (final url in [
      'http://provider.example/a',
      'https://user:password@provider.example/a',
      'https://provider.example/a?token=secret',
    ]) {
      expect(
        () => SetupPackage.fromJson({
          'url': url,
          'sha256': hash,
          'bytes': 1,
          'format': 'zip',
          'entry': 'Safe.app',
        }),
        throwsFormatException,
      );
    }
    expect(await downloads.cache.list().toList(), isEmpty);
  });
}
