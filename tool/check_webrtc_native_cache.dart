// Native Windows/Linux check after the packaged plugin has downloaded its ZIP.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  if (!Platform.isWindows && !Platform.isLinux)
    throw StateError('Desktop CMake runtime check.');
  final config = File('.dart_tool/package_config.json');
  final entries = (jsonDecode(await config.readAsString())['packages'] as List)
      .cast<Map>();
  final package = Directory.fromUri(
    config.uri.resolve(
      entries.singleWhere((e) => e['name'] == 'flutter_webrtc')['rootUri'],
    ),
  );
  final thirdParty = Directory('${package.path}/third_party');
  final pins = jsonDecode(await File('tool/webrtc_native.json').readAsString());
  final arch = Platform.version.contains('arm64') ? 'arm64' : 'x64';
  final platform = Platform.isWindows ? 'win' : 'linux';
  final pin = (pins['desktop'] as List).cast<Map>().singleWhere(
    (p) => p['asset'] == 'libwebrtc-$platform-$arch-release',
  );
  final sourceZip = File('${thirdParty.path}/downloads/${pin['asset']}.zip');
  if (!await sourceZip.exists())
    throw StateError('Build the native plugin before testing its cache.');
  final root = await Directory.systemTemp.createTemp(
    'broomm-webrtc-integrity-',
  );
  try {
    for (final binary in [false, true]) {
      final fixture = Directory(
        '${root.path}/${binary ? 'binary' : 'archive'}',
      );
      await fixture.create();
      await File('${fixture.path}/CMakeLists.txt').writeAsString('''
cmake_minimum_required(VERSION 3.21)
project(BroommWebRTCIntegrity NONE)
set(CMAKE_SIZEOF_VOID_P 8)
include(third_party/CMakeLists.txt)
''');
      final cache = Directory('${fixture.path}/third_party');
      await Directory('${cache.path}/downloads').create(recursive: true);
      for (final name in ['CMakeLists.txt', 'libwebrtc_version.ini']) {
        await File('${thirdParty.path}/$name').copy('${cache.path}/$name');
      }
      final zip = File('${cache.path}/downloads/${pin['asset']}.zip');
      final target = File('${cache.path}/libwebrtc/lib/${pin['binary']}');
      if (binary) {
        await sourceZip.copy(zip.path);
        await target.parent.create(recursive: true);
        await target.writeAsString('corrupted runtime');
      } else {
        await zip.writeAsString('corrupted archive');
      }
      final result = await Process.run('cmake', [
        '-S',
        fixture.path,
        '-B',
        '${fixture.path}/build',
      ]).timeout(const Duration(seconds: 30));
      if (result.exitCode == 0)
        throw StateError(
          'CMake accepted a corrupted ${binary ? 'binary' : 'archive'}.',
        );
      final diagnostic = '${result.stdout}\n${result.stderr}';
      if (!diagnostic.contains(
        binary ? 'runtime binary hash mismatch' : 'cache hash mismatch',
      )) {
        throw StateError(
          'CMake failed before reaching the integrity check: $diagnostic',
        );
      }
      if (await File('${zip.path}.incoming').exists())
        throw StateError('CMake downloaded over damaged cache state.');
      if (binary
          ? await target.readAsString() != 'corrupted runtime'
          : await zip.readAsString() != 'corrupted archive') {
        throw StateError(
          'CMake replaced the damaged cache instead of refusing it.',
        );
      }
      stdout.writeln(
        'Rejected corrupted ${binary ? 'runtime' : 'archive'} without replacing it.',
      );
    }
  } finally {
    await root.delete(recursive: true);
  }
}
