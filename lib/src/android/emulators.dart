import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../game_launch.dart';
import '../retroarch.dart';
import '../progress/files.dart';
import '../romm/models.dart';

/// Android applications, not desktop bundles. These are concrete, researched
/// launch contracts; metadata and imported setup files cannot supply intents.
class AndroidEmulator {
  const AndroidEmulator(
    this.id,
    this.name,
    this.packages,
    this.platforms,
    this.installUrl,
    this.activity,
    this.action, {
    this.saveNote,
  });
  final String id, name, activity, action, installUrl;
  final Set<String> platforms;
  final List<String> packages;
  final String? saveNote;
}

const androidEmulators = [
  AndroidEmulator(
    'retroarch',
    'RetroArch',
    ['com.retroarch.aarch64', 'com.retroarch', 'com.retroarch.ra32'],
    {
      '3do',
      'arcade',
      'atari2600',
      'jaguar',
      'jaguarcd',
      'lynx',
      'dreamcast',
      'gb',
      'gbc',
      'gba',
      'n64',
      'nes',
      'sega32',
      'gamegear',
      'sms',
      'genesis',
      'saturn',
      'snes',
      'tg16',
    },
    'https://www.retroarch.com/?page=platforms',
    'com.retroarch.browser.retroactivity.RetroActivityFuture',
    'android.intent.action.MAIN',
    saveNote: 'Install the platform’s core in RetroArch before launching. Android cloud saves, states and automatic core/BIOS setup are not integrated yet.',
  ),
  AndroidEmulator(
    'ppsspp',
    'PPSSPP',
    ['org.ppsspp.ppsspp', 'org.ppsspp.ppssppgold'],
    {'psp'},
    'https://www.ppsspp.org/download/',
    'org.ppsspp.ppsspp.PpssppActivity',
    'android.intent.action.VIEW',
    saveNote: 'Use PPSSPP’s Memory Stick folder. Savedata and matching Android states can be synchronized after the emulator is closed.',
  ),
  AndroidEmulator(
    'melonds',
    'melonDS',
    ['me.magnum.melonds'],
    {'nds'},
    'https://github.com/rafaelvcaetano/melonDS-android/releases',
    'me.magnum.melonds.ui.emulator.EmulatorActivity',
    'me.magnum.melonds.LAUNCH_ROM',
    saveNote: 'Select the custom save folder configured in melonDS. Raw .sav files are compatible; Android states require their own verified format.',
  ),
  AndroidEmulator(
    'azahar',
    'Azahar',
    ['org.azahar_emu.azahar'],
    {'3ds'},
    'https://github.com/azahar-emu/azahar/releases',
    'org.citra.citra_emu.activities.EmulationActivity',
    'android.intent.action.VIEW',
    saveNote: 'Select Azahar’s user folder in Android’s document picker. CIA installation uses Azahar’s own installer; desktop native importers cannot run on Android.',
  ),
  AndroidEmulator(
    'dolphin',
    'Dolphin',
    ['org.dolphinemu.dolphinemu'],
    {'ngc', 'wii'},
    'https://dolphin-emu.org/download/',
    'org.dolphinemu.dolphinemu.ui.main.MainActivity',
    'android.intent.action.MAIN',
    saveNote: 'Android cloud saves, states and Wii package installation are not integrated yet. Your existing progress stays in Dolphin.',
  ),
  AndroidEmulator(
    'eden',
    'Eden',
    ['dev.eden.eden_emulator'],
    {'switch'},
    'https://git.eden-emu.dev/eden-emu/eden/releases',
    'org.yuzu.yuzu_emu.activities.EmulationActivity',
    'android.intent.action.VIEW',
    saveNote: 'Android Switch saves, firmware and NSP installation are not integrated yet. Your existing progress stays in Eden. This emulator has no save states.',
  ),
  AndroidEmulator(
    'armsx2',
    'ARMSX2',
    ['com.armsx2'],
    {'ps2'},
    'https://github.com/ARMSX2/ARMSX2/releases',
    'com.armsx2.MainActivity',
    'android.intent.action.VIEW',
    saveNote: 'Android memory-card and state synchronization are not integrated yet. Your existing progress stays in ARMSX2.',
  ),
  AndroidEmulator(
    'duckstation',
    'DuckStation',
    ['com.github.stenzek.duckstation'],
    {'psx'},
    'https://play.google.com/store/apps/details?id=com.github.stenzek.duckstation',
    'com.github.stenzek.duckstation.EmulationActivity',
    'android.intent.action.MAIN',
    saveNote: 'Android memory-card and state synchronization are not integrated yet. Shared multi-game cards are not uploaded as one game’s progress.',
  ),
];

class AndroidApp {
  const AndroidApp(
    this.package,
    this.version,
    this.build, {
    this.enabled = true,
  });
  final String package, version, build;
  final bool enabled;
}

class AndroidEmulators extends ChangeNotifier {
  AndroidEmulators(this.data, {MethodChannel? channel, bool? enabled})
    : channel = channel ?? const MethodChannel('app.broomm/emulators'),
      enabled = enabled ?? Platform.isAndroid {
    if (this.enabled)
      this.channel.setMethodCallHandler((call) async {
        if (call.method == 'installationChanged') {
          await load();
          return;
        }
        if (call.method == 'installFailed') error = '${call.arguments}';
        _emit();
      });
  }
  final Directory data;
  final MethodChannel channel;
  final bool enabled;
  final installed = <String, AndroidApp>{};
  final _trees = <String, String>{};
  bool busy = false, _disposed = false;
  bool settingsKnown = false;
  String? error;

  List<AndroidEmulator> choices(RommPlatform platform) {
    final canonical = gamePlatform(
      RommGame(
        id: 0,
        name: '',
        platformId: platform.id,
        platform: platform.name,
        platformSlug: platform.slug,
      ),
      [platform],
    )?.slug;
    return androidEmulators
        .where(
          (e) =>
              e.platforms.contains(canonical) ||
              e.id == 'retroarch' &&
                  canonical != null &&
                  retroSystem(canonical) != null,
        )
        .toList();
  }

  AndroidApp? app(AndroidEmulator emulator) {
    final apps = emulator.packages
        .map((p) => installed[p])
        .whereType<AndroidApp>()
        .toList();
    return apps.where((a) => a.enabled).firstOrNull ?? apps.firstOrNull;
  }

  String _key(String profile, AndroidEmulator emulator) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(profile))
      throw const FormatException('Invalid Android profile identity');
    return '$profile:${emulator.id}';
  }

  String? tree(String profile, AndroidEmulator emulator) =>
      _trees[_key(profile, emulator)];
  bool progressSupported(AndroidEmulator emulator) =>
      {'ppsspp', 'melonds', 'azahar'}.contains(emulator.id);

  Future<Directory> privateRoot(
    String profile,
    AndroidEmulator emulator,
  ) async {
    _key(profile, emulator);
    if (!progressSupported(emulator))
      throw UnsupportedError(
        'Android save integration for ${emulator.name} is not implemented yet. Its external progress is kept.',
      );
    final root = Directory(
      '${data.path}/profiles/$profile/emulators/${emulator.id}',
    );
    await progressDirectory(root);
    final owner = await progressFile(root, 'profile.json');
    if (await owner.exists()) {
      final j = await progressJson(owner);
      if (j['version'] != 1 ||
          j['emulator'] != emulator.id ||
          j['profile'] != profile)
        throw const FileSystemException(
          'Unrecognized Android progress directory; files were kept.',
        );
    } else {
      if (await root.list(followLinks: false).isEmpty == false)
        throw const FileSystemException(
          'Unrecognized Android emulator files were kept. Restore its ownership record before continuing.',
        );
      await progressWrite(owner, {
        'version': 1,
        'emulator': emulator.id,
        'profile': profile,
      });
    }
    await progressDirectory(Directory('${root.path}/user'));
    return root;
  }

  Future<void> load() async {
    if (!enabled || busy) return;
    busy = true;
    error = null;
    settingsKnown = false;
    _emit();
    try {
      final file = File('${data.path}/android/emulators.json');
      if (await progressExists('${data.path}/android'))
        await progressFile(data, 'android/emulators.json');
      if (await progressExists(file.path)) {
        final record = await progressJson(file);
        if (record['version'] != 1 || record['trees'] is! Map)
          throw const FormatException('Invalid Android emulator settings');
        final trees = (record['trees'] as Map).cast<String, String>();
        for (final entry in trees.entries) {
          if (!RegExp(r'^[a-f0-9]{32}:[a-z0-9]+$').hasMatch(entry.key) ||
              !_rootMatches(entry.key, entry.value))
            throw const FormatException('Invalid Android storage grant');
        }
        _trees
          ..clear()
          ..addAll(trees);
      } else {
        _trees.clear();
      }
      settingsKnown = true;
      final rows = await channel.invokeListMethod<Object?>('installed', {
        'packages': androidEmulators.expand((e) => e.packages).toList(),
      });
      if (rows == null)
        throw StateError('Android returned no installation status.');
      final found = <String, AndroidApp>{};
      for (final row in rows.cast<Map>()) {
        final package = row['package'] as String;
        if (!androidEmulators.any((e) => e.packages.contains(package)) ||
            found.containsKey(package) ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(row['build'] as String))
          throw const FormatException('Invalid Android application identity');
        found[package] = AndroidApp(
          package,
          row['version'] as String,
          row['build'] as String,
          enabled: row['enabled'] != 'false',
        );
      }
      installed
        ..clear()
        ..addAll(found);
    } catch (e) {
      // A failed query must never turn known applications into "not installed".
      error = 'Android emulator status could not be checked. $e';
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> install(AndroidEmulator emulator) =>
      channel.invokeMethod<void>('installPage', {'url': emulator.installUrl});

  Future<void> installApk(AndroidEmulator emulator) =>
      channel.invokeMethod<void>('installApk', {'packages': emulator.packages});

  Future<void> open(AndroidEmulator emulator) async {
    final selected = app(emulator);
    if (selected == null) throw StateError('Install ${emulator.name} first.');
    if (!selected.enabled)
      throw StateError(
        'Enable ${emulator.name} in Android app settings first.',
      );
    await channel.invokeMethod<void>('open', {'package': selected.package});
  }

  Future<String> exposeStorage(
    String profile,
    String name,
    AndroidEmulator emulator,
  ) async {
    await ensureNoWriters();
    await privateRoot(profile, emulator);
    final safeName = String.fromCharCodes(
      name.runes.where((r) => r >= 32 && r != 127).take(60),
    );
    return (await channel.invokeMethod<String>('dataRoot', {
      'profile': profile,
      'emulator': emulator.id,
      'label':
          'Broomm · ${safeName.substring(0, safeName.length.clamp(0, 60))} · ${emulator.name}',
    }))!;
  }

  Future<void> confirmStorage(
    String profile,
    AndroidEmulator emulator,
    String uri,
  ) async {
    await ensureNoWriters();
    final key = _key(profile, emulator);
    if (!settingsKnown)
      throw StateError(
        'Android emulator settings could not be read. Existing folders were kept.',
      );
    if (!_treeUri(uri))
      throw const FormatException('Invalid Android folder grant');
    if (!_rootMatches(key, uri))
      throw const FormatException(
        'Android progress folder belongs to another emulator/profile',
      );
    // A shared external directory cannot be assigned to two profile histories.
    if (_trees.entries.any((e) => e.key != key && e.value == uri))
      throw StateError(
        'This emulator folder belongs to another profile. Choose a separate folder to keep progress private.',
      );
    final next = {..._trees, key: uri};
    await progressWrite(
      await progressFile(data, 'android/emulators.json', createParents: true),
      {'version': 1, 'trees': next},
    );
    _trees
      ..clear()
      ..addAll(next);
    _emit();
  }

  Future<String> fingerprint(AndroidApp app) async {
    final hash = await channel.invokeMethod<String>('fingerprint', {
      'package': app.package,
    });
    if (hash == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))
      throw StateError('The Android emulator build could not be verified.');
    return hash;
  }

  static bool _treeUri(String value) {
    final u = Uri.tryParse(value);
    return value.length < 4096 &&
        !value.contains('\u0000') &&
        u != null &&
        u.scheme == 'content' &&
        u.authority.isNotEmpty &&
        u.pathSegments.contains('tree');
  }

  static bool _rootMatches(String key, String value) {
    if (!_treeUri(value)) return false;
    final uri = Uri.parse(value);
    return uri.authority == 'app.broomm.broomm.emulator-data' &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments[1] == key &&
        {'ppsspp', 'melonds', 'azahar'}.contains(key.split(':').last);
  }

  Future<String> launch(
    AndroidEmulator emulator,
    AndroidApp app,
    List<String> files,
    String selected, {
    String? core,
    String? profile,
  }) async {
    if (!settingsKnown)
      throw StateError(
        'Android emulator settings could not be read. Refresh or repair them before launching.',
      );
    if (!emulator.packages.contains(app.package) || !files.contains(selected))
      throw const FormatException('Android emulator/game selection changed');
    if (!app.enabled)
      throw StateError(
        'Enable ${emulator.name} in Android app settings first.',
      );
    return (await channel.invokeMethod<String>('launch', {
      'package': app.package,
      'build': app.build,
      'activity': emulator.activity,
      'action': emulator.action,
      'emulator': emulator.id,
      'files': files,
      'selected': selected,
      if (core != null) 'core': core,
      if (profile != null && tree(profile, emulator) != null)
        'root': _key(profile, emulator),
    }))!;
  }

  Future<void> releaseGrants() => channel.invokeMethod<void>('releaseGrants');

  Future<void> ensureNoWriters() async {
    final writers = await channel.invokeMethod<int>('writers');
    if (writers == null || writers != 0)
      throw StateError(
        'An Android emulator still has writable save files open. Close it before synchronizing.',
      );
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (enabled) channel.setMethodCallHandler(null);
    super.dispose();
  }
}
