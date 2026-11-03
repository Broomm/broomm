import 'dart:io';

import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory data;
  late ManagedEmulators manager;
  Future<File> write(String path) async {
    final file = File('${data.path}/$path');
    await file.parent.create(recursive: true);
    return file.writeAsString('fixture');
  }

  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-reset-');
    manager = ManagedEmulators(data, asset: (p) => File(p).readAsString());
  });
  tearDown(() async {
    manager.dispose();
    await data.delete(recursive: true);
  });
  test('reset removes broken installations and every profile configuration while retaining games and accounts', () async {
    for (final path in [
      'emulators/selected.json',
      'emulators/.packages-interrupted/payload',
      'setup-downloads/partial',
      'setup-packages/offline',
      'profiles/${'b' * 32}/emulators/rpcs3/portable/config.yml',
      'profiles/${'b' * 32}/emulators/rpcs3/cache/compiled.tmp',
      'profiles/${'a' * 32}/emulators/retroarch/config/core-options.cfg',
    ])
      await write(path);
    final retained = <File>[
      await write('library/installed/rom'),
      await write('artwork/logo.png'),
      await write('settings.json'),
      await write('downloads/queue.json'),
      await write('profiles/${'a' * 32}/account-data'),
      await write('addons/installed'),
      await write('cloud-saves/pending/state.json'),
      await write('profiles/${'a' * 32}/emulators/retroarch/saves/local.srm'),
      await write(
        'profiles/${'a' * 32}/emulators/retroarch/states/local.state',
      ),
      await write(
        'profiles/${'b' * 32}/emulators/rpcs3/portable/dev_hdd0/home/00000001/savedata/game/settings.ini',
      ),
      await write(
        'profiles/${'c' * 32}/emulators/ryubing/user/system/Profiles.json',
      ),
      await write(
        'profiles/${'c' * 32}/emulators/ryubing/user/bis/user/save/console-state',
      ),
    ];
    var preferencesCleared = false;
    await manager.resetAll(
      clearPreferences: () async => preferencesCleared = true,
    );
    expect(manager.error, isNull);
    expect(preferencesCleared, isTrue);
    for (final file in retained) expect(await file.readAsString(), 'fixture');
    expect(await manager.root.exists(), isFalse);
    expect(
      await Directory('${data.path}/profiles/${'a' * 32}/emulators').exists(),
      isTrue,
    );
    expect(
      await File(
        '${data.path}/profiles/${'b' * 32}/emulators/rpcs3/portable/config.yml',
      ).readAsString(),
      isNot('fixture'),
    );
    expect(await File('${data.path}/emulator-reset.json').exists(), isFalse);
  });
  test('held session prevents every reset mutation and release permits a fresh reset', () async {
    final retained = await write('emulators/broken-build');
    final lease = await SessionLease.acquire(data);
    try {
      await manager.resetAll();
      expect(manager.error, isNotNull);
      expect(await retained.readAsString(), 'fixture');
      expect(await File('${data.path}/emulator-reset.json').exists(), isFalse);
    } finally {
      await lease.release();
    }
    await manager.resetAll();
    expect(manager.error, isNull);
    expect(await retained.exists(), isFalse);
  });
  test('interrupted reset remains visible and repeatable without installation records', () async {
    await write('emulators/broken-build');
    await manager.resetAll(
      clearPreferences: () async =>
          throw const FileSystemException('held checkpoint failure'),
    );
    expect(manager.error, isNotNull);
    final restarted = ManagedEmulators(data, asset: manager.asset);
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.error, contains('reset was interrupted'));
    await restarted.resetAll(clearPreferences: () async {});
    expect(restarted.error, isNull);
    expect(await File('${data.path}/emulator-reset.json').exists(), isFalse);
    expect(await Directory('${data.path}/emulators').exists(), isFalse);
  });
}
