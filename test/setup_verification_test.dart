import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reviewed archives use structural checks without rehashing every extracted file; folder imports retain fingerprints', () async {
    final root = await Directory.systemTemp.createTemp('broomm-package-check-');
    final app = await Directory('${root.path}/AppDir').create();
    await File('${app.path}/app')
        .writeAsString('already verified in the archive');
    final expected = {
      'files': {'app': '0' * 64},
      'links': <String, String>{},
    };
    final b = TestedBuild({
      'id': 'fixture',
      'name': 'Fixture',
      'version': '1',
      'host': 'linux-x64',
      'bundle': 'AppDir',
      'executable': 'app',
      'sha256': 'a' * 64,
      'sdl': 2,
      'native': {},
    });
    final manager = ManagedEmulators(
      Directory('${root.path}/data'),
      hostOverride: 'linux-x64',
      asset: (_) async => jsonEncode(expected),
    );
    try {
      await manager.verifyBundle(
        b,
        app.path,
        DownloadCancellation(),
        verifiedArchive: true,
      );
      await expectLater(
        manager.verifyBundle(b, app.path, DownloadCancellation()),
        throwsStateError,
      );
      final extra = await File('${app.path}/unexpected')
          .writeAsString('foreign');
      await expectLater(
        manager.verifyBundle(
          b,
          app.path,
          DownloadCancellation(),
          verifiedArchive: true,
        ),
        throwsStateError,
      );
      await extra.delete();
      if (!Platform.isWindows) {
        await Link('${app.path}/link').create(root.path);
        await expectLater(
          manager.verifyBundle(
            b,
            app.path,
            DownloadCancellation(),
            verifiedArchive: true,
          ),
          throwsStateError,
        );
      }
    } finally {
      manager.dispose();
      await root.delete(recursive: true);
    }
  });
}
