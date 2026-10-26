import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/credential.dart';

Map<String, dynamic> romFixture(int id, {String? name}) => {
  'id': id,
  'name': name ?? 'Game $id',
  'platform_id': 4,
  'platform_display_name': 'Nintendo GameCube',
  'fs_name': 'game.iso',
  'fs_size_bytes': 1024,
  'metadatum': {
    'genres': ['Adventure'],
    'first_release_date': 1000000000,
    'average_rating': 82.5,
  },
  'path_cover_large': '/assets/romm/cover.webp',
  'merged_screenshots': [],
};

void main() {
  test('server addresses preserve prefixes and reject ambiguous credential destinations', () {
    expect(
      normalizeServer('romm.example.com/library/').toString(),
      'https://romm.example.com/library',
    );
    for (final address in [
      'ftp://server',
      'https://name:secret@server',
      'https://server?token=x',
      'https://server/#x',
      'https://server/a/%2e%2e',
      'https://server/a\\b',
      'https://server/\u0000',
    ]) {
      expect(
        () => normalizeServer(address),
        throwsA(isA<RommFailure>()),
        reason: address,
      );
    }
  });
  late HttpServer server;
  late RommClient client;
  late Future<void> Function(HttpRequest) serve;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = RommClient(Uri.parse('http://127.0.0.1:${server.port}/romm'));
    serve = (r) async {
      r.response.statusCode = 404;
      await r.response.close();
    };
    server.listen((r) => serve(r));
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
  });
  Future<void> jsonResponse(
    HttpRequest r,
    Object value, {
    int status = 200,
  }) async {
    r.response.statusCode = status;
    r.response.headers.contentType = ContentType.json;
    r.response.write(jsonEncode(value));
    await r.response.close();
  }

  test('real HTTP login uses scoped form auth, stable user identity and paginated server filters', () async {
    final queries = <Uri>[];
    String? password;
    serve = (r) async {
      switch (r.uri.path) {
        case '/romm/api/heartbeat':
          await jsonResponse(r, {
            'SYSTEM': {'VERSION': '5.4.0'},
          });
        case '/romm/api/token':
          final form = Uri.splitQueryString(await utf8.decoder.bind(r).join());
          expect(form['grant_type'], 'password');
          expect(form['scope'], RommClient.scopes);
          expect(form['username'], 'player');
          password = form['password'];
          expect(
            r.headers.contentType!.mimeType,
            'application/x-www-form-urlencoded',
          );
          await jsonResponse(r, {
            'access_token': 'access-one',
            'token_type': 'bearer',
            'expires': 900,
            'refresh_token': 'refresh-one',
          });
        case '/romm/api/users/me':
          expect(r.headers.value('authorization'), 'Bearer access-one');
          await jsonResponse(r, {
            'id': 7,
            'username': 'player',
            'enabled': true,
          });
        case '/romm/api/roms':
          queries.add(r.uri);
          expect(r.headers.value('authorization'), 'Bearer access-one');
          await jsonResponse(r, {
            'items': [
              {
                ...romFixture(5),
                'sibling_roms': [
                  {
                    'id': 6,
                    'name': 'Game 5',
                    'fs_name_no_ext': 'Game 5 (Europe)',
                    'fs_name_no_tags': 'Game 5',
                    'is_main_sibling': false,
                  },
                ],
              },
            ],
            'total': 3,
            'offset': 1,
            'limit': 1,
          });
        default:
          await jsonResponse(r, {}, status: 404);
      }
    };
    expect(await client.checkServer(), '5.4.0');
    expect((await client.login('player', 'p&ss=word +')).id, 7);
    expect(password, 'p&ss=word +');
    final page = await client.games(
      search: 'Mario & Luigi',
      platform: 4,
      limit: 1,
      offset: 1,
    );
    expect(queries.single.queryParameters['search_term'], 'Mario & Luigi');
    expect(queries.single.queryParameters['platform_ids'], '4');
    expect(queries.single.queryParameters['group_by_meta_id'], 'true');
    expect(page.hasMore, true);
    expect(page.games.single.year, 2001);
    expect(page.games.single.name, 'Game 5');
    expect(page.games.single.versions.map((v) => v.id), [5, 6]);
    await client.games(recent: true, limit: 1, offset: 2);
    expect(queries.last.queryParameters['group_by_meta_id'], 'true');
    expect(queries.last.queryParameters['offset'], '2');
  });
  test(
    'expired sessions refresh once when concurrent reads need a token',
    () async {
      var refreshes = 0;
      final release = Completer<void>();
      serve = (r) async {
        if (r.uri.path.endsWith('/token')) {
          final form = Uri.splitQueryString(await utf8.decoder.bind(r).join());
          if (form['grant_type'] == 'refresh_token') {
            refreshes++;
            await release.future;
            await jsonResponse(r, {
              'access_token': 'new',
              'refresh_token': 'next',
              'token_type': 'bearer',
              'expires': 900,
            });
          } else {
            await jsonResponse(r, {
              'access_token': 'old',
              'refresh_token': 'refresh',
              'token_type': 'bearer',
              'expires': 900,
            });
          }
        } else if (r.uri.path.endsWith('/me')) {
          await jsonResponse(r, {
            'id': 7,
            'username': 'player',
            'enabled': true,
          });
        } else {
          expect(r.headers.value('authorization'), 'Bearer new');
          await jsonResponse(r, []);
        }
      };
      await client.login('player', 'pass');
      // Trigger expiry through the actual token response, rather than mutating client internals.
      client.close();
      client = RommClient(Uri.parse('http://127.0.0.1:${server.port}/romm'));
      var passwordGrant = true;
      final previous = serve;
      serve = (r) async {
        if (passwordGrant && r.uri.path.endsWith('/token')) {
          passwordGrant = false;
          await r.drain<void>();
          await jsonResponse(r, {
            'access_token': 'old',
            'refresh_token': 'refresh',
            'token_type': 'bearer',
            'expires': 1,
          });
        } else
          await previous(r);
      };
      final login = client.login('player', 'pass');
      // currentUser also requires the same refresh; release after its request is observed.
      while (refreshes == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final a = client.platforms(), b = client.platforms();
      release.complete();
      await login;
      await Future.wait([a, b]);
      expect(refreshes, 1);
    },
  );
  test('stored OAuth refresh tokens restore a new client and publish rotated credentials without another password', () async {
    var passwords = 0, refreshes = 0;
    final writes = <RommCredential>[];
    serve = (r) async {
      if (r.uri.path.endsWith('/token')) {
        final form = Uri.splitQueryString(await utf8.decoder.bind(r).join());
        if (form['grant_type'] == 'password') {
          passwords++;
        } else {
          refreshes++;
          expect(form['refresh_token'], 'refresh-original');
          expect(form.containsKey('password'), false);
        }
        await jsonResponse(r, {
          'access_token': refreshes == 0
              ? 'access-original'
              : 'access-restored',
          'refresh_token': refreshes == 0
              ? 'refresh-original'
              : 'refresh-rotated',
          'token_type': 'bearer',
          'expires': 900,
        });
      } else {
        expect(
          r.headers.value('authorization'),
          'Bearer ${refreshes == 0 ? 'access-original' : 'access-restored'}',
        );
        await jsonResponse(r, {'id': 7, 'username': 'player', 'enabled': true});
      }
    };
    await client.login('player', 'fixture-password');
    final saved = client.credential!;
    expect(saved.kind, 'refresh');
    expect(saved.secret, 'refresh-original');
    expect(jsonEncode(saved.toJson()), isNot(contains('access-original')));
    client.close();
    client = RommClient(Uri.parse('http://127.0.0.1:${server.port}/romm'));
    client.onCredentialChanged = (value) async => writes.add(value);
    expect((await client.restore(saved)).id, 7);
    expect(passwords, 1);
    expect(refreshes, 1);
    expect(writes.single.secret, 'refresh-rotated');
  });
  test('rejected refresh requires sign-in while service failures retain uncertainty and malformed tokens never publish', () async {
    var status = 400;
    var writes = 0;
    client.onCredentialChanged = (_) async => writes++;
    serve = (r) async {
      expect(r.uri.path, '/romm/api/token');
      await jsonResponse(
        r,
        status == 200
            ? {
                'access_token': 'access',
                'refresh_token': '',
                'token_type': 'bearer',
                'expires': 900,
              }
            : {},
        status: status,
      );
    };
    const saved = RommCredential('refresh', 'saved-refresh');
    await expectLater(
      client.restore(saved),
      throwsA(isA<RommFailure>().having((e) => e.status, 'status', 401)),
    );
    status = 503;
    await expectLater(
      client.restore(saved),
      throwsA(isA<RommFailure>().having((e) => e.status, 'status', 503)),
    );
    status = 200;
    await expectLater(client.restore(saved), throwsA(isA<RommFailure>()));
    expect(writes, 0);
    expect(client.credential!.secret, 'saved-refresh');
  });
  test('API key pairing accepts the generated alphabet and normalizes case and separators', () async {
    final token = 'rmm_${List.filled(64, 'a').join()}';
    var exchanges = 0;
    var identities = 0;
    var expected = '';
    serve = (r) async {
      if (r.uri.path == '/romm/api/client-tokens/exchange') {
        exchanges++;
        expect(r.method, 'POST');
        expect(r.headers.value('authorization'), isNull);
        expect(jsonDecode(await utf8.decoder.bind(r).join()), {
          'code': expected,
        });
        await jsonResponse(r, {'raw_token': token});
      } else {
        identities++;
        expect(r.uri.path, '/romm/api/users/me');
        expect(r.headers.value('authorization'), 'Bearer $token');
        await jsonResponse(r, {'id': 7, 'username': 'player', 'enabled': true});
      }
    };
    for (final entry in {
      'ABCD2345': 'ABCD2345',
      'abcd2345': 'ABCD2345',
      'abcd-2345': 'ABCD2345',
      'ABCDEFGH': 'ABCDEFGH',
      '23456789': '23456789',
    }.entries) {
      expected = entry.value;
      expect((await client.loginToken(entry.key)).id, 7);
      expect(client.credential!.kind, 'client');
      expect(client.credential!.secret, token);
    }
    expect(exchanges, 5);
    expect(identities, 5);
  });
  test('malformed pairing codes fail before any network request', () async {
    var requests = 0;
    serve = (r) async {
      requests++;
      await jsonResponse(r, {});
    };
    for (final code in [
      '',
      'ABCD234',
      'ABCD23456',
      'ABCD!345',
      'ABCD0345',
      'ABCDI345',
      'ABCD 345',
      'ABCDé',
    ]) {
      await expectLater(client.loginToken(code), throwsA(isA<RommFailure>()));
      expect(client.credential, isNull);
    }
    expect(requests, 0);
  });
  test(
    'an expired API key pairing code is not retried or accepted as a session',
    () async {
      var requests = 0;
      serve = (r) async {
        requests++;
        expect(r.uri.path, '/romm/api/client-tokens/exchange');
        expect(r.headers.value('authorization'), isNull);
        await jsonResponse(r, {
          'detail': 'Invalid or expired pairing code',
        }, status: 404);
      };
      await expectLater(
        client.loginToken('ABCD-2345'),
        throwsA(isA<RommFailure>().having((e) => e.status, 'status', 404)),
      );
      expect(requests, 1);
      expect(client.credential, isNull);
    },
  );
  test('long-lived client tokens restore directly and account rejection never becomes anonymous success', () async {
    final token = 'rmm_${List.filled(64, 'a').join()}';
    var status = 200;
    serve = (r) async {
      expect(r.uri.path, '/romm/api/users/me');
      expect(r.headers.value('authorization'), 'Bearer $token');
      await jsonResponse(r, {
        'id': 7,
        'username': 'player',
        'enabled': true,
      }, status: status);
    };
    expect((await client.restore(RommCredential('client', token))).id, 7);
    expect(client.credential!.kind, 'client');
    status = 401;
    await expectLater(
      client.currentUser(),
      throwsA(isA<RommFailure>().having((e) => e.status, 'status', 401)),
    );
  });
  test(
    'redirects never forward login secrets and permission errors stay explicit',
    () async {
      var redirected = false;
      serve = (r) async {
        if (r.uri.path == '/romm/api/token') {
          r.response.statusCode = 302;
          r.response.headers.set('location', '/elsewhere');
          await r.response.close();
        } else {
          redirected = true;
          await jsonResponse(r, {});
        }
      };
      await expectLater(
        client.login('player', 'private'),
        throwsA(isA<RommFailure>().having((e) => e.status, 'status', 302)),
      );
      expect(redirected, false);
      serve = (r) async => jsonResponse(r, {
        'detail': 'do not display server-controlled secrets',
      }, status: 403);
      await expectLater(
        client.login('player', 'private'),
        throwsA(
          isA<RommFailure>().having(
            (e) => e.message,
            'message',
            isNot(contains('secrets')),
          ),
        ),
      );
    },
  );
  test('artwork is confined to the authenticated server and its base path', () {
    expect(
      client.artworkUri('/assets/romm/cover.webp')!.path,
      '/romm/assets/romm/cover.webp',
    );
    expect(
      client.artworkUri('/romm/assets/cover.webp')!.path,
      '/romm/assets/cover.webp',
    );
    for (final path in [
      'https://elsewhere.test/art',
      '//elsewhere.test/art',
      'http://127.0.0.1:${server.port}/outside/cover',
      '../escape',
      '/assets/%2e%2e/%2e%2e/escape',
    ]) {
      expect(client.artworkUri(path), isNull, reason: path);
    }
  });
  test('wrong versions, malformed JSON and slow responses produce actionable failures', () async {
    serve = (r) async => jsonResponse(r, {
      'SYSTEM': {'VERSION': '4.9.0'},
    });
    await expectLater(
      client.checkServer(),
      throwsA(
        isA<RommFailure>().having(
          (e) => e.message,
          'version',
          contains('4.9.0'),
        ),
      ),
    );
    serve = (r) async {
      r.response.write('<html>proxy login</html>');
      await r.response.close();
    };
    await expectLater(client.checkServer(), throwsA(isA<RommFailure>()));
    client.close();
    client = RommClient(
      Uri.parse('http://127.0.0.1:${server.port}'),
      deadline: const Duration(milliseconds: 50),
    );
    serve = (r) async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await r.response.close();
    };
    await expectLater(
      client.checkServer(),
      throwsA(
        isA<RommFailure>().having(
          (e) => e.message,
          'timeout',
          contains('too long'),
        ),
      ),
    );
  });
}
