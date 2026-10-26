import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';

import 'shell_model_test.dart' show FixtureRomm, settleModel;
import 'remembered_signin_test.dart' show MemoryCredentials;
import 'library_download_test.dart' show fixture;

void main() {
  late Directory root;
  late ShellModel model;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-notices-');
    model = ShellModel(
      ShellStorage(root),
      credentials: MemoryCredentials(),
      clientFactory: FixtureRomm.new,
    );
    await model.start();
    await model.addServer('https://notifications.example');
    await model.login('Player', 'fixture');
    await settleModel(model);
  });
  tearDown(() async {
    model.dispose();
    await root.delete(recursive: true);
  });
  Future<void> open(WidgetTester t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1180, 800);
    await t.binding.setSurfaceSize(const Size(1180, 800));
    await t.pumpWidget(BroommApp(model: model));
    await t.pumpAndSettle();
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.binding.setSurfaceSize(null);
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  }

  testWidgets(
    'top-left cards expire without moving Home or taking focus; a new event gets its full lifetime',
    (t) async {
      await open(t);
      final tile = find.byKey(const ValueKey('home-app-1'));
      final before = t.getRect(tile),
          focus = FocusManager.instance.primaryFocus;
      model.showNotice('Download complete');
      await t.pumpAndSettle();
      expect(t.getRect(tile), before);
      expect(FocusManager.instance.primaryFocus, same(focus));
      final card = find.byKey(const ValueKey('shell-notification'));
      expect(t.getRect(card).left, lessThan(40));
      expect(t.getRect(card).top, lessThan(40));
      await t.pump(const Duration(seconds: 6));
      expect(find.text('Download complete'), findsOneWidget);
      model.showNotice('Artwork saved');
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 6));
      expect(find.text('Artwork saved'), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(card, findsNothing);
      expect(FocusManager.instance.primaryFocus, same(focus));
      final profile = t.getRect(find.byKey(const ValueKey('shell-profile')));
      expect(profile.top, greaterThan(700));
      expect(profile.right, greaterThan(1100));
      expect(find.text('broomm'), findsNothing);
      await finish(t);
    },
  );
  testWidgets(
    'progress remains available until completion, problems retain their source state and switching profile removes old feedback',
    (t) async {
      await open(t);
      model.download = DownloadProgress(fixture(), 'Downloading', 1, 10);
      model.showNotice('Starting download');
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 20));
      await t.pumpAndSettle();
      expect(find.text('Cancel download'), findsNothing);
      expect(find.byKey(const ValueKey('shell-notification')), findsNothing);
      model.download = null;
      model.reportProblem('Storage needs attention');
      await t.pumpAndSettle();
      expect(find.text('Storage needs attention'), findsOneWidget);
      await t.pump(const Duration(seconds: 13));
      await t.pumpAndSettle();
      expect(find.text('Storage needs attention'), findsNothing);
      expect(model.error, 'Storage needs attention');
      model.gameActive = true;
      model.reportProblem('The game has stopped');
      await t.pumpAndSettle();
      expect(find.text('The game has stopped'), findsNothing);
      model.gameActive = false;
      await t.pumpAndSettle();
      expect(find.text('The game has stopped'), findsOneWidget);
      model.showNotice('Account feedback');
      await t.pumpAndSettle();
      model.switchAccount();
      await t.pumpAndSettle();
      expect(find.text('Account feedback'), findsNothing);
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );
}
