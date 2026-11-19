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
import 'package:broomm/src/shell/library.dart';
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
  int checks = 0;

  @override
  Future<AndroidPspState> finishIfPspClosed() async {
    checks++;
    active = false;
    return AndroidPspState.closed;
  }
}

class UnverifiedAndroidSession extends AndroidGameSession {
  UnverifiedAndroidSession(super.manager, super.cloud);

  @override
  Future<bool> approveFinish(Future<bool> Function(bool) confirm) =>
      confirm(false);
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
  bool canStop = false, stopped = false;
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
    canStop = false;
    stopped = false;
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
            case 'canPrepareSharedFolder':
              return canStop;
            case 'emulatorStopped':
              return stopped;
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

  test(
    'declining an unverified launch leaves no recovery or save work',
    () async {
      final session = AndroidGameSession(manager, RecordingCloud(data));
      canStop = true;
      nativeSession = (call) async => {'state': 'unknown'};
      try {
        await session.start(
          server: serverId,
          profile: profileId,
          rom: 42,
          emulator: emulator('ppsspp'),
          app: manager.app(emulator('ppsspp'))!,
          files: ['/fixture/Game.pbp'],
          selected: '/fixture/Game.pbp',
          confirmClose: (available) async {
            expect(available, isTrue);
            return false;
          },
          prepare: (_, _) async => fail('Declining must not prepare saves.'),
        );
        expect(await session.pending(), isNull);
        expect(
          calls.where(
            (call) => {'rootEmulatorStop', 'launch'}.contains(call.method),
          ),
          isEmpty,
        );
        final lease = await SessionLease.acquire(data);
        await lease.release();
      } finally {
        session.dispose();
      }
    },
  );

  test(
    'confirmed force stop precedes launch even if the observer stays unknown',
    () async {
      final session = AndroidGameSession(manager, RecordingCloud(data));
      canStop = true;
      nativeSession = (call) async => call.method == 'rootEmulatorStop'
          ? null
          : {'state': 'unknown', 'elapsed': 1, 'wall': 1};
      try {
        await session.start(
          server: serverId,
          profile: profileId,
          rom: 42,
          emulator: emulator('ppsspp'),
          app: manager.app(emulator('ppsspp'))!,
          files: ['/fixture/Game.pbp'],
          selected: '/fixture/Game.pbp',
          confirmClose: (available) async {
            expect(available, isTrue);
            expect(
              calls.where((call) => call.method == 'rootEmulatorStop'),
              isEmpty,
            );
            return true;
          },
        );
        final stop = calls.indexWhere(
          (call) => call.method == 'rootEmulatorStop',
        );
        final handoff = calls.indexWhere((call) => call.method == 'launch');
        expect(stop, greaterThanOrEqualTo(0));
        expect(handoff, greaterThan(stop));
        expect((await session.pending())?['launched'], isTrue);
        await session.finish(emulatorClosed: true);
      } finally {
        session.dispose();
      }
    },
  );

  test('a confirmed force stop syncs the original session without a second closure check', () async {
    final api = SaveServer(), cloud = RecordingCloud(data);
    final session = AndroidGameSession(manager, cloud);
    canStop = true;
    var observations = 0;
    nativeSession = (call) async {
      if (call.method == 'rootPspSharedLifecycle' ||
          call.method == 'rootEmulatorLifecycle') {
        observations++;
        return {'state': 'unknown', 'elapsed': 1, 'wall': 1};
      }
      if (call.method != 'rootEmulatorStop') return null;
      expect(call.arguments, {
        'package': 'org.ppsspp.ppsspp',
        'build': buildHash,
      });
      expect((await session.pending())?['forceClosed'], isTrue);
      return null;
    };
    try {
      await launch(session, game: game(cloud, api));
      expect(await session.approveFinish((available) async => false), isFalse);
      expect(cloud.calls, ['before:$profileId']);
      expect(await session.pending(), isNotNull);
      expect(
        await session.approveFinish((available) async {
          expect(available, isTrue);
          return true;
        }),
        isTrue,
      );
      final beforeFinish = observations;
      await session.finish(emulatorClosed: true);
      expect(observations, beforeFinish);
      expect(cloud.calls, ['before:$profileId', 'after:0']);
      expect(await session.pending(), isNull);
    } finally {
      session.dispose();
      api.close();
    }
  });

  test(
    'deferring sync warns on the game until the original session finishes',
    () async {
      await configure('ppsspp');
      final model = ShellModel(ShellStorage(data), androidManager: manager)
        ..server = const SavedServer(serverId, 'https://romm.invalid', '5.4.0')
        ..profile = const SavedProfile(profileId, serverId, 3, 'Test')
        ..installed = [
          InstalledGame(
            const RommGame(
              id: 42,
              name: 'Fixture game',
              platformId: 9,
              platform: 'PSP',
              platformSlug: 'psp',
              fsName: 'Game.pbp',
              fullPath: 'psp/Game.pbp',
            ),
            data,
            3,
          ),
        ];
      final status = await progressFile(
        data,
        'cloud-saves/$serverId/$profileId/42/state.json',
        createParents: true,
      );
      await progressWrite(status, {
        'synced': '2026-11-18T12:00:00Z',
        'pending': false,
        'emptySynced': true,
      });
      try {
        await model.refreshCloudStatus();
        expect(model.cloudStatus(42), CloudSaveStatus.synced);
        await launch(model.androidSession);
        expect(
          await model.androidSession.approveFinish((canStop) async {
            expect(canStop, isFalse);
            return false;
          }),
          isFalse,
        );
        await model.refreshCloudStatus();
        expect(model.cloudStatus(42), CloudSaveStatus.attention);
        expect(
          await model.androidSession.approveFinish((canStop) async {
            expect(canStop, isFalse);
            return true;
          }),
          isTrue,
        );
        await model.androidSession.finish(
          emulatorClosed: true,
          confirmedByPlayer: true,
        );
        await model.refreshCloudStatus();
        expect(model.cloudStatus(42), CloudSaveStatus.synced);
        expect(
          calls.where((call) => call.method == 'rootEmulatorStop'),
          isEmpty,
        );
      } finally {
        model.dispose();
        managerDisposed = true;
      }
    },
  );

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

  Widget appWithSession(AndroidSessionScreen screen) => MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => screen),
        ),
        child: const Text('Home'),
      ),
    ),
  );

  void emulatorReturned(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets('declining the return prompt goes Home and retains the session', (
    t,
  ) async {
    final session = UnverifiedAndroidSession(manager, RecordingCloud(data));
    var finishes = 0;
    await t.pumpWidget(
      appWithSession(
        AndroidSessionScreen(
          session: session,
          title: 'A game',
          emulator: 'PPSSPP',
          start: (_) async => session.active = true,
          finish: () async => finishes++,
        ),
      ),
    );
    await t.tap(find.text('Home'));
    await t.pumpAndSettle();
    emulatorReturned(t);
    await t.pumpAndSettle();
    expect(find.text('Is PPSSPP closed?'), findsOneWidget);
    final choices = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(ConsoleButton),
    );
    expect(choices, findsNWidgets(2));
    await t.tap(find.text('No'));
    await t.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(finishes, 0);
    expect(session.active, isTrue);
    await t.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'launch approval uses one force-close prompt and No returns Home',
    (t) async {
      final session = AndroidGameSession(manager, RecordingCloud(data));
      var launches = 0;
      await t.pumpWidget(
        appWithSession(
          AndroidSessionScreen(
            session: session,
            title: 'A game',
            emulator: 'PPSSPP',
            start: (confirm) async {
              if (await confirm(true)) launches++;
            },
            finish: () async =>
                fail('Declining launch must not finish or sync.'),
          ),
        ),
      );
      await t.tap(find.text('Home'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Broomm will force-close PPSSPP before continuing. Continue?',
        ),
        findsOneWidget,
      );
      final choices = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ConsoleButton),
      );
      expect(choices, findsNWidgets(2));
      await t.tap(find.text('No'));
      await t.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(launches, 0);
      await t.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('verified exits finish automatically without a closure prompt', (
    t,
  ) async {
    final session = ObservedRetroArchSession(manager, RecordingCloud(data))
      ..exit = AndroidRetroArchState.closed;
    await t.pumpWidget(
      appWithSession(
        AndroidSessionScreen(
          session: session,
          title: 'Minish Cap',
          emulator: 'RetroArch',
          rooted: true,
          start: (_) async => session.active = true,
          finish: () async => fail('A verified exit needs no confirmation.'),
        ),
      ),
    );
    await t.tap(find.text('Home'));
    await t.pumpAndSettle();
    emulatorReturned(t);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('rooted PPSSPP finishes on resume without an activity result', (
    t,
  ) async {
    final session = ObservedPspSession(manager, RecordingCloud(data));
    await t.pumpWidget(
      appWithSession(
        AndroidSessionScreen(
          session: session,
          title: 'Lumines II',
          emulator: 'PPSSPP',
          rooted: true,
          start: (_) async => session.active = true,
          finish: () async =>
              fail('Verified native closure needs no confirmation.'),
        ),
      ),
    );
    await t.tap(find.text('Home'));
    await t.pumpAndSettle();
    emulatorReturned(t);
    await t.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(session.checks, 1);
    await t.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('cold RetroArch offers setup and a Play retry', (t) async {
    final session = AndroidGameSession(manager, RecordingCloud(data));
    var setupOpened = false, played = false;
    await t.pumpWidget(
      appWithSession(
        AndroidSessionScreen(
          session: session,
          title: 'Minish Cap',
          emulator: 'RetroArch',
          rooted: true,
          start: (_) async {
            if (!setupOpened) throw const AndroidRetroArchSetupRequired();
            played = true;
            session.active = true;
          },
          openSetup: () async => setupOpened = true,
          finish: () async => fail('Opening setup does not start save sync.'),
        ),
      ),
    );
    await t.tap(find.text('Home'));
    await t.pumpAndSettle();
    await t.tap(find.text('Open RetroArch'));
    await t.pumpAndSettle();
    expect(played, isFalse);
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(played, isTrue);
    expect(find.text('Open RetroArch'), findsNothing);
    expect(find.byType(PairingScreen), findsNothing);
    await t.pumpWidget(const SizedBox());
    session.dispose();
  });
}
