// Offscreen UI artifacts using an isolated catalogue; no owner account access.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/artwork.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';

import '../test/game_versions_test.dart' show VersionCatalogue;
import '../test/home_artwork_widget_test.dart' show driveArtwork;
import '../test/remembered_signin_test.dart' show MemoryCredentials;
import '../test/shell_model_test.dart' show settleModel;
import '../test/navigation_test.dart' show buttonNode;

void main() {
  testWidgets(
    'render a grouped Store and its desktop/compact version chooser',
    (t) async {
      const output = '.tool-cache/research/home-refresh/previews';
      late Directory root;
      late ShellModel model;
      await t.runAsync(() async {
        root = await Directory.systemTemp.createTemp('broomm-versions-render-');
        model = ShellModel(
          ShellStorage(root),
          credentials: MemoryCredentials(),
          clientFactory: VersionCatalogue.new,
        );
        await model.start();
        await model.addServer('https://versions.example');
        await model.login('Player', 'fixture');
        await settleModel(model);
        await model.browse(platform: 4);
        model.navigate(ShellScreen.store);
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
        await t.pumpAndSettle();
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

      expect(find.byType(GameCard), findsOneWidget);
      await save('grouped-store');
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
      await save('version-chooser');
      expect(
        buttonNode(
          t,
          find.byKey(const ValueKey('download-version-1')),
        ).hasFocus,
        true,
      );
      t.view.physicalSize = const Size(390, 844);
      await t.binding.setSurfaceSize(const Size(390, 844));
      await save('version-chooser-compact');
      expect(
        buttonNode(
          t,
          find.byKey(const ValueKey('download-version-1')),
        ).hasFocus,
        true,
      );
      await t.pumpWidget(const SizedBox());
      model.dispose();
      await t.runAsync(() => root.delete(recursive: true));
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
}
