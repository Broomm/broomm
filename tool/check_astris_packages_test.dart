@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/addons/astris.dart';
import 'package:broomm/src/addons/files.dart';
import 'package:broomm/src/addons/package_profile.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';

void main() {
  test('Astris native update/DLC inspection, publication and removal preserve progress', () async {
    final fixture = Platform.environment['BROOMM_ASTRIS_FIXTURE']!;
    final data = Directory('$fixture/data');
    final manager = ManagedEmulators(
      data,
      project: Directory.current.path,
      asset: (p) => File(p).readAsString(),
    );
    await manager.load();
    final profileId = Platform.environment['BROOMM_ASTRIS_PROFILE']!;
    final cancellation = DownloadCancellation();
    final lease = await SessionLease.acquire(data);
    try {
      final (executable, profile) = await manager.preparePackages(
        'switch',
        profileId,
        cancellation,
        emulator: 'Astris',
      );
      final stage = await data.createTemp('astris-package-check-');
      final packages = await Directory('${stage.path}/packages').create();
      for (final kind in ['DLC', 'UPDATE']) {
        final copied = await Process.run('/bin/cp', [
          '-c',
          Platform.environment['BROOMM_ASTRIS_$kind']!,
          '${packages.path}/${kind.toLowerCase()}.nsp',
        ]);
        expect(copied.exitCode, 0, reason: '${copied.stderr}');
      }
      final native = await Directory('${stage.path}/native').create();
      final found = await inspectAstrisPackages(
        executable,
        Platform.environment['BROOMM_ASTRIS_ROM']!,
        packages,
        native,
        profile,
        data,
        cancellation,
      );
      expect(found.updates, isNotNull);
      expect(found.dlc, isNotEmpty);
      final payload = await Directory('${stage.path}/payload').create();
      final units = <String, dynamic>{};
      final original = <String, String?>{};
      for (final e in {'updates': found.updates!, 'dlc': found.dlc!}.entries) {
        final path = 'games/${found.title}/${e.key}.json';
        final file = await addonFile(payload, path, createParents: true);
        await file.writeAsString(jsonEncode(e.value));
        units[path] = {
          'version': 1,
          'files': {'': await sha256File(file.path)},
        };
        final before = File('${profile.path}/user/$path');
        original[path] = await before.exists()
            ? await before.readAsString()
            : null;
      }
      final sentinel = File(
        '${profile.path}/user/astris-package-test-progress',
      );
      expect(await sentinel.exists(), false);
      await sentinel.writeAsString('preserved');
      final deployment = PackageProfile(profile, 'switch');
      const owner = '1234567890abcdef1234567890abcdef/1';
      try {
        await deployment.apply(owner, payload, units);
        await deployment.apply(owner, payload, units);
        final updates = await addonJson(
          File('${profile.path}/user/games/${found.title}/updates.json'),
        );
        expect(updates['selected'], found.updates!['selected']);
        final dlc = jsonDecode(
          await File('${profile.path}/user/games/${found.title}/dlc.json')
              .readAsString(),
        ) as List;
        expect(dlc.length, found.dlc!.length);
      } finally {
        await deployment.remove(owner);
      }
      for (final e in original.entries) {
        final file = File('${profile.path}/user/${e.key}');
        expect(await file.exists(), e.value != null);
        if (e.value != null) expect(await file.readAsString(), e.value);
      }
      expect(await sentinel.readAsString(), 'preserved');
      await sentinel.delete();
      stdout.writeln(
        'Astris ${found.title}: update + ${found.dlc!.length} DLC, native metadata reused and removed; progress retained. Evidence: ${stage.path}',
      );
    } finally {
      await lease.release();
      manager.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
