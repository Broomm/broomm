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

class _AndroidSessionScreenState extends State<AndroidSessionScreen>
    with WidgetsBindingObserver {
  bool started = false;
  bool completed = false;
  String? error;
  bool _leftForEmulator = false, _offerSync = false, _promptOpen = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && widget.session.active)
      _leftForEmulator = true;
    if (state == AppLifecycleState.resumed && _leftForEmulator) {
      _leftForEmulator = false;
      _offerSync = true;
      _showReturnPrompt();
    }
  }

  void _showReturnPrompt() {
    if (!_offerSync ||
        _promptOpen ||
        widget.session.busy ||
        !widget.session.active ||
        !mounted)
      return;
    _offerSync = false;
    _promptOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await run(finishPrompt);
      _promptOpen = false;
    });
  }

  Future<void> finishPrompt() async {
    final confirmed = await showConsoleDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Finished? Sync progress'),
        content: const Text(
          'Save your progress and close the emulator before syncing. Returning to Broomm can leave it running. Only continue when you have finished playing.',
        ),
        actions: [
          ConsoleButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Not finished'),
          ),
          ConsoleButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Emulator closed · Sync progress'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.finish();
    if (!mounted) return;
    setState(() => completed = true);
    Navigator.pop(context);
  }

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
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_showReturnPrompt);
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_showReturnPrompt);
    super.dispose();
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
                      if (error != null && active)
                        ConsoleButton(
                          onPressed: session.busy
                              ? null
                              : () => run(session.reconnectFolder),
                          child: const Text('Reconnect original save folder'),
                        ),
                      if (error != null && active)
                        ConsoleButton(
                          onPressed: session.busy
                              ? null
                              : () => run(() async {
                                  final keep = await showConsoleDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text(
                                        'Leave the emulator’s saves unchanged?',
                                      ),
                                      content: const Text(
                                        'Close the emulator first. Broomm will finish this session without changing its folder or uploading uncertain progress. Private recovery copies will be kept. Use this when folder access or an external save change prevents normal recovery.',
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
                                            'Emulator closed · Keep folder unchanged',
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (keep != true) return;
                                  await session.keepMmjFolder(
                                    emulatorClosed: true,
                                  );
                                  if (mounted) {
                                    setState(() => completed = true);
                                    Navigator.pop(context);
                                  }
                                }),
                          child: Text(
                            widget.emulator == 'Citra MMJ'
                                ? 'Keep MMJ folder unchanged · Finish'
                                : 'Keep emulator folder unchanged · Finish',
                          ),
                        ),
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
