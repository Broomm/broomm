@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/setup/archive.dart';
import 'package:broomm/src/setup/package.dart';
import 'package:flutter_test/flutter_test.dart';

// Model another supported codesign output without changing any program code.
class _DifferentSigning extends SetupDownloads {
  _DifferentSigning(super.data);
  @override
  Future<String> prepare(
    SetupPackage package,
    Directory working,
    DownloadCancellation cancellation,
    void Function(String, double?) progress, {
    Directory? localRoot,
  }) async {
    final path = await super.prepare(
      package,
      working,
      cancellation,
      progress,
      localRoot: localRoot,
    );
    await setupTool('/usr/bin/codesign', [
      '--force',
      '--deep',
      '--sign',
      '-',
      '--digest-algorithm=sha1,sha256',
      path,
    ], cancellation);
    return path;
  }
}

void main() {
  late Directory root;
  late ManagedEmulators manager;
  late Map<String, String> assets;
  late File archive, setup;
  late String reviewedHash;
  const profile = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  ManagedEmulators open() => ManagedEmulators(
    Directory('${root.path}/data'),
    asset: (p) async => assets[p]!,
    downloads: _DifferentSigning(Directory('${root.path}/data')),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-signing-');
    final source = await Directory(
      '${root.path}/source/Fixture.app/Contents/MacOS',
    ).create(recursive: true);
    await File('/usr/bin/true').copy('${source.path}/Fixture');
    await File('${source.parent.path}/Info.plist').writeAsString('''
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.broomm.signing-fixture</string>
<key>CFBundleExecutable</key><string>Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string></dict></plist>
''');
    await Directory('${source.parent.path}/Resources').create();
    await File('${source.parent.path}/Resources/data')
        .writeAsString('reviewed resource');
    archive = File('${root.path}/fixture.tar.gz');
    await runOwnedTool('/usr/bin/tar', [
      '-czf',
      archive.path,
      '-C',
      source.parent.parent.parent.path,
      'Fixture.app',
    ]);
    final recipe = {
      'file': 'fixture.tar.gz',
      'sha256': await sha256File(archive.path),
      'bytes': await archive.length(),
      'format': 'tar.gz',
      'entry': 'Fixture.app',
      'prepare': 'macos-adhoc',
    };
    final prepared = await SetupDownloads(root).prepare(
      SetupPackage.fromJson(recipe),
      root,
      DownloadCancellation(),
      (_, _) {},
      localRoot: root,
    );
    reviewedHash = await sha256File('$prepared/Contents/MacOS/Fixture');
    final files = <String, String>{};
    await for (final file in Directory(prepared).list(recursive: true)) {
      if (file is File)
        files[file.path.substring(prepared.length + 1)] = await sha256File(
          file.path,
        );
    }
    assets = {
      'assets/setup/tested-builds.json': jsonEncode({
        'builds': [
          {
            'id': 'dolphin',
            'name': 'Dolphin',
            'version': 'fixture',
            'host': 'macos-arm64',
            'bundle': 'Fixture.app',
            'executable': 'Contents/MacOS/Fixture',
            'sha256': reviewedHash,
            'source_package': recipe,
            'sdl': 3,
            'native': {},
          },
        ],
      }),
      'assets/setup/dolphin.integrity.json': jsonEncode({
        'files': files,
        'links': {},
      }),
      'assets/setup/dolphin.symbols': '',
      'assets/setup/setup.json': jsonEncode({
        'schema_version': 2,
        'host': 'macos-arm64',
        'launchers': {
          'dolphin': {'source': recipe},
        },
      }),
    };
    setup = await File('${root.path}/setup.json')
        .writeAsString(assets['assets/setup/setup.json']!);
    manager = open();
  });
  tearDown(() async {
    manager.dispose();
    await root.delete(recursive: true);
  });

  test('valid different signature bytes install, persist and reuse without the source archive', () async {
    await manager.install(await manager.readPlan(file: setup.path));
    expect(manager.error, isNull, reason: manager.error);
    final resolved = await manager.resolveConfiguration('Dolphin', profile);
    expect(resolved.executableHash, isNot(reviewedHash));
    expect(resolved.buildHash, reviewedHash);
    expect(resolved.withInstallationIdentity('game').buildHash, reviewedHash);
    await archive.delete();
    manager.dispose();
    manager = open();
    await manager.install(await manager.readPlan(file: setup.path));
    expect(manager.error, isNull, reason: manager.error);
    final reopened = await manager.resolveConfiguration('Dolphin', profile);
    expect(reopened.executableHash, resolved.executableHash);
    expect(reopened.buildHash, reviewedHash);
  });

  test('damaged signed resources and unknown archive provenance cannot become usable installations', () async {
    await manager.install(await manager.readPlan(file: setup.path));
    expect(manager.error, isNull, reason: manager.error);
    final release = '${manager.root.path}/dolphin/$reviewedHash';
    final progress = await File('${manager.data.path}/keep.sav')
        .writeAsString('progress');
    final resource = File('$release/Fixture.app/Contents/Resources/data');
    final original = await resource.readAsString();
    await resource.writeAsString('damaged resource');
    await expectLater(
      manager.resolveConfiguration('Dolphin', profile),
      throwsStateError,
    );
    await resource.writeAsString(original);
    final receipt = File('$release/receipt.json');
    final record = jsonDecode(await receipt.readAsString()) as Map;
    record['preparation']['archive_sha256'] = '0' * 64;
    await receipt.writeAsString(jsonEncode(record));
    await expectLater(
      manager.resolveConfiguration('Dolphin', profile),
      throwsFormatException,
    );
    expect(await resource.readAsString(), original);
    expect(await progress.readAsString(), 'progress');
  });

  test('unverified archives and cancelled signing preparation publish nothing and preserve progress', () async {
    final plan = await manager.readPlan(file: setup.path);
    await manager.data.create(recursive: true);
    final save = await File('${manager.data.path}/keep.sav')
        .writeAsString('progress');
    final original = await archive.readAsBytes();
    await archive.writeAsBytes([...original]..[0] ^= 1);
    await manager.install(plan);
    expect(manager.error, contains('differs from the reviewed build'));
    expect(manager.installed, isEmpty);
    await archive.writeAsBytes(original);
    var cancelled = false;
    void cancel() {
      if (!cancelled && manager.phase.contains('Preparing reviewed macOS')) {
        cancelled = true;
        manager.cancel();
      }
    }

    manager.addListener(cancel);
    await manager.install(await manager.readPlan(file: setup.path));
    manager.removeListener(cancel);
    expect(cancelled, true);
    expect(manager.error, contains('Setup cancelled'));
    expect(manager.installed, isEmpty);
    expect(await save.readAsString(), 'progress');
  });
}
