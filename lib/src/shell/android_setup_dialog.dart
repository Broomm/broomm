import 'package:flutter/material.dart';

import '../android/emulators.dart';
import '../android/root_saves.dart';
import '../android/setup.dart';
import '../romm/client.dart';
import 'controls.dart';

class AndroidSetupDialog extends StatefulWidget {
  const AndroidSetupDialog({
    super.key,
    required this.manager,
    required this.emulator,
    required this.platform,
    required this.profile,
    this.client,
    this.platformId,
    this.autoComplete = true,
  });
  final AndroidEmulators manager;
  final AndroidEmulator emulator;
  final String platform, profile;
  final bool autoComplete;
  final RommClient? client;
  final int? platformId;

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
    client: widget.client,
    platformId: widget.platformId,
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
      final duck = emulator.id == 'duckstation';
      final close = androidCloseInstructions(emulator.name);
      final sharedPs2 = setup.armsx2SharedSetup;
      final pendingPs2 = sharedPs2 && setup.hasPendingFolder;
      final initialize = emulator.id == 'ppsspp'
          ? 'Open PPSSPP once, choose Skip for now / App Private Data and wait for the main menu.'
          : 'Open ${emulator.name} once and finish its first-run setup and permissions.';
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
                      : setup.firmwarePhase ?? 'Preparing ${emulator.name}…',
                ),
              ] else
                Text(switch (setup.step) {
                  AndroidSetupStep.install =>
                    duck
                        ? 'Open DuckStation’s official beta page to download the APK, then open the downloaded file and confirm Android’s installation prompt.'
                        : 'Install ${emulator.name} and confirm Android’s installation prompt. Setup continues when Android confirms the app is installed.',
                  AndroidSetupStep.waitingInstall =>
                    duck
                        ? 'Install the APK from DuckStation’s official beta page, then return here to continue setup.'
                        : 'Finish installing ${emulator.name} in Android, then return here to continue setup.',
                  AndroidSetupStep.initialize => '$initialize\n\n$close',
                  AndroidSetupStep.folder =>
                    pendingPs2
                        ? '${setup.sharedBiosPrepared ? 'In ARMSX2’s BIOS step, select the Broomm BIOS subfolder inside the App Data Folder you just granted.' : 'If ARMSX2 needs a BIOS, choose Prepare BIOS from RomM below or import your own BIOS in ARMSX2.'}\n\nFinish ARMSX2’s setup, use its standard global memory cards and turn off per-game cards.\n\n$close'
                        : sharedPs2
                        ? '${androidSetupInstructions(emulator, prepared: setup.preparedFolder)} You can grant it now, before finishing ARMSX2’s setup.'
                        : 'Open ${emulator.name} once and finish its first-run setup and permissions.\n\n${androidSetupInstructions(emulator, prepared: setup.preparedFolder)}\n\n$close',
                  AndroidSetupStep.ready => 'Ready to play',
                }),
              if (setup.folderProblem case final problem?)
                ProblemNotice(problem),
              if (setup.problem != null) ProblemNotice(setup.problem!),
              if (setup.problem != null &&
                  {
                    AndroidSetupStep.initialize,
                    AndroidSetupStep.folder,
                  }.contains(setup.step))
                const Text(
                  'If the emulator stays open after you save and quit, use Force stop in Android App info.',
                ),
            ],
          ),
          actions: [
            if (setup.busy && downloading)
              ConsoleButton(
                onPressed: manager.cancelDownload,
                child: const Text('Cancel download'),
              ),
            if (setup.busy && setup.preparingFirmware)
              ConsoleButton(
                onPressed: setup.cancelFirmware,
                child: const Text('Cancel setup'),
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
                  child: Text(duck ? 'Download page' : 'Get APK'),
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
                    (setup.canUseShared3dsFolder ||
                        (emulator.id == 'retroarch' &&
                                    androidRootRetroCore(widget.platform) !=
                                        null ||
                                {
                                  'ppsspp',
                                  'duckstation',
                                  'melonds',
                                  'dolphin',
                                  'eden',
                                  'armsx2',
                                }.contains(emulator.id)) &&
                            setup.step != AndroidSetupStep.folder))
                  ConsoleButton(
                    onPressed: setup.useSharedFolder,
                    child: const Text('Use shared folder'),
                  ),
                if (setup.problem != null)
                  ConsoleButton(
                    onPressed: setup.openAppInfo,
                    child: const Text('Android App info'),
                  ),
                if (setup.hasPendingFolder)
                  ConsoleButton(
                    onPressed: () => setup.selectFolder(change: true),
                    child: const Text('Choose another folder'),
                  ),
                if (!setup.hasPendingFolder || pendingPs2)
                  ConsoleButton(
                    onPressed: setup.open,
                    child: const Text('Open emulator'),
                  ),
                if (setup.canPrepareSharedBios && !setup.sharedBiosPrepared)
                  ConsoleButton(
                    onPressed: setup.prepareSharedBios,
                    child: const Text('Prepare BIOS from RomM'),
                  ),
                ConsoleButton(
                  autofocus: true,
                  onPressed: setup.step == AndroidSetupStep.folder
                      ? setup.selectFolder
                      : setup.verify,
                  child: Text(
                    setup.hasPendingFolder
                        ? 'Verify selected folder'
                        : sharedPs2
                        ? 'Select App Data Folder'
                        : setup.step == AndroidSetupStep.folder
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
