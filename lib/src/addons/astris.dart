import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../astris_process.dart';
import '../managed_emulators.dart' show copyTree, ownedDirectory;
import '../romm/transfer.dart';
import '../switch_content.dart';
import 'files.dart';
import 'package_import.dart';

/// Astris's own pinned content API produces its native selection records.
/// Only private staging is writable; publication/ownership remains in Dart.
Future<SwitchPackages> inspectAstrisPackages(
  String executable,
  String base,
  Directory packages,
  Directory stage,
  Directory profile,
  Directory data,
  DownloadCancellation cancellation,
) async {
  stage = Directory(await stage.resolveSymbolicLinks());
  final root = stage.path, user = Directory('${stage.path}/user');
  for (final p in ['home', 'config', 'cache', 'data', 'tmp', 'user/system'])
    await ownedDirectory(Directory('$root/$p'));
  final origin = Directory('${profile.path}/user');
  for (final key in ['prod.keys', 'title.keys']) {
    final file = await addonFile(origin, 'system/$key');
    await copyTree(file.path, '${user.path}/system/$key', cancellation);
  }
  final key = await switchHeaderKey(File('${user.path}/system/prod.keys'));
  late final String title;
  try {
    title = await switchBaseIdentity(File(base), key);
  } finally {
    key.fillRange(0, key.length, 0);
  }
  final inputs = <String>[];
  await for (final item in packages.list(followLinks: false)) {
    if (item is! File || !item.path.endsWith('.nsp'))
      throw const FormatException('Astris packages must be owned NSP files.');
    inputs.add(await item.resolveSymbolicLinks());
  }
  inputs.sort();
  if (inputs.length > 512)
    throw const FormatException('Too many Astris packages.');
  final known = <String>{...inputs};
  for (final kind in ['updates', 'dlc']) {
    final path = 'games/$title/$kind.json';
    if (!await addonExists('${origin.path}/$path')) continue;
    final file = await addonFile(origin, path);
    if (await file.length() > 12 * 1024 * 1024)
      throw const FormatException('Astris content metadata exceeds limits.');
    final value = jsonDecode(await file.readAsString());
    if (kind == 'updates' && value is Map && value['paths'] is List)
      known.addAll((value['paths'] as List).cast<String>());
    if (kind == 'dlc' && value is List)
      known.addAll(value.map((v) => (v as Map)['path'] as String));
    await copyTree(
      file.path,
      (await addonFile(user, path, createParents: true)).path,
      cancellation,
    );
  }
  final request = File('$root/inspection-request.json');
  await request.writeAsString(jsonEncode(inputs), flush: true);
  final bundled =
      '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/native';
  final native = await File('$bundled/broomm-astris.dylib').exists()
      ? bundled
      : '${Directory.current.path}/build/native';
  final writer = '${await data.resolveSymbolicLinks()}/writer.lock';
  final child = await AstrisProcess.start(
    executable: executable,
    root: root,
    writer: writer,
    guard: '$native/broomm-installer-guard.dylib',
    environment: {
      'HOME': '$root/home',
      'TMPDIR': '$root/tmp',
      'PATH': '/usr/bin:/bin',
      'LANG': 'en_US.UTF-8',
      'DYLD_INSERT_LIBRARIES':
          '$native/broomm-installer-guard.dylib:$native/broomm-astris.dylib',
      'BROOMM_INSTALLER_WRITER_LOCK': writer,
      'BROOMM_WRITER_LOCK': writer,
      'BROOMM_CONFIGURATION_ROOT': root,
      'BROOMM_CONFIGURATION_SANDBOX':
          '(version 1)(allow default)(deny network*)(deny file-write* (require-all (require-not (subpath ${jsonEncode(root)})) (require-not (subpath ${jsonEncode(await Directory.systemTemp.resolveSymbolicLinks())})) (require-not (literal ${jsonEncode(writer)}))))',
      'BROOMM_ASTRIS_ROOT': root,
      'BROOMM_ASTRIS_USER': user.path,
      'BROOMM_ASTRIS_INSPECT': request.path,
    },
  );
  final diagnostics = File('$root/inspector.log').openWrite();
  var bytes = 0;
  void output(List<int> chunk) {
    if (bytes < 1024 * 1024)
      diagnostics.add(chunk.take(1024 * 1024 - bytes).toList());
    bytes += chunk.length;
  }

  final out = child.stdout.listen(output).asFuture<void>(),
      err = child.stderr.listen(output).asFuture<void>();
  cancellation.abort = () => child.kill(ProcessSignal.sigterm);
  int code;
  try {
    code = await child.exitCode.timeout(const Duration(minutes: 2));
  } finally {
    if (!await child.exitCode
        .then((_) => true)
        .timeout(Duration.zero, onTimeout: () => false)) {
      child.kill(ProcessSignal.sigterm);
      try {
        await child.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode;
      }
    }
    await Future.wait([out, err]);
    await diagnostics.close();
    cancellation.abort = null;
  }
  cancellation.check();
  if (code != 0)
    throw const FormatException(
      'Astris could not finish inspecting these packages. No content was installed.',
    );
  final receipt = await addonFile(stage, 'astris-inspection.json');
  if (await receipt.length() > 12 * 1024 * 1024)
    throw const FormatException('Astris content response exceeds limits.');
  final rows = jsonDecode(await receipt.readAsString()) as List;
  if (rows.length != inputs.length ||
      !Iterable<int>.generate(inputs.length).every(
        (i) =>
            rows[i] is Map &&
            rows[i]['path'] == inputs[i] &&
            rows[i]['title'] == title,
      ))
    throw const FormatException(
      'Astris rejected a package or associated it with another game. No content was installed.',
    );
  final updatesFile = File('${user.path}/games/$title/updates.json'),
      dlcFile = File('${user.path}/games/$title/dlc.json');
  final updates = await addonExists(updatesFile.path)
      ? await addonJson(updatesFile)
      : null;
  final dlc = await addonExists(dlcFile.path)
      ? jsonDecode(
          await (await addonFile(dlcFile.parent, 'dlc.json')).readAsString(),
        ) as List
      : null;
  validateSwitchPackages(title, updates, dlc, known);
  final represented = <String>{
    ...?((updates?['paths'] as List?)?.cast<String>()),
    for (final row in dlc ?? []) (row as Map)['path'] as String,
  };
  if (!represented.containsAll(inputs))
    throw const FormatException(
      'Astris did not register every package. No content was installed.',
    );
  return SwitchPackages(title, updates, dlc);
}
