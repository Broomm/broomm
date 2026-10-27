// Explicit native distribution check. No owner settings, ROMs or progress are
// used. The local snapshot pack must first exist under build/setup-packages.
@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('installed-app setup validates every pinned bundle and core, then reuses installations without source archives', () async {
    final parent = Directory('.tool-cache/setup-downloads');
    await parent.create(recursive: true);
    final reuse = Platform.environment['BROOMM_SETUP_REUSE_FIXTURE'];
    final Directory data;
    if (reuse == null) {
      data = await parent.createTemp('native-install-');
    } else {
      data = Directory(reuse);
      final path = await data.resolveSymbolicLinks();
      final base = await parent.resolveSymbolicLinks();
      if (!path.startsWith('$base/native-install-') ||
          path.substring(base.length + 1).contains('/'))
        throw StateError(
          'Only this check’s retained private fixture can be resumed.',
        );
    }
    final manager = ManagedEmulators(
      data,
      asset: (path) => File(path).readAsString(),
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
      file: 'build/setup-packages/macos-arm64/setup.json',
    );
    expect(manager.project, isNull);
    expect(plan.items, hasLength(12));
    await manager.install(plan);
    expect(manager.error, isNull, reason: manager.error);
    expect(manager.installed, hasLength(12));
    expect(manager.installedCores, hasLength(14));
    // This is the unmodified bundled manifest, with no checkout-bound sources.
    // Re-verification must not require any external archive or network request.
    final bundled = await manager.readPlan();
    await manager.install(bundled);
    expect(manager.error, isNull, reason: manager.error);
    final result = {
      'host': Platform.operatingSystemVersion,
      'data': data.absolute.path,
      'project_root': manager.project,
      'resumed_fixture': reuse != null,
      'installed': manager.installed,
      'cores': manager.installedCores.toList(),
      'default_reverification': 'passed',
    };
    await File(
      '${parent.path}/native-install.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(result)}\n');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
