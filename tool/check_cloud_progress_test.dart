import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/zip.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/session_lease.dart';

void main() {
  test('supplied ROM identities and isolated native progress snapshots restore byte-for-byte without copying settings or other games', () async {
    if (!Platform.isMacOS)
      throw UnsupportedError('Requires the existing native macOS fixtures');
    final project = Directory.current;
    final evidence = Directory(
      '${project.path}/.tool-cache/research/cloud-saves',
    );
    await evidence.create(recursive: true);
    final root = await evidence.createTemp('native-progress-');
    final owner = Directory('${project.path}/broomm-data');
    final prototype = Directory(
      '${project.path}/.tool-cache/research/managed-play/native-data',
    );
    const ownerProfile = '15770cf1430ff66c406582cc4245ae63';
    const prototypeProfile = 'f123456789abcdef0123456789abcdef';
    final builds =
        (jsonDecode(
              await File('${project.path}/assets/setup/tested-builds.json')
                  .readAsString(),
            ) as Map)['builds']
            as List;
    final results = <Map<String, dynamic>>[];
    final sourceLease = await SessionLease.acquire(owner);
    final prototypeLease = await SessionLease.acquire(prototype);
    try {
      final fixtures = [
        (
          'RetroArch',
          'snes',
          'roms/snes/Super Mario World (USA).sfc',
          owner,
          ownerProfile,
        ),
        (
          'Dolphin',
          'ngc',
          'roms/ngc/Super Smash Bros. Melee (USA) (En,Ja).rvz',
          owner,
          ownerProfile,
        ),
        (
          'Dolphin',
          'wii',
          'roms/wii/Super Smash Bros. Brawl (USA, Canada) (Rev 2).rvz',
          owner,
          ownerProfile,
        ),
        (
          'Azahar',
          '3ds',
          'roms/n3ds/Mario Kart 7 (USA) (En,Fr,Es) (Rev 1).cci',
          prototype,
          prototypeProfile,
        ),
        (
          'RPCS3',
          'ps3',
          'roms/ps3/Rayman Legends BLUS31183/PS3_GAME/USRDIR/EBOOT.BIN',
          prototype,
          prototypeProfile,
        ),
        (
          'melonDS',
          'nds',
          'broomm-data/library/506d439865d8f46267001bdd3a1fe0e5/5590/content/Pokemon Ranger.nds',
          owner,
          ownerProfile,
        ),
      ];
      for (final (name, platform, rom, source, profile) in fixtures) {
        final nativeSource = Directory(
          '${source.path}/profiles/$profile/emulators/${name.toLowerCase()}',
        );
        final native = Directory('${root.path}/$platform/profile');
        await native.parent.create(recursive: true);
        final copy = await Process.run('/bin/cp', [
          '-cR',
          nativeSource.path,
          native.path,
        ]);
        expect(copy.exitCode, 0, reason: '${copy.stderr}');
        final build = builds.cast<Map>().singleWhere(
          (b) => b['id'] == name.toLowerCase(),
        );
        final user = name == 'Azahar'
            ? '${native.path}/home/Library/Application Support/Azahar'
            : name == 'RPCS3'
            ? '${native.path}/portable'
            : '${native.path}/user';
        final resolved = ResolvedSession(
          PreparedEmulator(
            name,
            native.path,
            'unused',
            3,
            null,
            null,
            userDirectory: user,
          ),
          '${project.path}/$rom',
          build['sha256'] as String,
          {},
          coreHash: build['core_sha256'] as String?,
        );
        final layout = await gameProgressLayout(resolved, platform);
        final original = await layout.files();
        final hashes = <String, String>{};
        for (final e in original.entries) {
          hashes[e.key] = await progressFileHash(e.value);
        }
        // Files deliberately outside this title's boundary must survive restore.
        final sentinel = File('${native.path}/unrelated-game-and-settings');
        await sentinel.writeAsString('keep');
        final store = ProgressStore(
          Directory('${root.path}/$platform/cloud'),
          layout,
          42,
          3,
        );
        final snapshot = await store.capture();
        final imported = await store.importBundle(snapshot.bundle);
        expect(imported.digest, snapshot.digest);
        String? exportedExtension;
        if (!snapshot.empty) {
          final exported = await store.exportNative(snapshot);
          try {
            exportedExtension = exported.extension;
            final expected = platform == 'nds'
                ? 'sav'
                : platform == 'snes'
                ? 'srm'
                : 'zip';
            expect(exported.extension, expected);
            if (exported.extension == 'zip') {
              final archive = await ProgressZip.read(exported.file);
              expect(
                archive.entries.any((e) => e.name == 'broomm.json'),
                false,
              );
            } else {
              expect(
                await exported.file.readAsBytes(),
                await original.values.single.readAsBytes(),
              );
            }
            final nativeImported = await store.importNative(exported.file);
            expect(nativeImported.ordinaryDigest, snapshot.ordinaryDigest);
            final retainedStore = ProgressStore(
              Directory('${root.path}/$platform/retained'),
              ProgressLayout(
                native.path,
                layout.format,
                layout.game,
                [],
                archiveOnly: true,
              ),
              42,
              3,
            );
            final retained = await retainedStore.importNative(exported.file);
            expect(retained.ordinaryDigest, snapshot.ordinaryDigest);
          } finally {
            await exported.close();
          }
        }
        for (final file in original.values) {
          final bytes = await file.readAsBytes();
          // Preserve format identities (notably the GCI title header) while
          // changing payload bytes in the disposable copy.
          if (bytes.isNotEmpty) bytes[bytes.length - 1] ^= 0xff;
          await file.writeAsBytes(bytes, flush: true);
        }
        await store.restore(imported, {'pending': false});
        final after = await layout.files();
        for (final e in after.entries) {
          expect(
            await progressFileHash(e.value),
            hashes[e.key],
            reason: '${layout.identity}: ${e.key}',
          );
        }
        expect(await sentinel.readAsString(), 'keep');
        expect(
          snapshot.entries.keys.any(
            (k) =>
                k.contains('config') ||
                k.contains('ticket') ||
                k.contains('/content/'),
          ),
          false,
        );
        results.add({
          'emulator': name,
          'platform': platform,
          'identity': layout.identity,
          'files': original.length,
          'bytes': original.values.isEmpty
              ? 0
              : (await Future.wait(original.values.map((f) => f.length())))
                    .fold<int>(0, (a, b) => a + b),
          'roundTrip': true,
          'nativeExportExtension': exportedExtension,
          'nativeExportRoundTrip': !snapshot.empty,
          'note': original.isEmpty
              ? 'Identity validated; this fixture has no game progress. No gameplay save-load claim.'
              : 'Native files restored byte-for-byte; no gameplay save-load claim.',
        });
      }
    } finally {
      await prototypeLease.release();
      await sourceLease.release();
    }
    await File('${evidence.path}/native-progress.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'host': Platform.operatingSystem,
        'fixtures': root.path,
        'results': results,
      }),
      flush: true,
    );
    // Report no progress contents, account credentials or source hashes.
    for (final result in results) {
      stdout.writeln(
        '${result['platform']}: ${result['files']} files, identity ${result['identity']}, isolated round trip passed',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
