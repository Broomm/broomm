part of 'store.dart';

class NativeProgressExport {
  const NativeProgressExport(
    this.file,
    this.extension, {
    this.stage,
    this.includesStates = false,
  });
  final File file;
  final String extension;
  final Directory? stage;
  final bool includesStates;
  Future<void> close() async {
    if (stage != null && await stage!.exists())
      await stage!.delete(recursive: true);
  }
}

extension NativeProgressExportStore on ProgressStore {
  /// Internal recovery/provenance stays in Broomm's local snapshot. Public
  /// saves contain native bytes, or a real ZIP of the native directory data.
  Future<NativeProgressExport> exportNative(
    ProgressSnapshot snapshot,
  ) => Isolate.run(() async {
    await _verify(snapshot.directory, snapshot.manifest);
    final ordinary =
        snapshot.entries.keys.where((k) => !k.startsWith('states-')).toList()
          ..sort();
    final raw = layout.rawSaveKey;
    if (raw != null && ordinary.length == 1 && ordinary.single == raw)
      return NativeProgressExport(
        await progressFile(
          Directory('${snapshot.directory.path}/files'),
          ordinary.single,
        ),
        raw.split('.').last,
      );
    // A session can have states before its first ordinary in-game save.
    if (ordinary.isEmpty)
      return NativeProgressExport(snapshot.bundle, 'zip', includesStates: true);
    final stage = await directory.createTemp('.native-export-');
    try {
      final root = Directory('${stage.path}/data');
      await root.create();
      final areas = ordinary.map((k) => k.split('/').first).toSet();
      final preserveAreas =
          areas.length > 1 || areas.single != 'save' && areas.single != 'cardA';
      final names = <String>[];
      for (final key in ordinary) {
        final name = preserveAreas ? key : key.substring(key.indexOf('/') + 1);
        await _copy(
          await progressFile(
            Directory('${snapshot.directory.path}/files'),
            key,
          ),
          await progressFile(root, name, createParents: true),
        );
        names.add(name);
      }
      final output = File('${stage.path}/progress.zip');
      await ProgressZip.write(output, root, names);
      return NativeProgressExport(output, 'zip', stage: stage);
    } catch (_) {
      await stage.delete(recursive: true);
      rethrow;
    }
  });
}
