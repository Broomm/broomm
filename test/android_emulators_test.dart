import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/android/progress.dart';
import 'package:broomm/src/android/session.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/progress/files.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/shell/android_session_screen.dart';
import 'package:broomm/src/widgets/pairing_screen.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';

import 'cloud_saves_test.dart' show SaveServer, serverId, profileId;
import 'psp_test.dart' show pspPbp;

const channel = MethodChannel('app.broomm/android-test');
const buildHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

class RecordingCloud extends CloudSaves {
  RecordingCloud(super.root) : super(notice: (_, _) {});
  final calls = <String>[];
  final finalized = <CloudGame>[];
  @override
  Future<void> beforePlay(CloudGame g, {ProgressResolver? resolve}) async {
    calls.add('before:${g.profile}');
  }

  @override
  Future<void> afterPlay(CloudGame g, int exit) async {
    calls.add('after:$exit');
    finalized.add(g);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;
  late AndroidEmulators manager;
  late List<MethodCall> calls;
  late List<Map<String, Object>> apps;
  Object? failure;
  int writers = 0;
  bool managerDisposed = false;
  Future<Object?> Function(MethodCall)? handoff;
  AndroidEmulator emulator(String id) =>
      androidEmulators.singleWhere((e) => e.id == id);
  Future<void> configure(String id) async {
    final e = emulator(id);
    final uri = await manager.exposeStorage(profileId, 'Player', e);
    await manager.confirmStorage(profileId, e, uri);
  }

  Future<void> launch(AndroidGameSession session, {CloudGame? game}) =>
      session.start(
        server: serverId,
        profile: profileId,
        rom: 42,
        emulator: emulator('ppsspp'),
        app: manager.app(emulator('ppsspp'))!,
        files: ['/fixture/Game.pbp'],
        selected: '/fixture/Game.pbp',
        game: game,
      );
  CloudGame game(
    CloudSaves cloud,
    SaveServer api, {
    String profile = profileId,
  }) => CloudGame(
    server: serverId,
    profile: profile,
    user: 3,
    rom: 42,
    client: api,
    layout: ProgressLayout(
      '${data.path}/profiles/$profile/emulators/ppsspp',
      'fixture',
      'game',
      const [],
    ),
  );

  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-android-');
    calls = [];
    failure = null;
    handoff = null;
    writers = 0;
    managerDisposed = false;
    apps = [
      {'package': 'org.ppsspp.ppsspp', 'version': '1.20.4', 'build': buildHash},
      {
        'package': 'me.magnum.melonds',
        'version': 'fixture',
        'build': buildHash,
      },
      {
        'package': 'dev.eden.eden_emulator',
        'version': '0.2.1',
        'build': buildHash,
      },
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'installed':
              if (failure != null) throw failure!;
              return apps;
            case 'fingerprint':
              return buildHash;
            case 'writers':
              return writers;
            case 'dataRoot':
              final args = call.arguments as Map;
              return 'content://app.broomm.broomm.emulator-data/tree/${Uri.encodeComponent('${args['profile']}:${args['emulator']}')}';
            case 'launch':
              return handoff == null
                  ? '0123456789abcdef0123456789abcdef'
                  : handoff!(call);
            default:
              return null;
          }
        });
    manager = AndroidEmulators(data, channel: channel, enabled: true);
    await manager.load();
  });
  tearDown(() async {
    if (!managerDisposed) manager.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await data.delete(recursive: true);
  });

  test(
    'Android roster and defaults do not depend on installed desktop bundles',
    () async {
      final m = ShellModel(ShellStorage(data), androidManager: manager);
      await m.start();
      const switchPlatform = RommPlatform(1, 'Switch', 'switch', 1),
          ps3 = RommPlatform(2, 'PlayStation 3', 'ps3', 1),
          ps4 = RommPlatform(3, 'PlayStation 4', 'ps4', 1),
          snes = RommPlatform(4, 'Super Nintendo', 'snes', 1);
      expect(m.defaultEmulator(switchPlatform), 'eden');
      expect(m.emulatorChoices(ps3), isEmpty);
      expect(m.emulatorChoices(ps4), isEmpty);
      expect(m.emulatorChoices(snes).single.emulatorId, 'retroarch');
      expect(m.emulators.builds, isEmpty);
      expect(await Directory('${data.path}/emulators').exists(), false);
      m.dispose();
      managerDisposed = true;
    },
  );

  test(
    'failed or contradictory package observations preserve known installations',
    () async {
      failure = PlatformException(code: 'query-failed');
      await manager.load();
      expect(manager.app(emulator('ppsspp')), isNotNull);
      expect(manager.error, isNotNull);
      failure = null;
      apps = [apps.first, apps.first];
      await manager.load();
      expect(manager.installed.length, 3);
      expect(manager.error, isNotNull);
    },
  );

  test(
    'profile storage confirmation is durable and cannot follow another profile',
    () async {
      await configure('ppsspp');
      final first = manager.tree(profileId, emulator('ppsspp'));
      final other = 'c123456789abcdef0123456789abcdef';
      await expectLater(
        manager.confirmStorage(other, emulator('ppsspp'), first!),
        throwsFormatException,
      );
      await manager.load();
      expect(manager.tree(profileId, emulator('ppsspp')), first);
      expect(manager.tree(other, emulator('ppsspp')), isNull);
      final owner = await progressJson(
        File('${data.path}/profiles/$profileId/emulators/ppsspp/profile.json'),
      );
      expect(owner['profile'], profileId);
    },
  );

  test('handoff arguments stay literal and selection mismatches never reach Android', () async {
    const path = '/fixture/Some Game \$(touch unsafe) é.pbp';
    await manager.launch(emulator('ppsspp'), manager.app(emulator('ppsspp'))!, [
      path,
    ], path);
    final args = calls.last.arguments as Map;
    expect(args['selected'], path);
    expect(args['files'], [path]);
    final count = calls.length;
    await expectLater(
      manager.launch(emulator('ppsspp'), manager.app(emulator('ppsspp'))!, [
        path,
      ], '/other'),
      throwsFormatException,
    );
    expect(calls.length, count);
  });

  test(
    'unrecognized Android profile files are never adopted or overwritten',
    () async {
      final folder = Directory(
        '${data.path}/profiles/$profileId/emulators/ppsspp',
      );
      await folder.create(recursive: true);
      final sentinel = File('${folder.path}/keep-me');
      await sentinel.writeAsString('progress');
      await expectLater(
        manager.privateRoot(profileId, emulator('ppsspp')),
        throwsA(isA<FileSystemException>()),
      );
      expect(await sentinel.readAsString(), 'progress');
      expect(await File('${folder.path}/profile.json').exists(), false);
      expect(await Directory('${folder.path}/user').exists(), false);
    },
  );

  test('corrupt cross-profile storage records block launch without losing the last observation', () async {
    await configure('ppsspp');
    final uri = manager.tree(profileId, emulator('ppsspp'))!;
    await File('${data.path}/android/emulators.json').writeAsString(
      jsonEncode({
        'version': 1,
        'trees': {'c123456789abcdef0123456789abcdef:ppsspp': uri},
      }),
    );
    await manager.load();
    expect(manager.settingsKnown, false);
    expect(manager.app(emulator('ppsspp')), isNotNull);
    await expectLater(
      manager.launch(emulator('ppsspp'), manager.app(emulator('ppsspp'))!, [
        '/fixture/a',
      ], '/fixture/a'),
      throwsStateError,
    );
    expect(calls.where((c) => c.method == 'launch'), isEmpty);
  });

  test('an emulator build change cannot relabel old native states as the new build', () async {
    final api = SaveServer(), cloud = RecordingCloud(data);
    final session = AndroidGameSession(manager, cloud);
    CloudGame version(String state) => CloudGame(
      server: serverId,
      profile: profileId,
      user: 3,
      rom: 42,
      client: api,
      layout: ProgressLayout(
        '${data.path}/profiles/$profileId/emulators/ppsspp',
        'ppsspp-savedata-v1',
        'ULUS10340',
        [
          const ProgressArea('save', 'user/PSP/SAVEDATA'),
          ProgressArea(state, 'user/PSP/PPSSPP_STATE'),
        ],
      ),
    );
    await launch(session, game: version('states-original-android'));
    await session.finish(
      emulatorClosed: true,
      recovery: version('states-replaced-android'),
    );
    expect(cloud.calls.last, 'after:1');
    expect(cloud.finalized.single.layout.areas.map((a) => a.id), ['save']);
    session.dispose();
    api.close();
  });

  test('concurrent starts reserve before awaiting and keep the session lease through handoff', () async {
    final ready = Completer<void>(), returned = Completer<Object?>();
    handoff = (_) {
      ready.complete();
      return returned.future;
    };
    final cloud = RecordingCloud(data);
    final session = AndroidGameSession(manager, cloud);
    final first = launch(session);
    await ready.future;
    await expectLater(launch(session), throwsStateError);
    await expectLater(SessionLease.acquire(data), throwsStateError);
    await expectLater(session.finish(emulatorClosed: true), throwsStateError);
    returned.complete('0123456789abcdef0123456789abcdef');
    await first;
    expect(session.active, true);
    expect(cloud.calls, isEmpty);
    await expectLater(session.finish(emulatorClosed: false), throwsStateError);
    expect(await session.pending(), isNotNull);
    await session.finish(emulatorClosed: true);
    final lease = await SessionLease.acquire(data);
    await lease.release();
    session.dispose();
  });

  test('unknown handoff result retains recovery and restart needs explicit closure', () async {
    final api = SaveServer(), cloud = RecordingCloud(data);
    final session = AndroidGameSession(manager, cloud);
    handoff = (_) async => throw PlatformException(code: 'lost-reply');
    await expectLater(
      launch(session, game: game(cloud, api)),
      throwsA(isA<PlatformException>()),
    );
    expect(await session.pending(), isNotNull);
    expect(cloud.calls, ['before:$profileId']);
    session.dispose();
    // Wait for the explicitly released coordinator, not for an emulator exit.
    await Future<void>.delayed(Duration.zero);
    final recovered = AndroidGameSession(manager, cloud);
    await expectLater(launch(recovered), throwsStateError);
    await recovered.finish(emulatorClosed: true, recovery: game(cloud, api));
    expect(cloud.calls.last, 'after:1');
    expect(await recovered.pending(), isNull);
    recovered.dispose();
    api.close();
  });

  test(
    'open native writers and wrong-account recovery cannot finalize saves',
    () async {
      final api = SaveServer(),
          cloud = RecordingCloud(data),
          session = AndroidGameSession(manager, RecordingCloud(data));
      writers = 1;
      await expectLater(launch(session), throwsStateError);
      expect(await session.pending(), isNull);
      writers = 0;
      await launch(session);
      writers = 1;
      await expectLater(session.finish(emulatorClosed: true), throwsStateError);
      expect(await session.pending(), isNotNull);
      writers = 0;
      await expectLater(
        session.finish(
          emulatorClosed: true,
          recovery: game(
            cloud,
            api,
            profile: 'c123456789abcdef0123456789abcdef',
          ),
        ),
        throwsStateError,
      );
      expect(await session.pending(), isNotNull);
      await session.finish(emulatorClosed: true);
      session.dispose();
      api.close();
    },
  );

  test('Android DS raw save uses existing BROOMM history and native .sav extension', () async {
    await configure('melonds');
    final rom = File('${data.path}/Ranger.nds');
    final bytes = Uint8List(32)..setRange(12, 16, ascii.encode('ARGP'));
    await rom.writeAsBytes(bytes);
    final platform = playablePlatforms.singleWhere((p) => p.slug == 'nds');
    final layout = await androidProgressLayout(
      manager,
      profileId,
      emulator('melonds'),
      platform,
      rom.path,
    );
    final api = SaveServer(), cloud = CloudSaves(data, notice: (_, _) {});
    final g = CloudGame(
      server: serverId,
      profile: profileId,
      user: 3,
      rom: 42,
      client: api,
      layout: layout,
    );
    final session = AndroidGameSession(manager, cloud);
    await session.start(
      server: serverId,
      profile: profileId,
      rom: 42,
      emulator: emulator('melonds'),
      app: manager.app(emulator('melonds'))!,
      files: [rom.path],
      selected: rom.path,
      game: g,
    );
    final save = await layout.target('save/game.sav');
    await save.writeAsBytes(List<int>.filled(512 * 1024, 0x51));
    await session.finish(emulatorClosed: true);
    final remote = api.records.values.single;
    expect(remote.slot, 'BROOMM');
    expect(
      remote.name,
      matches(r'^Broomm \[\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\]\.sav$'),
    );
    expect(api.contents[remote.id]!.length, 512 * 1024);
    session.dispose();
    api.close();
  });

  test('Android PSP save/state boundaries exclude installed DLC and unrelated titles', () async {
    await configure('ppsspp');
    final rom = File('${data.path}/Nplus.pbp');
    await rom.writeAsBytes(pspPbp());
    final layout = await androidProgressLayout(
      manager,
      profileId,
      emulator('ppsspp'),
      playablePlatforms.singleWhere((p) => p.slug == 'psp'),
      rom.path,
    );
    final root = Directory(layout.root);
    for (final path in [
      'user/PSP/SAVEDATA/ULUS10340DATA/DATA.BIN',
      'user/PSP/SAVEDATA/ULUS99999DATA/DATA.BIN',
      'user/PSP/GAME/ULUS10340/DLC.BIN',
    ]) {
      final file = await progressFile(root, path, createParents: true);
      await file.writeAsBytes([1, 2, 3]);
    }
    final files = await layout.files();
    expect(files.keys.toList(), ['save/ULUS10340DATA/DATA.BIN']);
    final state = layout.areas.singleWhere((a) => a.id.startsWith('states-'));
    expect(state.accepts('ULUS10340_1.02_0.ppst'), true);
    expect(state.accepts('ULUS99999_1.02_0.ppst'), false);
    expect(calls.any((c) => c.method == 'fingerprint'), true);
    await expectLater(
      androidProgressLayout(
        manager,
        profileId,
        emulator('eden'),
        playablePlatforms.singleWhere((p) => p.emulatorId == 'eden'),
        rom.path,
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'a disabled emulator remains installed and cannot be launched',
    () async {
      apps.first['enabled'] = 'false';
      await manager.load();
      final app = manager.app(emulator('ppsspp'))!;
      expect(app.enabled, false);
      expect(manager.error, isNull);
      await expectLater(
        manager.launch(emulator('ppsspp'), app, ['/fixture/a'], '/fixture/a'),
        throwsStateError,
      );
      expect(calls.where((c) => c.method == 'launch'), isEmpty);
    },
  );

  testWidgets(
    'finishing an interrupted Android session releases the recovery route',
    (t) async {
      final session = AndroidGameSession(manager, RecordingCloud(data));
      var finishes = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AndroidSessionScreen(
                    session: session,
                    title: 'Interrupted game',
                    emulator: 'PPSSPP',
                    recovering: true,
                    finish: () async {
                      finishes++;
                    },
                  ),
                ),
              ),
              child: const Text('Open recovery'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open recovery'));
      await t.pumpAndSettle();
      await t.tap(find.text('Finish game session'));
      await t.pumpAndSettle();
      await t.tap(find.text('Emulator closed · Finish'));
      await t.pumpAndSettle();
      expect(finishes, 1);
      expect(find.byType(AndroidSessionScreen), findsNothing);
      expect(find.text('Open recovery'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'Android game route launches directly and never shows controller pairing',
    (t) async {
      final session = AndroidGameSession(manager, RecordingCloud(data));
      var launches = 0;
      await t.pumpWidget(
        MaterialApp(
          home: AndroidSessionScreen(
            session: session,
            title: 'A game',
            emulator: 'PPSSPP',
            start: () async {
              ++launches;
            },
            finish: () => session.finish(emulatorClosed: true),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(PairingScreen), findsNothing);
      expect(launches, 1);
      expect(
        find.textContaining('Cloud save access is not configured'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
