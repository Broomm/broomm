import 'package:flutter/material.dart';

import '../android/emulators.dart';
import '../android/root_inspection.dart';
import '../romm/models.dart';
import '../progress/service.dart';
import 'controls.dart';
import 'android_root_inspection_dialog.dart';
import 'android_install_dialog.dart';
import 'model.dart';
import 'navigation.dart';

class AndroidEmulatorSettingsScreen extends StatefulWidget {
  const AndroidEmulatorSettingsScreen({super.key, required this.model});
  final ShellModel model;
  @override
  State<AndroidEmulatorSettingsScreen> createState() =>
      _AndroidEmulatorSettingsScreenState();
}

class _AndroidEmulatorSettingsScreenState
    extends State<AndroidEmulatorSettingsScreen>
    with WidgetsBindingObserver {
  ShellModel get model => widget.model;
  AndroidEmulators get manager => model.android;
  String? problem;
  bool working = false;
  bool installationDialogOpen = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !model.gameActive && !working)
      manager.load();
  }

  Future<void> run(Future<void> Function() action) async {
    if (working) return;
    setState(() {
      working = true;
      problem = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => problem = '$e');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> configure(AndroidEmulator emulator) async {
    if (await model.androidSession.pending() != null)
      throw StateError(
        'Finish the previous game before changing save folders.',
      );
    final instructions = switch (emulator.id) {
      'ppsspp' => 'In PPSSPP, select a shared Memory Stick folder. Select that same folder here; it contains PSP/SAVEDATA and PSP/PPSSPP_STATE.',
      'melonds' => 'In melonDS, disable saving next to the ROM and select a custom save folder. Set Save state location to Save directory. Select that exact custom save folder here.',
      'azahar' => 'In Azahar, select a shared user-data folder. Select that same folder here, containing sdmc and states.',
      'citra-mmj' => 'Use MMJ’s normal shared citra-emu folder, usually Internal storage/citra-emu. Select that folder here. Private Android/data / Storage Access builds are unsupported. Verify MMJ actually uses shared storage; Broomm cannot read that private setting.',
      'dolphin' => 'Initialize Dolphin, then select Dolphin from the Android picker’s sidebar and grant its full user-data root. For GameCube, set both memory-card slots to GCI Folder in Dolphin.',
      'retroarch' => 'Install the needed cores in RetroArch and save its configuration. Select RetroArch from the picker’s sidebar and grant its Core Data/app-data root (the one containing cores and files). Broomm uses a separate session configuration; your normal settings remain available.',
      'armsx2' => 'In ARMSX2, select a shared custom App Data Folder and enable its requested all-files permission. Use standard global memory cards and disable per-game memory cards. Close ARMSX2, then select its full custom data folder here. Stable and nightly keep separate connections.',
      'duckstation' => 'Use a DuckStation version with configurable data locations. Put memory cards in memcards and states in savestates under one shared folder. Set both slots to Shared Between All Games, using shared_card_1.mcd and shared_card_2.mcd. Select the parent folder here. Broomm swaps a separate card per profile/game and restores standalone cards afterward.',
      'eden' => 'Initialize Eden and configure its keys/firmware in Eden. Select Eden from the Android picker’s sidebar and grant its full data root. Broomm reads its console account to find game saves. Eden does not support save states.',
      _ => throw StateError('No save-folder instructions for this emulator.'),
    };
    final yes = await showConsoleDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text('Connect ${emulator.name} saves'),
        content: Text(
          '$instructions\n\nClose the emulator before continuing. This connection is shared by Broomm profiles; no folder reselection is needed when switching profiles. Each profile’s game progress stays separate. Existing standalone saves are preserved and restored after play; use Use existing save file to import progress from RomM.',
        ),
        actions: [
          ConsoleButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ConsoleButton(
            onPressed: () async {
              try {
                await manager.open(emulator);
              } catch (e) {
                model.showNotice('$e', problem: true);
              }
            },
            child: const Text('Open emulator'),
          ),
          ConsoleButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Emulator closed · Select folder'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final package = manager.app(emulator)?.package;
    final uri = await manager.chooseFolder(emulator);
    if (uri == null) return;
    if (manager.app(emulator)?.package != package)
      throw StateError(
        'The installed emulator changed. Select its folder again.',
      );
    await manager.confirmSharedStorage(emulator, uri);
    model.showNotice(
      '${emulator.name} save folder connected for all Broomm profiles.',
    );
  }

  Future<void> install(
    AndroidEmulator emulator, {
    bool imported = false,
  }) async {
    if (working) return;
    installationDialogOpen = true;
    try {
      await run(() async {
        await showConsoleDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AndroidInstallDialog(
            manager: manager,
            emulator: emulator,
            install: () => imported
                ? manager.installApk(emulator, server: model.server!.id)
                : manager.install(emulator, server: model.server!.id),
          ),
        );
      });
    } finally {
      if (mounted) setState(() => installationDialogOpen = false);
    }
  }

  Future<void> recover() async {
    final record = await model.androidSession.pending();
    if (record == null || !mounted) return;
    final emulator = androidEmulators.singleWhere(
      (e) => e.id == record['emulator'],
    );
    final yes = await showConsoleDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Finish ${emulator.name} session?'),
        content: const Text(
          'Save and close the emulator completely before continuing. Interrupted progress is retained and will need review before upload.',
        ),
        actions: [
          ConsoleButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ConsoleButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Emulator closed · Finish'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    CloudGame? game;
    if (model.server?.id == record['server'] &&
        model.profile?.id == record['profile'] &&
        model.installation(record['rom'] as int) != null &&
        manager.progressSupported(emulator) &&
        manager.connected(model.profile!.id, emulator))
      game = await model.cloudGame(
        record['rom'] as int,
        androidRom: record['selected'] as String?,
      );
    await model.androidSession.finish(emulatorClosed: true, recovery: game);
    model.showNotice(
      'Android session finished. Interrupted progress was kept for review.',
    );
  }

  List<(AndroidEmulator, AndroidApp)> get rootTargets => [
    for (final emulator in androidEmulators)
      for (final package in emulator.packages)
        if (manager.app(emulator, package: package) case final app?)
          if (app.enabled) (emulator, app),
  ];

  Future<void> inspectRoot() async {
    final targets = rootTargets;
    if (targets.isEmpty) return;
    final target = targets.length == 1
        ? targets.single
        : await showConsoleDialog<(AndroidEmulator, AndroidApp)>(
            context: context,
            builder: (c) => AlertDialog(
              scrollable: true,
              title: const Text('Choose an emulator to inspect'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (emulator, app) in targets)
                    ConsoleButton(
                      onPressed: () => Navigator.pop(c, (emulator, app)),
                      child: Text('${emulator.name} · ${app.package}'),
                    ),
                ],
              ),
              actions: [
                ConsoleButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
    if (target == null || !mounted) return;
    final (emulator, app) = target;
    await showConsoleDialog<void>(
      context: context,
      builder: (_) => AndroidRootInspectionDialog(
        emulator: emulator,
        app: app,
        inspector: AndroidRootInspector(phase: manager.phase),
      ),
    );
  }

  Future<void> configureRootSaves(
    RommPlatform platform,
    AndroidEmulator emulator,
  ) async {
    final connected = manager.gbaRoot(emulator) != null;
    final accepted = await showConsoleDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          connected ? 'Disconnect GBA root saves?' : 'Connect GBA root saves',
        ),
        content: Text(
          connected
              ? 'Quit RetroArch first. Broomm keeps your saves and uses the shared folder for GBA if one is connected.'
              : 'Install mGBA and quit RetroArch. Allow root access when asked. This connects ordinary GBA saves for Broomm profiles.',
        ),
        actions: [
          ConsoleButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ConsoleButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              connected
                  ? 'RetroArch closed · Disconnect'
                  : 'RetroArch closed · Connect',
            ),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    if (connected) {
      await manager.disconnectGbaRoot(emulator);
      model.showNotice('GBA root saves disconnected.');
    } else {
      await manager.connectGbaRoot(emulator);
      await model.setDefaultEmulator(platform, emulator.id);
      model.showNotice('GBA root saves connected.');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, manager]),
    builder: (context, _) => ConsoleScrollView(
      padding: const EdgeInsets.all(16),
      child: FocusTraversalGroup(
        policy: ConsoleTraversalPolicy(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Emulator Settings',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 12),
            if (working || manager.busy) const LinearProgressIndicator(),
            if (manager.requestingInstallPermission)
              const Text(
                'Android permission required: enable Allow from this source for Broomm, then return here. Installation will continue automatically.',
              ),
            if (manager.installing != null) ...[
              LinearProgressIndicator(
                value:
                    manager.downloadBytes == null || manager.downloadBytes == 0
                    ? null
                    : manager.downloadedBytes / manager.downloadBytes!,
              ),
              Text(
                'Downloading emulator APK · ${(manager.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
              ),
              ConsoleButton(
                onPressed: manager.cancelDownload,
                child: const Text('Cancel download'),
              ),
            ],
            FutureBuilder<Map<String, dynamic>?>(
              future: model.androidSession.pending(),
              builder: (_, snapshot) {
                if (snapshot.hasError)
                  return ProblemNotice('${snapshot.error}');
                return snapshot.data == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ConsoleButton(
                          onPressed: working ? null : () => run(recover),
                          child: const Text('Finish previous game session'),
                        ),
                      );
              },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ConsoleButton(
                  autofocus: true,
                  onPressed: working || manager.busy
                      ? null
                      : () => run(manager.load),
                  child: const ActionLabel('Refresh apps', icon: Icons.refresh),
                ),
                ConsoleButton(
                  onPressed:
                      working ||
                          manager.busy ||
                          model.gameActive ||
                          rootTargets.isEmpty
                      ? null
                      : () => run(inspectRoot),
                  child: const Text('Inspect root access'),
                ),
              ],
            ),
            if (problem != null) ProblemNotice(problem!),
            if (manager.error != null) ProblemNotice(manager.error!),
            for (final platform in [
              ...model.platforms,
            ]..sort((a, b) => a.name.compareTo(b.name))) ...[
              const SizedBox(height: 16),
              Text(platform.name, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 6),
              if (manager.choices(platform).isEmpty)
                const Text(
                  'No supported emulator',
                  style: TextStyle(color: muted),
                ),
              for (final emulator in manager.choices(platform))
                card(platform, emulator),
            ],
          ],
        ),
      ),
    ),
  );
  Widget card(RommPlatform platform, AndroidEmulator emulator) {
    final app = manager.app(emulator);
    final isDefault =
        app?.enabled == true && model.defaultEmulator(platform) == emulator.id;
    final configured =
        model.profile != null &&
        manager.connected(model.profile!.id, emulator, platform: platform.slug);
    final rootCard = emulator.id == 'retroarch' && platform.slug == 'gba';
    final rooted = rootCard && manager.gbaRoot(emulator) != null;
    const actionPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 12);
    final disabled =
        // The modal owns interaction; keep its invoking button focusable so
        // closing it restores the same card instead of jumping to Refresh.
        !installationDialogOpen &&
            (working || manager.busy || manager.installing != null) ||
        model.gameActive ||
        app?.enabled == false;
    return ConsoleFocusRegion(
      child: Container(
        key: ValueKey('android-emulator-${platform.id}:${emulator.id}'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xff14202d),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDefault ? accent : Colors.white12,
            width: isDefault ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${emulator.name}${isDefault ? ' · Default' : ''}',
              style: const TextStyle(fontSize: 19),
            ),
            const SizedBox(height: 3),
            Text(
              app == null
                  ? (manager.error == null
                        ? 'Not installed'
                        : 'Status unavailable')
                  : !app.enabled
                  ? 'Disabled in Android'
                  : [
                      app.version,
                      if (rooted)
                        'Root saves'
                      else if (configured)
                        'Folder saves'
                      else
                        'Saves not connected',
                    ].join(' · '),
              style: TextStyle(
                color: app?.enabled == true && configured ? accent : muted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ConsoleButton(
                  padding: actionPadding,
                  onPressed: disabled ? null : () => install(emulator),
                  child: Text(
                    emulator.id == 'duckstation'
                        ? 'Open Play Store'
                        : emulator.id == 'ppsspp' &&
                              app?.package == 'org.ppsspp.ppssppgold'
                        ? 'Download free PPSSPP'
                        : app == null
                        ? 'Install'
                        : 'Get APK',
                  ),
                ),
                ConsoleButton(
                  padding: actionPadding,
                  onPressed: disabled
                      ? null
                      : () => install(emulator, imported: true),
                  child: const Text('Install APK…'),
                ),
                if (app != null) ...[
                  if (rootCard)
                    ConsoleButton(
                      padding: actionPadding,
                      onPressed: disabled
                          ? null
                          : () => run(
                              () => configureRootSaves(platform, emulator),
                            ),
                      child: const Text('Root saves…'),
                    ),
                  ConsoleButton(
                    padding: actionPadding,
                    onPressed: disabled
                        ? null
                        : () => run(() => manager.open(emulator)),
                    child: const Text('Open'),
                  ),
                  if (manager.progressSupported(emulator))
                    ConsoleButton(
                      padding: actionPadding,
                      onPressed: disabled
                          ? null
                          : () => run(() => configure(emulator)),
                      child: const Text('Save folder…'),
                    ),
                  if (!isDefault)
                    ConsoleButton(
                      padding: actionPadding,
                      onPressed: disabled
                          ? null
                          : () => run(
                              () => model.setDefaultEmulator(
                                platform,
                                emulator.id,
                              ),
                            ),
                      child: const Text('Set default'),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
