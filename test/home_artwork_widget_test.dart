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
import 'package:broomm/src/shell/library.dart';
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
  bool hasPlatformIcon = false;
  final platformIconRequests = <String>[];

  @override
  Future<Uint8List?> platformIcon(String slug) async {
    platformIconRequests.add(slug);
    return hasPlatformIcon && slug == 'ngc'
        ? artworkIco(artworkPng(64, 64))
        : null;
  }

  @override
  Future<RommGame> game(int id) async {
    final g = fixture(id: id);
    return RommGame(
      id: g.id,
      name: 'Artwork Adventure',
      platformId: g.platformId,
      platform: g.platform,
      platformSlug: 'ngc',
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
    if (!model.disposed) model.dispose();
    await model.finishDownloads();
    await model.finishCloud();
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
    await decodeArtworkImages(t);
    await t.pumpWidget(const SizedBox());
    var finished = false;
    final drained = () async {
      await model.finishDownloads();
      await model.finishCloud();
    }().whenComplete(() => finished = true);
    // Drive real I/O and the widget clock until the native queue handle closes.
    // ChangeNotifier.dispose starts cleanup but cannot await that file close.
    await driveArtwork(t, () => finished);
    await drained;
    // FileImage may retain its native encoded buffer through the image cache.
    // Cache handles are disposed in post-frame callbacks, so unmounting alone
    // does not release Windows file mappings before fixture deletion.
    t.binding.imageCache.clear();
    t.binding.imageCache.clearLiveImages();
    await t.pump();
    await t.binding.setSurfaceSize(null);
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  }

  Future<void> download(WidgetTester t) async {
    await t.runAsync(() => model.downloadGame(fixture()));
    await t.pump();
  }

  for (final disposed in [false, true]) {
    testWidgets(
      'artwork fixture shutdown releases the ${disposed ? "disposing" : "live"} download queue before storage cleanup',
      (t) async {
        await download(t);
        final queue = DownloadQueueStore(
          root,
          model.server!.id,
          model.profile!.id,
        );
        await t.runAsync(() async {
          await expectLater(queue.open(), throwsA(isA<DownloadQueueInUse>()));
        });
        if (disposed) model.dispose();
        await finish(t);
        // A second owner must acquire the actual production lock immediately after
        // shutdown, with no deletion retries or dependency on filesystem timing.
        await t.runAsync(() async {
          await queue.open();
          await queue.close();
        });
      },
    );
  }

  for (final removed in [false, true]) {
    testWidgets(
      'artwork cleanup releases ${removed ? 'cache-only' : 'visible'} file image variants before deletion',
      (t) async {
        final file = File('${root.path}/cleanup.png');
        await t.runAsync(() => file.writeAsBytes(artworkPng(64, 64)));
        await t.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                Image.file(file, cacheWidth: 32),
                Image.file(file, cacheWidth: 64),
              ],
            ),
          ),
        );
        await decodeArtworkImages(t);
        expect(t.binding.imageCache.currentSize, greaterThanOrEqualTo(2));
        if (removed) await t.pumpWidget(const SizedBox());
        await finish(t);
        expect(t.binding.imageCache.pendingImageCount, 0);
        expect(t.binding.imageCache.currentSize, 0);
        expect(t.binding.imageCache.liveImageCount, 0);
        await t.runAsync(() => file.delete());
        expect(await t.runAsync(() => file.exists()), false);
      },
    );
  }

  void addRailGames(List<String> names) {
    model.installed = [
      for (final (index, name) in names.indexed)
        InstalledGame(
          RommGame(
            id: index + 1,
            name: name,
            platformId: 4,
            platform: 'PlayStation 2',
          ),
          root,
          7,
        ),
    ];
  }

  testWidgets(
    'first and last tiles settle at the same left-side anchor with complete captions',
    (t) async {
      const names = [
        'First game',
        'Second game',
        'Third game',
        'Super Smash Bros. Ultimate',
        'Shadow of the Colossus Special Edition',
      ];
      addRailGames(names);
      await open(t, size: const Size(960, 600));
      final store = find.byKey(const ValueKey('home-app-1'));
      void expectStoreDetailsAligned() {
        final storeLeft = t.getRect(store).left;
        expect(t.getRect(find.text('Game Store')).left, closeTo(storeLeft, 1));
        expect(
          t.getRect(find.widgetWithText(ConsoleButton, 'Open')).left,
          closeTo(storeLeft, 1),
        );
      }

      expectStoreDetailsAligned();
      expect(t.getRect(store).left, closeTo(100, 1));
      final anchor = t.getCenter(store).dx;
      final caption = find.byKey(const ValueKey('home-selected-caption'));
      final title = find.byKey(const ValueKey('home-game-title'));
      for (final (i, name) in names.indexed) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pumpAndSettle();
        final tile = find.byKey(ValueKey(i + 1));
        expect(model.selectedHomeGame?.game.name, name);
        expect(t.getCenter(tile).dx, closeTo(anchor, 1));
        expect(
          find.descendant(of: caption, matching: find.text('PS2')),
          findsOneWidget,
        );
        expect(t.getRect(caption).right, lessThanOrEqualTo(960));
        expect(t.renderObject<RenderParagraph>(title).didExceedMaxLines, false);
      }
      // The last title can wrap below the tile on a narrow display.
      t.view.physicalSize = const Size(320, 600);
      await t.binding.setSurfaceSize(const Size(320, 600));
      await t.pumpAndSettle();
      final paragraph = t.renderObject<RenderParagraph>(title);
      final lastGlyph = paragraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: names.last.length - 1,
              extentOffset: names.last.length,
            ),
          )
          .single
          .toRect();
      expect(t.getRect(title).left + lastGlyph.right, lessThan(320));
      expect(lastGlyph.bottom, lessThanOrEqualTo(paragraph.size.height));
      expect(
        t.getRect(caption).top,
        greaterThan(t.getRect(find.byKey(const ValueKey(5))).bottom),
      );
      for (final _ in names) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await t.pumpAndSettle();
      }
      expectStoreDetailsAligned();
      await finish(t);
    },
  );

  testWidgets(
    'tile growth is gradual, can reverse, and honors reduced motion',
    (t) async {
      addRailGames(['First game', 'Second game']);
      await open(t);
      final store = find.byKey(const ValueKey('home-app-1'));
      final first = find.byKey(const ValueKey(1));
      final base = t.getRect(first).width;
      final enlarged = t.getRect(store).width;
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      await t.pump(const Duration(milliseconds: 160));
      final growing = t.getRect(first).width;
      expect(growing, greaterThan(base));
      expect(growing, lessThan(enlarged));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(t.getRect(first).width, closeTo(growing, 1));
      await t.pumpAndSettle();
      expect(t.getRect(first).width, closeTo(base, 1));

      await t.runAsync(
        () => model.savePreferences(model.preferences.copy(reduceMotion: true)),
      );
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(t.getRect(first).width, closeTo(enlarged, 1));
      await t.pumpAndSettle();
      await finish(t);
    },
  );

  testWidgets(
    'a horizontal drag snaps the closest game to the selection anchor',
    (t) async {
      addRailGames(['First game', 'Second game', 'Third game']);
      await open(t);
      final anchor = t.getCenter(find.byKey(const ValueKey('home-app-1')));
      await t.dragFrom(anchor, const Offset(-180, 0));
      await t.pumpAndSettle();
      expect(model.selectedHomeGame?.game.name, 'First game');
      expect(
        t.getCenter(find.byKey(const ValueKey(1))).dx,
        closeTo(anchor.dx, 1),
      );
      await finish(t);
    },
  );

  testWidgets(
    'a mapped download opens square then hero pickers and persists a top-aligned, fading Home image with cropped-poster fallback',
    (t) async {
      final client = model.client! as ArtworkCatalogue;
      client.hasPlatformIcon = true;
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
      final cached = File(
        '${root.path}/platform-icons/${model.server!.id}/icon-ngc.png',
      );
      await driveArtwork(t, cached.existsSync);
      model.homeSelection(1);
      await t.pumpAndSettle();
      final platformIcon = find.byKey(const ValueKey('home-platform-icon'));
      await driveArtwork(t, () => platformIcon.evaluate().isNotEmpty);
      await decodeArtworkImages(t);
      expect(client.platformIconRequests, ['ngc']);
      expect(model.installed.single.artwork!.logo, endsWith('/logo.png'));
      expect(find.byKey(const ValueKey('home-game-logo')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-game-title')), findsOneWidget);
      final play = find.byWidgetPredicate(
        (w) =>
            w is ConsoleButton &&
            w.focusNode?.debugLabel == 'Home primary action',
      );
      final playText = find.descendant(of: play, matching: find.text('Play'));
      expect(find.descendant(of: play, matching: platformIcon), findsOneWidget);
      final options = find.widgetWithText(ConsoleButton, 'Options');
      final store = find.byKey(const ValueKey('home-app-1'));
      final gameTile = find.byKey(const ValueKey(1));
      final caption = find.byKey(const ValueKey('home-selected-caption'));
      expect(t.getRect(gameTile).width, greaterThan(t.getRect(store).width));
      expect(t.getRect(caption).left, greaterThan(t.getRect(gameTile).right));
      expect(t.getRect(caption).bottom, closeTo(t.getRect(gameTile).bottom, 4));
      expect(
        find.descendant(of: caption, matching: find.text('GC')),
        findsOneWidget,
      );
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
      final logo = find.byKey(const ValueKey('home-game-logo'));
      void expectDetailsAligned() {
        final tile = t.getRect(gameTile);
        final artwork = t.getRect(logo);
        expect(
          t.getRect(find.byKey(const ValueKey('system-app-0'))).left,
          closeTo(tile.left, 1),
        );
        expect(artwork.left, closeTo(tile.left, 1));
        expect(
          t.getRect(platformIcon).right,
          lessThan(t.getRect(playText).left),
        );
        expect(
          t.getCenter(platformIcon).dy,
          closeTo(t.getCenter(playText).dy, 1),
        );
        expect(artwork.top - tile.bottom, greaterThanOrEqualTo(71));
        expect(t.getRect(play).left, closeTo(tile.left, 1));
        expect(t.getCenter(play).dy, closeTo(t.getCenter(options).dy, 1));
      }

      expectDetailsAligned();
      t.view.physicalSize = const Size(1900, 900);
      await t.binding.setSurfaceSize(const Size(1900, 900));
      await t.pumpAndSettle();
      final logoAtDefaultScale = t.getRect(logo).height;
      expect(logoAtDefaultScale, closeTo(192, 1));
      expect(
        t.getRect(logo).width / logoAtDefaultScale,
        closeTo(640 / 200, .01),
      );
      expectDetailsAligned();
      await t.runAsync(
        () => model.savePreferences(model.preferences.copy(uiScale: 150)),
      );
      await t.pumpAndSettle();
      expect(t.getRect(logo).height, closeTo(logoAtDefaultScale * 1.5, 1));
      expectDetailsAligned();
      await t.runAsync(
        () => model.savePreferences(model.preferences.copy(uiScale: 75)),
      );
      await t.pumpAndSettle();
      expect(t.getRect(logo).height, closeTo(logoAtDefaultScale * .75, 1));
      await t.runAsync(
        () => model.savePreferences(model.preferences.copy(uiScale: 125)),
      );
      await t.pumpAndSettle();
      final playHeight = t.getRect(play).height;
      await t.runAsync(
        () => model.savePreferences(model.preferences.copy(logoScale: 150)),
      );
      await t.pumpAndSettle();
      expect(
        t.getRect(logo).height,
        closeTo(logoAtDefaultScale * 1.25 * 1.5, 1),
      );
      expect(t.getRect(play).height, closeTo(playHeight, 1));
      expectDetailsAligned();
      await t.runAsync(
        () => model.savePreferences(model.preferences.copy(uiScale: 100)),
      );
      t.view.physicalSize = const Size(320, 600);
      await t.binding.setSurfaceSize(const Size(320, 600));
      await t.pumpAndSettle();
      expectDetailsAligned();
      final narrowLogo = t.getRect(logo);
      expect(narrowLogo.right, lessThanOrEqualTo(320));
      expect(narrowLogo.height, lessThan(logoAtDefaultScale));
      expect(narrowLogo.width / narrowLogo.height, closeTo(640 / 200, .01));
      t.state<HomeScreenState>(find.byType(HomeScreen)).focusSelection();
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(t.widget<ConsoleButton>(play).focusNode!.hasPrimaryFocus, true);
      expect(t.getRect(play).bottom, lessThan(600));
      await t.runAsync(
        () => model.savePreferences(model.preferences.copy(showArtwork: false)),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-hero-image')), findsNothing);
      expect(find.byKey(const ValueKey('home-game-logo')), findsNothing);
      expect(platformIcon, findsNothing);
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
    'Play shows the platform icon for a game without a logo at compact UI scale',
    (t) async {
      final client = model.client! as ArtworkCatalogue;
      client
        ..mapped = false
        ..hasPlatformIcon = true;
      await t.runAsync(
        () => model.savePreferences(model.preferences.copy(uiScale: 150)),
      );
      await open(t, size: const Size(320, 600));
      await download(t);
      await driveArtwork(t, () => model.installed.isNotEmpty);
      model.homeSelection(1);
      final icon = find.byKey(const ValueKey('home-platform-icon'));
      await driveArtwork(t, () => icon.evaluate().isNotEmpty);
      await t.pumpAndSettle();
      final play = find.widgetWithText(ConsoleButton, 'Play');
      expect(find.byKey(const ValueKey('home-game-logo')), findsNothing);
      expect(find.descendant(of: play, matching: icon), findsOneWidget);
      expect(t.getRect(icon).left, greaterThan(t.getRect(play).left));
      expect(
        t.getRect(icon).right,
        lessThan(t.getRect(find.text('Play')).left),
      );
      expect(
        t.getRect(find.text('Play')).right,
        lessThan(t.getRect(play).right),
      );
      model.homeSelection(0);
      await t.pumpAndSettle();
      expect(find.widgetWithText(ConsoleButton, 'Open'), findsOneWidget);
      expect(icon, findsNothing);
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
      expect(model.homeIndex, 1);
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
        1,
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
