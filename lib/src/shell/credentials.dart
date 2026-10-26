import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../romm/credential.dart';
import 'storage.dart';

abstract class CredentialBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformCredentials implements CredentialBackend {
  static const channel = MethodChannel('app.broomm/credentials');
  Future<T?> invoke<T>(String method, String key, [String? value]) async {
    try {
      return await channel
          .invokeMethod<T>(method, {
            'key': key,
            if (value != null) 'value': value,
          })
          .timeout(const Duration(seconds: 12));
    } on MissingPluginException {
      throw const CredentialFailure(
        'Secure sign-in storage is unavailable on this build.',
      );
    } on PlatformException {
      throw const CredentialFailure(
        'Secure sign-in storage is locked or unavailable. Unlock your system keyring and retry.',
      );
    } on TimeoutException {
      throw const CredentialFailure(
        'Secure sign-in storage did not respond. Unlock your system keyring and retry.',
      );
    }
  }

  @override
  Future<String?> read(String key) => invoke<String>('read', key);
  @override
  Future<void> write(String key, String value) =>
      invoke<void>('write', key, value);
  @override
  Future<void> delete(String key) => invoke<void>('delete', key);
}

class CredentialFailure implements Exception {
  const CredentialFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Secret values live only in the native secure store. Stable, nonsecret locks
/// serialize restore/refresh/publication across Broomm processes sharing data.
class ProfileCredentials {
  ProfileCredentials(this.data, {CredentialBackend? backend})
    : backend = backend ?? PlatformCredentials();
  final Directory data;
  final CredentialBackend backend;
  static final Map<String, Future<void>> _tails = {};

  Future<T> locked<T>(String key, Future<T> Function() operation) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(key))
      throw const FormatException('Invalid profile identity');
    if (await FileSystemEntity.type(data.path, followLinks: false) !=
        FileSystemEntityType.directory)
      throw const CredentialFailure('Invalid Broomm sign-in storage location.');
    final queueKey = '${await data.resolveSymbolicLinks()}:$key';
    final result = (_tails[queueKey] ?? Future<void>.value()).then((_) async {
      final dir = Directory('${data.path}/authentication-locks');
      if (await FileSystemEntity.type(dir.path, followLinks: false) ==
          FileSystemEntityType.notFound)
        await dir.create();
      if (await FileSystemEntity.type(dir.path, followLinks: false) !=
          FileSystemEntityType.directory)
        throw const CredentialFailure(
          'Invalid sign-in lock directory. Existing sign-ins have been kept.',
        );
      final file = File('${dir.path}/$key.lock');
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file)
        throw const CredentialFailure(
          'Invalid sign-in lock. Existing sign-ins have been kept.',
        );
      final lock = await file.open(mode: FileMode.append);
      try {
        final until = DateTime.now().add(const Duration(seconds: 3));
        while (true) {
          try {
            await lock.lock(FileLock.exclusive);
            break;
          } on FileSystemException {
            if (DateTime.now().isAfter(until))
              throw const CredentialFailure(
                'Another Broomm process is updating this sign-in. Retry in a moment.',
              );
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
        }
        return await operation();
      } finally {
        await lock.close();
      }
    });
    _tails[queueKey] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<RommCredential?> read(SavedServer server, SavedProfile profile) async {
    final value = await backend.read(profile.id);
    if (value == null) return null;
    if (value.length > 32768)
      throw const CredentialFailure(
        'Saved sign-in data is invalid. It has been kept.',
      );
    try {
      final j = jsonDecode(value) as Map;
      if (j['version'] != 1 ||
          j['server'] != server.address ||
          j['user'] != profile.userId ||
          profile.serverId != server.id)
        throw const FormatException('Credential identity mismatch');
      return RommCredential.fromJson(j);
    } catch (_) {
      throw const CredentialFailure(
        'The saved sign-in does not match this server/profile or is damaged. It has been kept.',
      );
    }
  }

  Future<void> write(
    SavedServer server,
    SavedProfile profile,
    RommCredential credential,
  ) async {
    final value = jsonEncode({
      'version': 1,
      'server': server.address,
      'user': profile.userId,
      ...credential.toJson(),
    });
    await backend.write(profile.id, value);
    if (await backend.read(profile.id) != value)
      throw const CredentialFailure(
        'Saved sign-in could not be verified. The current session is still usable.',
      );
  }

  Future<void> delete(String profileId) async {
    await backend.delete(profileId);
    if (await backend.read(profileId) != null)
      throw const CredentialFailure('The saved sign-in could not be removed.');
  }
}
