@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/addons/packages.dart';
import 'package:broomm/src/addons/files.dart';
import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/managed_emulators.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:flutter_test/flutter_test.dart';

const _server = '0123456789abcdef0123456789abcdef';
const _profile = 'abcdef0123456789abcdef0123456789';
const _second = 'bbcdef0123456789abcdef0123456789';
final _media = Directory('.tool-cache/research/ra-wii-switch/media');

class _CacheClient extends RommClient {
  _CacheClient() : super(Uri.parse('https://fixture.invalid'));
  final transfers = <int>[];
  @override
  Future<void> downloadFile(
    RommFile file,
    File target, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    cancellation.check();
    transfers.add(file.id);
    await File('${_media.path}/${file.id}.${file.name.split('.').last}')
        .copy(target.path);
    onProgress(file.bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final id in [7747, 7746, 8082]) {
    test(
      'real RomM packages $id import, reapply privately and uninstall while retaining progress',
      () async {
        final evidence = await Directory('.tool-cache/research/ra-wii-switch')
            .createTemp('native-packages-$id-');
        final data = Directory('${evidence.absolute.path}/data');
        await data.create();
        final json = jsonDecode(
          await File('${_media.path}/$id.json').readAsString(),
        ) as Map<String, dynamic>;
        final game = RommGame.fromJson(json),
            platform = id == 8082 ? 'switch' : 'wii';
        final base = RommGame.fromJson({
          ...json,
          'files': (json['files'] as List)
              .where((f) => (f as Map)['category'] == 'game')
              .toList(),
        });
        final manager = ManagedEmulators(
          data,
          project: Directory.current.path,
          asset: (p) => File(p).readAsString(),
        );
        await manager.install(
          await manager.readPlan(
            file: 'tool/setup-development.json',
            only: {platform == 'wii' ? 'dolphin' : 'ryubing'},
          ),
        );
        expect(manager.error, isNull, reason: manager.error);
        final library = GameLibrary(data), client = _CacheClient();
        final entry = await library.install(
          serverId: _server,
          userId: 7,
          game: base,
          client: client,
          cancellation: DownloadCancellation(),
          progress: (_) {},
          verifyChecksum: false,
        );
        final service = GamePackages(
          data,
          library,
          platform,
          prepare: (p, c) => manager.preparePackages(platform, p, c),
        );
        final started = DateTime.now();
        final result = await service.sync(
          serverId: _server,
          profileId: _profile,
          entry: entry,
          game: game,
          client: client,
          cancellation: DownloadCancellation(),
          progress: (_) {},
        );
        expect(result.available, platform == 'wii' ? 1 : 6);
        expect(result.installed, result.available);
        final engine = platform == 'wii' ? 'dolphin' : 'ryubing';
        final profile = Directory(
          '${data.path}/profiles/$_profile/emulators/$engine',
        );
        final manifest = await addonJson(
          File('${data.path}/addons/$_server/$id/$platform/current.json'),
        );
        final title = manifest['base'] as String;
        final save = File(
          platform == 'wii'
              ? '${profile.path}/user/Wii/title/00010001/${title.substring(8)}/data/broomm-native-check'
              : '${profile.path}/user/bis/user/save/broomm-native-check',
        );
        await save.parent.create(recursive: true);
        await save.writeAsString('private progress retained');
        final transfers = client.transfers.length;
        final repeated = await service.sync(
          serverId: _server,
          profileId: _profile,
          entry: entry,
          game: game,
          client: client,
          cancellation: DownloadCancellation(),
          progress: (_) {},
        );
        expect(repeated.installed, 0);
        expect(client.transfers.length, transfers);
        final lease = await SessionLease.acquire(data);
        try {
          final (_, second) = await manager.preparePackages(
            platform,
            _second,
            DownloadCancellation(),
          );
          final rom = (await library.contentFiles(entry)).single;
          await service.applyForLaunch(
            _server,
            id,
            _second,
            second,
            rom,
            entry: entry,
          );
          if (platform == 'wii') {
            final resolved = await manager.resolveProgress(
              launchDescriptor(base, gamePlatform(base, [])!, rom),
              _profile,
            );
            final layout = await gameProgressLayout(resolved, platform);
            expect(layout.game, title);
            expect(layout.areas.any((a) => a.path.endsWith('/data')), true);
            expect(
              await File(
                '${profile.path}/user/Wii/ticket/00010005/${title.substring(8).toLowerCase()}.tik',
              ).exists(),
              false,
              reason: 'DLC uses a distinct title namespace, not a guessed base ticket',
            );
          } else {
            final updates = await addonJson(
              File('${second.path}/user/games/$title/updates.json'),
            );
            expect(await File(updates['selected'] as String).exists(), true);
            final dlc = jsonDecode(
              await File('${second.path}/user/games/$title/dlc.json')
                  .readAsString(),
            ) as List;
            expect(dlc, hasLength(5));
          }
          await service.uninstall(_server, id);
          expect(await save.readAsString(), 'private progress retained');
          if (platform == 'wii')
            expect(
              await Directory(
                '${profile.path}/user/Wii/title/00010001/${title.substring(8)}/content',
              ).list().isEmpty,
              true,
            );
          else
            expect(
              await File('${profile.path}/user/games/$title/updates.json')
                  .exists(),
              false,
            );
        } finally {
          await lease.release();
        }
        await File('${evidence.path}/result.json').writeAsString(
          jsonEncode({
            'game': id,
            'platform': platform,
            'nativePackages': result.available,
            'elapsedMs': DateTime.now().difference(started).inMilliseconds,
            'repeatTransfers': false,
            'secondProfileApplied': true,
            'uninstalled': true,
            'progressRetained': true,
            'build': manager
                .buildFor(platform == 'wii' ? 'Dolphin' : 'Ryubing')!
                .hash,
            'ownerProfilesChanged': false,
          }),
        );
        manager.dispose();
        client.close();
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }
}
