import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broomm/src/addons/files.dart';
import 'package:broomm/src/addons/three_ds.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/shell/library.dart';

const addonServer = '0123456789abcdef0123456789abcdef';
const addonProfile = 'abcdef0123456789abcdef0123456789';
const secondAddonProfile = 'bbcdef0123456789abcdef0123456789';
const baseTitle = '00040000000edf00';
const dlcTitle = '0004008c000edf00';
const updateTitle = '0004000e000edf00';

Uint8List base3ds({String id = baseTitle, bool ncsd = false}) {
  final bytes = Uint8List(ncsd ? 0x400 : 0x200);
  final d = ByteData.sublistView(bytes);
  var offset = 0;
  if (ncsd) {
    d.setUint32(0x100, 0x4e435344);
    d.setUint32(0x120, 1, Endian.little);
    d.setUint32(0x124, 1, Endian.little);
    offset = 0x200;
  }
  d.setUint32(offset + 0x100, 0x4e434348);
  d.setUint64(offset + 0x118, int.parse(id, radix: 16), Endian.little);
  return bytes;
}

Uint8List titleMetadata(String id, int version) {
  final bytes = Uint8List(0x140 + 0x9c4 + 0x30);
  final d = ByteData.sublistView(bytes);
  d.setUint32(0, 0x10004);
  d.setUint64(0x140 + 0x4c, int.parse(id, radix: 16));
  d.setUint16(0x140 + 0x9c, version);
  d.setUint16(0x140 + 0x9e, 1);
  return bytes;
}

Uint8List addonCia({String id = dlcTitle, int version = 1}) {
  final tmd = titleMetadata(id, version);
  final bytes = Uint8List(0x2040 + tmd.length);
  final d = ByteData.sublistView(bytes);
  d.setUint32(0, 0x2020, Endian.little);
  d.setUint32(16, tmd.length, Endian.little);
  bytes.setRange(0x2040, bytes.length, tmd);
  return bytes;
}

class AddonFiles extends RommClient {
  AddonFiles(this.payloads) : super(Uri.parse('https://fixture.example'));
  final Map<String, List<int>> payloads;
  final downloads = <String>[];
  RommGame? detail;
  Object? problem;
  void Function(DownloadCancellation)? onDownload;
  @override
  Future<RommGame> game(int id) async {
    if (problem != null) throw problem!;
    return detail!;
  }

  @override
  Future<void> downloadFile(
    RommFile f,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    onDownload?.call(cancellation);
    cancellation.check();
    downloads.add(f.fullPath);
    await destination.writeAsBytes(payloads[f.fullPath]!, flush: true);
    onProgress(payloads[f.fullPath]!.length);
  }
}

Future<RommGame> addonGame(
  Directory scratch,
  Map<String, List<int>> files, {
  int id = 18,
  Map<String, String> categories = const {},
}) async {
  final manifest = <RommFile>[];
  var index = 10;
  for (final e in files.entries) {
    final tmp = File('${scratch.path}/checksum-$index');
    await tmp.writeAsBytes(e.value);
    manifest.add(
      RommFile(
        id: index++,
        romId: id,
        name: e.key.split('/').last,
        fullPath: 'roms/3ds/Smash/$id/${e.key}',
        bytes: e.value.length,
        category: categories[e.key],
        crc: await rawCrc32(tmp.path),
      ),
    );
    await tmp.delete();
  }
  return RommGame(
    id: id,
    name: 'Smash Bros.',
    platformId: 3,
    platform: 'Nintendo 3DS',
    platformSlug: '3ds',
    fullPath: 'roms/3ds/Smash/$id',
    fsName: 'Smash',
    files: manifest,
  );
}

AddonFiles filesClient(RommGame game, Map<String, List<int>> files) =>
    AddonFiles({
      for (final e in files.entries) '${game.fullPath}/${e.key}': e.value,
    })..detail = game;

Future<(String, Directory)> addonRuntime(
  Directory data,
  String id,
  DownloadCancellation _,
) async {
  final dir = Directory('${data.path}/profiles/$id/emulators/azahar');
  await Directory('${azaharUserPath(dir.path)}/config').create(recursive: true);
  await File('${dir.path}/profile.json').writeAsString(
    jsonEncode({'version': 1, 'profile': id, 'emulator': 'azahar'}),
  );
  await File('${azaharUserPath(dir.path)}/config/qt-config.ini')
      .writeAsString('[Data%20Storage]\nuse_custom_storage=false\n');
  return ('/fixture/azahar', dir);
}

class FakeCiaImport {
  final imported = <ThreeDsTitle>[];
  bool fail = false;
  Future<void> Function(DownloadCancellation)? beforeFinish;
  Future<void> call(
    String executable,
    String cia,
    Directory stage,
    DownloadCancellation cancellation,
  ) async {
    final title = await readCiaTitle(cia);
    imported.add(title);
    final root = azaharUserPath(stage.path);
    final content = Directory('$root/${titleContentPath(title.id)}');
    await content.create(recursive: true);
    await File('${content.path}/00000000.tmd')
        .writeAsBytes(titleMetadata(title.id, title.version));
    await File('${content.path}/00000000.app')
        .writeAsString('${title.id}:${title.version}');
    final ticket = File(
      '$root/nand/dbs/ticket.db/${title.id.toUpperCase()}.0000000000000001.tik',
    );
    await ticket.parent.create(recursive: true);
    await ticket.writeAsString(title.id);
    await beforeFinish?.call(cancellation);
    if (fail)
      throw const RommFailure(
        'Fixture: native importer failed after writing staged data',
      );
  }
}
