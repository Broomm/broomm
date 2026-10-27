import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/updates/controller.dart';
import 'package:broomm/src/updates/installation.dart';
import 'package:broomm/src/updates/releases.dart';

import 'application_updates_test.dart' show updateRelease;
import 'remembered_signin_test.dart' show MemoryCredentials;
import 'shell_model_test.dart' show FixtureRomm, settleModel;

class BlockingUpdateInstaller extends ApplicationInstaller {
  final started = Completer<void>();
  final cancelled = Completer<void>();
  @override
  void cancel() {
    super.cancel();
    if (!cancelled.isCompleted) cancelled.complete();
  }

  @override
  Future<PreparedAppUpdate> prepare(
    AppUpdate update,
    Directory data,
    void Function(String, double?) progress,
  ) async {
    progress('Downloading Broomm fixture…', .5);
    started.complete();
    await cancelled.future;
    throw const UpdateFailure('Update cancelled.');
  }
}

void main() {
  testWidgets(
    'automatic offer is first on Home, preserves selection, and opens a cancellable controller update flow',
    (t) async {
      late Directory root;
      late ShellModel model;
      final offer = Completer<AppUpdate?>();
      final began = Completer<BlockingUpdateInstaller>();
      late BlockingUpdateInstaller installer;
      final updates = ApplicationUpdates(
        current: '0.1.0',
        target: 'windows-x64',
        check: (_, _, _) => offer.future,
        installer: () {
          installer = BlockingUpdateInstaller();
          began.complete(installer);
          return installer;
        },
      );
      await t.runAsync(() async {
        root = await Directory.systemTemp.createTemp('broomm-update-ui-');
        model = ShellModel(
          ShellStorage(root),
          credentials: MemoryCredentials(),
          clientFactory: FixtureRomm.new,
          applicationUpdates: updates,
        );
        await model.start();
        await model.addServer('https://fixture.example');
        await model.login('Player', 'fixture');
        await settleModel(model);
      });
      await t.pumpWidget(BroommApp(model: model));
      printOnFailure('Updater UI: model ready');
      await t.pumpAndSettle();
      expect(model.homeApps, [0, 1, 2]);
      final selected = model.homeApps[model.homeIndex];
      offer.complete(
        selectUpdate([updateRelease('0.1.1')], '0.1.0', false, 'windows-x64'),
      );
      await t.pumpAndSettle();
      expect(model.homeApps, [4, 0, 1, 2]);
      expect(model.homeApps[model.homeIndex], selected);
      final update = find.byKey(const ValueKey('home-app-4'));
      expect(
        t.getTopLeft(update).dx,
        lessThan(t.getTopLeft(find.byKey(const ValueKey('home-app-0'))).dx),
      );
      Future<void> controller(String action) async {
        await t.binding.defaultBinaryMessenger.handlePlatformMessage(
          'app.broomm/prototype',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('controller', action),
          ),
          (_) {},
        );
        await t.pump();
      }

      await controller('left');
      printOnFailure('Updater UI: first left dispatched');
      await t.pumpAndSettle();
      await controller('left');
      printOnFailure('Updater UI: second left dispatched');
      await t.pumpAndSettle();
      expect(model.homeIndex, 0);
      await controller('accept');
      printOnFailure('Updater UI: activation dispatched');
      for (var i = 0; i < 30 && !began.isCompleted; i++) {
        await t.pump(const Duration(milliseconds: 20));
        await t.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(
        model.screen,
        ShellScreen.update,
        reason:
            'Controller activation at ${FocusManager.instance.primaryFocus?.debugLabel}',
      );
      expect(
        began.isCompleted,
        isTrue,
        reason: '${updates.status}; busy=${model.busy}',
      );
      expect(installer.started.isCompleted, isTrue);
      // The live-operation footer spinner intentionally never settles.
      await t.pump(const Duration(milliseconds: 300));
      expect(model.screen, ShellScreen.update);
      expect(model.applicationUpdating, isTrue);
      expect(find.text('Downloading Broomm fixture…'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      model.navigate(ShellScreen.store);
      expect(model.screen, ShellScreen.update);
      await controller('back');
      printOnFailure('Updater UI: cancellation dispatched');
      Future<void> drain(Future<void> work) async {
        var finished = false;
        Object? failure;
        unawaited(
          work.then(
            (_) {
              finished = true;
            },
            onError: (Object e) {
              failure = e;
              finished = true;
            },
          ),
        );
        for (var i = 0; i < 100 && !finished; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await t.pump(const Duration(milliseconds: 10));
        }
        expect(
          finished,
          isTrue,
          reason: 'Updater background work must drain before fixture removal',
        );
        if (failure != null) throw failure!;
      }

      await drain(updates.finish());
      await drain(model.finishDownloads());
      printOnFailure('Updater UI: background work drained');
      await t.pumpAndSettle();
      expect(installer.cancelled.isCompleted, isTrue);
      expect(model.applicationUpdating, isFalse);
      expect(find.textContaining('Update cancelled.'), findsOneWidget);
      await t.tap(find.text('Back to Home'));
      await t.pumpAndSettle();
      printOnFailure('Updater UI: returned Home');
      expect(model.screen, ShellScreen.home);
      await t.pumpWidget(const SizedBox.shrink());
      await t.runAsync(() async {
        await model.finishDownloads();
        await model.finishCloud();
        model.dispose();
        await root.delete(recursive: true);
      });
      printOnFailure('Updater UI: fixture removed');
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('automatic channel follows RC installs; stale check replies cannot overwrite a changed channel', () async {
    final first = Completer<AppUpdate?>(), second = Completer<AppUpdate?>();
    var calls = 0;
    final seen = <bool>[];
    final updates = ApplicationUpdates(
      current: '0.1.0-rc1',
      target: 'windows-x64',
      check: (_, candidates, _) {
        seen.add(candidates);
        return ++calls == 1 ? first.future : second.future;
      },
    );
    final old = updates.check();
    final changed = updates.setChannel('stable');
    second.complete(null);
    await changed;
    first.complete(
      selectUpdate(
        [updateRelease('0.1.0-rc2')],
        '0.1.0-rc1',
        true,
        'windows-x64',
      ),
    );
    await old;
    expect(seen, [true, false]);
    expect(updates.available, isNull);
    expect(updates.checkFailed, isFalse);
    updates.dispose();
    final preferences = ShellPreferences.fromJson({'pageSize': 24});
    expect(preferences.updateChannel, 'auto');
    expect(
      ShellPreferences.fromJson(preferences.copy(updateChannel: 'rc').toJson())
          .updateChannel,
      'rc',
    );
  });
}
