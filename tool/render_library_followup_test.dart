// Offscreen widget rendering only: generated fixtures, no credentials or games.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/shell_model_test.dart' show FixtureRomm, settleModel;
import '../test/remembered_signin_test.dart' show MemoryCredentials;
import '../test/library_download_test.dart' show fixture;

void main() {
  testWidgets(
    'render the downloads hub and in-place keyboard at desktop and compact sizes',
    (t) async {
      final output =
          Platform.environment['BROOMM_LIBRARY_RENDER_ROOT'] ??
          '.tool-cache/research/library-followup/previews';
      late Directory data;
      late ShellModel model;
      await t.runAsync(() async {
        data = await Directory.systemTemp.createTemp('broomm-library-render-');
        model = ShellModel(
          ShellStorage(data),
          credentials: MemoryCredentials(),
          clientFactory: FixtureRomm.new,
        );
        await model.start();
        await model.addServer('https://fixture.example');
        await model.login('Player', 'fixture');
        await settleModel(model);
        await Directory(output).create(recursive: true);
        for (final font in {
          'Helvetica Neue': '/System/Library/Fonts/HelveticaNeue.ttc',
          'MaterialIcons':
              'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
        }.entries) {
          await (FontLoader(font.key)..addFont(
                File(font.value).readAsBytes().then(ByteData.sublistView),
              ))
              .load();
        }
      });
      model.downloads.addAll([
        DownloadJob(fixture(id: 1), state: DownloadState.active),
        DownloadJob(fixture(id: 2)),
        DownloadJob(
          fixture(id: 3),
          state: DownloadState.failed,
          problem: 'Connection lost. Retry or remove the downloaded data.',
        ),
      ]);
      model.download = DownloadProgress(
        fixture(id: 1),
        'Downloading game files',
        48 * 1024 * 1024,
        128 * 1024 * 1024,
      );
      final boundary = GlobalKey();
      t.view.devicePixelRatio = 1;
      Future<void> size(Size value) async {
        t.view.physicalSize = value;
        await t.binding.setSurfaceSize(value);
        await t.pumpAndSettle();
      }

      Future<void> save(String name) async {
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$output/$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      await size(const Size(1180, 800));
      await t.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: BroommApp(model: model),
        ),
      );
      await t.pumpAndSettle();
      await save('home-downloads');
      model.navigate(ShellScreen.downloads);
      await t.pumpAndSettle();
      await save('downloads');
      await size(const Size(390, 844));
      await save('downloads-compact');
      model.navigate(ShellScreen.store);
      await size(const Size(1180, 800));
      await save('store-buttons');
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonX);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('console-keyboard')), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      await save('keyboard-store');
      await size(const Size(800, 600));
      await save('keyboard-compact');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() async {
        await model.finishDownloads();
        model.dispose();
        await data.delete(recursive: true);
      });
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
}
