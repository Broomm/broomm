// Review/pin the native desktop downloads missing hashes in upstream 1.6.3.
// Only the project-managed dependency cache is modified; source stays upstream.
import 'dart:convert';
import 'dart:io';

import '../lib/src/progress/digest.dart';

String digest(String text) =>
    (ProgressDigest.sha256()..add(utf8.encode(text))).finish();

Future<void> main() async {
  final root = Directory.current.resolveSymbolicLinksSync();
  final configFile = File('$root/.dart_tool/package_config.json');
  final config = jsonDecode(await configFile.readAsString()) as Map;
  final entry = (config['packages'] as List).cast<Map>().singleWhere(
    (p) => p['name'] == 'flutter_webrtc',
  );
  final package = Directory.fromUri(configFile.uri.resolve(entry['rootUri']))
      .resolveSymbolicLinksSync();
  final cache = Directory('$root/.tool-cache/pub').resolveSymbolicLinksSync();
  if (!package.startsWith('$cache${Platform.pathSeparator}')) {
    throw StateError('WebRTC must use the project-managed PUB_CACHE.');
  }
  final pins =
      jsonDecode(await File('tool/webrtc_native.json').readAsString()) as Map;
  final target = File('$package/third_party/CMakeLists.txt');
  final lock = await File('$package/third_party/.broomm-prepare.lock')
      .open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.exclusive);
    final original = await target.readAsString();
    final marker = '# Broomm reviewed runtime hashes; flutter_webrtc 1.6.3.';
    if (original.startsWith(marker)) {
      final saved = File('$package/third_party/.broomm-original.cmake');
      if (!await saved.exists() ||
          digest(await saved.readAsString()) != pins['cmake_sha256'] ||
          original != patch(await saved.readAsString(), pins)) {
        throw StateError('The reviewed WebRTC build recipe changed.');
      }
    } else {
      if (digest(original) != pins['cmake_sha256'])
        throw StateError('Unreviewed WebRTC native build recipe.');
      await File('$package/third_party/.broomm-original.cmake')
          .writeAsString(original, flush: true);
      final stage = File('$package/third_party/.broomm-cmake-${pid}.tmp');
      await stage.writeAsString(patch(original, pins), flush: true);
      await stage.rename(target.path);
    }
    stdout.writeln(
      'Verified flutter_webrtc 1.6.3 native download recipe and pinned hashes.',
    );
  } finally {
    await lock.close();
  }
}

String patch(String original, Map pins) {
  final choices = <String>[];
  for (final asset in pins['desktop'] as List) {
    choices.add(
      '${choices.isEmpty ? 'if' : 'elseif'}(LIBWEBRTC_ASSET STREQUAL "${asset['asset']}")\n'
      '  set(BROOMM_ARCHIVE_HASH "${asset['archive_sha256']}")\n'
      '  set(BROOMM_BINARY "${asset['binary']}")\n'
      '  set(BROOMM_BINARY_HASH "${asset['binary_sha256']}")',
    );
  }
  final guard =
      '''
file(LOCK "\${LIBWEBRTC_THIRD_PARTY_DIR}/.broomm-native.lock" GUARD FILE TIMEOUT 30)
${choices.join('\n')}
else()
  message(FATAL_ERROR "WebRTC runtime architecture has no reviewed Broomm pin")
endif()
if(EXISTS "\${ZIPFILE}")
  file(SHA256 "\${ZIPFILE}" BROOMM_FOUND_HASH)
  if(NOT BROOMM_FOUND_HASH STREQUAL BROOMM_ARCHIVE_HASH)
    message(FATAL_ERROR "WebRTC cache hash mismatch; contents retained for inspection")
  endif()
endif()
''';
  var value = original.replaceFirst(
    'if(NOT EXISTS "\${ZIPFILE}")',
    '$guard\nif(NOT EXISTS "\${ZIPFILE}")',
  );
  value = value.replaceFirst(
    '  file(DOWNLOAD "\${DOWNLOAD_URL}"',
    '''  if(EXISTS "\${ZIPFILE}.incoming")
    message(FATAL_ERROR "Interrupted WebRTC download retained; inspect its private cache")
  endif()
  file(DOWNLOAD "\${DOWNLOAD_URL}"''',
  );
  value = value.replaceFirst(
    '      \${ZIPFILE}\n',
    '      "\${ZIPFILE}.incoming"\n      EXPECTED_HASH "SHA256=\${BROOMM_ARCHIVE_HASH}"\n      TIMEOUT 180\n',
  );
  value = value.replaceFirst(
    '  _libwebrtc_extract_and_normalize("\${ZIPFILE}"',
    '  file(RENAME "\${ZIPFILE}.incoming" "\${ZIPFILE}" NO_REPLACE)\n  _libwebrtc_extract_and_normalize("\${ZIPFILE}"',
  );
  return '''# Broomm reviewed runtime hashes; flutter_webrtc 1.6.3.
$value
file(SHA256 "\${LIBWEBRTC_THIRD_PARTY_DIR}/libwebrtc/lib/\${BROOMM_BINARY}" BROOMM_FOUND_BINARY_HASH)
if(NOT BROOMM_FOUND_BINARY_HASH STREQUAL BROOMM_BINARY_HASH)
  message(FATAL_ERROR "WebRTC runtime binary hash mismatch; contents retained")
endif()
''';
}
