import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/steamgrid.dart';

import 'shell_model_test.dart' show FixtureRomm, settleModel;
import 'remembered_signin_test.dart' show MemoryCredentials;
import 'library_download_test.dart' show fixture, bytes;
import 'support/artwork_fixtures.dart' show artworkPng;

RommGame queuedFixture(int id) {
  final f = fixture(id: id);
  return RommGame(
    id: id,
    name: f.name,
    platformId: f.platformId,
    platform: f.platform,
    bytes: f.bytes,
    fsName: f.fsName,
    fullPath: f.fullPath,
    files: f.files,
    sgdbId: 10,
  );
}

class QueuedRomm extends FixtureRomm {
  QueuedRomm(super.server);
  final started = Completer<void>(), release = Completer<void>();
  final secondStarted = Completer<void>(), releaseSecond = Completer<void>();
  bool holdSecond = false;
  final order = <int>[];
  bool failFirst = false;
  @override
  Future<RommGame> game(int id) async => queuedFixture(id);
  @override
  Future<void> downloadFile(
    RommFile file,
    File target, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    order.add(file.romId);
    if (file.romId == 1) {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
    if (file.romId == 2 && holdSecond) {
      secondStarted.complete();
      await releaseSecond.future;
    }
    cancellation.check();
    if (failFirst && file.romId == 1)
      throw const RommFailure('Fixture connection lost');
    await target.writeAsBytes(bytes);
    onProgress(bytes.length);
  }
}

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 300 && !ready(); i++)
    await Future<void>.delayed(const Duration(milliseconds: 5));
  expect(ready(), true);
}

void main() {
  late Directory data;
  late ShellModel model;
  late QueuedRomm api;
  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-queue-');
    model = ShellModel(
      ShellStorage(data),
      credentials: MemoryCredentials(),
      clientFactory: (uri) => api = QueuedRomm(uri),
    );
    await model.start();
    await model.addServer('https://queue.example');
    await model.login('Player', 'fixture');
    await settleModel(model);
  });
  tearDown(() async {
    if (!api.release.isCompleted) api.release.complete();
    if (!api.releaseSecond.isCompleted) api.releaseSecond.complete();
    await model.finishDownloads();
    model.dispose();
    await data.delete(recursive: true);
  });
  ArtworkDownload icon() => ArtworkDownload(
    GridArtwork(
      id: 1,
      kind: ArtworkKind.icon,
      url: Uri.https('cdn2.steamgriddb.com', '/icon.png'),
      thumb: Uri.https('cdn2.steamgriddb.com', '/icon.png'),
      width: 16,
      height: 16,
      mime: 'image/png',
      author: 'Fixture',
    ),
    artworkPng(16, 16),
  );
  test('queue is serial and deduplicated; artwork persists while its payload is blocked and follows the verified Home entry', () async {
    await model.savePreferences(model.preferences.copy(maxDownloads: 1));
    final a = model.downloadGame(queuedFixture(1));
    await api.started.future;
    final b = model.downloadGame(queuedFixture(2));
    await until(() => model.artworkRequests.length == 2);
    expect(model.artworkRequests.map((g) => g.id), [1, 2]);
    expect(model.installed, isEmpty);
    expect(model.homeAppCount, 4);
    final duplicate = model.downloadGame(queuedFixture(2));
    await model.saveGameArtwork(1, icon: icon());
    final early = await model.library.artworkFor(model.server!.id, 1);
    expect(await File(early!.icon!).exists(), true);
    api.release.complete();
    await Future.wait([a, b, duplicate]);
    expect(api.order, [1, 2]);
    expect(model.downloads, isEmpty);
    expect(model.downloading, false);
    expect(model.installed.map((g) => g.game.id), [1, 2]);
    expect(await File(model.installation(1)!.artwork!.icon!).exists(), true);
    expect(model.installation(1)!.artwork!.icon, early.icon);
    expect(model.homeAppCount, 3);
  });
  test('bounded simultaneous transfers keep independent progress, stages and cancellation while a queued game waits for capacity', () async {
    await model.savePreferences(model.preferences.copy(maxDownloads: 2));
    api.holdSecond = true;
    final a = model.downloadGame(queuedFixture(1));
    await api.started.future;
    final b = model.downloadGame(queuedFixture(2));
    await api.secondStarted.future;
    final c = model.downloadGame(queuedFixture(3));
    await until(() => model.downloads.length == 3);
    expect(api.order, [1, 2]);
    expect(model.queuedGame(3)!.state, DownloadState.queued);
    final first = model.queuedGame(1)!;
    expect(first.progress!.game.id, 1);
    expect(model.queuedGame(2)!.progress!.game.id, 2);
    final stages = await Directory('${data.path}/library/${model.server!.id}')
        .list()
        .where(
          (f) => f.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last
              .startsWith('.partial-'),
        )
        .toList();
    expect(stages.length, 2);
    model.cancelDownload(first);
    api.release.complete();
    await a;
    await c;
    expect(first.state, DownloadState.failed);
    expect(model.installation(1), isNull);
    expect(model.queuedGame(2)!.state, DownloadState.active);
    expect(model.installation(3), isNotNull);
    expect(
      await stages.where((s) => s.path.contains('.partial-2-')).single.exists(),
      true,
    );
    api.releaseSecond.complete();
    await b;
    expect(model.installation(2), isNotNull);
    final files = await model.library.contentFiles(model.installation(2)!);
    expect(await File(files.single).readAsBytes(), bytes);
    expect(model.downloading, false);
    expect((await ShellStorage(data).load()).preferences.maxDownloads, 2);
  });
  test('increasing the configured cap starts a waiting job without interrupting existing work or sharing its failure', () async {
    await model.savePreferences(model.preferences.copy(maxDownloads: 1));
    api.failFirst = true;
    api.holdSecond = true;
    final a = model.downloadGame(queuedFixture(1));
    await api.started.future;
    final b = model.downloadGame(queuedFixture(2));
    await until(() => model.queuedGame(2) != null);
    expect(api.order, [1]);
    await model.savePreferences(model.preferences.copy(maxDownloads: 2));
    await api.secondStarted.future;
    api.release.complete();
    await a;
    api.releaseSecond.complete();
    await b;
    expect(model.queuedGame(1)!.problem, contains('Fixture connection lost'));
    expect(model.queuedGame(2), isNull);
    expect(model.installation(2), isNotNull);
  });
  test('a failed transfer retains its early artwork and retry record, lets the next game finish, and removal cleans only that transfer', () async {
    api.failFirst = true;
    final a = model.downloadGame(queuedFixture(1));
    await api.started.future;
    final b = model.downloadGame(queuedFixture(2));
    await until(() => model.downloads.length == 2);
    await model.saveGameArtwork(1, icon: icon());
    api.release.complete();
    await Future.wait([a, b]);
    expect(model.queuedGame(1)!.state, DownloadState.failed);
    expect(model.installation(1), isNull);
    expect(model.installation(2), isNotNull);
    final owner = model.server!.id, job = model.queuedGame(1)!;
    await model.removeDownload(job);
    expect(
      await Directory('${data.path}/home-artwork/$owner/1').exists(),
      false,
    );
    expect(await model.installation(2)!.directory.exists(), true);
    expect(model.downloads, isEmpty);
  });
  test('artwork for a completed game can be changed while the next transfer holds the library writer', () async {
    api.holdSecond = true;
    final a = model.downloadGame(queuedFixture(1));
    await api.started.future;
    final b = model.downloadGame(queuedFixture(2));
    await until(() => model.downloads.length == 2);
    api.release.complete();
    await a;
    await api.secondStarted.future;
    await model.saveGameArtwork(1, icon: icon());
    final chosen = model.installation(1)!.artwork!.icon!;
    expect(await File(chosen).exists(), true);
    api.releaseSecond.complete();
    await b;
    await model.loadLibrary();
    expect(model.installation(1)!.artwork!.icon, chosen);
  });
  test('interrupted queue records survive restart under their original account; another writer cannot claim them', () async {
    final store = DownloadQueueStore(data, model.server!.id, model.profile!.id);
    await store.open();
    await store.save([
      DownloadJob(queuedFixture(1), state: DownloadState.active),
      DownloadJob(queuedFixture(2)),
    ]);
    final other = DownloadQueueStore(data, model.server!.id, model.profile!.id);
    await expectLater(other.open(), throwsA(isA<DownloadQueueInUse>()));
    await other.close(); // A non-owner must never drop the live owner's guard.
    await expectLater(other.open(), throwsA(isA<DownloadQueueInUse>()));
    await store.close();
    final resumed = await other.open();
    expect(resumed.map((j) => j.game.id), [1, 2]);
    expect(resumed.every((j) => j.state == DownloadState.failed), true);
    await other.close();
  });

  test('a locked account queue stays visible read-only, then refresh safely acquires the same interrupted download', () async {
    final writer = DownloadQueueStore(
      data,
      model.server!.id,
      model.profile!.id,
    );
    await writer.open();
    await writer.save([
      DownloadJob(queuedFixture(1), state: DownloadState.active),
    ]);
    final record = File('${writer.root.path}/queue.json');
    final before = await record.readAsString();
    await model.loadDownloads();
    expect(model.downloadsReadOnly, true);
    expect(model.queuedGame(1)!.state, DownloadState.active);
    expect(model.downloadError, isNull);
    await model.removeDownload(model.queuedGame(1)!);
    await model.retryDownload(model.queuedGame(1)!);
    expect(await record.readAsString(), before);
    await writer.close();
    await model.loadDownloads();
    expect(model.downloadsReadOnly, false);
    expect(model.queuedGame(1)!.state, DownloadState.failed);
    await model.removeDownload(model.queuedGame(1)!);
    expect(model.downloads, isEmpty);
    expect((jsonDecode(await record.readAsString()) as Map)['jobs'], isEmpty);
  });

  test('an independent process holds the production lock while snapshots remain readable and failed open never releases its inode', () async {
    final writer = DownloadQueueStore(
      data,
      model.server!.id,
      model.profile!.id,
    );
    await writer.open();
    await writer.save([
      DownloadJob(queuedFixture(2), state: DownloadState.active),
    ]);
    await writer.close();
    final child = await Process.start('dart', [
      'test/support/hold_library_lock.dart',
      '${writer.root.path}/queue.lock',
    ]);
    try {
      expect(
        await child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'held',
      );
      await expectLater(writer.open(), throwsA(isA<DownloadQueueInUse>()));
      expect((await writer.readSnapshot()).single.state, DownloadState.active);
      await expectLater(writer.open(), throwsA(isA<DownloadQueueInUse>()));
    } finally {
      child.stdin.writeln('release');
      await child.stdin.close();
      expect(await child.exitCode, 0);
    }
    expect((await writer.open()).single.state, DownloadState.failed);
    await writer.close();
  });
}
