import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broomm/src/android/apk_download.dart';
import 'package:broomm/src/android/retroarch_core_setup.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/files.dart';

/// Explicit network integration check; never installs a core or launches a game.
/// Run with: devbox run -- dart tool/check_android_jaguar_download.dart
Future<void> main() async {
  final source = jsonDecode(
    await File('vendor/android/virtualjaguar/3.11.0/provenance.json')
        .readAsString(),
  ) as Map;
  final root = await Directory('build/test-results').create(recursive: true);
  final stage = await root.createTemp('android-jaguar-download-');
  final results = <String, Object>{};
  try {
    for (final entry in (source['artifacts'] as Map).entries) {
      final abi = entry.key as String, expected = entry.value as Map;
      final watch = Stopwatch()..start();
      await downloadAndroidRetroCore(
        stage,
        'virtualjaguar',
        abi,
        AndroidApkDownload(),
        progress: (_, _) {},
        publish: (id, hash) async {
          final file = File(
            '${stage.path}/android/virtualjaguar-stage/$id/'
            '${androidRetroCoreFile('virtualjaguar')}',
          );
          final bytes = await file.readAsBytes();
          final header = ByteData.sublistView(bytes);
          if (hash != expected['sha256'] ||
              await progressFileHash(file) != hash ||
              bytes.length != expected['bytes'] ||
              bytes.length < 20 ||
              bytes[0] != 127 ||
              ascii.decode(bytes.sublist(1, 4)) != 'ELF' ||
              bytes[4] != expected['elf_class'] ||
              bytes[5] != 1 ||
              header.getUint16(16, Endian.little) != 3 ||
              header.getUint16(18, Endian.little) != expected['elf_machine']) {
            throw StateError('The verified $abi core differs from provenance.');
          }
          results[abi] = {
            'sha256': hash,
            'bytes': bytes.length,
            'elf_class': bytes[4],
            'elf_machine': header.getUint16(18, Endian.little),
            'elapsed_ms': watch.elapsedMilliseconds,
          };
        },
      );
      stdout.writeln('Verified official Virtual Jaguar 3.11.0 for $abi.');
    }
    final output = File('${root.path}/android-jaguar-${progressNonce()}.json');
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'checked_utc': DateTime.now().toUtc().toIso8601String(), 'source_revision': source['source_revision'], 'artifacts': results, 'effects': 'Only public downloads into private staging; no installation.'})}\n',
      flush: true,
    );
    stdout.writeln('Four-ABI integration receipt: ${output.path}');
  } finally {
    await stage.delete(recursive: true);
  }
}
