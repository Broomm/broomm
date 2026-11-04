import 'dart:io';
import 'dart:isolate';

import '../progress/files.dart';

String? linuxDistribution() {
  if (!Platform.isLinux) return null;
  for (final path in ['/etc/os-release', '/usr/lib/os-release']) {
    try {
      return linuxOsReleaseId(File(path).readAsStringSync());
    } on FileSystemException {
      // Some images expose only the vendor os-release file.
    }
  }
  return null;
}

String? linuxOsReleaseId(String text) {
  final value = RegExp(
    r"""^ID=(?:"([a-z0-9._-]+)"|'([a-z0-9._-]+)'|([a-z0-9._-]+))\s*$""",
    multiLine: true,
  ).firstMatch(text);
  return value?.group(1) ?? value?.group(2) ?? value?.group(3);
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
