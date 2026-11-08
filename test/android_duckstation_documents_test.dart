import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:broomm/src/android/duckstation_documents.dart';
import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/romm/transfer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;
  late List<String> files;
  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-duck-documents-');
    final content = '${data.path}/library/${'a' * 32}/6583/content';
    files = [];
    for (final entry in {
      'Discs/Mega Man – X4.chd': [1, 2, 3],
      'launch.m3u': [4, 5],
    }.entries) {
      final file = File('$content/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value, flush: true);
      files.add(file.path);
    }
  });
  tearDown(() => data.delete(recursive: true));

  test('adapter sends stable identities across release/relaunch and cancellation never reaches native launch', () async {
    const channel = MethodChannel('app.broomm/duck-documents-test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'installed') {
            return [
              {
                'package': 'com.github.stenzek.duckstation',
                'version': androidDuckStationDocumentVersion,
                'build': 'a' * 64,
              },
            ];
          }
          if (call.method == 'launch') return 'native-grant';
          return null;
        });
    final manager = AndroidEmulators(data, channel: channel, enabled: true);
    try {
      await manager.load();
      final emulator = androidEmulators.singleWhere(
        (e) => e.id == 'duckstation',
      );
      final app = manager.app(emulator)!;
      await manager.launch(emulator, app, files, files.first);
      await manager.releaseGrants();
      await manager.launch(emulator, app, files.reversed.toList(), files.last);
      final launches = calls.where((c) => c.method == 'launch').toList();
      expect(launches, hasLength(2));
      final first = (launches.first.arguments as Map)['documentToken'];
      expect(first, matches(r'^[a-f0-9]{32}$'));
      expect((launches.last.arguments as Map)['documentToken'], first);
      await expectLater(
        manager.launch(
          emulator,
          app,
          files,
          files.first,
          cancellation: DownloadCancellation()..cancel(),
        ),
        throwsA(isA<DownloadCancelled>()),
      );
      expect(calls.where((c) => c.method == 'launch'), hasLength(2));
    } finally {
      manager.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  test('document identity survives revocation/relaunch and different device library IDs', () async {
    final first = await androidDuckStationDocumentToken(
      data,
      files,
      files.first,
    );
    expect(first, matches(r'^[a-f0-9]{32}$'));
    expect(
      await androidDuckStationDocumentToken(
        data,
        files.reversed.toList(),
        files.last,
      ),
      first,
    );
    final device = Directory('${data.path}/other-device');
    final copies = <String>[];
    final oldContent = files.last.substring(0, files.last.lastIndexOf('/'));
    for (final path in files) {
      final relative = path.substring(oldContent.length + 1);
      final copy = File(
        '${device.path}/library/${'b' * 32}/23/content/$relative',
      );
      await copy.parent.create(recursive: true);
      await File(path).copy(copy.path);
      copies.add(copy.path);
    }
    expect(
      await androidDuckStationDocumentToken(device, copies, copies.first),
      first,
    );
  });

  test('same-size content replacement changes identity with the modified time preserved', () async {
    final first = await androidDuckStationDocumentToken(
      data,
      files,
      files.first,
    );
    final file = File(files.first), before = await File(files.first).stat();
    await file.writeAsBytes([3, 2, 1], flush: true);
    await file.setLastModified(before.modified);
    expect(await file.length(), before.size);
    expect(
      await androidDuckStationDocumentToken(data, files, files.first),
      isNot(first),
    );
    await file.writeAsBytes([1, 2, 3], flush: true);
    expect(
      await androidDuckStationDocumentToken(data, files, files.first),
      first,
    );
  });

  test('foreign, missing and non-regular resources fail; cancellation leaves content intact', () async {
    final foreign = File('${data.path}/outside.chd');
    await foreign.writeAsBytes([9]);
    await expectLater(
      androidDuckStationDocumentToken(data, [
        ...files,
        foreign.path,
      ], files.first),
      throwsA(isA<FormatException>()),
    );
    final missing = '${File(files.last).parent.path}/missing.sbi';
    await expectLater(
      androidDuckStationDocumentToken(data, [...files, missing], files.first),
      throwsA(isA<FileSystemException>()),
    );
    final directory = Directory('${File(files.last).parent.path}/directory');
    await directory.create();
    await expectLater(
      androidDuckStationDocumentToken(data, [
        ...files,
        directory.path,
      ], files.first),
      throwsA(isA<FileSystemException>()),
    );
    if (!Platform.isWindows) {
      final link = Link('${File(files.last).parent.path}/linked.chd');
      await link.create(files.first);
      await expectLater(
        androidDuckStationDocumentToken(data, [
          ...files,
          link.path,
        ], files.first),
        throwsA(isA<FileSystemException>()),
      );
    }
    final cancellation = DownloadCancellation();
    await expectLater(
      androidDuckStationDocumentToken(
        data,
        files,
        files.first,
        cancellation: cancellation,
        phase: (_) => cancellation.cancel(),
      ),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(await File(files.first).readAsBytes(), [1, 2, 3]);
    expect(await foreign.readAsBytes(), [9]);
  });
}
