part of 'model.dart';

extension DownloadsModel on ShellModel {
  int get homeAppCount => homeApps.length;
  int get lastHomeIndex => homeAppCount - 1 + installed.length;
  DownloadJob? queuedGame(int id) =>
      downloads.where((j) => j.game.id == id).firstOrNull;

  Future<void> loadDownloads({bool create = false}) {
    if (_queueLoading case final work?) return work;
    final work = _openDownloads(create: create);
    _queueLoading = work;
    return work.whenComplete(() {
      if (identical(_queueLoading, work)) _queueLoading = null;
    });
  }

  Future<void> _openDownloads({bool create = false}) async {
    if (_queueStore != null || !authenticated) return;
    final revision = _context;
    final store = DownloadQueueStore(
      storage.directory,
      server!.id,
      profile!.id,
    );
    if (!create && !await File('${store.root.path}/queue.json').exists())
      return;
    try {
      final loaded = await store.open();
      if (revision != _context || disposed) {
        await store.close();
        return;
      }
      _queueStore = store;
      downloadsReadOnly = false;
      downloadQueueNotice = null;
      downloadError = null;
      final wasEmpty = downloads.isEmpty;
      downloads.clear();
      downloads.addAll(loaded);
      if (wasEmpty && downloads.isNotEmpty && homeIndex >= downloadHomeIndex)
        ++homeIndex;
      if (!wasEmpty && downloads.isEmpty && homeIndex >= downloadHomeIndex)
        --homeIndex;
      _emit();
    } on DownloadQueueInUse catch (e) {
      try {
        final snapshot = await store.readSnapshot();
        if (revision != _context || disposed) return;
        final wasEmpty = downloads.isEmpty;
        downloads
          ..clear()
          ..addAll(snapshot);
        if (wasEmpty && downloads.isNotEmpty && homeIndex >= downloadHomeIndex)
          ++homeIndex;
        if (!wasEmpty && downloads.isEmpty && homeIndex >= downloadHomeIndex)
          --homeIndex;
        downloadsReadOnly = true;
        downloadQueueNotice = e.toString();
        downloadError = null;
      } catch (readError) {
        if (revision != _context || disposed) return;
        downloadError = 'The saved download list could not be read. $readError';
      }
      _emit();
    } catch (e) {
      if (revision != _context || disposed) return;
      downloadError = 'The download queue could not be opened. $e';
      _emit();
    }
  }

  Future<void> _saveDownloads() {
    final before = _queueWrite ?? Future<void>.value();
    final work = before.catchError((Object _) {}).then((_) async {
      await _queueStore?.save(downloads);
    });
    _queueWrite = work;
    return work.whenComplete(() {
      if (identical(_queueWrite, work)) _queueWrite = null;
    });
  }

  Future<void> enqueueDownload(RommGame game, {bool addons = false}) async {
    if (!authenticated ||
        applicationUpdating ||
        disposed ||
        gameActive ||
        _stoppingDownloads ||
        downloads.length >= 200)
      return;
    final generation = _context;
    await finishCloud();
    if (generation != _context ||
        applicationUpdating ||
        !authenticated ||
        disposed ||
        gameActive ||
        _stoppingDownloads)
      return;
    if (downloadsReadOnly) {
      await loadDownloads(create: true);
      if (generation != _context || disposed) return;
      if (downloadsReadOnly) {
        showNotice(downloadQueueNotice!, problem: true);
        return;
      }
    }
    final existing = queuedGame(game.id);
    if (existing != null && existing.state != DownloadState.failed)
      return existing.done.future;
    if (_queueStore == null) await loadDownloads(create: true);
    if (generation != _context || disposed || _stoppingDownloads) return;
    if (_queueStore == null) return;
    final registered = queuedGame(game.id);
    if (registered != null && registered.state != DownloadState.failed)
      return registered.done.future;
    final wasEmpty = downloads.isEmpty;
    if (registered != null) downloads.remove(registered);
    final job = DownloadJob(game, addons: addons);
    downloads.add(job);
    if (wasEmpty && homeIndex >= downloadHomeIndex) ++homeIndex;
    try {
      await _saveDownloads();
    } catch (e) {
      downloads.remove(job);
      if (registered != null) downloads.add(registered);
      downloadError = 'The download could not be queued. $e';
      _emit();
      return;
    }
    if (!addons && game.sgdbId != null) artworkRequests.add(game);
    _emit();
    _startQueue();
    await job.done.future;
  }

  void _startQueue() {
    if (applicationUpdating ||
        _stoppingDownloads ||
        downloadsReadOnly ||
        !authenticated ||
        disposed)
      return;
    while (_downloadWorkers.length < preferences.maxDownloads) {
      final job = downloads
          .where((j) => j.state == DownloadState.queued)
          .firstOrNull;
      if (job == null) break;
      job.state = DownloadState.active;
      job.problem = null;
      final cancellation = DownloadCancellation();
      _downloadCancellations[job] = cancellation;
      final generation = _context;
      final work =
          () async {
            try {
              await _saveDownloads();
              cancellation.check();
              if (job.addons) {
                final entry = installation(job.game.id);
                if (entry == null)
                  throw StateError('The game is no longer installed.');
                await _updateAddons(entry, cancellation, job);
              } else {
                await _install(job.game, cancellation, job);
              }
            } catch (e) {
              job.problem = 'Download could not finish. $e';
            }
            if (generation != _context || disposed) return;
            if (job.problem == null && !cancellation.cancelled) {
              downloads.remove(job);
              if (downloads.isEmpty && homeIndex >= downloadHomeIndex)
                --homeIndex;
            } else {
              job.state = DownloadState.failed;
              job.problem ??=
                  'Download cancelled. Retry or remove downloaded data.';
            }
            try {
              await _saveDownloads();
            } catch (e) {
              downloadError = 'The queue checkpoint could not be saved. $e';
            }
          }().whenComplete(() {
            _downloadWorkers.remove(job);
            _downloadCancellations.remove(job);
            _downloadWork = _downloadWorkers.isEmpty
                ? null
                : Future.wait(_downloadWorkers.values);
            if (!job.done.isCompleted) job.done.complete();
            _emit();
            _startQueue();
            if (!downloading && !_stoppingDownloads) unawaited(retryCloud());
          });
      _downloadWorkers[job] = work;
      _downloadWork = Future.wait(_downloadWorkers.values);
    }
    _emit();
  }

  // Reserve the next native-content mutation before yielding. Cancellation of a
  // waiter does not let a later installer overtake the still-running writer.
  Future<T> _serializedAddon<T>(
    DownloadCancellation cancellation,
    Future<T> Function() action,
  ) {
    var started = false;
    final work = (_addonTail ?? Future<void>.value()).then((_) {
      cancellation.check();
      started = true;
      return action();
    });
    final tail = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _addonTail = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_addonTail, tail)) _addonTail = null;
      }),
    );
    return Future.any([
      work,
      cancellation.whenCancelled.then<T>((_) {
        // An admitted native writer must finish its cancellation/rollback before
        // the account can close or another operation can use its progress.
        if (started) return work;
        throw const DownloadCancelled();
      }),
    ]);
  }

  Future<void> retryDownload(DownloadJob job) async {
    if (downloadsReadOnly) return;
    if (!downloads.contains(job) || job.state != DownloadState.failed) return;
    final generation = _context;
    await finishCloud();
    if (generation != _context ||
        disposed ||
        gameActive ||
        _stoppingDownloads ||
        !downloads.contains(job) ||
        job.state != DownloadState.failed)
      return;
    job.state = DownloadState.queued;
    job.problem = null;
    job.done = Completer<void>();
    await _saveDownloads();
    _emit();
    _startQueue();
  }

  Future<void> removeDownload(DownloadJob job) async {
    if (downloadsReadOnly) return;
    if (!downloads.contains(job) || job.state == DownloadState.active) return;
    await _libraryWork;
    // Failed transfers already dispose their private payload stage. Never remove
    // a verified base game when only its later add-on phase failed.
    if (!job.addons)
      await library.discardDownloadArtwork(server!.id, job.game.id);
    if (!job.addons)
      installed = [
        for (final g in installed)
          if (g.game.id == job.game.id)
            InstalledGame(
              g.game,
              g.directory,
              g.userId,
              problem: g.problem,
              removing: g.removing,
            )
          else
            g,
      ];
    artworkRequests.removeWhere((g) => g.id == job.game.id);
    downloads.remove(job);
    if (downloads.isEmpty && homeIndex >= downloadHomeIndex) --homeIndex;
    await _saveDownloads();
    if (!job.done.isCompleted) job.done.complete();
    _emit();
  }
}
