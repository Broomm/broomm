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
  ]) {
    test('each versioned $core archive verifies and publishes its reviewed core', () async {
      final vendor = Directory('vendor/android/$core/$version');
      final provenance = jsonDecode(
        await File('${vendor.path}/provenance.json').readAsString(),
      ) as Map;
      final data = await Directory.systemTemp.createTemp('broomm-mgba-');
      try {
        for (final abi in (provenance['archives'] as Map).keys.cast<String>()) {
          final archive = await File(
            '${vendor.path}/$abi/${core}_libretro_android.so.zip',
          ).readAsBytes();
          final client = ApkClient((uri) {
            expect(uri.host, 'raw.githubusercontent.com');
            expect(uri.path, contains('/$version/$abi/'));
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
                '${data.path}/android/$core-stage/$stage/${core}_libretro_android.so',
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
    });
  }
}
