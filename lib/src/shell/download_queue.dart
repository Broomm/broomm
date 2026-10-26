import 'dart:async';
import 'dart:io';

import '../progress/files.dart';
import '../romm/models.dart';
import 'library.dart';

enum DownloadState { queued, active, failed }

class DownloadJob {
  DownloadJob(
    this.game, {
    this.addons = false,
    this.state = DownloadState.queued,
    this.problem,
  });
  RommGame game;
  final bool addons;
  DownloadState state;
  String? problem;
  DownloadProgress? progress;
  Completer<void> done = Completer<void>();
  Map<String, dynamic> toJson() => {
    'game': game.toJson(),
    'addons': addons,
    'state': state.name,
    if (problem != null) 'problem': problem,
  };
}

class DownloadQueueInUse implements Exception {
  const DownloadQueueInUse();
  @override
  String toString() =>
      'Another Broomm instance is managing this account’s downloads. Quit that instance, then refresh Downloads to retry or remove them.';
}

/// One queue writer per saved account, including independent app processes.
/// No credentials or temporary content paths are serialized here.
class DownloadQueueStore {
  DownloadQueueStore(Directory data, String server, String profile)
    : root = Directory('${data.path}/downloads/$server/$profile') {
    if (![server, profile].every((v) => RegExp(r'^[a-f0-9]{32}$').hasMatch(v)))
      throw const FormatException('Invalid download owner');
  }
  final Directory root;
  RandomAccessFile? _lock;
  String? _key;
  static final _held = <String>{};
  Future<List<DownloadJob>> open() async {
    if (_lock != null) throw StateError('This queue is already open');
    await progressDirectory(root);
    final key = await root.resolveSymbolicLinks();
    if (!_held.add(key)) throw const DownloadQueueInUse();
    _key = key;
    try {
      final file = await progressFile(root, 'queue.lock');
      _lock = await file.open(mode: FileMode.append);
      try {
        await _lock!.lock(FileLock.exclusive);
      } on FileSystemException catch (e) {
        if ([11, 13, 32, 33, 35].contains(e.osError?.errorCode))
          throw const DownloadQueueInUse();
        rethrow;
      }
      return await readSnapshot(interrupted: true);
    } catch (_) {
      await close();
      rethrow;
    }
  }

  /// Atomic queue checkpoints remain readable while another process owns the
  /// writer. Observing them never turns its live jobs into interrupted jobs.
  Future<List<DownloadJob>> readSnapshot({bool interrupted = false}) async {
    final record = File('${root.path}/queue.json');
    if (!await progressExists(record.path)) return [];
    await progressFile(root, 'queue.json');
    final j = await progressJson(record);
    if (j['version'] != 1 ||
        j['jobs'] is! List ||
        (j['jobs'] as List).length > 200)
      throw const FormatException(
        'Unrecognized download queue; existing data was kept',
      );
    final jobs = <DownloadJob>[];
    for (final item in j['jobs'] as List) {
      final v = item as Map;
      final game = RommGame.fromJson(
        (v['game'] as Map).cast<String, dynamic>(),
      );
      if (game.id < 1 ||
          jobs.any((j) => j.game.id == game.id) ||
          !DownloadState.values.any((s) => s.name == v['state']) ||
          v['addons'] is! bool ||
          (v['problem'] != null && v['problem'] is! String))
        throw const FormatException('Conflicting download identities');
      jobs.add(
        DownloadJob(
          game,
          addons: v['addons'] == true,
          state: interrupted
              ? DownloadState.failed
              : DownloadState.values.firstWhere((s) => s.name == v['state']),
          problem:
              v['problem'] as String? ??
              (interrupted
                  ? 'Download interrupted. Retry or remove it.'
                  : null),
        ),
      );
    }
    return jobs;
  }

  Future<void> save(List<DownloadJob> jobs) async {
    if (_lock == null)
      throw StateError('The download queue is not owned by this app');
    await progressWrite(File('${root.path}/queue.json'), {
      'version': 1,
      'jobs': jobs.map((j) => j.toJson()).toList(),
    });
  }

  Future<void> close() async {
    final lock = _lock;
    _lock = null;
    final key = _key;
    _key = null;
    try {
      await lock?.close();
    } finally {
      if (key != null) _held.remove(key);
    }
  }
}
