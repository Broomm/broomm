part of 'client.dart';

class RommSave {
  const RommSave({
    required this.id,
    required this.romId,
    required this.userId,
    required this.name,
    required this.bytes,
    this.emulator,
    this.slot,
    this.hash,
    this.updated = '',
    this.missing = false,
    this.directory = '',
    this.created = '',
    this.stateAsset = false,
  });
  factory RommSave.fromJson(Map<String, dynamic> j, {bool stateAsset = false}) {
    if (j['id'] is! int ||
        (j['id'] as int) < 1 ||
        j['rom_id'] is! int ||
        (j['rom_id'] as int) < 1 ||
        j['user_id'] is! int ||
        j['file_name'] is! String ||
        j['file_size_bytes'] is! int ||
        (j['file_size_bytes'] as int) < 0 ||
        (j['file_size_bytes'] as int) > 512 * 1024 * 1024)
      throw const RommFailure(
        'RomM returned an invalid save record. Existing progress has been kept.',
      );
    return RommSave(
      id: j['id'] as int,
      romId: j['rom_id'] as int,
      userId: j['user_id'] as int,
      name: j['file_name'] as String,
      bytes: j['file_size_bytes'] as int,
      emulator: j['emulator'] as String?,
      slot: j['slot'] as String?,
      hash: j['content_hash'] as String?,
      updated: j['updated_at'] as String? ?? '',
      missing: j['missing_from_fs'] == true,
      directory: j['file_path'] as String? ?? '',
      created: j['created_at'] as String? ?? '',
      stateAsset: stateAsset,
    );
  }
  final int id, romId, userId, bytes;
  final String name, updated, directory, created;
  final String? emulator, slot, hash;
  final bool missing;
  final bool stateAsset;
  String get folder => directory.replaceAll('\\', '/').split('/').last;
  bool get legacyManaged =>
      !stateAsset &&
      name == 'broomm' &&
      emulator == 'Broomm' &&
      slot == null &&
      (directory.isEmpty || folder == 'Broomm');
  bool get versioned =>
      !stateAsset &&
      slot == 'BROOMM' &&
      emulator == 'Broomm' &&
      RegExp(
        r'^Broomm \[\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\]\.(sav|srm|mcd|ps2|zip)$',
      ).hasMatch(name);
  bool get managed => legacyManaged || versioned;
  bool _sameContents(RommSave other) =>
      id == other.id &&
      romId == other.romId &&
      userId == other.userId &&
      name == other.name &&
      emulator == other.emulator &&
      slot == other.slot &&
      bytes == other.bytes &&
      hash == other.hash &&
      missing == other.missing &&
      directory == other.directory &&
      stateAsset == other.stateAsset;
  String get revision => jsonEncode([
    id,
    romId,
    userId,
    name,
    emulator,
    slot,
    bytes,
    hash,
    updated,
    missing,
    directory,
  ]);
}

mixin RommSaves {
  HttpClient get _http;
  String? get _access;
  bool get _closed;
  Duration get deadline;
  Uri endpoint(String path, [Map<String, String>? query]);
  Future<void> _ensureToken();
  Future<dynamic> _json(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  });
  Future<List<RommSave>> saves(int romId) async {
    final j = await _json('GET', 'api/saves', query: {'rom_id': '$romId'});
    if (j is! List || j.length > 10000)
      throw const RommFailure(
        'RomM returned an incomplete save listing. Existing progress has been kept.',
      );
    final result = j
        .map((e) => RommSave.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    if (result.any((s) => s.romId != romId) ||
        result.map((s) => s.id).toSet().length != result.length)
      throw const RommFailure(
        'RomM returned conflicting save identities. Existing progress has been kept.',
      );
    return result;
  }

  Future<RommSave> save(int id) async => RommSave.fromJson(
    (await _json('GET', 'api/saves/$id') as Map).cast<String, dynamic>(),
  );
  Future<List<RommSave>> states(int romId) async {
    final j = await _json('GET', 'api/states', query: {'rom_id': '$romId'});
    if (j is! List || j.length > 10000)
      throw const RommFailure(
        'RomM returned an incomplete state listing. Progress was kept.',
      );
    final result = j
        .map(
          (e) => RommSave.fromJson(
            (e as Map).cast<String, dynamic>(),
            stateAsset: true,
          ),
        )
        .toList();
    if (result.any((s) => s.romId != romId) ||
        result.map((s) => s.id).toSet().length != result.length)
      throw const RommFailure(
        'RomM returned conflicting state identities. Progress was kept.',
      );
    return result;
  }

  Future<RommSave> state(int id) async => RommSave.fromJson(
    (await _json('GET', 'api/states/$id') as Map).cast<String, dynamic>(),
    stateAsset: true,
  );
  Future<RommSave> renameSave(RommSave save, String name) async =>
      RommSave.fromJson(
        (await _json(
          'PUT',
          'api/saves/${save.id}/file-name',
          body: {'file_name': name},
        ) as Map).cast<String, dynamic>(),
      );
  Future<void> downloadSave(
    RommSave save,
    File destination, {
    required DownloadCancellation cancellation,
    void Function(int)? onProgress,
  }) => _downloadProgressAsset(
    save,
    destination,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  Future<void> downloadState(
    RommSave state,
    File destination, {
    required DownloadCancellation cancellation,
    void Function(int)? onProgress,
  }) => _downloadProgressAsset(
    state,
    destination,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  Future<void> _downloadProgressAsset(
    RommSave save,
    File destination, {
    required DownloadCancellation cancellation,
    void Function(int)? onProgress,
  }) async {
    if (save.missing)
      throw const RommFailure(
        'RomM reports that this save is missing from its storage. Local progress has been kept.',
      );
    HttpClientRequest? request;
    RandomAccessFile? output;
    var stopped = false;
    final timer = Timer(const Duration(minutes: 15), () => request?.abort());
    cancellation.abort = () => request?.abort();
    try {
      cancellation.check();
      await _ensureToken();
      cancellation.check();
      request = await _http
          .getUrl(
            endpoint(
              'api/${save.stateAsset ? 'states' : 'saves'}/${save.id}/content',
              {'optimistic': 'false'},
            ),
          )
          .then((r) {
            if (stopped || cancellation.cancelled || _closed) r.abort();
            return r;
          })
          .timeout(deadline);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_access');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(deadline);
      if (response.statusCode != 200) throw _saveStatus(response.statusCode);
      if (response.contentLength >= 0 && response.contentLength != save.bytes)
        throw const RommFailure(
          'The remote save changed size during download. Retry; existing progress has been kept.',
        );
      await destination.create(exclusive: true);
      output = await destination.open(mode: FileMode.writeOnly);
      var received = 0;
      await for (final chunk in response.timeout(deadline)) {
        cancellation.check();
        received += chunk.length;
        if (received > save.bytes)
          throw const RommFailure('RomM sent more save data than expected.');
        await output.writeFrom(chunk);
        onProgress?.call(received);
      }
      if (received != save.bytes)
        throw const RommFailure(
          'The save transfer was incomplete. Existing progress has been kept.',
        );
      await output.flush();
      cancellation.check();
    } on TimeoutException {
      throw const RommFailure(
        'The cloud-save download stalled. Local progress has been kept.',
      );
    } on IOException {
      cancellation.check();
      throw const RommFailure(
        'Cloud saves could not reach RomM or local storage. Progress has been kept on this device.',
      );
    } finally {
      stopped = true;
      timer.cancel();
      cancellation.abort = null;
      request?.abort();
      await output?.close();
    }
  }

  Future<RommSave> uploadSave(
    int romId,
    File file, {
    required String name,
    RommSave? replace,
    String? slot,
    required DownloadCancellation cancellation,
    void Function(int)? onProgress,
  }) => _uploadProgressAsset(
    romId,
    file,
    name: name,
    replace: replace,
    slot: slot,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  Future<RommSave> uploadState(
    int romId,
    File file, {
    required String name,
    required DownloadCancellation cancellation,
    void Function(int)? onProgress,
  }) => _uploadProgressAsset(
    romId,
    file,
    name: name,
    stateAsset: true,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  Future<RommSave> _uploadProgressAsset(
    int romId,
    File file, {
    required String name,
    RommSave? replace,
    String? slot,
    bool stateAsset = false,
    required DownloadCancellation cancellation,
    void Function(int)? onProgress,
  }) async {
    if (slot != null && (slot != 'BROOMM' || stateAsset || replace != null))
      throw const RommFailure('Invalid Broomm save-slot operation.');
    if (name.isEmpty ||
        utf8.encode(name).length > 200 ||
        name.contains(RegExp(r'[\x00-\x1f\x7f/\\]')) ||
        name == '.' ||
        name == '..')
      throw const RommFailure('Choose a valid save filename.');
    if (replace != null &&
        (replace.romId != romId ||
            replace.name != name ||
            replace.emulator != 'Broomm'))
      throw const RommFailure(
        'The destination save identity changed. Existing progress has been kept.',
      );
    final boundary =
        'broomm-${DateTime.now().microsecondsSinceEpoch}-${file.lengthSync()}';
    final escaped = name.replaceAll('"', r'\"');
    final header = utf8.encode(
      '--$boundary\r\nContent-Disposition: form-data; name="${stateAsset ? 'stateFile' : 'saveFile'}"; filename="$escaped"\r\nContent-Type: application/octet-stream\r\n\r\n',
    );
    final footer = utf8.encode('\r\n--$boundary--\r\n');
    final bytes = await file.length();
    if (bytes > 512 * 1024 * 1024)
      throw const RommFailure(
        'This save exceeds the supported 512 MiB transfer size.',
      );
    final j = await _saveTransfer(
      replace == null ? 'POST' : 'PUT',
      replace == null
          ? 'api/${stateAsset ? 'states' : 'saves'}'
          : 'api/saves/${replace.id}',
      query: replace == null
          ? {
              'rom_id': '$romId',
              'emulator': 'Broomm',
              if (slot != null) 'slot': slot,
              // Slot POST reserves a fresh timestamped filename first. This
              // disables hash deduplication, so changed states can accompany
              // identical native save bytes in a new, independent version.
              // Unslotted backups still refuse existing filenames.
              'overwrite': slot == null ? 'false' : 'true',
              'autocleanup': 'false',
            }
          : null,
      file: file,
      head: header,
      tail: footer,
      length: bytes + header.length + footer.length,
      contentType: ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      ),
      cancellation: cancellation,
      onProgress: onProgress,
    );
    final returned = RommSave.fromJson(
      (j as Map).cast<String, dynamic>(),
      stateAsset: stateAsset,
    );
    // RomM 5.4 serializes the new ORM object's subsecond timestamp in POST,
    // but its database may persist whole seconds. Obtain the stored revision
    // before readback; only that documented precision loss is accepted here.
    final stored = await (stateAsset ? state(returned.id) : save(returned.id));
    final postedTime = DateTime.tryParse(returned.updated);
    final storedTime = DateTime.tryParse(stored.updated);
    final rounded =
        postedTime != null &&
        storedTime != null &&
        storedTime.millisecond == 0 &&
        storedTime.microsecond == 0 &&
        postedTime.microsecondsSinceEpoch ~/ 1000000 ==
            storedTime.microsecondsSinceEpoch ~/ 1000000;
    if (!returned._sameContents(stored) ||
        returned.updated != stored.updated && !rounded)
      throw const RommFailure(
        'The uploaded save identity or contents changed before readback. Local progress and previous versions were kept.',
      );
    return stored;
  }

  RommFailure _saveStatus(int status) => RommFailure(switch (status) {
    401 => 'Cloud saves need a valid sign-in. Local progress has been kept.',
    403 => 'Cloud saves need the assets.write permission. Sign in once again to authorize it, or use a client token with that permission. Local progress has been kept.',
    404 =>
      'This remote save is no longer available. Local progress has been kept.',
    409 => 'The remote save changed or that name is already taken. Existing progress has been kept.',
    413 => 'RomM rejected this save because of its upload size limit. The local snapshot has been kept.',
    >= 300 && < 400 => 'RomM redirected the save request. Credentials were not forwarded; use its final address.',
    _ =>
      'RomM could not complete the save transfer (HTTP $status). Local progress has been kept.',
  }, status: status);

  Future<dynamic> _saveTransfer(
    String method,
    String path, {
    Map<String, String>? query,
    File? file,
    List<int>? head,
    List<int>? tail,
    int? length,
    List<int>? body,
    required ContentType contentType,
    DownloadCancellation? cancellation,
    void Function(int)? onProgress,
  }) async {
    HttpClientRequest? request;
    var stopped = false;
    final timer = Timer(const Duration(minutes: 15), () => request?.abort());
    if (cancellation != null) cancellation.abort = () => request?.abort();
    try {
      cancellation?.check();
      await _ensureToken();
      cancellation?.check();
      request = await _http
          .openUrl(method, endpoint(path, query))
          .then((r) {
            if (stopped || cancellation?.cancelled == true || _closed)
              r.abort();
            return r;
          })
          .timeout(deadline);
      request.followRedirects = false;
      request.headers.contentType = contentType;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_access');
      request.contentLength = length ?? body?.length ?? 0;
      if (body != null) request.add(body);
      if (file != null) {
        request.add(head!);
        var received = 0;
        await request
            .addStream(
              file.openRead().map((chunk) {
                cancellation?.check();
                received += chunk.length;
                onProgress?.call(received);
                return chunk;
              }),
            )
            .timeout(const Duration(minutes: 15));
        request.add(tail!);
      }
      final response = await request.close().timeout(deadline);
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw _saveStatus(response.statusCode);
      final bytes = BytesBuilder(copy: false);
      var size = 0;
      await for (final chunk in response.timeout(deadline)) {
        size += chunk.length;
        if (size > 12 * 1024 * 1024)
          throw const RommFailure('RomM returned an oversized save response.');
        bytes.add(chunk);
      }
      cancellation?.check();
      return size == 0 ? null : jsonDecode(utf8.decode(bytes.takeBytes()));
    } on TimeoutException {
      throw const RommFailure(
        'The save transfer timed out. Its local snapshot is kept; retry to confirm whether RomM received it.',
      );
    } on IOException {
      cancellation?.check();
      throw const RommFailure(
        'The save transfer could not finish. Its local snapshot is kept; retry to confirm whether RomM received it.',
      );
    } finally {
      stopped = true;
      timer.cancel();
      if (cancellation != null) cancellation.abort = null;
      request?.abort();
    }
  }
}
