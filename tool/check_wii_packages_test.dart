@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:broomm/src/addons/package_import.dart';
import 'package:broomm/src/addons/wii.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter_test/flutter_test.dart';

// Apple SDK crypto is used only to generate a synthetic, unsigned test WAD.
// No emulator code, game content, console secrets or BIOS is in this fixture.
final _sys = DynamicLibrary.open('/usr/lib/libSystem.B.dylib');
final _alloc = _sys
    .lookupFunction<
      Pointer<Void> Function(IntPtr),
      Pointer<Void> Function(int)
    >('malloc');
final _free = _sys
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'free',
    );
final _crypt = _sys
    .lookupFunction<
      Int32 Function(
        Uint32,
        Uint32,
        Uint32,
        Pointer<Void>,
        IntPtr,
        Pointer<Void>,
        Pointer<Void>,
        IntPtr,
        Pointer<Void>,
        IntPtr,
        Pointer<IntPtr>,
      ),
      int Function(
        int,
        int,
        int,
        Pointer<Void>,
        int,
        Pointer<Void>,
        Pointer<Void>,
        int,
        Pointer<Void>,
        int,
        Pointer<IntPtr>,
      )
    >('CCCrypt');
final _sha1 = _sys
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Uint32, Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>, int, Pointer<Void>)
    >('CC_SHA1');

Uint8List _encrypt(List<int> input, List<int> key, List<int> iv) {
  final p = _alloc(input.length + key.length + 16 + input.length + 8)
      .cast<Uint8>();
  try {
    p.asTypedList(input.length).setAll(0, input);
    final k = p + input.length, v = k + key.length, out = v + 16;
    k.asTypedList(key.length).setAll(0, key);
    v.asTypedList(16).setAll(0, iv);
    final count = (out + input.length).cast<IntPtr>();
    expect(
      _crypt(
        0,
        0,
        0,
        k.cast(),
        key.length,
        v.cast(),
        p.cast(),
        input.length,
        out.cast(),
        input.length,
        count,
      ),
      0,
    );
    return Uint8List.fromList(out.asTypedList(count.value));
  } finally {
    _free(p.cast());
  }
}

Uint8List _digest(List<int> input) {
  final p = _alloc(input.length + 20).cast<Uint8>();
  try {
    p.asTypedList(input.length).setAll(0, input);
    _sha1(p.cast(), input.length, (p + input.length).cast());
    return Uint8List.fromList((p + input.length).asTypedList(20));
  } finally {
    _free(p.cast());
  }
}

Future<Uint8List> syntheticWad({int version = 1}) async {
  final clear = utf8.encode('Broomm private native WAD fixture.');
  final content = Uint8List((clear.length + 15) & ~15)..setAll(0, clear);
  const title = 0x00010005735a4145;
  final titleBytes = Uint8List(16);
  ByteData.sublistView(titleBytes).setUint64(0, title);
  final common = [
    for (var i = 0; i < 32; i += 2)
      int.parse(
        'ebe42a225e8593e448d9c5457381aaf7'.substring(i, i + 2),
        radix: 16,
      ),
  ];
  final key = Uint8List(16);
  final bytes = Uint8List(0x580), d = ByteData(0x580);
  d.setUint32(0, 0x20);
  d.setUint16(4, 0x4973);
  d.setUint32(16, 0x2a4);
  d.setUint32(20, 0x208);
  d.setUint32(24, 64);
  d.setUint32(0x40, 0x10001);
  d.setUint64(0x40 + 0x140 + 0x9c, title);
  d.setUint32(0x300, 0x10001);
  d.setUint64(0x300 + 0x140 + 0x4c, title);
  d.setUint16(0x300 + 0x140 + 0x58, 0x3031);
  d.setUint16(0x300 + 0x140 + 0x9c, version);
  d.setUint16(0x300 + 0x140 + 0x9e, 1);
  d.setUint32(0x300 + 0x1e4, 1);
  d.setUint16(0x300 + 0x1e4 + 6, 1);
  d.setUint64(0x300 + 0x1e4 + 8, clear.length);
  bytes.setAll(0, d.buffer.asUint8List());
  bytes.setAll(0x40 + 0x140, ascii.encode('Root-CA00000001-XS00000003'));
  bytes.setAll(0x300 + 0x140, ascii.encode('Root-CA00000001-CP00000004'));
  bytes.setAll(0x40 + 0x140 + 0x7f, _encrypt(key, common, titleBytes));
  bytes.setAll(0x300 + 0x1e4 + 16, _digest(clear));
  bytes.setAll(0x540, _encrypt(content, key, Uint8List(16)));
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pinned Dolphin imports synthetic WAD privately and confirms native contents', () async {
    final root = await Directory('.tool-cache/research/ra-wii-switch')
        .createTemp('native-wii-');
    final stage = Directory('${root.path}/native');
    await stage.create();
    final input = File('${root.path}/test.wad');
    await input.writeAsBytes(await syntheticWad());
    final lease = await SessionLease.acquire(root);
    try {
      final title = await readWiiWad(input.path);
      expect(title.title, '00010005735a4145');
      final manager = ManagedEmulators(
        Directory('broomm-data'),
        asset: (p) => File(p).readAsString(),
      );
      await manager.load();
      final build = manager.buildFor('Dolphin')!;
      final exe =
          '${manager.root.path}/${build.id}/${build.hash}/${build.bundle}/${build.executable}';
      await manager.verifyBundle(
        build,
        '${manager.root.path}/${build.id}/${build.hash}/${build.bundle}',
        DownloadCancellation(),
      );
      await importWiiWad(
        exe,
        input.absolute.path,
        stage,
        root,
        DownloadCancellation(),
      );
      final native = File(
        '${stage.path}/user/Wii/title/00010005/735a4145/content/00000001.app',
      );
      expect(await native.readAsString(), 'Broomm private native WAD fixture.');
      expect(
        await File('${stage.path}/user/Wii/ticket/00010005/735a4145.tik')
            .exists(),
        true,
      );
      await File('${root.path}/result.json').writeAsString(
        jsonEncode({
          'host': 'macos-arm64',
          'dolphin': build.version,
          'executable': build.hash,
          'nativeImport': true,
          'payloadRoundTrip': true,
          'ownerProfilesChanged': false,
        }),
      );
      manager.dispose();
    } finally {
      await lease.release();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
