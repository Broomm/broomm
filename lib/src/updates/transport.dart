import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'releases.dart';

/// Separate from RomM clients: no account headers or tokens reach GitHub.
class UpdateTransport {
  UpdateTransport({HttpClient? client}) : client = client ?? HttpClient() {
    this.client.connectionTimeout = const Duration(seconds: 15);
    _deadline = Timer(const Duration(minutes: 20), () {
      expired = true;
      close();
    });
  }
  final HttpClient client;
  bool cancelled = false;
  bool expired = false;
  Timer? _deadline;
  void cancel() {
    cancelled = true;
    close();
  }

  void close() {
    _deadline?.cancel();
    client.close(force: true);
  }

  void check() {
    if (expired)
      throw const UpdateFailure(
        'The update connection timed out. Please retry.',
      );
    if (cancelled)
      throw const UpdateFailure(
        'Update cancelled. Your existing installation was kept.',
      );
  }

  Future<HttpClientResponse> get(Uri uri, {bool api = false}) async {
    for (var i = 0; i < 6; i++) {
      check();
      final trusted = api
          ? uri.host == 'api.github.com'
          : uri.host == 'github.com' ||
                uri.host.endsWith('.githubusercontent.com');
      if (!trusted ||
          uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.port != 443 ||
          uri.hasFragment)
        throw const UpdateFailure('Untrusted update download address.');
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Broomm/$broommReleaseVersion',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        api ? 'application/vnd.github+json' : 'application/octet-stream',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        // Closing the bounded client on failure aborts an untrusted response.
        if (location == null) break;
        uri = uri.resolve(location);
        await response.take(0).drain<void>();
        continue;
      }
      return response;
    }
    throw const UpdateFailure('Too many update download redirects.');
  }

  Future<List<int>> bytes(
    Uri uri, {
    required int limit,
    bool api = false,
    bool missing = false,
  }) async {
    final response = await get(uri, api: api);
    if (missing && response.statusCode == 404) return [];
    if (response.statusCode != 200)
      throw const UpdateFailure(
        'The GitHub update service is unavailable. Try again later.',
      );
    if (response.contentLength > limit)
      throw const UpdateFailure('The update response exceeds its size limit.');
    final data = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      check();
      if (data.length + chunk.length > limit)
        throw const UpdateFailure(
          'The update response exceeds its size limit.',
        );
      data.addAll(chunk);
    }
    return data;
  }

  Future<AppUpdate?> latest(
    String current,
    bool candidates,
    String target,
  ) async {
    final releases = <dynamic>[];
    try {
      // The latest stable endpoint avoids starving stable users behind many RCs.
      for (final path in [
        '/repos/$broommRepository/releases?per_page=100',
        '/repos/$broommRepository/releases/latest',
      ]) {
        final body = await bytes(
          Uri.parse('https://api.github.com$path'),
          limit: 4 * 1024 * 1024,
          api: true,
          missing: path.endsWith('/latest'),
        );
        if (body.isEmpty) continue;
        final value = jsonDecode(utf8.decode(body));
        if (value is List) {
          releases.addAll(value);
        } else if (value is Map) {
          releases.add(value);
        } else {
          throw const UpdateFailure('Invalid GitHub release information.');
        }
      }
      return selectUpdate(releases, current, candidates, target);
    } finally {
      close();
    }
  }

  Future<void> download(
    ReleaseAsset asset,
    File destination,
    void Function(double) progress,
  ) async {
    final response = await get(asset.uri);
    if (response.statusCode != 200 ||
        response.contentLength >= 0 && response.contentLength != asset.bytes)
      throw const UpdateFailure(
        'The update download is unavailable or incomplete.',
      );
    await destination.create(exclusive: true);
    final output = await destination.open(mode: FileMode.writeOnly);
    var received = 0;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        check();
        received += chunk.length;
        if (received > asset.bytes)
          throw const UpdateFailure('The update exceeds its release size.');
        await output.writeFrom(chunk);
        progress(received / asset.bytes);
      }
      if (received != asset.bytes)
        throw const UpdateFailure('The update download was incomplete.');
      await output.flush();
    } finally {
      await output.close();
    }
  }
}
