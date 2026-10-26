import 'dart:io';

class SessionLease {
  SessionLease._(this.file, this.key);
  final RandomAccessFile file;
  final String key;
  bool _released = false;
  bool get active => !_released;
  static final _held = <String>{};
  static Future<SessionLease> acquire(Directory root) async {
    await root.create(recursive: true);
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
        FileSystemEntityType.directory)
      throw const FileSystemException('Invalid Broomm storage directory');
    final key = await root.resolveSymbolicLinks();
    if (!_held.add(key))
      throw StateError(
        'Another Broomm operation owns the game session. Finish it before continuing.',
      );
    RandomAccessFile? file;
    try {
      for (final name in ['session.lock', 'writer.lock']) {
        final type = await FileSystemEntity.type(
          '${root.path}/$name',
          followLinks: false,
        );
        if (type != FileSystemEntityType.file &&
            type != FileSystemEntityType.notFound)
          throw const FileSystemException('Invalid Broomm session lock');
      }
      file = await File('${root.path}/session.lock')
          .open(mode: FileMode.append);
      await file.lock(FileLock.exclusive);
      final writer = await File('${root.path}/writer.lock')
          .open(mode: FileMode.append);
      try {
        await writer.lock(FileLock.exclusive);
        await writer.unlock();
      } finally {
        await writer.close();
      }
      return SessionLease._(file, key);
    } catch (_) {
      await file?.close();
      _held.remove(key);
      throw StateError(
        'A game or emulator setup is still active in Broomm. Close it normally before continuing.',
      );
    }
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await file.close();
    } finally {
      _held.remove(key);
    }
  }
}
