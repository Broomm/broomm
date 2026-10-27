// Explicit live-provider check. Uses only isolated data and bundled recipes.
@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ryubing installs from the normal bundled recipe without a companion pack and reuses its verified binary', () async {
    final parent = Directory('.tool-cache/setup-ryubing-fix');
    await parent.create(recursive: true);
    final data = await parent.createTemp('native-');
    final manager = ManagedEmulators(
      data,
      asset: (p) => File(p).readAsString(),
    );
    addTearDown(manager.dispose);
    var phase = '';
    manager.addListener(() {
      if (manager.phase != phase) {
        phase = manager.phase;
        stdout.writeln(phase);
      }
    });
    final plan = await manager.readPlan(only: {'ryubing'});
    expect(manager.project, isNull);
    expect(plan.items.single.packageRoot, isNull);
    expect(plan.items.single.downloads.values.single.file, isNull);
    await manager.install(plan);
    expect(manager.error, isNull, reason: manager.error);
    expect(manager.ready('Ryubing'), true);
    final build = plan.items.single.build;
    final installed =
        '${manager.root.path}/ryubing/${build.hash}/${build.bundle}';
    expect(await File('$installed/Icon\r').exists(), false);
    await manager.verifyBundle(build, installed, DownloadCancellation());
    final second = ManagedEmulators(data, asset: manager.asset);
    addTearDown(second.dispose);
    await second.load();
    await second.install(await second.readPlan(only: {'ryubing'}));
    expect(second.error, isNull, reason: second.error);
    expect(second.ready('Ryubing'), true);
    await File('${parent.path}/native-result.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'data': data.absolute.path, 'host': Platform.operatingSystemVersion, 'source': plan.items.single.downloads.values.single.url.toString(), 'archive_sha256': plan.items.single.downloads.values.single.sha256, 'executable_sha256': build.hash, 'full_inventory_verified': true, 'no_project_root': true, 'no_companion_package': true, 'restart_reuse': 'passed'})}\n',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
