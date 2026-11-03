import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The only remote evaluations in production are Broomm's bundled Steam bridge.
abstract class SteamConnection {
  Future<Map<String, dynamic>> evaluate(String expression);
  Future<void> close();
}

class SteamCef implements SteamConnection {
  SteamCef._(this._socket) {
    _subscription = _socket.listen(
      _message,
      onError: _failed,
      onDone: () {
        _failed(
          StateError(
            'Steam closed its debugging connection. Retry Add to Steam.',
          ),
        );
      },
    );
  }
  final WebSocket _socket;
  late final StreamSubscription<dynamic> _subscription;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _next = 0;
  bool _closed = false;

  /// No proxy, credentials, remote endpoints or arbitrary browser tabs.
  static Future<SteamConnection> connect({
    List<int> ports = const [8080, 8081],
  }) async {
    for (final port in ports) {
      final http = HttpClient()..findProxy = (_) => 'DIRECT';
      http.connectionTimeout = const Duration(seconds: 2);
      final deadline = Timer(
        const Duration(seconds: 8),
        () => http.close(force: true),
      );
      var upgraded = false;
      try {
        final request = await http
            .getUrl(Uri.parse('http://127.0.0.1:$port/json/list'))
            .timeout(const Duration(seconds: 2));
        request.followRedirects = false;
        final response = await request.close().timeout(
          const Duration(seconds: 2),
        );
        if (response.statusCode != 200) continue;
        final bytes = <int>[];
        await for (final chunk in response.timeout(
          const Duration(seconds: 2),
        )) {
          bytes.addAll(chunk);
          if (bytes.length > 1024 * 1024)
            throw const FormatException('Oversized Steam discovery response');
        }
        final data = jsonDecode(utf8.decode(bytes));
        if (data is! List || data.length > 256)
          throw const FormatException('Invalid Steam discovery response');
        final matches = data.whereType<Map>().where((entry) {
          final url = Uri.tryParse('${entry['url']}');
          return entry['title'] == 'SharedJSContext' &&
              entry['type'] == 'page' &&
              url?.scheme == 'https' &&
              url?.host == 'steamloopback.host' &&
              url?.userInfo == '' &&
              url?.port == 443;
        }).toList();
        if (matches.length != 1) {
          if (matches.isEmpty) continue;
          throw StateError(
            'More than one Steam shared context was found. Restart Steam normally and retry.',
          );
        }
        final ws = Uri.tryParse('${matches.single['webSocketDebuggerUrl']}');
        if (ws == null ||
            ws.scheme != 'ws' ||
            ws.host != '127.0.0.1' ||
            ws.port != port ||
            ws.userInfo.isNotEmpty ||
            ws.hasQuery ||
            ws.hasFragment ||
            !RegExp(r'^/devtools/page/[A-Za-z0-9_-]+$').hasMatch(ws.path)) {
          throw const FormatException(
            'Steam returned an unsafe debugging address',
          );
        }
        final socket = await WebSocket.connect(
          ws.toString(),
          customClient: _HandshakeClient(http, port),
        ).timeout(const Duration(seconds: 3));
        // The WebSocket owns its upgraded connection; the HttpClient is closed
        // in finally to release discovery connections without killing that socket.
        upgraded = true;
        return SteamCef._(socket);
      } on SocketException {
        continue;
      } on TimeoutException {
        continue;
      } on HttpException {
        continue;
      } finally {
        deadline.cancel();
        http.close(force: !upgraded);
      }
    }
    throw StateError(
      'Steam CEF debugging is unavailable. Open Steam with CEF debugging enabled, sign in, and retry. See the Add to Steam instructions.',
    );
  }

  void _message(dynamic data) {
    try {
      if (data is! String || data.length > 8 * 1024 * 1024) {
        throw const FormatException('Invalid Steam debugging message');
      }
      final message = jsonDecode(data);
      if (message is! Map)
        throw const FormatException('Invalid Steam debugging message');
      if (message['id'] == null) return; // Unsubscribed CDP events.
      final result = _pending.remove(message['id']);
      if (result == null) return; // A reply to a request that timed out.
      final body = message['result'];
      if (message['error'] != null ||
          body is! Map ||
          body['exceptionDetails'] != null ||
          body['result'] is! Map ||
          body['result']['value'] is! Map) {
        result.completeError(
          StateError(
            'Steam could not complete the library operation. Retry Add to Steam.',
          ),
        );
      } else {
        result.complete(
          Map<String, dynamic>.from(body['result']['value'] as Map),
        );
      }
    } catch (e) {
      _failed(e);
    }
  }

  void _failed(Object error) {
    if (_closed) return;
    _closed = true;
    for (final request in _pending.values) {
      if (!request.isCompleted) request.completeError(error);
    }
    _pending.clear();
    unawaited(_socket.close().catchError((_) {}));
  }

  @override
  Future<Map<String, dynamic>> evaluate(String expression) async {
    if (_closed) throw StateError('Steam is disconnected. Retry Add to Steam.');
    final id = ++_next;
    final reply = Completer<Map<String, dynamic>>();
    _pending[id] = reply;
    try {
      _socket.add(
        jsonEncode({
          'id': id,
          'method': 'Runtime.evaluate',
          'params': {
            'expression': expression,
            'returnByValue': true,
            'awaitPromise': true,
            'silent': true,
            'timeout': 25000,
          },
        }),
      );
      return await reply.future.timeout(const Duration(seconds: 28));
    } finally {
      _pending.remove(id);
    }
  }

  @override
  Future<void> close() async {
    _failed(StateError('Steam debugging connection closed.'));
    await _subscription.cancel();
  }
}

/// WebSocket.connect uses HttpClient.openUrl, whose redirect default is true.
/// Restrict that SDK handshake too, rather than only guarding discovery URLs.
class _HandshakeClient implements HttpClient {
  _HandshakeClient(this.client, this.port);
  final HttpClient client;
  final int port;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (method != 'GET' ||
        url.scheme != 'http' ||
        url.host != '127.0.0.1' ||
        url.port != port ||
        url.userInfo.isNotEmpty ||
        url.query.isNotEmpty ||
        url.fragment.isNotEmpty ||
        !url.path.startsWith('/devtools/page/'))
      throw const FormatException('Unsafe Steam WebSocket handshake');
    return await client.openUrl(method, url)
      ..followRedirects = false;
  }

  // This deliberately narrow client is used only by the SDK WebSocket
  // handshake; unexpected future SDK calls fail closed.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
