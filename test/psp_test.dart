import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/psp.dart';
import 'package:broomm/src/addons/psp.dart';
import 'package:broomm/src/addons/files.dart';
import 'package:broomm/src/addons/package_profile.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/catalogue.dart';
import 'package:broomm/src/pairing.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/managed_profile.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/progress/store.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/session.dart';
import 'package:broomm/src/sony_sfo.dart';

Uint8List pspSfo({String id = 'ULUS10340', String version = '1.02'}) {
  final rows = {'DISC_ID': id, 'DISC_VERSION': version},
      keys = BytesBuilder(),
      values = BytesBuilder();
  final entries = <List<int>>[];
  for (final e in rows.entries) {
    entries.add([keys.length, values.length, utf8.encode(e.value).length + 1]);
    keys.add(utf8.encode('${e.key}\x00'));
    values.add(utf8.encode('${e.value}\x00'));
  }
  final k = 20 + rows.length * 16,
      v = k + keys.length,
      b = Uint8List(v + values.length),
      d = ByteData.sublistView(b);
  d.setUint32(0, 0x00505346);
  d.setUint32(8, k, Endian.little);
  d.setUint32(12, v, Endian.little);
  d.setUint32(16, rows.length, Endian.little);
  for (var i = 0; i < entries.length; i++) {
    final a = 20 + i * 16, e = entries[i];
    d.setUint16(a, e[0], Endian.little);
    d.setUint16(a + 2, 0x204, Endian.little);
    d.setUint32(a + 4, e[2], Endian.little);
    d.setUint32(a + 8, e[2], Endian.little);
    d.setUint32(a + 12, e[1], Endian.little);
  }
  b.setRange(k, v, keys.takeBytes());
  b.setRange(v, b.length, values.takeBytes());
  return b;
}

Uint8List pspPbp({String id = 'ULUS10340', String version = '1.02'}) {
  final sfo = pspSfo(id: id, version: version),
      b = Uint8List(40 + sfo.length),
      d = ByteData.sublistView(b);
  b.setRange(0, 4, [0, 80, 66, 80]);
  d.setUint32(8, 40, Endian.little);
  for (var i = 12; i < 40; i += 4) d.setUint32(i, b.length, Endian.little);
  b.setRange(40, b.length, sfo);
  return b;
}

Uint8List _record(int sector, int bytes, String name, bool directory) {
  final n = ascii.encode(name),
      b = Uint8List(34 + n.length + (n.length.isEven ? 1 : 0)),
      d = ByteData.sublistView(b);
  b[0] = b.length;
  d.setUint32(2, sector, Endian.little);
  d.setUint32(6, sector);
  d.setUint32(10, bytes, Endian.little);
  d.setUint32(14, bytes);
  b[25] = directory ? 2 : 0;
  b[32] = n.length;
  b.setRange(33, 33 + n.length, n);
  return b;
}

Uint8List pspIso() {
  final b = Uint8List(24 * 2048), sfo = pspSfo(), pvd = 16 * 2048;
  b[pvd] = 1;
  b.setRange(pvd + 1, pvd + 6, ascii.encode('CD001'));
  b[pvd + 6] = 1;
  final root = _record(20, 2048, '\x00', true),
      game = _record(21, 2048, 'PSP_GAME', true),
      param = _record(22, sfo.length, 'PARAM.SFO;1', false);
  b.setRange(pvd + 156, pvd + 156 + root.length, root);
  b.setRange(20 * 2048, 20 * 2048 + game.length, game);
  b.setRange(21 * 2048, 21 * 2048 + param.length, param);
  b.setRange(22 * 2048, 22 * 2048 + sfo.length, sfo);
  return b;
}

Uint8List _cso(Uint8List iso) {
  final sectors = iso.length ~/ 2048,
      head = Uint8List(24 + (sectors + 1) * 4),
      d = ByteData.sublistView(head),
      out = BytesBuilder();
  head.setRange(0, 4, ascii.encode('CISO'));
  d.setUint32(4, 24, Endian.little);
  d.setUint64(8, iso.length, Endian.little);
  d.setUint32(16, 2048, Endian.little);
  head[20] = 1;
  var at = head.length;
  for (var i = 0; i < sectors; i++) {
    final block = iso.sublist(i * 2048, (i + 1) * 2048),
        packed = ZLibEncoder(raw: true).convert(block),
        raw = packed.length >= 2048;
    d.setUint32(24 + i * 4, at | (raw ? 0x80000000 : 0), Endian.little);
    final data = raw ? block : packed;
    out.add(data);
    at += data.length;
  }
  d.setUint32(24 + sectors * 4, at, Endian.little);
  return Uint8List.fromList([...head, ...out.takeBytes()]);
}

void main() {
  test('Sony metadata rejects out-of-range key tables and unterminated keys as format failures', () {
    for (final change in [
      (ByteData d) => d.setUint32(8, 0xffffffff, Endian.little),
      (ByteData d) => d.setUint16(20, 0xffff, Endian.little),
      (ByteData d) => d.setUint32(12, 0xffffffff, Endian.little),
    ]) {
      final b = pspSfo();
      change(ByteData.sublistView(b));
      expect(() => parseSonySfo(b, label: 'PSP'), throwsFormatException);
    }
    final b = pspSfo(), d = ByteData.sublistView(b);
    b.fillRange(
      d.getUint32(8, Endian.little),
      d.getUint32(12, Endian.little),
      65,
    );
    expect(() => parseSonySfo(b), throwsFormatException);
  });
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('broomm-psp-'),
  );
  tearDown(() async => root.delete(recursive: true));
  test(
    'PSP identities agree across native ISO, mixed raw/deflated CSO and PBP',
    () async {
      for (final e in {
        'game.iso': pspIso(),
        'game.cso': _cso(pspIso()),
        'EBOOT.PBP': pspPbp(),
      }.entries) {
        final f = File('${root.path}/${e.key}');
        await f.writeAsBytes(e.value);
        expect((await pspGameMetadata(f.path))['DISC_ID'], 'ULUS10340');
      }
    },
  );
  test('PSP parser rejects unrelated SFO identity, damaged index ranges and unsupported codecs', () async {
    final f = File('${root.path}/game.cso');
    await f.writeAsBytes(_cso(pspIso())..[20] = 2);
    await expectLater(pspGameMetadata(f.path), throwsFormatException);
    final b = _cso(pspIso());
    ByteData.sublistView(b).setUint32(24 + 16 * 4, 1, Endian.little);
    await f.writeAsBytes(b);
    await expectLater(pspGameMetadata(f.path), throwsFormatException);
    final pbp = File('${root.path}/game.pbp');
    await pbp.writeAsBytes(pspPbp(id: '../../bad'));
    await expectLater(pspGameMetadata(pbp.path), throwsFormatException);
  });
  test('PSP CSO sector expansion is bounded and malformed native offsets cannot select files', () async {
    final f = File('${root.path}/game.pbp'), b = pspPbp();
    ByteData.sublistView(b).setUint32(12, 0xffffffff, Endian.little);
    await f.writeAsBytes(b);
    await expectLater(pspGameMetadata(f.path), throwsFormatException);
    await f.writeAsBytes([0, 80, 66, 80]);
    await expectLater(pspGameMetadata(f.path), throwsFormatException);
    expect(
      () => pspContentPath('SAVEDATA/ULES00001/DATA.BIN', 'ULUS10340'),
      throwsFormatException,
    );
    expect(
      () => pspContentPath('GAME/ULUS10340/../../keys', 'ULUS10340'),
      throwsFormatException,
    );
  });
  Future<PreparedEmulator> prepared() async {
    final b = TestedBuild({
      'id': 'ppsspp',
      'name': 'PPSSPP',
      'host': 'macos-arm64',
      'version': 'test',
      'bundle': 'test.app',
      'executable': 'test',
      'sha256': 'a' * 64,
      'sdl': 2,
      'native': <String, String>{},
    });
    final p = await prepareManagedProfile(
      root,
      'a' * 32,
      b,
      Directory('${root.path}/release'),
    );
    return PreparedEmulator('PPSSPP', p.path, 'unused', 2, null, null);
  }

  test('PSP adapter preserves rendering settings and pins only its owned single controller map', () async {
    final e = await prepared(), ini = File('${e.user}/PSP/SYSTEM/ppsspp.ini');
    await ini.writeAsString(
      '[Graphics]\nRenderingMode=1\nInternalResolution=3\n',
    );
    final rom = File('${root.path}/game.pbp');
    await rom.writeAsBytes(pspPbp());
    final game = LaunchGame(
      '42',
      'PSP',
      'psp',
      'PPSSPP',
      rom.path,
      1,
      0,
      target: ControllerTarget.psp,
    );
    expect(await const PpssppAdapter().prepare(e, game, rom.path, 0), [
      '--windowed',
      '--pause-menu-exit',
      rom.path,
    ]);
    expect(await ini.readAsString(), contains('InternalResolution=3'));
    final controls = await File('${e.user}/PSP/SYSTEM/controls.ini')
        .readAsString();
    expect(controls, contains('Cross = 10-189'));
    expect(controls, contains('L = 10-193'));
    expect(controls, isNot(contains('11-')));
    expect(game.controllerTarget, ControllerTarget.psp);
    expect(playablePlatforms.where((p) => p.slug == 'psp').single.players, 1);
  });
  test('PSP native save ZIP excludes static DLC, other titles and incompatible state versions', () async {
    final e = await prepared(), rom = File('${root.path}/game.pbp');
    await rom.writeAsBytes(pspPbp());
    final payload = await Directory('${root.path}/payload').create(),
        dlc = await addonFile(
          payload,
          'PSP/SAVEDATA/ULUS10340DLC/content.bin',
          createParents: true,
        );
    await dlc.writeAsBytes([1, 2, 3]);
    final packages = PackageProfile(Directory(e.root), 'psp');
    await packages.apply('${'b' * 32}/42', payload, {
      'PSP/SAVEDATA/ULUS10340DLC/content.bin': {
        'version': 1,
        'files': {'': await progressFileHash(dlc)},
      },
    });
    final layout = await gameProgressLayout(
      ResolvedSession(e, rom.path, 'c' * 64, {}),
      'psp',
    );
    final save = await layout.target('save/ULUS10340DATA00/DATA.BIN');
    await save.writeAsBytes([4, 5, 6]);
    for (final path in [
      'ULUS99999DATA00/DATA.BIN',
      'ULUS10340DLC/progress.bin',
    ]) {
      final f = File('${e.user}/PSP/SAVEDATA/$path');
      await f.parent.create(recursive: true);
      await f.writeAsBytes([7]);
    }
    for (final name in [
      'ULUS10340_1.02_0.ppst',
      'ULUS10340_1.00_0.ppst',
      'load_undo.ppst',
    ]) {
      await File('${e.user}/PSP/PPSSPP_STATE/$name').writeAsBytes([8]);
    }
    final store = ProgressStore(Directory('${root.path}/store'), layout, 42, 3),
        snapshot = await store.capture();
    expect(snapshot.entries.keys.where((k) => k.startsWith('save/')).toSet(), {
      'save/ULUS10340DATA00/DATA.BIN',
      'save/ULUS10340DLC/progress.bin',
    });
    expect(
      snapshot.entries.keys.where((k) => !k.startsWith('save/')),
      hasLength(1),
    );
    final exported = await store.exportNative(snapshot);
    try {
      expect(exported.extension, 'zip');
      expect(
        (await store.importNative(exported.file)).ordinaryDigest,
        snapshot.ordinaryDigest,
      );
    } finally {
      await exported.close();
    }
    await packages.remove('${'b' * 32}/42');
    expect(
      await File('${e.user}/PSP/SAVEDATA/ULUS10340DLC/content.bin').exists(),
      false,
    );
    expect(await save.readAsBytes(), [4, 5, 6]);
    expect(
      await File('${e.user}/PSP/SAVEDATA/ULUS10340DLC/progress.bin').exists(),
      true,
    );
  });
  test('PSP content transaction completes recovery and retains an untracked preimage for uninstall', () async {
    final e = await prepared(),
        p = Directory(e.root),
        payload = await Directory('${root.path}/payload').create(),
        path = 'PSP/GAME/ULUS10340/extra.bin',
        file = await addonFile(payload, path, createParents: true);
    await file.writeAsBytes([1]);
    final target = await addonFile(
      Directory(e.user),
      path,
      createParents: true,
    );
    await target.writeAsBytes([2]);
    final units = {
      path: {
        'version': 1,
        'files': {'': await progressFileHash(file)},
      },
    };
    final packages = PackageProfile(
      p,
      'psp',
      checkpoint: (phase) {
        if (phase == 'backed-up') throw StateError('power loss');
      },
    );
    await expectLater(
      packages.apply('${'b' * 32}/42', payload, units),
      throwsStateError,
    );
    await PackageProfile(p, 'psp').recover();
    expect(await target.readAsBytes(), [1]);
    await PackageProfile(p, 'psp').remove('${'b' * 32}/42');
    expect(await target.readAsBytes(), [2]);
  });
}
