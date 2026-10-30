import 'package:flutter/material.dart';

import '../android/emulators.dart';
import '../romm/models.dart';
import '../progress/service.dart';
import 'controls.dart';
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
        manager.tree(model.profile!.id, emulator) != null)
      game = await model.cloudGame(
        record['rom'] as int,
        androidRom: record['selected'] as String?,
      );
    await model.androidSession.finish(emulatorClosed: true, recovery: game);
    model.showNotice(
      'Android session finished. Interrupted progress was kept for review.',
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, manager]),
    builder: (context, _) => ConsoleScrollView(
      padding: const EdgeInsets.all(24),
      child: FocusTraversalGroup(
        policy: ConsoleTraversalPolicy(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Emulator Settings',
              style: TextStyle(fontSize: 38, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 12),
            const Text(
              'Android uses installed emulator apps. Games open directly; controller setup and overlays stay in the emulator.',
              style: TextStyle(color: muted, height: 1.6),
            ),
            const SizedBox(height: 20),
            if (working || manager.busy) const LinearProgressIndicator(),
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
            ConsoleButton(
              autofocus: true,
              onPressed: working || manager.busy
                  ? null
                  : () => run(manager.load),
              child: const ActionLabel(
                'Refresh installed apps',
                icon: Icons.refresh,
              ),
            ),
            if (problem != null) ProblemNotice(problem!),
            if (manager.error != null) ProblemNotice(manager.error!),
            for (final platform in [
              ...model.platforms,
            ]..sort((a, b) => a.name.compareTo(b.name))) ...[
              const SizedBox(height: 28),
              Text(platform.name, style: const TextStyle(fontSize: 25)),
              const SizedBox(height: 12),
              if (manager.choices(platform).isEmpty)
                const Text(
                  'No supported Android emulator integration for this platform yet. Games remain available to download.',
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
        manager.tree(model.profile!.id, emulator) != null;
    final disabled =
        working ||
        manager.busy ||
        manager.installing != null ||
        model.gameActive ||
        app?.enabled == false;
    return ConsoleFocusRegion(
      child: Container(
        key: ValueKey('android-emulator-${platform.id}:${emulator.id}'),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(24),
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
              style: const TextStyle(fontSize: 23),
            ),
            const SizedBox(height: 8),
            Text(
              app == null
                  ? (manager.error == null
                        ? 'Not installed'
                        : 'Installation status unavailable')
                  : !app.enabled
                  ? 'Disabled in Android app settings'
                  : 'Installed · ${app.version}',
              style: TextStyle(color: app == null ? muted : accent),
            ),
            const SizedBox(height: 12),
            if (emulator.id == 'armsx2')
              Text(
                'Detected channels: ${[if (manager.installed.containsKey('com.armsx2')) 'Stable', if (manager.installed.containsKey('com.armsx2.nightly')) 'Nightly'].join(' · ')}${app?.package == 'com.armsx2' ? ' · Stable preferred' : ''}',
                style: const TextStyle(color: muted),
              ),
            Text(
              emulator.saveNote ?? '',
              style: const TextStyle(color: muted, height: 1.5),
            ),
            if (manager.progressSupported(emulator)) ...[
              const SizedBox(height: 8),
              Text(
                manager.folder(emulator) != null
                    ? 'Save folder connected for all Broomm profiles. Finish and sync after closing the emulator.'
                    : configured
                    ? 'Legacy profile folder connected. Configure saves to use one folder across profiles.'
                    : 'Connect a save folder once to enable cloud saves.',
                style: TextStyle(color: configured ? accent : muted),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ConsoleButton(
                  onPressed: disabled
                      ? null
                      : () => run(
                          () => manager.install(
                            emulator,
                            server: model.server!.id,
                          ),
                        ),
                  child: Text(
                    emulator.id == 'duckstation'
                        ? 'Open Play Store'
                        : emulator.id == 'ppsspp' &&
                              app?.package == 'org.ppsspp.ppssppgold'
                        ? 'Download free PPSSPP'
                        : app == null
                        ? 'Install'
                        : 'Download installer',
                  ),
                ),
                ConsoleButton(
                  onPressed: disabled
                      ? null
                      : () => run(
                          () => manager.installApk(
                            emulator,
                            server: model.server!.id,
                          ),
                        ),
                  child: const Text('Install APK…'),
                ),
                if (app != null) ...[
                  ConsoleButton(
                    onPressed: disabled
                        ? null
                        : () => run(() => manager.open(emulator)),
                    child: const Text('Open emulator'),
                  ),
                  if (manager.progressSupported(emulator))
                    ConsoleButton(
                      onPressed: disabled
                          ? null
                          : () => run(() => configure(emulator)),
                      child: const Text('Configure saves'),
                    ),
                  if (!isDefault)
                    ConsoleButton(
                      onPressed: disabled
                          ? null
                          : () => run(
                              () => model.setDefaultEmulator(
                                platform,
                                emulator.id,
                              ),
                            ),
                      child: const Text('Set as default'),
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
