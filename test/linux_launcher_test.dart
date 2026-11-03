@TestOn('linux || mac-os')
library;

import 'dart:io';
import 'dart:convert';

import 'package:broomm/src/linux_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File executable;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-launcher-');
    root = Directory(await root.resolveSymbolicLinks());
    final app = await Directory('${root.path}/App with spaces').create();
    executable = await File('${app.path}/broomm')
        .writeAsString('#!/bin/sh\nexit 0\n');
    expect(
      (await Process.run('/bin/chmod', ['u+x', executable.path])).exitCode,
      0,
    );
    await Directory('${app.path}/data').create();
    await File('assets/branding/broomm-icon.png')
        .copy('${app.path}/data/broomm.png');
  });
  tearDown(() => root.delete(recursive: true));
  LinuxLauncher installer(
    Map<String, String> env, {
    Future<bool> Function()? icon,
  }) => LinuxLauncher(
    enabled: true,
    environment: env,
    executable: executable.path,
    fileIcon: icon ?? () async => true,
  );
  test('explicit install uses XDG user applications and shared branding; repeat refreshes the same launcher', () async {
    final env = {
      'HOME': '${root.path}/home',
      'XDG_DATA_HOME': '${root.path}/custom-data',
    };
    final service = installer(env);
    final first = await service.install();
    expect(
      first.desktopFile,
      '${root.path}/custom-data/applications/$broommDesktopId.desktop',
    );
    expect(await Directory('${root.path}/home').exists(), isFalse);
    final text = await File(first.desktopFile).readAsString();
    expect(
      const LineSplitter()
          .convert(text)
          .where((l) => l.startsWith('Exec='))
          .single,
      contains(executable.path),
    );
    expect(text, contains('Icon=$broommDesktopId\n'));
    expect(
      await File(
        '${root.path}/custom-data/icons/hicolor/512x512/apps/$broommDesktopId.png',
      ).readAsBytes(),
      await File('assets/branding/broomm-icon.png').readAsBytes(),
    );
    final second = await installer(env, icon: () async => false).install();
    expect(second.desktopFile, first.desktopFile);
    expect(second.fileIconApplied, isFalse);
    expect(await File(first.desktopFile).readAsString(), text);
    expect(
      (await Directory(File(first.desktopFile).parent.path).list().toList())
          .whereType<File>()
          .where((f) => f.path.endsWith('.desktop')),
      hasLength(1),
    );
  });
  test('empty and relative XDG values use HOME; missing absolute locations fail without installing', () async {
    for (final xdg in ['', 'relative']) {
      final service = installer({
        'HOME': '${root.path}/$xdg-home',
        'XDG_DATA_HOME': xdg,
      });
      expect(
        (await service.install()).desktopFile,
        '${root.path}/$xdg-home/.local/share/applications/$broommDesktopId.desktop',
      );
    }
    await expectLater(
      installer({'HOME': 'relative'}).install(),
      throwsStateError,
    );
    await expectLater(installer({}).install(), throwsStateError);
  });
  test('foreign launchers and linked icon destinations are preserved, and retry works after the conflict is removed', () async {
    final data = Directory('${root.path}/user-data');
    final apps = await Directory('${data.path}/applications')
        .create(recursive: true);
    final desktop = await File('${apps.path}/$broommDesktopId.desktop')
        .writeAsString('User-owned launcher');
    final service = installer({'XDG_DATA_HOME': data.path});
    await expectLater(service.install(), throwsStateError);
    expect(await desktop.readAsString(), 'User-owned launcher');
    expect(await Directory('${data.path}/icons').exists(), isFalse);
    await desktop.delete();
    final icons = await Directory('${data.path}/icons/hicolor/512x512/apps')
        .create(recursive: true);
    final other = await File('${root.path}/unrelated').writeAsString('Keep');
    final link = await Link('${icons.path}/$broommDesktopId.png')
        .create(other.path);
    await expectLater(service.install(), throwsA(isA<FileSystemException>()));
    expect(await other.readAsString(), 'Keep');
    expect(await desktop.exists(), isFalse);
    await link.delete();
    await service.install();
    expect(await desktop.exists(), isTrue);
  });
  test('another process excludes publication, and the same installer can retry after release', () async {
    final data = Directory('${root.path}/locked-data');
    final apps = await Directory('${data.path}/applications')
        .create(recursive: true);
    final child = await Process.start('dart', [
      'test/support/hold_library_lock.dart',
      '${apps.path}/.$broommDesktopId.install.lock',
    ]);
    final service = installer({'XDG_DATA_HOME': data.path});
    try {
      expect(
        await child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'held',
      );
      await expectLater(service.install(), throwsA(isA<FileSystemException>()));
      expect(
        await File('${apps.path}/$broommDesktopId.desktop').exists(),
        isFalse,
      );
      expect(await Directory('${data.path}/icons').exists(), isFalse);
    } finally {
      child.stdin.writeln('release');
      await child.stdin.close();
      expect(await child.exitCode, 0);
    }
    expect(await File((await service.install()).desktopFile).exists(), isTrue);
  });
  test(
    'unsupported desktop executable paths fail before publication',
    () async {
      for (final character in ['=', '%']) {
        final binary = await executable.copy(
          '${executable.parent.path}/broomm${character}name',
        );
        await Process.run('/bin/chmod', ['u+x', binary.path]);
        final data = Directory('${root.path}/unsupported-data');
        final service = LinuxLauncher(
          enabled: true,
          environment: {'XDG_DATA_HOME': data.path},
          executable: binary.path,
          fileIcon: () async =>
              fail('No icon metadata before a valid launcher'),
        );
        await expectLater(service.install(), throwsStateError);
        expect(await data.exists(), isFalse);
      }
    },
  );
  test(
    'Linux GIO launches the exact escaped executable without shell expansion',
    () async {
      final app = await Directory(
        '${root.path}/App "quotes" `ticks` \$HOME \\ symbols',
      ).create();
      await executable.parent.rename('${root.path}/original-app');
      executable = await File('${root.path}/original-app/broomm')
          .copy('${app.path}/broomm');
      await Process.run('/bin/chmod', ['u+x', executable.path]);
      await Directory('${app.path}/data').create();
      await File('assets/branding/broomm-icon.png')
          .copy('${app.path}/data/broomm.png');
      await executable.writeAsString(
        '#!/bin/sh\npwd -P > launched-cwd\nprintf "%s" "\$#" > argument-count\n: > launch-complete\n',
      );
      final env = {
        'XDG_DATA_HOME': '${root.path}/gio-data',
        'HOME': '${root.path}/gio-home',
      };
      final result = await installer(env).install();
      // GIO is part of the existing Linux GTK runtime/toolchain. This tests its
      // real Desktop Entry parser, rather than duplicating our quoting logic.
      final launched = await Process.run('gio', [
        'launch',
        result.desktopFile,
      ], environment: env);
      expect(launched.exitCode, 0, reason: '${launched.stderr}');
      final cwd = File('${app.path}/launched-cwd'),
          args = File('${app.path}/argument-count');
      final complete = File('${app.path}/launch-complete');
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!await complete.exists() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await complete.exists(), isTrue);
      expect((await cwd.readAsString()).trimRight(), app.path);
      expect(await args.readAsString(), '0');
    },
    skip: !Platform.isLinux,
  );
}
