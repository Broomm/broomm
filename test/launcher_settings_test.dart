import 'dart:async';
import 'dart:io';

import 'package:broomm/src/linux_launcher.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/shell/settings_screen.dart';
import 'package:broomm/src/shell/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class HeldLauncher extends LinuxLauncher {
  HeldLauncher(bool enabled) : super(enabled: enabled);
  int calls = 0;
  var result = Completer<LauncherInstallation>();
  @override
  Future<LauncherInstallation> install() {
    calls++;
    return result.future;
  }
}

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('broomm-launcher-ui-'),
  );
  tearDown(() => root.delete(recursive: true));
  test('installation failure is actionable and leaves the action available for retry', () async {
    final launcher = HeldLauncher(true);
    final model = ShellModel(ShellStorage(root), launcherInstaller: launcher);
    addTearDown(model.dispose);
    final failed = model.installLauncher();
    launcher.result.completeError(
      StateError('Launcher directory is read-only'),
    );
    await failed;
    expect(model.installingLauncher, isFalse);
    expect(model.notice!.problem, isTrue);
    expect(model.launcherStatus, contains('read-only'));
    launcher.result = Completer<LauncherInstallation>();
    final retry = model.installLauncher();
    launcher.result.complete(
      const LauncherInstallation('/fixture/launcher.desktop', true),
    );
    await retry;
    expect(launcher.calls, 2);
    expect(model.installingLauncher, isFalse);
    expect(model.notice!.problem, isFalse);
    expect(model.launcherStatus, contains('Close Broomm'));
  });
  testWidgets(
    'Application section exposes a keyboard/controller reachable Linux action and reports restart guidance',
    (t) async {
      final launcher = HeldLauncher(true);
      final model = ShellModel(ShellStorage(root), launcherInstaller: launcher);
      await t.runAsync(() => model.start());
      await t.pumpWidget(
        AnimatedBuilder(
          animation: model,
          builder: (_, __) => MaterialApp(
            home: Scaffold(
              body: Shortcuts(
                shortcuts: {
                  const SingleActivator(LogicalKeyboardKey.gameButtonA):
                      const ControllerActivateIntent(),
                },
                child: SettingsScreen(model: model, openLab: () {}),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final button = find.byKey(const ValueKey('install-to-launcher'));
      final focus = find.descendant(
        of: button,
        matching: find.byType(FocusableActionDetector),
      );
      for (
        var i = 0;
        i < 6 && !t.widget<FocusableActionDetector>(focus).focusNode!.hasFocus;
        i++
      ) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await t.pumpAndSettle();
      }
      expect(
        t.widget<FocusableActionDetector>(focus).focusNode!.hasFocus,
        isTrue,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await t.pumpAndSettle();
      expect(launcher.calls, 1);
      expect(find.text('Installing launcher…'), findsOneWidget);
      launcher.result.complete(
        const LauncherInstallation('/fixture/launcher.desktop', false),
      );
      await t.pumpAndSettle();
      expect(model.installingLauncher, isFalse);
      expect(
        find.textContaining('Close Broomm and open it again'),
        findsOneWidget,
      );
      expect(
        find.textContaining('did not accept a custom executable icon'),
        findsOneWidget,
      );
      expect(model.notice!.problem, isFalse);
      await t.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  testWidgets(
    'other hosts retain Application settings without the Linux-only button',
    (t) async {
      final launcher = HeldLauncher(false);
      final model = ShellModel(ShellStorage(root), launcherInstaller: launcher);
      await t.runAsync(() => model.start());
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(model: model, openLab: () {}),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('APPLICATION'), findsOneWidget);
      expect(find.byKey(const ValueKey('install-to-launcher')), findsNothing);
      expect(launcher.calls, 0);
      await t.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
}
