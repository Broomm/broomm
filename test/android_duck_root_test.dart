import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/android/duck_root.dart';
import 'package:broomm/src/android/duck_root_store.dart';
import 'package:broomm/src/android/duck_session.dart';
import 'package:broomm/src/android/save_plan.dart';
import 'package:broomm/src/android/session.dart';
import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/progress/files.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'android_psp_root_test.dart' show PspRootFixture;
import 'cloud_saves_test.dart' show SaveServer, profileId, serverId;
import 'android_duck_states_test.dart' show duckStateEnvelope;

/// Native method boundary model. Real Android/ptrace evidence is independent.
class DuckRootFixture extends PspRootFixture {
  DuckRootFixture(super.root);
  @override
  AndroidEmulator get emulator =>
      androidEmulators.singleWhere((e) => e.id == 'duckstation');
  @override
  Map<String, String> get binding => {
    ...super.binding,
    'access': 'root-duck-v1',
    'package': 'com.github.stenzek.duckstation',
    'dataDir': '/data/user/0/com.github.stenzek.duckstation',
    'apk': androidDuckApk,
  };
  File get settings => File('${root.path}/settings.ini');
  File get bios => File('${root.path}/bios.bin');
  bool holdWriter = false;
  int settlingObservations = 0;
  String? losePath;
  Completer<void>? stopGate, stopEntered;
  Future<void> initialize() async {
    await settings.writeAsString(
      '[GPU]\nResolutionScale = 2\n[Pad1]\nType = AnalogController\n[Achievements]\nToken = original-private-token\n',
      flush: true,
    );
    await bios.writeAsBytes(List.filled(524288, 0), flush: true);
  }

  File resolve(Map a) => a['path'] == '@settings'
      ? settings
      : (a['path'] as String).startsWith('@bios/')
      ? bios
      : File('${memory(a).path}/${a['path']}');
  @override
  Future<Map<String, dynamic>> files(Map a, {required bool full}) async {
    final base = memory(a), out = <String, dynamic>{};
    await for (final f in base.list(recursive: true, followLinks: false)) {
      if (f is! File) continue;
      final path = fileIdentity(f.path.substring(base.path.length + 1));
      if (!full &&
          !(path.startsWith('games/${a['game']}/cards/') ||
              path.startsWith('games/${a['game']}/${a['stateGroup']}/')))
        continue;
      out[path] = await entry(f);
    }
    return out;
  }

  @override
  Future<Object?> call(MethodCall call) async {
    calls.add(call.method);
    final a = (call.arguments as Map?) ?? {};
    if (call.method == 'installed')
      return [
        {
          'package': binding['package'],
          'build': binding['build'],
          'version': '0.1-12693-gcc4a0d678',
        },
      ];
    if (call.method == 'ioBusy') return false;
    if (call.method == 'releaseGrants') return null;
    if (call.method == 'open') {
      state = 'menu';
      return null;
    }
    if (call.method == 'launch') {
      launches.add(Map.of(a));
      state = 'running';
      return 'native-grant';
    }
    if (call.method == 'returnToBroomm') {
      state = 'quiescent';
      return null;
    }
    if (call.method == 'rootDuckLifecycle' || call.method == 'rootDuckStop') {
      if (call.method == 'rootDuckStop') {
        if (holdWriter || state != 'quiescent' || a['process'] == null)
          throw PlatformException(code: 'writer-busy');
        final gate = stopGate;
        stopGate = null;
        stopEntered?.complete();
        await gate?.future;
        state = 'idle';
        return {'state': 'closed', 'elapsed': ++clock, 'wall': 100000 + clock};
      }
      var observed = state;
      if (settlingObservations > 0 && a['process'] != null) {
        settlingObservations--;
        observed = 'settling';
      }
      return {
        'state': observed == 'idle' && a['process'] != null
            ? 'interrupted'
            : observed,
        'elapsed': ++clock,
        'wall': 100000 + clock,
        'paused': state == 'quiescent' && a['pauseWall'] != null,
        if ({
          'menu',
          'running',
          'settling',
          'quiescent',
        }.contains(observed)) ...{
          'pid': 77,
          'startTicks': 99,
        },
      };
    }
    if (state != 'idle') throw PlatformException(code: 'writer-not-closed');
    if (call.method == 'rootDuckInspect')
      return {
        ...binding,
        'version': '0.1-12693-gcc4a0d678',
        'config': Uint8List.fromList(await settings.readAsBytes()),
        'settings': await entry(settings),
        'bios': {'bios.bin': await entry(bios)},
      };
    if (call.method == 'rootDuckProfile') {
      if (!await memory(a).exists())
        await put(a, 'profile.ini', (a['config'] as List).cast<int>());
      return {'status': 'ready', 'directory': androidDuckDirectory(a)};
    }
    if (call.method == 'rootDuckGame') return null;
    if (call.method == 'rootDuckProfileList' || call.method == 'rootDuckList')
      return {
        'files': await files(a, full: call.method == 'rootDuckProfileList'),
        'next': null,
      };
    if (call.method == 'rootDuckProfileRead' || call.method == 'rootDuckRead') {
      final source = resolve(a),
          observed = await entry(source),
          target = File(a['target'] as String);
      if (observed['sha256'] != a['sha256'] ||
          observed['metadata'] != a['metadata'])
        throw PlatformException(code: 'changed-capture');
      await target.create(exclusive: true);
      await source.copy(target.path);
      return null;
    }
    if (call.method == 'rootDuckProfileReplace' ||
        call.method == 'rootDuckReplace') {
      final target = resolve(a),
          observed = await target.exists() ? await entry(target) : null;
      if (observed?['sha256'] == a['after']) return observed;
      if (observed?['sha256'] != a['before'] ||
          observed != null && observed['metadata'] != a['metadata'])
        throw PlatformException(code: 'changed-publication');
      if (a['after'] == null) {
        await target.delete();
        return null;
      }
      await target.parent.create(recursive: true);
      await File(a['source'] as String).copy(target.path);
      if (loseReplace || losePath == a['path']) {
        loseReplace = false;
        losePath = null;
        throw PlatformException(code: 'lost-publication-reply');
      }
      return entry(target);
    }
    throw StateError('Unexpected method ${call.method}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.broomm/duck-root-test');
  late Directory temp, data;
  late DuckRootFixture native;
  late AndroidEmulators manager;
  late AndroidDuckRootStore roots;
  late CloudSaves cloud;
  late SaveServer api;
  late AndroidDuckSession session;
  const stateGroup = 'states-0123456789abcdef-android';
  Future<AndroidDuckPlan> plan([String profile = profileId]) async =>
      AndroidDuckPlan(
        ProgressLayout(
          (await manager.privateRoot(profile, native.emulator)).path,
          'duckstation-cards-v1',
          '42',
          [
            ProgressArea(
              'save',
              'user/games/42/cards',
              pattern: r'^card[12]\.mcd$',
            ),
            ProgressArea(
              stateGroup,
              'user/games/42/$stateGroup',
              pattern: r'^[A-Za-z0-9_-]+\.sav$',
            ),
          ],
        ),
        native.binding,
        profile,
        'f' * 32,
        platformId: 23,
      );
  CloudGame game(AndroidDuckPlan p) => CloudGame(
    server: serverId,
    profile: p.profile,
    user: api.user,
    rom: 42,
    client: api,
    layout: p,
  );
  Future<void> prepare(AndroidDuckPlan p) async {
    await session.prepare(game(p), p);
    await cloud.beforePlay(game(p));
    await session.cloudPrepared(game(p), p);
    await session.install(game(p), p);
  }

  List<int> card(int marker) {
    final b = List.filled(131072, 0);
    b[0] = 77;
    b[1] = 67;
    b[8192] = marker;
    return b;
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('broomm-duck-root-');
    data = await Directory('${temp.path}/data').create();
    native = DuckRootFixture(await Directory('${temp.path}/native').create());
    await native.initialize();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, native.call);
    manager = AndroidEmulators(data, channel: channel, enabled: true);
    roots = AndroidDuckRootStore(manager);
    cloud = CloudSaves(data, notice: (_, _) {});
    api = SaveServer();
    session = AndroidDuckSession(manager, cloud);
    await manager.load();
    await manager.connectDuckRoot(native.emulator);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    manager.dispose();
    api.close();
    await temp.delete(recursive: true);
  });
  test('whole cards and build states remain private to two accounts; original preferences and profile changes survive', () async {
    final original = await native.settings.readAsString(), p = await plan();
    await prepare(p);
    final r = await progressJson(await roots.profileFile(profileId));
    final published = androidIni(await native.settings.readAsString());
    final workspace = androidDuckDirectory(r);
    expect(published['BIOS/SearchDirectory'], '$workspace/bios');
    expect(published['MemoryCards/Directory'], '$workspace/games/42/cards');
    expect(
      published['MemoryCards/Card1Path'],
      '$workspace/games/42/cards/card1.mcd',
    );
    expect(
      await File('${native.memory(r).path}/profile.ini').readAsString(),
      isNot(contains('original-private-token')),
    );
    await session.launching(game(p), p);
    native.state = 'running';
    await session.identify(game(p), p, 100);
    expect(await session.exitState(game(p), p), AndroidDuckState.running);
    await native.put(r, 'games/42/cards/card1.mcd', card(3));
    await native.put(
      r,
      'games/42/$stateGroup/SLUS-00561_1.sav',
      duckStateEnvelope(p.publication),
    );
    await native.settings.writeAsString(
      (await native.settings.readAsString()).replaceFirst(
        'ResolutionScale = 2',
        'ResolutionScale = 3',
      ),
      flush: true,
    );
    native.state = 'quiescent';
    await session.finish(game(p), p, automatic: true);
    expect(await native.settings.readAsString(), original);
    expect(await (await p.target('save/card1.mcd')).readAsBytes(), card(3));
    expect(api.records, isNotEmpty);
    expect(api.stateRecords, isNotEmpty);
    const other = 'd123456789abcdef0123456789abcdef';
    api.user = 4;
    final second = await plan(other);
    await prepare(second);
    final secondRecord = await progressJson(await roots.profileFile(other));
    expect(
      await native.files({
        ...roots.arguments(secondRecord),
        ...second.arguments,
      }, full: false),
      isEmpty,
    );
    await session.launching(game(second), second);
    native.state = 'running';
    await session.identify(game(second), second, 100);
    await native.put(secondRecord, 'games/42/cards/card1.mcd', card(4));
    native.state = 'quiescent';
    await session.finish(game(second), second, automatic: true);
    api.user = 3;
    await prepare(p);
    expect(
      await File('${native.memory(r).path}/games/42/cards/card1.mcd')
          .readAsBytes(),
      card(3),
    );
    expect(
      await native.settings.readAsString(),
      contains('ResolutionScale = 3'),
    );
    await session.finish(game(p), p, automatic: false);
    expect(await native.settings.readAsString(), original);
  });
  test('lost settings publication reply is recovered from the durable loan without adopting standalone credentials', () async {
    final original = await native.settings.readAsString(),
        r = await roots.profile(serverId, profileId, native.binding);
    native.loseReplace = true;
    await expectLater(
      roots.borrow(r, kind: 'settings', transaction: progressNonce()),
      throwsA(isA<PlatformException>()),
    );
    expect(await roots.loan(), isNotNull);
    expect(await native.settings.readAsString(), isNot(original));
    await roots.restoreSettingsLoan();
    expect(await native.settings.readAsString(), original);
    expect(await roots.loan(), isNull);
  });
  test('busy writer and changed save routes refuse restoration and preserve both copies', () async {
    final r = await roots.profile(serverId, profileId, native.binding),
        original = await native.settings.readAsString();
    await roots.borrow(r, kind: 'settings', transaction: progressNonce());
    final borrowed = await native.settings.readAsString();
    native.state = 'running';
    await expectLater(roots.restoreSettingsLoan(), throwsStateError);
    expect(await native.settings.readAsString(), borrowed);
    native.state = 'idle';
    await native.settings.writeAsString(
      borrowed.replaceFirst('Card1Type = Shared', 'Card1Type = PerGameTitle'),
    );
    await expectLater(roots.restoreSettingsLoan(), throwsStateError);
    expect(await roots.loan(), isNotNull);
    expect(await native.settings.readAsString(), isNot(original));
  });
  for (final path in ['profile.ini', '@settings']) {
    test(
      'lost $path restoration reply preserves new private preferences and the exact standalone configuration',
      () async {
        final original = await native.settings.readAsString(),
            r = await roots.profile(serverId, profileId, native.binding);
        await roots.borrow(r, kind: 'settings', transaction: progressNonce());
        await native.settings.writeAsString(
          (await native.settings.readAsString()).replaceFirst(
            'ResolutionScale = 2',
            'ResolutionScale = 3',
          ),
          flush: true,
        );
        native.losePath = path;
        await expectLater(
          roots.restoreSettingsLoan(),
          throwsA(isA<PlatformException>()),
        );
        expect(await roots.loan(), isNotNull);
        await roots.restoreSettingsLoan();
        expect(await native.settings.readAsString(), original);
        expect(
          await File('${native.memory(r).path}/profile.ini').readAsString(),
          contains('ResolutionScale = 3'),
        );
        expect(await roots.loan(), null);
      },
    );
  }
  test('rooted PS1 supervisor launches separately and serializes automatic closure across its settings pause', () async {
    final original = await native.settings.readAsString();
    final content = Directory('${data.path}/library/$serverId/42/content');
    await content.create(recursive: true);
    final rom = await File('${content.path}/Game.chd').writeAsBytes([1, 2, 3]);
    await File('${content.parent.path}/receipt.json').writeAsString(
      jsonEncode({
        'version': 1,
        'serverId': serverId,
        'userId': api.user,
        'game': {
          'id': 42,
          'platform_slug': 'psx',
          'fs_name': 'Game',
          'revision': 'r1',
        },
        'files': [
          {'path': 'Game.chd', 'bytes': 3},
        ],
      }),
    );
    final p = await rootedAndroidDuckProgress(
      manager,
      profileId,
      native.emulator,
      rom.path,
      '42',
      [rom.path],
      platformId: 23,
    );
    final supervisor = AndroidGameSession(manager, cloud);
    addTearDown(supervisor.dispose);
    await supervisor.start(
      server: serverId,
      profile: profileId,
      rom: 42,
      emulator: native.emulator,
      app: manager.app(native.emulator)!,
      files: [rom.path],
      selected: rom.path,
      rooted: true,
      rootPlatform: 'psx',
      emulatorClosed: false,
      prepare: (_, _) async => game(p),
    );
    expect(native.launches.single['rootedDuck'], true);
    expect(native.launches.single.containsKey('root'), false);
    expect(await supervisor.finishIfDuckClosed(), AndroidDuckState.running);
    final r = await progressJson(await roots.profileFile(profileId));
    await native.put(r, 'games/42/cards/card1.mcd', card(3));
    native.state = 'unknown';
    expect(await supervisor.finishIfDuckClosed(), AndroidDuckState.unknown);
    expect(native.calls.where((m) => m == 'rootDuckStop'), isEmpty);
    native.state = 'quiescent';
    native.settlingObservations = 1;
    final gate = Completer<void>();
    native.stopGate = gate;
    native.stopEntered = Completer<void>();
    final closing = supervisor.finishIfDuckClosed();
    try {
      await Future.any<void>([
        native.stopEntered!.future,
        closing.then(
          (state) => throw StateError(
            'Closure ended before reaching the held guard: $state',
          ),
        ),
      ]);
      expect(supervisor.busy, true);
      expect(await supervisor.finishIfDuckClosed(), AndroidDuckState.unknown);
    } finally {
      gate.complete();
    }
    expect(await closing, AndroidDuckState.closed);
    expect(native.calls.where((m) => m == 'rootDuckStop'), hasLength(1));
    expect(await supervisor.pending(), null);
    expect(supervisor.active, false);
    expect(await native.settings.readAsString(), original);
    expect(await roots.loan(), null);
    expect(api.records, isNotEmpty);
  });
}
