import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../game_launch.dart';
import '../retroarch.dart';
import '../progress/files.dart';
import '../romm/models.dart';
import '../session_lease.dart';
import 'apk_download.dart';
import 'retroarch_core_setup.dart';
import 'root_saves.dart';

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
    this.action,
  );
  final String id, name, activity, action, installUrl;
  final Set<String> platforms;
  final List<String> packages;
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
  ),
  AndroidEmulator(
    'ppsspp',
    'PPSSPP',
    ['org.ppsspp.ppsspp', 'org.ppsspp.ppssppgold'],
    {'psp'},
    'https://www.ppsspp.org/download/',
    'org.ppsspp.ppsspp.PpssppActivity',
    'android.intent.action.VIEW',
  ),
  AndroidEmulator(
    'melonds',
    'melonDS',
    ['me.magnum.melonds'],
    {'nds'},
    'https://github.com/rafaelvcaetano/melonDS-android/releases',
    'me.magnum.melonds.ui.emulator.EmulatorActivity',
    'me.magnum.melonds.LAUNCH_ROM',
  ),
  AndroidEmulator(
    'azahar',
    'Azahar',
    ['org.azahar_emu.azahar'],
    {'3ds'},
    'https://github.com/azahar-emu/azahar/releases',
    'org.citra.citra_emu.activities.EmulationActivity',
    'android.intent.action.VIEW',
  ),
  AndroidEmulator(
    'citra-mmj',
    'Citra MMJ',
    ['org.citra.emu', 'com.antutu.ABenchMark'],
    {'3ds'},
    'https://github.com/weihuoya/citra/releases',
    'org.citra.emu.ui.EmulationActivity',
    'android.intent.action.VIEW',
  ),
  AndroidEmulator(
    'dolphin',
    'Dolphin',
    ['org.dolphinemu.dolphinemu'],
    {'ngc', 'wii'},
    'https://dolphin-emu.org/download/',
    'org.dolphinemu.dolphinemu.ui.main.MainActivity',
    'android.intent.action.MAIN',
  ),
  AndroidEmulator(
    'eden',
    'Eden',
    ['dev.eden.eden_emulator'],
    {'switch'},
    'https://git.eden-emu.dev/eden-emu/eden/releases',
    'org.yuzu.yuzu_emu.activities.EmulationActivity',
    'android.intent.action.VIEW',
  ),
  AndroidEmulator(
    'armsx2',
    'ARMSX2',
    ['com.armsx2', 'com.armsx2.nightly'],
    {'ps2'},
    'https://github.com/ARMSX2/ARMSX2/releases',
    'com.armsx2.MainActivity',
    'android.intent.action.VIEW',
  ),
  AndroidEmulator(
    'duckstation',
    'DuckStation',
    ['com.github.stenzek.duckstation'],
    {'psx'},
    'https://play.google.com/store/apps/details?id=com.github.stenzek.duckstation',
    'com.github.stenzek.duckstation.EmulationActivity',
    'android.intent.action.MAIN',
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
          await load(
            installationConfirmed:
                (call.arguments as Map?)?['installed'] == true,
          );
          return;
        }
        if (call.method == 'installFailed') error = '${call.arguments}';
        _emit();
      });
  }
  final Directory data;
  final MethodChannel channel;
  final bool enabled;
  void Function(String)? phase;
  final installed = <String, AndroidApp>{};
  final _trees = <String, String>{};
  final _folders = <String, Map<String, String>>{};
  final _gbaRoots = <String, Map<String, String>>{};
  final _snesRoots = <String, Map<String, String>>{};
  final _retroRoots = <String, Map<String, String>>{};
  final _fingerprints = <String, String>{};
  bool busy = false, _disposed = false;
  AndroidApkDownload? _download;
  String? installing;
  bool requestingInstallPermission = false;
  bool _installActionActive = false;
  int downloadedBytes = 0;
  int? downloadBytes;
  void cancelDownload() => _download?.cancel();
  bool settingsKnown = false;
  String? error;
  Future<void> Function(String server, AndroidEmulator emulator)? onInstalled;
  Future<void> Function(AndroidEmulator emulator)? onRemoved;
  String? removalEmulator;

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

  AndroidApp? app(AndroidEmulator emulator, {String? package}) {
    if (package != null)
      return emulator.packages.contains(package) ? installed[package] : null;
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

  String? tree(String profile, AndroidEmulator emulator, {String? package}) =>
      folder(emulator, package: package)?['tree'] ??
      _trees[_key(profile, emulator)];
  Map<String, String>? folder(AndroidEmulator emulator, {String? package}) {
    final selected = app(emulator, package: package);
    return selected == null
        ? null
        : _folders['${emulator.id}:${selected.package}'];
  }

  Map<String, String>? gbaRoot(AndroidEmulator emulator, {String? package}) {
    final selected = app(emulator, package: package);
    return emulator.id == 'retroarch' && selected != null
        ? _gbaRoots[selected.package]
        : null;
  }

  Map<String, String>? rootConnection(
    AndroidEmulator emulator,
    String platform, {
    String? package,
  }) {
    final selected = app(emulator, package: package);
    if (emulator.id != 'retroarch' ||
        selected == null ||
        androidRootRetroCore(platform) == null)
      return null;
    return _rootBindings(platform)[_rootBindingKey(platform, selected.package)];
  }

  Map<String, Map<String, String>> _rootBindings(String platform) =>
      switch (platform) {
        'gba' => _gbaRoots,
        'snes' => _snesRoots,
        'gb' ||
        'gbc' ||
        'atari2600' ||
        'tg16' ||
        'genesis' ||
        'sms' ||
        'gamegear' ||
        'sega32' ||
        'n64' => _retroRoots,
        _ => throw UnsupportedError('Unsupported rooted RetroArch system.'),
      };

  String _rootBindingKey(String platform, String package) =>
      {'gba', 'snes'}.contains(platform) ? package : '$platform:$package';

  bool hasCurrentRoot(
    AndroidEmulator emulator,
    String platform, {
    String? package,
  }) {
    final binding = rootConnection(emulator, platform, package: package);
    return binding != null &&
        binding['build'] == app(emulator, package: package)?.build;
  }

  bool hasCurrentGbaRoot(AndroidEmulator emulator, {String? package}) {
    final binding = gbaRoot(emulator, package: package);
    return binding != null &&
        binding['build'] == app(emulator, package: package)?.build;
  }

  bool connected(
    String profile,
    AndroidEmulator emulator, {
    String? platform,
  }) =>
      (platform == null &&
          (gbaRoot(emulator) != null ||
              rootConnection(emulator, 'snes') != null ||
              rootConnection(emulator, 'gb') != null ||
              rootConnection(emulator, 'gbc') != null ||
              rootConnection(emulator, 'atari2600') != null ||
              rootConnection(emulator, 'tg16') != null ||
              rootConnection(emulator, 'genesis') != null ||
              rootConnection(emulator, 'sms') != null ||
              rootConnection(emulator, 'gamegear') != null ||
              rootConnection(emulator, 'sega32') != null ||
              rootConnection(emulator, 'n64') != null)) ||
      (platform != null && hasCurrentRoot(emulator, platform)) ||
      tree(profile, emulator) != null;

  Future<AndroidApp> _checkGbaRootChange(AndroidEmulator emulator) async {
    if (!settingsKnown || emulator.id != 'retroarch')
      throw StateError('Refresh RetroArch before connecting root saves.');
    if (await progressExists('${data.path}/android/session.json') ||
        await progressExists('${data.path}/android/shared-swap.json'))
      throw StateError(
        'Finish the pending Android session before changing its storage connection.',
      );
    await ensureNoWriters(closureConfirmed: true);
    final selected = app(emulator);
    if (selected == null || !selected.enabled)
      throw StateError('Install and enable RetroArch first.');
    return selected;
  }

  /// Returns the package whose standard first run still needs to be opened.
  Future<AndroidApp?> connectGbaRoot(
    AndroidEmulator emulator, {
    String platform = 'gba',
  }) => _withInstallPermission(
    () => _connectGbaRoot(emulator, platform),
    requiresApkPermission: false,
  );

  Future<AndroidApp?> _connectGbaRoot(
    AndroidEmulator emulator,
    String platform,
  ) async {
    if (androidRootRetroCore(platform) == null)
      throw UnsupportedError('Unsupported rooted RetroArch system.');
    final core = androidRootRetroCore(platform)!;
    final lease = await SessionLease.acquire(data);
    try {
      final selected = await _checkGbaRootChange(emulator);
      phase?.call('Checking RetroArch and $core.');
      final setup = await channel.invokeMapMethod<String, dynamic>(
        core == 'mgba' ? 'rootMgbaSetup' : 'rootCoreSetup',
        {
          'package': selected.package,
          'build': selected.build,
          'coreName': core,
        },
      );
      if (setup == null ||
          setup['abi'] is! String ||
          (setup['core'] != null &&
              (setup['core'] is! String ||
                  !RegExp(r'^[a-f0-9]{64}$')
                      .hasMatch(setup['core'] as String))))
        throw const FormatException('Invalid mGBA setup report.');
      final identity = androidRetroArchRootIdentity(
        setup,
        selected,
        platform: platform,
      );
      var verifiedCore = setup['core'] as String?;
      if (verifiedCore == null) {
        final download = _download = AndroidApkDownload();
        installing = core;
        downloadedBytes = 0;
        downloadBytes = null;
        _emit();
        phase?.call('Downloading the reviewed Android $core core.');
        try {
          await downloadAndroidRetroCore(
            data,
            core,
            setup['abi'] as String,
            download,
            progress: (bytes, total) {
              downloadedBytes = bytes;
              downloadBytes = total;
              _emit();
            },
            publish: (stage, sha256) async {
              installing = null;
              _emit();
              phase?.call('Installing the verified $core core in RetroArch.');
              verifiedCore = await channel.invokeMethod<String>(
                core == 'mgba' ? 'rootInstallMgba' : 'rootInstallCore',
                {
                  ...identity,
                  'coreName': core,
                  'stage': stage,
                  'sha256': sha256,
                },
              );
            },
          );
        } finally {
          installing = null;
          _download = null;
          _emit();
        }
      }
      final report = await inspectAndroidRetroArchRoot(
        this,
        selected,
        platform: platform,
      );
      final binding = androidRetroArchRootIdentity(
        report,
        selected,
        platform: platform,
      );
      if (!mapEquals(identity, binding) || report['core'] != verifiedCore)
        throw StateError('RetroArch changed during setup. Refresh and retry.');
      if (androidRetroArchNeedsSetup(report, selected)) return selected;
      final roots = _rootBindings(platform);
      final next = {
        ...roots,
        _rootBindingKey(platform, selected.package): binding,
      };
      await _save(
        gbaRoots: platform == 'gba' ? next : null,
        snesRoots: platform == 'snes' ? next : null,
        retroRoots:
            {
              'gb',
              'gbc',
              'atari2600',
              'tg16',
              'genesis',
              'sms',
              'gamegear',
              'sega32',
              'n64',
            }.contains(platform)
            ? next
            : null,
      );
      roots
        ..clear()
        ..addAll(next);
      phase?.call('$core saves and states are ready.');
      _emit();
      return null;
    } finally {
      await lease.release();
    }
  }

  Future<void> disconnectGbaRoot(
    AndroidEmulator emulator, {
    String platform = 'gba',
  }) async {
    if (androidRootRetroCore(platform) == null)
      throw UnsupportedError('Unsupported rooted RetroArch system.');
    final selected = await _checkGbaRootChange(emulator);
    final roots = _rootBindings(platform);
    final next = {...roots}
      ..remove(_rootBindingKey(platform, selected.package));
    await _save(
      gbaRoots: platform == 'gba' ? next : null,
      snesRoots: platform == 'snes' ? next : null,
      retroRoots:
          {
            'gb',
            'gbc',
            'atari2600',
            'tg16',
            'genesis',
            'sms',
            'gamegear',
            'sega32',
            'n64',
          }.contains(platform)
          ? next
          : null,
    );
    roots
      ..clear()
      ..addAll(next);
    _emit();
  }

  File get _removal => File('${data.path}/android/removal.json');

  Future<Map<String, dynamic>?> pendingRemoval() async {
    if (!await progressExists(_removal.path)) return null;
    final record = await progressJson(
      await progressFile(data, 'android/removal.json'),
    );
    if (record['version'] != 1 ||
        !androidEmulators.any(
          (e) =>
              e.id == record['emulator'] &&
              e.packages.contains(record['package']),
        ) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(record['build'] as String? ?? ''))
      throw const FormatException(
        'Invalid emulator removal record. Files were kept.',
      );
    return record;
  }

  Future<void> ensureSetupAllowed() async {
    if (!settingsKnown)
      throw StateError('Refresh emulator settings before continuing setup.');
    for (final name in ['session', 'shared-swap', 'mmj-swap']) {
      if (await progressExists('${data.path}/android/$name.json'))
        throw StateError(
          'Finish the previous Android session before changing emulator setup.',
        );
    }
    await ensureNoWriters(closureConfirmed: true);
  }

  Future<bool> remove(AndroidEmulator emulator, {AndroidApp? expected}) async {
    if (_installActionActive || installing != null || busy)
      throw StateError('Finish the current emulator setup first.');
    _installActionActive = true;
    final SessionLease lease;
    try {
      lease = await SessionLease.acquire(data);
    } catch (_) {
      _installActionActive = false;
      rethrow;
    }
    try {
      if (!settingsKnown) throw StateError('Refresh emulator settings first.');
      for (final name in ['session', 'shared-swap', 'mmj-swap']) {
        if (await progressExists('${data.path}/android/$name.json'))
          throw StateError(
            'Finish the previous Android session before removing an emulator.',
          );
      }
      await ensureNoWriters(closureConfirmed: true, allowRemoval: true);
      var record = await pendingRemoval();
      if (record != null && record['emulator'] != emulator.id)
        throw StateError('Finish the pending emulator removal first.');
      if (expected != null) {
        if (!emulator.packages.contains(expected.package) ||
            app(emulator, package: expected.package)?.build != expected.build)
          throw StateError('The emulator changed. Refresh and retry removal.');
        record = {
          'version': 1,
          'emulator': emulator.id,
          'package': expected.package,
          'build': expected.build,
        };
        await progressWrite(
          await progressFile(data, 'android/removal.json', createParents: true),
          record,
        );
      }
      if (record == null)
        throw StateError('No emulator installation was selected.');
      removalEmulator = emulator.id;
      _emit();
      final package = record['package'] as String;
      await load();
      if (!settingsKnown || error != null)
        throw StateError(
          'Emulator status could not be verified. Retry removal.',
        );
      final current = app(emulator, package: package);
      if (current != null) {
        if (current.build != record['build'])
          throw StateError(
            'The emulator changed. Confirm removal of the current installation.',
          );
        final removed = await channel.invokeMethod<bool>('uninstall', {
          'package': package,
          'build': current.build,
        });
        if (removed == null)
          throw StateError(
            'Android did not confirm emulator removal. Retry removal.',
          );
        if (!removed) {
          await _removal.delete();
          removalEmulator = null;
          return false;
        }
        await load();
        if (!settingsKnown ||
            error != null ||
            app(emulator, package: package) != null)
          throw StateError(
            'Emulator removal could not be verified. Retry removal.',
          );
      }
      final folders = {..._folders}..remove('${emulator.id}:$package');
      final roots = {..._gbaRoots}..remove(package);
      final snesRoots = {..._snesRoots}..remove(package);
      final retroRoots = {..._retroRoots}
        ..removeWhere((key, _) => key.endsWith(':$package'));
      final trees = Map<String, String>.fromEntries(
        _trees.entries.where((e) => !e.key.endsWith(':${emulator.id}')),
      );
      await channel.invokeMethod<void>('clearEmulatorSetup', {
        'package': package,
        'emulator': emulator.id,
      });
      await _save(
        trees: trees,
        folders: folders,
        gbaRoots: roots,
        snesRoots: snesRoots,
        retroRoots: retroRoots,
      );
      _trees
        ..clear()
        ..addAll(trees);
      _folders
        ..clear()
        ..addAll(folders);
      _gbaRoots
        ..clear()
        ..addAll(roots);
      _snesRoots
        ..clear()
        ..addAll(snesRoots);
      _retroRoots
        ..clear()
        ..addAll(retroRoots);
      await onRemoved?.call(emulator);
      if (await progressExists(_installation.path) &&
          (await progressJson(_installation))['emulator'] == emulator.id)
        await _installation.delete();
      await _removal.delete();
      removalEmulator = null;
      phase?.call(
        '${emulator.name} removed and its Broomm configuration cleared.',
      );
      return true;
    } finally {
      _installActionActive = false;
      await lease.release();
      _emit();
    }
  }

  bool progressSupported(AndroidEmulator emulator) =>
      androidEmulators.contains(emulator);

  Map<String, String> folderArguments(
    AndroidEmulator emulator, {
    String? package,
  }) {
    final value = folder(emulator, package: package);
    if (value == null)
      throw StateError(
        'Connect ${emulator.name}’s save folder in Emulator Settings first.',
      );
    return {...value, 'emulator': emulator.id};
  }

  static bool sharedTree(
    AndroidEmulator emulator,
    String package,
    String value,
  ) {
    if (!_treeUri(value) || !emulator.packages.contains(package)) return false;
    final uri = Uri.parse(value);
    if (uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first != 'tree')
      return false;
    final provider = switch (emulator.id) {
      'dolphin' || 'eden' => '$package.user',
      'retroarch' => '$package.documents',
      _ => null,
    };
    if (provider != null && uri.authority == provider) return true;
    if (uri.authority != 'com.android.externalstorage.documents') return false;
    final parts = uri.pathSegments.last.split(':');
    if (parts.length != 2 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(parts.first) ||
        parts.last.isEmpty)
      return false;
    try {
      progressRelative(parts.last);
    } catch (_) {
      return false;
    }
    return parts.last.split('/').first != 'Android' &&
        (emulator.id != 'citra-mmj' || parts.last == 'citra-emu');
  }

  Future<String?> chooseFolder(
    AndroidEmulator emulator, {
    String? package,
  }) async {
    final selected = app(emulator, package: package);
    if (selected == null) throw StateError('Install ${emulator.name} first.');
    final uri = await channel.invokeMethod<String>('sharedPick', {
      'emulator': emulator.id,
      'package': selected.package,
    });
    if (uri != null && !sharedTree(emulator, selected.package, uri))
      throw StateError(
        'Choose ${emulator.name}’s own provider or a shared data folder. Private Android/data folders are unsupported.',
      );
    return uri;
  }

  Future<void> confirmSharedStorage(
    AndroidEmulator emulator,
    String uri,
  ) async {
    if (!settingsKnown) throw StateError('Refresh emulator settings first.');
    final selected = app(emulator);
    if (selected == null || !sharedTree(emulator, selected.package, uri))
      throw const FormatException('Invalid emulator folder identity');
    final binding = {'tree': uri, 'package': selected.package};
    await channel.invokeMethod<void>('sharedCheck', {
      ...binding,
      'emulator': emulator.id,
      'probe': true,
    });
    final next = {..._folders, '${emulator.id}:${selected.package}': binding};
    await _save(folders: next);
    _folders
      ..clear()
      ..addAll(next);
    _emit();
  }

  Future<void> _save({
    Map<String, String>? trees,
    Map<String, Map<String, String>>? folders,
    Map<String, Map<String, String>>? gbaRoots,
    Map<String, Map<String, String>>? snesRoots,
    Map<String, Map<String, String>>? retroRoots,
  }) async {
    await progressWrite(
      await progressFile(data, 'android/emulators.json', createParents: true),
      {
        'version': 9,
        'trees': trees ?? _trees,
        'folders': folders ?? _folders,
        'gbaRoots': gbaRoots ?? _gbaRoots,
        'snesRoots': snesRoots ?? _snesRoots,
        'retroRoots': retroRoots ?? _retroRoots,
        'fingerprints': _fingerprints,
      },
    );
  }

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

  Future<void> load({bool installationConfirmed = false}) async {
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
        if (![1, 2, 3, 4, 5, 6, 7, 8, 9].contains(record['version']) ||
            record['trees'] is! Map)
          throw const FormatException('Invalid Android emulator settings');
        final trees = (record['trees'] as Map).cast<String, String>();
        for (final entry in trees.entries) {
          if (!RegExp(r'^[a-f0-9]{32}:[a-z0-9-]+$').hasMatch(entry.key) ||
              !_rootMatches(entry.key, entry.value))
            throw const FormatException('Invalid Android storage grant');
        }
        _trees
          ..clear()
          ..addAll(trees);
        final folders = (record['folders'] as Map? ?? {})
            .cast<String, dynamic>();
        final checked = <String, Map<String, String>>{};
        final roots = <String, Map<String, String>>{};
        for (final entry in folders.entries) {
          final binding = (entry.value as Map).cast<String, String>();
          final emulator = androidEmulators
              .where((e) => entry.key == '${e.id}:${binding['package']}')
              .firstOrNull;
          if (record['version'] == 3 &&
              emulator?.id == 'retroarch' &&
              binding['access'] == 'root-gba-v1' &&
              androidRootBinding(binding)) {
            roots[binding['package']!] = binding;
            continue;
          }
          if (emulator == null ||
              binding['tree'] == null ||
              !sharedTree(emulator, binding['package']!, binding['tree']!))
            throw const FormatException('Invalid connected emulator folder');
          checked[entry.key] = binding;
        }
        _folders
          ..clear()
          ..addAll(checked);
        if ([4, 5, 6, 7, 8, 9].contains(record['version'])) {
          final savedRoots = (record['gbaRoots'] as Map)
              .cast<String, dynamic>();
          for (final entry in savedRoots.entries) {
            final binding = (entry.value as Map).cast<String, String>();
            if (binding['package'] != entry.key ||
                binding['access'] != 'root-gba-v1' ||
                !androidRootBinding(binding))
              throw const FormatException('Invalid GBA root connection');
            roots[entry.key] = binding;
          }
        }
        _gbaRoots
          ..clear()
          ..addAll(roots);
        final snesRoots = <String, Map<String, String>>{};
        if ([5, 6, 7, 8, 9].contains(record['version'])) {
          for (final entry in (record['snesRoots'] as Map).entries) {
            final binding = (entry.value as Map).cast<String, String>();
            if (binding['package'] != entry.key ||
                binding['access'] != 'root-snes-v1' ||
                !androidRootBinding(binding))
              throw const FormatException('Invalid SNES root connection');
            snesRoots[entry.key as String] = binding;
          }
        }
        _snesRoots
          ..clear()
          ..addAll(snesRoots);
        final retroRoots = <String, Map<String, String>>{};
        if ([6, 7, 8, 9].contains(record['version'])) {
          for (final entry in (record['retroRoots'] as Map).entries) {
            final binding = (entry.value as Map).cast<String, String>();
            final platform = (entry.key as String).split(':').first;
            if (!{
                  'gb',
                  'gbc',
                  'atari2600',
                  'tg16',
                  'genesis',
                  'sms',
                  'gamegear',
                  'sega32',
                  'n64',
                }.contains(platform) ||
                entry.key != '$platform:${binding['package']}' ||
                (record['version'] == 6 && !{'gb', 'gbc'}.contains(platform)) ||
                (record['version'] == 7 &&
                    !{'gb', 'gbc', 'atari2600', 'tg16'}.contains(platform)) ||
                (record['version'] == 8 && platform == 'n64') ||
                binding['access'] != androidRootRetroAccess(platform) ||
                !androidRootBinding(binding))
              throw const FormatException('Invalid RetroArch root connection');
            retroRoots[entry.key as String] = binding;
          }
        }
        _retroRoots
          ..clear()
          ..addAll(retroRoots);
        final hashes = (record['fingerprints'] as Map? ?? {})
            .cast<String, String>();
        if (hashes.entries.any(
          (e) =>
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(e.key) ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(e.value),
        ))
          throw const FormatException('Invalid emulator fingerprint cache');
        _fingerprints
          ..clear()
          ..addAll(hashes);
      } else {
        _trees.clear();
        _folders.clear();
        _gbaRoots.clear();
        _snesRoots.clear();
        _retroRoots.clear();
      }
      settingsKnown = true;
      final rows = await channel.invokeListMethod<Object?>('installed', {
        'packages': androidEmulators.expand((e) => e.packages).toList(),
        // The performance variant deliberately shares AnTuTu's package name.
        // Package identity alone must not mistake the benchmark for MMJ.
        'requiredActivities': {
          for (final e in androidEmulators.where((e) => e.id == 'citra-mmj'))
            for (final package in e.packages) package: e.activity,
        },
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
      removalEmulator = (await pendingRemoval())?['emulator'] as String?;
      await _finishInstallation(installationConfirmed);
    } catch (e) {
      // A failed query must never turn known applications into "not installed".
      error = 'Android emulator status could not be checked. $e';
    } finally {
      busy = false;
      _emit();
    }
  }

  File get _installation => File('${data.path}/android/installation.json');

  Future<void> _requestInstallation(
    AndroidEmulator emulator,
    String? server,
  ) async {
    if (server == null) return;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(server))
      throw const FormatException('Invalid installation server');
    await progressWrite(
      await progressFile(
        data,
        'android/installation.json',
        createParents: true,
      ),
      {
        'version': 1,
        'server': server,
        'emulator': emulator.id,
        'previousBuild': app(emulator)?.build,
      },
    );
  }

  Future<void> _finishInstallation(bool confirmed) async {
    if (onInstalled == null || !await progressExists(_installation.path))
      return;
    final record = await progressJson(
      await progressFile(data, 'android/installation.json'),
    );
    final emulator = androidEmulators
        .where((e) => e.id == record['emulator'])
        .firstOrNull;
    if (record['version'] != 1 ||
        emulator == null ||
        !RegExp(r'^[a-f0-9]{32}$')
            .hasMatch(record['server'] as String? ?? '') ||
        record['previousBuild'] != null &&
            !RegExp(r'^[a-f0-9]{64}$')
                .hasMatch(record['previousBuild'] as String? ?? ''))
      throw const FormatException('Invalid pending Android installation');
    final current = app(emulator);
    if (current?.enabled != true ||
        !confirmed && current!.build == record['previousBuild'])
      return;
    await onInstalled!(record['server'] as String, emulator);
    await _installation.delete();
  }

  Future<void> cancelInstallationDefault(String server) async {
    if (!await progressExists(_installation.path)) return;
    final record = await progressJson(
      await progressFile(data, 'android/installation.json'),
    );
    if (record['server'] == server) await _installation.delete();
  }

  Future<T> _withInstallPermission<T>(
    Future<T> Function() action, {
    bool requiresApkPermission = true,
  }) async {
    if (_installActionActive || installing != null)
      throw StateError('Finish the current emulator installation first.');
    _installActionActive = true;
    try {
      final allowed = requiresApkPermission
          ? await channel.invokeMethod<bool>('canInstallPackages')
          : true;
      if (allowed == null)
        throw StateError(
          'Android install permission could not be checked. Retry Install.',
        );
      if (!allowed) {
        requestingInstallPermission = true;
        phase?.call('Requesting Android permission to install emulator APKs.');
        _emit();
        final granted = await channel
            .invokeMethod<bool>('requestInstallPermission')
            .timeout(
              const Duration(seconds: 125),
              onTimeout: () => throw StateError(
                'Install permission was not confirmed. Return to Broomm and retry Install.',
              ),
            );
        if (granted != true)
          throw StateError(
            'Installation permission was not granted. Choose Install again and enable Allow from this source for Broomm in Android settings.',
          );
        phase?.call(
          'Android installation permission confirmed. Continuing installation.',
        );
      }
      requestingInstallPermission = false;
      _emit();
      if (_disposed)
        throw StateError('Broomm closed before installation could continue.');
      return await action();
    } finally {
      requestingInstallPermission = false;
      _installActionActive = false;
      _emit();
    }
  }

  Future<void> install(AndroidEmulator emulator, {String? server}) =>
      _withInstallPermission(
        () => _install(emulator, server: server),
        requiresApkPermission: emulator.id != 'duckstation',
      );

  Future<void> _install(AndroidEmulator emulator, {String? server}) async {
    if (installing != null)
      throw StateError('Finish the current emulator installation first.');
    await _requestInstallation(emulator, server);
    // Gold is a paid store entitlement. DuckStation requests linking to its
    // official distribution page; neither APK is repackaged by Broomm.
    if (emulator.id == 'duckstation') {
      await channel.invokeMethod<void>('installPage', {
        'url': emulator.installUrl,
      });
      return;
    }
    installing = emulator.id;
    downloadedBytes = 0;
    downloadBytes = null;
    _download = AndroidApkDownload();
    phase?.call('Resolving official ${emulator.name} APK.');
    _emit();
    File? apk;
    try {
      final device = await channel.invokeMapMethod<String, dynamic>('device');
      final uri = await _download!.source(
        emulator.id,
        (device!['abis'] as List).cast<String>(),
      );
      final clock = Stopwatch()..start();
      apk = await _download!.download(data, uri, (received, expected) {
        downloadedBytes = received;
        downloadBytes = expected;
        if (clock.elapsedMilliseconds >= 1000 || received == expected) {
          phase?.call(
            '${emulator.name} APK: $received bytes${expected == null ? '' : ' of $expected'}.',
          );
          clock.reset();
        }
        _emit();
      });
      if (_download!.cancelled)
        throw StateError('Installation download cancelled.');
      phase?.call(
        'Opening Android’s installer for ${emulator.name}; installation still requires confirmation and package readback.',
      );
      await channel.invokeMethod<void>('installDownloadedApk', {
        'path': apk.path,
        'packages': emulator.id == 'ppsspp'
            ? ['org.ppsspp.ppsspp']
            : emulator.packages,
        'requiredActivity': emulator.activity,
      });
    } catch (e) {
      phase?.call(
        '${emulator.name} APK preparation did not complete: ${e is PlatformException ? '${e.code}: ${e.message}' : e.runtimeType}.',
      );
      if (apk != null && await apk.exists()) await apk.delete();
      if (server != null) await cancelInstallationDefault(server);
      rethrow;
    } finally {
      _download?.cancel();
      _download = null;
      installing = null;
      _emit();
    }
  }

  Future<void> installApk(AndroidEmulator emulator, {String? server}) =>
      _withInstallPermission(() => _installApk(emulator, server: server));

  Future<void> _installApk(AndroidEmulator emulator, {String? server}) async {
    await _requestInstallation(emulator, server);
    try {
      await channel.invokeMethod<void>('installApk', {
        'packages': emulator.packages,
        if (emulator.id == 'citra-mmj') 'requiredActivity': emulator.activity,
      });
    } catch (_) {
      if (server != null) await cancelInstallationDefault(server);
      rethrow;
    }
  }

  Future<void> open(AndroidEmulator emulator, {String? package}) async {
    final selected = app(emulator, package: package);
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
    if (emulator.id == 'citra-mmj')
      await channel.invokeMethod<void>('sharedCheck', {'tree': uri});
    // MMJ swaps title data around each session; its live folder is intentionally
    // shared while snapshots and cloud history remain private to each profile.
    if (emulator.id != 'citra-mmj' &&
        _trees.entries.any((e) => e.key != key && e.value == uri))
      throw StateError(
        'This emulator folder belongs to another profile. Choose a separate folder to keep progress private.',
      );
    final next = {..._trees, key: uri};
    await _save(trees: next);
    _trees
      ..clear()
      ..addAll(next);
    _emit();
  }

  Future<String> fingerprint(AndroidApp app) async {
    if (_fingerprints[app.build] case final cached?) return cached;
    final hash = await channel.invokeMethod<String>('fingerprint', {
      'package': app.package,
    });
    if (hash == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))
      throw StateError('The Android emulator build could not be verified.');
    _fingerprints[app.build] = hash;
    if (_fingerprints.length > 32)
      _fingerprints.remove(_fingerprints.keys.first);
    await _save();
    return hash;
  }

  Future<String> resourceFingerprint(
    String key,
    Future<String> Function() inspect,
  ) async {
    if (_fingerprints[key] case final hash?) return hash;
    final hash = await inspect();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))
      throw const FormatException('Invalid Android resource fingerprint');
    _fingerprints[key] = hash;
    if (_fingerprints.length > 32)
      _fingerprints.remove(_fingerprints.keys.first);
    await _save();
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
    if (key.endsWith(':citra-mmj')) return sharedMmjTree(value);
    final uri = Uri.parse(value);
    return uri.authority == 'app.broomm.broomm.emulator-data' &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments[1] == key &&
        {'ppsspp', 'melonds', 'azahar'}.contains(key.split(':').last);
  }

  static bool sharedMmjTree(String value) {
    if (!_treeUri(value)) return false;
    final uri = Uri.parse(value);
    return uri.authority == 'com.android.externalstorage.documents' &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments.first == 'tree' &&
        RegExp(r'^[A-Za-z0-9_-]+:citra-emu$').hasMatch(uri.pathSegments.last) &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  Future<String?> chooseMmjFolder() async {
    await ensureNoWriters();
    final uri = await channel.invokeMethod<String>('sharedPick');
    if (uri != null && !sharedMmjTree(uri))
      throw StateError(
        'Choose the shared citra-emu folder. MMJ’s private Android/data (Storage Access) folder is not supported. No saves were changed.',
      );
    return uri;
  }

  Future<String> launch(
    AndroidEmulator emulator,
    AndroidApp app,
    List<String> files,
    String selected, {
    String? core,
    String? profile,
    String? configuration,
    String? nativeRom,
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
      if (configuration != null) 'configuration': configuration,
      if (nativeRom != null) 'nativeRom': nativeRom,
      if (profile != null &&
          folder(emulator) == null &&
          emulator.id != 'citra-mmj' &&
          tree(profile, emulator) != null)
        'root': _key(profile, emulator),
    }))!;
  }

  Future<void> releaseGrants() => channel.invokeMethod<void>('releaseGrants');

  Future<void> ensureNoWriters({
    bool closureConfirmed = false,
    bool allowRemoval = false,
  }) async {
    if (!allowRemoval && await progressExists(_removal.path))
      throw StateError(
        'Finish the pending emulator removal before continuing.',
      );
    // The owner accepts explicit closure confirmation for Android sessions.
    if (closureConfirmed) {
      if (await channel.invokeMethod<bool>('ioBusy') == true)
        throw StateError(
          'An Android save transfer is already running. Wait for it to finish.',
        );
      return;
    }
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
    _download?.cancel();
    if (enabled) channel.setMethodCallHandler(null);
    super.dispose();
  }
}
