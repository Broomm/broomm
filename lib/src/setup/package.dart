import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../progress/digest.dart';
import '../progress/files.dart';
import '../romm/transfer.dart';
import 'archive.dart';
import 'dolphin.dart';
import 'astris.dart';

Future<String> _hashSetupFile(String path) =>
    Isolate.run(() => progressFileHash(File(path)));

class SetupPackage {
  const SetupPackage(
    this.url,
    this.sha256,
    this.bytes,
    this.format,
    this.entry,
    this.prepare, {
    this.file,
  });
  factory SetupPackage.fromJson(Map value) {
    if (value.keys.any(
          (k) => !{
            'url',
            'file',
            'sha256',
            'bytes',
            'format',
            'entry',
            'prepare',
          }.contains(k),
        ) ||
        (value['url'] is String) == (value['file'] is String) ||
        value.containsKey('url') && value['url'] is! String ||
        value.containsKey('file') && value['file'] is! String ||
        value.containsKey('prepare') && value['prepare'] is! String ||
        value['sha256'] is! String ||
        value['bytes'] is! int ||
        value['format'] is! String ||
        value['entry'] is! String)
      throw const FormatException('Invalid emulator download recipe.');
    final url = value['url'] == null
            ? null
            : Uri.tryParse(value['url'] as String),
        hash = value['sha256'] as String,
        bytes = value['bytes'] as int,
        format = value['format'] as String,
        entry = value['entry'] as String,
        prepare = value['prepare'] as String? ?? 'none';
    if (value['url'] != null &&
            (url == null ||
                url.scheme != 'https' ||
                url.host.isEmpty ||
                url.port != 443 ||
                url.userInfo.isNotEmpty ||
                url.hasQuery ||
                url.hasFragment ||
                url.toString().length > 4096 ||
                RegExp(r'[\x00-\x20\x7f]').hasMatch(value['url'] as String)) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        bytes < 1 ||
        bytes > 2 * 1024 * 1024 * 1024 ||
        !{'zip', '7z', 'tar.xz', 'tar.gz', 'dmg'}.contains(format) ||
        !{
          'none',
          'macos-adhoc',
          'macos-dolphin',
          'macos-astris',
        }.contains(prepare))
      throw const FormatException(
        'Unsupported or unsafe emulator download recipe.',
      );
    progressRelative(entry);
    if (value['file'] != null) progressRelative(value['file'] as String);
    if (prepare != 'none' && !entry.endsWith('.app'))
      throw const FormatException(
        'Only a reviewed application bundle can be prepared for macOS.',
      );
    return SetupPackage(
      url,
      hash,
      bytes,
      format,
      entry,
      prepare,
      file: value['file'] as String?,
    );
  }
  final Uri? url;
  final String? file;
  final String sha256, format, entry, prepare;
  final int bytes;
  String get reference => 'download:$sha256:$entry';
  bool samePayload(SetupPackage other) =>
      sha256 == other.sha256 &&
      bytes == other.bytes &&
      format == other.format &&
      entry == other.entry &&
      prepare == other.prepare;
}

/// Called under the application's session lease. Completed original archives
/// can be reused; every reuse is freshly hashed. Native extraction has separate
/// private staging, so a cached download never contains a surviving writer.
class SetupDownloads {
  SetupDownloads(this.data, {HttpClient Function()? client})
    : createClient = client ?? HttpClient.new;
  final Directory data;
  final HttpClient Function() createClient;
  Directory get cache => Directory('${data.path}/setup-downloads');

  Future<File> archive(
    SetupPackage package,
    DownloadCancellation cancellation,
    void Function(String, double?) progress, {
    Directory? localRoot,
  }) async {
    cancellation.check();
    if (package.file != null) {
      final base = localRoot ?? Directory('${data.path}/setup-packages');
      final type = await FileSystemEntity.type(base.path, followLinks: false);
      if (type == FileSystemEntityType.notFound)
        throw StateError(
          'The selected offline setup needs its local archive directory. Choose the bundled setup for automatic downloads, or keep the imported archives beside their setup JSON.',
        );
      if (type != FileSystemEntityType.directory)
        throw StateError(
          'The setup package directory is linked or invalid. Its files were kept.',
        );
      final file = await progressFile(base, package.file!);
      if (!await file.exists())
        throw StateError(
          'This pinned build needs the Broomm setup package (${package.file}). Import its setup.json, or place the package under ${data.path}/setup-packages. No installation was changed.',
        );
      progress('Verifying local emulator package…', null);
      if (await file.length() != package.bytes ||
          await _hashSetupFile(file.path) != package.sha256)
        throw StateError(
          'The local emulator package differs from the reviewed build. Nothing was installed.',
        );
      cancellation.check();
      return file;
    }
    await progressDirectory(cache);
    var count = 0;
    await for (final candidate in cache.list(followLinks: false)) {
      if (++count > 4096)
        throw StateError(
          'The emulator download cache needs inspection before more entries can be added.',
        );
      if (candidate is! Directory ||
          !candidate.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last
              .startsWith('.download-'))
        continue;
      Map record;
      try {
        record = await progressJson(File('${candidate.path}/download.json'));
      } catch (_) {
        continue;
      }
      if (record['product'] != 'Broomm setup' ||
          record['format'] != 1 ||
          record['state'] != 'complete' ||
          record['sha256'] != package.sha256 ||
          record['bytes'] != package.bytes)
        continue;
      final file = await progressFile(candidate, 'payload');
      if (!await file.exists() || await file.length() != package.bytes)
        continue;
      progress('Verifying cached download…', null);
      final hash = await _hashSetupFile(file.path);
      cancellation.check();
      if (hash == package.sha256) return file;
      // Keep altered/foreign bytes. They cannot become an installed release.
    }
    final stage = await cache.createTemp('.download-');
    var complete = false;
    final client = createClient()
      ..connectionTimeout = const Duration(seconds: 20);
    void abort() => client.close(force: true);
    cancellation.abort = abort;
    var expired = false;
    final deadline = Timer(const Duration(minutes: 20), () {
      expired = true;
      abort();
    });
    try {
      await progressWrite(File('${stage.path}/download.json'), {
        'product': 'Broomm setup',
        'format': 1,
        'state': 'downloading',
        'sha256': package.sha256,
        'bytes': package.bytes,
      });
      progress('Downloading emulator package…', 0);
      var uri = package.url!;
      HttpClientResponse? response;
      for (var i = 0; i < 6; i++) {
        cancellation.check();
        if (uri.scheme != 'https' ||
            uri.port != 443 ||
            uri.userInfo.isNotEmpty ||
            uri.hasFragment)
          throw const FormatException(
            'The emulator provider redirected to an unsafe address.',
          );
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 30));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'Broomm setup');
        final next = await request.close().timeout(const Duration(seconds: 30));
        if (next.isRedirect) {
          final location = next.headers.value(HttpHeaders.locationHeader);
          await next.take(0).drain<void>();
          if (location == null) break;
          try {
            uri = uri.resolve(location);
          } on FormatException {
            throw const FormatException(
              'The emulator provider returned an invalid redirect address.',
            );
          }
          continue;
        }
        response = next;
        break;
      }
      if (response == null || response.statusCode != 200)
        throw StateError(
          'The reviewed emulator download is unavailable from its provider. Retry later or check Broomm for updated setup recipes. Existing installations were kept.',
        );
      if (response.contentLength >= 0 &&
          response.contentLength != package.bytes)
        throw StateError(
          'The provider package size changed. Nothing was installed.',
        );
      final file = await progressFile(stage, 'payload');
      await file.create(exclusive: true);
      final sink = await file.open(mode: FileMode.writeOnly);
      var received = 0, last = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          cancellation.check();
          received += chunk.length;
          if (received > package.bytes)
            throw StateError('The emulator download exceeds its pinned size.');
          await sink.writeFrom(chunk);
          if (DateTime.now().difference(last).inMilliseconds >= 150 ||
              received == package.bytes) {
            last = DateTime.now();
            progress('Downloading emulator package…', received / package.bytes);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      cancellation.check();
      if (received != package.bytes)
        throw StateError('The emulator download was incomplete. Retry setup.');
      progress('Verifying emulator download…', null);
      final hash = await _hashSetupFile(file.path);
      cancellation.check();
      if (hash != package.sha256)
        throw StateError(
          'Emulator archive checksum mismatch. Nothing was installed.',
        );
      await progressWrite(File('${stage.path}/download.json'), {
        'product': 'Broomm setup',
        'format': 1,
        'state': 'complete',
        'sha256': package.sha256,
        'bytes': package.bytes,
      });
      complete = true;
      return file;
    } catch (error) {
      cancellation.check();
      if (expired)
        throw StateError('The emulator download timed out. Retry setup.');
      if (error is HttpException ||
          error is SocketException ||
          error is TlsException ||
          error is TimeoutException)
        throw StateError(
          'The emulator download connection was interrupted or could not be secured. Check your connection and retry setup. Completed installations were kept.',
        );
      rethrow;
    } finally {
      deadline.cancel();
      if (identical(cancellation.abort, abort)) cancellation.abort = null;
      client.close(force: true);
      if (!complete) await stage.delete(recursive: true);
    }
  }

  Future<String> prepare(
    SetupPackage package,
    Directory working,
    DownloadCancellation cancellation,
    void Function(String, double?) progress, {
    Directory? localRoot,
  }) async {
    final input = await archive(
      package,
      cancellation,
      progress,
      localRoot: localRoot,
    );
    cancellation.check();
    final stage = await working.createTemp('.archive-');
    var stableInput = input;
    if (package.file != null) {
      stableInput = await input.copy('${stage.path}/payload');
      if (await stableInput.length() != package.bytes ||
          await _hashSetupFile(stableInput.path) != package.sha256)
        throw StateError(
          'The local emulator archive changed during preparation. Nothing was installed.',
        );
    }
    progress('Extracting emulator package…', null);
    final path = await extractSetupArchive(
      stableInput,
      package.format,
      package.entry,
      stage,
      cancellation,
    );
    if (package.prepare != 'none') {
      progress('Preparing reviewed macOS application…', null);
      cancellation.check();
      // codesign may spawn an allocator that also writes the application.
      // Finish this bounded operation before honoring Cancel; abnormal teardown
      // keeps staging rather than assuming that every descendant writer exited.
      try {
        if (package.prepare == 'macos-dolphin') {
          await prepareDolphin(Directory(path));
        } else if (package.prepare == 'macos-astris') {
          await prepareAstris(Directory(path));
        } else {
          await setupTool('/usr/bin/codesign', [
            '--force',
            '--deep',
            '--sign',
            '-',
            path,
          ], DownloadCancellation());
        }
      } catch (_) {
        throw const SetupWriterUncertain();
      }
    }
    cancellation.check();
    return path;
  }
}
