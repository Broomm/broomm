import 'package:flutter/material.dart';

import '../android/emulators.dart';
import '../android/root_saves.dart';
import '../android/setup.dart';
import 'controls.dart';

class AndroidSetupDialog extends StatefulWidget {
  const AndroidSetupDialog({
    super.key,
    required this.manager,
    required this.emulator,
    required this.platform,
    required this.profile,
    this.autoComplete = true,
  });
  final AndroidEmulators manager;
  final AndroidEmulator emulator;
  final String platform, profile;
  final bool autoComplete;

  @override
  State<AndroidSetupDialog> createState() => _AndroidSetupDialogState();
}

class _AndroidSetupDialogState extends State<AndroidSetupDialog>
    with WidgetsBindingObserver {
  late final setup = AndroidEmulatorSetup(
    widget.manager,
    widget.emulator,
    widget.platform,
    widget.profile,
  )..addListener(_changed);
  bool completing = false;

  void _changed() {
    if (widget.autoComplete &&
        setup.step == AndroidSetupStep.ready &&
        !setup.busy &&
        !completing) {
      completing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => setup.verify());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setup.resumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    setup.removeListener(_changed);
    setup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([setup, widget.manager]),
    builder: (context, _) {
      final manager = widget.manager, emulator = widget.emulator;
      final downloading = manager.installing != null;
      return PopScope(
        canPop: !setup.busy,
        child: AlertDialog(
          scrollable: true,
          title: Text('Set up ${emulator.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (setup.busy) ...[
                LinearProgressIndicator(
                  value: downloading && (manager.downloadBytes ?? 0) > 0
                      ? manager.downloadedBytes / manager.downloadBytes!
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  manager.requestingInstallPermission
                      ? 'Enable Allow from this source for Broomm in Android settings, then return here.'
                      : downloading
                      ? 'Downloading ${switch (manager.installing) {
                          'mgba' => 'mGBA',
                          'snes9x' => 'Snes9x',
                          _ => emulator.name,
                        }} · ${(manager.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                      : 'Preparing ${emulator.name}…',
                ),
              ] else
                Text(switch (setup.step) {
                  AndroidSetupStep.install =>
                    'Install ${emulator.name} and confirm Android’s installation prompt. Setup continues when Android confirms the app is installed.',
                  AndroidSetupStep.waitingInstall =>
                    'Finish installing ${emulator.name} in Android, then return here to continue setup.',
                  AndroidSetupStep.initialize =>
                    'Open ${emulator.name} once, finish its first-run setup and permissions, then quit it. Broomm will check setup when you return.',
                  AndroidSetupStep.folder =>
                    'Open ${emulator.name} once and finish its first-run setup and permissions.\n\n${androidSetupInstructions(emulator)}\n\nClose the emulator before selecting its folder.',
                  AndroidSetupStep.ready => 'Ready to play',
                }),
              if (setup.problem != null) ProblemNotice(setup.problem!),
            ],
          ),
          actions: [
            if (setup.busy && downloading)
              ConsoleButton(
                onPressed: manager.cancelDownload,
                child: const Text('Cancel download'),
              ),
            if (!setup.busy) ...[
              ConsoleButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              if (setup.step == AndroidSetupStep.ready) ...[
                ConsoleButton(
                  onPressed: () => setup.install(imported: true),
                  child: const Text('Install APK…'),
                ),
                ConsoleButton(
                  onPressed: setup.install,
                  child: const Text('Get APK'),
                ),
                ConsoleButton(
                  autofocus: true,
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done'),
                ),
              ] else if (setup.step == AndroidSetupStep.install ||
                  setup.step == AndroidSetupStep.waitingInstall) ...[
                ConsoleButton(
                  onPressed: () => setup.install(imported: true),
                  child: const Text('Install APK…'),
                ),
                if (setup.step == AndroidSetupStep.waitingInstall)
                  ConsoleButton(
                    onPressed: setup.refresh,
                    child: const Text('Refresh status'),
                  ),
                ConsoleButton(
                  autofocus: true,
                  onPressed: setup.install,
                  child: Text(
                    emulator.id == 'duckstation' ? 'Download page' : 'Install',
                  ),
                ),
              ] else ...[
                if (setup.problem != null &&
                    (emulator.id == 'retroarch' &&
                            androidRootRetroCore(widget.platform) != null ||
                        {
                          'ppsspp',
                          'duckstation',
                          'melonds',
                        }.contains(emulator.id)) &&
                    setup.step != AndroidSetupStep.folder)
                  ConsoleButton(
                    onPressed: setup.useSharedFolder,
                    child: const Text('Use shared folder'),
                  ),
                ConsoleButton(
                  onPressed: setup.open,
                  child: const Text('Open emulator'),
                ),
                ConsoleButton(
                  autofocus: true,
                  onPressed: setup.step == AndroidSetupStep.folder
                      ? setup.selectFolder
                      : setup.verify,
                  child: Text(
                    setup.step == AndroidSetupStep.folder
                        ? 'Emulator closed · Select folder'
                        : 'Check setup',
                  ),
                ),
              ],
            ],
          ],
        ),
      );
    },
  );
}
