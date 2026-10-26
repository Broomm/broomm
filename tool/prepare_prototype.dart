import 'dart:convert';
import 'dart:io';

// Explicit, local-only provisioning. Never searches for or downloads firmware.
Future<void> main() async {
  if (!Platform.isMacOS)
    throw UnsupportedError('Prototype bridge currently requires macOS arm64');
  final project = Directory.current.absolute.path;
  final data = '$project/prototype-data';
  await Directory(data).create(recursive: true);
  final lock = await File('$data/session.lock').open(mode: FileMode.append);
  await lock.lock(FileLock.exclusive);
  try {
    final writer = await File('$data/writer.lock').open(mode: FileMode.append);
    try {
      await writer.lock(FileLock.exclusive);
      await writer.unlock();
    } finally {
      await writer.close();
    }
    final manifest = <String, dynamic>{
      'protocol': 1,
      'project': project,
      'emulators': {},
    };
    for (final name in ['RetroArch', 'Dolphin', 'RPCS3', 'Azahar', 'Ryubing']) {
      final source =
          '$project/experiments/injection/sessions/${name.toLowerCase()}';
      final metadata = jsonDecode(
        await File('$source/installation.json').readAsString(),
      ) as Map<String, dynamic>;
      final target = '$data/${name.toLowerCase()}';
      if (!await Directory(target).exists()) {
        final stage = '$target.staging';
        if (await Directory(stage).exists()) {
          await Directory(stage)
              .rename('$stage.failed-${DateTime.now().microsecondsSinceEpoch}');
        }
        await Directory(stage).create();
        // Do not copy transient emulator logs (RPCS3 deliberately seals old
        // compressed logs with mode 000). Persistent game/firmware data remains.
        final bundleName = (metadata['bundle'] as String).split('/').last;
        for (final relative in [
          bundleName,
          name == 'RPCS3' ? 'portable' : 'user',
          'cache/cache',
          'system',
          'saves',
          'states',
          'config',
          'data',
          'screenshots',
        ]) {
          final item = Directory('$source/$relative');
          if (!await item.exists()) continue;
          final destination = Directory('$stage/$relative');
          await destination.parent.create(recursive: true);
          final copy = await Process.run('/bin/cp', [
            '-cR',
            item.path,
            destination.path,
          ]);
          if (copy.exitCode != 0)
            throw StateError('Copy failed for $name/$relative: ${copy.stderr}');
        }
        await Directory(stage).rename(target);
      }
      metadata['root'] = target;
      for (final key in ['bundle', 'executable', 'user', 'sdl_library']) {
        if (metadata[key] != null)
          metadata[key] = (metadata[key] as String).replaceFirst(
            source,
            target,
          );
      }
      if (name == 'RetroArch') {
        final original = jsonDecode(
          await File(
            '$project/experiments/injection/artifacts/local-installations.json',
          ).readAsString(),
        ) as Map;
        final bundle = original[name]['bundle'] as String;
        final core =
            '${bundle.substring(0, bundle.lastIndexOf('/app/'))}/cores/snes9x_libretro.dylib';
        final dest = '$target/snes9x_libretro.dylib';
        if (!await File(dest).exists()) await File(core).copy(dest);
        metadata['core'] = dest;
      }
      // Executable symbols are resolved afresh for these copied builds, not reused
      // from stale ASLR addresses. No compilers are needed by the running app.
      final symbols = await Process.run('/usr/bin/nm', [
        '-arch',
        'arm64',
        metadata['executable'] as String,
      ]);
      if (symbols.exitCode != 0)
        throw StateError('Cannot inspect $name symbols');
      await File('$target/local-symbols.txt').writeAsString(
        RegExp(
              r'^([0-9a-f]+) [tT] _(SDL_\S+|_ZNK11GMainWindow10metaObjectEv|_ZNK11main_window10metaObjectEv|_ZN11GMainWindow11OnPauseGameEv|_ZN11GMainWindow12OnResumeGameEb|_ZN11main_window13OnPlayOrPauseEv)$',
              multiLine: true,
            )
            .allMatches(symbols.stdout as String)
            .map((m) => '${m[1]} ${m[2]}')
            .join('\n'),
      );
      final native = <String, String>{};
      if (name == 'Dolphin') {
        for (final entry in {
          'BROOMM_CORE_SYSTEM': '__ZN4Core6System11GetInstanceEv',
          'BROOMM_CORE_STATE': '__ZN4Core8GetStateERNS_6SystemE',
          'BROOMM_CORE_SET_STATE':
              '__ZN4Core8SetStateERNS_6SystemENS_5StateEbb',
        }.entries) {
          final m = RegExp(
            '^([0-9a-f]+) [tT] ${entry.value}\$',
            multiLine: true,
          ).firstMatch(symbols.stdout as String);
          if (m == null)
            throw StateError('Unsupported Dolphin: ${entry.value}');
          native[entry.key] = m[1]!;
        }
      }
      if (name == 'RPCS3') {
        final m = RegExp(
          r'^([0-9a-f]+) [SBD] _Emu$',
          multiLine: true,
        ).firstMatch(symbols.stdout as String);
        if (m == null) throw StateError('Unsupported RPCS3 status ABI');
        native['BROOMM_EMU_STATUS'] = m[1]!;
      }
      metadata['native'] = native;
      final hash = await Process.run('/usr/bin/shasum', [
        '-a',
        '256',
        metadata['executable'] as String,
      ]);
      if (hash.exitCode != 0) throw StateError('Cannot fingerprint $name');
      metadata['executable_sha256'] = (hash.stdout as String).split(' ').first;
      (manifest['emulators'] as Map)[name] = metadata;
      stdout.writeln('Prepared $name in $target');
    }
    final file = File('$data/installations.json.pending');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );
    await file.rename('$data/installations.json');
  } finally {
    await lock.unlock();
    await lock.close();
  }
}
