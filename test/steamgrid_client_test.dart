import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/steamgrid.dart';
import 'package:broomm/src/romm/models.dart';

import 'support/artwork_fixtures.dart';

void main() {
  late HttpServer server;
  late SteamGridClient client;
  late Future<void> Function(HttpRequest) respond;
  Uri image(String path) => Uri.parse('http://127.0.0.1:${server.port}/$path');
  Map<String, dynamic> entry(
    int id, {
    int width = 512,
    int height = 512,
    String mime = 'image/png',
  }) => {
    'id': id,
    'width': width,
    'height': height,
    'mime': mime,
    'url': image('$id.png').toString(),
    'thumb': image('thumb$id.png').toString(),
    'author': {'name': 'Artist $id'},
  };
  Future<void> json(HttpRequest r, Object v, {int status = 200}) async {
    r.response.statusCode = status;
    r.response.headers.contentType = ContentType.json;
    r.response.write(jsonEncode(v));
    await r.response.close();
  }

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = SteamGridClient('sgdb-fixture-key', api: image('api/v2'));
    respond = (r) async => json(r, {});
    server.listen((r) async {
      try {
        await respond(r);
      } on IOException {
        /* Deliberate cancellation. */
      }
    });
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
  });
  test(
    'cancelling one picker request group leaves the next popup operational',
    () async {
      final enteredIcon = Completer<void>(),
          enteredHero = Completer<void>(),
          releaseIcon = Completer<void>(),
          releaseHero = Completer<void>();
      respond = (r) async {
        final icon = r.uri.path.contains('/grids/');
        (icon ? enteredIcon : enteredHero).complete();
        await (icon ? releaseIcon : releaseHero).future;
        await json(r, {'success': true, 'total': 0, 'data': []});
      };
      final iconOwner = Object(), heroOwner = Object();
      final icon = client.page(42, ArtworkKind.icon, owner: iconOwner);
      await enteredIcon.future;
      final hero = client.page(42, ArtworkKind.hero, owner: heroOwner);
      await enteredHero.future;
      try {
        client.cancelRequests(iconOwner);
        await expectLater(icon, throwsA(isA<RommFailure>()));
        releaseHero.complete();
        expect((await hero).images, isEmpty);
        await expectLater(
          client.page(42, ArtworkKind.icon, owner: iconOwner),
          throwsA(isA<RommFailure>()),
        );
      } finally {
        releaseIcon.complete();
        if (!releaseHero.isCompleted) releaseHero.complete();
      }
    },
  );
  test('preview responses are bounded and closing the picker cancels pending HTTP work', () async {
    respond = (r) async {
      r.response.headers.contentType = ContentType('image', 'png');
      r.response.add(List<int>.filled(2 * 1024 * 1024, 0));
      await r.response.close();
    };
    await expectLater(
      client.image(image('large.png'), thumbnail: true),
      throwsA(isA<RommFailure>()),
    );
    final entered = Completer<void>(), release = Completer<void>();
    respond = (r) async {
      entered.complete();
      await release.future;
    };
    final pending = client.page(42, ArtworkKind.icon);
    await entered.future;
    client.close();
    try {
      await expectLater(pending, throwsA(isA<RommFailure>()));
    } finally {
      release.complete();
    }
  });
  test('mapped SGDB requests authenticate only the API, filter square PNGs and use heroes separately with pagination', () async {
    respond = (r) async {
      expect(r.headers.value('authorization'), 'Bearer sgdb-fixture-key');
      expect(r.uri.queryParameters['types'], 'static');
      if (r.uri.path.contains('/grids/')) {
        expect(r.uri.path, '/api/v2/grids/game/42');
        expect(r.uri.queryParameters['dimensions'], '512x512,1024x1024');
        expect(r.uri.queryParameters['mimes'], 'image/png');
        await json(r, {
          'success': true,
          'page': 0,
          'total': 51,
          'data': [
            entry(1),
            entry(2, width: 600, height: 900),
            entry(3, mime: 'image/jpeg'),
            {...entry(4), 'url': 'https://unrelated.example/image.png'},
            {
              ...entry(5),
              'tags': ['nsfw'],
            },
          ],
        });
      } else {
        expect(r.uri.path, '/api/v2/heroes/game/42');
        expect(r.uri.queryParameters['page'], '1');
        expect(r.uri.queryParameters.containsKey('dimensions'), false);
        await json(r, {
          'success': true,
          'total': 51,
          'data': [entry(8, width: 1920, height: 620), entry(9)],
        });
      }
    };
    final icons = await client.page(42, ArtworkKind.icon);
    expect(icons.images.map((e) => e.id), [1]);
    expect(icons.hasMore, true);
    final heroes = await client.page(42, ArtworkKind.hero, page: 1);
    expect(heroes.images.single.id, 8);
    expect(heroes.hasMore, false);
  });
  test('image transport sends no credentials and rejects foreign URLs, redirects and non-image responses', () async {
    var status = 200, mime = 'image/png';
    respond = (r) async {
      expect(r.headers.value('authorization'), isNull);
      r.response.statusCode = status;
      r.response.headers.set('content-type', mime);
      if (status == 302)
        r.response.headers.set('location', image('redirect').toString());
      else
        r.response.add(artworkPng(1, 1));
      await r.response.close();
    };
    expect(await client.image(image('image.png')), artworkPng(1, 1));
    expect(
      () => client.image(Uri.parse('https://unrelated.example/test.png')),
      throwsA(isA<RommFailure>()),
    );
    status = 302;
    await expectLater(
      client.image(image('image.png')),
      throwsA(isA<RommFailure>().having((e) => e.status, 'status', 302)),
    );
    status = 200;
    mime = 'text/html';
    await expectLater(
      client.image(image('image.png')),
      throwsA(isA<RommFailure>()),
    );
  });
  test('logos use the logo endpoint, accept tall or wide PNG/WebP images and exclude unsupported formats', () async {
    respond = (r) async {
      expect(r.uri.path, '/api/v2/logos/game/42');
      expect(r.headers.value('authorization'), 'Bearer sgdb-fixture-key');
      expect(r.uri.queryParameters['mimes'], 'image/png,image/webp');
      expect(r.uri.queryParameters.containsKey('dimensions'), false);
      await json(r, {
        'success': true,
        'data': [
          entry(20, width: 900, height: 200),
          entry(21, width: 100, height: 400),
          entry(22, mime: 'image/jpeg'),
          entry(23, width: 9000),
        ],
      });
    };
    final logos = await client.page(42, ArtworkKind.logo);
    expect(logos.images.map((v) => v.id), [20, 21]);
    expect(logos.images.every((v) => v.kind == ArtworkKind.logo), true);
  });
  test('invalid keys, malformed responses and failed catalogues stay failures rather than empty artwork', () async {
    var status = 401;
    respond = (r) async => json(
      r,
      status == 200 ? {'success': true, 'data': 'damaged'} : {},
      status: status,
    );
    await expectLater(
      client.page(42, ArtworkKind.icon),
      throwsA(isA<RommFailure>().having((e) => e.status, 'status', 401)),
    );
    status = 503;
    await expectLater(
      client.page(42, ArtworkKind.hero),
      throwsA(isA<RommFailure>().having((e) => e.status, 'status', 503)),
    );
    status = 200;
    await expectLater(
      client.page(42, ArtworkKind.hero),
      throwsA(isA<RommFailure>()),
    );
  });
}
