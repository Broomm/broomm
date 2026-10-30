import 'dart:io';

import '../progress/digest.dart';
import '../progress/files.dart';
import '../progress/layout.dart';
import '../progress/service.dart';
import '../progress/store.dart';
import 'emulators.dart';

/// Dart owns the shared-folder swap and recovery journal. Android only performs
/// bounded document I/O. The caller holds SessionLease and confirms MMJ is closed.
/// Unknown standalone saves are backed up and restored, never silently adopted
/// into a RomM profile. Each external write has verified old/new inventories.
class MmjSharedSaves {
  MmjSharedSaves(this.manager, {this.phase});
  final AndroidEmulators manager;
  final void Function(String)? phase;
  File get journal => File('${manager.data.path}/android/mmj-swap.json');

  Future<bool> get pending => progressExists(journal.path);

  List<Map<String, String>> _areas(ProgressLayout layout) {
    if (layout.format != 'azahar-data-v1' ||
        !RegExp(r'^00040000[a-f0-9]{8}$').hasMatch(layout.game))
      throw const FormatException('Unsupported MMJ title save boundary');
    const zeros = '00000000000000000000000000000000';
    final sd = 'sdmc/Nintendo 3DS/$zeros/$zeros';
    final result = <Map<String, String>>[];
    for (final area in layout.areas) {
      final path = area.path;
      final expected = area.id == 'save'
          ? '$sd/title/00040000/${layout.game.substring(8)}/data'
          : RegExp(r'^ext-[a-f0-9]{8}$').hasMatch(area.id)
          ? '$sd/extdata/00000000/${area.id.substring(4)}'
          : null;
      if (expected == null || path != 'user/$expected')
        throw const FormatException('Unsupported MMJ save directory');
      result.add({'path': expected});
    }
    if (!layout.areas.any((a) => a.id == 'save'))
      throw const FormatException('Missing MMJ title save directory');
    // Hide standalone states while a profile is active. New MMJ states remain
    // in its retained capture, but are not claimed as compatible cloud states.
    result.add({
      'path': 'states',
      'prefix': '${layout.game.toUpperCase()}.',
      'suffix': '.cst',
    });
    return result;
  }

  void _game(CloudGame game) {
    if (game.layout.root !=
        '${manager.data.path}/profiles/${game.profile}/emulators/citra-mmj')
      throw const FormatException(
        'MMJ save storage belongs to another profile',
      );
    _areas(game.layout);
  }

  Future<Map<String, dynamic>> _record(CloudGame game) async {
    _game(game);
    final record = await progressJson(journal);
    if (record['version'] != 1 ||
        record['profile'] != game.profile ||
        record['server'] != game.server ||
        record['rom'] != game.rom ||
        record['title'] != game.layout.game ||
        !RegExp(r'^[a-f0-9]{32}$')
            .hasMatch(record['transaction'] as String? ?? '') ||
        !AndroidEmulators.sharedMmjTree(record['tree'] as String? ?? '') ||
        !{
          'installing',
          'installed',
          'captured',
          'restoring',
          'restored',
        }.contains(record['phase']))
      throw const FormatException(
        'MMJ recovery belongs to another game/profile or is damaged. Files were kept.',
      );
    _inventory(record['original'], game.layout);
    _inventory(record['working'], game.layout);
    if (record['captured'] != null) _inventory(record['captured'], game.layout);
    return record;
  }

  Directory _directory(Map<String, dynamic> record) => Directory(
    '${manager.data.path}/android/mmj-session/${record['transaction']}',
  );

  Map<String, dynamic> _inventory(Object? value, ProgressLayout layout) {
    if (value is! Map || value.length > progressMaxFiles)
      throw const FormatException('Invalid MMJ file inventory');
    final files = value.cast<String, dynamic>();
    var total = 0;
    final areas = _areas(layout);
    for (final entry in files.entries) {
      progressRelative(entry.key);
      if (!areas.any((area) {
        final base = '${area['path']}/';
        if (!entry.key.startsWith(base)) return false;
        final relative = entry.key.substring(base.length);
        return area['prefix'] == null ||
            !relative.contains('/') &&
                relative.startsWith(area['prefix']!) &&
                relative.endsWith(area['suffix']!);
      }))
        throw const FormatException('MMJ file is outside the selected title');
      final metadata = entry.value;
      if (metadata is! Map ||
          metadata['bytes'] is! int ||
          metadata['bytes'] < 0 ||
          metadata['bytes'] > progressMaxFileBytes ||
          !RegExp(r'^[a-f0-9]{64}$')
              .hasMatch(metadata['sha256'] as String? ?? ''))
        throw const FormatException('Invalid MMJ save metadata');
      total += metadata['bytes'] as int;
      if (total > progressMaxBytes)
        throw const FormatException(
          'MMJ saves exceed the supported size limit',
        );
    }
    return files;
  }

  Future<Map<String, dynamic>> _list(String tree, ProgressLayout layout) async {
    final result = await manager.channel.invokeMapMethod<String, dynamic>(
      'sharedList',
      {'tree': tree, 'areas': _areas(layout)},
    );
    return _inventory(result, layout);
  }

  bool _same(Map<String, dynamic> a, Map<String, dynamic> b) =>
      progressEntriesDigest(a) == progressEntriesDigest(b);

  Future<void> _read(
    Map<String, dynamic> record,
    ProgressLayout layout,
    Map<String, dynamic> inventory,
    String destination,
  ) async {
    final elapsed = Stopwatch()..start();
    phase?.call(
      'MMJ ${layout.game}: copying ${inventory.length} shared save files into private recovery.',
    );
    final dir = _directory(record);
    for (final entry in inventory.entries) {
      final file = await progressFile(
        dir,
        '$destination/${entry.key}',
        createParents: true,
      );
      await manager.channel.invokeMethod<void>('sharedRead', {
        'tree': record['tree'],
        'path': entry.key,
        'target': file.path,
        'sha256': entry.value['sha256'],
        'bytes': entry.value['bytes'],
      });
      if (await file.length() != entry.value['bytes'] ||
          await progressFileHash(file) != entry.value['sha256'])
        throw const FileSystemException('MMJ save snapshot failed readback');
    }
    if (!_same(await _list(record['tree'] as String, layout), inventory))
      throw StateError(
        'MMJ saves changed while reading. Close MMJ completely and retry; copies were kept.',
      );
    phase?.call(
      'MMJ ${layout.game}: private recovery copy verified after ${elapsed.elapsedMilliseconds} ms.',
    );
  }

  Future<void> _copy(File source, File target, Map metadata) async {
    await target.create(exclusive: true);
    final output = await target.open(mode: FileMode.writeOnly);
    try {
      await for (final bytes in source.openRead())
        await output.writeFrom(bytes);
      await output.flush();
    } finally {
      await output.close();
    }
    if (await target.length() != metadata['bytes'] ||
        await progressFileHash(target) != metadata['sha256'] ||
        await progressFileHash(source) != metadata['sha256'])
      throw StateError(
        'MMJ profile progress changed while preparing its copy.',
      );
  }

  Future<void> begin(CloudGame game, String build) async {
    _game(game);
    if (await pending)
      throw StateError('Finish the previous MMJ shared-folder session first.');
    final emulator = androidEmulators.singleWhere((e) => e.id == 'citra-mmj');
    final tree = manager.tree(game.profile, emulator);
    if (tree == null || !AndroidEmulators.sharedMmjTree(tree))
      throw StateError(
        'Connect MMJ’s shared citra-emu folder in Emulator Settings.',
      );
    await manager.channel.invokeMethod<void>('sharedCheck', {'tree': tree});
    final record = <String, dynamic>{
      'version': 1,
      'transaction': progressNonce(),
      'tree': tree,
      'profile': game.profile,
      'server': game.server,
      'rom': game.rom,
      'title': game.layout.game,
      'build': build,
      'phase': 'installing',
      'original': await _list(tree, game.layout),
      'working': <String, dynamic>{},
    };
    final dir = _directory(record);
    await progressDirectory(dir);
    await _read(
      record,
      game.layout,
      record['original'] as Map<String, dynamic>,
      'original',
    );
    final working = record['working'] as Map<String, dynamic>;
    for (final entry in (await game.layout.files()).entries) {
      final area = game.layout.area(entry.key.split('/').first);
      final relative =
          '${area.path.substring(5)}/${area.native(entry.key.substring(area.id.length + 1))}';
      final metadata = {
        'bytes': await entry.value.length(),
        'sha256': await progressFileHash(entry.value),
      };
      working[relative] = metadata;
      await _copy(
        entry.value,
        await progressFile(dir, 'working/$relative', createParents: true),
        metadata,
      );
    }
    _inventory(working, game.layout);
    // No shared save is changed until both complete recovery copies exist.
    await progressWrite(
      await progressFile(
        manager.data,
        'android/mmj-swap.json',
        createParents: true,
      ),
      record,
    );
    await _apply(record, game.layout, 'original', 'working', 'working');
    record['phase'] = 'installed';
    await progressWrite(journal, record);
  }

  Future<void> _apply(
    Map<String, dynamic> record,
    ProgressLayout layout,
    String beforeKey,
    String afterKey,
    String source,
  ) async {
    final elapsed = Stopwatch()..start();
    final before = _inventory(record[beforeKey], layout);
    final after = _inventory(record[afterKey], layout);
    final paths = {...before.keys, ...after.keys}.toList()..sort();
    phase?.call(
      'MMJ ${layout.game}: applying $afterKey shared save inventory (${paths.length} files).',
    );
    for (final path in paths) {
      final next = after[path] as Map?;
      final file = next == null
          ? null
          : await progressFile(_directory(record), '$source/$path');
      if (file != null &&
          (await file.length() != next!['bytes'] ||
              await progressFileHash(file) != next['sha256']))
        throw const FileSystemException(
          'MMJ recovery copy is damaged; shared saves were kept.',
        );
      await manager.channel.invokeMethod<void>('sharedReplace', {
        'tree': record['tree'],
        'path': path,
        'before': before[path]?['sha256'],
        'after': next?['sha256'],
        'source': file?.path,
        'token':
            '${record['transaction']}-${afterKey == 'working' ? 'in' : 'out'}',
      });
    }
    if (!_same(await _list(record['tree'] as String, layout), after))
      throw StateError(
        'MMJ shared saves changed during replacement. Recovery copies were kept.',
      );
    phase?.call(
      'MMJ ${layout.game}: $afterKey shared save inventory verified after ${elapsed.elapsedMilliseconds} ms.',
    );
  }

  /// False means no game could run (installation was interrupted), or the
  /// profile was already captured before restoring standalone saves.
  Future<bool> capture(CloudGame game, CloudSaves cloud) async {
    final record = await _record(game);
    if (record['phase'] == 'restoring' || record['phase'] == 'restored')
      return false;
    if (record['phase'] == 'installing') {
      await _apply(record, game.layout, 'original', 'working', 'working');
      record['captured'] = record['working'];
      record['capture'] = 'working';
      record['phase'] = 'restoring';
      await progressWrite(journal, record);
      return false;
    }
    final inventory = await _list(record['tree'] as String, game.layout);
    final capture = 'captures/${progressNonce()}';
    await _read(record, game.layout, inventory, '$capture/user');
    // Reuse the ordinary cloud store's interruption-safe private restore. Native
    // states stay in the retained capture and never enter the cloud manifest.
    final store = cloud.store(game);
    await store.recover();
    final snapshot = await ProgressStore(
      store.directory,
      ProgressLayout(
        '${_directory(record).path}/$capture',
        game.layout.format,
        game.layout.game,
        game.layout.areas,
      ),
      game.rom,
      game.user,
      ownerRoot: manager.data,
    ).capture();
    await store.restore(snapshot, await store.state());
    record['captured'] = inventory;
    record['capture'] = '$capture/user';
    record['phase'] = 'captured';
    await progressWrite(journal, record);
    return true;
  }

  Future<void> restoreOriginal(CloudGame game) async {
    final record = await _record(game);
    if (record['phase'] == 'captured') {
      // Do not restore over writes made by an emulator reopened after capture.
      if (!_same(
        await _list(record['tree'] as String, game.layout),
        _inventory(record['captured'], game.layout),
      ))
        throw StateError(
          'MMJ was changed after capture. Close it and finish again.',
        );
      record['phase'] = 'restoring';
      await progressWrite(journal, record);
    }
    if (record['phase'] == 'restoring') {
      await _apply(record, game.layout, 'captured', 'original', 'original');
      record['phase'] = 'restored';
      await progressWrite(journal, record);
    }
    if (record['phase'] != 'restored')
      throw StateError(
        'Capture MMJ progress before restoring its previous saves.',
      );
    // Retain private recovery/capture data, including unsupported MMJ states.
    await progressWrite(
      await progressFile(_directory(record), 'completed.json'),
      record,
    );
    await journal.delete();
  }

  /// Explicit user resolution: do not mutate an uncertain external folder or
  /// upload it as a profile's progress. Original/working/captured files survive.
  Future<void> keepSharedFolder(String server, String profile, int rom) async {
    final record = await progressJson(journal);
    if (record['version'] != 1 ||
        record['server'] != server ||
        record['profile'] != profile ||
        record['rom'] != rom ||
        !RegExp(r'^[a-f0-9]{32}$')
            .hasMatch(record['transaction'] as String? ?? ''))
      throw const FormatException(
        'MMJ recovery identity changed; files were kept.',
      );
    await progressWrite(
      await progressFile(_directory(record), 'kept-shared-folder.json'),
      {
        ...record,
        'resolution': 'user-kept-shared-folder',
        'resolved': DateTime.now().toUtc().toIso8601String(),
      },
    );
    await journal.delete();
  }
}
