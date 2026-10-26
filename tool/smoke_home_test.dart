// Real Home -> owned download -> managed emulator; explicit fixture catalogue.
import 'dart:io';
import 'dart:async';

import 'package:broomm/src/app_model.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/controls.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/widgets/pairing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/shell_model_test.dart' show FixtureRomm, settleModel;

class HomeRomm extends FixtureRomm {
  HomeRomm(super.server);
  static final source = File('roms/${testGames.first.rom}');
  @override
  Future<List<RommPlatform>> platforms() async => [
    const RommPlatform(44, 'Super Nintendo', 'snes', 1),
  ];
  @override
  Future<RommGame> game(int id) async => RommGame(
    id: id,
    name: 'Home launch integration',
    platform: 'Super Nintendo',
    platformId: 44,
    platformSlug: 'snes',
    bytes: await source.length(),
    fsName: 'Home launch integration.sfc',
    fullPath: 'roms/Home launch integration.sfc',
    files: [
      RommFile(
        id: 8,
        romId: id,
        name: 'Home launch integration.sfc',
        fullPath: 'roms/Home launch integration.sfc',
        bytes: await source.length(),
      ),
    ],
  );
  @override
  Future<void> downloadFile(
    RommFile file,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    cancellation.check();
    await source.copy(destination.path);
    onProgress(await source.length());
  }
}

void main() {
  testWidgets(
    'Home plays a completed download through the managed pairing route',
    (t) async {
      late ShellModel shell;
      GameSession? session;
      final project = Directory.current.path;
      final data = Directory(
        '$project/.tool-cache/research/managed-play/home-data',
      );
      await t.binding.setSurfaceSize(const Size(1180, 800));
      await t.runAsync(() async {
        shell = ShellModel(
          ShellStorage(data),
          project: project,
          clientFactory: HomeRomm.new,
        );
        await shell.start();
        await shell.addServer('https://fixture.example');
        await shell.login('Home test', 'fixture');
        await settleModel(shell);
        final plan = await shell.emulators.readPlan(only: {'retroarch'});
        await shell.emulators.install(plan);
        expect(shell.emulators.error, isNull);
        if (shell.installation(9001) == null) {
          await shell.downloadGame(await shell.client!.game(9001));
        }
        expect(shell.installation(9001), isNotNull);
        shell.homeSelection(3);
      });
      await t.pumpWidget(
        BroommApp(
          model: shell,
          project: project,
          sessionFactory: (resolve) => session = GameSession(
            project,
            managedRoot: data.path,
            resolve: resolve,
            testInputs: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      final tile = find.byWidgetPredicate(
        (w) => w is ConsoleButton && w.label == 'Home launch integration',
      );
      await t.runAsync(() => t.tap(tile));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(shell.gameActive, true);
      // Widget time owns the post-frame launch and session polling timers.
      // Alternate actual I/O with frame pumps instead of waiting in runAsync.
      for (var i = 0; i < 500 && session?.status?.paused != 1; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await t.pump(const Duration(milliseconds: 40));
      }
      await t.runAsync(() async {
        expect(
          session?.status?.inputReady,
          true,
          reason: '${shell.error}; ${session?.emulator?.root}',
        );
        expect(session?.status?.paused, 1);
        await atomicText('${session!.emulator!.root}/test-input.txt', '0 0 3');
      });
      for (
        var i = 0;
        i < 100 && session!.status!.testSourceIds.length != 2;
        i++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await t.pump(const Duration(milliseconds: 40));
      }
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pumpAndSettle();
      expect(find.byType(PairingScreen), findsOneWidget);
      final model = t.widget<PairingScreen>(find.byType(PairingScreen)).model;
      final sourceId = session!.status!.testSourceIds.first;
      await t.tap(
        find.byWidgetPredicate(
          (w) =>
              w is ActionChip &&
              w.label is Text &&
              ((w.label as Text).data?.endsWith('#$sourceId') ?? false),
        ),
      );
      await t.pump();
      expect(model.pairing!.players.length, 1);
      final profile = shell.profile;
      shell.switchAccount();
      expect(shell.profile, same(profile));
      unawaited(model.play());
      for (var i = 0; i < 500 && model.busy; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await t.pump(const Duration(milliseconds: 40));
      }
      expect(model.screen, Screen.playing, reason: model.error);
      unawaited(model.stop());
      for (var i = 0; i < 500 && model.busy; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await t.pump(const Duration(milliseconds: 40));
      }
      await t.pumpAndSettle();
      expect(find.byType(PairingScreen), findsNothing);
      for (var i = 0; i < 100 && shell.gameActive; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await t.pump(const Duration(milliseconds: 40));
      }
      expect(shell.gameActive, false);
      expect(shell.error, isNull);
      expect(shell.installation(9001), isNotNull);
      expect(session!.running, false);
      await t.pumpWidget(const SizedBox());
      shell.dispose();
      await t.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
