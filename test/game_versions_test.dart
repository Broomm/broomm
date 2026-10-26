import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/artwork.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';

import 'shell_model_test.dart' show FixtureRomm, settleModel;
import 'library_download_test.dart' show fixture, bytes;
import 'remembered_signin_test.dart' show MemoryCredentials;
import 'home_artwork_widget_test.dart' show driveArtwork;
import 'navigation_test.dart' show native, buttonNode;

class VersionCatalogue extends FixtureRomm {
  VersionCatalogue(super.server);
  bool reject = false;
  bool wrongIdentity = false;
  Completer<RommGame>? heldVersion;
  final transferred = <int>[];
  RommGame version(int id) {
    final f = fixture(id: id);
    return RommGame(
      id: id,
      name: 'Chronicle',
      platformId: 4,
      platform: 'GameCube',
      fsName: id == 1
          ? 'Chronicle (USA) (Rev 1).iso'
          : 'Chronicle (Europe).iso',
      fullPath: f.fullPath,
      files: f.files,
      bytes: f.bytes,
      siblings: [
        RommVariant(
          id == 1 ? 2 : 1,
          'Chronicle',
          id == 1 ? 'Chronicle (Europe)' : 'Chronicle (USA) (Rev 1)',
        ),
      ],
    );
  }

  @override
  Future<RommPage> games({
    String search = '',
    int? platform,
    int offset = 0,
    int limit = 24,
    bool recent = false,
  }) async => RommPage([version(1)], 1, 0, limit);
  @override
  Future<RommGame> game(int id) async {
    if (id == 2 && wrongIdentity) return version(99);
    if (id == 2 && heldVersion != null) return heldVersion!.future;
    if (id == 2 && reject)
      throw const RommFailure('This version is unavailable.', status: 403);
    return version(id);
  }

  @override
  Future<void> downloadFile(
    RommFile f,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    transferred.add(f.romId);
    await destination.writeAsBytes(bytes);
    onProgress(bytes.length);
  }
}

void main() {
  test('sibling identity survives receipts, self/duplicate siblings are collapsed and unrelated equal names stay distinct', () {
    final j = fixture().toJson()
      ..['sibling_roms'] = [
        {'id': 1, 'name': 'Same', 'fs_name_no_ext': 'Self'},
        {'id': 2, 'name': 'Same', 'fs_name_no_ext': 'Same (Europe)'},
        {'id': 2, 'name': 'Same', 'fs_name_no_ext': 'Duplicate'},
      ];
    final g = RommGame.fromJson(j);
    expect(g.versions.map((v) => v.id), [1, 2]);
    expect(
      RommGame.fromJson(g.toJson()).versions.last.fileName,
      'Same (Europe)',
    );
    final page = RommPage.fromJson({
      'items': [
        j,
        {...j, 'id': 3, 'sibling_roms': []},
      ],
      'total': 2,
      'offset': 0,
      'limit': 2,
    });
    expect(page.games.map((v) => v.id), [1, 3]);
    expect(() => RommVariant.fromJson({'id': -1}), throwsFormatException);
  });

  group('version download workflow', () {
    late Directory root;
    late ShellModel model;
    late VersionCatalogue catalogue;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('broomm-versions-');
      model = ShellModel(
        ShellStorage(root),
        credentials: MemoryCredentials(),
        clientFactory: (uri) => catalogue = VersionCatalogue(uri),
      );
      await model.start();
      await model.addServer('https://versions.example');
      await model.login('Player', 'fixture');
      await settleModel(model);
      await model.browse(platform: 4);
      model.navigate(ShellScreen.store);
    });
    tearDown(() async {
      model.dispose();
      await root.delete(recursive: true);
    });
    Future<void> open(WidgetTester t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1100, 800);
      await t.binding.setSurfaceSize(const Size(1100, 800));
      await t.pumpWidget(BroommApp(model: model));
      await t.pumpAndSettle();
      expect(find.byType(GameCard), findsOneWidget);
      await t.tap(find.byType(GameCard));
      await t.pumpAndSettle();
      await t.tap(find.text('Download game'));
      await driveArtwork(
        t,
        () => find
            .byKey(const ValueKey('download-version-2'))
            .evaluate()
            .isNotEmpty,
      );
    }

    Future<void> finish(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    }

    testWidgets(
      'one Store entry offers filename-tagged versions and controller choice installs only the selected identity',
      (t) async {
        await open(t);
        await t.pumpAndSettle();
        expect(
          buttonNode(
            t,
            find.byKey(const ValueKey('download-version-1')),
          ).hasFocus,
          true,
        );
        t.view.physicalSize = const Size(390, 844);
        await t.binding.setSurfaceSize(const Size(390, 844));
        await t.pumpAndSettle();
        expect(
          buttonNode(
            t,
            find.byKey(const ValueKey('download-version-1')),
          ).hasFocus,
          true,
          reason:
              'Responsive details behind the modal must not steal its focus.',
        );
        expect(find.text('Chronicle (Europe)'), findsOneWidget);
        expect(find.text('Chronicle (USA) (Rev 1).iso'), findsOneWidget);
        await native(t, 'down');
        await native(t, 'accept');
        await driveArtwork(t, () => model.installed.length == 1);
        expect(model.installed.single.game.id, 2);
        expect(catalogue.transferred, [2]);
        expect(model.installation(1), isNull);
        expect(find.text('Choose a version'), findsNothing);
        expect(t.takeException(), isNull);
        await finish(t);
      },
    );
    testWidgets(
      'cancelling or failing a version keeps the chooser and library safe; profile changes reject a held selection',
      (t) async {
        await open(t);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(model.installed, isEmpty);
        expect(catalogue.transferred, isEmpty);
        await t.tap(find.text('Download game'));
        await driveArtwork(
          t,
          () => find
              .byKey(const ValueKey('download-version-2'))
              .evaluate()
              .isNotEmpty,
        );
        catalogue.reject = true;
        await t.tap(find.byKey(const ValueKey('download-version-2')));
        await driveArtwork(
          t,
          () => find.text('This version is unavailable.').evaluate().isNotEmpty,
        );
        expect(model.installed, isEmpty);
        expect(find.text('Choose a version'), findsOneWidget);
        catalogue.reject = false;
        catalogue.wrongIdentity = true;
        await t.tap(find.byKey(const ValueKey('download-version-2')));
        await driveArtwork(
          t,
          () => find
              .text('RomM returned a different game identity.')
              .evaluate()
              .isNotEmpty,
        );
        expect(catalogue.transferred, isEmpty);
        catalogue.wrongIdentity = false;
        catalogue.heldVersion = Completer<RommGame>();
        await t.tap(find.byKey(const ValueKey('download-version-2')));
        model.switchAccount();
        catalogue.heldVersion!.complete(catalogue.version(2));
        await driveArtwork(
          t,
          () => find.text('The active profile changed.').evaluate().isNotEmpty,
        );
        expect(catalogue.transferred, isEmpty);
        expect(model.installed, isEmpty);
        await finish(t);
      },
    );
  });
}
