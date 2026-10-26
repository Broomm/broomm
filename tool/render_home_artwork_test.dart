// Offscreen application artifacts, with isolated generated PNGs and no account access.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/steamgrid.dart';
import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/artwork_picker.dart';
import 'package:broomm/src/shell/home_screen.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:broomm/src/progress/files.dart';

import '../test/home_artwork_widget_test.dart'
    show artworkFixture, FixtureSteamGrid, driveArtwork, decodeArtworkImages;
import '../test/library_download_test.dart' show fixture;

class Gallery extends FixtureSteamGrid {
  Gallery() : super('fixture');
  @override
  Future<Uint8List> image(
    Uri uri, {
    bool thumbnail = false,
    Object? owner,
  }) async {
    if (!uri.path.contains('logo'))
      return super.image(uri, thumbnail: thumbnail, owner: owner);
    final picture = ui.PictureRecorder();
    final canvas = Canvas(picture);
    final text = TextPainter(
      text: const TextSpan(
        text: 'ARTWORK\nADVENTURE',
        style: TextStyle(
          fontFamily: 'Helvetica Neue',
          fontSize: 68,
          fontWeight: FontWeight.w800,
          height: 1.05,
          color: Colors.white,
          shadows: [
            Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 3)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 620);
    text.paint(canvas, const Offset(10, 20));
    final rendered = picture.endRecording();
    final image = await rendered.toImage(640, 200);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
      rendered.dispose();
      text.dispose();
    }
  }

  @override
  Future<ArtworkPage> page(
    int gameId,
    ArtworkKind kind, {
    int page = 0,
    Object? owner,
  }) async {
    final base = art(kind);
    return ArtworkPage(
      List.generate(
        6,
        (i) => GridArtwork(
          id: base.id + i,
          kind: kind,
          url: Uri.parse('https://cdn2.steamgriddb.com/${kind.name}-$i.png'),
          thumb: Uri.parse(
            'https://cdn2.steamgriddb.com/${kind.name}-$i-thumb.png',
          ),
          width: base.width,
          height: base.height,
          mime: base.mime,
          author: 'Example artist ${i + 1}',
        ),
      ),
      false,
    );
  }
}

void main() {
  testWidgets(
    'render both artwork steps, layered Home and title options at desktop and compact sizes',
    (t) async {
      final output =
          Platform.environment['BROOMM_HOME_RENDER_ROOT'] ??
          '.tool-cache/research/home-refresh/previews';
      late Directory root;
      late ShellModel model;
      await t.runAsync(() async {
        root = await Directory.systemTemp.createTemp('broomm-artwork-render-');
        model = await artworkFixture(root, grid: Gallery());
        await Directory(output).create(recursive: true);
        for (final f in {
          'Helvetica Neue': '/System/Library/Fonts/HelveticaNeue.ttc',
          'MaterialIcons':
              'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
        }.entries) {
          await (FontLoader(f.key)..addFont(
                File(f.value).readAsBytes().then(ByteData.sublistView),
              ))
              .load();
        }
      });
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1180, 800);
      await t.binding.setSurfaceSize(const Size(1180, 800));
      final boundary = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: BroommApp(model: model),
        ),
      );
      await t.pumpAndSettle();
      Future<void> save(String name) async {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await t.pumpAndSettle();
        await decodeArtworkImages(t);
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await t.runAsync(() => model.downloadGame(fixture()));
      await t.pump();
      await driveArtwork(
        t,
        () => find
            .byKey(const ValueKey('artwork-icon-201'))
            .evaluate()
            .isNotEmpty,
      );
      await save('square-picker');
      await t.tap(find.byKey(const ValueKey('artwork-icon-201')));
      await driveArtwork(
        t,
        () => find
            .byKey(const ValueKey('artwork-hero-202'))
            .evaluate()
            .isNotEmpty,
      );
      await save('hero-picker');
      await t.tap(find.byKey(const ValueKey('artwork-hero-202')));
      await driveArtwork(
        t,
        () => find
            .byKey(const ValueKey('artwork-logo-203'))
            .evaluate()
            .isNotEmpty,
      );
      await save('logo-picker');
      await t.tap(find.byKey(const ValueKey('artwork-logo-203')));
      await driveArtwork(t, () => model.installed.single.artwork?.hero != null);
      model.homeSelection(3);
      t.state<HomeScreenState>(find.byType(HomeScreen)).focusSelection();
      await t.pump(const Duration(seconds: 8));
      await save('home-hero');
      final original = model.installed.single;
      model.installed = [
        original,
        for (final id in [2, 3])
          InstalledGame(
            fixture(id: id),
            original.directory,
            original.userId,
            artwork: original.artwork,
          ),
      ];
      await t.runAsync(() async {
        for (final id in [1, 2, 3]) {
          final file = await progressFile(
            root,
            'cloud-saves/${model.server!.id}/${model.profile!.id}/$id/state.json',
            createParents: true,
          );
          await progressWrite(file, {
            'pending': id != 1,
            'baseline': 'a' * 64,
            'synced': '2026-10-23T00:00:00Z',
            if (id == 3) 'conflict': {'reason': 'other device'},
          });
        }
        await model.refreshCloudStatus();
      });
      await t.pumpAndSettle();
      expect(find.byTooltip('Cloud saves synced'), findsOneWidget);
      expect(find.byTooltip('Cloud saves waiting to sync'), findsOneWidget);
      expect(find.byTooltip('Cloud saves need attention'), findsOneWidget);
      await save('home-cloud-status');
      model.installed = [original];
      await t.runAsync(model.refreshCloudStatus);
      await t.pumpAndSettle();
      model.showNotice('Artwork Adventure downloaded. Ready to play.');
      await save('notification-card');
      await t.pump(const Duration(seconds: 8));
      await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await save('title-options');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      unawaited(steamGridSettings(t.element(find.byType(HomeScreen)), model));
      await save('api-key-setting');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      t.view.physicalSize = const Size(390, 844);
      await t.binding.setSurfaceSize(const Size(390, 844));
      await t.pumpAndSettle();
      t.state<HomeScreenState>(find.byType(HomeScreen)).focusSelection();
      await save('home-compact');
      unawaited(
        selectGameArtwork(
          t.element(find.byType(HomeScreen)),
          model,
          model.installed.single.game,
        ),
      );
      await t.pump();
      await driveArtwork(
        t,
        () => find
            .byKey(const ValueKey('artwork-icon-201'))
            .evaluate()
            .isNotEmpty,
      );
      await save('square-picker-compact');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      model.dispose();
      await t.runAsync(() => root.delete(recursive: true));
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
}
