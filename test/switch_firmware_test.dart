import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/zip.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/switch_firmware.dart';

class _Manager extends ManagedEmulators {
  _Manager(super.data) : super(asset: (_) async => '');
  @override
  Future<void> load() async {}
  @override
  Future<(String, Directory)> preparePackages(
    String platform,
    String id,
    DownloadCancellation c, {
    String? emulator,
  }) async {
    final eden = emulator == 'Eden';
    final p = Directory(
      '${data.path}/profiles/$id/emulators/${eden ? 'eden' : 'ryubing'}',
    );
    await Directory('${p.path}/${eden ? 'data/eden' : 'user'}')
        .create(recursive: true);
    return ('unused', p);
  }
}

class _Client extends RommClient {
  _Client(this.files, this.payloads)
    : super(Uri.parse('https://fixture.invalid'));
  final List<RommFirmware> files;
  final Map<int, List<int>> payloads;
  final calls = <int>[];
  void Function(DownloadCancellation)? before;
  @override
  Future<List<RommFirmware>> firmware(int platform) async => files;
  @override
  Future<void> downloadFirmware(
    RommFirmware f,
    File output, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    calls.add(f.id);
    await output.writeAsBytes(payloads[f.id]!);
    before?.call(cancellation);
    cancellation.check();
    onProgress(f.bytes);
  }
}

void main() {
  late Directory root;
  late _Manager manager;
  const profile = 'a123456789abcdef0123456789abcdef';
  Future<File> zip(Map<String, List<int>> files) async {
    final stage = await root.createTemp('zip-');
    for (final e in files.entries) {
      final f = File('${stage.path}/${e.key}');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(e.value);
    }
    final out = File('${stage.path}/firmware.zip');
    await ProgressZip.write(out, stage, files.keys.toList());
    return out;
  }

  Future<_Client> client({
    String title = 'title.keys',
    bool ambiguous = false,
  }) async {
    final archive = await zip({
      'Firmware/${'a' * 32}.nca': List.filled(0xc00, 9),
    });
    final payloads = {
      1: await archive.readAsBytes(),
      2: utf8.encode('header_key = ${'1' * 64}\n'),
      3: utf8.encode('# empty title key set\n'),
    };
    final files = [
      for (final e in payloads.entries)
        RommFirmware(
          e.key,
          8,
          {1: 'firmware.zip', 2: 'prod.keys', 3: title}[e.key]!,
          e.value.length,
          (ProgressDigest.md5()..add(e.value)).finish(),
        ),
    ];
    if (ambiguous) files.add(RommFirmware(4, 8, 'other.zip', 1, 'a' * 32));
    return _Client(files, payloads);
  }

  Future<void> run(_Client c, {String emulator = 'Ryubing'}) async {
    final lease = await SessionLease.acquire(root);
    try {
      await ensureSwitchFirmware(
        manager,
        profile,
        8,
        c,
        DownloadCancellation(),
        (_) {},
        lease: lease,
        emulator: emulator,
      );
    } finally {
      await lease.release();
    }
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-switch-firmware-');
    manager = _Manager(root);
    manager.builds.add(
      TestedBuild({
        'id': 'ryubing',
        'name': 'Ryubing',
        'version': 'test',
        'host': 'macos-arm64',
        'bundle': 'Ryujinx.app',
        'executable': 'x',
        'sha256': 'a' * 64,
        'sdl': 2,
        'native': <String, String>{},
      }),
    );
    manager.builds.add(
      TestedBuild({
        'id': 'eden',
        'name': 'Eden',
        'version': 'test',
        'host': 'macos-arm64',
        'bundle': 'eden.app',
        'executable': 'x',
        'sha256': 'b' * 64,
        'sdl': 2,
        'native': <String, String>{},
      }),
    );
  });
  test('Eden firmware uses its native NAND paths and keeps the other Switch console isolated', () async {
    final c = await client();
    try {
      await run(c, emulator: 'Eden');
      final user = '${root.path}/profiles/$profile/emulators/eden/data/eden';
      expect(
        await File('$user/nand/system/Contents/registered/${'a' * 32}.nca/00')
            .length(),
        0xc00,
      );
      expect(await File('$user/keys/prod.keys').exists(), true);
      expect(
        await Directory('${root.path}/profiles/$profile/emulators/ryubing')
            .exists(),
        false,
      );
      final before = c.calls.length;
      await run(c, emulator: 'Eden');
      expect(c.calls.length, before);
    } finally {
      c.close();
    }
  });
  tearDown(() async {
    manager.dispose();
    await root.delete(recursive: true);
  });
  test('exact RomM layout provisions private native files once and never replaces configured keys or firmware', () async {
    final c = await client();
    try {
      await run(c);
      expect(c.calls.toSet(), {1, 2, 3});
      final user = '${root.path}/profiles/$profile/emulators/ryubing/user';
      expect(
        await File('$user/bis/system/Contents/registered/${'a' * 32}.nca/00')
            .length(),
        0xc00,
      );
      await File('$user/system/prod.keys')
          .writeAsString('private configured key');
      final count = c.calls.length;
      await run(c);
      expect(c.calls.length, count);
      expect(
        await File('$user/system/prod.keys').readAsString(),
        'private configured key',
      );
    } finally {
      c.close();
    }
  });
  for (final engine in ['Ryubing', 'Eden']) {
    test(
      '$engine keeps an existing incomplete resource tree and requires explicit repair',
      () async {
        final c = await client();
        final build = manager.buildFor(engine)!;
        final firmware = Directory(
          '${manager.root.path}/${build.id}/${build.hash}/resources/switch_firmware',
        );
        await firmware.create(recursive: true);
        final foreign = File('${firmware.path}/unrelated.txt');
        await foreign.writeAsString('keep');
        try {
          await expectLater(
            run(c, emulator: engine),
            throwsA(isA<RommFailure>()),
          );
          expect(await foreign.readAsString(), 'keep');
          expect(
            await Directory('${firmware.path}/${'a' * 32}.nca').exists(),
            false,
          );
          final p =
              '${root.path}/profiles/$profile/emulators/${engine == 'Eden' ? 'eden/data/eden/nand' : 'ryubing/user/bis'}/system/Contents/registered';
          expect(await Directory(p).exists(), false);
        } finally {
          c.close();
        }
      },
    );
  }
  test('typo aliases and ambiguous firmware choices fail before any download; cancelled provisioning is retryable', () async {
    for (final c in [
      await client(title: 'title.keus'),
      await client(ambiguous: true),
    ]) {
      try {
        await expectLater(run(c), throwsA(isA<RommFailure>()));
        expect(c.calls, isEmpty);
      } finally {
        c.close();
      }
    }
    final c = await client();
    try {
      c.before = (cancel) => cancel.cancel();
      await expectLater(run(c), throwsA(isA<DownloadCancelled>()));
      expect(
        await File(
          '${root.path}/emulators/ryubing/${'a' * 64}/resources/prod_keys',
        ).exists(),
        false,
      );
      c.before = null;
      await run(c);
      expect(
        await File(
          '${root.path}/profiles/$profile/emulators/ryubing/user/system/prod.keys',
        ).exists(),
        true,
      );
    } finally {
      c.close();
    }
  });
  test('ZIP normalization rejects colliding NCA IDs, unsupported payload and damaged key files', () async {
    final good = await zip({'${'a' * 32}.cnmt.nca': List.filled(0xc00, 1)});
    final stage = await root.createTemp('stage-');
    final content = await stageSwitchFirmware(good, stage);
    expect(await File('${content.path}/${'a' * 32}.nca/00').length(), 0xc00);
    for (final files in [
      {
        'a/${'a' * 32}.nca': List.filled(0xc00, 1),
        'b/${'a' * 32}.nca': List.filled(0xc00, 2),
      },
      {
        'readme.txt': [1, 2, 3],
      },
    ]) {
      final bad = await zip(files);
      await expectLater(
        stageSwitchFirmware(bad, await root.createTemp('bad-')),
        throwsFormatException,
      );
    }
    expect(
      () => validateSwitchKeyFile('header_key = 1', prod: true),
      throwsFormatException,
    );
    expect(
      () => validateSwitchKeyFile('wrong = aa', prod: false),
      throwsFormatException,
    );
  });
}
