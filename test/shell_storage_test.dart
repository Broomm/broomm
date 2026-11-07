import 'dart:io';

import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ShellStorage storage;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-shell-storage-');
    storage = ShellStorage(root);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('Linux keyring is opt-in and stays selected after a restart', () async {
    expect(ShellPreferences.fromJson({}).linuxUseKeyring, isFalse);
    final defaultSettings = (await storage.load()).preferences;
    expect(defaultSettings.linuxUseKeyring, isFalse);
    await storage.preferences(defaultSettings.copy(linuxUseKeyring: true));
    final restored = (await ShellStorage(root).load()).preferences;
    expect(restored.copy(reduceMotion: true).linuxUseKeyring, isTrue);
  });

  test('emulator removal clears its defaults across servers and keeps other preferences', () async {
    final first = (await storage.saveServer(
      normalizeServer('https://first.example'),
      '5.4.0',
    )).servers.single;
    final second = (await storage.saveServer(
      normalizeServer('https://second.example'),
      '5.4.0',
    )).servers.last;
    await storage.emulatorDefaults(first.id, {
      'gba': 'retroarch',
      'psp': 'ppsspp',
    });
    await storage.emulatorDefaults(second.id, {
      'snes': 'retroarch',
      'nds': 'melonds',
    });
    await storage.removeEmulatorDefaults('retroarch');
    final restored = await ShellStorage(root).load();
    expect(restored.emulatorDefaults, {
      '${first.id}:psp': 'ppsspp',
      '${second.id}:nds': 'melonds',
    });
    expect(restored.servers.length, 2);
  });

  test(
    'servers survive cancelled login and same account IDs remain server scoped',
    () async {
      var records = await storage.saveServer(
        normalizeServer('https://first.example/base'),
        '5.4.0',
      );
      final first = records.servers.single;
      records = await storage.saveProfile(first, const RommUser(1, 'Player'));
      records = await storage.saveServer(
        normalizeServer('https://second.example'),
        '5.4.0',
      );
      final second = records.servers.last;
      records = await storage.saveProfile(second, const RommUser(1, 'Player'));
      await storage.saveServer(
        normalizeServer('https://empty.example'),
        '5.4.0',
      );
      final restarted = await ShellStorage(root).load();
      expect(restarted.servers.length, 3);
      expect(restarted.profiles.length, 2);
      expect(restarted.profiles.map((p) => p.id).toSet().length, 2);
      expect(restarted.profiles.map((p) => p.serverId).toSet().length, 2);
      expect(restarted.servers.last.id, restarted.lastServer);
      expect(
        (await File('${root.path}/accounts.json').readAsString()).toLowerCase(),
        isNot(contains('password')),
      );
    },
  );
  test(
    'serialized writes retain profiles and preferences after restart',
    () async {
      final server = (await storage.saveServer(
        normalizeServer('https://server.example'),
        '5.4.0',
      )).servers.single;
      await Future.wait([
        storage.saveProfile(server, const RommUser(2, 'One')),
        storage.preferences(
          const ShellPreferences(
            reduceMotion: true,
            pageSize: 48,
            showArtwork: false,
          ),
        ),
        storage.saveProfile(server, const RommUser(3, 'Two')),
      ]);
      final restarted = await ShellStorage(root).load();
      expect(restarted.profiles.map((p) => p.name), ['One', 'Two']);
      expect(restarted.preferences.pageSize, 48);
      expect(restarted.preferences.reduceMotion, true);
      expect(restarted.preferences.showArtwork, false);
    },
  );
  test('corrupt or linked settings stay preserved and cannot become an empty account store', () async {
    final file = File('${root.path}/accounts.json');
    await file.writeAsString('{broken');
    await expectLater(storage.load(), throwsA(isA<FileSystemException>()));
    await expectLater(
      storage.saveServer(normalizeServer('https://new.example'), '5.4.0'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), '{broken');
    if (!Platform.isWindows) {
      final target = File('${root.path}/untouched');
      await target.writeAsString('original');
      await file.delete();
      await Link(file.path).create(target.path);
      await expectLater(storage.load(), throwsA(isA<FileSystemException>()));
      expect(await target.readAsString(), 'original');
    }
  });
}
