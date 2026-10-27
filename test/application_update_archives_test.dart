import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/progress/zip.dart';
import 'package:broomm/src/updates/archive.dart';

List<int> tarEntry(String name, List<int> contents, {int type = 48}) {
  final h = Uint8List(512);
  void put(int start, String text) =>
      h.setRange(start, start + text.length, ascii.encode(text));
  put(0, name);
  put(100, '0000755');
  put(108, '0000000');
  put(116, '0000000');
  put(124, contents.length.toRadixString(8).padLeft(11, '0'));
  put(136, '00000000000');
  put(148, '        ');
  h[156] = type;
  put(257, 'ustar');
  final sum = h.fold<int>(0, (n, b) => n + b);
  put(148, '${sum.toRadixString(8).padLeft(6, '0')}\x00 ');
  return [
    ...h,
    ...contents,
    ...List.filled((512 - contents.length % 512) % 512, 0),
  ];
}

void main() {
  test('Linux tar extraction accepts complete bounded bundles and rejects traversal, collisions and links before writes', () async {
    final root = await Directory.systemTemp.createTemp('broomm-update-tar-');
    addTearDown(() => root.delete(recursive: true));
    final archive = File('${root.path}/app.tar.gz');
    for (final scenario in [
      'normal',
      'traversal',
      'collision',
      'link',
      'truncated',
    ]) {
      final bytes = <int>[
        ...tarEntry(scenario == 'traversal' ? '../outside' : 'bundle/data/a', [
          42,
        ], type: scenario == 'link' ? 50 : 48),
        if (scenario == 'collision') ...tarEntry('bundle/data/A', [43]),
        if (scenario != 'truncated') ...List.filled(1024, 0),
      ];
      await archive.writeAsBytes(gzip.encode(bytes));
      final output = Directory('${root.path}/$scenario');
      if (scenario == 'normal') {
        await extractUpdate(archive, output, 'linux');
        expect(await File('${output.path}/bundle/data/a').readAsBytes(), [42]);
      } else {
        await expectLater(
          extractUpdate(archive, output, 'linux'),
          throwsException,
        );
        expect(await output.exists(), isFalse);
      }
    }
    expect(await File('${root.path}/outside').exists(), isFalse);
  });

  test(
    'Windows ZIP traversal is rejected before any output is extracted',
    () async {
      final root = await Directory.systemTemp.createTemp('broomm-update-zip-');
      addTearDown(() => root.delete(recursive: true));
      final source = await Directory('${root.path}/source').create();
      await File('${source.path}/payload0').writeAsString('keep confined');
      final archive = File('${root.path}/app.zip');
      await ProgressZip.write(archive, source, ['payload0']);
      final bytes = await archive.readAsBytes();
      final name = ascii.encode('payload0'), unsafe = ascii.encode('../evilX');
      for (var i = 0; i <= bytes.length - name.length; i++) {
        if (List.generate(
          name.length,
          (n) => bytes[i + n] == name[n],
        ).every((b) => b))
          bytes.setRange(i, i + name.length, unsafe);
      }
      await archive.writeAsBytes(bytes);
      final output = Directory('${root.path}/new');
      await expectLater(
        extractUpdate(archive, output, 'windows'),
        throwsA(isA<FormatException>()),
      );
      expect(await output.exists(), isFalse);
      expect(await File('${root.path}/evilX').exists(), isFalse);
    },
  );

  test('macOS framework links remain confined; save extraction still refuses all links', () async {
    final root = await Directory.systemTemp.createTemp(
      'broomm-update-mac-links-',
    );
    addTearDown(() => root.delete(recursive: true));
    final app = await Directory(
      '${root.path}/broomm.app/Contents/Frameworks/Fixture.framework/Versions/A',
    ).create(recursive: true);
    await File('${app.path}/asset').writeAsString('framework data');
    final link = Link('${app.parent.path}/Current');
    await link.create('A');
    final zip = File('${root.path}/app.zip');
    expect(
      (await Process.run('/usr/bin/ditto', [
        '-c',
        '-k',
        '--keepParent',
        '${root.path}/broomm.app',
        zip.path,
      ])).exitCode,
      0,
    );
    final inspected = await ProgressZip.read(zip, inspectLinks: true);
    expect(inspected.entries.any((e) => e.symbolicLink), isTrue);
    await expectLater(ProgressZip.read(zip), throwsA(isA<FormatException>()));
    await expectLater(
      inspected.extract(Directory('${root.path}/saves')),
      throwsA(isA<FormatException>()),
    );
    final output = Directory('${root.path}/new');
    await extractUpdate(zip, output, 'macos');
    expect(
      await File(
        '${output.path}/broomm.app/Contents/Frameworks/Fixture.framework/Versions/Current/asset',
      ).readAsString(),
      'framework data',
    );
    await link.delete();
    await link.create('../../../../../../outside');
    await zip.delete();
    expect(
      (await Process.run('/usr/bin/ditto', [
        '-c',
        '-k',
        '--keepParent',
        '${root.path}/broomm.app',
        zip.path,
      ])).exitCode,
      0,
    );
    final rejected = Directory('${root.path}/rejected');
    await expectLater(extractUpdate(zip, rejected, 'macos'), throwsException);
    expect(await rejected.exists(), isFalse);
  }, testOn: 'mac-os');
}
