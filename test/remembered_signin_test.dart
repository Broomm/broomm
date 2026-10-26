import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/romm/credential.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/shell/credentials.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_model_test.dart' show FixtureRomm, settleModel;

class MemoryCredentials implements CredentialBackend {
  final values = <String, String>{};
  bool locked = false;
  bool failWrites = false;
  @override
  Future<String?> read(String key) async {
    if (locked) throw const CredentialFailure('Secure store locked');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (locked || failWrites)
      throw const CredentialFailure('Secure store locked');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (locked) throw const CredentialFailure('Secure store locked');
    values.remove(key);
  }
}

class RememberedRomm extends FixtureRomm {
  RememberedRomm(super.server);
  int passwords = 0, restores = 0;
  RommFailure? restoreFailure;
  int userId = 7;
  RommCredential? saved;
  @override
  RommCredential? get credential => saved;
  @override
  Future<RommUser> login(String name, String password) async {
    passwords++;
    saved = const RommCredential('refresh', 'fixture-refresh');
    return RommUser(userId, name);
  }

  @override
  Future<RommUser> restore(RommCredential value) async {
    restores++;
    if (restoreFailure != null) throw restoreFailure!;
    saved = const RommCredential('refresh', 'rotated-fixture-refresh');
    return RommUser(userId, 'Remembered player');
  }
}

void main() {
  late Directory data;
  late MemoryCredentials backend;
  late ShellModel model;
  final clients = <RememberedRomm>[];
  ShellModel create() => ShellModel(
    ShellStorage(data),
    credentials: backend,
    clientFactory: (uri) {
      final client = RememberedRomm(uri);
      clients.add(client);
      return client;
    },
  );
  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-signin-test-');
    backend = MemoryCredentials();
    clients.clear();
    model = create();
    await model.start();
    await model.addServer('https://one.example');
  });
  tearDown(() async {
    model.dispose();
    await data.delete(recursive: true);
  });
  Future<void> login() async {
    expect(await model.login('Player', 'never-store-this-password'), true);
    await settleModel(model);
  }

  test('one sign-in survives restart and switching; explicit sign-out removes only the credential', () async {
    await login();
    final profile = model.profile!, server = model.server!;
    expect(clients.last.passwords, 1);
    expect(backend.values[profile.id], contains('fixture-refresh'));
    expect(
      await File('${data.path}/accounts.json').readAsString(),
      isNot(contains('never-store-this-password')),
    );
    final canary = File('${data.path}/local-progress');
    await canary.writeAsString('save');
    model.dispose();
    clients.clear();
    model = create();
    await model.start();
    expect(model.screen, ShellScreen.servers);
    expect(
      clients,
      isEmpty,
      reason: 'No account work before explicit selection',
    );
    await model.chooseServer(server);
    expect(await model.activateProfile(profile), true);
    expect(clients.last.passwords, 0);
    expect(clients.last.restores, 1);
    expect(backend.values[profile.id], contains('rotated-fixture-refresh'));
    model.switchAccount();
    expect(backend.values.containsKey(profile.id), true);
    expect(await model.activateProfile(profile), true);
    await model.signOut();
    expect(backend.values.containsKey(profile.id), false);
    expect(await model.activateProfile(profile), false);
    expect(model.knownProfiles.single.id, profile.id);
    expect(await canary.readAsString(), 'save');
  });
  test('unavailable or rejected restoration preserves credentials and keeps failures distinct from missing sign-in', () async {
    await login();
    final profile = model.profile!;
    final secret = backend.values[profile.id];
    model.switchAccount();
    backend.locked = true;
    expect(await model.activateProfile(profile), isNull);
    expect(model.error, contains('locked'));
    expect(backend.values[profile.id], secret);
    backend.locked = false;
    final original = model.clientFactory;
    model.dispose();
    model = ShellModel(
      ShellStorage(data),
      credentials: backend,
      clientFactory: (uri) {
        final client = original(uri) as RememberedRomm;
        client.restoreFailure = const RommFailure('Offline');
        return client;
      },
    );
    await model.start();
    await model.chooseServer(model.records.servers.single);
    expect(await model.activateProfile(profile), isNull);
    expect(model.error, 'Offline');
    expect(backend.values[profile.id], secret);
    clients.last.restoreFailure = const RommFailure('Revoked', status: 401);
    model.dispose();
    model = ShellModel(
      ShellStorage(data),
      credentials: backend,
      clientFactory: (uri) =>
          RememberedRomm(uri)
            ..restoreFailure = const RommFailure('Revoked', status: 401),
    );
    await model.start();
    await model.chooseServer(model.records.servers.single);
    expect(await model.activateProfile(profile), false);
    expect(backend.values[profile.id], secret);
    expect(model.knownProfiles.length, 1);
  });
  test('same remote user on different servers has separate secrets and swapped envelopes never authenticate', () async {
    await login();
    final a = model.profile!;
    final first = backend.values[a.id]!;
    model.changeServer();
    await model.addServer('https://two.example');
    await login();
    final b = model.profile!;
    expect(b.id, isNot(a.id));
    backend.values[b.id] = first;
    model.switchAccount();
    final before = clients.length;
    expect(await model.activateProfile(b), isNull);
    expect(clients.length, before + 1);
    expect(clients.last.restores, 0);
    expect(model.error, contains('does not match'));
    expect(backend.values[a.id], first);
    expect(model.records.profiles.length, 2);
  });
  test('locked storage keeps successful login usable; late refresh cannot recreate a signed-out credential', () async {
    backend.locked = true;
    await login();
    expect(model.authenticated, true);
    expect(model.credentialNotice, isNotNull);
    expect(backend.values, isEmpty);
    backend.locked = false;
    model.switchAccount();
    await login();
    final connection = clients.last, profile = model.profile!;
    final callback = connection.onCredentialChanged!;
    await model.signOut();
    await callback(const RommCredential('refresh', 'late-refresh'));
    expect(backend.values.containsKey(profile.id), false);
  });
  test('failed rotated-token publication retains restored play and a locked sign-out retains the active profile', () async {
    await login();
    final profile = model.profile!;
    model.switchAccount();
    backend.failWrites = true;
    expect(await model.activateProfile(profile), true);
    expect(model.authenticated, true);
    expect(model.credentialNotice, isNotNull);
    expect(clients.last.refreshGuard, isNull);
    expect(backend.values[profile.id], contains('fixture-refresh'));
    backend.locked = true;
    await model.signOut();
    expect(model.profile?.id, profile.id);
    expect(model.error, contains('could not be removed'));
    expect(backend.values.containsKey(profile.id), true);
    backend.locked = backend.failWrites = false;
    await model.signOut();
    expect(model.authenticated, false);
    expect(backend.values.containsKey(profile.id), false);
  });
  test('credential transactions serialize store instances and preserve ownership on corrupted data', () async {
    final id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final a = ProfileCredentials(data, backend: backend),
        b = ProfileCredentials(data, backend: backend);
    final entered = Completer<void>(), release = Completer<void>();
    var second = false;
    final first = a.locked(id, () async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final next = b.locked(id, () async {
      second = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(second, false);
    release.complete();
    await Future.wait([first, next]);
    expect(second, true);
    await login();
    final p = model.profile!;
    backend.values[p.id] = '{damaged';
    await expectLater(
      a.read(model.server!, p),
      throwsA(isA<CredentialFailure>()),
    );
    expect(backend.values[p.id], '{damaged');
    expect(
      jsonDecode(
        await File('${data.path}/accounts.json').readAsString(),
      )['profiles'].length,
      1,
    );
  });
  test('an independent process holding the production credential lock excludes restore until release', () async {
    final key = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
    final locks = Directory('${data.path}/authentication-locks');
    await locks.create();
    final child = await Process.start('dart', [
      'test/support/hold_library_lock.dart',
      '${locks.path}/$key.lock',
    ]);
    final ready = child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    expect(await ready.timeout(const Duration(seconds: 10)), 'held');
    final store = ProfileCredentials(data, backend: backend);
    var entered = false;
    try {
      await expectLater(
        store.locked(key, () async {
          entered = true;
        }),
        throwsA(isA<CredentialFailure>()),
      );
      expect(entered, false);
    } finally {
      child.stdin.writeln('release');
      await child.stdin.close();
      await child.exitCode;
    }
    await store.locked(key, () async {
      entered = true;
    });
    expect(entered, true);
  });
}
