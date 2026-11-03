import 'dart:io';

import '../progress/files.dart';

bool isRollingCore(Map value, Map expected, String host) =>
    value['managed'] == 'Broomm libretro core 1' &&
    value['id'] == expected['id'] &&
    value['host'] == host &&
    value['source_url'] == expected['source_url'] &&
    value['sha256'] is String &&
    RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String);

/// Explicit setup selects observed provider builds. Startup merely reads that
/// selection; it never downloads a newer nightly or changes a save-state group.
Future<Map<String, Map>> readRollingCores(
  Directory release,
  Map<String, Map> known,
  String host,
) async {
  final root = Directory('${release.path}/cores');
  final index = File('${root.path}/selected.json');
  if (!await progressExists(index.path)) return {};
  final record = await progressJson(await progressFile(root, 'selected.json'));
  if (record['version'] != 1 || record['selected'] is! Map)
    throw const FormatException('Invalid installed core selection.');
  final result = <String, Map>{};
  for (final entry in (record['selected'] as Map).entries) {
    if (!known.containsKey(entry.key) ||
        entry.value is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.value as String))
      throw const FormatException('Invalid installed core identity.');
    final value = await progressJson(
      await progressFile(root, '${entry.key}-${entry.value}/receipt.json'),
    );
    if (!isRollingCore(value, known[entry.key]!, host) ||
        value['sha256'] != entry.value)
      throw const FormatException(
        'Installed core receipt does not match its selection.',
      );
    result[entry.key as String] = value;
  }
  return result;
}
