import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:broomm/src/android/duckstation_documents.dart';
import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/romm/transfer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;
  late List<String> files;
  Future<void> publish({String? revision}) async {
    final root = Directory('${data.path}/library/${'a' * 32}/6583');
    await File('${root.path}/receipt.json').writeAsString(
      jsonEncode({
        'version': 1,
        'serverId': 'a' * 32,
        'userId': 2,
        'game': {
          'id': 6583,
          'platform_slug': 'psx',
          'fs_name': 'Mega Man X4',
          'revision': revision,
        },
        'files': [
          for (final path in files)
            {
              'path': path.substring('${root.path}/content/'.length),
              'bytes': await File(path).length(),
            },
        ],
        'completedAt': '2026-11-08T00:00:00Z',
      }),
    );
  }

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
    await publish();
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

  test('publication identity survives release, another device and publication metadata changes', () async {
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
        '${device.path}/library/${'b' * 32}/6583/content/$relative',
      );
      await copy.parent.create(recursive: true);
      await File(path).copy(copy.path);
      copies.add(copy.path);
    }
    final original = jsonDecode(
      await File('${data.path}/library/${'a' * 32}/6583/receipt.json')
          .readAsString(),
    ) as Map;
    original['serverId'] = 'b' * 32;
    original['userId'] = 3;
    original['completedAt'] = '2026-11-09T00:00:00Z';
    original['files'] = (original['files'] as List).reversed.toList();
    // Optional download verification and display metadata do not change media identity.
    for (final item in original['files']) {
      item['verification'] = 'crc32';
      item['crc32'] = '12345678';
    }
    original['game']['name'] = 'Localized display title';
    await File('${device.path}/library/${'b' * 32}/6583/receipt.json')
        .writeAsString(jsonEncode(original));
    expect(
      await androidDuckStationDocumentToken(device, copies, copies.first),
      first,
    );
  });

  test(
    'launch uses receipt identity and metadata without opening ROM payloads',
    () async {
      final known = {for (final path in files) path: File(path)};
      final record = File('${data.path}/library/${'a' * 32}/6583/receipt.json');
      final first = await IOOverrides.runZoned(
        () => androidDuckStationDocumentToken(data, files, files.first),
        createFile: (path) =>
            path == record.path ? record : _MetadataFile(known[path]!),
      );
      await publish(revision: 'Rev 1');
      expect(
        await androidDuckStationDocumentToken(data, files, files.first),
        isNot(first),
      );
      await publish();
      expect(
        await androidDuckStationDocumentToken(data, files, files.first),
        first,
      );
    },
  );

  test('missing, mismatched and duplicate publication entries refuse before native launch', () async {
    final record = File('${data.path}/library/${'a' * 32}/6583/receipt.json');
    final text = await record.readAsString();
    for (final change in <void Function(Map)>[
      (j) => j['serverId'] = 'b' * 32,
      (j) => j['game']['id'] = 23,
      (j) => j['files'][0]['bytes'] = 77,
      (j) => j['files'][1] = j['files'][0],
    ]) {
      final j = jsonDecode(text) as Map;
      change(j);
      await record.writeAsString(jsonEncode(j));
      await expectLater(
        androidDuckStationDocumentToken(data, files, files.first),
        throwsA(isA<FormatException>()),
      );
    }
    await record.delete();
    await expectLater(
      androidDuckStationDocumentToken(data, files, files.first),
      throwsA(isA<FileSystemException>()),
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

/// The owning boundary is metadata-only: any payload I/O fails this regression.
class _MetadataFile implements File {
  _MetadataFile(this.inner);
  final File inner;
  @override
  String get path => inner.path;
  @override
  Future<FileStat> stat() => inner.stat();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Launch must not read ROM contents: ${invocation.memberName}',
  );
}
