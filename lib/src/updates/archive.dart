import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../progress/files.dart';
import '../progress/zip.dart';
import 'releases.dart';

const updateExpandedLimit = 2 * 1024 * 1024 * 1024;

Future<void> updateTool(String executable, List<String> args) async {
  final process = await Process.start(executable, args);
  Future<void> drain(Stream<List<int>> stream) async {
    var bytes = 0;
    await for (final chunk in stream) {
      bytes += chunk.length;
      if (bytes > 1024 * 1024) process.kill();
    }
  }

  final work = Future.wait<Object?>([
    process.exitCode,
    drain(process.stdout),
    drain(process.stderr),
  ]);
  late final List<Object?> result;
  try {
    result = await work.timeout(const Duration(minutes: 3));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    try {
      await work.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const UpdateWriterUncertain();
    }
    throw const UpdateFailure(
      'Update preparation timed out. Nothing was installed.',
    );
  }
  if (result.first != 0)
    throw const UpdateFailure(
      'The downloaded application failed extraction or signature validation. Nothing was installed.',
    );
}

class UpdateWriterUncertain extends UpdateFailure {
  const UpdateWriterUncertain()
    : super(
        'Update preparation could not stop safely. Its recovery files were kept. Restart Broomm before retrying.',
      );
}

/// Extraction stays private. Never write through a link or a colliding path.
Future<void> extractUpdate(File file, Directory output, String os) async {
  if (await progressExists(output.path))
    throw const UpdateFailure('Update staging already exists.');
  if (os == 'linux') {
    await _extractTar(file, output);
    return;
  }
  final zip = await ProgressZip.read(
    file,
    maxBytes: updateExpandedLimit,
    maxEntryBytes: updateExpandedLimit,
    inspectLinks: os == 'macos',
  );
  for (final e in zip.entries) {
    if (os == 'macos' &&
        !e.name.startsWith('broomm.app/') &&
        !e.name.startsWith('__MACOSX/'))
      throw const UpdateFailure('Unexpected file in the macOS update.');
    if (e.symbolicLink) {
      final link = await zip.linkTarget(e);
      final parts = e.name.split('/')..removeLast();
      if (link.isEmpty ||
          link.startsWith('/') ||
          link.contains('\\') ||
          RegExp(r'[\x00-\x1f:]').hasMatch(link))
        throw const UpdateFailure('Unsafe application archive link.');
      for (final part in link.split('/')) {
        if (part == '..') {
          if (parts.length < 2)
            throw const UpdateFailure('Application link escapes its bundle.');
          parts.removeLast();
        } else if (part.isNotEmpty && part != '.') {
          parts.add(part);
        }
      }
      if (parts.first != 'broomm.app')
        throw const UpdateFailure('Application link escapes its bundle.');
    }
  }
  if (os == 'macos') {
    await output.create();
    await updateTool('/usr/bin/ditto', ['-x', '-k', file.path, output.path]);
    final app = Directory('${output.path}/broomm.app');
    final root = await app.resolveSymbolicLinks();
    await for (final e in app.list(recursive: true, followLinks: false)) {
      if (e is Link) {
        final resolved = await e.resolveSymbolicLinks();
        if (!resolved.startsWith('$root/'))
          throw const UpdateFailure(
            'Extracted application link escapes its bundle.',
          );
      }
    }
  } else if (os == 'windows') {
    await zip.extract(output);
  } else {
    throw const UpdateFailure('Unsupported update archive platform.');
  }
}

Future<void> _extractTar(File file, Directory output) async {
  final tar = File('${file.path}.tar');
  await tar.create(exclusive: true);
  final sink = await tar.open(mode: FileMode.writeOnly);
  var expanded = 0;
  try {
    await for (final chunk in file.openRead().transform(gzip.decoder)) {
      expanded += chunk.length;
      if (expanded > updateExpandedLimit)
        throw const UpdateFailure('Update expands beyond its size limit.');
      await sink.writeFrom(chunk);
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  final input = await tar.open();
  final files = <(String, int, int)>[],
      seen = <String>{},
      directories = <String>{};
  var offset = 0, count = 0, bytes = 0;
  try {
    var ended = false;
    while (offset + 512 <= expanded) {
      await input.setPosition(offset);
      final header = await input.read(512);
      if (header.every((b) => b == 0)) {
        ended = true;
        break;
      }
      int octal(int start, int length) {
        final text = ascii
            .decode(header.sublist(start, start + length))
            .replaceAll('\x00', '')
            .trim();
        if (!RegExp(r'^[0-7]+$').hasMatch(text))
          throw const UpdateFailure('Invalid TAR number.');
        return int.parse(text, radix: 8);
      }

      String text(int start, int length) => utf8.decode(
        header.sublist(start, start + length).takeWhile((b) => b != 0).toList(),
      );
      var sum = 0;
      for (var i = 0; i < 512; i++) {
        sum += i >= 148 && i < 156 ? 32 : header[i];
      }
      if (sum != octal(148, 8) || ++count > 4096)
        throw const UpdateFailure('Invalid or oversized TAR directory.');
      final prefix = text(345, 155),
          leaf = text(0, 100),
          type = header[156],
          size = octal(124, 12);
      var name = prefix.isEmpty ? leaf : '$prefix/$leaf';
      if (name.endsWith('/')) name = name.substring(0, name.length - 1);
      progressRelative(name);
      if (name != 'bundle' && !name.startsWith('bundle/') ||
          !seen.add(name.toLowerCase()) ||
          type != 0 && type != 48 && type != 53 ||
          type == 53 && size != 0)
        throw const UpdateFailure('Unsafe or unsupported TAR entry.');
      for (var n = 1; n < name.split('/').length; n++) {
        directories.add(name.split('/').take(n).join('/').toLowerCase());
      }
      if (type != 53) {
        bytes += size;
        if (bytes > updateExpandedLimit)
          throw const UpdateFailure('Update expands beyond its size limit.');
        files.add((name, offset + 512, size));
      }
      offset += 512 + ((size + 511) ~/ 512) * 512;
      if (offset > expanded)
        throw const UpdateFailure('Truncated update archive.');
    }
    if (!ended || files.any((e) => directories.contains(e.$1.toLowerCase())))
      throw const UpdateFailure('Incomplete or colliding TAR archive.');
    await output.create();
    for (final (name, start, size) in files) {
      final dest = await progressFile(output, name, createParents: true);
      await dest.create(exclusive: true);
      final out = await dest.open(mode: FileMode.writeOnly);
      try {
        await for (final chunk in tar.openRead(start, start + size)) {
          await out.writeFrom(chunk);
        }
        await out.flush();
      } finally {
        await out.close();
      }
    }
  } finally {
    await input.close();
    await tar.delete();
  }
}
