import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'romm/models.dart';

enum ArtworkKind { icon, hero, logo }

class GridArtwork {
  const GridArtwork({
    required this.id,
    required this.kind,
    required this.url,
    required this.thumb,
    required this.width,
    required this.height,
    required this.mime,
    required this.author,
  });
  final int id, width, height;
  final ArtworkKind kind;
  final Uri url, thumb;
  final String mime, author;
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'url': url.toString(),
    'author': author,
    'width': width,
    'height': height,
    'mime': mime,
  };
}

class ArtworkPage {
  const ArtworkPage(this.images, this.hasMore);
  final List<GridArtwork> images;
  final bool hasMore;
}

/// Separate HTTP owner: RomM credentials are never sent to SGDB or its CDN.
class SteamGridClient {
  SteamGridClient(
    this.key, {
    HttpClient? http,
    Uri? api,
    this.deadline = const Duration(seconds: 20),
  }) : api = api ?? Uri.https('www.steamgriddb.com', '/api/v2'),
       _http = http ?? HttpClient() {
    _http.connectionTimeout = deadline;
    _http.maxConnectionsPerHost = 4;
  }
  final String key;
  final Uri api;
  final HttpClient _http;
  final Duration deadline;
  bool closed = false;
  final _cancelledOwners = <Object>{};
  final _requests = <HttpClientRequest, Object>{};
  void cancelRequests(Object owner) {
    _cancelledOwners.add(owner);
    for (final entry in _requests.entries.toList()) {
      if (identical(entry.value, owner)) entry.key.abort();
    }
  }

  bool mediaAllowed(Uri uri) =>
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      !uri.hasQuery &&
      ((uri.scheme == 'https' &&
              const [
                'cdn2.steamgriddb.com',
                'cdn.steamgriddb.com',
              ].contains(uri.host)) ||
          (api.scheme == 'http' &&
              api.host == '127.0.0.1' &&
              uri.origin == api.origin));

  Future<ArtworkPage> page(
    int gameId,
    ArtworkKind kind, {
    int page = 0,
    Object? owner,
  }) async {
    if (gameId <= 0 || page < 0 || page > 999)
      throw const RommFailure('Invalid artwork request.');
    final path = switch (kind) {
      ArtworkKind.icon => 'grids',
      ArtworkKind.hero => 'heroes',
      ArtworkKind.logo => 'logos',
    };
    final uri = api.replace(
      path: '${api.path}/$path/game/$gameId',
      queryParameters: {
        if (kind == ArtworkKind.icon) 'dimensions': '512x512,1024x1024',
        'mimes': switch (kind) {
          ArtworkKind.icon => 'image/png',
          ArtworkKind.logo => 'image/png,image/webp',
          ArtworkKind.hero => 'image/png,image/jpeg,image/webp',
        },
        'types': 'static',
        'nsfw': 'false',
        'humor': 'false',
        'epilepsy': 'false',
        'limit': '50',
        'page': '$page',
      },
    );
    final bytes = await _get(
      uri,
      auth: true,
      limit: 2 * 1024 * 1024,
      owner: owner,
    );
    try {
      final j = jsonDecode(utf8.decode(bytes)) as Map;
      if (j['success'] != true || j['data'] is! List)
        throw const FormatException();
      final items = j['data'] as List;
      if (items.length > 50) throw const FormatException();
      final images = <GridArtwork>[];
      for (final item in items) {
        if (item is! Map) continue;
        final id = item['id'], width = item['width'], height = item['height'];
        final url = Uri.tryParse(
          item['url'] is String ? item['url'] as String : '',
        );
        final thumb = Uri.tryParse(
          item['thumb'] is String ? item['thumb'] as String : '',
        );
        final mime =
            item['mime'] ??
            (url?.path.endsWith('.png') == true ? 'image/png' : null);
        if (id is! int ||
            id <= 0 ||
            width is! int ||
            height is! int ||
            width < 1 ||
            height < 1 ||
            width > 8192 ||
            height > 8192 ||
            width * height > 32 * 1024 * 1024 ||
            url == null ||
            thumb == null ||
            !mediaAllowed(url) ||
            !mediaAllowed(thumb) ||
            !['image/png', 'image/jpeg', 'image/webp'].contains(mime) ||
            (kind == ArtworkKind.icon &&
                (width != height || mime != 'image/png')) ||
            (kind == ArtworkKind.hero && width <= height) ||
            (kind == ArtworkKind.logo &&
                !['image/png', 'image/webp'].contains(mime)) ||
            (item['tags'] is List &&
                (item['tags'] as List).any(
                  (v) => ['nsfw', 'humor', 'epilepsy'].contains(v),
                )))
          continue;
        final name = item['author'] is Map
            ? (item['author'] as Map)['name']
            : null;
        images.add(
          GridArtwork(
            id: id,
            kind: kind,
            url: url,
            thumb: thumb,
            width: width,
            height: height,
            mime: mime as String,
            author: name is String ? name : 'SteamGridDB artist',
          ),
        );
      }
      final total = j['total'];
      return ArtworkPage(
        images,
        total is int ? (page + 1) * 50 < total : items.length == 50,
      );
    } on FormatException {
      throw const RommFailure(
        'SteamGridDB returned an invalid artwork catalogue.',
      );
    } on TypeError {
      throw const RommFailure(
        'SteamGridDB returned an invalid artwork catalogue.',
      );
    }
  }

  Future<Uint8List> image(Uri uri, {bool thumbnail = false, Object? owner}) {
    if (!mediaAllowed(uri))
      throw const RommFailure(
        'SteamGridDB returned an unsupported image address.',
      );
    return _get(
      uri,
      auth: false,
      limit: (thumbnail ? 1 : 24) * 1024 * 1024,
      owner: owner,
    );
  }

  Future<Uint8List> _get(
    Uri uri, {
    required bool auth,
    required int limit,
    Object? owner,
  }) async {
    if (closed || _cancelledOwners.contains(owner))
      throw const RommFailure('Artwork selection was closed.');
    HttpClientRequest? request;
    var cancelled = false;
    final operation = () async {
      request = await _http.getUrl(uri);
      if (closed || cancelled || _cancelledOwners.contains(owner)) {
        request!.abort();
        throw const RommFailure('Artwork selection was closed.');
      }
      if (owner != null) _requests[request!] = owner;
      request!.followRedirects = false;
      if (auth)
        request!.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request!.headers.set(
        HttpHeaders.acceptHeader,
        auth ? 'application/json' : 'image/png,image/jpeg,image/webp',
      );
      final response = await request!.close();
      if (response.statusCode != 200) {
        final status = response.statusCode;
        request!.abort();
        throw RommFailure(switch (status) {
          401 || 403 => 'SteamGridDB did not accept the API key. Update it in Broomm settings.',
          404 =>
            'No artwork catalogue was found for this mapped SteamGridDB game.',
          429 => 'SteamGridDB is busy. Wait a moment, then retry.',
          >= 300 && < 400 =>
            'SteamGridDB redirected this request. Artwork was not downloaded.',
          _ =>
            'SteamGridDB could not load artwork (HTTP $status). Retry or keep the current artwork.',
        }, status: status);
      }
      final mime = response.headers.contentType?.mimeType;
      if ((!auth &&
              !['image/png', 'image/jpeg', 'image/webp'].contains(mime)) ||
          (auth && mime != 'application/json')) {
        request!.abort();
        throw const RommFailure(
          'SteamGridDB returned an unsupported response type.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      var count = 0;
      await for (final chunk in response) {
        count += chunk.length;
        if (count > limit) {
          request!.abort();
          throw const RommFailure(
            'This artwork exceeds the supported size. Choose another image.',
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
            'SteamGridDB took too long to respond. Retry or keep the current artwork.',
          );
        },
      );
    } on IOException {
      throw const RommFailure(
        'SteamGridDB could not be reached. Check your connection and retry.',
      );
    } finally {
      if (request != null) _requests.remove(request);
    }
  }

  void close() {
    closed = true;
    _http.close(force: true);
    _requests.clear();
    _cancelledOwners.clear();
  }
}

class ArtworkDownload {
  const ArtworkDownload(this.art, this.bytes);
  final GridArtwork art;
  final Uint8List bytes;
}

class HomeArtwork {
  const HomeArtwork({
    this.icon,
    this.hero,
    this.logo,
    this.iconCredit,
    this.heroCredit,
    this.logoCredit,
  });
  final String? icon, hero, logo, iconCredit, heroCredit, logoCredit;
}
