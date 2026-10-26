@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_model_test.dart' show FixtureRomm, settleModel;

void main() {
  testWidgets(
    'inline card setup and confirmed removal perform real owned file operations while keeping progress',
    (t) async {
      late Directory root, source;
      late ShellModel model;
      late ManagedEmulators manager;
      await t.runAsync(() async {
        root = await Directory.systemTemp.createTemp('broomm-inline-setup-');
        source = Directory('${root.path}/source/Fake.app');
        await source.create(recursive: true);
        await File('${source.path}/app').writeAsString('fixture executable');
        final hash = await sha256File('${source.path}/app');
        final assets = {
          'assets/setup/tested-builds.json': jsonEncode({
            'builds': [
              {
                'id': 'dolphin',
                'name': 'Dolphin',
                'version': 'fixture',
                'host': 'macos-arm64',
                'bundle': 'Fake.app',
                'executable': 'app',
                'sha256': hash,
                'sdl': 3,
                'native': {},
              },
            ],
          }),
          'assets/setup/dolphin.integrity.json': jsonEncode({
            'files': {'app': hash},
            'links': {},
          }),
          'assets/setup/dolphin.symbols': 'fixture symbols',
          'assets/setup/setup.json': jsonEncode({
            'schema_version': 1,
            'host': 'macos-arm64',
            'launchers': {
              'dolphin': {'source': source.path},
            },
          }),
        };
        manager = ManagedEmulators(
          Directory('${root.path}/data'),
          asset: (p) async => assets[p]!,
        );
        model = ShellModel(
          ShellStorage(manager.data),
          emulatorManager: manager,
          clientFactory: FixtureRomm.new,
        );
        await model.start();
        await model.addServer('https://server.example');
        await model.login('Player', 'fixture');
        await settleModel(model);
        model.navigate(ShellScreen.emulators);
        final save = File('${manager.data.path}/profiles/keep.sav');
        await save.parent.create(recursive: true);
        await save.writeAsString('progress');
      });
      await t.binding.setSurfaceSize(const Size(1180, 800));
      await t.pumpWidget(BroommApp(model: model));
      await t.pumpAndSettle();
      Future<void> drive(bool Function() finished) async {
        for (var i = 0; i < 500 && !finished(); i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await t.pump(const Duration(milliseconds: 20));
        }
        expect(finished(), true, reason: manager.error);
        await t.pumpAndSettle();
      }

      await t.tap(find.byKey(const ValueKey('setup-4:dolphin')));
      await drive(() => manager.plan != null);
      final card = find.byKey(const ValueKey('emulator-card-4:dolphin'));
      expect(
        find.descendant(of: card, matching: find.text('Start setup')),
        findsOneWidget,
      );
      final confirm = find.byKey(const ValueKey('confirm-4:dolphin'));
      await Scrollable.ensureVisible(t.element(confirm));
      await t.pumpAndSettle();
      await t.tap(confirm);
      await t.pump();
      await drive(() => manager.ready('Dolphin') && !manager.busy);
      expect(manager.error, isNull);
      final remove = find.byKey(const ValueKey('remove-4:dolphin'));
      await Scrollable.ensureVisible(t.element(remove));
      await t.pumpAndSettle();
      await t.tap(remove);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('confirm-remove-dolphin')));
      await t.pump();
      await drive(() => !manager.ready('Dolphin') && !manager.busy);
      expect(manager.error, isNull);
      await t.runAsync(() async {
        expect(
          await File('${manager.data.path}/profiles/keep.sav').readAsString(),
          'progress',
        );
        expect(
          await File('${source.path}/app').readAsString(),
          'fixture executable',
        );
      });
      expect(find.byKey(const ValueKey('remove-4:dolphin')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      model.dispose();
      await t.binding.setSurfaceSize(null);
      await t.runAsync(() => root.delete(recursive: true));
    },
  );
}
