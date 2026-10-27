@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/setup/archive.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _entry(
  String name, {
  String contents = '',
  String? link,
  int type = 48,
}) {
  final bytes = utf8.encode(contents), header = Uint8List(512);
  void put(int offset, String text) =>
      header.setRange(offset, offset + text.length, utf8.encode(text));
  put(0, name);
  put(100, '0000755');
  put(124, bytes.length.toRadixString(8).padLeft(11, '0'));
  put(148, '        ');
  header[156] = link == null ? type : 50;
  if (link != null) put(157, link);
  put(257, 'ustar');
  put(
    148,
    '${header.fold<int>(0, (a, b) => a + b).toRadixString(8).padLeft(6, '0')}\x00 ',
  );
  return [
    ...header,
    ...bytes,
    ...List.filled((512 - bytes.length % 512) % 512, 0),
  ];
}

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-setup-tar-');
  });
  tearDown(() => root.delete(recursive: true));
  test('application files and framework links extract privately with executable permissions', () async {
    final tar = await File('${root.path}/safe.tar').writeAsBytes([
      ..._entry('App.app/Contents/MacOS/app', contents: 'exact'),
      ..._entry('App.app/Framework/Versions/A/lib', contents: 'library'),
      ..._entry('App.app/Framework/Versions/Current', link: 'A'),
      ..._entry('App.app/Framework/lib', link: 'Versions/Current/lib'),
      ...List.filled(1024, 0),
    ]);
    final out = Directory('${root.path}/out');
    await extractSetupTar(tar, out, 'App.app', DownloadCancellation());
    expect(
      await File('${out.path}/App.app/Framework/lib').readAsString(),
      'library',
    );
    expect(
      (await File('${out.path}/App.app/Contents/MacOS/app').stat()).mode & 0x40,
      isNonZero,
    );
    expect(await Directory('${out.path}/App.app').exists(), true);
  });
  test('an empty Finder bundle icon marker is ignored without changing application contents', () async {
    final tar = await File('${root.path}/finder.tar').writeAsBytes([
      ..._entry('App.app/Icon\r'),
      ..._entry('App.app/Contents/MacOS/app', contents: 'tested executable'),
      ...List.filled(1024, 0),
    ]);
    final out = Directory('${root.path}/out');
    await extractSetupTar(tar, out, 'App.app', DownloadCancellation());
    expect(
      await File('${out.path}/App.app/Contents/MacOS/app').readAsString(),
      'tested executable',
    );
    expect(await File('${out.path}/App.app/Icon\r').exists(), false);
  });
  test('traversal, case collisions, escaping links and linked write ancestors fail before creating an output', () async {
    final cases = [
      [..._entry('../escape', contents: 'bad')],
      [
        ..._entry('App.app/A', contents: 'a'),
        ..._entry('App.app/a', contents: 'b'),
      ],
      [
        ..._entry('App.app/Dir/a', contents: 'a'),
        ..._entry('App.app/dir/b', contents: 'b'),
      ],
      [..._entry('App.app/escape', link: '../../outside')],
      [
        ..._entry('App.app/link', link: 'data'),
        ..._entry('App.app/link/child', contents: 'bad'),
      ],
      [..._entry('App.app/hardlink', type: 49)],
      [..._entry('App.app/Icon\r', contents: 'not empty metadata')],
      [..._entry('App.app/Icon\r', link: 'Contents')],
      [..._entry('App.app/../Icon\r')],
    ];
    for (var i = 0; i < cases.length; i++) {
      final tar = await File('${root.path}/bad-$i.tar')
          .writeAsBytes([...cases[i], ...List.filled(1024, 0)]);
      final output = Directory('${root.path}/out-$i');
      await expectLater(
        extractSetupTar(tar, output, 'App.app', DownloadCancellation()),
        throwsFormatException,
      );
      expect(await output.exists(), false);
    }
    expect(await File('${root.parent.path}/escape').exists(), false);
  });
  test('truncated directory and cancellation preserve unrelated files without publishing output', () async {
    final tar = await File('${root.path}/truncated.tar')
        .writeAsBytes(_entry('App.app/data', contents: 'data'));
    final out = Directory('${root.path}/out');
    await expectLater(
      extractSetupTar(tar, out, 'App.app', DownloadCancellation()),
      throwsFormatException,
    );
    expect(await out.exists(), false);
    final cancellation = DownloadCancellation()..cancel();
    await expectLater(
      extractSetupTar(tar, out, 'App.app', cancellation),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(await out.exists(), false);
  });
  test('cancelling a native tool drains a child that ignores termination before cleanup', () async {
    final ready = File('${root.path}/ready');
    final cancellation = DownloadCancellation();
    final work = setupTool('/bin/sh', [
      '-c',
      r'trap "" TERM; printf ready > "$1"; exec /bin/sleep 30',
      'fixture',
      ready.path,
    ], cancellation);
    final assertion = expectLater(work, throwsA(isA<DownloadCancelled>()));
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!await ready.exists()) {
      if (DateTime.now().isAfter(deadline))
        fail('Fixture child did not signal readiness');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    cancellation.cancel();
    await assertion.timeout(const Duration(seconds: 6));
    expect(await ready.readAsString(), 'ready');
  });
  test('unbounded native diagnostic output is stopped instead of accumulating in memory', () async {
    await expectLater(
      setupTool('/usr/bin/yes', [], DownloadCancellation()),
      throwsFormatException,
    );
  });
}
