part of 'model.dart';

extension ShellCloudSaves on ShellModel {
  CloudSaveStatus cloudStatus(int id) =>
      _cloudStatus[id] ?? CloudSaveStatus.waiting;

  Future<void> refreshCloudStatus() async {
    final s = server, p = profile, generation = _context;
    if (s == null || p == null || disposed) return;
    final revision = ++_cloudStatusRevision;
    final statuses = <int, CloudSaveStatus>{};
    for (final entry in List<InstalledGame>.of(installed)) {
      final platform = launchPlatform(entry.game);
      final androidEmulator = isAndroid
          ? androidEmulators
                .where((e) => e.id == platform?.emulatorId)
                .firstOrNull
          : null;
      statuses[entry.game.id] =
          platform == null ||
              isAndroid &&
                  (androidEmulator == null ||
                      !android.progressSupported(androidEmulator) ||
                      android.tree(p.id, androidEmulator) == null)
          ? CloudSaveStatus.attention
          : await readCloudSaveStatus(
              storage.directory,
              s.id,
              p.id,
              entry.game.id,
            );
      if (generation != _context ||
          revision != _cloudStatusRevision ||
          disposed)
        return;
    }
    _cloudStatus
      ..clear()
      ..addAll(statuses);
    _emit();
  }

  Future<CloudGame> cloudGame(
    int id, {
    ResolvedSession? resolved,
    String? androidRom,
  }) async {
    final s = server, p = profile, c = client, entry = installation(id);
    if (s == null ||
        p == null ||
        c == null ||
        entry == null ||
        entry.removing ||
        entry.problem != null)
      throw const RommFailure('Choose a profile and an installed game first.');
    final platform = launchPlatform(entry.game);
    if (platform == null)
      throw UnsupportedError(
        'Cloud saves are not supported for this platform yet.',
      );
    final cached = _cloudGames[id];
    if (resolved == null &&
        !isAndroid &&
        androidRom == null &&
        cached != null &&
        cached.profile == p.id &&
        identical(cached.client, c))
      return cached;
    if (resolved == null) {
      final files = gameCandidates(
        platform,
        await library.contentFiles(entry, excludeAddons: true),
      );
      if (files.length != 1 && androidRom == null)
        throw StateError(
          'Launch this game once and choose its game file before managing cloud saves.',
        );
      if (isAndroid) {
        if (androidRom != null && !files.contains(androidRom))
          throw StateError(
            'The selected Android ROM is outside this game’s installation.',
          );
        final emulator = androidEmulators.singleWhere(
          (e) => e.id == platform.emulatorId,
        );
        final layout = await androidProgressLayout(
          android,
          p.id,
          emulator,
          platform,
          androidRom ?? files.single,
        );
        final result = CloudGame(
          server: s.id,
          profile: p.id,
          user: p.userId,
          rom: id,
          client: c,
          layout: layout,
        );
        _cloudGames[id] = result;
        return result;
      }
      resolved = await emulators.resolveProgress(
        launchDescriptor(entry.game, platform, files.single),
        p.id,
      );
    }
    final layout = await gameProgressLayout(resolved, platform.slug);
    if (profile != p || client != c)
      throw StateError('The active profile changed.');
    final result = CloudGame(
      server: s.id,
      profile: p.id,
      user: p.userId,
      rom: id,
      client: c,
      layout: layout,
    );
    _cloudGames[id] = result;
    return result;
  }

  Future<T?> cloudAction<T>(Future<T> Function() action) async {
    if (isAndroid) await android.ensureNoWriters();
    if (isAndroid && await androidSession.pending() != null)
      throw StateError(
        'Close the Android emulator and finish its session before managing cloud saves.',
      );
    if (busy || gameActive || downloading || _cloudWork != null)
      throw StateError(
        'Finish the current game, download or save operation first.',
      );
    busy = true;
    _emit();
    T? value;
    final work = () async {
      try {
        value = await cloud.idle(action);
      } catch (e) {
        showNotice(progressFailure(e), problem: true);
        rethrow;
      }
    }();
    _cloudWork = work;
    try {
      await work;
      return value;
    } finally {
      if (identical(_cloudWork, work)) _cloudWork = null;
      busy = false;
      await refreshCloudStatus();
      _emit();
    }
  }

  Future<void> finishCloud() async {
    _cloudCancelled = true;
    cloud.cancel();
    try {
      await _cloudWork;
    } catch (_) {
      /* Owning boundary reports the failure. */
    }
  }

  Future<void> retryCloud() async {
    if (!authenticated ||
        busy ||
        gameActive ||
        downloading ||
        emulators.busy ||
        _stoppingDownloads ||
        _cloudWork != null ||
        disposed)
      return;
    // Reserve the worker before any directory/network await. Repeated UI/timer
    // triggers share this guard, and account/launch changes can cancel it.
    final done = Completer<void>();
    final work = done.future;
    _cloudWork = work;
    _cloudCancelled = false;
    try {
      await _retryCloud();
    } catch (e) {
      if (disposed || !authenticated) return;
      final message =
          'The cloud-save queue could not be read. ${progressFailure(e)}';
      if (_cloudIssuesShown.add('queue:$message'))
        showNotice(message, problem: true);
    } finally {
      if (identical(_cloudWork, work)) _cloudWork = null;
      done.complete();
      await refreshCloudStatus();
    }
  }

  Future<void> _retryCloud() async {
    if (!authenticated ||
        busy ||
        gameActive ||
        downloading ||
        _cloudCancelled ||
        disposed)
      return;
    if (isAndroid && await androidSession.pending() != null) return;
    final s = server!, p = profile!, c = client!;
    final relative = 'cloud-saves/${s.id}/${p.id}';
    final ids = <int>{for (final entry in installed) entry.game.id};
    if (await progressExists('${storage.directory.path}/$relative')) {
      final probe = await progressFile(storage.directory, '$relative/.probe');
      await for (final entry in probe.parent.list(followLinks: false)) {
        if (entry is! Directory) continue;
        final id = int.tryParse(
          entry.uri.pathSegments.where((s) => s.isNotEmpty).last,
        );
        if (id != null && id > 0) ids.add(id);
        if (ids.length > 10000)
          throw const FormatException('Too many pending cloud-save records');
      }
    }
    final ordered = ids.toList()..sort();
    final start = _cloudRetryCursor;
    var processed = 0;
    for (var offset = 0; offset < ordered.length; offset++) {
      if (busy ||
          gameActive ||
          downloading ||
          emulators.busy ||
          _cloudCancelled ||
          client != c ||
          profile != p ||
          disposed)
        return;
      final position = (start + offset) % ordered.length,
          id = ordered[position];
      try {
        final directory = '$relative/$id';
        final Map<String, dynamic> state;
        if (await progressExists('${storage.directory.path}/$directory')) {
          final file = await progressFile(
            storage.directory,
            '$directory/state.json',
          );
          state = await progressExists(file.path)
              ? await progressJson(file)
              : {};
        } else {
          state = {};
        }
        if (busy ||
            gameActive ||
            _cloudCancelled ||
            client != c ||
            profile != p ||
            disposed)
          return;
        final initial = state['synced'] == null;
        if (!initial && state['pending'] != true && state['active'] != true)
          continue;
        if (state['conflict'] != null || state['unclean'] == true) {
          _cloudIssue(
            s.id,
            p.id,
            id,
            'Cloud saves need a progress choice. Open this game’s Cloud saves menu; local progress is retained.',
          );
          continue;
        }
        // A retained snapshot can retry after ROM/emulator removal. A game
        // without any snapshot needs a verified native save boundary first.
        final entry = installation(id);
        final platform = entry == null ? null : launchPlatform(entry.game);
        final bootstrap =
            !isAndroid &&
            initial &&
            state['active'] != true &&
            entry != null &&
            !entry.removing &&
            entry.problem == null &&
            platform != null &&
            emulators.readyFor(platform.emulator, platform.slug);
        if (isAndroid && state['active'] == true) {
          _cloudIssue(
            s.id,
            p.id,
            id,
            'An interrupted Android session needs review before cloud sync. Progress was kept.',
          );
          continue;
        }
        if (!bootstrap && state['local'] == null && state['active'] != true)
          continue;
        _cloudRetryCursor = (position + 1) % ordered.length;
        await cloud.idle(() async {
          if (_cloudCancelled || client != c || profile != p || disposed)
            return;
          if (bootstrap) {
            final game = await cloudGame(id);
            if (_cloudCancelled || client != c || profile != p || disposed)
              return;
            await cloud.sync(game);
          } else {
            await cloud.retryPending(
              server: s.id,
              profile: p.id,
              user: p.userId,
              rom: id,
              client: c,
            );
          }
        });
        _cloudIssuesShown.removeWhere(
          (key) => key.startsWith('${s.id}:${p.id}:$id:'),
        );
        _emit();
      } catch (e) {
        if (_cloudCancelled) return;
        if (client == c && profile == p && !disposed)
          _cloudIssue(s.id, p.id, id, progressFailure(e));
        // A disconnected server should not cause a burst across the library.
        if (e is RommFailure) return;
      }
      if (++processed >= 12)
        return; // Bounded catch-up; timer handles the rest.
    }
  }

  void _cloudIssue(String server, String profile, int id, String message) {
    if (!_cloudIssuesShown.add('$server:$profile:$id:$message')) return;
    if (_cloudIssuesShown.length > 128)
      _cloudIssuesShown.remove(_cloudIssuesShown.first);
    final title = installation(id)?.game.name ?? 'Game $id';
    showNotice('$title: $message', problem: true);
  }
}
