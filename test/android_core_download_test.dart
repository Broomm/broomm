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
    ('mednafen_lynx', '1.24.0-fcdefcf'),
    ('fbneo', '1.0.0.03-20261107'),
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

  test('Jaguar uses exact upstream versioned ABI assets and refuses changed or truncated libraries', () async {
    final data = await Directory.systemTemp.createTemp('broomm-jaguar-');
    addTearDown(() => data.delete(recursive: true));
    for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64']) {
      final client = ApkClient((uri) {
        expect(
          uri,
          Uri.https(
            'github.com',
            '/libretro/virtualjaguar-libretro/releases/download/v3.11.0/virtualjaguar_libretro-android-$abi.so',
          ),
        );
        return ApkReply([127, 69, 76, 70]);
      });
      await expectLater(
        downloadAndroidRetroCore(
          data,
          'virtualjaguar',
          abi,
          AndroidApkDownload(client: client),
          progress: (_, _) {},
          publish: (_, _) async => fail('Unverified core was published.'),
        ),
        throwsFormatException,
      );
      expect(client.closed, true);
    }
    expect(
      await Directory('${data.path}/android/virtualjaguar-stage')
          .list()
          .toList(),
      isEmpty,
    );
  });

  test(
    'Jaguar bounds both declared and streamed raw-library downloads',
    () async {
      final data = await Directory.systemTemp.createTemp('broomm-jaguar-');
      addTearDown(() => data.delete(recursive: true));
      for (final declared in [true, false]) {
        final client = ApkClient(
          (_) => declared
              ? ApkReply([1], length: 3 * 1024 * 1024 + 1)
              : ApkReply(List.filled(3 * 1024 * 1024 + 1, 0), length: -1),
        );
        await expectLater(
          downloadAndroidRetroCore(
            data,
            'virtualjaguar',
            'arm64-v8a',
            AndroidApkDownload(client: client),
            progress: (_, _) {},
            publish: (_, _) async => fail('Oversized core was published.'),
          ),
          throwsFormatException,
        );
        expect(client.closed, true);
      }
      expect(
        await Directory('${data.path}/android/virtualjaguar-stage')
            .list()
            .toList(),
        isEmpty,
      );
    },
  );

  test('cancelled Jaguar transfer removes staging and a fresh attempt verifies independently', () async {
    final data = await Directory.systemTemp.createTemp('broomm-jaguar-');
    addTearDown(() => data.delete(recursive: true));
    final client = ApkClient((_) => ApkReply([127, 69, 76, 70]));
    final download = AndroidApkDownload(client: client);
    await expectLater(
      downloadAndroidRetroCore(
        data,
        'virtualjaguar',
        'arm64-v8a',
        download,
        progress: (_, _) => download.cancel(),
        publish: (_, _) async => fail('Cancelled core was published.'),
      ),
      throwsStateError,
    );
    expect(client.closed, true);
    final next = ApkClient((_) => ApkReply([127, 69, 76, 70]));
    await expectLater(
      downloadAndroidRetroCore(
        data,
        'virtualjaguar',
        'arm64-v8a',
        AndroidApkDownload(client: next),
        progress: (_, _) {},
        publish: (_, _) async => fail('Changed retry was published.'),
      ),
      throwsFormatException,
    );
    expect(next.closed, true);
    expect(
      await Directory('${data.path}/android/virtualjaguar-stage')
          .list()
          .toList(),
      isEmpty,
    );
  });
}
