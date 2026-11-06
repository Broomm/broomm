import 'package:flutter/material.dart';

import '../android/emulators.dart';
import 'controls.dart';

/// Keeps installation feedback visible even when the invoking card is scrolled.
class AndroidInstallDialog extends StatefulWidget {
  const AndroidInstallDialog({
    super.key,
    required this.manager,
    required this.emulator,
    required this.install,
  });

  final AndroidEmulators manager;
  final AndroidEmulator emulator;
  final Future<void> Function() install;

  @override
  State<AndroidInstallDialog> createState() => _AndroidInstallDialogState();
}

class _AndroidInstallDialogState extends State<AndroidInstallDialog> {
  bool working = true;
  String? problem;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  Future<void> run() async {
    if (!mounted) return;
    setState(() {
      working = true;
      problem = null;
    });
    try {
      await widget.install();
      if (!mounted) return;
      // The OS owns confirmation. Package readback establishes installation.
      setState(() => working = false);
      Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(() {
          working = false;
          problem = '$e';
        });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.manager,
    builder: (context, _) {
      final manager = widget.manager;
      final downloading = manager.installing == widget.emulator.id;
      return PopScope(
        canPop: !working,
        child: AlertDialog(
          scrollable: true,
          title: Text('Install ${widget.emulator.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (working) ...[
                LinearProgressIndicator(
                  value: downloading && (manager.downloadBytes ?? 0) > 0
                      ? manager.downloadedBytes / manager.downloadBytes!
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  manager.requestingInstallPermission
                      ? 'Enable Allow from this source for Broomm in Android settings, then return here. Installation will continue automatically.'
                      : downloading
                      ? 'Downloading emulator APK · ${(manager.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                      : 'Preparing installation…',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Android will ask you to confirm installation. Downloading an APK does not install the emulator.',
                ),
              ],
              if (problem != null) ProblemNotice(problem!),
            ],
          ),
          actions: [
            if (working && downloading)
              ConsoleButton(
                onPressed: manager.cancelDownload,
                child: const Text('Cancel download'),
              ),
            if (!working) ...[
              ConsoleButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              ConsoleButton(onPressed: run, child: const Text('Try again')),
            ],
          ],
        ),
      );
    },
  );
}
