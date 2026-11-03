import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final host in ['linux-x64', 'macos-arm64']) {
    test(
      '$host platform reviews include only their requested core and share the frontend',
      () async {
        final root = await Directory.systemTemp.createTemp('broomm-scope-');
        final manager = ManagedEmulators(
          root,
          hostOverride: host,
          asset: (path) => File(path).readAsString(),
        );
        try {
          final all = await manager.readPlan(only: {'retroarch'});
          final nes = all.forPlatform('nes').items.single;
          final gb = all.forPlatform('gb').items.single;
          final snes = all.forPlatform('snes').items.single;
          expect(nes.cores.keys, ['mesen']);
          expect(gb.cores.keys, ['gambatte']);
          expect(nes.core, isNull);
          expect(nes.source, gb.source);
          expect(nes.downloads.length, 2);
          expect(gb.downloads.length, 2);
          expect(snes.downloads.length, 2);
          expect(snes.core != null || snes.cores.containsKey('snes9x'), isTrue);
          expect(all.items.single.cores.length, greaterThan(2));
          expect(() => all.forPlatform('ps4'), throwsStateError);
        } finally {
          manager.dispose();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
