// Native macOS adapter smoke check with a unique disposable fixture identity.
import 'dart:io';

Future<void> main() async {
  if (!Platform.isMacOS)
    throw UnsupportedError('macOS native verification only');
  final source = await File('macos/Runner/MainFlutterWindow.swift')
      .readAsString();
  final start = source.indexOf('enum BroommKeychain');
  final directory = await Directory.systemTemp.createTemp(
    'broomm-keychain-check-',
  );
  try {
    final swift = File('${directory.path}/main.swift');
    await swift.writeAsString(
      'import Foundation\nimport Security\nimport LocalAuthentication\n${source.substring(start)}\n' +
          r'''
let args = CommandLine.arguments
let operation = args[1], key = args[2]
if operation == "write" {
  _ = try BroommKeychain.perform(method: "write", key: key, value: "broomm-disposable-fixture")
} else if operation == "verify" {
  guard try BroommKeychain.perform(method: "read", key: key, value: nil) == "broomm-disposable-fixture" else { fatalError("Readback failed") }
} else if operation == "delete" {
  _ = try BroommKeychain.perform(method: "delete", key: key, value: nil)
  guard try BroommKeychain.perform(method: "read", key: key, value: nil) == nil else { fatalError("Deletion failed") }
} else if operation == "invalid" {
  do { _ = try BroommKeychain.perform(method: "write", key: "../../invalid", value: "fixture"); fatalError("Invalid key accepted") } catch {}
}
''',
    );
    final binary = '${directory.path}/check';
    const env = {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'};
    final sdk = await Process.run('/usr/bin/xcrun', [
      '--sdk',
      'macosx',
      '--show-sdk-path',
    ], environment: env);
    if (sdk.exitCode != 0) throw StateError('Approved Apple SDK unavailable');
    final build = await Process.run('/usr/bin/xcrun', [
      'swiftc',
      '-target',
      'arm64-apple-macosx11.0',
      '-sdk',
      (sdk.stdout as String).trim(),
      swift.path,
      '-o',
      binary,
    ], environment: env);
    if (build.exitCode != 0)
      throw StateError('Native adapter compile failed: ${build.stderr}');
    final key = DateTime.now().microsecondsSinceEpoch
        .toRadixString(16)
        .padLeft(32, '0');
    try {
      for (final op in [
        'invalid',
        'write',
        'verify',
        'write',
        'verify',
        'delete',
      ]) {
        final result = await Process.run(binary, [op, key]);
        if (result.exitCode != 0)
          throw StateError('Keychain $op failed: ${result.stderr}');
      }
      stdout.writeln(
        'Keychain write, separate-process restore, update, deletion and invalid identity passed.',
      );
    } finally {
      await Process.run(binary, ['delete', key]);
    }
  } finally {
    await directory.delete(recursive: true);
  }
}
