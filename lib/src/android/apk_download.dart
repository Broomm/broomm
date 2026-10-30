import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../progress/files.dart';

/// Explicit emulator installation only. No polling or unattended upgrades.
class AndroidApkDownload {
  AndroidApkDownload({HttpClient? client}) : client = client ?? HttpClient();
  final HttpClient client;
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    client.close(force: true);
  }

  static const hosts = {
    'api.github.com',
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
    'www.ppsspp.org',
    'buildbot.libretro.com',
    'dl.dolphin-emu.org',
    'git.eden-emu.dev',
    'stable.eden-emu.dev',
  };
  Future<HttpClientResponse> response(Uri uri) async {
    for (var redirects = 0; redirects <= 6; redirects++) {
      if (cancelled) throw StateError('Installation download cancelled.');
      if (uri.scheme != 'https' ||
          !hosts.contains(uri.host) ||
          uri.userInfo.isNotEmpty)
        throw const FormatException('Unrecognized emulator download source');
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 30));
      request.followRedirects = false;
      request.headers.set('User-Agent', 'Broomm');
      final reply = await request.close().timeout(const Duration(seconds: 45));
      if ([301, 302, 303, 307, 308].contains(reply.statusCode)) {
        final next = reply.headers.value(HttpHeaders.locationHeader);
        await reply.drain<void>().timeout(const Duration(seconds: 15));
        if (next == null)
          throw const FormatException('Missing download redirect');
        uri = uri.resolve(next);
        continue;
      }
      if (reply.statusCode != 200)
        throw HttpException(
          'Official emulator download returned HTTP ${reply.statusCode}.',
        );
      return reply;
    }
    throw const FormatException('Too many emulator download redirects');
  }

  Future<Map<String, dynamic>> release(String repository) async {
    final reply = await response(
      Uri.https('api.github.com', '/repos/$repository/releases/latest'),
    );
    final bytes = <int>[];
    await for (final part in reply.timeout(const Duration(seconds: 45))) {
      bytes.addAll(part);
      if (bytes.length > 2 * 1024 * 1024)
        throw const FormatException('Emulator release response is too large');
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic> ||
        value['draft'] == true ||
        value['prerelease'] == true)
      throw const FormatException('No stable emulator release is available');
    return value;
  }

  /// Asset names are exact per upstream app, not the first APK in a release.
  static Uri githubAsset(String id, Map<String, dynamic> release) {
    final assets = (release['assets'] as List).cast<Map>();
    final candidates = assets.where((a) {
      final name = a['name'] as String;
      return switch (id) {
        'melonds' => name == 'app-gitHub-prod-release.apk',
        'azahar' => RegExp(
          r'^azahar-android-vanilla-[0-9.]+\.apk$',
        ).hasMatch(name),
        'citra-mmj' => RegExp(r'^Citra_MMJ_[0-9]+\.apk$').hasMatch(name),
        // ARMv8.0 is the conservative compatible choice, including ARMv8.2 CPUs.
        'armsx2' => RegExp(
          r'^ARMSX2-.+-legacy-armv8\.0-sdk26\.apk$',
        ).hasMatch(name),
        _ => false,
      };
    }).toList();
    if (candidates.length != 1)
      throw StateError(
        'The official release has no unambiguous supported APK. Use Install APK… or the official download page.',
      );
    final uri = Uri.parse(candidates.single['browser_download_url'] as String);
    if (uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        !uri.path.endsWith('.apk'))
      throw const FormatException('Invalid official APK URL');
    return uri;
  }

  Future<Uri> source(String id, List<String> abis) async {
    final arm64 = abis.contains('arm64-v8a');
    switch (id) {
      case 'retroarch':
        final name = arm64
            ? 'RetroArch_aarch64.apk'
            : abis.contains('armeabi-v7a')
            ? 'RetroArch_ra32.apk'
            : 'RetroArch.apk';
        return Uri.parse(
          'https://buildbot.libretro.com/stable/1.22.2/android/$name',
        );
      case 'ppsspp':
        return Uri.parse('https://www.ppsspp.org/files/1_20_4/ppsspp.apk');
      case 'dolphin':
        return Uri.parse(
          'https://dl.dolphin-emu.org/releases/2609a/dolphin-2609a.apk',
        );
      case 'eden':
        return Uri.parse(
          'https://stable.eden-emu.dev/v0.2.1/Eden-Android-v0.2.1-standard.apk',
        );
      default:
        if (id == 'armsx2' && !arm64)
          throw UnsupportedError('ARMSX2 requires a 64-bit ARM device.');
        final repository = switch (id) {
          'melonds' => 'rafaelvcaetano/melonDS-android',
          'azahar' => 'azahar-emu/azahar',
          'citra-mmj' => 'weihuoya/citra',
          'armsx2' => 'ARMSX2/ARMSX2',
          _ => throw UnsupportedError(
            'Use this emulator’s official store/download page.',
          ),
        };
        return githubAsset(id, await release(repository));
    }
  }

  Future<File> download(
    Directory data,
    Uri uri,
    void Function(int, int?) progress,
  ) async {
    final file = await progressFile(
      data,
      'android/apks/${progressNonce()}.apk',
      createParents: true,
    );
    await file.create(exclusive: true);
    final timer = Timer(const Duration(minutes: 10), cancel);
    final output = await file.open(mode: FileMode.writeOnly);
    var closed = false;
    try {
      final reply = await response(uri), expected = reply.contentLength;
      if (expected > 1024 * 1024 * 1024)
        throw const FormatException('Emulator APK exceeds its size limit');
      var total = 0;
      final clock = Stopwatch()..start();
      await for (final bytes in reply.timeout(const Duration(seconds: 60))) {
        if (cancelled) throw StateError('Installation download cancelled.');
        total += bytes.length;
        if (total > 1024 * 1024 * 1024)
          throw const FormatException('Emulator APK exceeds its size limit');
        await output.writeFrom(bytes);
        if (clock.elapsedMilliseconds >= 200) {
          progress(total, expected < 0 ? null : expected);
          clock.reset();
        }
      }
      if (cancelled || total == 0 || expected >= 0 && expected != total)
        throw const FormatException('The emulator APK download was incomplete');
      await output.flush();
      progress(total, total);
      return file;
    } catch (_) {
      await output.close();
      closed = true;
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      timer.cancel();
      if (!closed) await output.close();
      client.close(force: true);
    }
  }
}
