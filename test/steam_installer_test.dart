import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/steam/cdp.dart';
import 'package:broomm/src/steam/installer.dart';
import 'package:broomm/src/steam/launch_target.dart';
import 'package:flutter_test/flutter_test.dart';

class LibraryConnection implements SteamConnection {
  String account = '76561198000000000';
  String session = '00000000-0000-0000-0000-000000000001';
  final jobs = <String, int>{};
  final targets = <int, String>{};
  final artwork = <int, Set<String>>{};
  final tokens = <String>[];
  int creates = 0;
  bool loseReply = false,
      visible = true,
      failConfigure = false,
      failArtwork = false;
  Completer<void>? held;

  @override
  Future<Map<String, dynamic>> evaluate(String expression) async {
    final input = jsonDecode(
      expression.substring(
        expression.lastIndexOf(')(') + 2,
        expression.length - 1,
      ),
    ) as Map;
    final op = input['op'];
    if (op == 'context') return {'account': account, 'session': session};
    if (input['account'] != account)
      return {'error': 'The Steam account changed.'};
    if (op == 'inspect') {
      await held?.future;
      return {
        'ids': visible
            ? targets.entries
                  .where(
                    (e) =>
                        e.value == input['target'] ||
                        e.key == input['id'] && e.value == input['previous'],
                  )
                  .map((e) => e.key)
                  .toList()
            : <int>[],
      };
    }
    if (op == 'create') {
      final token = input['token'] as String;
      tokens.add(token);
      final id = jobs.putIfAbsent(token, () {
        creates++;
        final id = 0xf1234500 + creates;
        targets[id] = input['target'] as String;
        return id;
      });
      if (loseReply) {
        loseReply = false;
        throw StateError('Lost native create reply');
      }
      return {'id': id};
    }
    final id = input['id'] as int;
    if (op == 'configure') {
      if (failConfigure) throw StateError('Steam details are still pending');
      targets[id] = input['target'] as String;
      return {'id': id};
    }
    if (op == 'artwork') {
      if (failArtwork) {
        failArtwork = false;
        throw StateError('Artwork confirmation failed');
      }
      artwork.putIfAbsent(id, () => {}).add(input['kind'] as String);
      return {'id': id, 'verified': true};
    }
    throw StateError('Unexpected operation');
  }

  @override
  Future<void> close() async {}
}

void main() {
  late Directory root;
  late LibraryConnection library;
  var path = '/application/Broomm with spaces';
  SteamInstaller installer() => SteamInstaller(
    enabled: true,
    loadAsset: (p) => File(p).readAsBytes(),
    connect: () async => library,
    launchTarget: () async => SteamLaunchTarget(path, '/application'),
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-steam-');
    root = Directory(await root.resolveSymbolicLinks());
    library = LibraryConnection();
    path = '/application/Broomm with spaces';
  });
  tearDown(() => root.delete(recursive: true));

  test('repeated installation and relocation retain one full unsigned shortcut ID and all four assets', () async {
    final first = await installer().install(root);
    expect(first.appId, greaterThan(0x7fffffff));
    expect(library.artwork[first.appId], {
      'cover',
      'horizontal',
      'hero',
      'logo',
    });
    expect((await installer().install(root)).appId, first.appId);
    path = '/another location/Broomm';
    expect((await installer().install(root)).appId, first.appId);
    expect(library.targets[first.appId], path);
    expect(library.creates, 1);
  });
  test('a lost native create reply is joined after reconnect without a second creation', () async {
    library
      ..loseReply = true
      ..visible = false;
    await expectLater(installer().install(root), throwsStateError);
    expect(library.creates, 1);
    final result = await installer().install(root);
    expect(library.tokens.toSet(), hasLength(1));
    expect(library.creates, 1);
    expect(library.artwork[result.appId], hasLength(4));
  });
  test('unpublished native ID and partial artwork cannot turn retries into duplicate shortcuts', () async {
    library.failConfigure = true;
    await expectLater(installer().install(root), throwsStateError);
    library
      ..visible = false
      ..failConfigure = false;
    await expectLater(installer().install(root), throwsStateError);
    expect(library.creates, 1);
    library
      ..visible = true
      ..failArtwork = true;
    await expectLater(installer().install(root), throwsStateError);
    final result = await installer().install(root);
    expect(library.creates, 1);
    expect(library.artwork[result.appId], hasLength(4));
  });
  test('ambiguous exact targets and a failed scan do not create or configure shortcuts', () async {
    library.targets.addAll({123: path, 456: path});
    await expectLater(installer().install(root), throwsStateError);
    expect(library.creates, 0);
    expect(library.artwork, isEmpty);
    expect(library.targets, {123: path, 456: path});
  });
  test('a held cross-process production lock prevents every Steam mutation and permits a retry', () async {
    final directory = await Directory('${root.path}/steam').create();
    final child = await Process.start('dart', [
      'test/support/hold_library_lock.dart',
      '${directory.path}/installation.lock',
    ]);
    try {
      expect(
        await child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'held',
      );
      await expectLater(installer().install(root), throwsStateError);
      expect(library.creates, 0);
    } finally {
      child.stdin.writeln('release');
      await child.stdin.close();
      expect(await child.exitCode, 0);
    }
    await installer().install(root);
    expect(library.creates, 1);
  });
  test('account separation and same-instance exclusion retain independent library ownership', () async {
    library.held = Completer<void>();
    final service = installer();
    final first = service.install(root);
    await expectLater(service.install(root), throwsStateError);
    library.held!.complete();
    final result = await first;
    library.account = '76561198000000001';
    // A second user may already have an exact-path shortcut; it is discovered
    // afresh rather than inheriting the previous account's receipt.
    expect((await installer().install(root)).appId, result.appId);
    expect(
      await Directory('${root.path}/steam')
          .list()
          .where((f) => f.path.endsWith('.json'))
          .length,
      2,
    );
  });
  test(
    'linked receipt directory is preserved without connecting to Steam',
    () async {
      final elsewhere = await Directory('${root.path}/elsewhere').create();
      await Link('${root.path}/steam').create(elsewhere.path);
      await expectLater(
        installer().install(root),
        throwsA(isA<FileSystemException>()),
      );
      expect(await elsewhere.list().isEmpty, isTrue);
      expect(library.creates, 0);
    },
    skip: Platform.isWindows
        ? 'Windows symlink privileges vary; native Unix ownership boundary'
        : false,
  );
}
