import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../lib/src/progress/digest.dart';
import '../../lib/src/progress/files.dart';
import '../../lib/src/progress/zip.dart';
import '../../lib/src/romm/transfer.dart';
import '../../lib/src/setup/archive.dart' show extractSetupTar;

const mesenRevision = '0102910c39ad1a62bc3f784466f3f67ca9eae335';
const mesenSourceHash =
    '360f97e907ada9b8e28a95652aa1d07656340e1d84ff868312745a566b250e01';
const mesenVendor = 'vendor/android/mesen/0.9.9-0102910';
const mesenNdk = '29.0.14206865';
const mesenAbis = {
  'arm64-v8a': (2, 183),
  'armeabi-v7a': (1, 40),
  'x86': (1, 3),
  'x86_64': (2, 62),
};

/// Reuse production's inspect-before-write tar boundary. The complete source
/// archive is fixed, bounded and verified before decompression or extraction.
Future<Directory> prepareMesenSource(File archive, Directory stage) async {
  if (await FileSystemEntity.type(archive.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await archive.length() != 886080 ||
      await progressFileHash(archive) != mesenSourceHash) {
    throw const FormatException('Mesen source archive identity mismatch.');
  }
  if (await progressExists(stage.path))
    throw StateError(
      'Mesen staging already exists; preserve it for inspection.',
    );
  await progressDirectory(stage.parent);
  await stage.create();
  final tar = File('${stage.path}/source.tar');
  final sink = await tar.open(mode: FileMode.writeOnly);
  try {
    var bytes = 0;
    await for (final chunk in archive.openRead().transform(gzip.decoder)) {
      bytes += chunk.length;
      if (bytes > 8 * 1024 * 1024)
        throw const FormatException('Mesen source expands beyond 8 MiB.');
      await sink.writeFrom(chunk);
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  final extracted = Directory('${stage.path}/extracted');
  await extractSetupTar(
    tar,
    extracted,
    'Mesen-$mesenRevision',
    DownloadCancellation(),
  );
  final source = Directory('${extracted.path}/Mesen-$mesenRevision');
  final manifest = await mesenSourceManifest(source);
  if (manifest.length != 691 ||
      manifest.values.fold<int>(0, (n, m) => n + (m['bytes'] as int)) !=
          5395411) {
    throw const FormatException(
      'Mesen source tree differs from reviewed input.',
    );
  }
  await tar.delete();
  return source;
}

Future<Map<String, Map<String, Object>>> mesenSourceManifest(
  Directory source,
) async {
  final entries = await source
      .list(recursive: true, followLinks: false)
      .toList();
  entries.sort((a, b) => a.path.compareTo(b.path));
  final result = <String, Map<String, Object>>{};
  for (final entry in entries) {
    if (entry is Directory) continue;
    if (entry is! File)
      throw const FormatException('Mesen source must contain no links.');
    final relative = entry.path
        .substring(source.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    result[relative] = {
      'bytes': await entry.length(),
      'sha256': await progressFileHash(entry),
    };
  }
  return result;
}

void validateMesenElf(Uint8List bytes, String abi) {
  final expected = mesenAbis[abi];
  if (expected == null ||
      bytes.length < 20 ||
      bytes[0] != 0x7f ||
      bytes[1] != 69 ||
      bytes[2] != 76 ||
      bytes[3] != 70 ||
      bytes[4] != expected.$1 ||
      bytes[5] != 1 ||
      ByteData.sublistView(bytes).getUint16(16, Endian.little) != 3 ||
      ByteData.sublistView(bytes).getUint16(18, Endian.little) != expected.$2) {
    throw const FormatException('Mesen output has the wrong ELF identity.');
  }
}

Future<String> _capture(String executable, List<String> arguments) async {
  final result = await Process.run(
    executable,
    arguments,
  ).timeout(const Duration(seconds: 30));
  if (result.exitCode != 0)
    throw StateError('$executable failed: ${result.stderr}');
  return result.stdout as String;
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 ||
      !(mesenAbis.containsKey(arguments.single) ||
          arguments.single == '--inspect-source')) {
    stderr.writeln(
      'Usage: devbox run -- dart tool/android/build_mesen.dart '
      '<arm64-v8a|armeabi-v7a|x86|x86_64|--inspect-source>\n'
      'Builds only the fixed Mesen source with the project-staged NDK. '
      'Never downloads tools or changes global SDK settings.',
    );
    exitCode = 64;
    return;
  }
  final project = Directory.current.absolute;
  final cache = Directory('${project.path}/.tool-cache/android/mesen');
  await progressDirectory(cache);
  final lock = await File('${cache.path}/build.lock')
      .open(mode: FileMode.append);
  await lock.lock(FileLock.exclusive);
  try {
    final stage = Directory('${cache.path}/build-${progressNonce()}');
    final source = await prepareMesenSource(
      File('${project.path}/$mesenVendor/source.tar.gz'),
      stage,
    );
    final inputs = await mesenSourceManifest(source);
    if (arguments.single == '--inspect-source') {
      stdout.writeln(
        'Verified Mesen source: ${inputs.length} files, no links.',
      );
      await stage.delete(recursive: true);
      return;
    }
    if (!Platform.isLinux)
      throw UnsupportedError('The reviewed Mesen build host is Linux x86_64.');
    final ndk = '${project.path}/.tool-cache/android/sdk/ndk/$mesenNdk';
    final properties = await File('$ndk/source.properties').readAsString();
    if (!RegExp(
      r'^Pkg\.Revision\s*=\s*29\.0\.14206865\s*$',
      multiLine: true,
    ).hasMatch(properties)) {
      throw StateError('The project-staged NDK revision differs.');
    }
    final abi = arguments.single;
    final output = Directory('${project.path}/build/android-mesen/$abi');
    if (await progressExists(output.path))
      throw StateError('Mesen output exists; preserve it before rebuilding.');
    await progressDirectory(output.parent);
    await output.create();
    final toolchain = '$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin';
    final toolHashes = <String, String>{};
    for (final path in [
      'source.properties',
      'ndk-build',
      'build/core/build-local.mk',
      'toolchains/llvm/prebuilt/linux-x86_64/bin/clang',
      'toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf',
    ]) {
      toolHashes[path] = await progressFileHash(File('$ndk/$path'));
    }
    final commands = [
      '-C', '${source.path}/Libretro', '-j2', 'V=1',
      'APP_BUILD_SCRIPT=${source.path}/Libretro/jni/Android.mk',
      'NDK_APPLICATION_MK=${source.path}/Libretro/jni/Application.mk',
      'NDK_PROJECT_PATH=${source.path}/Libretro',
      'NDK_OUT=${stage.path}/obj', 'NDK_LIBS_OUT=${stage.path}/libs',
      'APP_ABI=$abi', 'APP_PLATFORM=android-24', 'NDK_DEBUG=0',
      // Do not let upstream's git command discover Broomm's parent checkout.
      'GIT_VERSION=${mesenRevision.substring(0, 7)}',
    ];
    final recipe = {
      'schema': 1,
      'core': 'mesen',
      'source_revision': mesenRevision,
      'source_archive_sha256': mesenSourceHash,
      'source_files': inputs,
      'builder_revision': await _capture('git', ['rev-parse', 'HEAD']),
      'builder_sha256': await progressFileHash(
        File('${project.path}/tool/android/build_mesen.dart'),
      ),
      'ndk_revision': mesenNdk,
      'tool_hashes': toolHashes,
      'clang_version': await _capture('$toolchain/clang', ['--version']),
      'host': await _capture('uname', ['-a']),
      'abi': abi,
      'command': ['$ndk/ndk-build', ...commands],
      'started_utc': DateTime.now().toUtc().toIso8601String(),
    };
    final receipt = File('${output.path}/build.json');
    Future<void> record() => receipt.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(recipe)}\n',
      flush: true,
    );
    await record();
    final log = File('${output.path}/build.log').openWrite();
    final child = await Process.start('$ndk/ndk-build', commands);
    var logBytes = 0;
    Future<void> pipe(Stream<List<int>> stream) async {
      await for (final bytes in stream) {
        logBytes += bytes.length;
        if (logBytes > 64 * 1024 * 1024) {
          child.kill(ProcessSignal.sigkill);
          throw StateError('Mesen build diagnostics exceed 64 MiB.');
        }
        log.add(bytes);
      }
    }

    late int code;
    try {
      final completed = await Future.wait<Object>([
        child.exitCode,
        pipe(child.stdout).then((_) => 0),
        pipe(child.stderr).then((_) => 0),
      ]).timeout(const Duration(minutes: 35));
      code = completed.first as int;
    } on TimeoutException {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
      rethrow;
    } finally {
      await log.flush();
      await log.close();
    }
    recipe['exit_code'] = code;
    recipe['finished_utc'] = DateTime.now().toUtc().toIso8601String();
    await record();
    if (code != 0)
      throw StateError('Mesen build failed ($code); full build.log retained.');
    if (jsonEncode(await mesenSourceManifest(source)) != jsonEncode(inputs))
      throw StateError(
        'Mesen build modified source inputs; output not accepted.',
      );
    final library = File('${stage.path}/libs/$abi/libretro.so');
    final handle = await library.open();
    try {
      validateMesenElf(await handle.read(20), abi);
    } finally {
      await handle.close();
    }
    final dynamic = await _capture('$toolchain/llvm-readelf', [
      '--dynamic',
      '--notes',
      library.path,
    ]);
    await File('${output.path}/elf.txt').writeAsString(dynamic);
    final needed = RegExp(r'\(NEEDED\).*\[([^\]]+)\]')
        .allMatches(dynamic)
        .map((m) => m[1]!)
        .toList();
    if (needed.isEmpty ||
        needed.any(
          (n) => !{'libc.so', 'libm.so', 'libdl.so', 'liblog.so'}.contains(n),
        ))
      throw StateError(
        'Mesen output has an unreviewed native dependency: $needed',
      );
    final payload = File('${output.path}/mesen_libretro_android.so');
    await library.copy(payload.path);
    final zip = File('${payload.path}.zip');
    await ProgressZip.write(zip, output, ['mesen_libretro_android.so']);
    final packaged = await ProgressZip.read(zip);
    recipe['output'] = {
      'payload_bytes': await payload.length(),
      'payload_sha256': await progressFileHash(payload),
      'archive_bytes': await zip.length(),
      'archive_sha256': await progressFileHash(zip),
      'archive_method': packaged.entries.single.method,
      'needed': needed,
    };
    await record();
    stdout.writeln(
      'Built Mesen $abi; recipe, logs, ELF and hashes: ${output.path}',
    );
  } finally {
    await lock.unlock();
    await lock.close();
  }
}
