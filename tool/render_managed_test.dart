// Static review artifacts with explicit fixtures; no emulator launch or UI automation.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:broomm/src/app_model.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/shell/controls.dart';
import 'package:broomm/src/shell/emulator_settings_screen.dart';
import 'package:broomm/src/shell/game_session_screen.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/overlay_state_test.dart' show PausedSession, RecordingHost;

void main() {
  testWidgets('render managed setup and the console pairing route', (t) async {
    final output =
        Platform.environment['BROOMM_RENDER_ROOT'] ??
        '.tool-cache/research/managed-play/previews';
    late Directory data;
    late ShellModel shell;
    await t.runAsync(() async {
      data = await Directory.systemTemp.createTemp('broomm-ui-managed-');
      shell = ShellModel(ShellStorage(data), project: Directory.current.path);
      await shell.start();
      shell.platforms = [
        const RommPlatform(4, 'Nintendo GameCube', 'ngc', 40),
        const RommPlatform(7, 'Nintendo Wii', 'wii', 12),
        const RommPlatform(8, 'Mega Drive', 'genesis', 5),
      ];
      shell.platformsLoaded = true;
      await Directory(output).create(recursive: true);
      await (FontLoader('Helvetica Neue')..addFont(
            File('/System/Library/Fonts/HelveticaNeue.ttc')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
    });
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1180, 800);
    await t.binding.setSurfaceSize(const Size(1180, 800));
    final key = GlobalKey();
    Widget wrap(Widget child) => RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xff0b141f),
          textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: 'Helvetica Neue',
            bodyColor: ink,
            displayColor: ink,
          ),
        ),
        home: child,
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

    await t.pumpWidget(
      wrap(Scaffold(body: EmulatorSettingsScreen(model: shell))),
    );
    await save('emulators');
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('setup-4:dolphin')));
      for (var i = 0; i < 100 && shell.emulators.plan == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await t.pumpAndSettle();
    await Scrollable.ensureVisible(
      t.element(find.byKey(const ValueKey('confirm-4:dolphin'))),
    );
    await save('emulators-inline-review');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    final dolphin = shell.emulators.buildFor('Dolphin')!;
    shell.emulators.installed[dolphin.id] = dolphin.hash;
    await t.pumpWidget(
      wrap(Scaffold(body: EmulatorSettingsScreen(model: shell))),
    );
    await save('emulators-configured');
    await t.tap(find.byKey(const ValueKey('remove-4:dolphin')));
    await save('emulators-remove-confirmation');
    await t.tap(find.text('Cancel'));
    t.view.physicalSize = const Size(390, 844);
    await t.binding.setSurfaceSize(const Size(390, 844));
    await save('emulators-compact');
    t.view.physicalSize = const Size(1180, 800);
    await t.binding.setSurfaceSize(const Size(1180, 800));
    final session = PausedSession()..alive = false;
    final model = PrototypeModel(
      '/unused',
      host: RecordingHost(),
      gameSession: session,
    );
    await t.pumpWidget(
      wrap(GameSessionScreen(model: model, game: testGames[2])),
    );
    await t.pump();
    session.emit();
    await t.pumpAndSettle();
    model.join(10);
    await save('pairing-wii');
    t.view.physicalSize = const Size(390, 844);
    await t.binding.setSurfaceSize(const Size(390, 844));
    await save('pairing-compact');
    await t.pumpWidget(const SizedBox());
    model.dispose();
    shell.dispose();
    await t.runAsync(() => data.delete(recursive: true));
    await t.binding.setSurfaceSize(null);
    t.view.resetDevicePixelRatio();
    t.view.resetPhysicalSize();
  });
}
