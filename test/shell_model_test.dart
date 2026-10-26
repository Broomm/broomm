import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:flutter_test/flutter_test.dart';

class FixtureRomm extends RommClient {
  FixtureRomm(super.server);
  final calls = <String>[];
  final pending = <String, Completer<RommPage>>{};
  bool isClosed = false;
  bool platformFailure = false;
  @override
  Future<String> checkServer() async => '5.4.0';
  @override
  Future<RommUser> login(String name, String password) async {
    calls.add('login');
    return RommUser(7, name);
  }

  @override
  Future<List<RommPlatform>> platforms() async {
    if (platformFailure)
      throw const RommFailure('platform denied', status: 403);
    return [const RommPlatform(4, 'GameCube', 'ngc', 40)];
  }

  @override
  Future<RommPage> games({
    String search = '',
    int? platform,
    int offset = 0,
    int limit = 24,
    bool recent = false,
  }) async {
    calls.add('$search/$platform/$offset');
    if (pending.containsKey(search)) return pending[search]!.future;
    return RommPage(
      List.generate(
        offset == 0 ? limit : 2,
        (i) => RommGame(
          id: offset + i,
          name: 'Game ${offset + i}',
          platformId: 4,
          platform: 'GameCube',
        ),
      ),
      limit + 2,
      offset,
      limit,
    );
  }

  @override
  Future<RommGame> game(int id) async =>
      RommGame(id: id, name: 'Game $id', platformId: 4, platform: 'GameCube');
  @override
  Future<Uint8List?> artwork(String path) async => null;
  @override
  void close() {
    isClosed = true;
    super.close();
  }
}

Future<void> settleModel(ShellModel model) async {
  for (var i = 0; i < 100 && (model.page == null || model.storeBusy); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  late Directory root;
  late ShellModel model;
  late List<FixtureRomm> clients;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-shell-model-');
    clients = [];
    model = ShellModel(
      ShellStorage(root),
      clientFactory: (uri) {
        final c = FixtureRomm(uri);
        clients.add(c);
        return c;
      },
    );
    await model.start();
  });
  tearDown(() async {
    model.dispose();
    await root.delete(recursive: true);
  });
  Future<void> signIn() async {
    await model.addServer('https://one.example');
    expect(await model.login('Player', 'not-persisted'), true);
    await settleModel(model);
  }

  test(
    'activation is explicit and restart remembers metadata without signing in',
    () async {
      await signIn();
      expect(model.screen, ShellScreen.home);
      model.switchAccount();
      expect(clients.last.isClosed, true);
      model.dispose();
      clients.clear();
      model = ShellModel(
        ShellStorage(root),
        clientFactory: (uri) {
          final c = FixtureRomm(uri);
          clients.add(c);
          return c;
        },
      );
      await model.start();
      expect(model.screen, ShellScreen.servers);
      expect(clients, isEmpty);
      expect(model.profile, isNull);
      await model.chooseServer(model.records.servers.single);
      expect(model.knownProfiles.single.name, 'Player');
      expect(clients, isEmpty);
      expect(
        await File('${root.path}/accounts.json').readAsString(),
        isNot(contains('not-persisted')),
      );
    },
  );
  test(
    'new searches and profile changes reject late catalogue results',
    () async {
      await signIn();
      final client = clients.last;
      client.pending['old'] = Completer();
      final old = model.browse(term: 'old');
      await model.browse(term: 'new');
      expect(model.search, 'new');
      final current = model.page;
      client.pending['old']!.complete(const RommPage([], 0, 0, 24));
      await old;
      expect(model.page, same(current));
      client.pending['late'] = Completer();
      final late = model.browse(term: 'late');
      model.switchAccount();
      client.pending['late']!.complete(const RommPage([], 0, 0, 24));
      await late;
      expect(model.page, isNull);
      expect(model.profile, isNull);
      expect(model.screen, ShellScreen.profiles);
      expect(client.isClosed, true);
    },
  );
  test('pagination uses server offsets, retains previous results on failure and resets filters', () async {
    await signIn();
    expect(model.hasMore, true);
    await model.loadMore();
    expect(model.page!.games.length, 26);
    expect(model.hasMore, false);
    expect(clients.last.calls, contains('/null/24'));
    await model.browse(term: 'test', platform: 4);
    expect(model.hasMore, true);
    await model.browse(term: '', clearPlatform: true);
    expect(model.platformId, isNull);
    expect(model.search, '');
    clients.last.platformFailure = true;
    await model.loadStore();
    expect(model.discoveryError, contains('platform denied'));
    expect(model.page, isNotNull);
  });
}
