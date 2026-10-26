import 'dart:io';

import 'files.dart';

enum CloudSaveStatus { synced, waiting, attention }

/// A read-only observation of the last durable sync result. Reading a badge
/// never prepares an emulator, reads native progress, or contacts RomM.
Future<CloudSaveStatus> readCloudSaveStatus(
  Directory data,
  String server,
  String profile,
  int rom,
) async {
  if (![server, profile].every((s) => RegExp(r'^[a-f0-9]{32}$').hasMatch(s)) ||
      rom < 1)
    return CloudSaveStatus.attention;
  try {
    var folder = data;
    for (final part in ['cloud-saves', server, profile, '$rom']) {
      folder = Directory('${folder.path}/$part');
      final type = await FileSystemEntity.type(folder.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return CloudSaveStatus.waiting;
      if (type != FileSystemEntityType.directory)
        return CloudSaveStatus.attention;
    }
    final file = await progressFile(folder, 'state.json');
    if (!await file.exists()) return CloudSaveStatus.waiting;
    final state = await progressJson(file);
    if (state['unclean'] == true ||
        state['conflict'] != null ||
        await progressExists('${folder.path}/restore.json'))
      return CloudSaveStatus.attention;
    if (state['active'] == true || state['pending'] != false)
      return CloudSaveStatus.waiting;
    if (state['synced'] is! String ||
        DateTime.tryParse(state['synced'] as String) == null)
      return CloudSaveStatus.waiting;
    if (state['emptySynced'] != true &&
        (state['baseline'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(state['baseline'] as String)))
      return CloudSaveStatus.attention;
    return CloudSaveStatus.synced;
  } catch (_) {
    return CloudSaveStatus.attention;
  }
}
