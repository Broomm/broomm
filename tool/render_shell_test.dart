// Deterministic UI artifacts using explicit test fixtures, never an app demo mode.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/shell/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/shell_model_test.dart' show FixtureRomm, settleModel;

void main() {
  testWidgets('render the console shell with isolated fixture data', (t) async {
    final output =
        Platform.environment['BROOMM_RENDER_ROOT'] ??
        '.tool-cache/research/romm-shell/previews';
    late Directory directory;
    late ShellModel model;
    await t.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('broomm-render-');
      model = ShellModel(
        ShellStorage(directory),
        clientFactory: FixtureRomm.new,
      );
      await model.start();
      final font = FontLoader('Helvetica Neue')
        ..addFont(
          File('/System/Library/Fonts/HelveticaNeue.ttc')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      await font.load();
      await icons.load();
      await Directory(output).create(recursive: true);
    });
    t.view.physicalSize = const Size(1180, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.binding.setSurfaceSize(const Size(1180, 800));
    final key = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: BroommApp(model: model),
      ),
    );
    Future<void> save(String name) async {
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$output/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await save('server');
    await t.runAsync(() async {
      await model.addServer('https://romm.example.com');
    });
    await save('profiles');
    await t.runAsync(() async {
      await model.login('Player one', 'fixture-only');
      await settleModel(model);
    });
    await save('home');
    const previewGame = RommGame(
      id: 99,
      name: 'A new adventure',
      platformId: 4,
      platform: 'Nintendo GameCube',
      summary: 'Downloaded game fixture for visual inspection.',
    );
    model.installed = [InstalledGame(previewGame, directory, 7)];
    model.homeSelection(3);
    await t.pumpAndSettle();
    final tile = find.byWidgetPredicate(
      (w) => w is ConsoleButton && w.label == previewGame.name,
    );
    t
        .widget<FocusableActionDetector>(
          find.descendant(
            of: tile,
            matching: find.byType(FocusableActionDetector),
          ),
        )
        .focusNode!
        .requestFocus();
    await save('downloaded-home');
    model.download = const DownloadProgress(
      const RommGame(
        id: 100,
        name: 'Another adventure',
        platformId: 4,
        platform: 'Nintendo GameCube',
      ),
      'Downloading file 1 of 2',
      524288000,
      1073741824,
    );
    model.homeSelection(2);
    model.homeSelection(3);
    await save('download-progress');
    model.download = null;
    model.homeSelection(1);
    for (final screen in [
      ShellScreen.store,
      ShellScreen.settings,
      ShellScreen.emulators,
    ]) {
      model.navigate(screen);
      await save(screen.name);
    }
    model.navigate(ShellScreen.home);
    t.view.physicalSize = const Size(390, 844);
    await t.binding.setSurfaceSize(const Size(390, 844));
    await save('home-phone');
    await t.pumpWidget(const SizedBox());
    model.dispose();
    await t.runAsync(() async {
      await directory.delete(recursive: true);
    });
  });
}
