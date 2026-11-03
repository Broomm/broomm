import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/steam/cdp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  final sockets = <WebSocket>[];
  setUp(
    () async => server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  );
  tearDown(() async {
    for (final socket in sockets) {
      await socket.close();
    }
    sockets.clear();
    await server.close(force: true);
  });
  Map<String, Object> target({String? websocket, String? origin}) => {
    'id': 'test',
    'title': 'SharedJSContext',
    'type': 'page',
    'url': origin ?? 'https://steamloopback.host/routes/library',
    'webSocketDebuggerUrl':
        websocket ?? 'ws://127.0.0.1:${server.port}/devtools/page/test',
  };
  test('discovers Big Picture shared context and matches out-of-order evaluations by CDP request identity', () async {
    final requests = <Map>[];
    server.listen((r) async {
      if (r.uri.path == '/json/list') {
        r.response.write(jsonEncode([target()]));
        await r.response.close();
      } else {
        final ws = await WebSocketTransformer.upgrade(r);
        sockets.add(ws);
        ws.listen((message) {
          requests.add(jsonDecode(message as String) as Map);
          if (requests.length == 2) {
            ws.add(
              jsonEncode({'method': 'Runtime.consoleAPICalled', 'params': {}}),
            );
            for (final request in requests.reversed) {
              expect(request['method'], 'Runtime.evaluate');
              expect(request['params']['awaitPromise'], isTrue);
              ws.add(
                jsonEncode({
                  'id': request['id'],
                  'result': {
                    'result': {
                      'value': {'input': request['params']['expression']},
                    },
                  },
                }),
              );
            }
          }
        });
      }
    });
    final c = await SteamCef.connect(ports: [server.port]);
    try {
      final result = await Future.wait([
        c.evaluate('first'),
        c.evaluate('second'),
      ]);
      expect(result, [
        {'input': 'first'},
        {'input': 'second'},
      ]);
    } finally {
      await c.close();
    }
  });
  test('rejects external debugger addresses and ambiguous Steam contexts before WebSocket access', () async {
    var mode = 'remote';
    var websocketRequests = 0;
    server.listen((r) async {
      if (r.uri.path != '/json/list') websocketRequests++;
      r.response.write(
        jsonEncode(
          mode == 'remote'
              ? [target(websocket: 'ws://example.com/devtools/page/test')]
              : [target(), target()],
        ),
      );
      await r.response.close();
    });
    await expectLater(
      SteamCef.connect(ports: [server.port]),
      throwsFormatException,
    );
    mode = 'ambiguous';
    await expectLater(SteamCef.connect(ports: [server.port]), throwsStateError);
    expect(websocketRequests, 0);
  });
  test('does not follow HTTP discovery redirects or connect arbitrary same-title browser contexts', () async {
    var redirects = true;
    var followed = 0;
    server.listen((r) async {
      if (r.uri.path != '/json/list') followed++;
      if (redirects) {
        r.response.statusCode = 302;
        r.response.headers.set(HttpHeaders.locationHeader, '/elsewhere');
      } else {
        r.response.write(jsonEncode([target(origin: 'https://example.com/')]));
      }
      await r.response.close();
    });
    await expectLater(SteamCef.connect(ports: [server.port]), throwsStateError);
    redirects = false;
    await expectLater(SteamCef.connect(ports: [server.port]), throwsStateError);
    expect(followed, 0);
  });
  test(
    'WebSocket handshake redirects cannot escape to another endpoint',
    () async {
      var followed = 0;
      final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      other.listen((r) async {
        followed++;
        r.response.statusCode = 403;
        await r.response.close();
      });
      server.listen((r) async {
        if (r.uri.path == '/json/list')
          r.response.write(jsonEncode([target()]));
        else {
          r.response.statusCode = 302;
          r.response.headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${other.port}/redirected',
          );
        }
        await r.response.close();
      });
      try {
        await expectLater(
          SteamCef.connect(ports: [server.port]),
          throwsA(isA<Exception>()),
        );
        expect(followed, 0);
      } finally {
        await other.close(force: true);
      }
    },
  );
  test('native exceptions and disconnected responses remain errors without leaking exception contents', () async {
    var disconnect = false;
    server.listen((r) async {
      if (r.uri.path == '/json/list') {
        r.response.write(jsonEncode([target()]));
        await r.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(r);
      sockets.add(ws);
      ws.listen((message) {
        final request = jsonDecode(message as String) as Map;
        if (disconnect) {
          ws.close();
          return;
        }
        ws.add(
          jsonEncode({
            'id': request['id'],
            'result': {
              'exceptionDetails': {'text': 'private runtime contents'},
            },
          }),
        );
      });
    });
    final c = await SteamCef.connect(ports: [server.port]);
    try {
      await expectLater(
        c.evaluate('fixed bundled script'),
        throwsA(
          isA<StateError>().having(
            (e) => e.toString(),
            'redaction',
            isNot(contains('private')),
          ),
        ),
      );
      disconnect = true;
      await expectLater(c.evaluate('fixed bundled script'), throwsStateError);
    } finally {
      await c.close();
    }
  });
}
