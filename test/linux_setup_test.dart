@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:broomm/src/linux_runtime.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/managed_profile.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/setup/archive.dart';
import 'package:broomm/src/setup/linux_identity.dart';
import 'package:broomm/src/progress/zip.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List elf({int machine = 62}) => Uint8List(64)
  ..setRange(0, 6, [0x7f, 69, 76, 70, 2, 1])
  ..[16] = 3
  ..[18] = machine;

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-linux-');
  });
  tearDown(() => root.delete(recursive: true));
  PreparedEmulator eden() => PreparedEmulator(
    'Eden',
    '/private/eden',
    '/managed/shared/bin/eden',
    2,
    null,
    null,
    linuxLauncher: '/managed/bin/eden',
  );
  test('Eden uses child-only XWayland when an X11 display is available, retaining its private loader context', () {
    final parent = {'DISPLAY': ':99', 'QT_QPA_PLATFORM': 'wayland'};
    final child = linuxLaunchEnvironment(eden(), environment: parent);
    expect(child['QT_QPA_PLATFORM'], 'xcb');
    expect(child['SHARUN_WORKING_DIR'], '/private/eden/home');
    expect(child['SHARUN_ALLOW_LD_PRELOAD'], '1');
    expect(parent, {'DISPLAY': ':99', 'QT_QPA_PLATFORM': 'wayland'});
  });
  test('Wayland-only hosts do not receive an unusable forced X11 backend', () {
    for (final parent in <Map<String, String>>[
      {},
      {'WAYLAND_DISPLAY': 'wayland-0'},
      {'DISPLAY': ''},
    ]) {
      expect(
        linuxLaunchEnvironment(eden(), environment: parent),
        isNot(contains('QT_QPA_PLATFORM')),
      );
    }
  });
  test(
    'the Eden graphics workaround does not change other emulator backends',
    () {
      for (final name in [
        'Dolphin',
        'Azahar',
        'PPSSPP',
        'DuckStation',
        'RetroArch',
      ]) {
        final e = PreparedEmulator(
          name,
          '/private/profile',
          '/managed/bin/emulator',
          2,
          '/managed/lib/SDL.so',
          null,
          linuxLauncher: name == 'PPSSPP' ? '/managed/launcher' : null,
        );
        expect(
          linuxLaunchEnvironment(e, environment: {'DISPLAY': ':99'}),
          isNot(contains('QT_QPA_PLATFORM')),
        );
      }
    },
  );
  test('Eden launches away from its generic portable user folder while keeping its private XDG data and preload', () {
    final e = PreparedEmulator(
      'Eden',
      '/private/profile with spaces',
      '/managed/shared/bin/eden',
      2,
      null,
      null,
      linuxLauncher: '/managed/bin/eden',
    );
    expect(linuxLaunchDirectory(e), '/private/profile with spaces/home');
    expect(
      linuxLaunchEnvironment(e)['SHARUN_WORKING_DIR'],
      linuxLaunchDirectory(e),
    );
    expect(
      File.fromUri(
        Directory('${linuxLaunchDirectory(e)}/').uri
            .resolve(linuxLaunchPreload(e, './.broomm-runtime/bridge.so')),
      ).path,
      '/private/profile with spaces/.broomm-runtime/bridge.so',
    );
    final psp = PreparedEmulator(
      'PPSSPP',
      '/private/psp',
      '/managed/shared/bin/PPSSPPSDL',
      2,
      null,
      null,
      linuxLauncher: '/managed/bin/PPSSPPSDL',
    );
    expect(linuxLaunchDirectory(psp), psp.root);
    expect(linuxLaunchEnvironment(psp)['SHARUN_WORKING_DIR'], psp.root);
    expect(linuxLaunchPreload(psp, './bridge.so'), './bridge.so');
  });
  test(
    'overlapping readiness observations share one durable publication',
    () async {
      final held = Completer<void>();
      var writes = 0;
      final gate = LinuxWindowReadiness(() {
        writes++;
        return held.future;
      });
      final first = gate.ready(), second = gate.ready();
      expect(identical(first, second), isTrue);
      expect(writes, 1);
      held.complete();
      await Future.wait([first, second]);
      await gate.ready();
      expect(writes, 1);
    },
  );
  test('failed readiness publication permits one later retry', () async {
    var writes = 0;
    final gate = LinuxWindowReadiness(() async {
      if (++writes == 1)
        throw const FileSystemException('held fixture failure');
    });
    await expectLater(gate.ready(), throwsA(isA<FileSystemException>()));
    await gate.ready();
    await gate.ready();
    expect(writes, 2);
  });
  test(
    'shutdown drains readiness publication and prevents late relaunch writes',
    () async {
      final held = Completer<void>();
      var writes = 0, closed = false;
      final gate = LinuxWindowReadiness(() {
        writes++;
        return held.future;
      });
      final publish = gate.ready(),
          closing = gate.close().then((_) {
            closed = true;
          });
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      await gate.ready();
      expect(writes, 1);
      held.complete();
      await Future.wait([publish, closing]);
      await gate.ready();
      expect(closed, isTrue);
      expect(writes, 1);
    },
  );
  test('Linux bundled setup selects reviewed ELF builds and never macOS addresses or file packs', () async {
    final manager = ManagedEmulators(
      Directory('${root.path}/data'),
      hostOverride: 'linux-x64',
      asset: (p) => File(p).readAsString(),
    );
    addTearDown(manager.dispose);
    final plan = await manager.readPlan();
    expect(plan.items.map((i) => i.build.id).toSet(), {
      'retroarch',
      'dolphin',
      'rpcs3',
      'azahar',
      'ryubing',
      'melonds',
      'duckstation',
      'pcsx2',
      'ppsspp',
      'eden',
    });
    expect(
      plan.items
          .expand((i) => i.downloads.values)
          .every((p) => p.url != null && p.file == null),
      isTrue,
    );
    final item = plan.items.firstWhere((i) => i.build.id == 'retroarch');
    expect(item.build.host, 'linux-x64');
    expect(item.build.native, isEmpty);
    expect(item.downloads.length, 16);
    expect(item.cores.length, 15);
    expect(item.core, isNull);
    expect(item.downloads.values.where((p) => p.rolling), hasLength(15));
    expect(
      item.downloads.values.every(
        (p) => p.url != null && p.file == null && p.format == 'zip',
      ),
      isTrue,
    );
    expect(await manager.data.exists(), isFalse);
    final unsupported = ManagedEmulators(
      manager.data,
      hostOverride: 'linux-riscv64',
      asset: manager.asset,
    );
    addTearDown(unsupported.dispose);
    await expectLater(unsupported.readPlan(), throwsUnsupportedError);
    expect(await manager.data.exists(), isFalse);
  });
  test('metadata cache rejects same-size replacements with restored mtime and allows fresh verified binding', () async {
    final file = await File('${root.path}/app').writeAsBytes(elf());
    await file.setLastModified(DateTime.utc(2020));
    final binding = await linuxTreeStamp(root, ['app']);
    await verifyLinuxStamp(root, ['app'], binding);
    final changed = elf()..[63] = 1;
    await file.writeAsBytes(changed);
    await file.setLastModified(DateTime.utc(2020));
    await expectLater(
      verifyLinuxStamp(root, ['app'], binding),
      throwsStateError,
    );
    await verifyLinuxStamp(root, ['app'], await linuxTreeStamp(root, ['app']));
    await file.rename('${root.path}/preserved');
    await Link(file.path).create('${root.path}/preserved');
    await expectLater(linuxFileStamp(file), throwsStateError);
    expect(await File('${root.path}/preserved').readAsBytes(), changed);
  });
  test('Linux ARM64 discovers the bundled RetroArch recipe and selects only the requested core', () async {
    final manager = ManagedEmulators(
      Directory('${root.path}/arm-data'),
      hostOverride: 'linux-arm64',
      asset: (p) => File(p).readAsString(),
    );
    addTearDown(manager.dispose);
    final plan = await manager.readPlan();
    final full = plan.items.single;
    expect(full.build.host, 'linux-arm64');
    expect(full.build.architecture, 'arm64');
    expect(full.downloads, hasLength(16));
    final nes = plan.forPlatform('nes').items.single;
    expect(nes.cores.keys, ['mesen']);
    expect(
      nes.downloads.values.map((p) => p.url!.path),
      everyElement(anyOf(contains('linux-arm64'), contains('/linux/aarch64/'))),
    );
    expect(nes.downloads, hasLength(2));
    expect(await manager.data.exists(), isFalse);
  });
  test('ELF validation rejects foreign architecture and truncated native components', () async {
    final file = await File('${root.path}/component').writeAsBytes(elf());
    await verifyLinuxElf(file, architecture: 'x64');
    await expectLater(
      verifyLinuxElf(file, architecture: 'arm64'),
      throwsStateError,
    );
    await file.writeAsBytes(elf(machine: 183));
    await verifyLinuxElf(file, architecture: 'arm64');
    await expectLater(
      verifyLinuxElf(file, architecture: 'x64'),
      throwsStateError,
    );
    await file.writeAsBytes([0x7f, 69, 76, 70]);
    await expectLater(
      verifyLinuxElf(file, architecture: 'x64'),
      throwsStateError,
    );
  });
  test('private bridge publication handles spaced paths but preserves unknown or linked destinations', () async {
    final source = await File('${root.path}/component.so').writeAsBytes(elf());
    final profile = await Directory('${root.path}/profile with spaces')
        .create();
    final path = await prepareLinuxBridge(source.path, profile.path);
    expect(path, './.broomm-runtime/bridge.so');
    final target = File('${profile.path}/.broomm-runtime/bridge.so');
    expect(await target.readAsBytes(), elf());
    final replacement = elf()..[63] = 7;
    await source.writeAsBytes(replacement);
    await prepareLinuxBridge(source.path, profile.path);
    expect(await target.readAsBytes(), replacement);
    await target.delete();
    await Link(target.path).create(source.path);
    await expectLater(
      prepareLinuxBridge(source.path, profile.path),
      throwsStateError,
    );
    expect(await source.readAsBytes(), replacement);
    final unknown = await Directory('${root.path}/other/.broomm-runtime')
        .create(recursive: true);
    await File('${unknown.path}/keep').writeAsString('owner content');
    await expectLater(
      prepareLinuxBridge(source.path, unknown.parent.path),
      throwsStateError,
    );
    expect(await File('${unknown.path}/keep').readAsString(), 'owner content');
  });
  test('private process helper repairs an old updater mode without modifying the packaged source', () async {
    final source = await File('${root.path}/broomm-native-run')
        .writeAsBytes(elf());
    await Process.run('/bin/chmod', ['644', source.path]);
    final profile = await Directory('${root.path}/private staging with spaces')
        .create();
    final relative = await prepareLinuxBridge(
      source.path,
      profile.path,
      runner: true,
    );
    final helper = File('${profile.path}/${relative.substring(2)}');
    expect((await helper.stat()).mode & 0x40, isNonZero);
    expect((await source.stat()).mode & 0x49, 0);
    expect(await helper.readAsBytes(), await source.readAsBytes());
  });
  test('Linux profiles share executable identity while preserving private settings and save data', () async {
    final record = jsonDecode(
      await File('assets/setup/linux-x64/tested-builds.json').readAsString(),
    ) as Map;
    final build = TestedBuild(
      (record['builds'] as List).cast<Map>().singleWhere(
        (b) => b['id'] == 'retroarch',
      ),
    );
    final data = Directory('${root.path}/data');
    final lease = await SessionLease.acquire(data);
    try {
      final a = await prepareManagedProfile(data, 'a' * 32, build, root);
      final b = await prepareManagedProfile(data, 'b' * 32, build, root);
      final config = File('${a.path}/retroarch.cfg');
      final text = await config.readAsString();
      expect(text, contains('gl_sdl3'));
      expect(text, contains('${a.path}/saves'));
      expect(text, isNot(contains(b.path)));
      await config.writeAsString('$text\nvideo_vsync = "false"\n');
      await File('${a.path}/saves/game.srm').writeAsString('progress');
      await prepareManagedProfile(data, 'a' * 32, build, root);
      expect(await config.readAsString(), contains('video_vsync = "false"'));
      expect(await File('${b.path}/saves/game.srm').exists(), isFalse);
      await Directory('${a.path}/saves').rename('${a.path}/retained');
      await expectLater(
        prepareManagedProfile(data, 'a' * 32, build, root),
        throwsStateError,
      );
      expect(
        await File('${a.path}/retained/game.srm').readAsString(),
        'progress',
      );
    } finally {
      await lease.release();
    }
  });
  test('Linux native configuration aliases keep each emulator save tree private across profiles', () async {
    final records =
        (jsonDecode(
              await File('assets/setup/linux-x64/tested-builds.json')
                  .readAsString(),
            ) as Map)['builds']
            as List;
    final paths = {
      'azahar': (
        'data/azahar-emu/sdmc/progress.bin',
        'home/Library/Application Support/Azahar/sdmc/progress.bin',
      ),
      'rpcs3': (
        'config/rpcs3/dev_hdd0/progress.bin',
        'portable/dev_hdd0/progress.bin',
      ),
      'duckstation': (
        'data/duckstation/memcards/progress.bin',
        'home/Library/Application Support/DuckStation/memcards/progress.bin',
      ),
      'melonds': ('config/melonDS/native.ini', 'launcher/portable/native.ini'),
      'ppsspp': (
        'config/ppsspp/PSP/SAVEDATA/progress.bin',
        'user/PSP/SAVEDATA/progress.bin',
      ),
      'pcsx2': (
        'user/pcsx2/inis/native.ini',
        'user/pcsx2/PCSX2/inis/native.ini',
      ),
    };
    for (final entry in paths.entries) {
      final build = TestedBuild(
        records.cast<Map>().singleWhere((b) => b['id'] == entry.key),
      );
      final data = await Directory('${root.path}/${entry.key}').create();
      final a = await prepareManagedProfile(data, 'a' * 32, build, root);
      final b = await prepareManagedProfile(data, 'b' * 32, build, root);
      final native = File('${a.path}/${entry.value.$1}');
      await native.parent.create(recursive: true);
      await native.writeAsString('native progress');
      expect(
        await File('${a.path}/${entry.value.$2}').readAsString(),
        'native progress',
      );
      expect(await File('${b.path}/${entry.value.$1}').exists(), isFalse);
      await prepareManagedProfile(data, 'a' * 32, build, root);
      expect(await native.readAsString(), 'native progress');
    }
  });
  test('foreign native configuration aliases preserve their target and refuse reuse', () async {
    final profile = await Directory('${root.path}/profile').create();
    await prepareLinuxProfileLinks(profile, 'ppsspp');
    final foreign = await Directory('${root.path}/foreign').create();
    final save = await File('${foreign.path}/progress').writeAsString('keep');
    final alias = Link('${profile.path}/config/ppsspp');
    await alias.delete();
    await alias.create(foreign.path);
    await expectLater(
      prepareLinuxProfileLinks(profile, 'ppsspp'),
      throwsStateError,
    );
    expect(await save.readAsString(), 'keep');
    expect(await alias.target(), foreign.path);
  });
  if (Platform.isLinux) {
    test(
      'Linux ZIP staging retains checks and cancellation before publication',
      () async {
        final source = await Directory('${root.path}/input/RetroArch')
            .create(recursive: true);
        await File('${source.path}/retroarch').writeAsBytes(elf());
        final archive = File('${root.path}/payload.zip');
        await ProgressZip.write(archive, source.parent, [
          'RetroArch/retroarch',
        ]);
        final output = await Directory('${root.path}/out').create();
        final selected = await extractSetupArchive(
          archive,
          'zip',
          'RetroArch',
          output,
          DownloadCancellation(),
        );
        expect(await File('$selected/retroarch').readAsBytes(), elf());
        final cancelled = DownloadCancellation()..cancel();
        await expectLater(
          extractSetupArchive(
            archive,
            'zip',
            'RetroArch',
            Directory('${root.path}/cancelled'),
            cancelled,
          ),
          throwsA(isA<DownloadCancelled>()),
        );
        expect(await Directory('${root.path}/cancelled').exists(), isFalse);
        await expectLater(
          extractSetupArchive(
            archive,
            'zip',
            '../escape',
            Directory('${root.path}/invalid'),
            DownloadCancellation(),
          ),
          throwsFormatException,
        );
        expect(await File('$selected/retroarch').readAsBytes(), elf());
      },
    );
  }
}
