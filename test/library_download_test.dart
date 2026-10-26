import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:flutter_test/flutter_test.dart';

const serverId = '0123456789abcdef0123456789abcdef';
const otherServerId = '1123456789abcdef0123456789abcdef';
const bytes = [49, 50, 51, 52, 53, 54, 55, 56, 57]; // CRC reference vector.
RommGame fixture({
  int id = 1,
  List<String> paths = const ['Game.iso'],
  String? crc = 'cbf43926',
  bool raw = true,
}) => RommGame(
  id: id,
  name: 'Game $id',
  platformId: 4,
  platform: 'GameCube',
  bytes: paths.length * bytes.length,
  fsName: paths.length == 1 ? paths.single : 'Game',
  fullPath: paths.length == 1 ? 'roms/ngc/${paths.single}' : 'roms/ngc/Game',
  files: List.generate(
    paths.length,
    (i) => RommFile(
      id: 10 + i,
      romId: id,
      name: paths[i].split('/').last,
      fullPath: paths.length == 1
          ? 'roms/ngc/${paths.single}'
          : 'roms/ngc/Game/${paths[i]}',
      bytes: bytes.length,
      crc: crc,
      rawCrc: raw,
    ),
  ),
);

void main() {
  late Directory root;
  late HttpServer server;
  late RommClient client;
  late GameLibrary library;
  late Future<void> Function(HttpRequest) serveFile;
  final requests = <Uri>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-download-');
    library = GameLibrary(root);
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = RommClient(Uri.parse('http://127.0.0.1:${server.port}/base'));
    serveFile = (r) async {
      r.response.add(bytes);
      await r.response.close();
    };
    server.listen((r) async {
      try {
        if (r.uri.path == '/base/api/token') {
          r.response.headers.contentType = ContentType.json;
          r.response.write(
            jsonEncode({
              'access_token': 'fixture-secret',
              'token_type': 'bearer',
              'expires': 900,
            }),
          );
          await r.response.close();
        } else if (r.uri.path == '/base/api/users/me') {
          r.response.headers.contentType = ContentType.json;
          r.response.write(
            jsonEncode({'id': 7, 'username': 'Player', 'enabled': true}),
          );
          await r.response.close();
        } else {
          requests.add(r.uri);
          expect(
            r.headers.value(HttpHeaders.authorizationHeader),
            'Bearer fixture-secret',
          );
          await serveFile(r);
        }
      } on IOException {
        /* Client cancellation may close the test response. */
      }
    });
    await client.login('Player', 'fixture-only');
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
    await root.delete(recursive: true);
  });
  Future<InstalledGame> install(
    RommGame game, {
    DownloadCancellation? cancel,
    void Function(DownloadProgress)? progress,
    bool verifyChecksum = true,
  }) => library.install(
    serverId: serverId,
    userId: 7,
    game: game,
    client: client,
    cancellation: cancel ?? DownloadCancellation(),
    progress: progress ?? (_) {},
    verifyChecksum: verifyChecksum,
  );

  test('real HTTP single and nested multi-file downloads publish shared durable Home records only after verification', () async {
    expect((await library.load(serverId)).games, isEmpty);
    final game = fixture(paths: ['disc.cue', 'tracks/disc.bin']);
    final phases = <String>[];
    final result = await install(game, progress: (p) => phases.add(p.phase));
    expect(requests.map((r) => r.path), [
      '/base/api/roms/10/files/content/disc.cue',
      '/base/api/roms/11/files/content/disc.bin',
    ]);
    expect(
      await File('${result.directory.path}/content/tracks/disc.bin')
          .readAsBytes(),
      bytes,
    );
    expect(phases, contains('Verifying file 2 of 2'));
    final restarted = await GameLibrary(root).load(serverId);
    expect(restarted.games.single.game.name, game.name);
    expect(restarted.games.single.problem, isNull);
    expect((await library.load(otherServerId)).games, isEmpty);
    await expectLater(install(game), throwsA(isA<RommFailure>()));
    expect(
      await File('${result.directory.path}/content/disc.cue').readAsBytes(),
      bytes,
    );
    final single = await install(fixture(id: 2));
    expect(
      await File('${single.directory.path}/content/Game.iso').readAsBytes(),
      bytes,
    );
  });

  test('cancellation and a concurrent installer cannot expose a partial Home entry; retry starts cleanly', () async {
    final cancel = DownloadCancellation(),
        started = Completer<void>(),
        release = Completer<void>();
    serveFile = (r) async {
      r.response.add(bytes.take(2).toList());
      await r.response.flush();
      started.complete();
      await release.future;
      await r.response.close();
    };
    final pending = install(fixture(), cancel: cancel);
    await started.future;
    await expectLater(
      GameLibrary(root).install(
        serverId: serverId,
        userId: 8,
        game: fixture(),
        client: client,
        cancellation: DownloadCancellation(),
        progress: (_) {},
      ),
      throwsA(isA<RommFailure>()),
    );
    cancel.cancel();
    release.complete();
    await expectLater(pending, throwsA(isA<DownloadCancelled>()));
    expect((await library.load(serverId)).games, isEmpty);
    serveFile = (r) async {
      r.response.add(bytes);
      await r.response.close();
    };
    await install(fixture());
    expect((await library.load(serverId)).games.length, 1);
  });

  test('truncated, oversized and corrupt responses preserve complete games and allow a later retry', () async {
    final first = await install(fixture());
    for (final body in [
      bytes.take(2).toList(),
      [...bytes, 0],
      List<int>.filled(9, 0),
    ]) {
      serveFile = (r) async {
        r.response.add(body);
        await r.response.close();
      };
      await expectLater(install(fixture(id: 2)), throwsA(isA<RommFailure>()));
      expect((await library.load(serverId)).games.map((g) => g.game.id), [1]);
    }
    expect(
      await File('${first.directory.path}/content/Game.iso').readAsBytes(),
      bytes,
    );
    serveFile = (r) async {
      r.response.add(bytes);
      await r.response.close();
    };
    await install(fixture(id: 2));
    expect((await library.load(serverId)).games.length, 2);
  });

  test('unsafe, colliding and wrong-owner manifests are rejected before any file request', () async {
    for (final paths in [
      ['good.bin', '../escape.bin'],
      ['Disc.bin', 'disc.bin'],
      ['a', 'a/b'],
      ['safe', 'C:/bad.bin'],
      ['good', 'nested/../bad'],
      ['good', 'NUL.bin'],
      ['good', 'trailing.'],
    ]) {
      await expectLater(
        install(fixture(paths: paths)),
        throwsA(isA<RommFailure>()),
      );
    }
    final game = fixture();
    final wrongOwner = RommGame(
      id: 2,
      name: 'Wrong',
      platformId: 4,
      platform: 'GC',
      fullPath: game.fullPath,
      files: game.files,
    );
    await expectLater(install(wrongOwner), throwsA(isA<RommFailure>()));
    expect(requests, isEmpty);
    expect((await library.load(serverId)).games, isEmpty);
  });

  test('redirects and authorization failures do not publish content or forward credentials', () async {
    for (final status in [302, 401, 403]) {
      serveFile = (r) async {
        r.response.statusCode = status;
        r.response.headers.set(
          'location',
          'http://127.0.0.1:${server.port}/unexpected',
        );
        await r.response.close();
      };
      await expectLater(
        install(fixture()),
        throwsA(isA<RommFailure>().having((e) => e.status, 'status', status)),
      );
      expect((await library.load(serverId)).games, isEmpty);
    }
    expect(requests.every((r) => !r.path.contains('unexpected')), true);
  });

  test('archive hashes are not compared to container bytes; damaged or unreadable records remain visible as problems', () async {
    final result = await install(
      fixture(paths: ['Game.zip'], crc: '00000000', raw: false),
    );
    await File('${result.directory.path}/content/Game.zip').delete();
    var snapshot = await library.load(serverId);
    expect(snapshot.games.single.problem, isNotNull);
    await File('${result.directory.path}/receipt.json').writeAsString('{bad');
    snapshot = await library.load(serverId);
    expect(snapshot.problem, isNotNull);
    expect(await result.directory.exists(), true);
    // RomM MIME detection can expand a container with an unexpected suffix.
    serveFile = (r) async {
      r.response.add([0x50, 0x4b, 3, 4, 0, 0, 0, 0, 0]);
      await r.response.close();
    };
    await install(fixture(id: 2, paths: ['unknown.rom'], crc: '00000000'));
    expect((await library.load(serverId)).games.single.game.id, 2);
  });

  test('stalled headers and stalled bodies time out without publishing partial files', () async {
    final base = client.server;
    client.close();
    client = RommClient(base, deadline: const Duration(milliseconds: 200));
    await client.login('Player', 'fixture-only');
    for (final bodyStarted in [false, true]) {
      final started = Completer<void>(), release = Completer<void>();
      serveFile = (r) async {
        if (bodyStarted) {
          r.response.add(bytes.take(2).toList());
          await r.response.flush();
        }
        started.complete();
        await release.future;
        await r.response.close();
      };
      final pending = install(fixture());
      await started.future;
      try {
        await expectLater(pending, throwsA(isA<RommFailure>()));
      } finally {
        release.complete();
      }
      expect((await library.load(serverId)).games, isEmpty);
    }
  });

  test(
    'linked library roots cannot redirect downloads outside Broomm storage',
    () async {
      if (Platform.isWindows)
        return; // Windows link permissions require its native runner.
      final outside = await Directory.systemTemp.createTemp(
        'broomm-untouched-',
      );
      try {
        await Link('${root.path}/library').create(outside.path);
        await expectLater(
          install(fixture()),
          throwsA(isA<FileSystemException>()),
        );
        expect(await outside.list().toList(), isEmpty);
      } finally {
        await outside.delete(recursive: true);
      }
    },
  );

  test('an independent process lock excludes publication, and abandoned staging is cleaned only after lock release', () async {
    await library.load(serverId);
    final staging = Directory(
      '${root.path}/library/$serverId/.partial-1-interrupted',
    );
    await staging.create();
    final otherStage = await Directory(
      '${root.path}/library/$serverId/.partial-2-active',
    ).create();
    final otherFile = await File('${otherStage.path}/partial.bin')
        .writeAsString('another game');
    await File('${staging.path}/partial.bin').writeAsString('unfinished');
    final child = await Process.start('dart', [
      'test/support/hold_library_lock.dart',
      '${root.path}/library/downloads.lock',
    ]);
    try {
      expect(
        await child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'held',
      );
      await expectLater(install(fixture()), throwsA(isA<RommFailure>()));
      expect(await staging.exists(), true);
    } finally {
      child.stdin.writeln('release');
      await child.stdin.close();
      expect(await child.exitCode, 0);
    }
    await install(fixture());
    expect(await staging.exists(), false);
    expect(await otherFile.readAsString(), 'another game');
    expect((await library.load(serverId)).games.length, 1);
  });

  test('size-only verification avoids the second payload scan but never accepts a truncated transfer', () async {
    final phases = <String>[];
    final result = await install(
      fixture(crc: '00000000'),
      verifyChecksum: false,
      progress: (p) => phases.add(p.phase),
    );
    final receipt = jsonDecode(
      await File('${result.directory.path}/receipt.json').readAsString(),
    ) as Map;
    expect((receipt['files'] as List).single['verification'], 'transfer-size');
    expect((receipt['files'] as List).single.containsKey('crc32'), false);
    expect(phases.any((p) => p.startsWith('Verifying')), false);
    expect(
      await File((await library.contentFiles(result)).single).readAsBytes(),
      bytes,
    );
    serveFile = (r) async {
      r.response.add(bytes.take(2).toList());
      await r.response.close();
    };
    await expectLater(
      install(fixture(id: 2), verifyChecksum: false),
      throwsA(isA<RommFailure>()),
    );
    expect((await library.load(serverId)).games.map((g) => g.game.id), [1]);
  });

  test('model download receipts survive restart and are reused by another authorized profile on that server', () async {
    final storage = ShellStorage(root);
    final saved = (await storage.saveServer(
      Uri.parse('https://fixture.example'),
      '5.4.0',
    )).servers.single;
    final models = <ShellModel>[];
    final clients = <_ModelClient>[];
    try {
      final model = ShellModel(
        storage,
        clientFactory: (uri) {
          final client = _ModelClient(uri);
          clients.add(client);
          return client;
        },
      );
      models.add(model);
      await model.start();
      await model.chooseServer(saved);
      await model.login('One', 'password');
      await model.downloadGame(fixture());
      expect(model.downloadError, isNull);
      expect(model.installed.single.game.id, 1);
      final path = model.installed.single.directory.path;
      model.switchAccount();
      await model.login('Two', 'password');
      expect(model.installed.single.directory.uri, Directory(path).uri);
      await model.downloadGame(fixture());
      expect(clients.fold<int>(0, (n, c) => n + c.transfers), 1);
      final restarted = ShellModel(
        storage,
        clientFactory: (_) =>
            _ModelClient(Uri.parse('https://fixture.example')),
      );
      models.add(restarted);
      await restarted.start();
      await restarted.chooseServer(saved);
      await restarted.login('One', 'password');
      expect(restarted.installed.single.directory.uri, Directory(path).uri);
      (model.client! as _ModelClient).deny = true;
      await model.loadLibrary();
      expect(model.installed, isEmpty);
      expect(model.libraryError, isNotNull);
      expect(await Directory(path).exists(), true);
    } finally {
      for (final model in models) {
        model.dispose();
      }
    }
  });

  test('signing out cancels a pending transfer and late completion cannot enter another server library', () async {
    final model = ShellModel(
      ShellStorage(root),
      clientFactory: _ModelClient.new,
    );
    try {
      await model.start();
      await model.addServer('https://first.example');
      await model.login('One', 'password');
      final connection = model.client! as _ModelClient;
      connection.started = Completer<void>();
      connection.release = Completer<void>();
      final pending = model.downloadGame(fixture());
      await connection.started!.future;
      model.switchAccount();
      connection.release!.complete();
      await pending;
      await model.addServer('https://second.example');
      await model.login('Two', 'password');
      expect(model.installed, isEmpty);
      expect(model.download, isNull);
      expect(model.downloadError, isNull);
      for (final selected in model.records.servers) {
        expect((await model.library.load(selected.id)).games, isEmpty);
      }
    } finally {
      await model.finishDownloads();
      model.dispose();
    }
  });
}

class _ModelClient extends RommClient {
  _ModelClient(super.server);
  int transfers = 0;
  bool deny = false;
  Completer<void>? started, release;
  @override
  Future<String> checkServer() async => '5.4.0';
  @override
  Future<RommUser> login(String username, String password) async =>
      RommUser(username == 'One' ? 1 : 2, username);
  @override
  Future<List<RommPlatform>> platforms() async => [];
  @override
  Future<RommPage> games({
    String search = '',
    int? platform,
    int offset = 0,
    int limit = 24,
    bool recent = false,
  }) async => const RommPage([], 0, 0, 24);
  @override
  Future<RommGame> game(int id) async {
    if (deny) throw const RommFailure('Forbidden', status: 403);
    return fixture(id: id);
  }

  @override
  Future<void> downloadFile(
    RommFile file,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    transfers++;
    if (started != null) {
      started!.complete();
      await release!.future;
    }
    cancellation.check();
    await destination.writeAsBytes(bytes, flush: true);
    onProgress(bytes.length);
  }
}
