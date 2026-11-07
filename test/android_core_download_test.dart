import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/android/apk_download.dart';
import 'package:broomm/src/android/retroarch_core_setup.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:flutter_test/flutter_test.dart';

import 'android_apk_download_test.dart' show ApkClient, ApkReply;

void main() {
  for (final (core, version) in [
    ('mgba', '0.11-212-7a12d6d'),
    ('snes9x', '1.63-fae2fea'),
    ('gambatte', '0.5.0-netlink-77f2567'),
    ('stella', '8.0-pre-20261107'),
    ('mednafen_pce_fast', '1.31.0.0-2de1ce1'),
    ('genesis_plus_gx', '1.7.4-f27655b'),
    ('picodrive', '2.05-1890c29'),
    ('mupen64plus_next', '3.0-15bada8'),
    ('mesen', '0.9.9-0102910'),
  ]) {
    test(
      'each versioned $core archive verifies and publishes its reviewed core',
      () async {
        final vendor = Directory('vendor/android/$core/$version');
        final provenance = jsonDecode(
          await File('${vendor.path}/provenance.json').readAsString(),
        ) as Map;
        final data = await Directory.systemTemp.createTemp('broomm-mgba-');
        final coreFile =
            provenance['entry'] as String? ?? '${core}_libretro_android.so';
        try {
          for (final abi
              in (provenance['archives'] as Map).keys.cast<String>()) {
            final archive = await File('${vendor.path}/$abi/$coreFile.zip')
                .readAsBytes();
            final client = ApkClient((uri) {
              expect(uri.host, 'raw.githubusercontent.com');
              expect(uri.path, contains('/$version/$abi/'));
              expect(uri.pathSegments.last, '$coreFile.zip');
              expect(uri.path, isNot(contains('/latest/')));
              return ApkReply(archive);
            });
            var publications = 0;
            await downloadAndroidRetroCore(
              data,
              core,
              abi,
              AndroidApkDownload(client: client),
              progress: (_, _) {},
              publish: (stage, hash) async {
                publications++;
                final payload = File(
                  '${data.path}/android/$core-stage/$stage/$coreFile',
                );
                expect(await progressFileHash(payload), hash);
                expect(
                  hash,
                  (provenance['archives'] as Map)[abi]['payload_sha256'],
                );
              },
            );
            expect(publications, 1);
            expect(client.closed, isTrue);
          }
        } finally {
          await data.delete(recursive: true);
        }
      },
    );
  }
}
