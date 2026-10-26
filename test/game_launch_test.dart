import 'package:broomm/src/game_launch.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RommGame game({String slug = '', String name = 'Nintendo GameCube'}) =>
      RommGame(
        id: 9,
        name: 'Game',
        platformId: 77,
        platform: name,
        platformSlug: slug,
      );
  test('launch adapters follow server platform identity and persisted slugs rather than ROM titles or numeric IDs', () {
    final value = game(slug: 'wii');
    expect(gamePlatform(value, [])!.slug, 'wii');
    expect(
      gamePlatform(game(name: 'Unknown'), [
        const RommPlatform(77, 'GC', 'ngc', 1),
      ])!.slug,
      'ngc',
    );
    expect(gamePlatform(game(slug: 'n3ds'), [])!.emulator, 'Azahar');
    expect(gamePlatform(game(slug: 'unsupported'), []), isNull);
    expect(RommGame.fromJson(value.toJson()).platformSlug, 'wii');
  });
  test('entry selection distinguishes extracted PS3 boot files from auxiliary binaries and keeps disc choice explicit', () {
    final ps3 = playablePlatforms.firstWhere((p) => p.slug == 'ps3');
    expect(
      gameCandidates(ps3, [
        '/root/Game/PS3_GAME/USRDIR/EBOOT.BIN',
        '/root/loader.bin',
        '/root/update.pkg',
      ]),
      ['/root/Game/PS3_GAME/USRDIR/EBOOT.BIN'],
    );
    final gc = playablePlatforms.firstWhere((p) => p.slug == 'ngc');
    expect(
      gameCandidates(gc, [
        '/root/Disc1.rvz',
        '/root/Disc2.ISO',
        '/root/readme.txt',
      ]).length,
      2,
    );
    expect(gameCandidates(gc, ['/root/game.zip']), isEmpty);
  });
  test('RetroArch acknowledgement accepts both measured status formats and rejects another game or substring', () {
    const path = '/private/games/An entirely different game.sfc';
    expect(
      retroStatusMatches(
        'GET_STATUS PAUSED Snes9x,An entirely different game\n',
        path,
      ),
      true,
    );
    expect(
      retroStatusMatches(
        'GET_STATUS PLAYING Snes9x,An entirely different game,crc32=abc123\n',
        path,
      ),
      true,
    );
    expect(
      retroStatusMatches(
        'GET_STATUS PLAYING Snes9x,An entirely different game 2',
        path,
      ),
      false,
    );
    expect(retroStatusMatches('GET_STATUS CONTENTLESS', path), false);
    expect(
      retroStatusMatches('GET_STATUS PLAYING Snes9x,A, B', '/games/A, B.zip'),
      true,
    );
  });
}
