import 'dart:async';
import 'dart:io';

import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/shell/android_emulator_settings_screen.dart';
import 'package:broomm/src/shell/android_setup_dialog.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class InstallManager extends AndroidEmulators {
  InstallManager(super.data) : super(enabled: false);
  Completer<void>? pending;
  int attempts = 0;
  bool imported = false;
  @override
  Future<void> ensureSetupAllowed() async {}

  @override
  Future<void> install(AndroidEmulator emulator, {String? server}) async {
    attempts++;
    pending = Completer<void>();
    try {
      await pending!.future;
    } finally {
      requestingInstallPermission = false;
      installing = null;
      notifyListeners();
    }
  }

  @override
  Future<void> installApk(AndroidEmulator emulator, {String? server}) {
    imported = true;
    return install(emulator, server: server);
  }

  void permission() {
    requestingInstallPermission = true;
    notifyListeners();
  }

  void download() {
    requestingInstallPermission = false;
    installing = 'retroarch';
    downloadedBytes = 1024 * 1024;
    downloadBytes = 2 * 1024 * 1024;
    notifyListeners();
  }

  @override
  void cancelDownload() =>
      pending!.completeError(StateError('Download cancelled'));
}

void main() {
  late Directory root;
  late InstallManager manager;
  late ShellModel model;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-install-feedback-');
    manager = InstallManager(root);
    model = ShellModel(ShellStorage(root), androidManager: manager)
      ..server = SavedServer('a' * 32, 'https://example.invalid', '5.4.0')
      ..profile = SavedProfile('b' * 32, 'a' * 32, 3, 'Test')
      ..platforms = [
        for (var i = 0; i < 12; i++)
          RommPlatform(i, 'A filler $i', 'unknown', 0),
        const RommPlatform(10, 'Game Boy Advance', 'gba', 1),
      ];
  });
  tearDown(() async {
    model.dispose();
    await root.delete(recursive: true);
  });

  Finder inDialog(Finder target) =>
      find.descendant(of: find.byType(AndroidSetupDialog), matching: target);

  Future<void> open(WidgetTester t, {bool imported = false}) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AndroidEmulatorSettingsScreen(model: model)),
      ),
    );
    await t.pumpAndSettle();
    final button = find.text('Set up');
    await t.ensureVisible(button);
    await t.pumpAndSettle();
    expect(t.getRect(find.text('Emulator Settings')).bottom, lessThan(0));
    await t.tap(button);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(inDialog(find.text(imported ? 'Install APK…' : 'Install')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'root inspection is one page action and selects the installed app',
    (t) async {
      const retroarch = 'com.retroarch.aarch64', ppsspp = 'org.ppsspp.ppsspp';
      manager.installed[retroarch] = const AndroidApp(
        retroarch,
        '1.22.2',
        'retro',
      );
      manager.installed[ppsspp] = const AndroidApp(ppsspp, '1.19', 'psp');
      model.platforms = [
        const RommPlatform(10, 'Game Boy Advance', 'gba', 1),
        const RommPlatform(11, 'Super Nintendo', 'snes', 1),
      ];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AndroidEmulatorSettingsScreen(model: model)),
        ),
      );
      await t.pumpAndSettle();
      final inspect = find.text('Inspect root access');
      expect(inspect, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('android-emulator-10:retroarch')),
          matching: inspect,
        ),
        findsNothing,
      );
      expect(find.text('Root saves…'), findsNothing);
      expect(find.text('Save folder…'), findsNothing);
      expect(find.text('Open emulator'), findsNWidgets(2));
      await t.tap(inspect);
      // The page keeps animating its busy indicator while the dialog is open.
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Choose an emulator to inspect'), findsOneWidget);
      await t.tap(find.text('PPSSPP · $ppsspp'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Selected app: $ppsspp · 1.19'), findsOneWidget);
      expect(find.text('Request root inspection'), findsOneWidget);
      await t.tap(find.text('Close'));
      await t.pumpAndSettle();
      await t.tap(inspect);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Choose an emulator to inspect'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('Choose an emulator to inspect'), findsNothing);
    },
  );

  testWidgets(
    'scrolled card keeps permission and download progress visible until OS handoff',
    (t) async {
      await open(t);
      expect(inDialog(find.text('Preparing RetroArch…')), findsOneWidget);
      manager.permission();
      await t.pump();
      expect(
        inDialog(find.textContaining('Allow from this source')),
        findsOneWidget,
      );
      manager.download();
      await t.pump();
      expect(
        inDialog(find.textContaining('1.0 MB')).hitTestable(),
        findsOneWidget,
      );
      expect(
        t
            .widget<LinearProgressIndicator>(
              inDialog(find.byType(LinearProgressIndicator)),
            )
            .value,
        .5,
      );
      manager.pending!.complete();
      await t.pumpAndSettle();
      expect(
        inDialog(find.textContaining('Finish installing')),
        findsOneWidget,
      );
      expect(manager.installed, isEmpty);
      await t.tap(inDialog(find.text('Cancel')));
      await t.pumpAndSettle();
      expect(find.byType(AndroidSetupDialog), findsNothing);
    },
  );

  testWidgets(
    'native handoff failure remains visible and permits retry from the same card',
    (t) async {
      await open(t);
      manager.pending!.completeError(
        PlatformException(
          code: 'android-install',
          message: 'Invalid downloaded APK',
        ),
      );
      // The settings page stays busy behind the modal until it closes.
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(
        inDialog(find.textContaining('Invalid downloaded APK')).hitTestable(),
        findsOneWidget,
      );
      await t.tap(inDialog(find.text('Install')));
      await t.pump();
      expect(manager.attempts, 2);
      expect(find.textContaining('Invalid downloaded APK'), findsNothing);
      manager.pending!.complete();
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'APK import failures and download cancellation remain actionable',
    (t) async {
      await open(t, imported: true);
      expect(manager.imported, isTrue);
      manager.pending!.completeError(
        StateError('Installation permission was not granted'),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(
        inDialog(find.textContaining('permission was not granted'))
            .hitTestable(),
        findsOneWidget,
      );
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      await t.tap(find.text('Set up'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(inDialog(find.text('Install')));
      await t.pump();
      manager.download();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(inDialog(find.text('Cancel download')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(
        inDialog(find.textContaining('Download cancelled')).hitTestable(),
        findsOneWidget,
      );
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.byType(AndroidSetupDialog), findsNothing);
    },
  );
}
