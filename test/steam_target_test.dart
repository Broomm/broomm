import 'dart:io';

import 'package:broomm/src/steam/launch_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-steam-target-');
    root = Directory(await root.resolveSymbolicLinks());
  });
  tearDown(() => root.delete(recursive: true));
  test('desktop target preserves spaces and literal shell metacharacters without a shell', () async {
    for (final name in [
      r'Broomm with spaces $ money.exe',
      'Broomm 100% café.exe',
    ]) {
      // File.fromUri constructs a native path. Interpolating / into a Windows
      // root produces a mixed-separator expectation, unlike the canonical path
      // the resolver correctly returns. Exercise that input separately below.
      final file = await File.fromUri(root.uri.resolveUri(Uri(path: name)))
          .writeAsString('fixture');
      if (!Platform.isWindows)
        await Process.run('/bin/chmod', ['u+x', file.path]);
      for (final input in {file.path, '${root.path}/$name'}) {
        final result = await SteamLaunchTarget.resolve(
          executable: input,
          operatingSystem: Platform.isWindows ? 'windows' : 'linux',
        );
        expect(result.executable, file.path);
        expect(result.directory, root.path);
        expect(await File(result.executable).readAsString(), 'fixture');
      }
    }
    for (final value in ['broken\npath', 'broken"path', 'broken\u0000path']) {
      expect(() => SteamLaunchTarget.validate(value), throwsStateError);
    }
  });
  test(
    'macOS resolves the packaged application bundle and rejects naked test executables',
    () async {
      final bundle = Directory('${root.path}/Broomm with spaces.app');
      await Directory('${bundle.path}/Contents/MacOS').create(recursive: true);
      await File('${bundle.path}/Contents/Info.plist').writeAsString('fixture');
      final binary = await File('${bundle.path}/Contents/MacOS/broomm')
          .writeAsString('fixture');
      await Process.run('/bin/chmod', ['u+x', binary.path]);
      final target = await SteamLaunchTarget.resolve(
        executable: binary.path,
        operatingSystem: 'macos',
      );
      expect(target.executable, bundle.path);
      expect(target.directory, root.path);
      final naked = await binary.copy('${root.path}/broomm');
      await Process.run('/bin/chmod', ['u+x', naked.path]);
      await expectLater(
        SteamLaunchTarget.resolve(
          executable: naked.path,
          operatingSystem: 'macos',
        ),
        throwsStateError,
      );
    },
    skip: Platform.isWindows
        ? 'Native bundle permissions checked on macOS and Linux'
        : false,
  );
}
