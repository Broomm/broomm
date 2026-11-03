import 'dart:async';
import 'dart:io';

import 'package:broomm/src/steam/installer.dart';
import 'package:broomm/src/linux_launcher.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/shell/settings_screen.dart';
import 'package:broomm/src/shell/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class HeldSteam extends SteamInstaller {
  HeldSteam({bool enabled = true})
    : super(enabled: enabled, loadAsset: (_) async => []);
  int calls = 0;
  Completer<SteamInstallation> result = Completer();
  @override
  Future<SteamInstallation> install(
    Directory storage, {
    void Function(String)? phase,
  }) {
    calls++;
    phase?.call('Connecting to Steam…');
    return result.future;
  }
}

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('broomm-steam-ui-'),
  );
  tearDown(() => root.delete(recursive: true));
  test('quit drain waits for the active action; failure permits retry and update/close block new effects', () async {
    final steam = HeldSteam();
    final m = ShellModel(ShellStorage(root), steamInstaller: steam);
    addTearDown(m.dispose);
    final work = m.addToSteam();
    await m.addToSteam();
    expect(steam.calls, 1);
    var drained = false;
    final finish = m.finishSteam().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    steam.result.completeError(
      StateError('Enable Steam CEF debugging and retry'),
    );
    await work;
    await finish;
    expect(m.addingToSteam, isFalse);
    expect(m.steamStatus, contains('CEF debugging'));
    expect(m.notice!.problem, isTrue);
    m.applicationUpdating = true;
    await m.addToSteam();
    m.applicationUpdating = false;
    m.closing = true;
    await m.addToSteam();
    expect(steam.calls, 1);
    m.closing = false;
    steam.result = Completer();
    final retry = m.addToSteam();
    steam.result.complete(const SteamInstallation(123));
    await retry;
    expect(steam.calls, 2);
    expect(m.notice!.problem, isFalse);
  });
  testWidgets(
    'desktop action supports controller focus, busy feedback and confirmed success',
    (t) async {
      final steam = HeldSteam();
      final m = ShellModel(
        ShellStorage(root),
        steamInstaller: steam,
        launcherInstaller: LinuxLauncher(enabled: false),
      );
      await t.runAsync(() => m.start());
      await t.pumpWidget(
        AnimatedBuilder(
          animation: m,
          builder: (_, __) => MaterialApp(
            home: Scaffold(
              body: Shortcuts(
                shortcuts: {
                  const SingleActivator(LogicalKeyboardKey.gameButtonA):
                      const ControllerActivateIntent(),
                },
                child: SettingsScreen(model: m, openLab: () {}),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final action = find.byKey(const ValueKey('add-to-steam'));
      await t.ensureVisible(action);
      final detector = find.descendant(
        of: action,
        matching: find.byType(FocusableActionDetector),
      );
      final focus = t.widget<FocusableActionDetector>(detector).focusNode!;
      focus.requestFocus();
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await t.pumpAndSettle();
      expect(steam.calls, 1);
      expect(find.text('Adding to Steam…'), findsOneWidget);
      expect(find.text('Connecting to Steam…'), findsOneWidget);
      steam.result.complete(const SteamInstallation(123));
      await t.pumpAndSettle();
      expect(find.text('Add to Steam'), findsOneWidget);
      expect(
        find.textContaining('Broomm and its artwork are in your Steam library'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      m.dispose();
    },
  );
  testWidgets(
    'Android keeps Application section without unsupported Steam action',
    (t) async {
      final steam = HeldSteam(enabled: false);
      final m = ShellModel(
        ShellStorage(root),
        steamInstaller: steam,
        launcherInstaller: LinuxLauncher(enabled: false),
      );
      await t.runAsync(() => m.start());
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(model: m, openLab: () {}),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('APPLICATION'), findsOneWidget);
      expect(find.byKey(const ValueKey('add-to-steam')), findsNothing);
      await m.addToSteam();
      expect(steam.calls, 0);
      await t.pumpWidget(const SizedBox());
      m.dispose();
    },
  );
}
