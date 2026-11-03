@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:flutter_test/flutter_test.dart';

// Opt-in: downloads the actual official frontend and all current Linux cores.
// Never uses the owner's accounts, games or emulator profiles.
void main() {
  test('fresh official RetroArch setup accepts current cores and every core loads its native ABI', () async {
    final parent = Directory('.tool-cache/research/linux-setup-fix');
    await parent.create(recursive: true);
    final data = await parent.createTemp('retroarch-');
    final manager = ManagedEmulators(
      data,
      asset: (p) => File(p).readAsString(),
    );
    addTearDown(manager.dispose);
    String previous = '';
    manager.addListener(() {
      if (previous != manager.phase) {
        previous = manager.phase;
        // ignore: avoid_print
        print(manager.phase);
      }
    });
    await manager.install(await manager.readPlan(only: {'retroarch'}));
    expect(manager.error, isNull, reason: manager.error);
    expect(manager.installedCores, hasLength(15));
    final compiler =
        Platform.environment['BROOMM_LINUX_CC'] ?? '/usr/bin/clang-18';
    final probe = '${data.path}/core-inspect';
    final compile = await Process.run(compiler, [
      'tool/fixtures/core_inspect.c',
      '-ldl',
      '-o',
      probe,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stderr}');
    final build = manager.buildFor('RetroArch')!;
    final observations = <Map>[];
    for (final entry in manager.installedCoreBuilds.entries) {
      final hash = entry.value['sha256'] as String;
      final file =
          '${manager.root.path}/retroarch/${build.hash}/cores/${entry.key}-$hash/core.so';
      final loaded = await Process.run(probe, [file]);
      expect(loaded.exitCode, 0, reason: '${entry.key}: ${loaded.stderr}');
      observations.add({
        'id': entry.key,
        'sha256': hash,
        'native': jsonDecode(loaded.stdout as String),
      });
    }
    await File('${data.path}/native-cores.json')
        .writeAsString(jsonEncode(observations));
    // Reset only these disposable installations; preserve a native save and an
    // outstanding cloud checkpoint to verify the owner's requested boundary.
    final runtime = await manager.resolveConfiguration('RetroArch', 'e' * 32);
    final save = File('${runtime.emulator.root}/saves/retained.srm');
    await save.writeAsString('disposable progress');
    final pending = File('${data.path}/cloud-saves/pending/state.json');
    await pending.parent.create(recursive: true);
    await pending.writeAsString('keep');
    await manager.resetAll();
    expect(manager.error, isNull, reason: manager.error);
    expect(await save.readAsString(), 'disposable progress');
    expect(await pending.readAsString(), 'keep');
    expect(await manager.root.exists(), isFalse);
    await File('${parent.path}/retroarch-result.json').writeAsString(
      jsonEncode({
        'data': data.path,
        'cores': observations,
        'reset_preserved_progress': true,
      }),
    );
  }, timeout: const Timeout(Duration(minutes: 15)));
}
