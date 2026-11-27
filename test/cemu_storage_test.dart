import 'dart:io';

import 'package:broomm/src/cemu.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/progress/files.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/remote/cemu_layout.dart';
import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  late Directory data;
  late String root, portable;
  Future<File> write(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }

  PreparedEmulator emulator({String title = '0005000012345678'}) =>
      PreparedEmulator(
        'Cemu',
        root,
        '$root/launcher/${'a' * 64}/Cemu/Cemu',
        0,
        null,
        null,
        userDirectory: portable,
        contentId: title,
      )..remoteScreen = true;
  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-cemu-storage-');
    root = '${data.path}/profiles/${'b' * 32}/emulators/cemu';
    portable = '$root/launcher/${'a' * 64}/Cemu/portable';
    await write('$root/profile.json', '{"version":1,"emulator":"cemu"}');
  });
  tearDown(() => data.delete(recursive: true));

  test('native save boundary excludes other accounts, titles and console identity across builds', () async {
    final base = '$root/user/mlc01';
    final own = '$base/usr/save/00050000/12345678/user';
    await write('$own/80000001/slot/data.bin', 'personal');
    await write('$own/common/shared.bin', 'common');
    for (final p in [
      '$own/80000002/other.bin',
      '$base/usr/save/00050000/87654321/user/80000001/data.bin',
      '$base/usr/save/0005000e/12345678/user/80000001/update.bin',
      '$base/usr/account/80000001/account.dat',
      '$base/otp.bin',
    ]) {
      await write(p, 'keep');
    }
    final session = ResolvedSession(emulator(), '', '1' * 64, {});
    final layout = await gameProgressLayout(session, 'wiiu');
    expect((await layout.files()).keys.toSet(), {
      'save/slot/data.bin',
      'common/shared.bin',
    });
    final otherBuild = PreparedEmulator(
      'Cemu',
      root,
      '$root/new-Cemu',
      0,
      null,
      null,
      userDirectory: '$root/launcher/${'c' * 64}/Cemu/portable',
      contentId: '0005000012345678',
    );
    final upgraded = await gameProgressLayout(
      ResolvedSession(otherBuild, '', '2' * 64, {}),
      'wiiu',
    );
    expect(
      (await upgraded.files()).map((k, v) => MapEntry(k, v.path)),
      (await layout.files()).map((k, v) => MapEntry(k, v.path)),
    );
    await expectLater(
      layout.target('save/../../another-account'),
      throwsFormatException,
    );
    await expectLater(
      gameProgressLayout(
        ResolvedSession(emulator(title: '0005000e12345678'), '', '1' * 64, {}),
        'wiiu',
      ),
      throwsFormatException,
    );
  });

  test('remote layout restores only owned preferences after interruption and launcher change', () async {
    final config = await write(
      '$portable/settings.xml',
      '<content><fullscreen>true</fullscreen><open_pad>false</open_pad><pad_size><x>500</x><y>300</y></pad_size><Graphic><VSync>2</VSync></Graphic></content>',
    );
    await CemuRemoteLayout.prepare(emulator());
    expect(
      cemuXml(
        await config.readAsString(),
        'content',
      ).rootElement.getElement('open_pad')!.innerText,
      'true',
    );
    await config.writeAsString(
      patchCemuSettings(await config.readAsString(), {
        'Graphic': <String, Object>{'VSync': 3},
        'open_pad': false,
      }),
    );
    // A new application instance reads the journal's original anchor rather than
    // guessing from the currently selected emulator release.
    portable = '$root/launcher/${'c' * 64}/Cemu/portable';
    await CemuRemoteLayout.restore(root);
    final restored = cemuXml(
      await config.readAsString(),
      'content',
    ).rootElement;
    expect(restored.getElement('fullscreen')!.innerText, 'true');
    expect(restored.getElement('open_pad')!.innerText, 'false');
    expect(restored.getElement('pad_size')!.getElement('x')!.innerText, '500');
    expect(restored.getElement('Graphic')!.getElement('VSync')!.innerText, '3');
    expect(await CemuRemoteLayout.journal(root).exists(), false);
    await CemuRemoteLayout.restore(root); // confirmed cleanup is repeatable
    await progressWrite(CemuRemoteLayout.journal(root), {
      'version': 1,
      'config': '../../foreign.xml',
      'keys': {},
    });
    final before = await config.readAsString();
    await expectLater(CemuRemoteLayout.restore(root), throwsFormatException);
    expect(await config.readAsString(), before);
  });

  test('reset removes Cemu settings and caches while preserving saves and native identity', () async {
    final removed = <File>[];
    for (final p in [
      'settings.xml',
      'controllerProfiles/controller0.xml',
      'shaderCache/game.bin',
      'title_list_cache.xml',
    ]) {
      removed.add(await write('$portable/$p', 'cache'));
    }
    final kept = <File>[];
    for (final p in [
      '$root/user/mlc01/usr/save/00050000/12345678/user/80000001/save',
      '$root/user/mlc01/usr/account/80000001/account.dat',
      '$portable/otp.bin',
      '$portable/seeprom.bin',
      '$portable/unrelated.txt',
    ]) {
      kept.add(await write(p, 'keep'));
    }
    final manager = ManagedEmulators(
      data,
      asset: (p) => File(p).readAsString(),
    );
    try {
      await manager.resetAll();
      expect(manager.error, isNull);
      for (final f in removed) {
        expect(await f.exists(), false);
      }
      for (final f in kept) {
        expect(await f.readAsString(), 'keep');
      }
    } finally {
      manager.dispose();
    }
  });
}
