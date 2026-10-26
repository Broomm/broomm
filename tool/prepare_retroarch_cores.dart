// Explicit development-cache provisioning. This is never run by the app or
// during ordinary startup, and it never updates an installed managed emulator.
import 'dart:convert';
import 'dart:io';

import '../lib/src/progress/digest.dart';
import '../lib/src/progress/files.dart';
import '../lib/src/progress/zip.dart';

Future<void> main() async {
  final meta = jsonDecode(
    await File('assets/setup/retroarch-cores.json').readAsString(),
  ) as Map;
  final destination = Directory('prototype-data/retroarch/cores');
  await progressDirectory(destination);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    for (final c in (meta['cores'] as List).cast<Map>()) {
      final id = c['id'] as String;
      if (!RegExp(r'^[a-z0-9_]+$').hasMatch(id))
        throw const FormatException('Invalid core ID');
      final target = await progressFile(destination, '${id}_libretro.dylib');
      if (await target.exists()) {
        if (await progressFileHash(target) != c['sha256'])
          throw StateError('$id changed; its existing bytes were kept.');
        stdout.writeln('$id: pinned core already cached');
        continue;
      }
      final url = Uri.parse(c['source_url'] as String);
      if (url.scheme != 'https' || url.host != 'buildbot.libretro.com')
        throw const FormatException('Invalid core provider');
      final stage = await destination.createTemp('.core-download-');
      try {
        final req = await client
            .getUrl(url)
            .timeout(const Duration(seconds: 30));
        req.followRedirects = false;
        final response = await req.close().timeout(const Duration(seconds: 30));
        if (response.statusCode != 200 ||
            response.contentLength > 128 * 1024 * 1024)
          throw HttpException(
            'Core provider returned ${response.statusCode}',
            uri: url,
          );
        final archive = File('${stage.path}/archive.zip'),
            sink = File('${stage.path}/archive.zip').openWrite();
        var bytes = 0;
        try {
          await for (final chunk in response.timeout(
            const Duration(seconds: 30),
          )) {
            bytes += chunk.length;
            if (bytes > 128 * 1024 * 1024)
              throw const FormatException('Core archive exceeds limit');
            sink.add(chunk);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (await progressFileHash(archive) != c['archive_sha256'])
          throw StateError(
            '$id provider archive no longer matches this pinned recipe. Nothing was installed.',
          );
        final zip = await ProgressZip.read(archive);
        if (zip.entries.length != 1 ||
            zip.entries.single.name != '${id}_libretro.dylib')
          throw const FormatException('Unexpected core archive layout');
        final extracted = Directory('${stage.path}/extracted');
        await zip.extract(extracted);
        final binary = File('${extracted.path}/${id}_libretro.dylib');
        if (await progressFileHash(binary) != c['sha256'])
          throw StateError('$id binary fingerprint differs');
        if (await target.exists())
          throw StateError('$id cache changed during preparation');
        await binary.rename(target.path);
        stdout.writeln('$id: pinned macOS arm64 core cached');
      } finally {
        await stage.delete(recursive: true);
      }
    }
  } finally {
    client.close(force: true);
  }
}
