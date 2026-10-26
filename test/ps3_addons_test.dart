import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/addons/ps3.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:broomm/src/session_lease.dart';

import 'support/addon_fixtures.dart'
    show AddonFiles, addonServer, addonProfile, secondAddonProfile;

const serial = 'BLUS31183';
Uint8List ps3Sfo({String id = serial, String version = '01.04'}) {
  final fields = {'TITLE_ID': id, 'APP_VER': version};
  final keys = BytesBuilder(), values = BytesBuilder();
  final entries = <List<int>>[];
  for (final e in fields.entries) {
    final k = keys.length, v = values.length;
    keys.add([...ascii.encode(e.key), 0]);
    final value = [...ascii.encode(e.value), 0];
    values.add(value);
    entries.add([k, v, value.length]);
  }
  final keyStart = 20 + 16 * fields.length, valueStart = keyStart + keys.length;
  final b = Uint8List(valueStart + values.length), d = ByteData.sublistView(b);
  d.setUint32(0, 0x00505346);
  d.setUint32(4, 0x101, Endian.little);
  d.setUint32(8, keyStart, Endian.little);
  d.setUint32(12, valueStart, Endian.little);
  d.setUint32(16, fields.length, Endian.little);
  for (var i = 0; i < entries.length; i++) {
    final p = 20 + 16 * i, e = entries[i];
    d.setUint16(p, e[0], Endian.little);
    d.setUint16(p + 2, 0x204, Endian.little);
    d.setUint32(p + 4, e[2], Endian.little);
    d.setUint32(p + 8, e[2], Endian.little);
    d.setUint32(p + 12, e[1], Endian.little);
  }
  b.setRange(keyStart, valueStart, keys.takeBytes());
  b.setRange(valueStart, b.length, values.takeBytes());
  return b;
}

Uint8List ps3Package({String id = serial, int value = 1}) {
  final b = Uint8List(256);
  b.setRange(0, 4, [0x7f, 80, 75, 71]);
  final content = ascii.encode('UP0001-${id}_00-TESTCONTENT00001');
  b.setRange(0x30, 0x30 + content.length, content);
  b.last = value;
  return b;
}

Future<RommGame> ps3Game(
  Map<String, List<int>> payloads, {
  int id = 42,
}) async => RommGame(
  id: id,
  name: 'PS3 fixture',
  platformId: 11,
  platform: 'PlayStation 3',
  platformSlug: 'ps3',
  fullPath: 'roms/ps3/$id',
  files: [
    for (final (i, e) in payloads.entries.indexed)
      RommFile(
        id: 10 + i,
        romId: id,
        name: e.key.split('/').last,
        fullPath: 'roms/ps3/$id/${e.key}',
        bytes: e.value.length,
        crc: ((ProgressCrc()..add(e.value)).value)
            .toRadixString(16)
            .padLeft(8, '0'),
      ),
  ],
);

class PkgFixture {
  PkgFixture(this.root);
  final Directory root;
  int imports = 0;
  bool fail = false;
  Future<(String, Directory)> prepare(String id, DownloadCancellation c) async {
    final profile = Directory('${root.path}/profiles/$id/emulators/rpcs3');
    await profile.create(recursive: true);
    await File('${profile.path}/profile.json').writeAsString(
      jsonEncode({'version': 1, 'profile': id, 'emulator': 'rpcs3'}),
    );
    await Directory('${profile.path}/portable').create();
    return ('fixture-executable', profile);
  }

  Future<Directory> install(
    String executable,
    String input,
    Directory stage,
    DownloadCancellation c, {
    required bool firmware,
    required Directory data,
  }) async {
    imports++;
    if (fail) throw StateError('Controlled importer failure');
    final user = Directory(
      '${stage.path}/home/Library/Application Support/rpcs3',
    );
    final game = Directory('${user.path}/dev_hdd0/game/$serial');
    await Directory('${game.path}/USRDIR').create(recursive: true);
    await File('${game.path}/PARAM.SFO').writeAsBytes(ps3Sfo());
    await File('${game.path}/USRDIR/${File(input).uri.pathSegments.last}.bin')
        .writeAsBytes(await File(input).readAsBytes());
    return user;
  }
}

void main() {
  late Directory root;
  late GameLibrary library;
  late Ps3Addons addons;
  late PkgFixture native;
  late AddonFiles client;
  late InstalledGame entry;
  late RommGame remote;
  final base = <String, List<int>>{
    'PS3_GAME/PARAM.SFO': ps3Sfo(),
    'PS3_GAME/USRDIR/EBOOT.BIN': [1, 2, 3],
  };
  Future<void> setup() async {
    root = await Directory.systemTemp.createTemp('broomm-ps3-addons-');
    library = GameLibrary(root);
    native = PkgFixture(root);
    final game = await ps3Game(base);
    client = AddonFiles({
      for (final e in base.entries) '${game.fullPath}/${e.key}': e.value,
    })..detail = game;
    entry = await library.install(
      serverId: addonServer,
      userId: 7,
      game: game,
      client: client,
      cancellation: DownloadCancellation(),
      progress: (_) {},
    );
    client.downloads.clear();
    final available = {
      ...base,
      'updates/01.04.pkg': ps3Package(),
      'dlc/Pack.pkg': ps3Package(value: 2),
    };
    remote = await ps3Game(available);
    client.payloads.addAll({
      for (final e in available.entries) '${remote.fullPath}/${e.key}': e.value,
    });
    addons = Ps3Addons(
      root,
      library,
      prepare: native.prepare,
      importer: native.install,
    );
  }

  Future<void> sync() async {
    await addons.sync(
      serverId: addonServer,
      profileId: addonProfile,
      entry: entry,
      game: remote,
      client: client,
      cancellation: DownloadCancellation(),
      progress: (_) {},
    );
  }

  File installed([String p = addonProfile]) => File(
    '${root.path}/profiles/$p/emulators/rpcs3/portable/dev_hdd0/game/$serial/USRDIR/12.pkg.bin',
  );
  setUp(setup);
  tearDown(() async {
    client.close();
    await root.delete(recursive: true);
  });
  test('PS3 downloads only add-ons, reuses verified content, repairs native files and removes content from every profile while keeping saves', () async {
    await sync();
    expect(native.imports, 2);
    expect(client.downloads.every((p) => p.endsWith('.pkg')), true);
    expect(await installed().exists(), true);
    final save = File(
      '${root.path}/profiles/$addonProfile/emulators/rpcs3/portable/dev_hdd0/home/00000001/savedata/${serial}DATA/progress',
    );
    await save.parent.create(recursive: true);
    await save.writeAsString('progress');
    await sync();
    expect(native.imports, 2);
    expect(client.downloads.length, 2);
    await installed().delete();
    await sync();
    expect(await installed().exists(), true);
    expect(native.imports, 2);
    final lease = await SessionLease.acquire(root);
    try {
      await addons.applyForLaunch(addonServer, 42, secondAddonProfile);
    } finally {
      await lease.release();
    }
    expect(await installed(secondAddonProfile).exists(), true);
    await library.remove(
      addonServer,
      42,
      uninstallAddons: () => addons.uninstall(addonServer, 42),
    );
    expect(await installed().exists(), false);
    expect(await installed(secondAddonProfile).exists(), false);
    expect(await save.readAsString(), 'progress');
  });
  test('foreign PS3 package IDs are rejected before import while game-created data can coexist with legitimate packages', () async {
    final payload = {...base, 'dlc/Foreign.pkg': ps3Package(id: 'BLES01863')};
    remote = await ps3Game(payload);
    client.payloads.addAll({
      for (final e in payload.entries) '${remote.fullPath}/${e.key}': e.value,
    });
    await expectLater(sync(), throwsA(isA<RommFailure>()));
    expect(native.imports, 0);
    final valid = {...base, 'dlc/Foreign.pkg': ps3Package()};
    remote = await ps3Game(valid);
    client.payloads.addAll({
      for (final e in valid.entries) '${remote.fullPath}/${e.key}': e.value,
    });
    final foreign = File('${installed().parent.path}/manual.bin');
    await foreign.parent.create(recursive: true);
    await foreign.writeAsString('manual');
    await sync();
    expect(await foreign.readAsString(), 'manual');
    expect(await installed().exists(), true);
    await addons.uninstall(addonServer, 42);
    expect(await foreign.readAsString(), 'manual');
  });

  test('overlapping native metadata is retained durably, package updates preserve new game data, and uninstall restores original bytes', () async {
    final dir = installed().parent.parent;
    await dir.create(recursive: true);
    final metadata = File('${dir.path}/PARAM.SFO');
    final original = ps3Sfo(version: '01.00');
    await metadata.writeAsBytes(original);
    final data = File('${dir.path}/USRDIR/game-created.db');
    await data.parent.create(recursive: true);
    await data.writeAsString('native installation data');
    await sync();
    expect(await metadata.readAsBytes(), ps3Sfo());
    final later = File('${dir.path}/USRDIR/new-game-file');
    await later.writeAsString('written during play');
    await sync();
    expect(await data.readAsString(), 'native installation data');
    await addons.uninstall(addonServer, 42);
    expect(await metadata.readAsBytes(), original);
    expect(await data.readAsString(), 'native installation data');
    expect(await later.readAsString(), 'written during play');
    expect(await installed().exists(), false);
  });

  test('interrupted file publication resumes after legacy ownership migration without claiming unrelated files', () async {
    await sync();
    final profile = Directory(
      '${root.path}/profiles/$addonProfile/emulators/rpcs3',
    );
    final current = File('${profile.path}/addons.json');
    final files =
        (jsonDecode(await current.readAsString()) as Map)['files'] as Map;
    final legacyFiles = <String, String>{};
    for (final e in files.entries) {
      if ((e.key as String).startsWith('dev_hdd0/game/$serial/'))
        legacyFiles[(e.key as String).substring(
              'dev_hdd0/game/$serial/'.length,
            )] =
            e.value['hash'] as String;
    }
    await current.writeAsString(
      jsonEncode({
        'version': 1,
        'units': {
          'dev_hdd0/game/$serial': {
            'version': 104,
            'owners': ['$addonServer/42'],
            'files': legacyFiles,
          },
        },
      }),
    );
    final nativeFile = File('${installed().parent.path}/native-only');
    await nativeFile.writeAsString('keep');
    await installed().delete();
    var stopped = false;
    addons = Ps3Addons(
      root,
      library,
      prepare: native.prepare,
      importer: native.install,
      checkpoint: (phase) {
        if (phase == 'published' && !stopped) {
          stopped = true;
          throw StateError('interrupted publication');
        }
      },
    );
    await expectLater(sync(), throwsStateError);
    await sync();
    expect(await installed().exists(), true);
    await addons.uninstall(addonServer, 42);
    expect(await nativeFile.readAsString(), 'keep');
  });
  test('an installer failure retains the base game and previous add-ons; the production session lease excludes new effects', () async {
    await sync();
    final before = await installed().readAsBytes();
    native.fail = true;
    final changed = {
      ...base,
      'updates/01.04.pkg': ps3Package(value: 8),
      'dlc/Pack.pkg': ps3Package(value: 2),
    };
    remote = await ps3Game(changed);
    client.payloads.addAll({
      for (final e in changed.entries) '${remote.fullPath}/${e.key}': e.value,
    });
    await expectLater(sync(), throwsStateError);
    expect(await installed().readAsBytes(), before);
    expect(await entry.directory.exists(), true);
    final count = client.downloads.length,
        lease = await SessionLease.acquire(root);
    try {
      await expectLater(sync(), throwsStateError);
      expect(client.downloads.length, count);
    } finally {
      await lease.release();
    }
  });

  test('metadata recovery preserves the original across interruption and refuses to discard unrecognized transaction files', () async {
    final metadata = File('${installed().parent.parent.path}/PARAM.SFO');
    await metadata.parent.create(recursive: true);
    final original = ps3Sfo(version: '01.00');
    await metadata.writeAsBytes(original);
    var interrupted = false;
    addons = Ps3Addons(
      root,
      library,
      prepare: native.prepare,
      importer: native.install,
      checkpoint: (phase) {
        if (phase == 'backed-up' && !interrupted) {
          interrupted = true;
          throw StateError('Interrupted metadata replacement');
        }
      },
    );
    await expectLater(sync(), throwsStateError);
    final unknown = File(
      '${root.path}/profiles/$addonProfile/emulators/rpcs3/.ps3-addon-transaction/unknown',
    );
    await unknown.writeAsString('unrecognized recovery data');
    await expectLater(sync(), throwsA(isA<FileSystemException>()));
    expect(await unknown.readAsString(), 'unrecognized recovery data');
    await unknown.delete();
    await sync();
    await addons.uninstall(addonServer, 42);
    expect(await metadata.readAsBytes(), original);
  });

  test('externally changed owned package files block removal without losing the change or native game data', () async {
    await sync();
    final metadata = File('${installed().parent.parent.path}/PARAM.SFO');
    final before = await metadata.readAsBytes();
    await installed().writeAsString('changed outside Broomm');
    await expectLater(
      addons.uninstall(addonServer, 42),
      throwsA(isA<FileSystemException>()),
    );
    expect(await installed().readAsString(), 'changed outside Broomm');
    expect(await metadata.readAsBytes(), before);
  });
  test('PS3 deletion can resume after a generation and its inner manifest are gone', () async {
    await sync();
    var failed = false;
    addons = Ps3Addons(
      root,
      library,
      prepare: native.prepare,
      importer: native.install,
      checkpoint: (phase) {
        if (phase == 'ps3-generation-removed' && !failed) {
          failed = true;
          throw StateError('Interrupted retirement');
        }
      },
    );
    await expectLater(
      library.remove(
        addonServer,
        42,
        uninstallAddons: () => addons.uninstall(addonServer, 42),
      ),
      throwsStateError,
    );
    expect(
      await File('${root.path}/addons-ps3/$addonServer/42/deleting.json')
          .exists(),
      true,
    );
    await library.remove(
      addonServer,
      42,
      uninstallAddons: () => addons.uninstall(addonServer, 42),
    );
    expect(await entry.directory.exists(), false);
    expect(await installed().exists(), false);
  });
}
