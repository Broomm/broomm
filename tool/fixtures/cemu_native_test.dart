import 'dart:io';
import 'dart:convert';

import 'package:broomm/src/cemu_process.dart';
import 'package:broomm/src/cemu.dart';
import 'package:broomm/src/remote/cemu_input.dart';
import 'package:broomm/src/astris_process.dart';
import 'package:broomm/src/cemu_profile.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/progress/file_hash.dart';
import 'package:flutter_test/flutter_test.dart';

// Explicit developer integration check; never launch an emulator in ordinary
// unit tests. The source must be the reviewed, privately signed Cemu bundle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real Cemu admits a private writer and closes normally', () async {
    final source = Platform.environment['BROOMM_CEMU_NATIVE_SOURCE'];
    if (!Platform.isMacOS || source == null)
      throw StateError(
        'Set BROOMM_CEMU_NATIVE_SOURCE to the reviewed private Cemu.app on macOS.',
      );
    final project = Directory.current.path;
    final data = await Directory('$project/build').createTemp('cemu-native-');
    final lease = await SessionLease.acquire(data);
    CemuProcess? child;
    final input = CemuRemoteInput();
    await input.start();
    var exited = false;
    try {
      final exe = '$source/Contents/MacOS/Cemu';
      final hash = await gameFileHash(exe);
      final profile = Directory(
        '${data.path}/profiles/${'a' * 32}/emulators/cemu',
      )..createSync(recursive: true);
      final launcher = await prepareCemuLauncher(
        profile: profile,
        source: Directory(source),
        executable: 'Contents/MacOS/Cemu',
        executableHash: hash,
        inventory: jsonDecode(
          await File('$project/assets/setup/cemu.integrity.json')
              .readAsString(),
        ) as Map,
        host: 'macos-arm64',
      );
      final emulator = PreparedEmulator(
        'Cemu',
        profile.path,
        launcher.$1,
        0,
        null,
        null,
        userDirectory: launcher.$2,
      );
      final arguments = await const CemuAdapter().configurationArguments(
        emulator,
      );
      final controller = File(
        '${emulator.user}/controllerProfiles/controller0.xml',
      );
      await controller.parent.create(recursive: true);
      await controller.writeAsString(cemuControllerProfile(input.port!));
      child = await CemuProcess.start(
        resolved: ResolvedSession(emulator, '', hash, {}),
        dataRoot: data.path,
        project: project,
        arguments: arguments,
      );
      child.stdout.listen(stdout.add);
      child.stderr.listen(stderr.add);
      await child.admit();
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!input.hasReader && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(
        input.hasReader,
        isTrue,
        reason: 'Real Cemu must consume its private DSU controller profile.',
      );
      final receipt = await child.receipt();
      expect(receipt!['applicationReady'], true);
      expect(receipt['pid'], child.pid);
      final kernel = AstrisProcessIdentity(
        '$project/build/native/broomm-installer-guard.dylib',
        '${data.path}/writer.lock',
        emulator.executable,
      );
      expect(kernel.writer(), [
        child.pid,
        receipt['seconds'],
        receipt['microseconds'],
      ]);
      expect(receipt['title'], '0000000000000000');
      final target = File('${data.path}/pause-target.json');
      await target.writeAsString(jsonEncode(child.target));
      final paused = await Process.run(
        '$project/build/native/cemu-state-check',
        [target.path],
      );
      expect(paused.exitCode, 0, reason: '${paused.stdout}\n${paused.stderr}');
      // Simulate loss of the coordinator while the independently held native
      // writer survives. A restarted launcher must refuse a second session.
      await lease.release();
      await expectLater(SessionLease.acquire(data), throwsStateError);
      final recovery = await Process.run(
        '$project/build/native/cemu-state-check',
        [target.path, data.path],
      );
      expect(
        recovery.exitCode,
        0,
        reason: '${recovery.stdout}\n${recovery.stderr}',
      );
      expect(await child.exitCode.timeout(const Duration(seconds: 20)), 0);
      exited = true;
      expect(kernel.writer(), isNull);
    } finally {
      await input.close();
      if (child == null || exited) {
        await lease.release();
        await data.delete(recursive: true);
      } else {
        if (lease.active) lease.retainForUncertainWriter();
        stderr.writeln(
          'Cemu check retained its writer and staging: ${data.path}',
        );
      }
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
