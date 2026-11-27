import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:broomm/src/cemu_process.dart';
import 'package:broomm/src/cemu_session_control.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/remote/cemu_sources.dart';
import 'package:broomm/src/remote/protocol.dart';
import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

class NativeCemu implements CemuControlProcess {
  Completer<bool>? heldPause;
  final pauseEntered = Completer<void>();
  bool paused = false, freezeSample = false;
  int revision = 1;
  int sample = 0;
  final commands = <(bool, bool)>[];
  @override
  int get pid => 123;
  @override
  Map<String, Object> get target => {
    'pid': pid,
    'birth': '456',
    'name': 'Cemu',
  };
  @override
  Future<void> admit() async {}
  @override
  Future<Map<String, dynamic>?> receipt() async => {
    'pid': pid,
    'ack': revision,
    'title': '0005000010101000',
    'sample': freezeSample ? sample : ++sample,
  };
  @override
  Future<int> command({required bool active, bool quit = false}) async {
    commands.add((active, quit));
    return ++revision;
  }

  @override
  Future<bool> state({bool? paused}) async {
    if (paused == true && !pauseEntered.isCompleted) pauseEntered.complete();
    if (paused == true && heldPause != null) {
      this.paused = await heldPause!.future;
      heldPause = null;
    } else if (paused != null)
      this.paused = paused;
    return this.paused;
  }
}

Future<void> until(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(end))
      fail('Cemu control did not reach the expected observable state.');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CemuControllerSources sources;
  late CemuSessionControl control;
  late NativeCemu native;
  late RawDatagramSocket reader;
  var now = 0;
  final statuses = <BridgeStatus>[], problems = <String>[];
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CemuProcess.channel, (_) async => null);
    now = 0;
    statuses.clear();
    problems.clear();
    sources = CemuControllerSources(milliseconds: () => now);
    native = NativeCemu()..heldPause = Completer<bool>();
    control = CemuSessionControl(
      sources,
      '0005000010101000',
      changed: statuses.add,
      problem: problems.add,
    );
    await control.prepare();
    await control.attach(native);
    reader = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    // Independently generated native DSU subscribe request (CRC checked in the
    // wire tests). This establishes a real local reader before readiness.
    const packet = '44535543e9030c00d8c84d2204030201020010000100000000000000';
    reader.send(
      Uint8List.fromList([
        for (var i = 0; i < packet.length; i += 2)
          int.parse(packet.substring(i, i + 2), radix: 16),
      ]),
      InternetAddress.loopbackIPv4,
      control.input.port!,
    );
  });
  tearDown(() async {
    if (native.heldPause?.isCompleted == false)
      native.heldPause!.complete(true);
    await control.close();
    reader.close();
    await sources.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CemuProcess.channel, null);
  });
  test('pairing waits for actual kernel pause confirmation', () async {
    await native.pauseEntered.future;
    expect(statuses.any((s) => s.inputReady), isFalse);
    native.heldPause!.complete(true);
    await until(() => statuses.any((s) => s.inputReady));
    expect(statuses.last.paused, 1);
    expect(statuses.last.blocked, true);
    expect(problems, isEmpty);
  });
  test('replacing a source pauses its assignment and cannot silently reuse the old controller ID', () async {
    native.heldPause!.complete(true);
    sources.update(
      remote: false,
      device: 'first',
      pad: RemotePad.neutral,
      connected: true,
    );
    await until(() => statuses.any((s) => s.inputReady));
    final first = control.devices.single.id;
    await control.command([PlayerAssignment(first)], active: true);
    expect(statuses.last.blocked, false);
    sources.update(
      remote: false,
      device: 'second',
      pad: RemotePad.neutral,
      connected: true,
    );
    await until(() => statuses.any((s) => s.request == 'disconnect'));
    expect(native.paused, true);
    expect(control.devices.single.id, isNot(first));
    await expectLater(
      control.command([PlayerAssignment(first)], active: true),
      throwsStateError,
    );
    expect(native.commands.where((c) => c.$1), hasLength(1));
  });
  test('closing while Start is held cancels pending resume before it can activate gameplay', () async {
    native.heldPause!.complete(true);
    sources.update(
      remote: false,
      device: 'first',
      pad: const RemotePad(1 << 6, [0, 0, 0, 0, 0, 0]),
      connected: true,
    );
    await until(() => statuses.any((s) => s.inputReady));
    final resume = control.command([
      PlayerAssignment(control.devices.single.id),
    ], active: true);
    final rejected = expectLater(resume, throwsStateError);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await control.command([], active: false, quit: true);
    await rejected;
    expect(native.commands, [(false, true)]);
    expect(statuses.last.blocked, true);
  });
  test('resuming a long kernel pause tolerates the frozen native receipt until a fresh sample arrives', () async {
    native.heldPause!.complete(true);
    await until(() => statuses.any((s) => s.inputReady));
    native.freezeSample = true;
    now = 60000;
    final before = statuses.length;
    await until(() => statuses.length > before);
    expect(problems, isEmpty); // A paused native worker cannot publish.
    sources.update(
      remote: false,
      device: 'first',
      pad: RemotePad.neutral,
      connected: true,
    );
    await control.command([
      PlayerAssignment(control.devices.single.id),
    ], active: true);
    final resumed = statuses.length;
    await until(() => statuses.length > resumed);
    expect(native.paused, false);
    expect(statuses.last.blocked, false);
    expect(problems, isEmpty);
    native.freezeSample = false;
  });

  test('an unpaused native worker that stops advancing its heartbeat blocks input and reports once', () async {
    native.heldPause!.complete(true);
    sources.update(
      remote: false,
      device: 'first',
      pad: RemotePad.neutral,
      connected: true,
    );
    await until(() => statuses.any((s) => s.inputReady));
    await control.command([
      PlayerAssignment(control.devices.single.id),
    ], active: true);
    native.freezeSample = true;
    now = 1000;
    sources.update(
      remote: false,
      device: 'first',
      pad: RemotePad.neutral,
      connected: true,
    );
    await control.command([
      PlayerAssignment(control.devices.single.id),
    ], active: true);
    now = 2001;
    sources.update(
      remote: false,
      device: 'first',
      pad: RemotePad.neutral,
      connected: true,
    );
    await until(() => problems.isNotEmpty);
    expect(statuses.last.blocked, true);
    expect(problems.single, contains('stopped updating'));
    final failed = statuses.length;
    await until(() => statuses.length > failed);
    expect(problems, hasLength(1));
  });
}
