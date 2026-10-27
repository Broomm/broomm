import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/addons/service.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';

import 'support/addon_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.broomm/prototype'),
          (call) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.broomm/prototype'),
          null,
        );
  });
  late Directory root;
  late ShellModel model;
  late AddonFiles client;
  late FakeCiaImport importer;
  late RommGame game;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-addon-shell-');
    final files = {'Game.cci': base3ds(), 'dlc/Pack.cia': addonCia()};
    game = await addonGame(root, files);
    client = filesClient(game, files);
    importer = FakeCiaImport();
    model = ShellModel(
      ShellStorage(root),
      gameAddons: GameAddons(
        root,
        GameLibrary(root),
        prepare: (id, c) => addonRuntime(root, id, c),
        importer: importer.call,
      ),
    );
    model.server = const SavedServer(
      addonServer,
      'https://fixture.example',
      '5.4.0',
    );
    model.profile = const SavedProfile(addonProfile, addonServer, 7, 'Player');
    model.client = client;
    model.screen = ShellScreen.home;
    model.records = ShellRecords(
      servers: [model.server!],
      profiles: [model.profile!],
    );
  });
  tearDown(() async {
    await model.finishDownloads();
    model.dispose();
    await root.delete(recursive: true);
  });
  test('new game download automatically imports DLC and a repeated menu check does no transfer or native import', () async {
    await model.downloadGame(game);
    expect(model.installed.single.game.id, game.id);
    expect(importer.imported.length, 1);
    expect(
      client.downloads.length,
      2,
    ); // Base + DLC, with reuse during native import.
    expect(model.downloadError, isNull);
    expect(model.downloadMessage, contains('Installed 1'));
    await model.downloadUpdatesAndDlc(game.id);
    expect(model.downloadMessage, 'Updates and DLC are up to date.');
    expect(importer.imported.length, 1);
    expect(client.downloads.length, 2);
  }, skip: !Platform.isMacOS);

  test('cancellation keeps an admitted add-on writer and its queue worker active until rollback finishes', () async {
    final entered = Completer<DownloadCancellation>(),
        release = Completer<void>(),
        finished = Completer<void>();
    importer.beforeFinish = (c) async {
      entered.complete(c);
      await release.future;
      c.check();
    };
    final work = model.downloadGame(game).whenComplete(finished.complete);
    final cancellation = await entered.future;
    try {
      await expectLater(SessionLease.acquire(root), throwsStateError);
      model.cancelDownload(model.queuedGame(game.id)!);
      await cancellation.whenCancelled;
      await Future<void>(() {});
      expect(finished.isCompleted, false);
      expect(model.downloading, true);
      await expectLater(SessionLease.acquire(root), throwsStateError);
    } finally {
      release.complete();
      await work;
    }
    expect(model.downloading, false);
    expect(model.installation(game.id), isNotNull);
    final lease = await SessionLease.acquire(root);
    await lease.release();
  }, skip: !Platform.isMacOS);

  test('automatic import failure keeps a playable base; manual retry finishes, and failed catalogue refresh retains installed DLC', () async {
    importer.fail = true;
    await model.downloadGame(game);
    expect(model.installed.single.problem, isNull);
    expect(await model.installed.single.directory.exists(), true);
    expect(model.downloadError, contains('is downloaded'));
    importer.fail = false;
    await model.downloadUpdatesAndDlc(game.id);
    expect(model.downloadError, isNull);
    expect(model.downloadMessage, contains('Installed 1'));
    client.problem = const RommFailure('RomM is offline', status: 503);
    await model.downloadUpdatesAndDlc(game.id);
    expect(model.downloadError, contains('RomM is offline'));
    expect(
      await File(
        '${root.path}/profiles/$addonProfile/emulators/azahar/addons.json',
      ).exists(),
      true,
    );
    expect(model.installed.length, 1);
  }, skip: !Platform.isMacOS);

  test(
    'a changed remote game identity cannot install or remove another title',
    () async {
      await model.downloadGame(game);
      client.detail = await addonGame(root, {
        'Game.cci': base3ds(),
        'dlc/Pack.cia': addonCia(),
      }, id: 19);
      await model.downloadUpdatesAndDlc(game.id);
      expect(model.downloadError, isNotNull);
      expect(importer.imported.length, 1);
      expect(model.installed.single.game.id, 18);
    },
    skip: !Platform.isMacOS,
  );

  testWidgets(
    'Home Select exposes Download Updates and DLC and gamepad activation checks the installed game',
    (t) async {
      t.view.physicalSize = const Size(1180, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(() => model.downloadGame(game));
      model.homeIndex = 3;
      await t.pumpWidget(BroommApp(model: model));
      await t.pumpAndSettle();
      await t.binding.defaultBinaryMessenger.handlePlatformMessage(
        'app.broomm/prototype',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('controller', 'options'),
        ),
        (_) {},
      );
      await t.pumpAndSettle();
      expect(find.text('Download Updates and DLC'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      // Select Artwork is first, the update action is the next controller row.
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      // Dialog continuations run in the widget clock, while hashes/processes
      // run on real I/O. Drive both, as in the artwork integration tests.
      for (
        var i = 0;
        i < 300 &&
            (model.downloading ||
                model.downloadMessage != 'Updates and DLC are up to date.');
        i++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(model.downloading, false);
      await t.pumpAndSettle();
      expect(find.text('Select Artwork'), findsNothing);
      expect(model.downloadMessage, 'Updates and DLC are up to date.');
      expect(model.downloadError, isNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
    skip: !Platform.isMacOS,
  );
}
