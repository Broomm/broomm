@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Info extends Struct {
  external Pointer<Uint8> name;
  external Pointer<Uint8> version;
  external Pointer<Uint8> extensions;
  @Bool()
  external bool fullPath;
  @Bool()
  external bool blockExtract;
}

String _text(Pointer<Uint8> p) {
  final bytes = <int>[];
  for (var i = 0; i < 8192 && p[i] != 0; i++) {
    bytes.add(p[i]);
  }
  return utf8.decode(bytes);
}

void main() {
  final system = DynamicLibrary.open('/usr/lib/libSystem.B.dylib');
  final alloc = system
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc');
  final free = system
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  test('all pinned expansion cores load their real native ABI and report media contracts', () async {
    final root = await Directory('.tool-cache/research/ra-wii-switch')
        .createTemp('native-public-abi-');
    final manager = ManagedEmulators(
      Directory('${root.path}/data'),
      asset: (p) => File(p).readAsString(),
    );
    addTearDown(manager.dispose);
    await manager.install(await manager.readPlan(only: {'retroarch'}));
    expect(manager.error, isNull, reason: manager.error);
    final j = jsonDecode(
      await File('assets/setup/retroarch-cores.json').readAsString(),
    ) as Map;
    final report = <Map>[];
    for (final core in (j['cores'] as List).cast<Map>()) {
      final path = File(
        '${manager.root.path}/retroarch/${manager.buildFor('RetroArch')!.hash}/cores/${core['id']}-${core['sha256']}/core.dylib',
      ).absolute.path;
      expect(await sha256File(path), core['sha256']);
      final lib = DynamicLibrary.open(path);
      expect(
        lib.lookupFunction<Uint32 Function(), int Function()>(
          'retro_api_version',
        )(),
        1,
      );
      final pointer = alloc(sizeOf<_Info>()).cast<_Info>();
      try {
        lib.lookupFunction<
          Void Function(Pointer<_Info>),
          void Function(Pointer<_Info>)
        >('retro_get_system_info')(pointer);
        final info = pointer.ref;
        expect(_text(info.name), isNotEmpty);
        expect(_text(info.extensions), isNotEmpty);
        report.add({
          'id': core['id'],
          'sha256': core['sha256'],
          'name': _text(info.name),
          'version': _text(info.version),
          'extensions': _text(info.extensions),
          'fullPath': info.fullPath,
          'blockExtract': info.blockExtract,
        });
      } finally {
        free(pointer.cast());
      }
    }
    await File('.tool-cache/research/ra-wii-switch/native-cores.json')
        .writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        );
  });
}
