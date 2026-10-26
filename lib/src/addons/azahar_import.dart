import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../managed_emulators.dart' show ownedDirectory;
import '../romm/models.dart';
import '../romm/transfer.dart';
import 'files.dart';

/// Native --install is proven headless on the shipped macOS pack. Windows
/// builds use a blocking message box and are deliberately not advertised yet.
Future<void> installAzaharCia(
  String executable,
  String cia,
  Directory stage,
  DownloadCancellation cancellation,
) async {
  if (!Platform.isMacOS)
    throw UnsupportedError(
      'Native 3DS add-on import is not validated on this host yet.',
    );
  cancellation.check();
  if (await addonExists(
    '${File(executable).parent.parent.parent.parent.path}/user',
  ))
    throw const RommFailure(
      'The Azahar bundle has adjacent portable data. Remove that untracked portable configuration before using managed add-on installation.',
    );
  final root = await stage.resolveSymbolicLinks();
  final home = '$root/home';
  for (final p in [
    'home/Library/Application Support/Azahar/config',
    'tmp',
    'config',
    'cache',
    'data',
  ]) {
    await ownedDirectory(Directory('$root/$p'));
  }
  await File('$home/Library/Application Support/Azahar/config/qt-config.ini')
      .writeAsString('''
[UI]
firstStart=false
firstStart\\default=false
check_for_update_on_start=false
check_for_update_on_start\\default=false
[Data%20Storage]
use_custom_storage=false
''', flush: true);
  String quote(String s) =>
      '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  final policy =
      '(version 1)(allow default)(deny network*)(deny file-write* (require-not (subpath ${quote(root)})))';
  final child = await Process.start(
    '/usr/bin/sandbox-exec',
    ['-p', policy, executable, '--install', File(cia).absolute.path],
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
      'QT_QPA_PLATFORM': 'cocoa',
      'QT_MAC_DISABLE_FOREGROUND_APPLICATION_TRANSFORM': '1',
    },
  );
  final output = <int>[];
  final stdoutDone = child.stdout.listen((bytes) {
    if (output.length + bytes.length <= 65536) output.addAll(bytes);
  }).asFuture<void>();
  // Drain bounded diagnostics without exposing paths, keys or raw native logs
  // to a notification. Failed imports never reach a player's writable data.
  final stderrDone = child.stderr.drain<void>();
  cancellation.abort = () => child.kill(ProcessSignal.sigkill);
  int code;
  try {
    cancellation.check();
    code = await child.exitCode.timeout(const Duration(minutes: 3));
  } on TimeoutException {
    child.kill(ProcessSignal.sigkill);
    await child.exitCode;
    throw const RommFailure(
      'Azahar add-on installation timed out. Existing games and progress were kept; retry from Options.',
    );
  } finally {
    // If check() threw immediately after spawn, still stop and reap our child.
    if (cancellation.cancelled) {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
    }
    await Future.wait([stdoutDone, stderrDone]);
    cancellation.abort = null;
  }
  cancellation.check();
  if (code != 0 ||
      !utf8
          .decode(output, allowMalformed: true)
          .contains('Installed CIA successfully.'))
    throw RommFailure(
      'Azahar could not install this CIA (status $code). Use a valid decrypted 3DS update/DLC CIA for this game. Existing progress was kept.',
    );
}
