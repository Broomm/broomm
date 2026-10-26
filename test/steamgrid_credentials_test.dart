import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/shell/credentials.dart';
import 'package:broomm/src/shell/steamgrid_credentials.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:broomm/src/romm/credential.dart';

import 'remembered_signin_test.dart' show MemoryCredentials;

void main() {
  late Directory data;
  late MemoryCredentials backend;
  late ProfileCredentials profileStore;
  late SteamGridCredentials keys;
  const server = SavedServer(
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'https://one.example',
    '5.4.0',
  );
  const profile = SavedProfile(
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    7,
    'Player',
  );
  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-sgdb-key-');
    backend = MemoryCredentials();
    profileStore = ProfileCredentials(data, backend: backend);
    keys = SteamGridCredentials(profileStore);
  });
  tearDown(() async {
    await data.delete(recursive: true);
  });
  test('SGDB keys survive store recreation in a separate slot and removal cannot affect RomM sign-in', () async {
    await profileStore.write(
      server,
      profile,
      const RommCredential('refresh', 'romm-refresh'),
    );
    await keys.write(server, profile, 'sgdb-key');
    expect(
      await SteamGridCredentials(ProfileCredentials(data, backend: backend))
          .read(server, profile),
      'sgdb-key',
    );
    expect((await profileStore.read(server, profile))!.secret, 'romm-refresh');
    await keys.delete(profile);
    expect(await keys.read(server, profile), isNull);
    expect((await profileStore.read(server, profile))!.secret, 'romm-refresh');
  });
  test('a key bound to a different server and unavailable storage stay errors rather than missing keys', () async {
    await keys.write(server, profile, 'sgdb-key');
    const other = SavedServer(
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'https://two.example',
      '5.4.0',
    );
    await expectLater(
      keys.read(other, profile),
      throwsA(isA<CredentialFailure>()),
    );
    backend.locked = true;
    await expectLater(
      keys.read(server, profile),
      throwsA(isA<CredentialFailure>()),
    );
    backend.locked = false;
    expect(await keys.read(server, profile), 'sgdb-key');
  });
}
