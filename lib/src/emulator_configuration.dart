import 'dart:async';
import 'dart:io';

import 'emulators.dart';
import 'managed_emulators.dart' show ownedDirectory;
import 'session.dart';
import 'session_lease.dart';

/// A no-game configuration process shares the ordinary profile and owns its
/// writer lease until native exit. It never prepares game mappings or saves.
class EmulatorConfiguration {
  EmulatorConfiguration(this.data, this.project, {this.log});
  final Directory data;
  final String? project;
  final SessionLog? log;
  Process? _child;
  SessionLease? _lease;
  Future<int>? done;
  int? get pid => _child?.pid;

  Future<void> start(Future<ResolvedSession> Function() resolve) async {
    if (_lease != null) throw StateError('An emulator is already open.');
    _lease = await SessionLease.acquire(data);
    try {
      if (!Platform.isMacOS)
        throw UnsupportedError(
          'Managed emulator configuration needs a validated native package for this host.',
        );
      final resolved = await resolve();
      final e = resolved.emulator,
          root = await Directory(resolved.emulator.root).resolveSymbolicLinks();
      final args = await EmulatorAdapter.forName(e.name)
          .configurationArguments(e);
      final bundled =
          '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/native/broomm-installer-guard.dylib';
      final guard = await File(bundled).exists()
          ? bundled
          : '${project ?? Directory.current.path}/build/native/broomm-installer-guard.dylib';
      if (!await File(guard).exists())
        throw StateError(
          'The native writer guard is missing. Use a complete Broomm build.',
        );
      final writer = '${await data.resolveSymbolicLinks()}/writer.lock';
      final temp = '$root/tmp';
      await ownedDirectory(Directory(temp));
      String quote(String s) =>
          '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
      final child = await Process.start(
        '/usr/bin/sandbox-exec',
        [
          '-p',
          '(version 1)(allow default)(deny file-write* (require-all (require-not (subpath ${quote(root)})) (require-not (subpath ${quote(temp)})) (require-not (literal ${quote(writer)}))))',
          '/usr/bin/env',
          'DYLD_INSERT_LIBRARIES=$guard',
          e.executable,
          ...args,
        ],
        workingDirectory: root,
        includeParentEnvironment: false,
        environment: {
          'HOME': resolved.home ?? '$root/home',
          'XDG_CONFIG_HOME': '$root/config',
          'XDG_DATA_HOME': '$root/data',
          'XDG_CACHE_HOME': e.cacheDirectory ?? '$root/cache',
          'TMPDIR': temp,
          'PATH': '/usr/bin:/bin',
          'LANG': 'en_US.UTF-8',
          'BROOMM_INSTALLER_WRITER_LOCK': writer,
          if (e.name == 'Eden') 'BROOMM_EDEN': '1',
          if (e.name == 'PPSSPP') 'BROOMM_PSP_MEMSTICK': e.user,
        },
      );
      _child = child;
      final out = child.stdout.listen(log?.output ?? (_) {}).asFuture<void>(),
          err = child.stderr.listen(log?.output ?? (_) {}).asFuture<void>();
      done = () async {
        try {
          final code = await child.exitCode;
          await Future.wait([out, err]);
          return code;
        } finally {
          _child = null;
          await _lease?.release();
          _lease = null;
        }
      }();
    } catch (_) {
      await _lease?.release();
      _lease = null;
      rethrow;
    }
  }
}
