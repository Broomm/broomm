import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/addons/files.dart';
import 'package:broomm/src/addons/packages.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:flutter_test/flutter_test.dart';

/// Read-only production inspection. All package-checkpoint writes are confined
/// to a disposable root; no emulator, credentials or cloud client is started.
void main() {
  test('installed Switch receipt selects base media and reuses content after restart', () async {
    final receipt = File(Platform.environment['BROOMM_SWITCH_RECEIPT']!);
    final before = await receipt.readAsString();
    final record = await addonJson(receipt);
    final game = RommGame.fromJson(
      (record['game'] as Map).cast<String, dynamic>(),
    );
    final entry = InstalledGame(game, receipt.parent, record['userId'] as int);
    final server = record['serverId'] as String;
    final source = receipt.parent.parent.parent.parent;
    final library = GameLibrary(source);
    final scratch = await Directory.systemTemp.createTemp(
      'broomm-switch-receipt-',
    );
    try {
      final current = await addonJson(
        File('${source.path}/addons/$server/${game.id}/switch/current.json'),
      );
      final original = await addonJson(
        File(
          '${source.path}/addons/$server/${game.id}/switch/${current['generation']}/manifest.json',
        ),
      );
      final copied = Directory(
        '${scratch.path}/addons/$server/${game.id}/switch',
      );
      await Directory('${copied.path}/${current['generation']}')
          .create(recursive: true);
      await File('${copied.path}/current.json')
          .writeAsString(jsonEncode(current));
      await File('${copied.path}/${current['generation']}/manifest.json')
          .writeAsString(jsonEncode(original));
      final packages = GamePackages(
        scratch,
        library,
        'switch',
        prepare: (_, __) =>
            throw StateError('Inspection cannot start an emulator'),
      );
      final timer = Stopwatch()..start();
      final files = await library.contentFiles(entry);
      final base = gameCandidates(
        playablePlatforms.firstWhere((p) => p.slug == 'switch'),
        await library.contentFiles(entry, excludeAddons: true),
      );
      expect(base, hasLength(1));
      await library.installationIdentity(entry, base.single);
      expect(await packages.needsSwitchSelection(server, entry), false);
      // A newly selected backend with no checkpoint must detect the already
      // installed attachments even when catalogue metadata has no file list.
      await File('${copied.path}/current.json').delete();
      expect(await packages.needsSwitchSelection(server, entry), true);
      timer.stop();
      expect(await receipt.readAsString(), before);
      stdout.writeln(
        jsonEncode({
          'game': game.id,
          'installedFiles': files.length,
          'baseCandidates': base.length,
          'persistedRemoteFiles': game.files.length,
          'existingCheckpointReused': true,
          'missingCheckpointDetected': true,
          'elapsedMs': timer.elapsedMilliseconds,
          'romPayloadBytesRead': 0,
          'productionWrites': 0,
        }),
      );
    } finally {
      await scratch.delete(recursive: true);
    }
  });
}
