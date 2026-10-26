import 'dart:convert';

import '../romm/models.dart';
import 'credentials.dart';
import 'storage.dart';

/// A separate, typed native-store slot. It cannot overwrite the RomM token.
class SteamGridCredentials {
  SteamGridCredentials(this.store);
  final ProfileCredentials store;
  Future<String?> read(SavedServer server, SavedProfile profile) =>
      store.locked(profile.id, () async {
        final value = await store.backend.read('sgdb-${profile.id}');
        if (value == null) return null;
        try {
          if (value.length > 4096) throw const FormatException();
          final j = jsonDecode(value) as Map;
          if (j['version'] != 1 ||
              j['server'] != server.address ||
              j['user'] != profile.userId ||
              profile.serverId != server.id)
            throw const FormatException();
          return validKey(j['key']);
        } catch (_) {
          throw const CredentialFailure(
            'The saved SteamGridDB key is damaged or belongs to a different profile. Update it in Broomm settings.',
          );
        }
      });
  Future<void> write(SavedServer server, SavedProfile profile, String input) =>
      store.locked(profile.id, () async {
        final key = validKey(input.trim());
        final text = jsonEncode({
          'version': 1,
          'server': server.address,
          'user': profile.userId,
          'key': key,
        });
        final slot = 'sgdb-${profile.id}';
        await store.backend.write(slot, text);
        if (await store.backend.read(slot) != text)
          throw const CredentialFailure(
            'The SteamGridDB key could not be verified.',
          );
      });
  Future<void> delete(SavedProfile profile) =>
      store.locked(profile.id, () async {
        final slot = 'sgdb-${profile.id}';
        await store.backend.delete(slot);
        if (await store.backend.read(slot) != null)
          throw const CredentialFailure(
            'The SteamGridDB key could not be removed.',
          );
      });
  static String validKey(Object? input) {
    if (input is! String ||
        input.isEmpty ||
        input.length > 512 ||
        input.contains(RegExp(r'[\x00-\x20\x7f]')))
      throw const RommFailure('Enter your SteamGridDB API key.');
    return input;
  }
}
