import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../progress/files.dart';
import '../progress/zip.dart';
import '../romm/transfer.dart';
import '../linux_runtime.dart' show prepareLinuxBridge;

const setupExpandedLimit = 8 * 1024 * 1024 * 1024;

/// AppImage's own pinned runtime extracts under kernel confinement. Inspect the
/// resulting private tree before it can be copied or published. Links must stay
/// within the application and may never act as write ancestors during copying.
Future<void> validateSetupTree(
  Directory directory,
  DownloadCancellation cancellation,
) async {
  final root = await directory.resolveSymbolicLinks();
  final spellings = <String, String>{};
  var count = 0, bytes = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    cancellation.check();
    final relative = entity.path.substring(directory.path.length + 1);
    progressRelative(relative);
    if (++count > 30000)
      throw const FormatException('Too many files in the emulator package.');
    final parts = relative.split('/');
    for (var i = 1; i <= parts.length; i++) {
      final name = parts.take(i).join('/');
      final old = spellings[name.toLowerCase()];
      if (old != null && old != name)
        throw const FormatException('Colliding emulator package paths.');
      spellings[name.toLowerCase()] = name;
    }
    if (entity is Link) {
      final target = await entity.target();
      if (target.startsWith('/') ||
          target.contains('\\') ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(target))
        throw const FormatException('Unsafe emulator package link.');
      final resolved = await entity.resolveSymbolicLinks();
      if (resolved != root && !resolved.startsWith('$root/'))
        throw const FormatException(
          'Emulator package link escapes its application.',
        );
    } else if (entity is File) {
      bytes += await entity.length();
      if (bytes > setupExpandedLimit)
        throw const FormatException('Expanded emulator archive exceeds 8 GiB.');
    } else if (entity is! Directory) {
      throw const FormatException('Unsupported emulator package file type.');
    }
  }
}

class SetupWriterUncertain implements Exception {
  const SetupWriterUncertain();
  @override
  String toString() =>
      'Archive preparation could not stop or detach safely. Its private staging was kept for recovery; close Broomm before inspecting it.';
}

/// Dart background writers have no inherited native writer lock. Their owner
/// must retain its session lease until process exit if closure is unconfirmed.
class SetupBackgroundWriterUncertain extends SetupWriterUncertain {
  const SetupBackgroundWriterUncertain();
}

/// Only native archive/disk-image primitives live here. Selection, validation,
/// file creation, cancellation and publication remain in Dart.
Future<List<int>> setupTool(
  String executable,
  List<String> arguments,
  DownloadCancellation cancellation, {
  File? output,
  String? workingDirectory,
  Map<String, String>? environment,
  bool supervised = false,
}) async {
  cancellation.check();
  RandomAccessFile? sink;
  var alive = false;
  int? exitCode;
  Timer? killTimer;
  try {
    if (output != null) {
      await output.create(exclusive: true);
      sink = await output.open(mode: FileMode.writeOnly);
    }
    final child = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    alive = true;
    unawaited(
      cancellation.whenCancelled.then((_) {
        if (!alive) return;
        child.kill();
        if (!supervised)
          killTimer = Timer(const Duration(seconds: 1), () {
            if (alive)
              child.kill(
                supervised ? ProcessSignal.sigterm : ProcessSignal.sigkill,
              );
          });
      }),
    );
    final stdout = <int>[], stderr = <int>[];
    Future<void> readOutput() async {
      var total = 0;
      try {
        await for (final bytes in child.stdout) {
          total += bytes.length;
          if (total > (sink == null ? 2 * 1024 * 1024 : setupExpandedLimit))
            throw const FormatException(
              'Emulator archive exceeds its size limit.',
            );
          if (sink == null) {
            stdout.addAll(bytes);
          } else {
            await sink.writeFrom(bytes);
          }
        }
      } catch (_) {
        if (alive)
          child.kill(
            supervised ? ProcessSignal.sigterm : ProcessSignal.sigkill,
          );
        rethrow;
      }
    }

    Future<void> readError() async {
      await for (final bytes in child.stderr) {
        if (stderr.length + bytes.length > 65536) {
          if (alive)
            child.kill(
              supervised ? ProcessSignal.sigterm : ProcessSignal.sigkill,
            );
          throw const FormatException(
            'Archive tool diagnostics exceeded their limit.',
          );
        }
        stderr.addAll(bytes);
      }
    }

    final work = Future.wait<Object?>([
      child.exitCode.then((code) {
        alive = false;
        exitCode = code;
        return code;
      }),
      readOutput(),
      readError(),
    ]);
    late List<Object?> result;
    try {
      result = await work.timeout(const Duration(minutes: 3));
    } on TimeoutException {
      if (alive)
        child.kill(supervised ? ProcessSignal.sigterm : ProcessSignal.sigkill);
      try {
        await work.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        throw const SetupWriterUncertain();
      }
      throw StateError(
        'Emulator archive preparation timed out. Nothing was installed.',
      );
    } catch (_) {
      if (supervised && (exitCode == null || exitCode! < 0))
        throw const SetupWriterUncertain();
      rethrow;
    }
    if (supervised && (exitCode == null || exitCode! < 0))
      throw const SetupWriterUncertain();
    cancellation.check();
    if (result.first != 0) {
      final detail = utf8
          .decode(stderr, allowMalformed: true)
          .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
          .trim();
      throw StateError(
        'Emulator archive preparation failed${detail.isEmpty ? '.' : ': ${detail.substring(0, detail.length.clamp(0, 500))}'}',
      );
    }
    await sink?.flush();
    return stdout;
  } finally {
    alive = false;
    killTimer?.cancel();
    await sink?.close();
  }
}

/// Convert through macOS's built-in libarchive CLI without extracting to the
/// filesystem. A bounded USTAR stream is then inspected completely in Dart.
Future<String> extractSetupArchive(
  File archive,
  String format,
  String entry,
  Directory stage,
  DownloadCancellation cancellation,
) async {
  if (Platform.isLinux) {
    cancellation.check();
    if (format == 'appimage' || format == 'appimage-zip') {
      stage = Directory(await stage.resolveSymbolicLinks());
      var image = archive;
      if (format == 'appimage-zip') {
        final zip = await ProgressZip.read(
          archive,
          maxBytes: 2 * 1024 * 1024 * 1024,
          maxEntryBytes: 2 * 1024 * 1024 * 1024,
        );
        final nested = Directory('${stage.path}/image');
        await zip.extract(nested, check: cancellation.check);
        final candidates = await nested
            .list(recursive: true, followLinks: false)
            .where((e) => e is File && e.path.endsWith('.AppImage'))
            .cast<File>()
            .toList();
        if (candidates.length != 1)
          throw const FormatException(
            'Expected one reviewed AppImage in the ZIP package.',
          );
        image = candidates.single;
      }
      final header = await image.open();
      try {
        final bytes = await header.read(20);
        if (bytes.length != 20 ||
            bytes[0] != 0x7f ||
            bytes[1] != 69 ||
            bytes[2] != 76 ||
            bytes[3] != 70 ||
            bytes[4] != 2 ||
            bytes[5] != 1 ||
            bytes[18] != 62 ||
            bytes[19] != 0)
          throw const FormatException(
            'Expected the reviewed Linux x64 AppImage.',
          );
      } finally {
        await header.close();
      }
      final packaged =
          '${File(Platform.resolvedExecutable).parent.path}/lib/broomm-native-run';
      final runner = await File(packaged).exists()
          ? packaged
          : '${Directory.current.path}/build/native/broomm-native-run';
      if (!await File(runner).exists())
        throw StateError(
          'The Linux package adapter is missing. Use a complete Broomm build.',
        );
      await setupTool('/bin/chmod', ['u+x', image.absolute.path], cancellation);
      final destination = Directory('${stage.path}/extracted');
      await destination.create();
      final privateRunner = await prepareLinuxBridge(
        runner,
        stage.absolute.path,
        runner: true,
      );
      await setupTool(
        '${stage.absolute.path}/${privateRunner.substring(2)}',
        [
          destination.path,
          destination.path,
          image.absolute.path,
          '--appimage-extract',
        ],
        cancellation,
        workingDirectory: destination.path,
        supervised: true,
        environment: {'TMPDIR': destination.path},
      );
      progressRelative(entry);
      final selected = Directory('${destination.path}/$entry');
      if (await FileSystemEntity.type(selected.path, followLinks: false) !=
          FileSystemEntityType.directory)
        throw const FormatException(
          'The AppImage did not produce its expected application directory.',
        );
      await validateSetupTree(selected, cancellation);
      return selected.path;
    }
    if (format == 'tar.gz') {
      final tar = File('${stage.path}/archive.tar');
      final sink = await tar.open(mode: FileMode.writeOnly);
      try {
        var total = 0;
        await for (final bytes in archive.openRead().transform(gzip.decoder)) {
          cancellation.check();
          total += bytes.length;
          if (total > setupExpandedLimit)
            throw const FormatException(
              'Expanded emulator archive exceeds 8 GiB.',
            );
          await sink.writeFrom(bytes);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      final destination = Directory('${stage.path}/extracted');
      await extractSetupTar(tar, destination, entry, cancellation);
      await tar.delete();
      return '${destination.path}/$entry';
    }
    if (format != 'zip')
      throw UnsupportedError(
        'This Linux emulator recipe requires a reviewed ZIP, AppImage or gzip package.',
      );
    progressRelative(entry);
    stage = Directory(await stage.resolveSymbolicLinks());
    final destination = Directory('${stage.path}/extracted');
    final zip = await ProgressZip.read(
      archive,
      maxBytes: 2 * 1024 * 1024 * 1024,
      maxEntryBytes: 2 * 1024 * 1024 * 1024,
    );
    await zip.extract(destination, check: cancellation.check);
    final selected = '${destination.path}/$entry';
    final type = await FileSystemEntity.type(selected, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory)
      throw const FormatException(
        'The Linux package is missing its expected application entry.',
      );
    return selected;
  }
  if (!Platform.isMacOS)
    throw UnsupportedError(
      'This emulator package requires its macOS archive adapter.',
    );
  stage = Directory(await stage.resolveSymbolicLinks());
  progressRelative(entry);
  final tar = File('${stage.path}/archive.tar');
  final destination = Directory('${stage.path}/extracted');
  if (format != 'dmg') {
    await setupTool(
      '/usr/bin/tar',
      ['-cf', '-', '--format=ustar', '@${archive.absolute.path}'],
      cancellation,
      output: tar,
    );
  } else {
    final mount = Directory('${stage.path}/mount');
    await mount.create();
    // An interrupted attachment must never be recursively deleted as a normal
    // staging folder. This marker is also useful after a process interruption.
    final marker = File('${stage.path}/mount-pending');
    await marker.writeAsString(mount.path, flush: true);
    Object? failure;
    try {
      final plist = await setupTool('/usr/bin/hdiutil', [
        'attach',
        '-readonly',
        '-nobrowse',
        '-noautoopen',
        '-plist',
        '-mountpoint',
        mount.absolute.path,
        archive.absolute.path,
      ], cancellation);
      final info = File('${stage.path}/attachment.plist');
      await info.writeAsBytes(plist, flush: true);
      final parsed = jsonDecode(
        utf8.decode(
          await setupTool('/usr/bin/plutil', [
            '-convert',
            'json',
            '-o',
            '-',
            info.path,
          ], cancellation),
        ),
      ) as Map;
      if (!(parsed['system-entities'] as List).any(
        (e) => e is Map && e['mount-point'] == mount.absolute.path,
      ))
        throw StateError(
          'The disk image did not acknowledge its private mount point.',
        );
      var current = mount;
      for (final component in entry.split('/')) {
        current = Directory('${current.path}/$component');
        if (await FileSystemEntity.type(current.path, followLinks: false) !=
            FileSystemEntityType.directory)
          throw StateError(
            'The disk image is missing its expected application directory.',
          );
      }
      await setupTool(
        '/usr/bin/tar',
        [
          '-cf',
          '-',
          '--format=ustar',
          '--no-xattrs',
          '--no-acls',
          '--no-fflags',
          '-C',
          mount.absolute.path,
          entry,
        ],
        cancellation,
        output: tar,
      );
    } catch (e) {
      failure = e;
    }
    try {
      // Cleanup has its own token: Cancel must still let the read-only volume
      // detach before any directory can be disposed.
      await setupTool('/usr/bin/hdiutil', [
        'detach',
        mount.absolute.path,
      ], DownloadCancellation());
      await marker.delete();
    } catch (_) {
      throw const SetupWriterUncertain();
    }
    if (failure != null) throw failure;
  }
  cancellation.check();
  await extractSetupTar(tar, destination, entry, cancellation);
  await tar.delete();
  return '${destination.path}/$entry';
}

class _TarEntry {
  const _TarEntry(
    this.name,
    this.offset,
    this.size,
    this.type,
    this.mode,
    this.link,
  );
  final String name, link;
  final int offset, size, type, mode;
}

/// Inspect everything before creating files. Links are created last, may not be
/// write ancestors, and must resolve inside the selected application.
Future<void> extractSetupTar(
  File tar,
  Directory destination,
  String selected,
  DownloadCancellation cancellation,
) async {
  progressRelative(selected);
  if (await progressExists(destination.path))
    throw StateError('Setup extraction destination already exists.');
  final length = await tar.length();
  if (length > setupExpandedLimit)
    throw const FormatException('Expanded emulator archive exceeds 8 GiB.');
  final input = await tar.open();
  final entries = <_TarEntry>[], seen = <String>{}, parents = <String>{};
  final spelling = <String, String>{};
  var position = 0, count = 0, ended = false;
  try {
    while (position + 512 <= length) {
      cancellation.check();
      await input.setPosition(position);
      final header = await input.read(512);
      if (header.every((b) => b == 0)) {
        final next = await input.read(512);
        ended = next.length == 512 && next.every((b) => b == 0);
        break;
      }
      int octal(int start, int size) {
        final value = ascii
            .decode(header.sublist(start, start + size))
            .replaceAll('\x00', '')
            .trim();
        if (!RegExp(r'^[0-7]+$').hasMatch(value))
          throw const FormatException('Invalid USTAR numeric field.');
        return int.parse(value, radix: 8);
      }

      String text(int start, int size) => utf8.decode(
        header.sublist(start, start + size).takeWhile((b) => b != 0).toList(),
      );
      var sum = 0;
      for (var i = 0; i < 512; i++) {
        sum += i >= 148 && i < 156 ? 32 : header[i];
      }
      if (sum != octal(148, 8) || ++count > 30000)
        throw const FormatException('Invalid or oversized USTAR directory.');
      final prefix = text(345, 155), size = octal(124, 12), type = header[156];
      var name = prefix.isEmpty ? text(0, 100) : '$prefix/${text(0, 100)}';
      while (name.startsWith('./')) {
        name = name.substring(2);
      }
      if (name.endsWith('/')) name = name.substring(0, name.length - 1);
      final next = position + 512 + ((size + 511) ~/ 512) * 512;
      if (size < 0 || next > length)
        throw const FormatException('Truncated emulator archive.');
      // Finder creates this empty marker for a custom bundle icon. It is not
      // executable content; discard only this exact root-level, empty regular
      // file. All other control-character paths and entry types remain invalid.
      if (selected.endsWith('.app') &&
          name == '$selected/Icon\r' &&
          size == 0 &&
          (type == 0 || type == 48)) {
        position = next;
        continue;
      }
      if (name.isNotEmpty && name != '.') {
        progressRelative(name);
        if (name == selected || name.startsWith('$selected/')) {
          final parts = name.split('/');
          for (var i = 1; i <= parts.length; i++) {
            final prefix = parts.take(i).join('/');
            final previous = spelling[prefix.toLowerCase()];
            if (previous != null && previous != prefix)
              throw const FormatException(
                'Colliding emulator archive directories.',
              );
            spelling[prefix.toLowerCase()] = prefix;
          }
          if (!seen.add(name.toLowerCase()) ||
              ![0, 48, 50, 53].contains(type) ||
              (type == 50 || type == 53) && size != 0)
            throw const FormatException(
              'Colliding or unsupported emulator archive entry.',
            );
          for (var i = 1; i < name.split('/').length; i++) {
            parents.add(name.split('/').take(i).join('/').toLowerCase());
          }
          final link = type == 50 ? text(157, 100) : '';
          if (type == 50) {
            if (link.isEmpty ||
                link.startsWith('/') ||
                link.contains('\\') ||
                RegExp(r'[\x00-\x1f\x7f:]').hasMatch(link))
              throw const FormatException('Unsafe emulator archive link.');
            final resolved = name.split('/')..removeLast();
            for (final part in link.split('/')) {
              if (part == '..') {
                if (resolved.isEmpty)
                  throw const FormatException(
                    'Emulator archive link escapes its application.',
                  );
                resolved.removeLast();
              } else if (part.isNotEmpty && part != '.') {
                resolved.add(part);
              }
            }
            final target = resolved.join('/');
            if (target != selected && !target.startsWith('$selected/'))
              throw const FormatException(
                'Emulator archive link escapes its application.',
              );
          }
          entries.add(
            _TarEntry(name, position + 512, size, type, octal(100, 8), link),
          );
        }
      }
      position = next;
    }
  } finally {
    await input.close();
  }
  if (!ended ||
      entries.isEmpty ||
      entries.any(
        (e) => e.type != 53 && parents.contains(e.name.toLowerCase()),
      ))
    throw const FormatException(
      'Incomplete archive, missing application or linked write ancestor.',
    );
  await progressDirectory(destination);
  final executable = <String>[];
  for (final e in entries.where((e) => e.type != 50)) {
    cancellation.check();
    if (e.type == 53) {
      await progressDirectory(Directory('${destination.path}/${e.name}'));
      continue;
    }
    final file = await progressFile(destination, e.name, createParents: true);
    await file.create(exclusive: true);
    final output = await file.open(mode: FileMode.writeOnly);
    try {
      await for (final bytes in tar.openRead(e.offset, e.offset + e.size)) {
        cancellation.check();
        await output.writeFrom(bytes);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    if ((e.mode & 0x49) != 0) executable.add(file.path);
  }
  for (final e in entries.where((e) => e.type == 50)) {
    cancellation.check();
    final file = await progressFile(destination, e.name, createParents: true);
    await Link(file.path).create(e.link);
  }
  final root = '${await destination.resolveSymbolicLinks()}/$selected';
  for (final e in entries.where((e) => e.type == 50)) {
    final resolved = await Link('${destination.path}/${e.name}')
        .resolveSymbolicLinks();
    if (resolved != root && !resolved.startsWith('$root/'))
      throw const FormatException(
        'Extracted emulator link escapes its application.',
      );
  }
  for (var i = 0; i < executable.length; i += 64) {
    await setupTool('/bin/chmod', [
      'u+x',
      ...executable.skip(i).take(64),
    ], cancellation);
  }
}
