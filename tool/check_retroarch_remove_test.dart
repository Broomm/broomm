@TestOn('mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/addons/files.dart';

void main() {
  test('the installed real core pack can be removed without changing private native saves or states', () async {
    final evidence = Directory('.tool-cache/research/ra-wii-switch');
    final fixtures = await evidence
        .list()
        .where((e) => e is Directory && e.path.contains('/native-retro-play-'))
        .cast<Directory>()
        .toList();
    fixtures.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    final data = Directory('${fixtures.first.absolute.path}/data');
    final manager = ManagedEmulators(
      data,
      project: Directory.current.path,
      asset: (p) => File(p).readAsString(),
    );
    await manager.load();
    expect(manager.installedCores, hasLength(14));
    final native = Directory(
      '${data.path}/profiles/a123456789abcdef0123456789abcdef/emulators/retroarch/core-data',
    );
    final before = await addonInventory(native);
    expect(before, isNotEmpty);
    await manager.remove(manager.buildFor('RetroArch')!);
    expect(manager.error, isNull, reason: manager.error);
    expect(await addonInventory(native), before);
    expect(
      await Directory(
        '${data.path}/emulators/retroarch/${manager.buildFor('RetroArch')!.hash}',
      ).exists(),
      false,
    );
    await File('${fixtures.first.path}/removal-verified.txt').writeAsString(
      'All 14 owned cores removed; ${before.length} private native progress files retained with identical hashes.',
    );
    manager.dispose();
  });
}
