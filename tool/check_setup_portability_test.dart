@TestOn('mac-os')
library;

import 'dart:convert';

import 'fixtures/configuration_cleanup.dart';

import 'dart:io';

import 'package:broomm/src/emulator_configuration.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/setup/archive.dart';
import 'package:broomm/src/setup/package.dart';
import 'package:flutter_test/flutter_test.dart';

class _AlternateSignatures extends SetupDownloads {
  _AlternateSignatures(super.data);
  @override
  Future<String> prepare(
    SetupPackage package,
    Directory working,
    DownloadCancellation cancellation,
    void Function(String, double?) progress, {
    Directory? localRoot,
  }) async {
    final path = await super.prepare(
      package,
      working,
      cancellation,
      progress,
      localRoot: localRoot,
    );
    if (package.prepare != 'none')
      await setupTool('/usr/bin/codesign', [
        '--force',
        '--deep',
        '--sign',
        '-',
        '--digest-algorithm=sha1,sha256',
        path,
      ], cancellation);
    return path;
  }
}

void main() {
  test('real PS2, PSP and Azahar bundles open independently with private storage and a Launch Services parent', () async {
    final parent = Directory('.tool-cache/research/setup-portability').absolute;
    final data = await parent.createTemp('verified installation ');
    final setup =
        jsonDecode(await File('assets/setup/setup.json').readAsString()) as Map;
    final entries = setup['launchers'] as Map;
    entries.removeWhere(
      (id, _) => !{'pcsx2', 'armsx2', 'ppsspp', 'azahar'}.contains(id),
    );
    for (final id in entries.keys) {
      final source = entries[id]['source'] as Map;
      source.remove('url');
      source['file'] =
          '$id.${{'ppsspp', 'azahar'}.contains(id) ? 'zip' : 'tar.xz'}';
    }
    final json = await File('${parent.path}/offline.json')
        .writeAsString(jsonEncode(setup));
    final log = SessionLog(
      '${data.path}/configuration.log',
      source: 'setup-portability-check',
    );
    final manager = ManagedEmulators(
      data,
      asset: (p) => File(p).readAsString(),
      log: log,
      downloads: _AlternateSignatures(data),
    );
    addTearDown(() async {
      manager.dispose();
      await log.close();
    });
    var last = '';
    manager.addListener(() {
      if (manager.phase.isNotEmpty && manager.phase != last) {
        last = manager.phase;
        stdout.writeln(last);
      }
    });
    final plan = await manager.readPlan(file: json.path);
    await manager.install(plan);
    expect(manager.error, isNull, reason: manager.error);
    final rows = <Map<String, Object?>>[];
    const profile = 'f323456789abcdef0123456789abcdef';
    for (final item in plan.items) {
      final build = item.build;
      final resolved = await manager.resolveConfiguration(build.name, profile);
      expect(
        resolved.executableHash,
        build.id == 'azahar' ? build.hash : isNot(build.hash),
      );
      expect(resolved.buildHash, build.hash);
      final configuration = EmulatorConfiguration(
        data,
        Directory.current.path,
        log: log,
      );
      final clock = Stopwatch()..start();
      await configuration.start(
        () => manager.resolveConfiguration(build.name, profile),
      );
      final pid = await configurationFixturePid(resolved.emulator.executable);
      try {
        await configurationFixtureReady(data, pid);
        await Future<void>.delayed(const Duration(seconds: 3));
        final parent = await Process.run('/bin/ps', [
          '-p',
          '$pid',
          '-o',
          'ppid=',
        ]);
        expect(parent.exitCode, 0);
        expect((parent.stdout as String).trim(), '1');
        await expectLater(SessionLease.acquire(data), throwsStateError);
        rows.add({
          'id': build.id,
          'build': build.hash,
          'localExecutable': resolved.executableHash,
          'archive': item.downloads[item.source]!.sha256,
          'privateConfigurationProcess': true,
          'competingWriterBlocked': true,
          'launchServicesParent': 1,
          if (build.id == 'azahar') 'terminalWarningPredicate': false,
          'elapsedMs': clock.elapsedMilliseconds,
        });
        stdout.writeln(
          '${build.name}: alternate signatures accepted; private configuration process alive',
        );
      } finally {
        await closeConfigurationFixture(pid, data);
      }
    }
    await File('${parent.path}/verified.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'data': data.path, 'results': rows, 'realGameplayTested': false, 'ownerDataWritten': false, 'cleanup': 'signals only to fixture-created no-game processes'})}\n',
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
