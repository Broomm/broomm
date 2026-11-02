import 'dart:io';

import '../progress/files.dart';

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
) async => {
  for (final name in names)
    name: await linuxFileStamp(await progressFile(root, name)),
};

Future<void> verifyLinuxStamp(
  Directory root,
  Iterable<String> names,
  Object? value,
) async {
  final expected = names.toSet();
  if (value is! Map ||
      value.length != expected.length ||
      !expected.containsAll(value.keys))
    throw StateError(
      'The Linux installation has no complete setup verification record. Verify setup; existing data was kept.',
    );
  for (final name in expected) {
    final observed = await linuxFileStamp(await progressFile(root, name));
    final saved = value[name];
    if (saved is! Map ||
        saved.length != observed.length ||
        observed.entries.any((e) => saved[e.key] != e.value))
      throw StateError(
        'Managed Linux files changed since setup ($name). Verify setup before playing; settings and progress were kept.',
      );
  }
}

Future<void> verifyLinuxElf(File file) async {
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
        b[18] != 62 ||
        b[19] != 0 ||
        (b[16] != 2 && b[16] != 3) ||
        b[17] != 0)
      throw StateError(
        'Expected the reviewed Linux x64 ELF executable. No installation was changed.',
      );
  } finally {
    await handle.close();
  }
}
