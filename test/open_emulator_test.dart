import 'dart:async';
import 'dart:io';

import 'package:broomm/src/emulator_configuration.dart';
import 'package:broomm/src/host.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_model_test.dart' show FixtureRomm, settleModel;
import 'remembered_signin_test.dart' show MemoryCredentials;

class LaunchFixture extends EmulatorConfiguration {
  LaunchFixture(Directory data) : super(data, null);
  int calls = 0;
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<void> start(Future<ResolvedSession> Function() resolve) async {
    calls++;
    if (fail) throw StateError('The OS refused this launch.');
    await pending?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LaunchFixture launcher;
  late ShellModel model;
  final windowActions = <String>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-open-emulator-');
    launcher = LaunchFixture(root);
    model = ShellModel(
      ShellStorage(root),
      clientFactory: FixtureRomm.new,
      credentials: MemoryCredentials(),
      configurationLauncher: launcher,
    );
    await model.start();
    await model.addServer('https://server.example');
    await model.login('Player', 'fixture');
    await settleModel(model);
    model.navigate(ShellScreen.emulators);
    windowActions.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DesktopHost.channel, (call) async {
          windowActions.add(call.method);
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DesktopHost.channel, null);
    model.dispose();
    await root.delete(recursive: true);
  });
  test('opening returns without hiding Broomm, becoming a game session or blocking shutdown and navigation', () async {
    await model.openEmulator('Azahar');
    expect(launcher.calls, 1);
    expect(model.gameActive, false);
    expect(model.screen, ShellScreen.emulators);
    expect(windowActions, isEmpty);
    await model.finishConfiguration();
    model.navigate(ShellScreen.store);
    expect(model.screen, ShellScreen.store);
    expect(model.gameActive, false);
  });
  test('launch failure is visible and the next launch is allowed without restoring or hiding the window', () async {
    launcher.fail = true;
    await model.openEmulator('Azahar');
    expect(model.error, contains('OS refused'));
    expect(model.gameActive, false);
    launcher.fail = false;
    await model.openEmulator('Azahar');
    expect(launcher.calls, 2);
    await model.finishConfiguration();
    expect(windowActions, isEmpty);
  });
  test('repeated activation shares only the pending handoff and shutdown waits for that request rather than an emulator lifetime', () async {
    launcher.pending = Completer<void>();
    final opening = model.openEmulator('Azahar');
    await Future<void>.delayed(Duration.zero);
    expect(launcher.calls, 1);
    await model.openEmulator('Azahar');
    expect(launcher.calls, 1);
    expect(model.gameActive, false);
    var finished = false;
    final closing = model.finishConfiguration().then((_) => finished = true);
    expect(finished, false);
    launcher.pending!.complete();
    await opening;
    await closing;
    expect(finished, true);
    expect(windowActions, isEmpty);
  });
}
