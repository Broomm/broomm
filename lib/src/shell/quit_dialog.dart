import 'dart:async';

import 'package:flutter/material.dart';

import 'controls.dart';
import 'navigation.dart';

/// Shutdown stays observable even when a native writer cannot stop. Quitting
/// immediately never clears its locks, save journals or partial-work staging.
Future<void> showQuitDialog(
  BuildContext context, {
  required Future<void> Function(void Function(String) phase) finish,
  required Future<void> Function() exit,
}) => showConsoleDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _QuitDialog(finish: finish, exit: exit),
);

class _QuitDialog extends StatefulWidget {
  const _QuitDialog({required this.finish, required this.exit});
  final Future<void> Function(void Function(String)) finish;
  final Future<void> Function() exit;
  @override
  State<_QuitDialog> createState() => _QuitDialogState();
}

class _QuitDialogState extends State<_QuitDialog> {
  String phase = 'Stopping current work…';
  String? problem;
  bool slow = false, exiting = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(run());
    });
  }

  Future<void> run() async {
    timer?.cancel();
    if (mounted)
      setState(() {
        problem = null;
        slow = false;
      });
    timer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => slow = true);
    });
    try {
      await widget.finish((value) {
        if (mounted) setState(() => phase = value);
      });
      if (mounted) await exit();
    } catch (error) {
      if (mounted) setState(() => problem = '$error');
    } finally {
      timer?.cancel();
    }
  }

  Future<void> exit() async {
    if (exiting) return;
    setState(() => exiting = true);
    try {
      await widget.exit();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted)
        setState(() {
          exiting = false;
          problem = '$error';
        });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: problem != null,
    child: Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ConsoleScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Closing Broomm', style: TextStyle(fontSize: 28)),
              const SizedBox(height: 20),
              if (problem == null) const LinearProgressIndicator(),
              const SizedBox(height: 18),
              Text(
                problem ?? phase,
                style: const TextStyle(color: muted, height: 1.6),
              ),
              if (slow || problem != null) ...[
                const SizedBox(height: 18),
                const Text(
                  'You can quit Broomm now and keep its recovery data. An emulator may remain open. Unfinished saves and transfers will need review when you return.',
                  style: TextStyle(color: muted, height: 1.6),
                ),
                const SizedBox(height: 22),
                ConsoleButton(
                  autofocus: true,
                  onPressed: exiting ? null : exit,
                  child: const Text('Quit Broomm now'),
                ),
              ],
              if (problem != null) ...[
                const SizedBox(height: 12),
                ConsoleButton(
                  onPressed: exiting ? null : run,
                  child: const Text('Retry closing'),
                ),
                const SizedBox(height: 12),
                ConsoleButton(
                  onPressed: exiting ? null : () => Navigator.pop(context),
                  child: const Text('Keep Broomm open'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
