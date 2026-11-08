import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/android/saturn.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client extends RommClient {
  _Client() : super(Uri.parse('https://fixture.invalid'));
  List<RommFirmware> records = [];
  @override
  Future<List<RommFirmware>> firmware(int platformId) async => records;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.broomm/saturn-options-test');
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('broomm-saturn-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Uint8List header({int parent = 0}) {
    final b = Uint8List(128)..setRange(0, 8, ascii.encode('MComprHD'));
    ByteData.sublistView(b)
      ..setUint32(8, 124)
      ..setUint32(12, 5)
      ..setUint64(32, 4096);
    b[104] = parent;
    return b;
  }

  test('Saturn inspected CHD identity survives hashing and refuses parent, replacement, links and cancellation', () async {
    final file = await File('${temp.path}/Disc.chd').writeAsBytes(header());
    final disc = await inspectAndroidSaturnDisc(
      file,
      DownloadCancellation(),
      (_) {},
    );
    expect(disc.sha256, await progressFileHash(file));
    await file.writeAsBytes(header(parent: 1));
    await expectLater(
      inspectAndroidSaturnDisc(file, DownloadCancellation(), (_) {}),
      throwsFormatException,
    );
    await file.writeAsBytes(header());
    await expectLater(
      inspectAndroidSaturnDisc(file, DownloadCancellation(), (phase) {
        if (phase == 'Verifying the Saturn disc…')
          file.writeAsBytesSync(header(parent: 1));
      }),
      throwsA(isA<FileSystemException>()),
    );
    final linked = await Link('${temp.path}/Linked.chd').create(file.path);
    await expectLater(
      inspectAndroidSaturnDisc(
        File(linked.path),
        DownloadCancellation(),
        (_) {},
      ),
      throwsA(isA<FileSystemException>()),
    );
    await file.writeAsBytes(header());
    final cancel = DownloadCancellation();
    await expectLater(
      inspectAndroidSaturnDisc(file, cancel, (_) {
        cancel.cancel();
      }),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(await file.readAsBytes(), header());
    await expectLater(
      inspectAndroidSaturnDisc(
        File('${temp.path}/Disc.cue'),
        DownloadCancellation(),
        (_) {},
      ),
      throwsUnsupportedError,
    );
  });
  test('Saturn inherits real game/core/global option precedence and refuses ambiguous or included options', () async {
    const root = '/storage/emulated/0/Android/data/com.retroarch.aarch64/files';
    final paths = <String>[];
    var files = <String, String>{
      '$root/Beetle Saturn/Beetle Saturn.opt':
          'beetle_saturn_save_method = "mednafen"',
      '$root/retroarch-core-options.cfg':
          'beetle_saturn_save_method = "libretro"',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'rootOptions');
          final args = call.arguments as Map;
          expect(args['coreName'], 'mednafen_saturn');
          final path = args['path'] as String;
          paths.add(path);
          return files[path] == null
              ? null
              : Uint8List.fromList(utf8.encode(files[path]!));
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    Future<Map<String, String>> read([Map<String, String> prefs = const {}]) =>
        readAndroidSaturnOptions(
          channel,
          {'package': 'com.retroarch.aarch64'},
          prefs,
          '/source/Disc.chd',
          'rom-nonce',
        );
    expect(await read(), {'beetle_saturn_save_method': 'mednafen'});
    expect(paths.last, '$root/Beetle Saturn/Beetle Saturn.opt');
    files['$root/Beetle Saturn/Disc.opt'] =
        'beetle_saturn_shared_int = "enabled"';
    expect(await read(), {'beetle_saturn_shared_int': 'enabled'});
    expect(
      await read({
        'game_specific_options': 'false',
        'global_core_options': 'true',
      }),
      {'beetle_saturn_save_method': 'libretro'},
    );
    for (final text in [
      '#include "foreign.opt"',
      'beetle_saturn_save_method = "libretro"\nbeetle_saturn_save_method = "mednafen"',
    ]) {
      files = {'$root/Beetle Saturn/Disc.opt': text};
      await expectLater(read(), throwsFormatException);
    }
  });
  test('Saturn preserves native save mode and cartridge-size histories without launching with ignored progress', () {
    const base = 'files/Broomm/profile/game/saves/';
    expect(androidSaturnInternalName({}, 'Disc'), 'Disc.srm');
    expect(
      androidSaturnInternalName({
        'beetle_saturn_save_method': 'mednafen',
        'beetle_saturn_shared_int': 'enabled',
      }, 'Disc'),
      'mednafen_saturn_libretro_shared.bkr',
    );
    verifyAndroidSaturnWorking({}, 'Disc', [
      '${base}Disc.srm',
      '${base}Disc.bkr',
      '${base}Disc.bcr',
      '${base}Disc.4mb.bcr',
    ]);
    expect(
      () => verifyAndroidSaturnWorking({}, 'Disc', ['${base}Disc.bkr']),
      throwsFormatException,
    );
    expect(
      () => verifyAndroidSaturnWorking(
        {'beetle_saturn_save_method': 'mednafen'},
        'Disc',
        ['${base}mednafen_saturn_libretro_shared.bkr'],
      ),
      throwsFormatException,
    );
    expect(
      () => verifyAndroidSaturnWorking({}, 'Disc', ['${base}Disc.4mb.bcr']),
      throwsFormatException,
    );
    verifyAndroidSaturnWorking(
      {'beetle_saturn_backup_memory_size': '4MB'},
      'Disc',
      ['${base}Disc.4mb.bcr'],
    );
    expect(
      () => verifyAndroidSaturnWorking(
        {'beetle_saturn_shared_ext': 'enabled'},
        'Disc',
        ['${base}Disc.bcr'],
      ),
      throwsFormatException,
    );
  });
  test('Saturn requires canonical regional BIOS and explicit ROM carts while preserving damaged cache objects', () async {
    expect(androidSaturnResourceNames({}), ['sega_101.bin', 'mpr-17933.bin']);
    expect(
      androidSaturnResourceNames({
        'beetle_saturn_cart': "The King of Fighters '95",
      }),
      contains('mpr-18811-mx.ic1'),
    );
    expect(
      () => androidSaturnResourceNames({'beetle_saturn_cart': 'Unknown'}),
      throwsFormatException,
    );
    final client = _Client();
    addTearDown(client.close);
    await expectLater(
      ensureAndroidSaturnResources(
        temp,
        31,
        {},
        client,
        DownloadCancellation(),
        (_) {},
      ),
      throwsA(isA<RommFailure>()),
    );
    final cache = Directory('${temp.path}/saturn-firmware');
    final old = await File('${cache.path}/${'a' * 32}.img')
        .writeAsBytes([1, 2, 3]);
    await File('${cache.path}/index.json').writeAsString(
      jsonEncode({
        'version': 1,
        'platform': 31,
        'resources': {
          'sega_101.bin': {'object': 'a' * 32, 'sha256': 'b' * 64},
        },
      }),
    );
    await expectLater(
      ensureAndroidSaturnResources(
        temp,
        31,
        {},
        client,
        DownloadCancellation(),
        (_) {},
      ),
      throwsA(isA<RommFailure>()),
    );
    expect(await old.readAsBytes(), [1, 2, 3]);
  });
}
