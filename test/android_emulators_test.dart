import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/android/progress.dart';
import 'package:broomm/src/android/root_saves.dart';
import 'package:broomm/src/android/psp_root.dart';
import 'package:broomm/src/android/session.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/progress/files.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/shell/android_session_screen.dart';
import 'package:broomm/src/shell/controls.dart' show ConsoleButton;
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

class ObservedRetroArchSession extends AndroidGameSession {
  ObservedRetroArchSession(super.manager, super.cloud);
  AndroidRetroArchState exit = AndroidRetroArchState.running;
  @override
  Future<AndroidRetroArchState> finishIfRetroArchClosed() async {
    if (exit == AndroidRetroArchState.closed) active = false;
    return exit;
  }
}

class ObservedPspSession extends AndroidGameSession {
  ObservedPspSession(super.manager, super.cloud);
  AndroidPspState exit = AndroidPspState.running;
  int checks = 0;
  @override
  Future<AndroidPspState> finishIfPspClosed() async {
    checks++;
    if (exit == AndroidPspState.closed) active = false;
    return exit;
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
  Future<Object?> Function(MethodCall)? handoff, nativeSession;
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
    nativeSession = null;
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
            case 'canInstallPackages':
              return true;
            case 'ioBusy':
              return false;
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
            case 'rootSessionAvailable':
            case 'rootEmulatorLifecycle':
            case 'rootPspSharedLifecycle':
            case 'rootEmulatorStop':
            case 'rootDuckResume':
              return nativeSession?.call(call);
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

  test('Citra MMJ is an Android 3DS alternative with its own launch and storage contract', () async {
    const platform = RommPlatform(9, 'Nintendo 3DS', '3ds', 1);
    final choices = manager.choices(platform);
    expect(choices.map((e) => e.id), containsAll(['azahar', 'citra-mmj']));
    final mmj = emulator('citra-mmj');
    expect(mmj.activity, 'org.citra.emu.ui.EmulationActivity');
    expect(
      mmj.packages,
      containsAll(['org.citra.emu', 'com.antutu.ABenchMark']),
    );
    expect(manager.progressSupported(mmj), true);
    final discovery =
        calls.lastWhere((c) => c.method == 'installed').arguments as Map;
    expect(discovery['requiredActivities'], {
      'org.citra.emu': mmj.activity,
      'com.antutu.ABenchMark': mmj.activity,
    });
    await manager.installApk(mmj);
    final installation =
        calls.lastWhere((c) => c.method == 'installApk').arguments as Map;
    expect(installation['requiredActivity'], mmj.activity);
    expect(installation['packages'], mmj.packages);
    final m = ShellModel(ShellStorage(data), androidManager: manager);
    expect(m.defaultEmulator(platform), isNull);
    apps.add({
      'package': 'org.citra.emu',
      'version': '20251112',
      'build': buildHash,
    });
    await manager.load();
    expect(m.defaultEmulator(platform), isNull);
    await manager.confirmSharedStorage(
      mmj,
      'content://com.android.externalstorage.documents/tree/primary%3Acitra-emu',
    );
    m.profile = const SavedProfile(profileId, serverId, 3, 'Test');
    expect(m.defaultEmulator(platform), 'citra-mmj');
    await manager.launch(mmj, manager.app(mmj)!, [
      '/fixture/Test.3ds',
    ], '/fixture/Test.3ds');
    final args = calls.lastWhere((c) => c.method == 'launch').arguments as Map;
    expect(args['emulator'], 'citra-mmj');
    expect(args['activity'], mmj.activity);
    m.dispose();
    managerDisposed = true;
  });

  test('Android install completion survives restart and requires observed installation', () async {
    final defaults = <String>[];
    manager.onInstalled = (server, e) async => defaults.add('$server:${e.id}');
    final mmj = emulator('citra-mmj');
    await manager.installApk(mmj, server: serverId);
    await manager.load();
    expect(defaults, isEmpty);
    failure = PlatformException(code: 'query-failed');
    await manager.load();
    expect(defaults, isEmpty);
    manager.dispose();
    manager = AndroidEmulators(data, channel: channel, enabled: true)
      ..onInstalled = (server, e) async => defaults.add('$server:${e.id}');
    failure = null;
    apps.add({
      'package': 'org.citra.emu',
      'version': '20251112',
      'build': buildHash,
    });
    await manager.load();
    expect(defaults, ['$serverId:citra-mmj']);
    await manager.load();
    expect(defaults.length, 1);
    await manager.installApk(mmj, server: serverId);
    await manager.load(); // Opening/cancelling an installer is not success.
    expect(defaults.length, 1);
    await manager.cancelInstallationDefault(serverId);
    await manager.load(installationConfirmed: true);
    expect(defaults.length, 1);
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
      expect(m.defaultEmulator(switchPlatform), isNull);
      await manager.confirmSharedStorage(
        emulator('eden'),
        'content://dev.eden.eden_emulator.user/tree/root',
      );
      m.profile = const SavedProfile(profileId, serverId, 3, 'Test');
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
    expect(args.containsKey('rootedPsp'), isFalse);
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
    'rooted PSP task handoff requires its emulator and owning profile',
    () async {
      final before = calls.length;
      for (final id in ['ppsspp', 'melonds']) {
        await expectLater(
          manager.launch(
            emulator(id),
            manager.app(emulator(id))!,
            ['/fixture/Game.pbp'],
            '/fixture/Game.pbp',
            rootedPsp: true,
            profile: id == 'melonds' ? profileId : null,
          ),
          throwsFormatException,
        );
      }
      expect(calls.length, before);
    },
  );

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

  test('explicit closure confirmation permits sync; wrong-account recovery still preserves progress', () async {
    final api = SaveServer(),
        cloud = RecordingCloud(data),
        session = AndroidGameSession(manager, RecordingCloud(data));
    writers = 1;
    await launch(session);
    await expectLater(session.finish(emulatorClosed: false), throwsStateError);
    await expectLater(
      session.finish(
        emulatorClosed: true,
        recovery: game(cloud, api, profile: 'c123456789abcdef0123456789abcdef'),
      ),
      throwsStateError,
    );
    expect(await session.pending(), isNotNull);
    await session.finish(emulatorClosed: true);
    expect(await session.pending(), isNull);
    session.dispose();
    api.close();
  });

  test('Android DS raw save uses existing BROOMM history and native .sav extension', () async {
    await configure('melonds');
    final rom = File('${data.path}/Ranger.nds');
    final bytes = Uint8List(32)..setRange(12, 16, ascii.encode('ARGP'));
    await rom.writeAsBytes(bytes);
    final platform = playablePlatforms.singleWhere(
      (p) => p.emulatorId == 'melonds',
    );
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
    final oldState = await progressFile(
      root,
      'user/PSP/PPSSPP_STATE/ULUS10340_1.02_0.ppst',
      createParents: true,
    );
    await oldState.writeAsBytes([7]);
    expect(layout.areas.where((a) => a.id.startsWith('states-')), isEmpty);
    expect(await oldState.readAsBytes(), [7]);
    expect(calls.any((c) => c.method == 'fingerprint'), true);
    await expectLater(
      androidProgressLayout(
        manager,
        profileId,
        emulator('eden'),
        playablePlatforms.singleWhere((p) => p.emulatorId == 'eden'),
        rom.path,
      ),
      throwsStateError,
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

  test('force close checkpoints the exact session and syncs only once the emulator is stopped', () async {
    final api = SaveServer(), cloud = RecordingCloud(data);
    final session = AndroidGameSession(manager, cloud);
    var lostReply = true, reopened = false;
    nativeSession = (call) async {
      if (call.method == 'rootEmulatorLifecycle')
        return {'state': reopened ? 'running' : 'idle'};
      if (call.method != 'rootEmulatorStop') return null;
      expect(call.arguments, {
        'package': 'org.ppsspp.ppsspp',
        'build': buildHash,
      });
      expect((await session.pending())?['forceClosed'], isTrue);
      if (lostReply) throw PlatformException(code: 'lost-reply');
      return null;
    };
    try {
      await launch(session, game: game(cloud, api));
      await expectLater(
        session.forceClose(),
        throwsA(isA<PlatformException>()),
      );
      expect(cloud.calls, ['before:$profileId']);
      expect(session.active, isTrue);
      expect((await session.pending())?['forceCloseSync'], isNull);

      lostReply = false;
      await session.forceClose();
      reopened = true;
      await expectLater(session.finish(emulatorClosed: true), throwsStateError);
      expect(cloud.calls, ['before:$profileId']);
      expect(await session.pending(), isNotNull);
      reopened = false;
      await session.forceClose();
      await session.finish(emulatorClosed: true);
      expect(cloud.calls, ['before:$profileId', 'after:0']);
      expect(await session.pending(), isNull);
    } finally {
      session.dispose();
      api.close();
    }
  });

  test('a lost force-close reply keeps captured progress for review', () async {
    final api = SaveServer(), cloud = RecordingCloud(data);
    final session = AndroidGameSession(manager, cloud);
    nativeSession = (call) async {
      if (call.method == 'rootEmulatorStop')
        throw PlatformException(code: 'lost-reply');
      return null;
    };
    try {
      await launch(session, game: game(cloud, api));
      await expectLater(
        session.forceClose(),
        throwsA(isA<PlatformException>()),
      );
      expect((await session.pending())?['forceCloseSync'], isNull);
      await session.finish(emulatorClosed: true);
      expect(cloud.calls, ['before:$profileId', 'after:1']);
    } finally {
      session.dispose();
      api.close();
    }
  });

  test('shared PPSSPP tracks the new activity in its cached process and syncs a verified exit', () async {
    final api = SaveServer(), cloud = RecordingCloud(data);
    final session = AndroidGameSession(manager, cloud);
    const process = {
      'pid': 42,
      'startTicks': 21,
      'launchElapsed': 500,
      'launchWall': 1500,
      'activityCreated': 1512,
    };
    nativeSession = (call) async {
      if (call.method == 'rootSessionAvailable') return true;
      expect(call.method, 'rootPspSharedLifecycle');
      final args = call.arguments as Map;
      expect(args['package'], 'org.ppsspp.ppsspp');
      if (args.containsKey('process')) {
        expect(args['process'], process);
        return {'state': 'closed', 'elapsed': 650, 'wall': 1650};
      }
      if (args.containsKey('launchElapsed')) {
        expect(args['launchElapsed'], 500);
        expect(args['launchWall'], 1500);
        return {'state': 'running', 'elapsed': 520, 'wall': 1520, ...process};
      }
      return {'state': 'idle', 'elapsed': 500, 'wall': 1500};
    };
    try {
      await launch(session, game: game(cloud, api));
      expect(session.tracksStandaloneExit, isTrue);
      expect(
        await session.finishIfStandaloneClosed(),
        AndroidRetroArchState.closed,
      );
      expect(cloud.calls, ['before:$profileId', 'after:0']);
      expect(await session.pending(), isNull);
    } finally {
      session.dispose();
      api.close();
    }
  });

  test(
    'standalone session automatically syncs only a matched normal exit',
    () async {
      apps.first['version'] = 'unreviewed';
      await manager.load();
      final api = SaveServer(), cloud = RecordingCloud(data);
      final session = AndroidGameSession(manager, cloud);
      var exit = 'interrupted';
      const observed = {
        'pid': 42,
        'startTicks': 51,
        'observedElapsed': 512,
        'observedWall': 1551,
      };
      nativeSession = (call) async {
        if (call.method == 'rootSessionAvailable') return true;
        expect(call.method, 'rootEmulatorLifecycle');
        final args = call.arguments as Map;
        expect(args['package'], 'org.ppsspp.ppsspp');
        expect(args['build'], buildHash);
        if (args.containsKey('launchedAfter')) {
          expect(args['launchedAfter'], 500);
          return {'state': 'running', ...observed};
        }
        if (args.containsKey('process')) {
          expect(args['process'], observed);
          return {'state': exit};
        }
        return {'state': 'idle', 'elapsed': 500};
      };
      try {
        await launch(session, game: game(cloud, api));
        expect(session.tracksStandaloneExit, isTrue);
        expect(
          await session.finishIfStandaloneClosed(),
          AndroidRetroArchState.interrupted,
        );
        expect(cloud.calls, ['before:$profileId']);
        expect(session.active, isTrue);
        exit = 'closed';
        expect(
          await session.finishIfStandaloneClosed(),
          AndroidRetroArchState.closed,
        );
        expect(cloud.calls, ['before:$profileId', 'after:0']);
        expect(await session.pending(), isNull);
      } finally {
        session.dispose();
        api.close();
      }
    },
  );

  test('DuckStation resume addresses the existing game without opening its launcher', () async {
    const package = 'com.github.stenzek.duckstation';
    apps.add({'package': package, 'version': 'fixture', 'build': buildHash});
    await manager.load();
    final session = AndroidGameSession(manager, RecordingCloud(data));
    final duck = emulator('duckstation');
    try {
      await expectLater(session.resumeDuckGame(), throwsStateError);
      await session.start(
        server: serverId,
        profile: profileId,
        rom: 42,
        emulator: duck,
        app: manager.app(duck)!,
        files: ['/fixture/Game.chd'],
        selected: '/fixture/Game.chd',
      );
      await expectLater(session.resumeDuckGame(), throwsStateError);
      const process = {'pid': 42, 'startTicks': 51};
      final journal = await progressFile(data, 'android/duck-swap.json');
      await progressWrite(journal, {
        ...(await session.pending())!,
        'binding': {'build': buildHash},
        'process': process,
      });
      await session.resumeDuckGame();
      expect(calls.singleWhere((c) => c.method == 'rootDuckResume').arguments, {
        'package': package,
        'build': buildHash,
        'process': process,
      });
      await journal.delete();
      expect(calls.where((c) => c.method == 'open'), isEmpty);
      expect(session.active, isTrue);
      await session.finish(emulatorClosed: true);
    } finally {
      session.dispose();
    }
  });

  test('Android App info targets only the active emulator package', () async {
    final session = AndroidGameSession(manager, RecordingCloud(data));
    try {
      await expectLater(session.openEmulatorAppInfo(), throwsStateError);
      expect(calls.where((call) => call.method == 'emulatorAppInfo'), isEmpty);

      await launch(session);
      await session.openEmulatorAppInfo();
      final request = calls.singleWhere(
        (call) => call.method == 'emulatorAppInfo',
      );
      expect(request.arguments, {'package': 'org.ppsspp.ppsspp'});
      expect(await session.pending(), isNotNull);
      expect(session.active, isTrue);
      await session.finish(emulatorClosed: true);
    } finally {
      session.dispose();
    }
  });

  testWidgets(
    'returning from an emulator offers sync and declining retains the active session',
    (t) async {
      final session = AndroidGameSession(manager, RecordingCloud(data));
      await t.runAsync(() => launch(session));
      var finishes = 0;
      await t.pumpWidget(
        MaterialApp(
          home: AndroidSessionScreen(
            session: session,
            recovering: true,
            cloudReady: true,
            title: 'A game',
            emulator: 'PPSSPP',
            finish: () async {
              finishes++;
            },
          ),
        ),
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.text('Emulator closed · Sync progress'), findsOneWidget);
      await t.tap(find.text('Keep playing'));
      await t.pumpAndSettle();
      expect(finishes, 0);
      expect(session.active, true);
      await t.runAsync(() async {
        expect(await session.pending(), isNotNull);
        await session.finish(emulatorClosed: true);
      });
      await t.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('Android sync and play and Back have separate touch bounds', (
    t,
  ) async {
    final session = AndroidGameSession(manager, RecordingCloud(data));
    await t.pumpWidget(
      MaterialApp(
        home: AndroidSessionScreen(
          session: session,
          title: 'Minish Cap',
          emulator: 'RetroArch',
          cloudReady: true,
          start: ({required bool emulatorClosed}) async {},
          finish: () async {},
        ),
      ),
    );
    final play = find.widgetWithText(
      ConsoleButton,
      'Emulator closed · Sync and play',
    );
    final back = find.widgetWithText(ConsoleButton, 'Back');
    expect(t.getRect(back).top - t.getRect(play).bottom, 12);
    await t.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'rooted RetroArch launches and syncs without confirmation when verified',
    (t) async {
      final session = ObservedRetroArchSession(manager, RecordingCloud(data));
      var launches = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AndroidSessionScreen(
                    session: session,
                    title: 'Minish Cap',
                    emulator: 'RetroArch',
                    cloudReady: true,
                    rooted: true,
                    resume: () async {},
                    start: ({required bool emulatorClosed}) async {
                      expect(emulatorClosed, isFalse);
                      launches++;
                      session.active = true;
                    },
                    finish: () async =>
                        fail('A verified exit needs no confirmation.'),
                  ),
                ),
              ),
              child: const Text('Play'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Play'));
      await t.pumpAndSettle();
      expect(launches, 1);
      expect(find.text('Emulator closed · Sync and play'), findsNothing);

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.text('Return to emulator'), findsOneWidget);
      expect(find.text('Android App info'), findsNothing);

      session.exit = AndroidRetroArchState.closed;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.byType(AndroidSessionScreen), findsNothing);
      expect(find.text('Play'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'rooted PSP completes from app lifecycle without an activity result',
    (t) async {
      final session = ObservedPspSession(manager, RecordingCloud(data));
      session.exit = AndroidPspState.closed;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AndroidSessionScreen(
                    session: session,
                    title: 'Lumines II',
                    emulator: 'PPSSPP',
                    cloudReady: true,
                    rooted: true,
                    start: ({required bool emulatorClosed}) async {
                      session.active = true;
                    },
                    finish: () async =>
                        fail('Native exit needs no confirmation.'),
                  ),
                ),
              ),
              child: const Text('Play PSP'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Play PSP'));
      await t.pumpAndSettle();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(session.active, isFalse);
      expect(session.checks, 1);
      expect(find.byType(AndroidSessionScreen), findsNothing);
      expect(find.text('Play PSP'), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(session.checks, 1);
      await t.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'rooted PSP retains live and uncertain writers on lifecycle return',
    (t) async {
      final session = ObservedPspSession(manager, RecordingCloud(data));
      var resumes = 0;
      await t.pumpWidget(
        MaterialApp(
          home: AndroidSessionScreen(
            session: session,
            title: 'Lumines II',
            emulator: 'PPSSPP',
            rooted: true,
            cloudReady: true,
            start: ({required bool emulatorClosed}) async =>
                session.active = true,
            resume: () async => resumes++,
            finish: () async => fail('A live writer must not synchronize.'),
          ),
        ),
      );
      await t.pumpAndSettle();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(session.active, isTrue);
      await t.tap(find.text('Check for exit'));
      await t.pumpAndSettle();
      expect(session.active, isTrue);
      expect(session.checks, 2);
      await t.tap(find.text('Return to emulator'));
      await t.pumpAndSettle();
      expect(resumes, 1);
      session.exit = AndroidPspState.unknown;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(session.active, isTrue);
      expect(session.checks, 3);
      expect(find.byType(AndroidSessionScreen), findsOneWidget);
      expect(find.text('Android App info'), findsNothing);
      await t.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('cold RetroArch offers its normal launcher and a play retry', (
    t,
  ) async {
    final session = AndroidGameSession(manager, RecordingCloud(data));
    var setupOpened = false, played = false;
    await t.pumpWidget(
      MaterialApp(
        home: AndroidSessionScreen(
          session: session,
          title: 'Minish Cap',
          emulator: 'RetroArch',
          cloudReady: true,
          rooted: true,
          start: ({required bool emulatorClosed}) async {
            expect(emulatorClosed, isFalse);
            if (!setupOpened) throw const AndroidRetroArchSetupRequired();
            played = true;
          },
          resume: () async => setupOpened = true,
          finish: () async => fail('Opening setup does not start save sync.'),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(played, isFalse);
    await t.tap(find.text('Open RetroArch'));
    await t.pumpAndSettle();
    expect(setupOpened, isTrue);
    expect(played, isFalse);
    await t.tap(find.text('Check and play'));
    await t.pumpAndSettle();
    expect(played, isTrue);
    expect(find.text('Open RetroArch'), findsNothing);
    await t.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'unverified PSP preparation offers native open and a guarded retry',
    (t) async {
      final session = AndroidGameSession(manager, RecordingCloud(data));
      var opened = false, attempts = 0, finishes = 0;
      await t.pumpWidget(
        MaterialApp(
          home: AndroidSessionScreen(
            session: session,
            title: 'LocoRoco',
            emulator: 'PPSSPP',
            cloudReady: true,
            rooted: true,
            start: ({required bool emulatorClosed}) async {
              expect(emulatorClosed, isFalse);
              attempts++;
              if (!opened) throw StateError('PPSSPP shutdown is unverified.');
              session.active = true;
            },
            resume: () async => opened = true,
            finish: () async => finishes++,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(session.active, isFalse);
      expect(attempts, 1);
      await t.tap(find.text('Open PPSSPP'));
      await t.pumpAndSettle();
      expect(opened, isTrue);
      expect(attempts, 1);
      expect(finishes, 0);
      await t.tap(find.text('Check and play'));
      await t.pumpAndSettle();
      expect(attempts, 2);
      expect(session.active, isTrue);
      expect(find.text('Open PPSSPP'), findsNothing);
      await t.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('failed native PSP open stays visible without starting sync', (
    t,
  ) async {
    final session = AndroidGameSession(manager, RecordingCloud(data));
    var attempts = 0;
    await t.pumpWidget(
      MaterialApp(
        home: AndroidSessionScreen(
          session: session,
          title: 'LocoRoco',
          emulator: 'PPSSPP',
          cloudReady: true,
          rooted: true,
          start: ({required bool emulatorClosed}) async {
            attempts++;
            throw StateError('PPSSPP shutdown is unverified.');
          },
          resume: () async => throw StateError('Native launcher unavailable.'),
          finish: () async => fail('Opening the menu must not synchronize.'),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Open PPSSPP'));
    await t.pumpAndSettle();
    expect(find.textContaining('Native launcher unavailable.'), findsOneWidget);
    expect(find.text('Open PPSSPP'), findsOneWidget);
    expect(find.text('Check and play'), findsOneWidget);
    expect(attempts, 1);
    expect(session.active, isFalse);
    expect(await t.runAsync(session.pending), isNull);
    await t.pumpWidget(const SizedBox());
    session.dispose();
  });

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
            start: ({required bool emulatorClosed}) async {
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
        find.textContaining('Connect this emulator’s save folder'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
