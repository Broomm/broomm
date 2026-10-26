// Offscreen widget artifacts for the owner's reported scrolling cases. This
// uses isolated catalogue/card fixtures, never a real account or emulator.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/emulator_settings_screen.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/navigation.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/navigation_test.dart' show buttonNode, labelled, native;
import '../test/shell_model_test.dart' show FixtureRomm, settleModel;

void main() {
  testWidgets('render focused Store edges and complete emulator cards', (
    t,
  ) async {
    final output =
        Platform.environment['BROOMM_RENDER_ROOT'] ??
        '.tool-cache/research/navigation-followup/previews';
    late Directory data;
    late ShellModel model;
    await t.runAsync(() async {
      data = await Directory.systemTemp.createTemp('broomm-focus-render-');
      model = ShellModel(
        ShellStorage(data),
        project: Directory.current.path,
        clientFactory: FixtureRomm.new,
      );
      await model.start();
      await model.addServer('https://fixture.example');
      await model.login('Player', 'fixture');
      await settleModel(model);
      model.credentialNotice = null;
      await Directory(output).create(recursive: true);
      for (final entry in {
        'Helvetica Neue': '/System/Library/Fonts/HelveticaNeue.ttc',
        'MaterialIcons':
            'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
      }.entries) {
        await (FontLoader(entry.key)..addFont(
              File(entry.value).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    });
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1180, 800);
    await t.binding.setSurfaceSize(const Size(1180, 800));
    final boundary = GlobalKey();
    model.navigate(ShellScreen.store);
    await t.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: BroommApp(model: model, project: Directory.current.path),
      ),
    );
    await t.pumpAndSettle();

    Future<void> save(String name) async {
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$output/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    requestConsoleFocus(buttonNode(t, labelled('Game 0, GameCube').first));
    await t.pumpAndSettle();
    final store = t
        .widget<CustomScrollView>(
          find.byKey(const PageStorageKey('store-scroll')),
        )
        .controller!;
    expect(store.offset, greaterThan(0));
    final search = find.byKey(const ValueKey('field-Search games'));
    final navigation = t
        .widgetList<Focus>(
          find.ancestor(of: search, matching: find.byType(Focus)),
        )
        .firstWhere(
          (w) =>
              w.focusNode != null &&
              w.focusNode!.canRequestFocus &&
              !w.focusNode!.skipTraversal,
        )
        .focusNode!;
    requestConsoleFocus(navigation);
    await t.pumpAndSettle();
    expect(store.offset, store.position.minScrollExtent);
    await save('store-search-top');

    model.platforms = [
      const RommPlatform(1, 'Arcade', 'arcade', 1),
      const RommPlatform(2, 'Game Boy', 'gb', 586),
      const RommPlatform(3, 'Game Boy Advance', 'gba', 1045),
      const RommPlatform(4, 'Game Boy Color', 'gbc', 558),
      const RommPlatform(5, 'Nintendo 3DS', '3ds', 515),
      const RommPlatform(6, 'Nintendo 64', 'n64', 8),
      const RommPlatform(7, 'Nintendo GameCube', 'ngc', 40),
      const RommPlatform(8, 'Nintendo Wii', 'wii', 12),
      const RommPlatform(9, 'PlayStation', 'ps', 248),
    ];
    for (final id in ['azahar', 'dolphin']) {
      final build = model.emulators.builds.firstWhere((b) => b.id == id);
      model.emulators.installed[id] = build.hash;
    }
    model.navigate(ShellScreen.emulators);
    await t.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byType(EmulatorSettingsScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    void checkCard(String key) {
      final card = find.byKey(ValueKey('emulator-card-$key'));
      expect(buttonNode(t, find.byKey(ValueKey('setup-$key'))).hasFocus, true);
      final view = t.getRect(scrollable), rect = t.getRect(card);
      expect(rect.top, greaterThanOrEqualTo(view.top));
      expect(rect.bottom, lessThanOrEqualTo(view.bottom));
    }

    await native(t, 'down');
    checkCard('5:azahar');
    await save('emulator-down-full-card');
    await native(t, 'down');
    checkCard('7:dolphin');
    await native(t, 'up');
    checkCard('5:azahar');
    await save('emulator-up-full-card');
    t.view.physicalSize = const Size(390, 844);
    await t.binding.setSurfaceSize(const Size(390, 844));
    await t.pumpAndSettle();
    requestConsoleFocus(
      buttonNode(t, find.byKey(const ValueKey('setup-5:azahar'))),
    );
    await t.pumpAndSettle();
    checkCard('5:azahar');
    await save('emulator-wrapped-full-card');

    await t.pumpWidget(const SizedBox());
    model.dispose();
    await t.runAsync(() => data.delete(recursive: true));
    await t.binding.setSurfaceSize(null);
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}
