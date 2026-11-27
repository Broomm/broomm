import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cemu.dart';
import 'cemu_process.dart';
import 'cemu_profile.dart';
import 'emulators.dart';
import 'managed_emulators.dart' show ownedDirectory;
import 'progress/digest.dart';
import 'progress/files.dart';
import 'romm/transfer.dart';
import 'session.dart';
import 'session_lease.dart';
import 'setup/linux_identity.dart';

/// Cemu itself reads WUA's compressed title metadata in an isolated no-game
/// run. No archive codec or filename-based save identity is introduced here.
Future<String> inspectCemuArchive({
  required File rom,
  required Directory profile,
  required Directory data,
  required Directory source,
  required String executable,
  required String executableHash,
  required Map inventory,
  required Map<String, String> native,
  required String host,
  required String project,
  SessionLease? owner,
  DownloadCancellation? cancellation,
}) async {
  if (!rom.path.toLowerCase().endsWith('.wua'))
    throw const FormatException(
      'Choose a WUA or a decrypted code/*.rpx Wii U game.',
    );
  final stamp = await linuxFileStamp(rom);
  final canonical = await rom.resolveSymbolicLinks();
  final digest = ProgressDigest.sha256()..add(utf8.encode(canonical));
  final cache = await progressFile(
    profile,
    'cemu-titles/${digest.finish()}.json',
    createParents: true,
  );
  if (await cache.exists()) {
    final saved = await progressJson(cache);
    final old = saved['stamp'];
    if (saved['version'] == 1 &&
        saved['source'] == canonical &&
        old is Map &&
        old.length == stamp.length &&
        stamp.entries.every((e) => old[e.key] == e.value))
      return cemuTitleId(saved['title'] as String? ?? '');
  }
  cancellation?.check();
  if (owner == null ||
      !owner.active ||
      owner.key != await data.resolveSymbolicLinks())
    throw UnsupportedError(
      'Launch this Wii U game once to inspect its native save identity before managing cloud saves.',
    );
  final parent = Directory('${data.path}/cemu-inspections');
  await ownedDirectory(parent);
  final stage = await parent.createTemp('.title-');
  CemuProcess? child;
  var exited = false;
  SessionLog? log;
  try {
    final launcher = await prepareCemuLauncher(
      profile: stage,
      source: source,
      executable: executable,
      executableHash: executableHash,
      inventory: inventory,
      host: host,
    );
    final emulator = PreparedEmulator(
      'Cemu',
      stage.path,
      launcher.$1,
      0,
      null,
      null,
      userDirectory: launcher.$2,
    );
    await const CemuAdapter().settings(emulator);
    final config = File('${emulator.user}/settings.xml');
    await atomicText(
      config.path,
      patchCemuSettings(await readCemuXml(config), {
        'GamePaths': <String, Object>{'Entry': File(canonical).parent.path},
        'open_pad': false,
      }),
    );
    cancellation?.check();
    log = SessionLog('${stage.path}/inspection.log');
    log.write(
      'Inspecting Wii U archive metadata with Cemu; no game is launched.',
    );
    child = await CemuProcess.start(
      resolved: ResolvedSession(emulator, '', executableHash, native),
      dataRoot: data.path,
      project: project,
      arguments: ['--mlc', '${stage.path}/user/mlc01'],
      supervised: true,
    );
    final sessionLog = log;
    child.stdout.listen(sessionLog.output);
    child.stderr.listen(sessionLog.output);
    await child.admit();
    final catalogue = File('${emulator.user}/title_list_cache.xml');
    String? title;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      cancellation?.check();
      if (await catalogue.exists()) {
        final text = await readCemuXml(catalogue);
        // A freshly published, valid but incomplete catalogue can precede the
        // scan's completion. It is not a confirmed absence or an empty save.
        title = cemuCatalogueCandidate(text, canonical);
        if (title != null) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (title == null)
      throw StateError(
        'Cemu could not identify this Wii U archive within the inspection window. No save was selected.',
      );
    await child.command(active: false, quit: true);
    final code = await child.exitCode.timeout(const Duration(seconds: 20));
    exited = true;
    if (code != 0)
      throw StateError(
        'Cemu metadata inspection exited with status $code. No save was selected.',
      );
    if (cemuCatalogueTitle(await readCemuXml(catalogue), canonical) != title)
      throw const FormatException(
        'Cemu title identity changed during inspection.',
      );
    final after = await linuxFileStamp(rom);
    if (!stamp.entries.every((e) => after[e.key] == e.value))
      throw const FormatException(
        'The Wii U archive changed during inspection.',
      );
    cancellation?.check();
    await progressWrite(cache, {
      'version': 1,
      'source': canonical,
      'stamp': stamp,
      'title': title,
    });
    return title;
  } finally {
    if (child != null && !exited) {
      try {
        await child.command(active: false, quit: true);
        await child.exitCode.timeout(const Duration(seconds: 20));
        exited = true;
      } catch (_) {
        owner.retainForUncertainWriter();
        throw StateError(
          'Cemu’s inspection process is still open. Close it normally and restart Broomm; inspection files and local progress were kept at ${stage.path}.',
        );
      }
    }
    await log?.close();
    if (child == null || exited) await stage.delete(recursive: true);
  }
}
