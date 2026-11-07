import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_artwork_library_test.dart' show ArtworkFiles;
import 'library_download_test.dart' show fixture;
import 'remembered_signin_test.dart' show MemoryCredentials;

void main() {
  late Directory data;
  late HttpServer server;
  late ShellModel model;
  late MemoryCredentials credentials;
  var unavailable = false, reject = false, loseIdentity = false;
  var revision = 0, user = 7;
  final denied = <int>{};
  final requests = <String>[];
  late String refresh;

  ShellModel create() => ShellModel(
    ShellStorage(data),
    credentials: credentials,
    clientFactory: (uri) =>
        RommClient(uri, deadline: const Duration(milliseconds: 500)),
  );
  Future<void> drop(HttpRequest request) async =>
      (await request.response.detachSocket(writeHeaders: false)).destroy();
  Future<void> reply(
    HttpRequest request,
    Object value, [
    int status = 200,
  ]) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(value));
    await request.response.close();
  }

  Future<void> restart() async {
    final saved = model.server!;
    model.dispose();
    model = create();
    await model.start();
    await model.chooseServer(saved);
  }

  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-offline-profile-');
    credentials = MemoryCredentials();
    unavailable = reject = loseIdentity = false;
    revision = 0;
    user = 7;
    refresh = 'refresh-0';
    denied.clear();
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        requests.add(request.uri.path);
        if (unavailable) {
          await drop(request);
          return;
        }
        switch (request.uri.path) {
          case '/api/heartbeat':
            await reply(request, {
              'SYSTEM': {'VERSION': '5.4.0'},
            });
          case '/api/token':
            final form = Uri.splitQueryString(
              await utf8.decoder.bind(request).join(),
            );
            if (reject ||
                form['grant_type'] == 'refresh_token' &&
                    form['refresh_token'] != refresh) {
              await reply(request, {}, 401);
            } else {
              refresh = 'refresh-${++revision}';
              await reply(request, {
                'access_token': 'access-$revision',
                'token_type': 'bearer',
                'refresh_token': refresh,
                'expires': 900,
              });
            }
          case '/api/users/me':
            if (loseIdentity) {
              await drop(request);
            } else {
              await reply(request, {'id': user, 'username': 'Player $user'});
            }
          case '/api/platforms':
            await reply(request, []);
          case '/api/roms':
            await reply(request, {
              'items': [],
              'offset': 0,
              'limit': 24,
              'total': 0,
            });
          default:
            final id = int.tryParse(request.uri.path.split('/').last);
            if (id == null) {
              await reply(request, {}, 404);
            } else if (denied.contains(id)) {
              await reply(request, {}, 403);
            } else {
              await reply(request, {
                'id': id,
                'name': 'Game $id',
                'platform_id': 4,
                'platform_slug': 'ngc',
              });
            }
        }
      } on IOException {
        /* Deliberate connection loss is a test boundary. */
      }
    });
    model = create();
    await model.start();
    await model.addServer('http://127.0.0.1:${server.port}', allowHttp: true);
    expect(await model.login('Player', 'test-only'), true);
    final files = ArtworkFiles();
    try {
      for (final owner in [7, 8]) {
        await model.library.install(
          serverId: model.server!.id,
          userId: owner,
          game: fixture(id: owner),
          client: files,
          cancellation: DownloadCancellation(),
          progress: (_) {},
        );
      }
    } finally {
      files.close();
    }
    await model.loadLibrary();
  });
  tearDown(() async {
    model.dispose();
    await server.close(force: true);
    await data.delete(recursive: true);
  });

  test('offline restart opens an explicit known profile and retains verified shared-game access', () async {
    final profile = model.profile!;
    final progress = File('${data.path}/profiles/${profile.id}/kept-progress');
    await progress.writeAsString('pending save');
    unavailable = true;
    await restart();
    expect(model.profile, isNull);
    expect(await model.activateProfile(profile), true);
    expect(model.offline, true);
    expect(model.installed.map((e) => e.game.id).toSet(), {7, 8});
    await model.ensureGameAccess(8);
    expect(await progress.readAsString(), 'pending save');
    unavailable = false;
    await model.reconnectProfile();
    expect(model.offline, false);
    expect(model.profile!.id, profile.id);
    expect(jsonDecode(credentials.values[profile.id]!)['secret'], refresh);
  });

  test('online denials remain denied offline and explicit sign-out removes deferred credentials', () async {
    final profile = model.profile!;
    denied.add(8);
    await model.loadLibrary();
    expect(model.installed.map((e) => e.game.id), [7]);
    unavailable = true;
    await restart();
    expect(await model.activateProfile(profile), true);
    expect(model.installed.map((e) => e.game.id), [7]);
    await model.signOut();
    expect(credentials.values.containsKey(profile.id), false);
    expect(await model.activateProfile(profile), false);
  });

  test(
    'a revoked sign-in never becomes offline authorization after restart',
    () async {
      final profile = model.profile!;
      reject = true;
      await restart();
      expect(await model.activateProfile(profile), false);
      unavailable = true;
      await restart();
      expect(await model.activateProfile(profile), isNull);
      expect(model.profile, isNull);
      expect(
        await model.storage
            .profileAccess(model.server!, profile)
            .then((v) => v.rejected),
        true,
      );
    },
  );

  test('rotation is saved before a lost identity response and identity mismatch cannot reconnect', () async {
    final profile = model.profile!;
    loseIdentity = true;
    await restart();
    expect(await model.activateProfile(profile), true);
    expect(model.offline, true);
    expect(jsonDecode(credentials.values[profile.id]!)['secret'], refresh);
    loseIdentity = false;
    user = 8;
    await model.reconnectProfile();
    expect(model.offline, true);
    expect(model.installed, isEmpty);
    expect(
      (await model.storage.profileAccess(model.server!, profile)).rejected,
      true,
    );
    expect(model.profile!.userId, 7);
  });
}
