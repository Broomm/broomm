import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/android/progress.dart';
import 'package:broomm/src/android/session.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/files.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/session_lease.dart';

import 'cloud_saves_test.dart' show SaveServer, serverId, profileId;
import 'support/addon_fixtures.dart' show base3ds, baseTitle;
import 'support/android_document_paths.dart';

const _tree =
    'content://com.android.externalstorage.documents/tree/primary%3Acitra-emu';
const _build =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _secondProfile = 'c123456789abcdef0123456789abcdef';
const _zeros = '00000000000000000000000000000000';
const _save = 'sdmc/Nintendo 3DS/$_zeros/$_zeros/title/00040000/000edf00/data';
const _ext = 'sdmc/Nintendo 3DS/$_zeros/$_zeros/extdata/00000000/00000edf';

/// Controlled standard-provider boundary. Failures are held at a destructive
/// publication gap, rather than relying on scheduling or repeated attempts.
class SharedFolderFixture {
  SharedFolderFixture(this.root);
  final Directory root;
  String? pick = _tree;
  bool granted = true;
  bool ioBusy = false;
  bool failInstall = false, failRestore = false;
  int launches = 0, writes = 0;
  final staged = <String, List<int>>{};

  Future<File> put(String path, String text) async {
    final file = await progressFile(root, path, createParents: true);
    await file.writeAsString(text, flush: true);
    return file;
  }

  Future<String?> text(String path) async {
    final file = File('${root.path}/$path');
    return await file.exists() ? file.readAsString() : null;
  }

  Future<Object?> call(MethodCall call) async {
    final args = call.arguments as Map? ?? {};
    switch (call.method) {
      case 'ioBusy':
        return ioBusy;
      case 'installed':
        return [
          {'package': 'org.citra.emu', 'version': 'fixture', 'build': _build},
        ];
      case 'writers':
        return ioBusy ? 1 : 0;
      case 'sharedPick':
        return pick;
      case 'sharedCheck':
        if (!granted) throw PlatformException(code: 'grant-revoked');
        return null;
      case 'launch':
        launches++;
        return 'fixture-handoff';
      case 'releaseGrants':
        return null;
    }
    if (!granted) throw PlatformException(code: 'grant-revoked');
    expect(args['tree'], _tree);
    switch (call.method) {
      case 'sharedList':
        final files = <String, dynamic>{};
        for (final spec in args['areas'] as List) {
          final area = spec as Map;
          final dir = Directory('${root.path}/${area['path']}');
          if (!await dir.exists()) continue;
          await for (final file in dir.list(
            recursive: true,
            followLinks: false,
          )) {
            if (file is! File) continue;
            final relative = androidDocumentRelativePath(dir.uri, file.uri);
            if (area['prefix'] != null &&
                (relative.contains('/') ||
                    !relative.startsWith(area['prefix'] as String) ||
                    !relative.endsWith(area['suffix'] as String)))
              continue;
            files['${area['path']}/$relative'] = {
              'bytes': await file.length(),
              'sha256': await progressFileHash(file),
            };
          }
        }
        return files;
      case 'sharedRead':
        final source = File('${root.path}/${args['path']}');
        expect(await progressFileHash(source), args['sha256']);
        await source.copy(args['target'] as String);
        return null;
      case 'sharedReplace':
        final target = await progressFile(
          root,
          args['path'] as String,
          createParents: true,
        );
        final actual = await target.exists()
            ? await progressFileHash(target)
            : null;
        if (actual == args['after']) return null;
        final key = '${args['token']}:${args['path']}';
        if (actual != args['before'] &&
            !(actual == null && staged.containsKey(key)))
          throw StateError('External writer changed the shared save');
        final source = args['source'] as String?;
        if (source != null) staged[key] = await File(source).readAsBytes();
        if (await target.exists()) await target.delete();
        writes++;
        final installing = (args['token'] as String).endsWith('-in');
        if (source != null && (installing ? failInstall : failRestore)) {
          if (installing) {
            failInstall = false;
          } else {
            failRestore = false;
          }
          throw PlatformException(code: 'interrupted-publication');
        }
        if (source != null)
          await target.writeAsBytes(staged.remove(key)!, flush: true);
        return null;
    }
    throw StateError('Unexpected Android operation ${call.method}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.broomm/mmj-test');
  final mmj = androidEmulators.singleWhere((e) => e.id == 'citra-mmj');
  late Directory fixture, data;
  late File rom;
  late SharedFolderFixture shared;
  late AndroidEmulators manager;
  final sessions = <AndroidGameSession>[];
  final apis = <SaveServer>[];
  late CloudSaves cloud;
  Future<void> connect(String profile) async =>
      manager.confirmStorage(profile, mmj, (await manager.chooseMmjFolder())!);
  Future<CloudGame> game(String profile, SaveServer api) async => CloudGame(
    server: serverId,
    profile: profile,
    user: api.user,
    rom: 42,
    client: api,
    layout: await androidProgressLayout(
      manager,
      profile,
      mmj,
      playablePlatforms.firstWhere((p) => p.slug == '3ds'),
      rom.path,
    ),
  );
  AndroidGameSession session() {
    final session = AndroidGameSession(manager, cloud);
    sessions.add(session);
    return session;
  }

  SaveServer api([int user = 3]) {
    final api = SaveServer()..user = user;
    apis.add(api);
    return api;
  }

  Future<void> start(AndroidGameSession session, CloudGame g) => session.start(
    server: g.server,
    profile: g.profile,
    rom: g.rom,
    emulator: mmj,
    app: manager.app(mmj)!,
    files: [rom.path],
    selected: rom.path,
    game: g,
  );
  Future<void> writePrivate(CloudGame game, String value) async {
    await (await game.layout.target('save/00000001/main')).writeAsString(value);
    await (await game.layout.target('save/00000001.metadata'))
        .writeAsString('native metadata');
    await (await game.layout.target('ext-00000edf/value'))
        .writeAsString('ext-$value');
  }

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('broomm-mmj-');
    data = await Directory('${fixture.path}/data').create();
    shared = SharedFolderFixture(
      await Directory('${fixture.path}/shared').create(),
    );
    final bytes = Uint8List(0x500)..setAll(0, base3ds());
    final header = ByteData.sublistView(bytes);
    header.setUint64(0x400, int.parse(baseTitle, radix: 16), Endian.little);
    header.setUint64(0x430, 0xedf, Endian.little);
    rom = await File('${fixture.path}/Smash.3ds').writeAsBytes(bytes);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, shared.call);
    manager = AndroidEmulators(data, channel: channel, enabled: true);
    await manager.load();
    cloud = CloudSaves(data, notice: (_, _) {});
  });
  tearDown(() async {
    for (final s in sessions) {
      s.dispose();
    }
    sessions.clear();
    await Future<void>.delayed(Duration.zero);
    for (final api in apis) {
      api.close();
    }
    apis.clear();
    manager.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await fixture.delete(recursive: true);
  });

  test('MMJ shared-folder play uploads BROOMM saves and keeps standalone and other-profile progress separate', () async {
    await shared.put('$_save/00000001/main', 'standalone');
    await shared.put('$_save/00000001.metadata', 'standalone metadata');
    await shared.put('$_ext/value', 'standalone extdata');
    await shared.put(
      'states/${baseTitle.toUpperCase()}.01.cst',
      'standalone state',
    );
    await shared.put('states/0004000000999900.01.cst', 'other title state');
    await shared.put('config/config.ini', 'settings');
    await connect(profileId);
    await connect(_secondProfile);
    final a = await game(profileId, api()),
        b = await game(_secondProfile, api(4));
    await writePrivate(a, 'player A');
    final first = session();
    await start(first, a);
    expect(await shared.text('$_save/00000001/main'), 'player A');
    expect(await shared.text('$_ext/value'), 'ext-player A');
    expect(
      await shared.text('states/${baseTitle.toUpperCase()}.01.cst'),
      isNull,
    );
    await expectLater(SessionLease.acquire(data), throwsStateError);
    await shared.put('$_save/00000001/main', 'player A after play');
    await first.finish(emulatorClosed: true);
    expect(await shared.text('$_save/00000001/main'), 'standalone');
    expect(await shared.text('$_ext/value'), 'standalone extdata');
    expect(
      await shared.text('states/${baseTitle.toUpperCase()}.01.cst'),
      'standalone state',
    );
    final remote = (a.client as SaveServer).records.values.last;
    expect(remote.slot, 'BROOMM');
    expect(remote.name, endsWith('.zip'));
    expect(
      await (await a.layout.target('save/00000001/main')).readAsString(),
      'player A after play',
    );
    expect(await b.layout.files(), isEmpty);
    // Re-read the actual persisted grant, including MMJ's hyphenated identity.
    manager.dispose();
    manager = AndroidEmulators(data, channel: channel, enabled: true);
    await manager.load();
    expect(manager.error, isNull);
    expect(manager.tree(_secondProfile, mmj), _tree);
    final second = session();
    await start(second, b);
    expect(await shared.text('$_save/00000001/main'), isNull);
    await shared.put('$_save/00000001/main', 'player B first save');
    await shared.put('$_save/00000001.metadata', 'native metadata');
    await second.finish(emulatorClosed: true);
    expect((b.client as SaveServer).records.values.single.slot, 'BROOMM');
    final again = session();
    await start(again, a);
    expect(await shared.text('$_save/00000001/main'), 'player A after play');
    await again.finish(emulatorClosed: true);
    expect(await shared.text('config/config.ini'), 'settings');
    expect(
      await shared.text('states/0004000000999900.01.cst'),
      'other title state',
    );
  });

  test('external changes retain copies and allow explicit finish without changing the shared folder', () async {
    await connect(profileId);
    final client = api(), g = await game(profileId, client);
    await writePrivate(g, 'profile');
    await shared.put('$_save/00000001/main', 'standalone');
    shared.failInstall = true;
    final run = session();
    await expectLater(start(run, g), throwsA(isA<PlatformException>()));
    await shared.put('$_save/00000001.metadata', 'outside writer');
    await expectLater(
      run.finish(emulatorClosed: true),
      throwsA(isA<PlatformException>()),
    );
    final writes = shared.writes, uploads = client.updatedIds.length;
    await expectLater(
      run.keepMmjFolder(emulatorClosed: false),
      throwsStateError,
    );
    await run.keepMmjFolder(emulatorClosed: true);
    expect(shared.writes, writes);
    expect(client.updatedIds.length, uploads);
    expect(await shared.text('$_save/00000001.metadata'), 'outside writer');
    expect(await run.pending(), isNull);
    final retained = await Directory('${data.path}/android/mmj-session')
        .list(recursive: true)
        .where((e) => e is File)
        .toList();
    expect(
      await Future.wait(
        retained
            .cast<File>()
            .where((e) => e.uri.pathSegments.last == 'main')
            .map((f) => f.readAsString()),
      ),
      contains('standalone'),
    );
    final lease = await SessionLease.acquire(data);
    await lease.release();
  });

  test('cancelled, private, and revoked folder grants never enable MMJ save writes', () async {
    shared.pick = null;
    expect(await manager.chooseMmjFolder(), isNull);
    shared.pick = 'content://com.android.externalstorage.documents/tree/primary%3AAndroid%2Fdata%2Forg.citra.emu';
    await expectLater(manager.chooseMmjFolder(), throwsStateError);
    await expectLater(
      manager.confirmStorage(profileId, mmj, shared.pick!),
      throwsFormatException,
    );
    expect(manager.tree(profileId, mmj), isNull);
    shared.pick = _tree;
    shared.granted = false;
    await expectLater(connect(profileId), throwsA(isA<PlatformException>()));
    expect(manager.tree(profileId, mmj), isNull);
    expect(shared.writes, 0);
    expect(shared.launches, 0);
    shared.granted = true;
    await connect(profileId);
    final g = await game(profileId, api());
    await writePrivate(g, 'private');
    await shared.put('$_save/00000001/main', 'external');
    shared.ioBusy = true;
    final blocked = session();
    await expectLater(start(blocked, g), throwsStateError);
    expect(await blocked.pending(), isNull);
    expect(shared.writes, 0);
    shared.ioBusy = false;
    shared.granted = false;
    final run = session();
    await expectLater(start(run, g), throwsA(isA<PlatformException>()));
    expect(shared.writes, 0);
    expect(shared.launches, 0);
    expect(await shared.text('$_save/00000001/main'), 'external');
    shared.granted = true;
    await run.finish(emulatorClosed: true);
  });

  for (final installing in [true, false]) {
    test(
      'interrupted MMJ ${installing ? 'preparation' : 'standalone restore'} recovers after restart without losing progress',
      () async {
        await connect(profileId);
        final g = await game(profileId, api());
        await writePrivate(g, 'profile');
        await shared.put('$_save/00000001/main', 'standalone');
        await shared.put('$_save/00000001.metadata', 'standalone metadata');
        final run = session();
        if (installing) {
          shared.failInstall = true;
          await expectLater(start(run, g), throwsA(isA<PlatformException>()));
          expect(shared.launches, 0);
        } else {
          await start(run, g);
          await shared.put('$_save/00000001/main', 'new gameplay');
          shared.failRestore = true;
          await expectLater(
            run.finish(emulatorClosed: true),
            throwsA(isA<PlatformException>()),
          );
        }
        expect(await run.pending(), isNotNull);
        if (installing) {
          // The native swap receipt independently preserves a recovery route.
          await run.marker.delete();
          expect(await run.pending(), isNotNull);
        }
        run.dispose();
        sessions.remove(run);
        await Future<void>.delayed(Duration.zero);
        final recovered = session();
        await expectLater(start(recovered, g), throwsStateError);
        await expectLater(
          recovered.finish(emulatorClosed: false, recovery: g),
          throwsStateError,
        );
        await recovered.finish(emulatorClosed: true, recovery: g);
        expect(await recovered.pending(), isNull);
        expect(await shared.text('$_save/00000001/main'), 'standalone');
        expect(
          await (await g.layout.target('save/00000001/main')).readAsString(),
          installing ? 'profile' : 'new gameplay',
        );
        final lease = await SessionLease.acquire(data);
        await lease.release();
      },
    );
  }
}
