import 'dart:convert';
import 'dart:io';

const releaseTargets = {
  'macos-universal': 'zip',
  'windows-x64': 'zip',
  'linux-x64': 'tar.gz',
  'linux-arm64': 'tar.gz',
  'android-universal': 'apk',
};

Future<String> command(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    args,
    environment: environment,
    runInShell: Platform.isWindows,
  );
  Future<String> capture(Stream<List<int>> stream) async {
    final bytes = await stream.fold<List<int>>([], (bytes, chunk) {
      if (bytes.length + chunk.length > 4 * 1024 * 1024) {
        process.kill();
        throw StateError('$executable returned too much diagnostic output.');
      }
      return bytes..addAll(chunk);
    });
    return utf8.decode(bytes, allowMalformed: true).trim();
  }

  final results =
      await Future.wait<Object>([
        process.exitCode,
        capture(process.stdout),
        capture(process.stderr),
      ]).timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          process.kill();
          throw StateError('$executable timed out.');
        },
      );
  final status = results[0] as int;
  if (status != 0) {
    // Do not print command arguments: signing paths/values may be sensitive.
    throw StateError('$executable failed ($status). ${results[2]}');
  }
  return results[1] as String;
}

Future<void> buildCommand(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    args,
    environment: environment,
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  final status = await process.exitCode.timeout(
    const Duration(minutes: 60),
    onTimeout: () {
      process.kill();
      throw StateError('$executable build timed out.');
    },
  );
  if (status != 0) throw StateError('$executable failed ($status).');
}
