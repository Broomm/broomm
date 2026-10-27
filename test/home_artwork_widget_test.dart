import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/steamgrid.dart';
import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/artwork.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/shell/home_screen.dart';
import 'package:broomm/src/shell/controls.dart';

import 'remembered_signin_test.dart' show MemoryCredentials;
import 'shell_model_test.dart' show FixtureRomm, settleModel;
import 'library_download_test.dart' show fixture, bytes;
import 'support/artwork_fixtures.dart';

class ArtworkCatalogue extends FixtureRomm {
  ArtworkCatalogue(super.server);
  bool mapped = true;
  @override
  Future<RommGame> game(int id) async {
    final g = fixture(id: id);
    return RommGame(
      id: g.id,
      name: 'Artwork Adventure',
      platformId: g.platformId,
      platform: g.platform,
      bytes: g.bytes,
      fsName: g.fsName,
      fullPath: g.fullPath,
      files: g.files,
      sgdbId: mapped ? 42 : null,
    );
  }

  @override
  Future<void> downloadFile(
    RommFile f,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    await destination.writeAsBytes(bytes);
    onProgress(bytes.length);
  }
}

class FixtureSteamGrid extends SteamGridClient {
  FixtureSteamGrid(super.key);
  bool fail = false;
  bool paged = false;
  final requests = <ArtworkKind>[];
  GridArtwork art(ArtworkKind kind) => GridArtwork(
    id: switch (kind) {
      ArtworkKind.icon => 201,
      ArtworkKind.hero => 202,
      ArtworkKind.logo => 203,
    },
    kind: kind,
    url: Uri.parse('https://cdn2.steamgriddb.com/${kind.name}.png'),
    thumb: Uri.parse('https://cdn2.steamgriddb.com/${kind.name}-thumb.png'),
    width: kind == ArtworkKind.icon ? 64 : 640,
    height: kind == ArtworkKind.icon ? 64 : 200,
    mime: 'image/png',
    author: 'Fixture artist',
  );
  @override
  Future<ArtworkPage> page(
    int gameId,
    ArtworkKind kind, {
    int page = 0,
    Object? owner,
  }) async {
    requests.add(kind);
    if (fail)
      throw const RommFailure('SteamGridDB is unavailable', status: 503);
    final base = art(kind);
    return ArtworkPage([
      if (!paged || page == 0)
        base
      else
        GridArtwork(
          id: base.id + 10,
          kind: kind,
          url: base.url,
          thumb: base.thumb,
          width: base.width,
          height: base.height,
          mime: base.mime,
          author: 'Second page artist',
        ),
    ], paged && page == 0);
  }

  @override
  Future<Uint8List> image(
    Uri uri, {
    bool thumbnail = false,
    Object? owner,
  }) async =>
      uri.path.contains('icon') ? artworkPng(64, 64) : artworkPng(640, 200);
}

Future<ShellModel> artworkFixture(
  Directory root, {
  required FixtureSteamGrid grid,
  MemoryCredentials? credentials,
}) async {
  final m = ShellModel(
    ShellStorage(root),
    credentials: credentials ?? MemoryCredentials(),
    clientFactory: ArtworkCatalogue.new,
    gridFactory: (_) => grid,
  );
  await m.start();
  await m.addServer('https://artwork.example');
  await m.login('Player', 'fixture');
  await settleModel(m);
  await m.steamGridCredentials.write(m.server!, m.profile!, 'fixture-sgdb-key');
  return m;
}

Future<void> driveArtwork(WidgetTester t, bool Function() finished) async {
  for (var i = 0; i < 300 && !finished(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(finished(), true);
  await t.pump();
}

Future<void> decodeArtworkImages(WidgetTester t) async {
  final images = t.widgetList<Image>(find.byType(Image)).toList();
  final errors = <Object>[];
  await t.runAsync(() async {
    for (final image in images) {
      var complete = false;
      final pending = precacheImage(
        image.image,
        t.element(find.byWidget(image)),
        onError: (error, _) => errors.add(error),
      ).whenComplete(() => complete = true);
      for (var i = 0; i < 100 && !complete; i++) {
        await t.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(
        complete,
        true,
        reason: 'The local image must finish decoding while real I/O and widget frames are driven together.',
      );
      await pending;
    }
  });
  await t.pumpAndSettle();
  expect(errors, isEmpty);
}

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
  late FixtureSteamGrid grid;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-artwork-widget-');
    grid = FixtureSteamGrid('fixture');
    model = await artworkFixture(root, grid: grid);
  });
  tearDown(() async {
    model.dispose();
    await root.delete(recursive: true);
  });
  Future<void> open(WidgetTester t, {Size size = const Size(1180, 800)}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    await t.binding.setSurfaceSize(size);
    await t.pumpWidget(BroommApp(model: model));
    await t.pumpAndSettle();
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.binding.setSurfaceSize(null);
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  }

  Future<void> download(WidgetTester t) async {
    await t.runAsync(() => model.downloadGame(fixture()));
    await t.pump();
  }

  testWidgets(
    'a mapped download opens square then hero pickers and persists a top-aligned, fading Home image with cropped-poster fallback',
    (t) async {
      await open(t);
      await download(t);
      await driveArtwork(
        t,
        () => find
            .byKey(const ValueKey('artwork-icon-201'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('Choose a square icon'), findsOneWidget);
      expect(find.text('Choose a background'), findsNothing);
      await t.tap(find.byKey(const ValueKey('artwork-icon-201')));
      await driveArtwork(
        t,
        () => find
            .byKey(const ValueKey('artwork-hero-202'))
            .evaluate()
            .isNotEmpty,
      );
      expect(grid.requests, [ArtworkKind.icon, ArtworkKind.hero]);
      await t.tap(find.byKey(const ValueKey('artwork-hero-202')));
      await driveArtwork(
        t,
        () => find
            .byKey(const ValueKey('artwork-logo-203'))
            .evaluate()
            .isNotEmpty,
      );
      await t.tap(find.byKey(const ValueKey('artwork-logo-203')));
      await driveArtwork(t, () => model.installed.single.artwork?.hero != null);
      model.homeSelection(3);
      await t.pumpAndSettle();
      await decodeArtworkImages(t);
      expect(model.installed.single.artwork!.logo, endsWith('/logo.png'));
      expect(find.byKey(const ValueKey('home-game-logo')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-game-title')), findsNothing);
      final play = find.byWidgetPredicate(
        (w) =>
            w is ConsoleButton &&
            w.focusNode?.debugLabel == 'Home primary action',
      );
      final options = find.widgetWithText(ConsoleButton, 'Options');
      expect(t.getCenter(play).dy, closeTo(t.getCenter(options).dy, 1));
      expect(t.getRect(options).left, greaterThan(t.getRect(play).right));
      final hero = t.widget<Image>(
        find.byKey(const ValueKey('home-hero-image')),
      );
      expect(hero.fit, BoxFit.cover);
      expect(hero.alignment, Alignment.topCenter);
      expect(t.getSize(find.byType(HomeBackground)).height, 600);
      expect(
        t
            .renderObject<RenderImage>(
              find.descendant(
                of: find.byType(HomeBackground),
                matching: find.byType(RawImage),
              ),
            )
            .image,
        isNotNull,
      );
      await t.runAsync(
        () => model.savePreferences(model.preferences.copy(showArtwork: false)),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-hero-image')), findsNothing);
      expect(find.byKey(const ValueKey('home-game-logo')), findsNothing);
      expect(find.byKey(const ValueKey('home-game-title')), findsOneWidget);
      t.view.physicalSize = const Size(320, 844);
      await t.binding.setSurfaceSize(const Size(320, 844));
      await t.pumpAndSettle();
      expect(t.getCenter(play).dy, closeTo(t.getCenter(options).dy, 1));
      expect(t.getRect(options).left, greaterThan(t.getRect(play).right));
      expect(t.getRect(options).right, lessThanOrEqualTo(320));
      expect(find.byType(GameArtwork), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );
  testWidgets(
    'gallery paging replaces previews and controller activation selects the newly focused page',
    (t) async {
      grid.paged = true;
      await open(t);
      await download(t);
      await driveArtwork(
        t,
        () => find
            .byKey(const ValueKey('artwork-icon-201'))
            .evaluate()
            .isNotEmpty,
      );
      await t.tap(find.text('Next page'));
      await driveArtwork(
        t,
        () => find
            .byKey(const ValueKey('artwork-icon-211'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byKey(const ValueKey('artwork-icon-201')), findsNothing);
      await t.tap(find.text('Previous page'));
      await driveArtwork(
        t,
        () => find
            .byKey(const ValueKey('artwork-icon-201'))
            .evaluate()
            .isNotEmpty,
      );
      await t.tap(find.text('Next page'));
      await driveArtwork(
        t,
        () => find
            .byKey(const ValueKey('artwork-icon-211'))
            .evaluate()
            .isNotEmpty,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await driveArtwork(
        t,
        () => find
            .byKey(const ValueKey('artwork-hero-202'))
            .evaluate()
            .isNotEmpty,
      );
      await t.tap(find.text('Keep current background'));
      await driveArtwork(
        t,
        () => find.text('Keep current logo').evaluate().isNotEmpty,
      );
      await t.tap(find.text('Keep current logo'));
      await driveArtwork(
        t,
        () =>
            model.installed.single.artwork?.iconCredit == 'Second page artist',
      );
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );
  testWidgets(
    'Select and pointer hover open title options; cancellation preserves files and confirmed deletion keeps progress with usable focus',
    (t) async {
      await t.runAsync(() => model.downloadGame(fixture()));
      model.artworkRequests.clear();
      final directory = model.installed.single.directory;
      final progress = File('${root.path}/profiles/keep.sav');
      await t.runAsync(() async {
        await progress.parent.create(recursive: true);
        await progress.writeAsString('save');
      });
      await open(t);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(
        t.getCenter(
          find.byWidgetPredicate(
            (w) => w is ConsoleButton && w.key == const ValueKey(1),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(model.homeIndex, 3);
      await t.binding.defaultBinaryMessenger.handlePlatformMessage(
        'app.broomm/prototype',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('controller', 'options'),
        ),
        (_) {},
      );
      await t.pumpAndSettle();
      expect(find.text('Select Artwork'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await t.pumpAndSettle();
      expect(find.text('Delete game'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await t.pumpAndSettle();
      expect(await t.runAsync(() => directory.exists()), true);
      expect(
        model.homeIndex,
        3,
        reason: 'Closing options must retain the hovered title',
      );
      await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete game'));
      await driveArtwork(t, () => model.installed.isEmpty && !model.busy);
      expect(await t.runAsync(() => directory.exists()), false);
      expect(await t.runAsync(() => progress.readAsString()), 'save');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<HomeScreen>(),
        isNotNull,
      );
      await mouse.removePointer();
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );
  testWidgets(
    'unavailable artwork can be skipped on a compact screen without blocking or removing the completed game',
    (t) async {
      grid.fail = true;
      await open(t, size: const Size(390, 844));
      await download(t);
      await driveArtwork(
        t,
        () => find.text('SteamGridDB is unavailable').evaluate().isNotEmpty,
      );
      await t.tap(find.text('Keep current icon'));
      await t.pump();
      await driveArtwork(t, () => grid.requests.length == 2);
      await t.tap(find.text('Keep current background'));
      await driveArtwork(t, () => grid.requests.length == 3);
      await t.tap(find.text('Keep current logo'));
      await t.pumpAndSettle();
      expect(model.installed.single.artwork, isNull);
      expect(model.downloadError, isNull);
      expect(
        await t.runAsync(() => model.installed.single.directory.exists()),
        true,
      );
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );
}
