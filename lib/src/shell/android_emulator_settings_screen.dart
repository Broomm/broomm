import 'package:flutter/material.dart';

import '../android/emulators.dart';
import '../android/root_inspection.dart';
import '../romm/models.dart';
import '../progress/service.dart';
import 'controls.dart';
import 'android_root_inspection_dialog.dart';
import 'android_setup_dialog.dart';
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

  Future<void> setup(RommPlatform platform, AndroidEmulator emulator) async {
    if (working) return;
    final profile = model.profile, server = model.server;
    if (profile == null || server == null) {
      model.showNotice(
        'Choose a profile before setting up an emulator.',
        problem: true,
      );
      return;
    }
    installationDialogOpen = true;
    try {
      await run(() async {
        await manager.ensureSetupAllowed();
        final slug = model
            .emulatorChoices(platform)
            .firstWhere((e) => e.emulatorId == emulator.id)
            .slug;
        final complete = await showConsoleDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AndroidSetupDialog(
            manager: manager,
            emulator: emulator,
            platform: slug,
            profile: profile.id,
            client: model.client,
            platformId: platform.id,
            autoComplete: !manager.connected(
              profile.id,
              emulator,
              platform: slug,
            ),
          ),
        );
        if (complete != true) return;
        if (model.profile?.id != profile.id || model.server?.id != server.id)
          throw StateError(
            'The active profile changed. Choose this emulator again.',
          );
        await model.setDefaultEmulator(platform, emulator.id);
        model.showNotice('${emulator.name} is ready to play.');
      });
    } finally {
      if (mounted) setState(() => installationDialogOpen = false);
    }
  }

  Future<void> remove(AndroidEmulator emulator) async {
    final app = manager.app(emulator);
    final accepted = await showConsoleDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${emulator.name}?'),
        content: Text(
          'This uninstalls ${emulator.name}${app == null ? '' : ' (${app.package})'}, including its cores, settings and standalone saves. Broomm’s connections and defaults for this emulator are cleared across profiles and platforms. Saved progress in Broomm and downloaded games are kept. Android will ask you to confirm uninstalling the app.',
        ),
        actions: [
          ConsoleButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ConsoleButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove emulator'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    if (await manager.remove(emulator, expected: app))
      model.showNotice('${emulator.name} removed.');
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
            if (!installationDialogOpen && (working || manager.busy))
              const LinearProgressIndicator(),
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
                'Downloading ${manager.installing == 'mgba' ? 'mGBA' : 'emulator APK'} · ${(manager.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
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
                  child: const ActionLabel(
                    'Refresh status',
                    icon: Icons.refresh,
                  ),
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
        app?.enabled == true &&
        model.profile != null &&
        manager.connected(model.profile!.id, emulator, platform: platform.slug);
    const actionPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 12);
    final disabled =
        // The modal owns interaction; keep its invoking button focusable so
        // closing it restores the same card instead of jumping to Refresh.
        !installationDialogOpen &&
            (working || manager.busy || manager.installing != null) ||
        model.gameActive;
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
                      configured ? 'Ready to play' : 'Not set up',
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
                  onPressed: disabled || manager.removalEmulator != null
                      ? null
                      : () => setup(platform, emulator),
                  child: Text(configured ? 'Verify setup' : 'Set up'),
                ),
                if (app != null || manager.removalEmulator == emulator.id)
                  ConsoleButton(
                    padding: actionPadding,
                    onPressed: disabled
                        ? null
                        : () => run(() => remove(emulator)),
                    child: Text(
                      manager.removalEmulator == emulator.id
                          ? 'Finish removal'
                          : 'Remove',
                    ),
                  ),
                if (app != null)
                  ConsoleButton(
                    padding: actionPadding,
                    onPressed:
                        disabled ||
                            !app.enabled ||
                            manager.removalEmulator != null
                        ? null
                        : () => run(
                            () => manager.open(
                              emulator,
                              profile: model.profile!.id,
                              server: model.server!.id,
                            ),
                          ),
                    child: const Text('Open emulator'),
                  ),
                if (!isDefault)
                  ConsoleButton(
                    padding: actionPadding,
                    onPressed:
                        disabled ||
                            !configured ||
                            manager.removalEmulator != null
                        ? null
                        : () => run(
                            () =>
                                model.setDefaultEmulator(platform, emulator.id),
                          ),
                    child: const Text('Set as default'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
