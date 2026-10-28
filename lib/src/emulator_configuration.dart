import 'dart:io';

import 'emulators.dart';
import 'managed_emulators.dart' show ownedDirectory;
import 'session.dart';
import 'session_lease.dart';
import 'romm/transfer.dart';
import 'setup/archive.dart';

/// Hands a private no-game application to the OS. There is no retained child,
/// readiness polling, exit watcher or lease after the launch request. Native
/// file locks protect its data independently of Broomm's lifetime.
class EmulatorConfiguration {
  EmulatorConfiguration(this.data, this.project, {this.log});
  final Directory data;
  final String? project;
  final SessionLog? log;

  Future<void> start(Future<ResolvedSession> Function() resolve) async {
    final lease = await SessionLease.acquire(data);
    try {
      if (!Platform.isMacOS)
        throw UnsupportedError(
          'Managed emulator configuration needs a validated native package for this host.',
        );
      final resolved = await resolve();
      final e = resolved.emulator;
      final root = await Directory(e.root).resolveSymbolicLinks();
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
      final base = await data.resolveSymbolicLinks();
      final writer = '$base/writer.lock';
      final coordinator = '$base/session.lock';
      final temp = Directory('$root/tmp');
      await ownedDirectory(temp);
      String quote(String s) =>
          '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
      final environment = {
        'HOME': resolved.home ?? '$root/home',
        'XDG_CONFIG_HOME': '$root/config',
        'XDG_DATA_HOME': '$root/data',
        'XDG_CACHE_HOME': e.cacheDirectory ?? '$root/cache',
        'TMPDIR': temp.path,
        'PATH': '/usr/bin:/bin',
        'LANG': 'en_US.UTF-8',
        'DYLD_INSERT_LIBRARIES': guard,
        'BROOMM_INSTALLER_WRITER_LOCK': writer,
        'BROOMM_CONFIGURATION_SESSION_LOCK': coordinator,
        'BROOMM_CONFIGURATION_ROOT': root,
        'BROOMM_CONFIGURATION_SANDBOX':
            '(version 1)(allow default)(deny file-write* (require-all (require-not (subpath ${quote(root)})) (require-not (literal ${quote(writer)})) (require-not (literal ${quote(coordinator)}))))',
        if (e.name == 'Eden') 'BROOMM_EDEN': '1',
        if (e.name == 'PPSSPP') 'BROOMM_PSP_MEMSTICK': e.user,
      };
      // Preparation is complete. The child takes the same coordinator lock
      // before it can write; a conflicting operation makes startup fail closed.
      await lease.release();
      final bundle = File(e.executable).parent.parent.parent;
      if (bundle.path.endsWith('.app') &&
          await File('${bundle.path}/Contents/Info.plist').exists()) {
        // No -W: open waits only for Launch Services to accept the request.
        // Explicit environment arguments preserve private HOME and the guard;
        // inheriting them through open itself would lose DYLD variables.
        await setupTool('/usr/bin/open', [
          '-n',
          '-a',
          bundle.path,
          for (final entry in environment.entries) ...[
            '--env',
            '${entry.key}=${entry.value}',
          ],
          if (args.isNotEmpty) ...['--args', ...args],
        ], DownloadCancellation());
      } else {
        // The private portable melonDS copy has no bundle metadata.
        await Process.start(
          e.executable,
          args,
          mode: ProcessStartMode.detached,
          workingDirectory: root,
          includeParentEnvironment: false,
          environment: environment,
        );
      }
      log?.write(
        'Requested private ${e.name} configuration; handed off to macOS.',
      );
    } finally {
      await lease.release();
    }
  }
}
