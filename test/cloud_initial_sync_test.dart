import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/progress/files.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloud_saves_test.dart' show SaveServer, serverId, profileId;

class InitialSyncEmulators extends ManagedEmulators {
  InitialSyncEmulators(super.data);
  @override
  bool ready(String name) => name == 'melonDS';
  @override
  Future<ResolvedSession> resolveProgress(
    LaunchGame game,
    String profile,
  ) async {
    final native = Directory(
      '${data.path}/profiles/$profile/emulators/melonds',
    );
    await native.create(recursive: true);
    await File('${native.path}/profile.json').writeAsString(
      jsonEncode({'version': 1, 'profile': profile, 'emulator': 'melonds'}),
    );
    return ResolvedSession(
      PreparedEmulator('melonDS', native.path, 'not-executed', 2, null, null),
      game.rom,
      'a' * 64,
      {},
    );
  }
}

class InitialSyncServer extends SaveServer {
  final romBytes = Uint8List(32)..setRange(12, 16, ascii.encode('ARGP'));
  Completer<void>? savesHeld, savesEntered;
  RommGame get detail => RommGame(
    id: 42,
    name: 'DS test game',
    platformId: 1,
    platform: 'Nintendo DS',
    platformSlug: 'nds',
    fsName: 'Game.nds',
    fullPath: 'roms/nds/Game.nds',
    bytes: romBytes.length,
    files: [
      RommFile(
        id: 1,
        romId: 42,
        name: 'Game.nds',
        fullPath: 'roms/nds/Game.nds',
        bytes: romBytes.length,
      ),
    ],
  );
  @override
  Future<RommGame> game(int id) async => detail;
  @override
  Future<void> downloadFile(
    RommFile file,
    File target, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    cancellation.check();
    await target.writeAsBytes(romBytes);
    onProgress(romBytes.length);
  }

  @override
  Future<List<RommSave>> saves(int id) async {
    if (savesHeld != null) {
      if (!savesEntered!.isCompleted) savesEntered!.complete();
      await savesHeld!.future;
    }
    return super.saves(id);
  }
}

void main() {
  late Directory data;
  late ShellModel model;
  late InitialSyncServer api;
  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-initial-sync-');
    api = InitialSyncServer();
    model = ShellModel(
      ShellStorage(data),
      emulatorManager: InitialSyncEmulators(data),
    );
    model.server = const SavedServer(
      serverId,
      'https://fixture.invalid',
      '5.4.0',
    );
    model.profile = const SavedProfile(profileId, serverId, 3, 'Player');
    model.client = api;
    model.screen = ShellScreen.home;
  });
  tearDown(() async {
    if (api.savesHeld != null && !api.savesHeld!.isCompleted)
      api.savesHeld!.complete();
    await model.finishDownloads();
    await model.finishCloud();
    model.dispose();
    await data.delete(recursive: true);
  });
  Future<void> drainCloud() async {
    // Queue completion schedules sync before completing its public download.
    // Await a listener condition rather than cancelling that first sync.
    for (var i = 0; i < 400 && model.cloudBusy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(model.cloudBusy, false);
    await model.refreshCloudStatus();
  }

  Future<File> nativeSave() async {
    final game = await model.cloudGame(42);
    final area = game.layout.areas.first;
    return File('${game.layout.root}/${area.path}/${area.exact}');
  }

  test('a new installation automatically verifies an empty BROOMM history and is synced without uploading a dummy save', () async {
    await model.downloadGame(api.detail);
    await drainCloud();
    expect(model.cloudStatus(42), CloudSaveStatus.synced);
    expect(api.records, isEmpty);
    final state = await progressJson(
      File('${data.path}/cloud-saves/$serverId/$profileId/42/state.json'),
    );
    expect(state['emptySynced'], true);
    expect(state['pending'], false);
    await model.loadLibrary();
    await drainCloud();
    expect(model.cloudStatus(42), CloudSaveStatus.synced);
  });

  test('first sync automatically restores only this account’s BROOMM slot, retaining other slots and native file extensions', () async {
    final other = api.add(
      List<int>.filled(512, 9),
      name: 'autosave.sav',
      slot: 'autosave',
      emulator: 'melonDS',
    );
    final managed = api.add(
      List<int>.filled(512, 3),
      name: 'Broomm [2026-10-23_12-00-00].sav',
      slot: 'BROOMM',
    );
    await model.downloadGame(api.detail);
    await drainCloud();
    expect(model.cloudStatus(42), CloudSaveStatus.synced);
    expect(await (await nativeSave()).readAsBytes(), api.contents[managed.id]);
    expect(api.readIds, isNot(contains(other.id)));
    expect(api.records.keys.toSet(), {other.id, managed.id});
  });

  test('an offline first check retries automatically; divergent legacy device progress needs attention and both versions survive', () async {
    api.offline = true;
    await model.downloadGame(api.detail);
    await drainCloud();
    expect(model.cloudStatus(42), CloudSaveStatus.waiting);
    final file = await nativeSave();
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(512, 4));
    final remote = api.add(
      List<int>.filled(512, 8),
      name: 'Broomm [2026-10-23_12-00-00].sav',
      slot: 'BROOMM',
    );
    api.offline = false;
    await model.retryCloud();
    expect(model.cloudStatus(42), CloudSaveStatus.attention);
    expect(await file.readAsBytes(), List<int>.filled(512, 4));
    expect(api.contents[remote.id], List<int>.filled(512, 8));
    expect(api.records.length, 1);
  });

  test('initial sync owns the production session lock and a context change drains it without acknowledging the cancelled result', () async {
    api.savesHeld = Completer<void>();
    api.savesEntered = Completer<void>();
    await model.downloadGame(api.detail);
    await api.savesEntered!.future;
    await expectLater(SessionLease.acquire(data), throwsStateError);
    var finished = false;
    final finish = model.finishCloud().then((_) => finished = true);
    await Future<void>(() {});
    expect(finished, false);
    api.savesHeld!.complete();
    await finish;
    final lease = await SessionLease.acquire(data);
    await lease.release();
    await model.refreshCloudStatus();
    expect(model.cloudStatus(42), CloudSaveStatus.waiting);
    expect(api.records, isEmpty);
  });
}
