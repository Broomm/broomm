import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../android/emulators.dart';
import '../android/root_inspection.dart';
import 'controls.dart';

class AndroidRootInspectionDialog extends StatefulWidget {
  const AndroidRootInspectionDialog({
    super.key,
    required this.emulator,
    required this.app,
    this.inspector,
  });
  final AndroidEmulator emulator;
  final AndroidApp app;
  final AndroidRootInspector? inspector;
  @override
  State<AndroidRootInspectionDialog> createState() =>
      _AndroidRootInspectionDialogState();
}

class _AndroidRootInspectionDialogState
    extends State<AndroidRootInspectionDialog> {
  late final inspector = widget.inspector ?? AndroidRootInspector();
  bool busy = false;
  AndroidRootReport? report;
  String? problem;

  Future<void> inspect() async {
    setState(() {
      busy = true;
      report = null;
      problem = null;
    });
    try {
      final value = await inspector.inspect(widget.emulator, widget.app);
      if (mounted) setState(() => report = value);
    } catch (e) {
      if (mounted)
        setState(
          () => problem = e is PlatformException
              ? e.message ?? 'Root inspection failed.'
              : '$e',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    inspector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text('Inspect ${widget.emulator.name} root access'),
    content: SizedBox(
      width: 640,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Selected app: ${widget.app.package} · ${widget.app.version}'),
          const SizedBox(height: 12),
          const Text(
            'On an already rooted device, check this app’s identity and private folder metadata. Magisk or your root manager may ask for permission. The read-only check times out after 30 seconds.',
          ),
          if (busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const Text('Waiting for root permission and directory inspection…'),
          ],
          if (problem != null) ProblemNotice(problem!),
          if (report case final value?) ...[
            const SizedBox(height: 16),
            const Text(
              'Read-only inspection completed',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'Snapshot of this request; future access must be verified again.',
            ),
            const SizedBox(height: 8),
            SelectableText(
              [
                '${value.values['device']} · Android ${value.values['android']} (API ${value.values['sdk']})',
                'ABIs: ${(value.values['abis'] as List).join(', ')}',
                'Android user: ${value.values['user']} · UID: ${value.values['uid']} · GID: ${value.values['gid']}',
                'Data directory: ${value.values['dataDir']}',
                'Mode: ${value.values['mode']} · Label: ${value.values['label']}',
                'Signer SHA-256: ${value.values['signer']}',
                'Build observation: ${value.values['build']}',
                if (value.values['memoryStick'] case final Map memory)
                  memory['kind'] == 'private'
                      ? 'PPSSPP app-private memory stick: ${memory['path']}\nStorage identity verified read-only. This inspection does not connect saves.'
                      : 'PPSSPP uses another memory-stick location. Its contents were not inspected.',
                if (value.values['appFiles'] case final Map files)
                  'DuckStation app-private files: ${files['path']}\nInitialized settings metadata verified (${files['settingsBytes']} bytes). Selected save folders and their contents were not inspected; no save connection was created.',
              ].join('\n'),
            ),
          ],
        ],
      ),
    ),
    actions: [
      ConsoleButton(
        autofocus: true,
        onPressed: () => Navigator.pop(context),
        child: Text(busy ? 'Cancel and close' : 'Close'),
      ),
      if (busy)
        ConsoleButton(
          onPressed: inspector.cancel,
          child: const Text('Cancel inspection'),
        )
      else
        ConsoleButton(
          onPressed: inspect,
          child: Text(
            problem == null && report == null
                ? 'Request root inspection'
                : 'Inspect again',
          ),
        ),
    ],
  );
}
