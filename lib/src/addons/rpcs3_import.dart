import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../managed_emulators.dart' show ownedDirectory;
import '../romm/models.dart';
import '../romm/transfer.dart';

/// RPCS3's CLI performs unattended installation only without its GUI main
/// window. Run in fresh staging, never a player profile or system installation.
Future<Directory> installRpcs3Content(
  String executable,
  String input,
  Directory stage,
  DownloadCancellation cancellation, {
  required bool firmware,
  required Directory data,
}) async {
  if (!Platform.isMacOS)
    throw UnsupportedError(
      'RPCS3 native installation is not validated on this host yet.',
    );
  final root = await stage.resolveSymbolicLinks();
  final writer = '${await data.resolveSymbolicLinks()}/writer.lock';
  final bundled =
      '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/native/broomm-installer-guard.dylib';
  final guard = await File(bundled).exists()
      ? bundled
      : '${Directory.current.path}/build/native/broomm-installer-guard.dylib';
  if (!await File(guard).exists())
    throw StateError(
      'The native installer guard is missing. Use a complete Broomm build.',
    );
  final home = '$root/home';
  final user = Directory('$home/Library/Application Support/rpcs3');
  for (final path in [
    user.path,
    '$root/tmp',
    '$root/config',
    '$root/cache',
    '$root/data',
  ])
    await ownedDirectory(Directory(path));
  String quote(String s) =>
      '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  final child = await Process.start(
    '/usr/bin/sandbox-exec',
    [
      '-p',
      '(version 1)(allow default)(deny network*)(deny file-write* (require-all (require-not (subpath ${quote(root)})) (require-not (literal ${quote(writer)}))))',
      '/usr/bin/env',
      'DYLD_INSERT_LIBRARIES=$guard',
      executable,
      '${firmware ? '--installfw' : '--installpkg'}=${File(input).absolute.path}',
      '--headless',
    ],
    workingDirectory: root,
    includeParentEnvironment: false,
    environment: {
      'HOME': home,
      'XDG_CONFIG_HOME': '$root/config',
      'XDG_CACHE_HOME': '$root/cache',
      'XDG_DATA_HOME': '$root/data',
      'TMPDIR': '$root/tmp',
      'PATH': '/usr/bin:/bin',
      'LANG': 'en_US.UTF-8',
      'QT_QPA_PLATFORM': 'offscreen',
      'BROOMM_INSTALLER_WRITER_LOCK': writer,
      'BROOMM_INSTALLER_ABORT_MODE': 'rpcs3-cli-v1',
    },
  );
  final log = File('$root/installer.log').openWrite();
  log.writeln('RPCS3 installer PID: ${child.pid}');
  var size = 0;
  void output(List<int> bytes) {
    if (size < 1024 * 1024) log.add(bytes.take(1024 * 1024 - size).toList());
    size += bytes.length;
  }

  final out = child.stdout.listen(output).asFuture<void>(),
      err = child.stderr.listen(output).asFuture<void>();
  cancellation.abort = () => child.kill(ProcessSignal.sigkill);
  int code;
  try {
    cancellation.check();
    code = await child.exitCode.timeout(const Duration(minutes: 10));
  } on TimeoutException {
    child.kill(ProcessSignal.sigkill);
    await child.exitCode;
    throw const RommFailure(
      'RPCS3 installation timed out. Existing games and progress were kept.',
    );
  } finally {
    cancellation.abort = null;
    await Future.wait([out, err]);
    await log.close();
  }
  cancellation.check();
  if (code != 0) {
    var completed = false;
    final report = File('$root/installer.log').openWrite(mode: FileMode.append);
    report.writeln('Native RPCS3 user directory: ${user.path}');
    if (await user.exists()) {
      await for (final f in user.list(recursive: true, followLinks: false)) {
        if (f is File &&
            (f.path.endsWith('RPCS3.log') ||
                f.path.endsWith('liblv2.sprx') ||
                f.path.endsWith('version.txt')))
          report.writeln(
            'Native output: ${f.path.substring(user.path.length)} (${await f.length()} bytes)',
          );
      }
    }
    await for (final file in stage.list(recursive: true, followLinks: false)) {
      if (file is! File || !file.path.endsWith('RPCS3.log')) continue;
      final size = await file.length();
      final bytes = await file
          .openRead(size > 65536 ? size - 65536 : 0)
          .fold<List<int>>([], (a, b) => a..addAll(b));
      final text = utf8.decode(bytes, allowMalformed: true);
      completed |= firmware
          ? RegExp(r'Successfully installed PS3 firmware version [0-9.]+\.')
                .hasMatch(text)
          : text.contains(
              'Successfully installed ${File(input).absolute.path} (title_id=',
            );
      report.writeln('Native completion checkpoint: $completed');
    }
    await report.close();
    final diagnostics = await File('$root/installer.log').readAsString();
    final teardown =
        (code == -6 ||
            (code == 86 &&
                diagnostics.contains('BROOMM_RPCS3_CLI_ABORT_V1'))) &&
        diagnostics.contains(
          'Emulation object is unavailable (process teardown)',
        );
    if (completed && teardown) {
      // Pinned d08d568d completes installation, then aborts in its uninitialized
      // emulation-object destructor. Accept only that measured post-completion
      // failure, followed by the caller's independent content validation. The
      // opted-in guard converts abort to status 86 without a macOS crash alert;
      // it never converts an arbitrary failed installation to success.
      return user;
    }
    throw RommFailure(
      'RPCS3 could not install this ${firmware ? 'firmware' : 'package'} (status $code). Existing progress was kept.',
    );
  }
  return user;
}

Future<void> retainRpcs3InstallLog(
  Directory stage,
  Directory data, {
  void Function(String)? onProblem,
}) async {
  try {
    final source = File('${stage.path}/installer.log');
    if (!await source.exists()) return;
    final root = Directory('${data.path}/diagnostics');
    await ownedDirectory(root);
    final file = File(
      '${root.path}/rpcs3-install-${DateTime.now().toUtc().microsecondsSinceEpoch}.log',
    );
    await file.create(exclusive: true);
    final size = await source.length();
    final output = file.openWrite();
    try {
      await output.addStream(
        source.openRead(size > 1024 * 1024 ? size - 1024 * 1024 : 0),
      );
      await output.flush();
    } finally {
      await output.close();
    }
    final logs =
        (await root.list(followLinks: false).toList())
            .whereType<File>()
            .where(
              (f) => RegExp(r'/rpcs3-install-[0-9]+\.log$').hasMatch(f.path),
            )
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in logs.skip(10)) await old.delete();
  } catch (_) {
    onProblem?.call(
      'RPCS3 installer diagnostics could not be retained. The installation result is unchanged.',
    );
  }
}
