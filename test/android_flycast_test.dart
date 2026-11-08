import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/android/flycast.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client extends RommClient {
  _Client() : super(Uri.parse('https://fixture.invalid'));
  @override
  Future<List<RommFirmware>> firmware(int platformId) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('broomm-flycast-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('Removing verified RetroArch setup clears only owned per-game preferences across profiles', () async {
    final kept = <File, List<int>>{};
    for (final profile in ['a' * 32, 'b' * 32]) {
      final root = await Directory(
        '${temp.path}/profiles/$profile/emulators/retroarch',
      ).create(recursive: true);
      await File('${root.path}/profile.json').writeAsString(
        jsonEncode({'version': 1, 'emulator': 'retroarch', 'profile': profile}),
      );
      await writeAndroidFlycastPreferences(root, '42', {
        'flycast_internal_resolution': '1280x960',
      });
      final save = File('${root.path}/root-dc/42/saves/ID.A1.bin');
      await save.parent.create(recursive: true);
      await save.writeAsBytes([1, 2, 3]);
      kept[save] = [1, 2, 3];
      final console = File('${root.path}/flycast-console/retained.bin');
      await console.parent.create();
      await console.writeAsBytes([4, 5, 6]);
      kept[console] = [4, 5, 6];
    }
    await clearAndroidFlycastPreferences(temp);
    for (final profile in ['a' * 32, 'b' * 32])
      expect(
        await File(
          '${temp.path}/profiles/$profile/emulators/retroarch/root-dc/42/options.json',
        ).exists(),
        false,
      );
    for (final e in kept.entries) expect(await e.key.readAsBytes(), e.value);
    await clearAndroidFlycastPreferences(temp);
  });

  test('Unrecognized ownership or linked game configuration blocks removal without touching foreign settings', () async {
    final profile = 'a' * 32;
    final root = await Directory(
      '${temp.path}/profiles/$profile/emulators/retroarch',
    ).create(recursive: true);
    final owner = await File('${root.path}/profile.json').writeAsString(
      jsonEncode({'version': 1, 'emulator': 'ppsspp', 'profile': profile}),
    );
    await writeAndroidFlycastPreferences(root, '42', {
      'flycast_internal_resolution': '1280x960',
    });
    final original = File('${root.path}/root-dc/42/options.json'),
        bytes = await File('${root.path}/root-dc/42/options.json')
            .readAsBytes();
    await expectLater(
      clearAndroidFlycastPreferences(temp),
      throwsA(isA<FileSystemException>()),
    );
    expect(await original.readAsBytes(), bytes);
    await owner.writeAsString(
      jsonEncode({'version': 1, 'emulator': 'retroarch', 'profile': profile}),
    );
    final foreign = await Directory('${temp.path}/foreign').create();
    final file = await File('${foreign.path}/options.json')
        .writeAsString('foreign configuration');
    await Directory('${root.path}/root-dc/42').delete(recursive: true);
    await Link('${root.path}/root-dc/42').create(foreign.path);
    await expectLater(
      clearAndroidFlycastPreferences(temp),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), 'foreign configuration');
  });

  test('Flycast console publication survives lost replies and preserves prior identities across games and accounts', () async {
    final a = await Directory('${temp.path}/one').create();
    final b = await Directory('${temp.path}/two').create();
    final first = await File('${temp.path}/first.bin')
        .writeAsBytes(List.filled(131072, 1));
    final second = await File('${temp.path}/second.bin')
        .writeAsBytes(List.filled(131072, 2));
    final firstHash = await progressFileHash(first),
        secondHash = await progressFileHash(second);
    expect(await readAndroidFlycastConsole(a), isNull);
    await publishAndroidFlycastConsole(a, null, first, firstHash);
    final original = (await readAndroidFlycastConsole(a))!;
    await publishAndroidFlycastConsole(a, null, first, firstHash);
    expect((await readAndroidFlycastConsole(a))!.object, original.object);
    await publishAndroidFlycastConsole(b, null, second, secondHash);
    expect((await readAndroidFlycastConsole(b))!.sha256, secondHash);
    expect((await readAndroidFlycastConsole(a))!.sha256, firstHash);
    await publishAndroidFlycastConsole(a, original.record, second, secondHash);
    expect((await readAndroidFlycastConsole(a))!.sha256, secondHash);
    expect(await progressFileHash(original.file), firstHash);
    await expectLater(
      publishAndroidFlycastConsole(a, original.record, first, firstHash),
      throwsStateError,
    );
    expect((await readAndroidFlycastConsole(a))!.sha256, secondHash);
    expect(await progressFileHash(first), firstHash);
  });

  test(
    'Known missing or damaged console flash cannot become a new empty identity',
    () async {
      final source = await File('${temp.path}/source.bin')
          .writeAsBytes(List.filled(131072, 3));
      final hash = await progressFileHash(source);
      await publishAndroidFlycastConsole(temp, null, source, hash);
      final known = (await readAndroidFlycastConsole(temp))!;
      await known.file.writeAsBytes([1]);
      await expectLater(readAndroidFlycastConsole(temp), throwsFormatException);
      await expectLater(
        publishAndroidFlycastConsole(temp, known.record, source, hash),
        throwsFormatException,
      );
      await known.file.delete();
      await expectLater(readAndroidFlycastConsole(temp), throwsFormatException);
      expect(await progressFileHash(source), hash);
    },
  );

  test('Private Flycast preferences persist per game without weakening all-port VMU isolation', () async {
    final options = {
      'flycast_internal_resolution': '1280x960',
      'flycast_per_content_vmus': 'disabled',
      'flycast_linked_vmu_storage': 'enabled',
    };
    final text = androidFlycastOptionsText(options);
    final actual = parseAndroidFlycastOptions(
      Uint8List.fromList(utf8.encode(text)),
    );
    expect(actual['flycast_internal_resolution'], '1280x960');
    expect(actual['flycast_per_content_vmus'], 'All VMUs');
    expect(actual['flycast_linked_vmu_storage'], 'disabled');
    await writeAndroidFlycastPreferences(temp, '42', actual);
    expect(await readAndroidFlycastPreferences(temp, '42'), {
      'flycast_internal_resolution': '1280x960',
    });
    expect(await readAndroidFlycastPreferences(temp, '43'), isEmpty);
    final other = await Directory('${temp.path}/other').create();
    expect(await readAndroidFlycastPreferences(other, '42'), isEmpty);
    for (final invalid in [
      '#include "other.opt"',
      'flycast_internal_resolution = "640x480"\nflycast_internal_resolution = "1280x960"',
    ]) {
      expect(
        () => parseAndroidFlycastOptions(
          Uint8List.fromList(utf8.encode(invalid)),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => androidFlycastOptionsText({'flycast_key': 'broken\nvalue'}),
      throwsFormatException,
    );
  });

  test('Flycast follows actual frontend option precedence without changing its source files', () async {
    const channel = MethodChannel('app.broomm/flycast-test');
    const base = '/storage/emulated/0/Android/data/com.retroarch.aarch64/files';
    final files = {
      '$base/Flycast/Flycast.opt': 'flycast_internal_resolution = "1280x960"',
      '$base/retroarch-core-options.cfg':
          'flycast_internal_resolution = "640x480"',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'rootOptions');
          final args = call.arguments as Map;
          expect(args['coreName'], 'flycast');
          final value = files[args['path']];
          return value == null ? null : Uint8List.fromList(utf8.encode(value));
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    Future<Map<String, String>> read([
      Map<String, String> preferences = const {},
    ]) => readAndroidFlycastOptions(
      channel,
      {'package': 'com.retroarch.aarch64'},
      preferences,
      '/source/Disc.chd',
      'rom-nonce',
    );
    expect((await read())['flycast_internal_resolution'], '1280x960');
    files['$base/Flycast/Disc.opt'] =
        'flycast_internal_resolution = "1920x1440"';
    expect((await read())['flycast_internal_resolution'], '1920x1440');
    expect(
      (await read({
        'game_specific_options': 'false',
        'global_core_options': 'true',
      }))['flycast_internal_resolution'],
      '640x480',
    );
    expect(
      files['$base/retroarch-core-options.cfg'],
      'flycast_internal_resolution = "640x480"',
    );
  });

  test('Dreamcast CHD accepts its concrete logical bound but refuses parent, incomplete media and cancellation', () async {
    Uint8List header(int logical, {int parent = 0}) {
      final bytes = Uint8List(128)..setRange(0, 8, ascii.encode('MComprHD'));
      ByteData.sublistView(bytes)
        ..setUint32(8, 124)
        ..setUint32(12, 5)
        ..setUint64(32, logical);
      bytes[104] = parent;
      return bytes;
    }

    final file = await File('${temp.path}/Disc.chd')
        .writeAsBytes(header(2 * 1024 * 1024 * 1024));
    final inspected = await inspectAndroidFlycastDisc(
      file,
      DownloadCancellation(),
      (_) {},
    );
    expect(inspected.sha256, await progressFileHash(file));
    for (final bytes in [
      header(2 * 1024 * 1024 * 1024 + 1),
      header(4096, parent: 1),
      Uint8List(12),
    ]) {
      await file.writeAsBytes(bytes);
      await expectLater(
        inspectAndroidFlycastDisc(file, DownloadCancellation(), (_) {}),
        throwsFormatException,
      );
    }
    await file.writeAsBytes(header(4096));
    final cancel = DownloadCancellation();
    await expectLater(
      inspectAndroidFlycastDisc(file, cancel, (_) {
        cancel.cancel();
      }),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(await file.readAsBytes(), header(4096));
    await expectLater(
      inspectAndroidFlycastDisc(
        File('${temp.path}/Disc.gdi'),
        DownloadCancellation(),
        (_) {},
      ),
      throwsUnsupportedError,
    );
  });

  test('Canonical Dreamcast boot firmware is distinct from mutable flash and damaged cache objects survive repair failure', () async {
    final client = _Client();
    addTearDown(client.close);
    await expectLater(
      ensureAndroidFlycastResources(
        temp,
        23,
        client,
        DownloadCancellation(),
        (_) {},
      ),
      throwsA(isA<RommFailure>()),
    );
    final cache = Directory('${temp.path}/flycast-firmware');
    final old = await File('${cache.path}/${'a' * 32}.img')
        .writeAsBytes([1, 2, 3]);
    await File('${cache.path}/index.json').writeAsString(
      jsonEncode({
        'version': 1,
        'platform': 23,
        'resources': {
          'dc_boot.bin': {'object': 'a' * 32, 'sha256': 'b' * 64},
        },
      }),
    );
    await expectLater(
      ensureAndroidFlycastResources(
        temp,
        23,
        client,
        DownloadCancellation(),
        (_) {},
      ),
      throwsA(isA<RommFailure>()),
    );
    expect(await old.readAsBytes(), [1, 2, 3]);
    expect(androidFlycastFirmware.keys, ['dc_boot.bin']);
    expect(await readAndroidFlycastConsole(temp), isNull);
  });
}
