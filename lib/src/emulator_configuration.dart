import 'dart:io';
import 'dart:async';

import 'emulators.dart';
import 'managed_emulators.dart' show ownedDirectory;
import 'session.dart';
import 'session_lease.dart';
import 'romm/transfer.dart';
import 'setup/archive.dart';
import 'linux_runtime.dart';
import 'cemu_process.dart';

/// Hands a private no-game application to the OS. There is no retained child,
/// readiness polling, exit watcher or lease after the launch request. Native
/// file locks protect its data independently of Broomm's lifetime.
class EmulatorConfiguration {
  EmulatorConfiguration(this.data, this.project, {this.log});
  final Directory data;
  final String? project;
  final SessionLog? log;

  Future<void> start(
    Future<ResolvedSession> Function() resolve, {
    String? emulator,
  }) async {
    final lease = await SessionLease.acquire(data);
    try {
      if (emulator == 'Cemu') {
        final resolved = await resolve();
        final arguments = await const CemuAdapter().configurationArguments(
          resolved.emulator,
        );
        final child = await CemuProcess.start(
          resolved: resolved,
          dataRoot: data.path,
          project: project ?? '',
          arguments: arguments,
        );
        child.stdout.listen((bytes) => log?.output(bytes));
        child.stderr.listen((bytes) => log?.output(bytes));
        try {
          await child.admit();
        } catch (_) {
          try {
            await child.command(active: false, quit: true);
            await child.exitCode.timeout(const Duration(seconds: 20));
          } catch (_) {
            lease.retainForUncertainWriter();
          }
          rethrow;
        }
        // The admitted child now holds the stable native writer lock. The
        // independent configuration window can outlive this launcher.
        unawaited(
          child.exitCode.then((code) {
            log?.write('Private Cemu configuration exited with status $code');
          }),
        );
        return;
      }
      if (Platform.isLinux) {
        final resolved = await resolve();
        final e = resolved.emulator;
        final root = await Directory(e.root).resolveSymbolicLinks();
        final name = e.name == 'RetroArch'
            ? 'broomm-retroarch.so'
            : 'broomm-sdl${e.sdlMajor}.so';
        final packaged =
            '${File(Platform.resolvedExecutable).parent.path}/lib/$name';
        final bridge = await File(packaged).exists()
            ? packaged
            : '${project ?? Directory.current.path}/build/native/$name';
        final preload = await prepareLinuxBridge(bridge, root);
        final args = await EmulatorAdapter.forName(e.name)
            .configurationArguments(e);
        final base = await data.resolveSymbolicLinks();
        await lease.release();
        await Process.start(
          linuxLaunchExecutable(e),
          args,
          mode: ProcessStartMode.detached,
          workingDirectory: linuxLaunchDirectory(e),
          environment: {
            'HOME': resolved.home ?? '$root/home',
            'XDG_CONFIG_HOME': '$root/config',
            'XDG_DATA_HOME': '$root/data',
            'XDG_CACHE_HOME': '$root/cache',
            'TMPDIR': '$root/cache',
            'LD_PRELOAD': [
              linuxLaunchPreload(e, preload),
              if ((Platform.environment['LD_PRELOAD'] ?? '').isNotEmpty)
                Platform.environment['LD_PRELOAD']!,
            ].join(':'),
            ...linuxLaunchEnvironment(e),
            'BROOMM_SESSION_EXECUTABLE': await File(linuxLaunchExecutable(e))
                .resolveSymbolicLinks(),
            'BROOMM_CONFIGURATION_ROOT': root,
            'BROOMM_CONFIGURATION_SESSION_LOCK': '$base/session.lock',
            'BROOMM_WRITER_LOCK': '$base/writer.lock',
            'BROOMM_PROBE_LOG': '$root/configuration.log',
          },
        );
        log?.write(
          'Requested independent private ${e.name} configuration on Linux.',
        );
        return;
      }
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
      if (e.name == 'Astris' &&
          !await File('${File(guard).parent.path}/broomm-astris.dylib')
              .exists())
        throw StateError(
          'The Astris preference bridge is missing. Use a complete Broomm build.',
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
        'DYLD_INSERT_LIBRARIES': e.name == 'Astris'
            ? '$guard:${File(guard).parent.path}/broomm-astris.dylib'
            : guard,
        'BROOMM_INSTALLER_WRITER_LOCK': writer,
        'BROOMM_CONFIGURATION_SESSION_LOCK': coordinator,
        'BROOMM_CONFIGURATION_ROOT': root,
        'BROOMM_CONFIGURATION_SANDBOX':
            '(version 1)(allow default)(deny file-write* (require-all (require-not (subpath ${quote(root)})) ${e.name == 'Astris' ? '(require-not (subpath ${quote(await Directory.systemTemp.resolveSymbolicLinks())}))' : ''} (require-not (literal ${quote(writer)})) (require-not (literal ${quote(coordinator)}))))',
        if (e.name == 'Astris') ...{
          'BROOMM_ASTRIS_ROOT': root,
          'BROOMM_ASTRIS_USER': e.user,
          'BROOMM_WRITER_LOCK': writer,
        },
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
