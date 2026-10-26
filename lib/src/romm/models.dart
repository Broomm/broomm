class RommFailure implements Exception {
  const RommFailure(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

Uri normalizeServer(String value) {
  final text = value.trim();
  if (hasUnsafeUrlPath(text))
    throw const RommFailure('The server address contains an invalid path.');
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      text.contains(RegExp(r'[\x00-\x20\\]')) ||
      uri.pathSegments.any((p) => p == '..' || p == '.')) {
    throw const RommFailure(
      'Enter a server address such as https://romm.example.com.',
    );
  }
  return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
}

bool hasUnsafeUrlPath(String value) {
  try {
    final decoded = Uri.decodeComponent(
      value.split('?').first.split('#').first,
    );
    return decoded.contains(RegExp(r'[\x00\\]')) ||
        RegExp(r'(^|/)\.{1,2}(/|$)').hasMatch(decoded);
  } on FormatException {
    return true;
  }
}

class RommUser {
  const RommUser(this.id, this.name);
  factory RommUser.fromJson(Map<String, dynamic> j) {
    if (j['id'] is! int || j['username'] is! String || j['enabled'] == false) {
      throw const RommFailure('RomM did not return an enabled account.');
    }
    return RommUser(j['id'] as int, j['username'] as String);
  }
  final int id;
  final String name;
}

class RommPlatform {
  const RommPlatform(this.id, this.name, this.slug, this.count);
  factory RommPlatform.fromJson(Map<String, dynamic> j) => RommPlatform(
    j['id'] as int,
    (j['display_name'] ?? j['name']) as String,
    j['slug'] as String,
    j['rom_count'] as int? ?? 0,
  );
  final int id, count;
  final String name, slug;
}

class RommFirmware {
  const RommFirmware(this.id, this.platformId, this.name, this.bytes, this.md5);
  factory RommFirmware.fromJson(Map<String, dynamic> j) {
    final name = j['file_name'], bytes = j['file_size_bytes'];
    if (j['id'] is! int ||
        (j['id'] as int) < 1 ||
        j['platform_id'] is! int ||
        name is! String ||
        name.isEmpty ||
        name.contains(RegExp(r'[\x00-\x1f/\\]')) ||
        bytes is! int ||
        bytes < 1 ||
        bytes > 1024 * 1024 * 1024 ||
        j['missing_from_fs'] == true)
      throw const RommFailure('RomM returned an invalid firmware record.');
    final hash = j['md5_hash'] as String?;
    if (hash == null || !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hash))
      throw const RommFailure(
        'The RomM firmware has no usable checksum. Rescan it in RomM.',
      );
    return RommFirmware(
      j['id'] as int,
      j['platform_id'] as int,
      name,
      bytes,
      hash.toLowerCase(),
    );
  }
  final int id, platformId, bytes;
  final String name, md5;
}

class RommGame {
  const RommGame({
    required this.id,
    required this.name,
    required this.platformId,
    required this.platform,
    this.summary = '',
    this.cover,
    this.backdrop,
    this.genres = const [],
    this.year,
    this.rating,
    this.bytes = 0,
    this.fsName = '',
    this.fullPath = '',
    this.files = const [],
    this.platformSlug = '',
    this.sgdbId,
    this.siblings = const [],
    this.regions = const [],
    this.languages = const [],
    this.revision,
  });
  factory RommGame.fromJson(Map<String, dynamic> j) {
    final meta = j['metadatum'] as Map? ?? const {};
    final release = meta['first_release_date'] as int?;
    final screenshots = j['merged_screenshots'] as List? ?? const [];
    return RommGame(
      id: j['id'] as int,
      name: (j['name'] as String?)?.trim().isNotEmpty == true
          ? j['name'] as String
          : (j['fs_name_no_ext'] ?? j['fs_name'] ?? 'Untitled game') as String,
      platformId: j['platform_id'] as int,
      sgdbId: j['sgdb_id'] is int && (j['sgdb_id'] as int) > 0
          ? j['sgdb_id'] as int
          : null,
      platformSlug: j['platform_slug'] as String? ?? '',
      siblings: (j['sibling_roms'] as List? ?? const [])
          .map((v) => RommVariant.fromJson((v as Map).cast<String, dynamic>()))
          .toList(),
      regions: (j['regions'] as List? ?? const []).cast<String>(),
      languages: (j['languages'] as List? ?? const []).cast<String>(),
      revision: j['revision'] as String?,
      platform:
          (j['platform_display_name'] ??
                  j['platform_slug'] ??
                  'Unknown platform')
              as String,
      summary: j['summary'] as String? ?? '',
      cover: (j['path_cover_large'] ?? j['path_cover_small']) as String?,
      backdrop: screenshots.isEmpty ? null : screenshots.first as String?,
      genres: (meta['genres'] as List? ?? const []).cast<String>(),
      year: release == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              release * 1000,
              isUtc: true,
            ).year,
      rating: (meta['average_rating'] as num?)?.toDouble(),
      bytes: j['fs_size_bytes'] as int? ?? 0,
      fsName: j['fs_name'] as String? ?? '',
      fullPath: j['full_path'] as String? ?? '',
      files: (j['files'] as List? ?? const [])
          .map((v) => RommFile.fromJson((v as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
  final int id, platformId, bytes;
  final int? sgdbId;
  final List<RommVariant> siblings;
  final List<String> regions, languages;
  final String? revision;
  List<RommVariant> get versions {
    final seen = <int>{id};
    return [
      RommVariant(id, name, fsName),
      ...siblings.where((v) => seen.add(v.id)),
    ];
  }

  final String name, platform, summary;
  final String? cover, backdrop;
  final List<String> genres;
  final int? year;
  final double? rating;
  final String fsName, fullPath;
  final List<RommFile> files;
  final String platformSlug;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'platform_id': platformId,
    'sgdb_id': sgdbId,
    'platform_display_name': platform,
    'platform_slug': platformSlug,
    'sibling_roms': siblings.map((v) => v.toJson()).toList(),
    'regions': regions,
    'languages': languages,
    'revision': revision,
    'summary': summary,
    'path_cover_large': cover,
    'merged_screenshots': [if (backdrop != null) backdrop],
    'fs_size_bytes': bytes,
    'fs_name': fsName,
    'full_path': fullPath,
    'metadatum': {
      'genres': genres,
      'average_rating': rating,
      if (year != null)
        'first_release_date':
            DateTime.utc(year!).millisecondsSinceEpoch ~/ 1000,
    },
  };
}

/// RomM's permission-filtered sibling identities. Filename tags distinguish
/// releases without guessing that games sharing a display name are identical.
class RommVariant {
  const RommVariant(this.id, this.name, this.fileName);
  factory RommVariant.fromJson(Map<String, dynamic> j) {
    if (j['id'] is! int || (j['id'] as int) < 1)
      throw const FormatException('Invalid ROM version identity');
    return RommVariant(
      j['id'] as int,
      j['name'] as String? ?? 'Game version',
      j['fs_name_no_ext'] as String? ?? j['fs_name_no_tags'] as String? ?? '',
    );
  }
  final int id;
  final String name, fileName;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fs_name_no_ext': fileName,
  };
}

class RommFile {
  const RommFile({
    required this.id,
    required this.romId,
    required this.name,
    required this.fullPath,
    required this.bytes,
    this.crc,
    this.rawCrc = true,
    this.category,
    this.modified,
    this.sha1,
  });
  factory RommFile.fromJson(Map<String, dynamic> j) => RommFile(
    id: j['id'] as int,
    romId: j['rom_id'] as int,
    name: j['file_name'] as String,
    fullPath: j['full_path'] as String,
    bytes: j['file_size_bytes'] as int,
    crc: j['crc_hash'] as String?,
    category: j['category'] as String?,
    modified: (j['last_modified'] ?? j['updated_at']) as String?,
    sha1: j['sha1_hash'] as String?,
    // RomM hashes decompressed members for some archives. Those values cannot
    // be compared with the downloaded container's raw-byte CRC.
    rawCrc:
        j['archive_members'] == null &&
        !RegExp(
          r'\.(zip|7z|rar|gz|bz2|xz|tar|zst)$',
          caseSensitive: false,
        ).hasMatch(j['file_name'] as String),
  );
  final int id, romId, bytes;
  final String name, fullPath;
  final String? crc;
  final bool rawCrc;
  final String? category, modified, sha1;
}

class RommPage {
  const RommPage(this.games, this.total, this.offset, this.limit);
  factory RommPage.fromJson(Map<String, dynamic> j) => RommPage(
    (j['items'] as List)
        .map((v) => RommGame.fromJson((v as Map).cast<String, dynamic>()))
        .toList(),
    j['total'] as int?,
    j['offset'] as int,
    j['limit'] as int,
  );
  final List<RommGame> games;
  final int? total;
  final int offset, limit;
  bool get hasMore =>
      games.length == limit &&
      (total == null || offset + games.length < total!);
}
