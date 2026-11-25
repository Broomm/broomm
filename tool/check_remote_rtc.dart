// Native Flutter entry point, never the application entry point. Run with
// --target tool/check_remote_rtc.dart and an existing private melonDS fixture.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/progress/files.dart';
import 'package:broomm/src/remote/rtc_video.dart';
import 'package:broomm/src/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const requestedProject = String.fromEnvironment('BROOMM_RTC_PROJECT');
  const requestedRoot = String.fromEnvironment('BROOMM_RTC_FIXTURE_ROOT');
  if (requestedProject.isEmpty || requestedRoot.isEmpty) {
    throw StateError('Select an existing private macOS fixture.');
  }
  final project = Directory(requestedProject).resolveSymbolicLinksSync();
  final root = Directory(requestedRoot).resolveSymbolicLinksSync();
  if (!Platform.isMacOS ||
      project.isEmpty ||
      !root.startsWith(
        '$project/.tool-cache/research/remote-followup/native-',
      )) {
    throw StateError('Requires an explicitly selected private macOS fixture.');
  }
  final evidence = Directory('$project/.tool-cache/research/remote-webrtc');
  await evidence.create(recursive: true);
  final events = <String>[], problems = <String>[];
  final changed = ValueNotifier<int>(0);
  final first = Completer<void>();
  late RemoteRtcVideo sender, receiver;
  receiver = RemoteRtcVideo(
    id: 1,
    sender: false,
    send: (s) => sender.signal(readVideoSignal(s)),
    changed: () {
      changed.value++;
      if (receiver.firstFrame && !first.isCompleted) first.complete();
    },
    problem: problems.add,
    event: events.add,
  );
  sender = RemoteRtcVideo(
    id: 1,
    sender: true,
    send: (s) => receiver.signal(readVideoSignal(s)),
    changed: () {},
    problem: problems.add,
    event: events.add,
  );
  runApp(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: changed,
          builder: (_, _, _) => receiver.renderer == null
              ? const SizedBox()
              : RTCVideoView(receiver.renderer!),
        ),
      ),
    ),
  );
  final manager = ManagedEmulators(
    Directory(root),
    project: project,
    asset: (path) => File('$project/$path').readAsString(),
  );
  final ipc = await Directory.systemTemp.createTemp('brm-rtc-fixture-');
  final profile = progressNonce();
  final session = GameSession(
    project,
    managedRoot: root,
    testInputs: true,
    remoteSocket: '${ipc.path}/input',
    remoteScreen: true,
    resolve: (game) => manager.resolve(game, profile),
  );
  session.onProblem = problems.add;
  const channel = MethodChannel('app.broomm/remote');
  var success = false;
  try {
    await manager.load();
    await session.launch(
      LaunchGame(
        'ds',
        'Private RTC fixture',
        'Nintendo DS',
        'melonDS',
        '$root/game.nds',
        1,
        0xff539388,
        target: ControllerTarget.nds,
      ),
    );
    await session.waitFor(
      (s) => s.inputReady && s.paused == 1,
      timeout: const Duration(seconds: 40),
    );
    final pairing = Pairing(1, target: ControllerTarget.nds)
      ..join(session.status!.testSourceIds.first);
    await session.command(pairing.players, active: true);
    await session.waitFor(
      (s) => s.paused == 0 && s.remoteCapture.first > 0,
      timeout: const Duration(seconds: 10),
    );
    await sender.startSender(
      (stream) => channel.invokeMethod<void>('capture', {
        ...session.macWindowTarget!,
        'remoteCapture': session.status!.remoteCapture,
        'id': 1,
        'name': 'melonDS',
        'streamId': stream.id,
      }),
    );
    await first.future.timeout(const Duration(seconds: 20));
    await Future<void>.delayed(const Duration(seconds: 16));
    if (receiver.renderer!.videoWidth < 1280 ||
        receiver.renderer!.videoHeight < 960) {
      throw StateError('Video negotiated below the high-resolution target.');
    }
    if (problems.isNotEmpty)
      throw StateError('Video fixture reported problems.');
    success = true;
  } catch (e, stack) {
    problems.add('$e\n$stack');
  } finally {
    await channel.invokeMethod<void>('capture');
    await sender.close();
    await receiver.close();
    if (session.running) await session.stop();
    await ipc.delete(recursive: true);
    manager.dispose();
    await File('${evidence.path}/native-loopback.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'success': success,
        'privateFixture': root,
        'events': events,
        'problems': problems,
      }),
    );
    exit(success ? 0 : 1);
  }
}
