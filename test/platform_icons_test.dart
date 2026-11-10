import 'dart:io';
import 'dart:typed_data';

import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:broomm/src/shell/platform_icon_image.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/artwork_fixtures.dart';

void main() {
  const serverId = '123456789012345678901234567890ab';
  const otherServerId = '123456789012345678901234567890cd';
  late Directory root;
  late HttpServer server;
  late RommClient client;
  late GameLibrary library;
  late List<(String, String?)> requests;
  late Map<String, Uint8List> icons;
  Future<Uint8List?> lookup(String id, String slug, {bool online = true}) =>
      library.platformIconFor(
        id,
        slug,
        validatePng: isDecodablePlatformIcon,
        client: online ? client : null,
      );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-platform-icons-');
    library = GameLibrary(root);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = RommClient(Uri.parse('http://127.0.0.1:${server.port}/romm'));
    requests = [];
    icons = {};
    server.listen((request) async {
      final path = request.uri.path;
      requests.add((
        path,
        request.headers.value(HttpHeaders.authorizationHeader),
      ));
      if (path.endsWith('/redirect.ico')) {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/escaped');
      } else if (icons[path] case final bytes?) {
        request.response.add(bytes);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  test(
    'downloads and reuses one icon per platform and server while offline',
    () async {
      const path = '/romm/assets/platforms/psx.ico';
      final png = artworkPng(64, 64);
      icons[path] = artworkIco(png);
      expect(await lookup(serverId, 'psx'), png);
      icons.clear();
      library = GameLibrary(root);
      expect(await lookup(serverId, 'psx', online: false), png);
      expect(await lookup(serverId, 'psx'), png);
      expect(await lookup(otherServerId, 'psx', online: false), isNull);
      expect(requests, [(path, null)]);
    },
  );

  test(
    'a missing or malformed response leaves no cache and can be retried',
    () async {
      const path = '/romm/assets/platforms/switch.ico';
      expect(await lookup(serverId, 'switch'), isNull);
      final png = artworkPng(64, 64);
      final malformed = artworkIco(png);
      ByteData.sublistView(malformed)
          .setUint32(18, malformed.length, Endian.little);
      icons[path] = malformed;
      expect(await lookup(serverId, 'switch'), isNull);
      expect(await lookup(serverId, 'switch', online: false), isNull);
      icons[path] = artworkIco(png);
      expect(await lookup(serverId, 'switch'), png);
      expect(requests, [(path, null), (path, null), (path, null)]);
    },
  );

  test(
    'icon requests reject unsafe slugs, redirects and oversized bodies',
    () async {
      expect(await client.platformIcon('../psx'), isNull);
      await expectLater(
        client.platformIcon('redirect'),
        throwsA(isA<RommFailure>().having((e) => e.status, 'status', 302)),
      );
      const path = '/romm/assets/platforms/oversized.ico';
      icons[path] = Uint8List(RommClient.platformIconByteLimit + 1);
      await expectLater(
        client.platformIcon('oversized'),
        throwsA(isA<RommFailure>()),
      );
      expect(requests, [
        ('/romm/assets/platforms/redirect.ico', null),
        (path, null),
      ]);
    },
  );
}
