import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import '../romm/models.dart';
import '../progress/files.dart';

class ProfileAccess {
  const ProfileAccess({this.rejected = false, this.games = const {}});
  final bool rejected;
  final Map<int, bool> games;
  bool permits(int game, {required bool downloadedByAccount}) =>
      !rejected && (games[game] ?? downloadedByAccount);
}

class SavedServer {
  const SavedServer(this.id, this.address, this.version);
  factory SavedServer.fromJson(Map j) => SavedServer(
    j['id'] as String,
    j['address'] as String,
    j['version'] as String,
  );
  final String id, address, version;
  Map<String, dynamic> toJson() => {
    'id': id,
    'address': address,
    'version': version,
  };
}

class SavedProfile {
  const SavedProfile(this.id, this.serverId, this.userId, this.name);
  factory SavedProfile.fromJson(Map j) => SavedProfile(
    j['id'] as String,
    j['serverId'] as String,
    j['userId'] as int,
    j['name'] as String,
  );
  final String id, serverId, name;
  final int userId;
  Map<String, dynamic> toJson() => {
    'id': id,
    'serverId': serverId,
    'userId': userId,
    'name': name,
  };
}

class ShellPreferences {
  const ShellPreferences({
    this.reduceMotion = false,
    this.showArtwork = true,
    this.pageSize = 24,
    this.maxDownloads = 3,
    this.verifyDownloads = false,
    this.updateChannel = 'auto',
    this.linuxUseKeyring = false,
  });
  factory ShellPreferences.fromJson(Map j) {
    final size = j['pageSize'] as int? ?? 24;
    if (![24, 48].contains(size))
      throw const FormatException('Invalid page size');
    final maxDownloads = j['maxDownloads'] as int? ?? 3;
    if (maxDownloads < 1 || maxDownloads > 6)
      throw const FormatException('Invalid simultaneous download limit');
    final channel = j['updateChannel'] as String? ?? 'auto';
    if (!{'auto', 'stable', 'rc'}.contains(channel))
      throw const FormatException('Invalid application update channel');
    return ShellPreferences(
      reduceMotion: j['reduceMotion'] as bool? ?? false,
      showArtwork: j['showArtwork'] as bool? ?? true,
      pageSize: size,
      maxDownloads: maxDownloads,
      verifyDownloads: j['verifyDownloads'] as bool? ?? false,
      updateChannel: channel,
      linuxUseKeyring: j['linuxUseKeyring'] as bool? ?? false,
    );
  }
  final bool reduceMotion, showArtwork, verifyDownloads, linuxUseKeyring;
  final int pageSize, maxDownloads;
  final String updateChannel;
  ShellPreferences copy({
    bool? reduceMotion,
    bool? showArtwork,
    int? pageSize,
    int? maxDownloads,
    bool? verifyDownloads,
    String? updateChannel,
    bool? linuxUseKeyring,
  }) => ShellPreferences(
    reduceMotion: reduceMotion ?? this.reduceMotion,
    showArtwork: showArtwork ?? this.showArtwork,
    pageSize: pageSize ?? this.pageSize,
    maxDownloads: maxDownloads ?? this.maxDownloads,
    verifyDownloads: verifyDownloads ?? this.verifyDownloads,
    updateChannel: updateChannel ?? this.updateChannel,
    linuxUseKeyring: linuxUseKeyring ?? this.linuxUseKeyring,
  );
  Map<String, dynamic> toJson() => {
    'reduceMotion': reduceMotion,
    'showArtwork': showArtwork,
    'pageSize': pageSize,
    'maxDownloads': maxDownloads,
    'verifyDownloads': verifyDownloads,
    'updateChannel': updateChannel,
    'linuxUseKeyring': linuxUseKeyring,
  };
}

class ShellRecords {
  const ShellRecords({
    this.servers = const [],
    this.profiles = const [],
    this.lastServer,
    this.preferences = const ShellPreferences(),
    this.emulatorDefaults = const {},
  });
  factory ShellRecords.fromJson(Map j) {
    if (j['version'] != 1)
      throw const FormatException('Unsupported settings version');
    final servers = (j['servers'] as List)
        .map((x) => SavedServer.fromJson(x as Map))
        .toList();
    final profiles = (j['profiles'] as List)
        .map((x) => SavedProfile.fromJson(x as Map))
        .toList();
    if (servers.map((s) => s.id).toSet().length != servers.length ||
        profiles.map((p) => p.id).toSet().length != profiles.length ||
        profiles.any((p) => !servers.any((s) => s.id == p.serverId)))
      throw const FormatException('Invalid account references');
    for (final server in servers) {
      if (normalizeServer(server.address).toString() != server.address)
        throw const FormatException('Invalid server address');
    }
    final defaults = <String, String>{};
    for (final entry in (j['emulatorDefaults'] as Map? ?? {}).entries) {
      final key = entry.key, value = entry.value;
      final identity = key is String
          ? RegExp(r'^([a-f0-9]{32}):([a-z0-9-]{1,80})$').firstMatch(key)
          : null;
      if (identity == null ||
          !servers.any((s) => s.id == identity.group(1)) ||
          value is! String ||
          !RegExp(r'^[a-z0-9-]{1,80}$').hasMatch(value))
        throw const FormatException('Invalid emulator default');
      defaults[key as String] = value;
    }
    return ShellRecords(
      servers: servers,
      profiles: profiles,
      lastServer: j['lastServer'] as String?,
      preferences: ShellPreferences.fromJson(j['preferences'] as Map),
      emulatorDefaults: defaults,
    );
  }
  final List<SavedServer> servers;
  final List<SavedProfile> profiles;
  final String? lastServer;
  final ShellPreferences preferences;
  final Map<String, String> emulatorDefaults;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'servers': servers.map((s) => s.toJson()).toList(),
    'profiles': profiles.map((p) => p.toJson()).toList(),
    'lastServer': lastServer,
    'preferences': preferences.toJson(),
    'emulatorDefaults': emulatorDefaults,
  };
}

class ShellStorage {
  ShellStorage(this.directory);
  final Directory directory;
  Future<void> _tail = Future.value();
  static Future<Directory> defaultDirectory() async {
    const custom = String.fromEnvironment('BROOMM_DATA_ROOT');
    if (custom.isNotEmpty) return Directory(custom);
    const project = String.fromEnvironment('BROOMM_PROJECT_ROOT');
    if (project.isNotEmpty) return Directory('$project/broomm-data');
    if (Platform.isAndroid) {
      final path = await const MethodChannel('app.broomm/platform')
          .invokeMethod<String>('dataDirectory');
      if (path == null)
        throw const FileSystemException('Android storage path unavailable');
      return Directory('$path/broomm');
    }
    final env = Platform.environment;
    if (Platform.isWindows) {
      final root = env['APPDATA'];
      if (root == null)
        throw const FileSystemException('Application data path unavailable');
      return Directory('$root/Broomm');
    }
    final home = env['HOME'];
    if (home == null)
      throw const FileSystemException('Application data path unavailable');
    return Directory(
      Platform.isMacOS
          ? '$home/Library/Application Support/Broomm'
          : '${env['XDG_CONFIG_HOME'] ?? '$home/.config'}/broomm',
    );
  }

  Future<T> _locked<T>(Future<T> Function() operation) {
    final next = _tail.then((_) async {
      await directory.create(recursive: true);
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory)
        throw const FileSystemException(
          'Settings directory is not a private directory',
        );
      final lockFile = File('${directory.path}/settings.lock');
      if (await FileSystemEntity.type(lockFile.path, followLinks: false) ==
          FileSystemEntityType.link)
        throw const FileSystemException(
          'Settings lock cannot be a symbolic link',
        );
      final lock = await lockFile.open(mode: FileMode.append);
      try {
        final until = DateTime.now().add(const Duration(seconds: 3));
        while (true) {
          try {
            await lock.lock(FileLock.exclusive);
            break;
          } on FileSystemException {
            if (DateTime.now().isAfter(until))
              throw const FileSystemException(
                'Settings are in use by another Broomm process. Try again.',
              );
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
        }
        return await operation();
      } finally {
        await lock.close();
      }
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<ShellRecords> _read() async {
    final file = File('${directory.path}/accounts.json');
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return const ShellRecords();
    if (type != FileSystemEntityType.file || await file.length() > 1024 * 1024)
      throw const FileSystemException('Settings file is invalid or too large');
    try {
      return ShellRecords.fromJson(
        jsonDecode(await file.readAsString()) as Map,
      );
    } on FormatException {
      throw const FileSystemException(
        'Saved Broomm settings are unreadable. The original file has been preserved.',
      );
    } on TypeError {
      throw const FileSystemException(
        'Saved Broomm settings are invalid. The original file has been preserved.',
      );
    }
  }

  Future<ShellRecords> load() => _locked(_read);

  Future<File> _accessFile(SavedServer server, SavedProfile profile) async {
    if (profile.serverId != server.id ||
        ![
          profile.id,
          server.id,
        ].every((id) => RegExp(r'^[a-f0-9]{32}$').hasMatch(id)))
      throw const FormatException('Invalid offline account identity');
    return progressFile(
      directory,
      'profiles/${profile.id}/romm-access.json',
      createParents: true,
    );
  }

  Future<ProfileAccess> _readAccess(
    SavedServer server,
    SavedProfile profile,
  ) async {
    final file = await _accessFile(server, profile);
    if (!await progressExists(file.path)) return const ProfileAccess();
    if (await file.length() > 2 * 1024 * 1024)
      throw const FormatException('Offline permission record is too large');
    final value = await progressJson(file);
    if (value['version'] != 1 ||
        value['server'] != server.id ||
        value['profile'] != profile.id ||
        value['user'] != profile.userId ||
        value['rejected'] is! bool ||
        value['games'] is! Map ||
        (value['games'] as Map).length > 10000)
      throw const FormatException(
        'Offline permissions do not match this account',
      );
    final games = <int, bool>{};
    for (final entry in (value['games'] as Map).entries) {
      final id = int.tryParse('${entry.key}');
      if (id == null || id < 1 || entry.value is! bool)
        throw const FormatException('Invalid offline game permission');
      games[id] = entry.value as bool;
    }
    return ProfileAccess(rejected: value['rejected'] as bool, games: games);
  }

  Future<ProfileAccess> profileAccess(SavedServer s, SavedProfile p) =>
      _locked(() => _readAccess(s, p));

  Future<void> updateProfileAccess(
    SavedServer server,
    SavedProfile profile, {
    bool? rejected,
    Map<int, bool> games = const {},
  }) => _locked(() async {
    final before = await _readAccess(server, profile);
    final next = {...before.games, ...games};
    if (next.length > 10000 || next.keys.any((id) => id < 1))
      throw const FormatException('Too many offline game permissions');
    await progressWrite(await _accessFile(server, profile), {
      'version': 1,
      'server': server.id,
      'profile': profile.id,
      'user': profile.userId,
      'rejected': rejected ?? before.rejected,
      'games': {for (final entry in next.entries) '${entry.key}': entry.value},
    });
  });
  Future<ShellRecords> _change(ShellRecords Function(ShellRecords) change) =>
      _locked(() async {
        final next = change(await _read());
        final text =
            '${const JsonEncoder.withIndent('  ').convert(next.toJson())}\n';
        final staging = File('${directory.path}/accounts-${_id()}.tmp');
        try {
          await staging.writeAsString(text, flush: true);
          await staging.rename('${directory.path}/accounts.json');
          if (await File('${directory.path}/accounts.json').readAsString() !=
              text)
            throw const FileSystemException(
              'Settings could not be verified after saving',
            );
        } finally {
          if (await staging.exists()) await staging.delete();
        }
        return next;
      });
  Future<ShellRecords> saveServer(Uri address, String version) => _change((s) {
    final servers = List<SavedServer>.of(s.servers);
    final existing = servers
        .where((x) => x.address == address.toString())
        .firstOrNull;
    final server = existing ?? SavedServer(_id(), address.toString(), version);
    if (existing == null) servers.add(server);
    return ShellRecords(
      servers: servers,
      profiles: s.profiles,
      lastServer: server.id,
      preferences: s.preferences,
      emulatorDefaults: s.emulatorDefaults,
    );
  });
  Future<ShellRecords> saveProfile(SavedServer server, RommUser user) =>
      _change((s) {
        final profiles = List<SavedProfile>.of(s.profiles);
        final index = profiles.indexWhere(
          (p) => p.serverId == server.id && p.userId == user.id,
        );
        final record = SavedProfile(
          index < 0 ? _id() : profiles[index].id,
          server.id,
          user.id,
          user.name,
        );
        if (index < 0)
          profiles.add(record);
        else
          profiles[index] = record;
        return ShellRecords(
          servers: s.servers,
          profiles: profiles,
          lastServer: server.id,
          preferences: s.preferences,
          emulatorDefaults: s.emulatorDefaults,
        );
      });
  Future<ShellRecords> preferences(ShellPreferences value) => _change(
    (s) => ShellRecords(
      servers: s.servers,
      profiles: s.profiles,
      lastServer: s.lastServer,
      preferences: value,
      emulatorDefaults: s.emulatorDefaults,
    ),
  );
  Future<ShellRecords> emulatorDefault(
    String serverId,
    String platform,
    String emulator,
  ) => emulatorDefaults(serverId, {platform: emulator});

  Future<ShellRecords> clearEmulatorDefaults() => _change(
    (s) => ShellRecords(
      servers: s.servers,
      profiles: s.profiles,
      lastServer: s.lastServer,
      preferences: s.preferences,
    ),
  );

  Future<ShellRecords> removeEmulatorDefaults(String emulator) => _change(
    (s) => ShellRecords(
      servers: s.servers,
      profiles: s.profiles,
      lastServer: s.lastServer,
      preferences: s.preferences,
      emulatorDefaults: {
        for (final entry in s.emulatorDefaults.entries)
          if (entry.value != emulator) entry.key: entry.value,
      },
    ),
  );

  Future<ShellRecords> emulatorDefaults(
    String serverId,
    Map<String, String> choices,
  ) => _change((s) {
    if (!s.servers.any((server) => server.id == serverId) ||
        choices.entries.any(
          (entry) =>
              !RegExp(r'^[a-z0-9_-]{1,80}$').hasMatch(entry.key) ||
              !RegExp(r'^[a-z0-9_-]{1,80}$').hasMatch(entry.value),
        )) {
      throw const FormatException('Invalid emulator preference');
    }
    return ShellRecords(
      servers: s.servers,
      profiles: s.profiles,
      lastServer: s.lastServer,
      preferences: s.preferences,
      emulatorDefaults: {
        ...s.emulatorDefaults,
        for (final entry in choices.entries)
          '$serverId:${entry.key}': entry.value,
      },
    );
  });
  static String _id() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
