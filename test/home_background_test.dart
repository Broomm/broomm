import 'dart:io';

import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/shell/artwork.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/steamgrid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'focus_outline_test.dart' show capture, pixel;
import 'support/artwork_fixtures.dart';

Finder get hero => find.byKey(const ValueKey('home-hero-image'));
Alignment alignment(WidgetTester t) =>
    t.widget<Image>(hero).alignment.resolve(TextDirection.ltr);
Future<void> decode(WidgetTester t) async {
  final image = t.widget<Image>(hero);
  await t.runAsync(() async {
    var complete = false;
    final work = precacheImage(
      image.image,
      t.element(hero),
      onError: (_, _) {},
    ).whenComplete(() => complete = true);
    // Image streams publish decoded frames through the scheduler. Drive it
    // alongside real file I/O, as in the existing artwork fixture checks.
    for (var i = 0; i < 100 && !complete; i++) {
      await t.pump(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(complete, true);
    await work;
  });
  await t.pumpAndSettle();
}

void main() {
  late Directory root;
  late ShellModel model;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-background-');
    final wide = await File('${root.path}/wide.png')
        .writeAsBytes(artworkPng(1200, 300));
    final copy = await wide.copy('${root.path}/other.png');
    final tall = await File('${root.path}/tall.png')
        .writeAsBytes(artworkPng(200, 400));
    final broken = await File('${root.path}/broken.png')
        .writeAsString('not an image');
    model = ShellModel(ShellStorage(root));
    model.screen = ShellScreen.home;
    model.homeIndex = 1;
    model.installed = [
      for (final (i, file) in [wide, copy, tall, broken].indexed)
        InstalledGame(
          RommGame(
            id: i + 1,
            name: 'Game $i',
            platformId: 4,
            platform: 'GameCube',
          ),
          root,
          7,
          artwork: HomeArtwork(hero: file.path),
        ),
    ];
  });
  tearDown(() async {
    model.dispose();
    await model.finishDownloads();
    await model.finishCloud();
    await root.delete(recursive: true);
  });
  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    t.binding.imageCache.clear();
    t.binding.imageCache.clearLiveImages();
    await t.pump();
    await t.binding.setSurfaceSize(null);
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  }

  Future<void> size(WidgetTester t, [Size value = const Size(400, 400)]) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = value;
    await t.binding.setSurfaceSize(value);
  }

  testWidgets(
    'wide cover art starts left, pans right, pauses and returns left without rebuilding the page',
    (t) async {
      await size(t);
      final boundary = GlobalKey();
      var builds = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                builds++;
                return RepaintBoundary(
                  key: boundary,
                  child: HomeBackground(model: model),
                );
              },
            ),
          ),
        ),
      );
      await decode(t);
      expect(alignment(t), Alignment.topLeft);
      final initialBuilds = builds;
      final left = await capture(t, boundary, settle: false);
      await t.pump(const Duration(seconds: 2));
      expect(alignment(t), Alignment.topLeft);
      await t.pump(const Duration(seconds: 11));
      expect(alignment(t).x, closeTo(0, .05));
      await t.pump(const Duration(seconds: 11));
      expect(alignment(t), Alignment.topRight);
      final right = await capture(t, boundary, settle: false);
      expect(
        pixel(right, const Offset(20, 30)).r,
        greaterThan(pixel(left, const Offset(20, 30)).r + .25),
      );
      await t.pump(const Duration(seconds: 1));
      expect(alignment(t), Alignment.topRight);
      await t.pump(const Duration(seconds: 11));
      expect(alignment(t).x, closeTo(0, .05));
      await t.pump(const Duration(seconds: 11));
      expect(alignment(t), Alignment.topLeft);
      expect(builds, initialBuilds);
      expect(t.getSize(find.byType(HomeBackground)).height, 300);
      await close(t);
    },
  );

  testWidgets(
    'hidden and muted artwork pauses; reduced motion and a new selection restart left',
    (t) async {
      await size(t);
      late StateSetter update;
      var reduced = false, ticking = true;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: reduced),
                  child: TickerMode(
                    enabled: ticking,
                    child: HomeBackground(model: model),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await decode(t);
      await t.pump(const Duration(seconds: 13));
      final before = alignment(t);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await t.pump(const Duration(seconds: 10));
      expect(alignment(t), before);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      expect(alignment(t).x, greaterThan(before.x));
      update(() => ticking = false);
      await t.pump();
      final muted = alignment(t);
      await t.pump(const Duration(seconds: 8));
      expect(alignment(t), muted);
      update(() => ticking = true);
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      expect(alignment(t).x, greaterThan(muted.x));
      update(() => reduced = true);
      await t.pump();
      expect(alignment(t), Alignment.topLeft);
      await t.pump(const Duration(seconds: 30));
      expect(alignment(t), Alignment.topLeft);
      update(() => reduced = false);
      await t.pump();
      await t.pump(const Duration(seconds: 13));
      expect(alignment(t).x, closeTo(0, .05));
      update(() => model.homeIndex = 2);
      await t.pumpAndSettle();
      await decode(t);
      expect(alignment(t), Alignment.topLeft);
      update(() => model.screen = ShellScreen.store);
      await t.pumpAndSettle();
      expect(hero, findsNothing);
      expect(t.takeException(), isNull);
      await close(t);
    },
  );

  testWidgets(
    'fitting or failed art stays still and resize only pans when horizontal overflow appears',
    (t) async {
      await size(t);
      model.homeIndex = 3;
      late StateSetter update;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return HomeBackground(model: model);
              },
            ),
          ),
        ),
      );
      await decode(t);
      await t.pump(const Duration(seconds: 30));
      expect(alignment(t), Alignment.topLeft);
      await size(t, const Size(100, 400));
      await t.pump();
      await decode(t);
      await t.pump(const Duration(seconds: 13));
      expect(alignment(t).x, closeTo(0, .05));
      await size(t);
      await t.pump();
      await decode(t);
      expect(alignment(t), Alignment.topLeft);
      update(() => model.homeIndex = 4);
      await t.pumpAndSettle();
      await decode(t);
      await t.pump(const Duration(seconds: 30));
      expect(alignment(t), Alignment.topLeft);
      expect(t.takeException(), isNull);
      await close(t);
    },
  );
}
