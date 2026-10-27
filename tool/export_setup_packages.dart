// Explicit development distribution export. Does not change trusted recipes,
// source applications, profile configuration, firmware, keys, ROMs or progress.
import 'dart:convert';
import 'dart:io';

import '../lib/src/progress/digest.dart';
import '../lib/src/progress/files.dart';
import '../lib/src/setup/package.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && (args.length != 2 || args.first != '--output'))
    throw const FormatException(
      'Usage: dart tool/export_setup_packages.dart [--output directory]',
    );
  if (!Platform.isMacOS)
    throw UnsupportedError('The snapshot pack requires its native macOS host.');
  final manifestFile = File('assets/setup/setup.json');
  final manifest = jsonDecode(await manifestFile.readAsString()) as Map;
  final output = Directory(
    args.isEmpty ? 'build/setup-packages/macos-arm64' : args[1],
  );
  await progressDirectory(output);
  final target = await progressFile(output, 'setup.json');
  if (await target.exists() &&
      jsonEncode(jsonDecode(await target.readAsString())) !=
          jsonEncode(manifest))
    throw StateError(
      'The output setup JSON contains different recipes; it was kept. Choose a new --output directory.',
    );
  final packages = <String, MapEntry<SetupPackage, String>>{};
  for (final entry in (manifest['launchers'] as Map).entries) {
    final id = entry.key as String, spec = entry.value as Map;
    for (final value in [
      spec['source'],
      spec['core'],
      ...(spec['cores'] as Map? ?? {}).values,
    ]) {
      if (value is! Map || value['file'] == null) continue;
      final package = SetupPackage.fromJson(value);
      final source = value == spec['source']
          ? 'prototype-data/$id'
          : value == spec['core']
          ? 'prototype-data/retroarch'
          : 'prototype-data/retroarch/cores';
      packages[package.file!] = MapEntry(package, source);
    }
  }
  for (final entry in packages.entries) {
    final package = entry.value.key;
    final target = await progressFile(output, entry.key);
    if (!await target.exists()) {
      final stage = await output.createTemp('.export-');
      try {
        final archive = File('${stage.path}/archive');
        final result = await Process.run('/usr/bin/tar', [
          '-czf',
          archive.absolute.path,
          '--format=ustar',
          '--no-xattrs',
          '--no-acls',
          '--no-fflags',
          '-C',
          Directory(entry.value.value).absolute.path,
          package.entry,
        ]);
        if (result.exitCode != 0)
          throw StateError('Could not export ${entry.key}.');
        if (await archive.length() != package.bytes ||
            await progressFileHash(archive) != package.sha256)
          throw StateError(
            '${entry.key} did not reproduce the pinned archive. The recipe and existing files were kept. Use the retained reviewed archive; do not recapture fingerprints to bypass this check.',
          );
        await archive.rename(target.path);
      } finally {
        await stage.delete(recursive: true);
      }
    }
    if (await target.length() != package.bytes ||
        await progressFileHash(target) != package.sha256)
      throw StateError('${entry.key} changed. The existing archive was kept.');
    stdout.writeln('${entry.key}: reviewed archive verified');
  }
  final text = await manifestFile.readAsString();
  final stage = await output.createTemp('.manifest-');
  try {
    final file = await File('${stage.path}/setup.json')
        .writeAsString(text, flush: true);
    if (await file.readAsString() != text)
      throw StateError('Setup JSON readback failed.');
    await file.rename(target.path);
  } finally {
    await stage.delete(recursive: true);
  }
  stdout.writeln(
    'Verified ${packages.length} snapshot archives under ${output.path}.',
  );
}
