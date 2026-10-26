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
    if (state == AppLifecycleState.resumed && !model.gameActive) manager.load();
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
        'Close the Android emulator and finish its session before changing save folders.',
      );
    final profile = model.profile!;
    final uri = await manager.exposeStorage(profile.id, profile.name, emulator);
    if (!mounted) return;
    final location = switch (emulator.id) {
      'ppsspp' => 'Memory Stick folder',
      'melonds' => 'custom save folder',
      _ => 'user data folder',
    };
    final confirmed = await showConsoleDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text('Connect ${emulator.name} saves'),
        content: Text(
          'In ${emulator.name}, choose “Broomm · ${profile.name} · ${emulator.name}” from Android’s folder picker as its $location. You may need to open the picker’s sidebar to find Broomm.\n\nThen save and close the emulator and confirm here. This folder belongs only to ${profile.name}; choose this profile’s folder again when changing profiles. Existing saves can be imported from RomM using Use existing save file.',
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
            child: const Text('Folder selected · emulator closed'),
          ),
        ],
      ),
    );
    if (confirmed == true && model.profile == profile) {
      await manager.confirmStorage(profile.id, emulator, uri);
      model.showNotice(
        '${emulator.name} cloud save folder connected for ${profile.name}.',
      );
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
        working || manager.busy || model.gameActive || app?.enabled == false;
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
            Text(
              emulator.saveNote ?? '',
              style: const TextStyle(color: muted, height: 1.5),
            ),
            if (manager.progressSupported(emulator)) ...[
              const SizedBox(height: 8),
              Text(
                configured ? 'Broomm save folder connected for this profile.' : 'Cloud saves require connecting this profile’s Broomm folder once.',
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
                      : () => run(() => manager.install(emulator)),
                  child: Text(app == null ? 'Install' : 'Download installer'),
                ),
                ConsoleButton(
                  onPressed: disabled
                      ? null
                      : () => run(() => manager.installApk(emulator)),
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
