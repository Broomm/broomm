import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import '../progress/digest.dart';
import '../progress/files.dart';
import 'archive.dart';
import 'helpers.dart';
import 'releases.dart';
import 'transport.dart';

const updateChannel = MethodChannel('app.broomm/updates');

class UpdateLocation {
  const UpdateLocation(this.parent, this.os, {this.target});
  final Directory parent;
  final String os;
  final String? target;
  static Future<UpdateLocation> discover(Directory data) async {
    if (Platform.isAndroid) {
      final path = await updateChannel.invokeMethod<String>('cacheDirectory');
      if (path == null)
        throw const UpdateFailure('Android update storage is unavailable.');
      return UpdateLocation(Directory(path), 'android');
    }
    final executable = File(
      await File(Platform.resolvedExecutable).resolveSymbolicLinks(),
    );
    final dir = Platform.isMacOS
        ? executable.parent.parent.parent
        : executable.parent;
    if (executable.uri.pathSegments.last !=
            (Platform.isWindows ? 'broomm.exe' : 'broomm') ||
        Platform.isMacOS && !dir.path.endsWith('.app') ||
        dir.parent.path == dir.path)
      throw const UpdateFailure(
        'Install an official Broomm release in its own writable folder to enable updates.',
      );
    final actualData = Directory(await data.resolveSymbolicLinks()).uri
        .toString()
        .toLowerCase();
    if (actualData.startsWith(dir.uri.toString().toLowerCase()))
      throw const UpdateFailure(
        'Move Broomm data outside its application installation before updating.',
      );
    return UpdateLocation(
      dir.parent,
      Platform.operatingSystem,
      target: dir.path,
    );
  }
}

/// One stable OS lock plus an in-process guard. The detached helper's exclusive
/// claim fences the brief interval after this process exits and its lock closes.
class UpdateLease {
  UpdateLease._(this.key, this.file);
  static final _held = <String>{};
  final String key;
  final RandomAccessFile file;
  bool closed = false;
  static Future<UpdateLease> acquire(Directory parent) async {
    await progressDirectory(parent);
    final key = await parent.resolveSymbolicLinks();
    if (!_held.add(key))
      throw const UpdateFailure('Another application update is in progress.');
    RandomAccessFile? file;
    try {
      final lock = await progressFile(Directory(key), '.broomm-updates.lock');
      file = await lock.open(mode: FileMode.append);
      await file.lock(FileLock.exclusive, 0, 1);
      if (await progressExists('$key/.broomm-update-active'))
        throw const UpdateFailure(
          'An installer is still active or has recovery files. Check the installation folder before retrying.',
        );
      return UpdateLease._(key, file);
    } catch (_) {
      await file?.close();
      _held.remove(key);
      rethrow;
    }
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    try {
      await file.close();
    } finally {
      _held.remove(key);
    }
  }
}

Future<Map> validateApplicationBundle(
  Directory payload,
  String target, {
  String? version,
  String? sha,
}) async {
  final root = target == 'macos-universal'
      ? Directory('${payload.path}/Contents/Resources')
      : payload;
  final record = await progressJson(File('${root.path}/broomm-release.json'));
  if (record['product'] != 'Broomm' ||
      record['target'] != target ||
      AppVersion.parse(record['version'] as String? ?? '') == null ||
      version != null && record['version'] != version ||
      sha != null && record['sha'] != sha)
    throw const UpdateFailure(
      'The application identity does not match this release.',
    );
  final binary = File(
    '${payload.path}/${target == 'macos-universal'
        ? 'Contents/MacOS/broomm'
        : target == 'windows-x64'
        ? 'broomm.exe'
        : 'broomm'}',
  );
  if (await FileSystemEntity.type(binary.path, followLinks: false) !=
      FileSystemEntityType.file)
    throw const UpdateFailure(
      'The update does not contain the Broomm executable.',
    );
  if (target != 'macos-universal') {
    final listed = record['entries'];
    final allowed =
        listed is List &&
            listed.every(
              (n) => n is String && !n.contains('/') && !n.contains('\\'),
            )
        ? listed.toSet()
        : {
            'broomm',
            'broomm.exe',
            'flutter_windows.dll',
            'lib',
            'data',
            'RUNNING.txt',
            'broomm-release.json',
            'NATIVE-SOURCES.md',
          };
    await for (final e in payload.list(followLinks: false)) {
      if (e is Link ||
          !allowed.contains(
                e.uri.pathSegments.where((s) => s.isNotEmpty).last,
              ) &&
              e.uri.pathSegments.last != '.DS_Store')
        throw const UpdateFailure(
          'The installation contains extra files. Move personal files outside the application folder before updating.',
        );
    }
    if (!await Directory('${payload.path}/data').exists() ||
        target.startsWith('linux-') &&
            !await File('${payload.path}/lib/libflutter_linux_gtk.so')
                .exists() ||
        target == 'windows-x64' &&
            !await File('${payload.path}/flutter_windows.dll').exists())
      throw const UpdateFailure('The application bundle is incomplete.');
  }
  return record;
}

class PreparedAppUpdate {
  PreparedAppUpdate(
    this.stage,
    this.location,
    this.lease, {
    this.payload,
    this.apk,
  });
  final Directory stage;
  final UpdateLocation location;
  final UpdateLease lease;
  final String? payload;
  final File? apk;
  Process? _helper;
  bool handedOff = false;
  Future<void> cancel() async {
    final commit = File('${stage.path}/commit');
    if (await progressExists(commit.path)) await commit.delete();
    await File('${stage.path}/cancel').writeAsString('cancel', flush: true);
  }

  Future<void> discard() async {
    try {
      await cancel();
      // A spawned helper owns its stage until it exits. Never delete its files
      // out from under it, including when startup/exit was cancelled.
      if (_helper == null && !handedOff) await stage.delete(recursive: true);
    } finally {
      await lease.close();
    }
  }

  Future<bool> start() async {
    if (apk != null) {
      final now = DateTime.now();
      await apk!.setLastModified(now);
      await File('${stage.path}/broomm-update.json').setLastModified(now);
      final opened = await updateChannel.invokeMethod<bool>('install', {
        'path': apk!.path,
      });
      if (opened == true) {
        handedOff = true;
        await lease.close();
      }
      return opened == true;
    }
    final claim = File('${location.parent.path}/.broomm-update-active');
    await claim.create(exclusive: true);
    await claim.writeAsString(stage.path, flush: true);
    try {
      final script = File(
        '${stage.path}/${location.os == 'windows' ? 'install.ps1' : 'install.sh'}',
      );
      if (location.os == 'macos')
        await File('${stage.path}/rename.js')
            .writeAsString(macExclusiveRenameScript, flush: true);
      await script.writeAsString(
        location.os == 'windows' ? windowsUpdateHelper : unixUpdateHelper,
        flush: true,
      );
      final arguments = [
        pid.toString(),
        location.target!,
        payload!,
        '${stage.path}/previous',
        stage.path,
        location.os,
        claim.path,
      ];
      final system = Platform.environment['SystemRoot'];
      if (location.os == 'windows' && system == null)
        throw const UpdateFailure(
          'Windows installation tools are unavailable.',
        );
      _helper = await Process.start(
        location.os == 'windows'
            ? '$system/System32/WindowsPowerShell/v1.0/powershell.exe'
            : '/bin/sh',
        [
          if (location.os == 'windows') ...[
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
          ],
          script.path,
          ...arguments,
        ],
        mode: ProcessStartMode.detached,
        workingDirectory: stage.path,
      );
      for (var i = 0; i < 50; i++) {
        if (await File('${stage.path}/ready').exists()) return true;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await cancel();
      throw const UpdateFailure(
        'The installer could not start. Broomm has not been replaced.',
      );
    } catch (_) {
      if (_helper == null &&
          await claim.exists() &&
          await claim.readAsString() == stage.path)
        await claim.delete();
      rethrow;
    }
  }

  Future<void> commit() async {
    await File('${stage.path}/commit').writeAsString('install', flush: true);
    handedOff = true;
  }
}

class ApplicationInstaller {
  ApplicationInstaller({UpdateTransport? transport, this.location})
    : transport = transport ?? UpdateTransport();
  final UpdateTransport transport;
  final UpdateLocation? location;
  void cancel() => transport.cancel();
  Future<PreparedAppUpdate> prepare(
    AppUpdate update,
    Directory data,
    void Function(String, double?) progress,
  ) async {
    final loc = location ?? await UpdateLocation.discover(data);
    if (loc.target != null)
      await validateApplicationBundle(Directory(loc.target!), update.target);
    late final UpdateLease lease;
    try {
      lease = await UpdateLease.acquire(loc.parent);
    } on FileSystemException {
      throw const UpdateFailure(
        'The installation folder is not writable or another Broomm process is updating. Move Broomm to a folder you own.',
      );
    }
    Directory? stage;
    try {
      stage = await loc.parent.createTemp('.broomm-update-');
      await File('${stage.path}/broomm-update.json').writeAsString(
        jsonEncode({
          'product': 'Broomm',
          'format': 1,
          'version': '${update.version}',
          'build_target': update.target,
          'target': loc.target,
          'archive': update.package.name,
        }),
        flush: true,
      );
      progress('Verifying release information…', null);
      final hash = parseUpdateChecksum(
        utf8.decode(await transport.bytes(update.checksum.uri, limit: 16384)),
        update.package.name,
      );
      final record = jsonDecode(
        utf8.decode(await transport.bytes(update.record.uri, limit: 65536)),
      );
      if (record is! Map ||
          record['product'] != 'Broomm' ||
          record['schema_version'] != 1 ||
          record['version'] != '${update.version}' ||
          record['target'] != update.target ||
          record['sha256'] != hash ||
          record['bytes'] != update.package.bytes ||
          record['sha'] is! String ||
          !RegExp(r'^[a-f0-9]{40}$').hasMatch(record['sha'] as String))
        throw const UpdateFailure(
          'The release checksum and build record disagree.',
        );
      final archive = File('${stage.path}/${update.package.name}');
      await transport.download(
        update.package,
        archive,
        (value) => progress('Downloading Broomm ${update.version}…', value),
      );
      transport.check();
      progress('Verifying application download…', null);
      final actual = await Isolate.run(() => progressFileHash(archive));
      if (actual != hash)
        throw const UpdateFailure(
          'Update checksum mismatch. Nothing was installed.',
        );
      transport.check();
      if (loc.os == 'android')
        return PreparedAppUpdate(stage, loc, lease, apk: archive);
      progress('Preparing installation…', null);
      final keep = File('${stage.path}/keep');
      await keep.writeAsString('native-preparation', flush: true);
      final output = Directory('${stage.path}/new'), os = loc.os;
      await Isolate.run(() => extractUpdate(archive, output, os));
      transport.check();
      final payload = Directory(
        '${output.path}${os == 'macos'
            ? '/broomm.app'
            : os == 'linux'
            ? '/bundle'
            : ''}',
      );
      await validateApplicationBundle(
        payload,
        update.target,
        version: '${update.version}',
        sha: record['sha'] as String,
      );
      if (os == 'macos')
        await updateTool('/usr/bin/codesign', [
          '--verify',
          '--deep',
          '--strict',
          payload.path,
        ]);
      if (os == 'linux')
        await updateTool('/bin/chmod', ['u+x', '${payload.path}/broomm']);
      await keep.delete();
      transport.check();
      return PreparedAppUpdate(stage, loc, lease, payload: payload.path);
    } catch (e) {
      try {
        if (stage != null) {
          if (e is UpdateWriterUncertain) {
            await File('${stage.path}/keep')
                .writeAsString('writer-uncertain', flush: true);
          } else {
            await stage.delete(recursive: true);
          }
        }
      } finally {
        await lease.close();
      }
      rethrow;
    } finally {
      transport.close();
    }
  }
}

/// Keep desktop backups/installer evidence. Old, owned stages without recovery
/// evidence and APKs past their renewed grace period are eligible for cleanup.
/// The preparation lock fences independent processes.
Future<({String message, bool problem})?> cleanupApplicationUpdates(
  UpdateLocation location, {
  String? current,
}) async {
  if (!await location.parent.exists()) return null;
  final lease = await UpdateLease.acquire(location.parent);
  ({String message, bool problem})? notice;
  try {
    await for (final e in location.parent.list(followLinks: false)) {
      if (e is! Directory ||
          !e.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last
              .startsWith('.broomm-update-'))
        continue;
      final marker = File('${e.path}/broomm-update.json');
      if (!await marker.exists()) continue;
      final record = await progressJson(marker);
      final version = record['version'] is String
          ? AppVersion.parse(record['version'] as String)
          : null;
      final build = record['build_target'];
      final validTarget = switch (location.os) {
        'macos' => build == 'macos-universal',
        'windows' => build == 'windows-x64',
        'linux' => build == 'linux-x64' || build == 'linux-arm64',
        'android' => build == 'android-universal',
        _ => false,
      };
      if (record['product'] != 'Broomm' ||
          record['format'] != 1 ||
          version == null ||
          record['version'] != '$version' ||
          !validTarget ||
          record['target'] != location.target ||
          record['archive'] != updatePackage('$version', build as String))
        continue;
      if (record['product'] == 'Broomm' &&
          record['format'] == 1 &&
          record['target'] == location.target &&
          current != null &&
          !await progressExists('${e.path}/reported')) {
        final failed = await progressExists('${e.path}/failed');
        final installed =
            record['version'] == current &&
            await progressExists('${e.path}/installed');
        if (failed || installed) {
          notice = (
            message: failed
                ? 'The previous Broomm update could not finish. Your prior installation and data were retained. Retry from Home; installer diagnostics are in the installation folder.'
                : 'Broomm updated to $current. Your library and progress are ready.',
            problem: failed,
          );
          final reported = await progressFile(e, 'reported');
          await reported.writeAsString('reported', flush: true);
        }
      }
      if (record['product'] != 'Broomm' ||
          record['format'] != 1 ||
          DateTime.now().difference((await marker.stat()).modified) <
              const Duration(hours: 24))
        continue;
      if (await Future.wait(
        [
          'ready',
          'commit',
          'previous',
          'install.log',
          'keep',
        ].map((n) => progressExists('${e.path}/$n')),
      ).then((v) => v.any((b) => b)))
        continue;
      await e.delete(recursive: true);
    }
  } finally {
    await lease.close();
  }
  return notice;
}
