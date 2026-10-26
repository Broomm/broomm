import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/steamgrid.dart';

import 'library_download_test.dart'
    show fixture, serverId, otherServerId, bytes;
import 'support/artwork_fixtures.dart';

class ArtworkFiles extends RommClient {
  ArtworkFiles() : super(Uri.parse('https://fixture.example'));
  @override
  Future<void> downloadFile(
    RommFile f,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    await destination.writeAsBytes(bytes);
    onProgress(bytes.length);
  }
}

ArtworkDownload choice(int id, ArtworkKind kind) => ArtworkDownload(
  GridArtwork(
    id: id,
    kind: kind,
    url: Uri.parse('https://cdn2.steamgriddb.com/$id.png'),
    thumb: Uri.parse('https://cdn2.steamgriddb.com/thumb$id.png'),
    width: kind == ArtworkKind.icon ? 16 : 64,
    height: 16,
    mime: 'image/png',
    author: 'Artist $id',
  ),
  artworkPng(kind == ArtworkKind.icon ? 16 : 64, 16),
);
void main() {
  late Directory root;
  late GameLibrary library;
  late ArtworkFiles client;
  Future<InstalledGame> install({String server = serverId, int id = 1}) =>
      library.install(
        serverId: server,
        userId: 7,
        game: fixture(id: id),
        client: client,
        cancellation: DownloadCancellation(),
        progress: (_) {},
      );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-artwork-library-');
    library = GameLibrary(root);
    client = ArtworkFiles();
  });
  tearDown(() async {
    client.close();
    await root.delete(recursive: true);
  });
  test('a conflicting public/pending identity is one blocked entry and an independent writer prevents deletion', () async {
    final game = await install();
    final pending = Directory('${game.directory.parent.path}/.deleting-1');
    await pending.create();
    await File('${game.directory.path}/receipt.json')
        .copy('${pending.path}/receipt.json');
    final snapshot = await library.load(serverId);
    expect(snapshot.games.length, 1);
    expect(snapshot.games.single.removing, true);
    expect(snapshot.problem, isNotNull);
    await expectLater(
      library.remove(serverId, 1),
      throwsA(isA<FileSystemException>()),
    );
    await pending.delete(recursive: true);
    final child = await Process.start('dart', [
      'test/support/hold_library_lock.dart',
      '${root.path}/writer.lock',
    ]);
    try {
      expect(
        await child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'held',
      );
      await expectLater(
        library.remove(serverId, 1),
        throwsA(isA<StateError>()),
      );
      expect(await game.directory.exists(), true);
    } finally {
      child.stdin.writeln('release');
      await child.stdin.close();
      await child.exitCode;
    }
    await library.remove(serverId, 1);
    expect(await game.directory.exists(), false);
  });
  test('durable intent survives pre-rename interruption, lost inner receipts and final marker-only cleanup', () async {
    for (final phase in ['before-rename', 'receipt-gone', 'payload-gone']) {
      final game = await install();
      final record = jsonDecode(
        await File('${game.directory.path}/receipt.json').readAsString(),
      ) as Map;
      final marker = File('${game.directory.parent.path}/.deleting-1.json');
      await marker.writeAsString(
        jsonEncode({...record, 'deletion': true}),
        flush: true,
      );
      if (phase != 'before-rename') {
        final trash = await game.directory.rename(
          '${game.directory.parent.path}/.deleting-1',
        );
        await File('${trash.path}/receipt.json').delete();
        if (phase == 'payload-gone') await trash.delete(recursive: true);
      }
      final pending = (await GameLibrary(root).load(serverId)).games.single;
      expect(pending.removing, true, reason: phase);
      await expectLater(
        library.contentFiles(pending),
        throwsA(isA<StateError>()),
      );
      await expectLater(install(), throwsA(isA<RommFailure>()));
      await GameLibrary(root).remove(serverId, 1);
      expect((await library.load(serverId)).games, isEmpty, reason: phase);
      expect(await marker.exists(), false);
    }
  });
  test('foreign or damaged deletion intents never authorize removing an owned game', () async {
    final game = await install();
    final marker = File('${game.directory.parent.path}/.deleting-1.json');
    final record = jsonDecode(
      await File('${game.directory.path}/receipt.json').readAsString(),
    ) as Map;
    for (final text in [
      jsonEncode({...record, 'serverId': otherServerId, 'deletion': true}),
      '{damaged',
    ]) {
      await marker.writeAsString(text);
      await expectLater(
        library.remove(serverId, 1),
        throwsA(isA<FormatException>()),
      );
      expect(
        await File('${game.directory.path}/content/Game.iso').readAsBytes(),
        bytes,
      );
      expect(await marker.readAsString(), text);
    }
  });
  test('selected artwork survives restart, icon-only changes retain the hero and a damaged optional record does not hide the ROM', () async {
    await install();
    final first = await library.saveArtwork(
      serverId,
      1,
      icon: choice(1, ArtworkKind.icon),
      hero: choice(2, ArtworkKind.hero),
      logo: choice(5, ArtworkKind.logo),
    );
    expect(
      await File(first!.icon!).readAsBytes(),
      choice(1, ArtworkKind.icon).bytes,
    );
    final again = await GameLibrary(root).load(serverId);
    expect(again.games.single.artwork!.hero, first.hero);
    expect(again.games.single.artwork!.logo, first.logo);
    final next = await library.saveArtwork(
      serverId,
      1,
      icon: choice(3, ArtworkKind.icon),
    );
    expect(
      await File(next!.hero!).readAsBytes(),
      choice(2, ArtworkKind.hero).bytes,
    );
    expect(File(first.icon!).existsSync(), false);
    expect(
      await File(next.logo!).readAsBytes(),
      choice(5, ArtworkKind.logo).bytes,
    );
    expect(File(first.logo!).existsSync(), false);
    await File('${File(next.icon!).parent.parent.parent.path}/artwork.json')
        .writeAsString('{damaged');
    final damaged = await library.load(serverId);
    expect(damaged.games.single.problem, isNull);
    expect(damaged.games.single.artwork, isNull);
    expect(damaged.problem, isNotNull);
    expect(
      await library.saveArtwork(serverId, 1, icon: choice(4, ArtworkKind.icon)),
      isNotNull,
    );
  });
  for (final linked in [false, true]) {
    test(
      'artwork replacement retains ${linked ? 'linked' : 'unrelated'} files beside an old choice',
      () async {
        await install();
        final first = await library.saveArtwork(
          serverId,
          1,
          icon: choice(1, ArtworkKind.icon),
        );
        final old = File(first!.icon!).parent;
        final foreign = File('${root.path}/foreign');
        await foreign.writeAsString('keep');
        if (linked) {
          // Even a recognized image filename must not authorize deleting a link.
          await Link('${old.path}/hero.jpg').create(foreign.path);
        } else {
          await File('${old.path}/notes.txt')
              .writeAsString('keep alongside artwork');
        }
        final next = await library.saveArtwork(
          serverId,
          1,
          icon: choice(3, ArtworkKind.icon),
        );
        expect(
          await File(next!.icon!).readAsBytes(),
          choice(3, ArtworkKind.icon).bytes,
        );
        expect(await File(first.icon!).exists(), true);
        expect(await foreign.readAsString(), 'keep');
        expect(
          linked
              ? await Link('${old.path}/hero.jpg').exists()
              : await File('${old.path}/notes.txt').exists(),
          true,
        );
      },
    );
  }
  test('failed or mismatched artwork never replaces an existing selection or changes game bytes', () async {
    final game = await install();
    final first = await library.saveArtwork(
      serverId,
      1,
      icon: choice(1, ArtworkKind.icon),
    );
    final bad = ArtworkDownload(choice(3, ArtworkKind.icon).art, Uint8List(24));
    await expectLater(
      library.saveArtwork(serverId, 1, icon: bad),
      throwsA(isA<FormatException>()),
    );
    expect(
      (await library.load(serverId)).games.single.artwork!.icon,
      first!.icon,
    );
    expect(
      await File('${game.directory.path}/content/Game.iso').readAsBytes(),
      bytes,
    );
    expect(
      () => validateArtworkDownload(choice(2, ArtworkKind.hero)),
      returnsNormally,
    );
    await expectLater(
      library.saveArtwork(serverId, 1, icon: choice(2, ArtworkKind.hero)),
      throwsA(isA<FormatException>()),
    );
  });
  test('deletion removes only owned ROM/artwork, keeps other games and all profile progress, and excludes active sessions', () async {
    final game = await install();
    await install(server: otherServerId);
    await install(id: 2);
    await library.saveArtwork(serverId, 1, icon: choice(1, ArtworkKind.icon));
    final progress = File(
      '${root.path}/profiles/player/emulators/dolphin/user/save',
    );
    await progress.parent.create(recursive: true);
    await progress.writeAsString('unsynced progress');
    final lease = await SessionLease.acquire(root);
    await expectLater(library.remove(serverId, 1), throwsA(isA<StateError>()));
    expect(await game.directory.exists(), true);
    await lease.release();
    await library.remove(serverId, 1);
    expect(await game.directory.exists(), false);
    expect((await library.load(serverId)).games.single.game.id, 2);
    expect((await library.load(otherServerId)).games.single.game.id, 1);
    expect(await progress.readAsString(), 'unsynced progress');
    await library.remove(serverId, 1); // Lost acknowledgement is idempotent.
  });
  test('unrelated files block deletion and an interrupted owned removal remains visible and retryable', () async {
    final game = await install();
    final extra = File('${game.directory.path}/unrelated.txt');
    await extra.writeAsString('keep');
    await expectLater(
      library.remove(serverId, 1),
      throwsA(isA<FileSystemException>()),
    );
    expect(await extra.readAsString(), 'keep');
    await extra.delete();
    final lease = await SessionLease.acquire(root);
    try {
      await game.directory.rename('${game.directory.parent.path}/.deleting-1');
    } finally {
      await lease.release();
    }
    final pending = (await library.load(serverId)).games.single;
    expect(pending.removing, true);
    await expectLater(install(), throwsA(isA<RommFailure>()));
    await expectLater(
      library.contentFiles(pending),
      throwsA(isA<StateError>()),
    );
    await library.remove(serverId, 1);
    expect((await library.load(serverId)).games, isEmpty);
  });
}
