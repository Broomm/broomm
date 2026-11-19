import 'package:flutter/material.dart';

import '../android/duck_root.dart';
import '../android/psp_root.dart';
import '../android/root_saves.dart';
import '../android/session.dart';
import 'controls.dart';
import 'navigation.dart';

Future<bool> confirmAndroidEmulatorClose(
  BuildContext context,
  String emulator,
  bool canStop,
) async =>
    await showConsoleDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        content: Text(
          canStop
              ? 'Broomm will force-close $emulator before continuing. Continue?'
              : 'Is $emulator closed?',
        ),
        actions: [
          ConsoleButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('No'),
          ),
          ConsoleButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    ) ??
    false;

class AndroidSessionScreen extends StatefulWidget {
  const AndroidSessionScreen({
    super.key,
    required this.session,
    required this.title,
    required this.emulator,
    required this.finish,
    this.start,
    this.openSetup,
    this.recovering = false,
    this.rooted = false,
  });

  final AndroidGameSession session;
  final String title, emulator;
  final Future<void> Function(Future<bool> Function(bool canStop) confirm)?
  start;
  final Future<void> Function()? openSetup;
  final Future<void> Function() finish;
  final bool recovering, rooted;

  @override
  State<AndroidSessionScreen> createState() => _AndroidSessionScreenState();
}

class _AndroidSessionScreenState extends State<AndroidSessionScreen>
    with WidgetsBindingObserver {
  bool _working = false, _leaving = false, _frontendSetup = false;
  bool _pausedInEmulator = false, _returned = false, _promptOpen = false;
  String? _error;

  AndroidGameSession get session => widget.session;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && session.active)
      _pausedInEmulator = true;
    if (state == AppLifecycleState.resumed && _pausedInEmulator) {
      _pausedInEmulator = false;
      _returned = true;
      _onReturn();
    }
  }

  void _onReturn() {
    if (!_returned || !mounted || session.busy || _working || _leaving) return;
    _returned = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_working && !_leaving) _run(_finish);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<bool> _confirm(bool canStop) async {
    if (!mounted) return false;
    setState(() => _promptOpen = true);
    try {
      return await confirmAndroidEmulatorClose(
        context,
        widget.emulator,
        canStop,
      );
    } finally {
      if (mounted) setState(() => _promptOpen = false);
    }
  }

  Future<void> _start() async {
    _frontendSetup = false;
    try {
      await widget.start!(_confirm);
      if (!session.active) _leave();
    } on AndroidRetroArchSetupRequired {
      _frontendSetup = true;
    }
  }

  Future<void> _finish() async {
    final closed =
        !widget.recovering &&
        (widget.rooted
            ? switch (widget.emulator) {
                'DuckStation' =>
                  await session.finishIfDuckClosed() == AndroidDuckState.closed,
                'PPSSPP' =>
                  await session.finishIfPspClosed() == AndroidPspState.closed,
                _ =>
                  await session.finishIfRetroArchClosed() ==
                      AndroidRetroArchState.closed,
              }
            : await session.finishIfStandaloneClosed() ==
                  AndroidRetroArchState.closed);
    if (!closed && await session.approveFinish(_confirm)) {
      await widget.finish();
    }
    _leave();
  }

  Future<void> _leaveFolderUnchanged() async {
    if (await session.approveFinish(_confirm)) {
      await session.keepMmjFolder(emulatorClosed: true);
    }
    _leave();
  }

  void _leave() {
    if (!mounted) return;
    _leaving = true;
    Navigator.pop(context);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working || _leaving) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      _error = '$e';
    } finally {
      _working = false;
      if (mounted && !_leaving) {
        setState(() {});
        _onReturn();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session.addListener(_onReturn);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run(widget.recovering ? _finish : _start);
    });
  }

  @override
  void dispose() {
    session.removeListener(_onReturn);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final working = _working || session.busy;
      final finishing = widget.recovering || session.active;
      final folderRecovery =
          finishing && !{'PPSSPP', 'DuckStation'}.contains(widget.emulator);
      return PopScope(
        canPop: !working,
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
                      if (working && !_promptOpen)
                        const LinearProgressIndicator(),
                      if (session.canCancelPreparation)
                        ConsoleButton(
                          onPressed: session.cancelPreparation,
                          child: const Text('Cancel preparation'),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        _frontendSetup
                            ? 'Open RetroArch to install its bundled resources. Wait for its main menu, then quit RetroArch and return here.'
                            : session.phase.isNotEmpty
                            ? session.phase
                            : 'Checking whether ${widget.emulator} is closed…',
                        style: const TextStyle(height: 1.6),
                      ),
                      if (_error != null) ...[
                        ProblemNotice(_error!),
                        if (folderRecovery) ...[
                          ConsoleButton(
                            onPressed: working
                                ? null
                                : () => _run(session.reconnectFolder),
                            child: const Text('Reconnect original save folder'),
                          ),
                          ConsoleButton(
                            onPressed: working
                                ? null
                                : () => _run(_leaveFolderUnchanged),
                            child: const Text('Keep emulator folder unchanged'),
                          ),
                        ],
                      ],
                      if (_frontendSetup && widget.openSetup != null)
                        ConsoleButton(
                          autofocus: true,
                          onPressed: working
                              ? null
                              : () => _run(widget.openSetup!),
                          child: const Text('Open RetroArch'),
                        ),
                      if (_error != null || _frontendSetup) ...[
                        const SizedBox(height: 12),
                        ConsoleButton(
                          onPressed: working
                              ? null
                              : () => _run(finishing ? _finish : _start),
                          child: const Text('Retry'),
                        ),
                        const SizedBox(height: 12),
                        ConsoleButton(
                          onPressed: working ? null : _leave,
                          child: const Text('Back'),
                        ),
                      ],
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
