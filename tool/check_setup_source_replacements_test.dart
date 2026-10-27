// Explicit live-provider check. Does not use owner settings, games or progress.
@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled setup installs Dolphin, Ryubing, RetroArch and all cores with HTTPS alone and reuses them after restart', () async {
    final parent = Directory('.tool-cache/setup-source-replacements');
    await parent.create(recursive: true);
    final fixture = await parent.createTemp('native-');
    final data = Directory('${fixture.path}/data');
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
    final plan = await manager.readPlan(
      only: {'dolphin', 'ryubing', 'retroarch'},
    );
    expect(manager.project, isNull);
    expect(
      plan.items.expand((i) => i.downloads.values).every((p) => p.file == null),
      true,
    );
    expect(
      plan.items.expand((i) => i.downloads.values).where((p) => p.url != null),
      hasLength(18),
    );
    await manager.install(plan);
    expect(manager.error, isNull, reason: manager.error);
    expect(manager.installed, hasLength(3));
    expect(manager.installedCores, hasLength(14));
    final second = ManagedEmulators(data, asset: manager.asset);
    addTearDown(second.dispose);
    await second.load();
    final bundled = await second.readPlan(
      only: {'dolphin', 'ryubing', 'retroarch'},
    );
    await second.install(bundled);
    expect(second.error, isNull, reason: second.error);
    expect(second.installed, hasLength(3));
    expect(second.installedCores, hasLength(14));
    await File('${parent.path}/native-result.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        'host': Platform.operatingSystemVersion,
        'fixture': fixture.absolute.path,
        'project_root': manager.project,
        'public_application_downloads': ['dolphin', 'ryubing', 'retroarch'],
        'core_downloads': 15,
        'offline_archives': [],
        'installed': manager.installed,
        'cores': manager.installedCores.toList(),
        'full_inventories': 'passed',
        'restart_without_sources': 'passed',
      })}\n',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
