import 'dart:async';

import 'package:flutter/foundation.dart';

import '../session_lease.dart';
import 'azahar.dart';
import 'citra_mmj.dart';
import 'emulators.dart';
import 'melon_root.dart';
import 'dolphin_root.dart';
import 'root_saves.dart';

enum AndroidSetupStep { install, waitingInstall, initialize, folder, ready }

/// One setup operation shared by the compact settings cards and their dialog.
class AndroidEmulatorSetup extends ChangeNotifier {
  AndroidEmulatorSetup(
    this.manager,
    this.emulator,
    this.platform,
    this.profile,
  ) {
    manager.addListener(_installed);
  }

  final AndroidEmulators manager;
  final AndroidEmulator emulator;
  final String platform;
  final String profile;
  AndroidSetupStep step = AndroidSetupStep.install;
  bool busy = false, _disposed = false, _shared = false, _opened = false;
  String? problem;
  Map<String, String> _previousBuilds = {};
  ({String uri, String package, String build})? _pendingFolder;

  bool get hasPendingFolder {
    final selected = _pendingFolder;
    final app = manager.app(emulator);
    return selected != null &&
        selected.package == app?.package &&
        selected.build == app?.build;
  }

  bool get azaharRootSetup =>
      !_shared &&
      emulator.id == 'azahar' &&
      manager.app(emulator)?.package == androidAzaharScopedPackage &&
      manager.app(emulator)?.version == androidAzaharScopedVersion;

  bool get mmjRootSetup =>
      !_shared &&
      emulator.id == 'citra-mmj' &&
      manager.app(emulator)?.package == androidMmjSharedPackage &&
      manager.app(emulator)?.version == androidMmjSharedVersion;

  bool get canUseShared3dsFolder =>
      !_shared &&
      (azaharRootSetup ||
          mmjRootSetup ||
          {
            androidAzaharRootFolderAccess,
            androidMmjRootFolderAccess,
          }.contains(manager.folder(emulator)?['access']));

  bool get _rooted =>
      !_shared &&
      (emulator.id == 'retroarch' && androidRootRetroCore(platform) != null ||
          emulator.id == 'ppsspp' &&
              platform == 'psp' &&
              manager.app(emulator)?.package == 'org.ppsspp.ppsspp' ||
          emulator.id == 'duckstation' && platform == 'psx' ||
          emulator.id == 'melonds' &&
              platform == 'nds' &&
              manager.app(emulator)?.version == androidMelonRootVersion ||
          emulator.id == 'dolphin' &&
              {'ngc', 'wii'}.contains(platform) &&
              manager.app(emulator)?.version == androidDolphinRootVersion) &&
      (manager.rootConnection(emulator, platform) != null ||
          manager.tree(profile, emulator) == null);

  Future<void> _run(Future<void> Function() action) async {
    if (busy || _disposed) return;
    busy = true;
    problem = null;
    notifyListeners();
    try {
      await manager.ensureSetupAllowed();
      await action();
    } catch (e) {
      problem = '$e';
    } finally {
      busy = false;
      if (!_disposed) {
        notifyListeners();
        _installed();
      }
    }
  }

  void _installed() {
    final app = manager.app(emulator);
    if (!_disposed &&
        !busy &&
        step == AndroidSetupStep.waitingInstall &&
        !manager.busy &&
        manager.settingsKnown &&
        manager.error == null &&
        app?.enabled == true &&
        app!.build != _previousBuilds[app.package]) {
      // Change the phase before dispatch so repeated inventory notifications
      // cannot start a second setup operation.
      step = AndroidSetupStep.install;
      unawaited(verify());
    }
  }

  Future<void> verify() => _run(() async {
    final app = manager.app(emulator);
    if (app == null) {
      step = AndroidSetupStep.install;
      return;
    }
    if (!app.enabled)
      throw StateError('Enable ${emulator.name} in Android settings first.');
    if (_rooted) {
      step = AndroidSetupStep.initialize;
      if (emulator.id == 'melonds') {
        await manager.connectMelonRoot(emulator);
        step = AndroidSetupStep.ready;
        return;
      }
      if (emulator.id == 'dolphin') {
        await manager.connectDolphinRoot(emulator, platform);
        step = AndroidSetupStep.ready;
        return;
      }
      if (emulator.id == 'duckstation') {
        await manager.connectDuckRoot(emulator);
        step = AndroidSetupStep.ready;
        return;
      }
      if (emulator.id == 'ppsspp') {
        await manager.connectPspRoot(emulator);
        step = AndroidSetupStep.ready;
        return;
      }
      final firstOpen = await manager.connectGbaRoot(
        emulator,
        platform: platform,
      );
      step = firstOpen == null
          ? AndroidSetupStep.ready
          : AndroidSetupStep.initialize;
    } else {
      final tree = manager.folder(emulator)?['tree'];
      if (tree == null) {
        step = AndroidSetupStep.folder;
      } else {
        final lease = await SessionLease.acquire(manager.data);
        try {
          await manager.ensureSetupAllowed();
          await manager.confirmSharedStorage(
            emulator,
            tree,
            verifyAzahar:
                !_shared &&
                manager.folder(emulator)?['access'] ==
                    androidAzaharRootFolderAccess,
            verifyMmj:
                !_shared &&
                manager.folder(emulator)?['access'] ==
                    androidMmjRootFolderAccess,
          );
          step = AndroidSetupStep.ready;
        } finally {
          await lease.release();
        }
      }
    }
  });

  Future<void> install({bool imported = false}) => _run(() async {
    _pendingFolder = null;
    _previousBuilds = {
      for (final package in emulator.packages)
        if (manager.installed[package] case final app?) package: app.build,
    };
    step = AndroidSetupStep.waitingInstall;
    if (imported) {
      await manager.installApk(emulator);
    } else {
      await manager.install(emulator);
    }
  });

  Future<void> refresh() async {
    if (busy) return;
    await manager.load();
    _installed();
  }

  Future<void> open() => _run(() async {
    await manager.open(emulator);
    _opened = true;
  });

  Future<void> resumed() async {
    if (busy) return;
    if (step == AndroidSetupStep.waitingInstall) {
      await refresh();
    } else if (step == AndroidSetupStep.initialize && _opened) {
      _opened = false;
      await verify();
    }
  }

  Future<void> useSharedFolder() => _run(() async {
    // A verified shared grant replaces a native media connection.
    if (!{'melonds', 'dolphin'}.contains(emulator.id) &&
        manager.rootConnection(emulator, platform) != null)
      if (emulator.id == 'duckstation')
        await manager.disconnectDuckRoot();
      else if (emulator.id == 'ppsspp')
        await manager.disconnectPspRoot();
      else
        await manager.disconnectGbaRoot(emulator, platform: platform);
    _pendingFolder = null;
    _shared = true;
    step = AndroidSetupStep.folder;
  });

  Future<void> selectFolder({bool change = false}) => _run(() async {
    final lease = await SessionLease.acquire(manager.data);
    try {
      await manager.ensureSetupAllowed();
      final app = manager.app(emulator);
      if (app == null) throw StateError('Install ${emulator.name} first.');
      if (!hasPendingFolder) _pendingFolder = null;
      // The picker can wake a cached emulator process. Keep the grant after
      // a failed check so retrying can verify it with the emulator stopped.
      final uri = !change && _pendingFolder != null
          ? _pendingFolder!.uri
          : await manager.chooseFolder(emulator, package: app.package);
      if (uri == null) return;
      final current = manager.app(emulator);
      if (current?.package != app.package || current?.build != app.build) {
        _pendingFolder = null;
        throw StateError('The emulator changed. Select its save folder again.');
      }
      final verifyAzahar = azaharRootSetup, verifyMmj = mmjRootSetup;
      if (verifyAzahar || verifyMmj)
        _pendingFolder = (uri: uri, package: app.package, build: app.build);
      await manager.confirmSharedStorage(
        emulator,
        uri,
        verifyAzahar: verifyAzahar,
        verifyMmj: verifyMmj,
      );
      _pendingFolder = null;
      step = AndroidSetupStep.ready;
    } finally {
      await lease.release();
    }
  });

  @override
  void dispose() {
    _disposed = true;
    manager.removeListener(_installed);
    super.dispose();
  }
}

String androidSetupInstructions(AndroidEmulator emulator) =>
    switch (emulator.id) {
      'ppsspp' => 'In PPSSPP, select a shared Memory Stick folder. Select that same folder here; it contains PSP/SAVEDATA and PSP/PPSSPP_STATE.',
      'melonds' => 'In melonDS, disable saving next to the ROM and select a custom save folder. Set Save state location to Save directory. Select that exact custom save folder here.',
      'azahar' => 'In Azahar, select a shared user-data folder. Select that same folder here, containing sdmc and states.',
      'citra-mmj' => 'Use MMJ’s normal shared citra-emu folder, usually Internal storage/citra-emu. Private Android/data and Storage Access builds are unsupported. Check that MMJ uses this folder.',
      'dolphin' => 'Initialize Dolphin, then select Dolphin from the Android picker’s sidebar and grant its full user-data root. For GameCube, set both memory-card slots to GCI Folder.',
      'retroarch' => 'Install the required core in RetroArch and save its configuration. Select RetroArch from the picker’s sidebar and grant its Core Data/app-data root containing cores and files.',
      'armsx2' => 'In ARMSX2, select a shared custom App Data Folder and enable its requested all-files permission. Use standard global memory cards and disable per-game cards. Select the full folder containing PCSX2-Android.ini, memcards and sstates.',
      'duckstation' => 'Use a DuckStation version with selectable data locations. Set both memory cards to Shared Between All Games, using shared_card_1.mcd and shared_card_2.mcd. Select the parent folder containing memcards and states.',
      'eden' => 'Initialize its console account and configure keys and firmware in Eden. Select Eden from the picker sidebar and grant its full user-data root.',
      _ => throw UnsupportedError(
        'No Android setup instructions for ${emulator.name}.',
      ),
    };
