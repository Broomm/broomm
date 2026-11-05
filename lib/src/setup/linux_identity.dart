import 'dart:io';
import 'dart:isolate';
import 'dart:ffi';

import '../progress/files.dart';

/// Native page size matters for ARMSX2's distinct Linux ARM64 builds. A
/// non-Linux inspection host uses 4K; callers can supply a fixture value.
int linuxKernelPageBytes() => Platform.isLinux
    ? DynamicLibrary.process().lookupFunction<Int32 Function(), int Function()>(
        'getpagesize',
      )()
    : 4096;

const _pageBuildFields = {
  'version',
  'executable',
  'sha256',
  'native',
  'integrity_asset',
  'symbols_asset',
  'source_package',
  'sdl',
  'sdl_library',
  'linux_launcher',
};

/// The trusted build inventory retains one emulator/card identity while its
/// executable, native symbols and save-state build identity follow the kernel.
List<Map> linuxPageBuilds(Map build) {
  final variants = build['linux_page_variants'];
  if (variants == null) return [build];
  if (build['host'] != 'linux-arm64' ||
      variants is! Map ||
      build['linux_page_bytes'] is! int) {
    throw const FormatException('Invalid Linux page-specific build inventory');
  }
  final result = <Map>[build];
  for (final entry in variants.entries) {
    final bytes = int.tryParse(entry.key.toString());
    if (bytes == null ||
        !{4096, 16384}.contains(bytes) ||
        entry.value is! Map ||
        (entry.value as Map).keys.any((k) => !_pageBuildFields.contains(k))) {
      throw const FormatException('Invalid Linux page-specific build variant');
    }
    result.add({...build, ...(entry.value as Map), 'linux_page_bytes': bytes});
  }
  return result;
}

Object? linuxPageSource(Object? source, int bytes) {
  if (source is! Map || !source.containsKey('linux_page_variants'))
    return source;
  final variants = source['linux_page_variants'];
  if (source.length != 1 ||
      variants is! Map ||
      variants.keys.any((k) => !{'4096', '16384'}.contains(k)) ||
      variants['$bytes'] is! Map) {
    throw const FormatException(
      'No reviewed emulator package matches the Linux page size',
    );
  }
  return variants['$bytes'];
}

Future<Map<String, int>> linuxFileStamp(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file)
    throw StateError(
      'A managed Linux executable is missing or linked. Verify setup; existing progress was kept.',
    );
  final stat = await file.stat();
  return {
    'bytes': stat.size,
    'modified': stat.modified.microsecondsSinceEpoch,
    'changed': stat.changed.microsecondsSinceEpoch,
    'mode': stat.mode,
  };
}

Future<Map<String, Object>> linuxTreeStamp(
  Directory root,
  Iterable<String> names,
) => _stampWorker(root.path, names.toList());

Future<Map<String, Object>> _stampWorker(String path, List<String> names) =>
    Isolate.run(() => _stampTree(Directory(path), names));

Future<Map<String, Object>> _stampTree(
  Directory root,
  List<String> names,
) async => {
  for (final name in names)
    name: await linuxFileStamp(await progressFile(root, name)),
};

Future<void> verifyLinuxStamp(
  Directory root,
  Iterable<String> names,
  Object? value,
) async {
  final observedFiles = await linuxTreeStamp(root, names);
  final expected = observedFiles.keys.toSet();
  if (value is! Map ||
      value.length != expected.length ||
      !expected.containsAll(value.keys))
    throw StateError(
      'The Linux installation has no complete setup verification record. Verify setup; existing data was kept.',
    );
  for (final name in expected) {
    final observed = observedFiles[name] as Map;
    final saved = value[name];
    if (saved is! Map ||
        saved.length != observed.length ||
        observed.entries.any((e) => saved[e.key] != e.value))
      throw StateError(
        'Managed Linux files changed since setup ($name). Verify setup before playing; settings and progress were kept.',
      );
  }
}

Future<void> verifyLinuxElf(File file, {required String architecture}) async {
  final machine = switch (architecture) {
    'x64' => 62,
    'arm64' => 183,
    _ => throw ArgumentError.value(architecture, 'architecture'),
  };
  final handle = await file.open();
  try {
    final b = await handle.read(64);
    if (b.length < 64 ||
        b[0] != 0x7f ||
        b[1] != 69 ||
        b[2] != 76 ||
        b[3] != 70 ||
        b[4] != 2 ||
        b[5] != 1 ||
        b[18] != machine ||
        b[19] != 0 ||
        (b[16] != 2 && b[16] != 3) ||
        b[17] != 0)
      throw StateError(
        'Expected the reviewed Linux $architecture ELF executable. No installation was changed.',
      );
  } finally {
    await handle.close();
  }
}
