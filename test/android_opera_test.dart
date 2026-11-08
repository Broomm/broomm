import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/android/opera.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client extends RommClient {
  _Client() : super(Uri.parse('https://fixture.invalid'));
  List<RommFirmware> records = [];
  int lookups = 0;
  bool unavailable = false;
  @override
  Future<List<RommFirmware>> firmware(int platformId) async {
    lookups++;
    if (unavailable) throw const RommFailure('Unavailable');
    return records;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.broomm/opera-options-test');
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('broomm-opera-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Uint8List chd({int parent = 0, int logical = 4096}) {
    final b = Uint8List(128)..setRange(0, 8, ascii.encode('MComprHD'));
    final data = ByteData.sublistView(b);
    data.setUint32(8, 124);
    data.setUint32(12, 5);
    data.setUint64(32, logical);
    b[104] = parent;
    return b;
  }

  test('Opera binds a self-contained CHD and refuses parent, changed, linked and oversized images', () async {
    final file = await File('${temp.path}/Disc.chd').writeAsBytes(chd());
    final disc = await inspectAndroidOperaDisc(
      file,
      DownloadCancellation(),
      (_) {},
    );
    expect(disc.sha256, await progressFileHash(file));
    expect(disc.bytes, 128);
    await file.writeAsBytes(chd(parent: 1));
    await expectLater(
      inspectAndroidOperaDisc(file, DownloadCancellation(), (_) {}),
      throwsFormatException,
    );
    await file.writeAsBytes(chd());
    await expectLater(
      inspectAndroidOperaDisc(file, DownloadCancellation(), (p) {
        if (p == 'Verifying the 3DO disc…')
          file.writeAsBytesSync(chd(logical: 8192));
      }),
      throwsA(isA<FileSystemException>()),
    );
    final link = await Link('${temp.path}/Linked.chd').create(file.path);
    await expectLater(
      inspectAndroidOperaDisc(File(link.path), DownloadCancellation(), (_) {}),
      throwsA(isA<FileSystemException>()),
    );
    final huge = await File('${temp.path}/Too big.iso')
        .open(mode: FileMode.write);
    await huge.truncate(1024 * 1024 * 1024 + 1);
    await huge.close();
    await expectLater(
      inspectAndroidOperaDisc(
        File('${temp.path}/Too big.iso'),
        DownloadCancellation(),
        (_) {},
      ),
      throwsFormatException,
    );
  });
  test('Opera refuses incomplete CUE/BIN sets and acknowledges read-only inspection cancellation', () async {
    final bin = await File('${temp.path}/Disc.bin').writeAsBytes([1, 2]);
    await File('${temp.path}/Disc.cue')
        .writeAsString('FILE "Disc.bin" BINARY\n TRACK 01 MODE1/2352\n');
    await expectLater(
      inspectAndroidOperaDisc(bin, DownloadCancellation(), (_) {}),
      throwsUnsupportedError,
    );
    await expectLater(
      inspectAndroidOperaDisc(
        File('${temp.path}/Disc.cue'),
        DownloadCancellation(),
        (_) {},
      ),
      throwsUnsupportedError,
    );
    final iso = await File('${temp.path}/Disc.iso')
        .writeAsBytes(List.filled(65536, 7));
    final cancellation = DownloadCancellation();
    await expectLater(
      inspectAndroidOperaDisc(iso, cancellation, (p) {
        cancellation.cancel();
      }),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(await iso.length(), 65536);
  });
  test('native option fallback paths survive temporary configuration and preserve explicit paths', () {
    const pkg = 'com.retroarch.aarch64';
    final original = '/storage/emulated/0/Android/data/$pkg/files';
    expect(androidRetroOptionPaths({}, pkg), {
      'rgui_config_directory': original,
      'core_options_path': '$original/retroarch-core-options.cfg',
    });
    expect(
      androidRetroOptionPaths({
        'rgui_config_directory': '/storage/emulated/0/RetroArch/config',
        'core_options_path': 'custom.cfg',
      }, pkg),
      {
        'rgui_config_directory': '/storage/emulated/0/RetroArch/config',
        'core_options_path': '$original/custom.cfg',
      },
    );
  });
  test('Opera follows game, actual folder, core and global precedence without merging options', () async {
    const directory = '/storage/emulated/0/RetroArch/config';
    final files = <String, String>{
      '$directory/Opera/Disc.opt':
          'opera_nvram_storage = "shared"\nopera_nvram_version = "7"\n',
      '$directory/Opera/native-folder.opt': 'opera_nvram_version = "4"\n',
      '$directory/Opera/Opera.opt': 'opera_nvram_version = "2"\n',
      '/storage/emulated/0/Android/data/com.retroarch.aarch64/files/retroarch-core-options.cfg':
          'opera_nvram_version = "9"\n',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'rootOptions');
          final text = files[(call.arguments as Map)['path']];
          return text == null ? null : Uint8List.fromList(utf8.encode(text));
        });
    final preferences = {'rgui_config_directory': directory};
    Future<Map<String, String>> read() => readAndroidOperaOptions(
      channel,
      {'package': 'com.retroarch.aarch64'},
      preferences,
      '/source/Disc.chd',
      'native-folder',
    );
    expect(
      androidOperaRawSaveKey(await read(), 'Disc'),
      'save/opera/shared/nvram.7.srm',
    );
    files.remove('$directory/Opera/Disc.opt');
    expect(
      androidOperaRawSaveKey(await read(), 'Disc'),
      'save/opera/per_game/Disc.4.srm',
    );
    preferences['game_specific_options'] = 'false';
    expect((await read())['opera_nvram_version'], '2');
    preferences['global_core_options'] = 'true';
    expect((await read())['opera_nvram_version'], '9');
    for (final text in [
      'opera_nvram_version = "2"\nopera_nvram_version = "3"',
      '#include "another.cfg"',
    ]) {
      files[files.keys.last] = text;
      await expectLater(read(), throwsFormatException);
    }
  });
  test('built-in Opera boot avoids network; selected BIOS ambiguity and damaged cache preserve old objects', () async {
    final client = _Client()..unavailable = true;
    try {
      expect(
        await ensureAndroidOperaResources(
          temp,
          1,
          {},
          client,
          DownloadCancellation(),
          (_) {},
        ),
        isEmpty,
      );
      expect(client.lookups, 0);
      expect(
        androidOperaResourceNames({
          'opera_bios': 'panafz10.bin',
          'opera_font': 'panafz1-kanji.bin',
        }),
        ['panafz10.bin', 'panafz1-kanji.bin'],
      );
      expect(
        () => androidOperaRawSaveKey({'opera_nvram_version': '10'}, 'Disc'),
        throwsFormatException,
      );
      expect(
        () => androidOperaResourceNames({'opera_bios': 'foreign.bin'}),
        throwsFormatException,
      );
      final cache = await Directory('${temp.path}/opera-firmware').create();
      final old = await File('${cache.path}/${'a' * 32}.img')
          .writeAsBytes([1, 2]);
      await File('${cache.path}/index.json').writeAsString(
        jsonEncode({
          'version': 1,
          'platform': 1,
          'resources': {
            'panafz10.bin': {'object': 'a' * 32, 'sha256': 'b' * 64},
          },
        }),
      );
      client.unavailable = false;
      client.records = [
        RommFirmware(
          1,
          1,
          'panafz10.bin',
          1048576,
          androidOperaFirmware['panafz10.bin']!.$2,
        ),
        RommFirmware(
          2,
          1,
          'panafz10.bin',
          1048576,
          androidOperaFirmware['panafz10.bin']!.$2,
        ),
      ];
      await expectLater(
        ensureAndroidOperaResources(
          temp,
          1,
          {'opera_bios': 'panafz10.bin'},
          client,
          DownloadCancellation(),
          (_) {},
        ),
        throwsA(isA<RommFailure>()),
      );
      expect(await old.readAsBytes(), [1, 2]);
    } finally {
      client.close();
    }
  });
}
