import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/progress/ryubing.dart';
import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File rom;
  late ResolvedSession session, astris;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-switch-identity-');
    rom = await File('${root.path}/game.nsp').writeAsBytes([1, 2, 3]);
    session = ResolvedSession(
      PreparedEmulator('Ryubing', root.path, 'unused', 2, null, null),
      rom.path,
      'a' * 64,
      {},
      installationIdentity: 'server-one/rom-42/file-10/publication-one',
    );
    astris = ResolvedSession(
      PreparedEmulator('Astris', root.path, 'unused', 2, null, null),
      rom.path,
      session.buildHash,
      {},
      installationIdentity: session.installationIdentity,
    );
  });
  tearDown(() async => root.delete(recursive: true));
  test('the same installed media reuses its native binding; another server or publication receives a separate binding', () async {
    final identity = await switchSourceIdentity(session);
    await recordRyubingGame(session, '01006a800016e000', identity.$1);
    expect((await switchSourceIdentity(session)).$1, identity.$1);
    final marker = File(
      '${root.path}/progress-identities/installed-${identity.$1}.json',
    );
    final record = jsonDecode(await marker.readAsString()) as Map;
    expect(record['source'], identity.$2);
    expect(record['program'], '01006a800016e000');
    expect(
      (await switchSourceIdentity(
        session.withInstallationIdentity(
          'server-two/rom-42/file-10/publication-one',
        ),
      )).$1,
      isNot(identity.$1),
    );
    expect(
      (await switchSourceIdentity(
        session.withInstallationIdentity(
          'server-one/rom-42/file-10/publication-two',
        ),
      )).$1,
      isNot(identity.$1),
    );
    expect(await rom.readAsBytes(), [1, 2, 3]);
  });
  test('a media replacement during cold initialization cannot publish a stale title binding and preserves existing progress', () async {
    final identity = await switchSourceIdentity(session);
    final progress = await File('${root.path}/save').writeAsString('retained');
    await rom.writeAsBytes([4, 5, 6]);
    await rom.setLastModified(DateTime.utc(2026, 10, 27, 20));
    await expectLater(
      recordRyubingGame(session, '01006a800016e000', identity.$1),
      throwsFormatException,
    );
    expect(
      await File(
        '${root.path}/progress-identities/installed-${identity.$1}.json',
      ).exists(),
      false,
    );
    expect(await progress.readAsString(), 'retained');
  });
  test('Astris can publish and reuse a binding after macOS updates last-opened metadata', () async {
    await rom.setLastModified(DateTime.utc(2026, 10, 27, 20));
    final before = await rom.stat();
    final identity = await switchSourceIdentity(astris);
    final attribute = await Process.run('/usr/bin/xattr', [
      '-wx',
      'com.apple.lastuseddate#PS',
      '00000065000000000000000000000000',
      rom.path,
    ]);
    expect(attribute.exitCode, 0, reason: '${attribute.stderr}');
    final after = await rom.stat();
    expect(after.changed, isNot(before.changed));
    expect(after.modified, before.modified);
    expect(await rom.readAsBytes(), [1, 2, 3]);
    await recordRyubingGame(astris, '01006a800016e000', identity.$1);
    expect(await switchSourceIdentity(astris), identity);
  }, skip: !Platform.isMacOS);
  test('Astris rejects an atomic replacement even with matching length and modification time', () async {
    final modified = DateTime.utc(2026, 10, 27, 20);
    await rom.setLastModified(modified);
    final identity = await switchSourceIdentity(astris);
    final replacement = await File('${root.path}/replacement.nsp')
        .writeAsBytes([4, 5, 6]);
    await replacement.setLastModified(modified);
    await replacement.rename(rom.path);
    final after = await rom.stat();
    expect(after.size, 3);
    expect(after.modified.toUtc(), modified);
    await expectLater(
      recordRyubingGame(astris, '01006a800016e000', identity.$1),
      throwsFormatException,
    );
  }, skip: !Platform.isMacOS);
  test('legacy checksum bindings are retained and do not guess the selected game; native initialization creates a separate installed-media binding', () async {
    final legacy = File('${root.path}/progress-identities/${'b' * 64}.json');
    await legacy.parent.create();
    await legacy.writeAsString('{"version":1,"program":"0100000000000001"}');
    await expectLater(
      ryubingProgressLayout(session, 'user'),
      throwsA(isA<SwitchNeedsInitialization>()),
    );
    final identity = await switchSourceIdentity(session);
    await recordRyubingGame(session, '01006a800016e000', identity.$1);
    expect(
      await legacy.readAsString(),
      '{"version":1,"program":"0100000000000001"}',
    );
    expect(
      await File(
        '${root.path}/progress-identities/installed-${identity.$1}.json',
      ).exists(),
      true,
    );
  });
}
