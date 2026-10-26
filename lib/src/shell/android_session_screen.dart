import 'package:flutter/material.dart';

import '../android/session.dart';
import 'controls.dart';
import 'navigation.dart';

class AndroidSessionScreen extends StatefulWidget {
  const AndroidSessionScreen({
    super.key,
    required this.session,
    required this.title,
    required this.emulator,
    required this.finish,
    this.start,
    this.resume,
    this.cloudReady = false,
    this.recovering = false,
  });
  final AndroidGameSession session;
  final String title, emulator;
  final Future<void> Function()? start, resume;
  final Future<void> Function() finish;
  final bool cloudReady, recovering;
  @override
  State<AndroidSessionScreen> createState() => _AndroidSessionScreenState();
}

class _AndroidSessionScreenState extends State<AndroidSessionScreen> {
  bool started = false;
  bool completed = false;
  String? error;
  Future<void> run(Future<void> Function() action) async {
    setState(() => error = null);
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // With no shared save storage there is nothing to restore before handoff.
    if (!widget.recovering && !widget.cloudReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          started = true;
          run(widget.start!);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      final active = session.active || widget.recovering && !completed;
      return PopScope(
        canPop: !session.busy && !active,
        child: Scaffold(
          body: SafeArea(
            child: ConsoleScrollBody(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.emulator,
                        style: const TextStyle(color: muted, fontSize: 20),
                      ),
                      const SizedBox(height: 24),
                      if (session.busy) const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        widget.recovering
                            ? 'A previous external emulator session still needs to be finished. Save and close the emulator before continuing.'
                            : session.phase.isNotEmpty
                            ? session.phase
                            : 'Save and close any open emulator before Broomm restores cloud progress and launches the game.',
                        style: const TextStyle(height: 1.6),
                      ),
                      if (!widget.cloudReady && !widget.recovering) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'Cloud save access is not configured for this Android emulator/profile. Progress stays in the emulator; cloud saves and states will not be synchronized.',
                          style: TextStyle(color: muted, height: 1.6),
                        ),
                      ],
                      if (error != null) ProblemNotice(error!),
                      const SizedBox(height: 24),
                      if (!active && !started)
                        ConsoleButton(
                          autofocus: true,
                          onPressed: session.busy
                              ? null
                              : () {
                                  started = true;
                                  run(widget.start!);
                                },
                          child: const Text('Emulator closed · Sync and play'),
                        ),
                      if (active) ...[
                        if (widget.resume != null)
                          ConsoleButton(
                            onPressed: session.busy
                                ? null
                                : () => run(widget.resume!),
                            child: const Text('Return to emulator'),
                          ),
                        const SizedBox(height: 12),
                        ConsoleButton(
                          autofocus: true,
                          onPressed: session.busy
                              ? null
                              : () => run(() async {
                                  final confirmed =
                                      await showConsoleDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text(
                                            'Finish game session?',
                                          ),
                                          content: const Text(
                                            'Save your progress and exit the emulator completely first. Switching back to Broomm can leave the emulator running in the background.',
                                          ),
                                          actions: [
                                            ConsoleButton(
                                              autofocus: true,
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: const Text('Cancel'),
                                            ),
                                            ConsoleButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              child: const Text(
                                                'Emulator closed · Finish',
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                  if (confirmed != true) return;
                                  await widget.finish();
                                  if (!mounted) return;
                                  setState(() => completed = true);
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) Navigator.pop(context);
                                  });
                                }),
                          child: Text(
                            widget.cloudReady
                                ? 'Finish and sync progress'
                                : 'Finish game session',
                          ),
                        ),
                      ] else if (!session.busy)
                        ConsoleButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Back'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
