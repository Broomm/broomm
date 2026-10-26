import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'transfer.dart';
import 'credential.dart';

part 'saves.dart';

class RommClient with RommSaves {
  RommClient(
    this.server, {
    HttpClient? http,
    this.deadline = const Duration(seconds: 20),
  }) : _http = http ?? HttpClient() {
    _http.connectionTimeout = deadline;
    _http.idleTimeout = const Duration(seconds: 15);
    _http.maxConnectionsPerHost = 4;
  }
  final Uri server;
  final HttpClient _http;
  final Duration deadline;
  String? _access, _refresh;
  DateTime? _expires;
  Future<void>? _refreshing;
  bool _closed = false;
  bool _clientToken = false;
  bool readOnlyLogin = false;
  Future<void> Function(Future<void> Function(RommCredential? latest))?
  refreshGuard;
  Future<void> Function(RommCredential)? onCredentialChanged;
  RommCredential? get credential => _clientToken && _access != null
      ? RommCredential('client', _access!)
      : _refresh != null
      ? RommCredential('refresh', _refresh!)
      : null;
  static const scopes =
      'me.read roms.read platforms.read assets.read assets.write firmware.read';

  Uri endpoint(String path, [Map<String, String>? query]) =>
      server.replace(path: '${server.path}/$path', queryParameters: query);

  Future<String> checkServer() async {
    final j = await _json('GET', 'api/heartbeat', auth: false) as Map;
    final version = (j['SYSTEM'] as Map?)?['VERSION'] as String?;
    if (version != '5.4.0') {
      throw RommFailure(
        'This build supports RomM 5.4.0. This server reports ${version ?? 'an unknown version'}.',
      );
    }
    return version!;
  }

  Future<RommUser> login(String username, String password) async {
    _refresh = null;
    _access = null;
    _clientToken = false;
    readOnlyLogin = false;
    Future<dynamic> authenticate(String requested) => _json(
      'POST',
      'api/token',
      auth: false,
      form: {
        'grant_type': 'password',
        'username': username,
        'password': password,
        'scope': requested,
      },
    );
    Map j;
    try {
      j = await authenticate(scopes) as Map;
    } on RommFailure catch (e) {
      if (e.status != 403) rethrow;
      // Browsing remains available to accounts without save-write privileges.
      j = await authenticate(
        scopes.replaceAll(' assets.write', '').replaceAll(' firmware.read', ''),
      ) as Map;
      readOnlyLogin = true;
    }
    await _tokens(j);
    return currentUser();
  }

  Future<RommUser> loginToken(String token) async {
    _refresh = null;
    _expires = null;
    _clientToken = true;
    final value = token.trim();
    final pairingCode = value.replaceAll('-', '').toUpperCase();
    if (RegExp(r'^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$')
        .hasMatch(pairingCode)) {
      final j = await _json(
        'POST',
        'api/client-tokens/exchange',
        auth: false,
        body: {'code': pairingCode},
      ) as Map;
      _access = j['raw_token'] as String?;
    } else {
      if (!RegExp(r'^rmm_[a-fA-F0-9]{64}$').hasMatch(value)) {
        throw const RommFailure(
          'Enter a RomM client token or an eight-character API key pairing code.',
        );
      }
      _access = value;
    }
    if (_access == null || !RegExp(r'^rmm_[a-fA-F0-9]{64}$').hasMatch(_access!))
      throw const RommFailure('RomM returned no token.');
    return currentUser();
  }

  Future<void> _tokens(Map j) async {
    if (_closed) throw const RommFailure('This server connection has closed.');
    final access = j['access_token'];
    final refresh = j['refresh_token'], expires = j['expires'];
    bool validToken(Object? v) =>
        v is String &&
        v.isNotEmpty &&
        v.length <= 16384 &&
        !v.contains(RegExp(r'[\x00-\x20]'));
    if (!validToken(access) ||
        j['token_type'] != 'bearer' ||
        (refresh != null && !validToken(refresh)) ||
        (expires != null && (expires is! int || expires < 0))) {
      throw const RommFailure('RomM returned an invalid login response.');
    }
    _access = access as String;
    _clientToken = false;
    _refresh = refresh as String? ?? _refresh;
    _expires = DateTime.now().add(Duration(seconds: expires as int? ?? 900));
    if (credential != null) await onCredentialChanged?.call(credential!);
  }

  Future<RommUser> restore(RommCredential saved) async {
    if (saved.kind == 'client') return loginToken(saved.secret);
    _refresh = saved.secret;
    await _refreshTokens();
    return currentUser();
  }

  Future<void> _refreshTokens() async {
    Future<void> update(RommCredential? latest) async {
      if (latest != null && latest.kind != 'refresh')
        throw const RommFailure(
          'The saved sign-in changed. Select your profile again.',
          status: 401,
        );
      if (latest?.kind == 'refresh') _refresh = latest!.secret;
      if (_refresh == null)
        throw const RommFailure(
          'Your session expired. Sign in again.',
          status: 401,
        );
      try {
        final j = await _json(
          'POST',
          'api/token',
          auth: false,
          form: {'grant_type': 'refresh_token', 'refresh_token': _refresh!},
        ) as Map;
        await _tokens(j);
      } on RommFailure catch (e) {
        if (e.status == 400 || e.status == 401)
          throw const RommFailure(
            'Your saved sign-in expired or was revoked. Sign in again.',
            status: 401,
          );
        rethrow;
      }
    }

    if (refreshGuard != null) {
      await refreshGuard!(update);
    } else {
      await update(null);
    }
  }

  Future<void> _ensureToken() async {
    if (_closed) throw const RommFailure('This server connection has closed.');
    if (_access == null)
      throw const RommFailure('Sign in to RomM first.', status: 401);
    if (_expires != null &&
        DateTime.now().add(const Duration(seconds: 30)).isAfter(_expires!)) {
      if (_refresh == null)
        throw const RommFailure(
          'Your session expired. Sign in again.',
          status: 401,
        );
      final pending = _refreshing ??= _refreshTokens();
      try {
        await pending;
      } finally {
        if (identical(_refreshing, pending)) _refreshing = null;
      }
    }
  }

  Future<RommUser> currentUser() async => RommUser.fromJson(
    (await _json('GET', 'api/users/me') as Map).cast<String, dynamic>(),
  );
  Future<List<RommPlatform>> platforms() async =>
      (await _json('GET', 'api/platforms') as List)
          .map((e) => RommPlatform.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
  Future<RommPage> games({
    String search = '',
    int? platform,
    int offset = 0,
    int limit = 24,
    bool recent = false,
  }) async {
    final j = await _json(
      'GET',
      'api/roms',
      query: {
        'limit': '$limit',
        'offset': '$offset',
        'with_char_index': 'false',
        'with_filter_values': 'false',
        'with_rom_id_index': 'false',
        'with_total': 'true',
        'group_by_meta_id': 'true',
        'order_by': recent
            ? 'id'
            : search.isEmpty
            ? 'name'
            : '',
        'order_dir': recent ? 'desc' : 'asc',
        if (search.isNotEmpty) 'search_term': search,
        if (platform != null) 'platform_ids': '$platform',
      },
    );
    return RommPage.fromJson((j as Map).cast<String, dynamic>());
  }

  Future<RommGame> game(int id) async => RommGame.fromJson(
    (await _json('GET', 'api/roms/$id') as Map).cast<String, dynamic>(),
  );

  /// Streams one manifest file to private staging with backpressure. No ROM
  /// payload or archive is accumulated in memory, extracted, or executed.
  Future<void> downloadFile(
    RommFile file,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) => _downloadContent(
    ['roms', '${file.id}', 'files', 'content', file.name],
    file.bytes,
    destination,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  Future<List<RommFirmware>> firmware(int platformId) async =>
      (await _json(
            'GET',
            'api/firmware',
            query: {'platform_id': '$platformId', 'missing': 'false'},
          ) as List)
          .map((v) => RommFirmware.fromJson((v as Map).cast<String, dynamic>()))
          .toList();

  Future<void> downloadFirmware(
    RommFirmware file,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) => _downloadContent(
    ['firmware', '${file.id}', 'content', file.name],
    file.bytes,
    destination,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  Future<void> _downloadContent(
    List<String> contentPath,
    int expectedBytes,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    HttpClientRequest? request;
    RandomAccessFile? output;
    var stopped = false;
    final totalDeadline = Timer(
      const Duration(hours: 24),
      () => request?.abort(),
    );
    cancellation.abort = () => request?.abort();
    try {
      cancellation.check();
      await _ensureToken();
      cancellation.check();
      final uri = server.replace(
        pathSegments: [
          ...server.pathSegments.where((v) => v.isNotEmpty),
          'api',
          ...contentPath,
        ],
      );
      request = await _http
          .getUrl(uri)
          .then((value) {
            if (stopped || cancellation.cancelled || _closed) value.abort();
            return value;
          })
          .timeout(deadline);
      cancellation.check();
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_access');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(deadline);
      if (response.statusCode != 200) {
        throw RommFailure(switch (response.statusCode) {
          401 => 'Your session expired. Sign in again to download.',
          403 => 'This account does not have permission to download this game.',
          404 =>
            'This game file is no longer available in RomM. Refresh and retry.',
          >= 300 && < 400 => 'RomM redirected the download. Credentials were not forwarded. Use the final server address.',
          _ =>
            'RomM could not download this file (HTTP ${response.statusCode}). Retry from the game page.',
        }, status: response.statusCode);
      }
      if (response.contentLength >= 0 &&
          response.contentLength != expectedBytes) {
        throw const RommFailure(
          'The file size changed in RomM. Refresh the game and retry.',
        );
      }
      output = await destination.open(mode: FileMode.writeOnly);
      var received = 0;
      await for (final chunk in response.timeout(deadline)) {
        cancellation.check();
        received += chunk.length;
        if (received > expectedBytes)
          throw const RommFailure(
            'RomM sent more data than the file manifest allows.',
          );
        await output.writeFrom(chunk);
        onProgress(received);
      }
      cancellation.check();
      if (received != expectedBytes)
        throw const RommFailure(
          'The download ended before the whole file arrived. Please retry.',
        );
      await output.flush();
    } on RommFailure {
      rethrow;
    } on TimeoutException {
      throw const RommFailure(
        'The download stalled. Check your connection and retry.',
      );
    } on IOException {
      cancellation.check();
      throw const RommFailure(
        'The download failed. Check your connection, free disk space and write access, then retry.',
      );
    } finally {
      stopped = true;
      totalDeadline.cancel();
      cancellation.abort = null;
      request?.abort();
      await output?.close();
    }
  }

  // Artwork is kept inside this account's client and may never carry its bearer
  // token to an external host or outside a server's configured path prefix.
  Uri? artworkUri(String path) {
    final supplied = Uri.tryParse(path);
    if (supplied == null ||
        hasUnsafeUrlPath(path) ||
        supplied.hasFragment ||
        supplied.userInfo.isNotEmpty)
      return null;
    Uri uri;
    if (supplied.hasScheme || supplied.hasAuthority) {
      uri = server.resolveUri(supplied);
    } else {
      final relative = path.replaceFirst(RegExp(r'^/+'), '');
      final base = server.path.replaceFirst(RegExp(r'^/'), '');
      final resource = base.isNotEmpty && relative.startsWith('$base/')
          ? relative.substring(base.length + 1)
          : relative;
      uri = Uri.parse('${server.origin}${server.path}/$resource');
    }
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.origin != server.origin ||
        (server.path.isNotEmpty && !uri.path.startsWith('${server.path}/')) ||
        uri.pathSegments.any((p) => p == '..' || p == '.'))
      return null;
    return uri;
  }

  Future<Uint8List?> artwork(String path) async {
    final uri = artworkUri(path);
    if (uri == null) return null;
    return _bytes('GET', uri, limit: 8 * 1024 * 1024);
  }

  Future<dynamic> _json(
    String method,
    String path, {
    bool auth = true,
    Map<String, String>? form,
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final bytes = await _bytes(
      method,
      endpoint(path, query),
      auth: auth,
      form: form,
      body: body,
      limit: 12 * 1024 * 1024,
    );
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const RommFailure(
        'The server returned an unreadable response. Check that the address points to RomM.',
      );
    }
  }

  Future<Uint8List> _bytes(
    String method,
    Uri uri, {
    bool auth = true,
    Map<String, String>? form,
    Map<String, dynamic>? body,
    required int limit,
  }) async {
    HttpClientRequest? request;
    bool cancelled = false;
    final operation = () async {
      if (_closed)
        throw const RommFailure('This server connection has closed.');
      if (auth) await _ensureToken();
      request = await _http.openUrl(method, uri);
      if (cancelled || _closed) {
        request!.abort();
        throw const RommFailure('This request was cancelled.');
      }
      request!.followRedirects = false;
      request!.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, image/*',
      );
      if (auth)
        request!.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $_access',
        );
      if (form != null) {
        request!.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request!.write(Uri(queryParameters: form).query);
      }
      if (body != null) {
        request!.headers.contentType = ContentType.json;
        request!.write(jsonEncode(body));
      }
      final response = await request!.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final status = response.statusCode;
        request!.abort();
        throw RommFailure(switch (status) {
          401 => 'Sign-in was not accepted, or your session expired. Please sign in again.',
          403 => 'This account does not have permission for this action.',
          404 => 'This RomM endpoint was not found. Check the server address and version.',
          429 => 'RomM is busy with too many requests. Wait a moment, then try again.',
          >= 300 && < 400 => 'RomM redirected the request. Enter its final server address; credentials were not forwarded.',
          _ => 'RomM could not complete the request (HTTP $status). Try again.',
        }, status: status);
      }
      final bytes = BytesBuilder(copy: false);
      var count = 0;
      await for (final chunk in response) {
        count += chunk.length;
        if (count > limit) {
          request!.abort();
          throw const RommFailure(
            'The server response exceeded the supported size.',
          );
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }();
    try {
      return await operation.timeout(
        deadline,
        onTimeout: () {
          cancelled = true;
          request?.abort();
          throw const RommFailure(
            'RomM took too long to respond. Check your connection and try again.',
          );
        },
      );
    } on RommFailure {
      rethrow;
    } on HandshakeException {
      throw const RommFailure(
        'The server certificate could not be verified. Use a trusted HTTPS address.',
      );
    } on IOException {
      throw const RommFailure(
        'Could not reach RomM. Check the server address and your connection.',
      );
    } on FormatException {
      throw const RommFailure('RomM returned an unexpected response.');
    }
  }

  void close() {
    _closed = true;
    _access = null;
    _refresh = null;
    _http.close(force: true);
  }
}
