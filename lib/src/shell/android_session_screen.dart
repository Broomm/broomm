import 'package:flutter/material.dart';

import '../android/root_saves.dart';
import '../android/session.dart';
import '../android/psp_root.dart';
import '../android/duck_root.dart';
import '../android/setup.dart';
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
    this.rooted = false,
    this.forceCloseAvailable = false,
  });
  final AndroidGameSession session;
  final String title, emulator;
  final Future<void> Function({required bool emulatorClosed})? start;
  final Future<void> Function()? resume;
  final Future<void> Function() finish;
  final bool cloudReady, recovering, rooted, forceCloseAvailable;
  @override
  State<AndroidSessionScreen> createState() => _AndroidSessionScreenState();
}

enum _FinishChoice { keepPlaying, appInfo, forceClose, closed }

class _AndroidSessionScreenState extends State<AndroidSessionScreen>
    with WidgetsBindingObserver {
  bool started = false;
  bool completed = false;
  String? error;
  bool _manualStart = false, _frontendSetup = false;
  AndroidRetroArchState? _retroArchState;
  bool _leftForEmulator = false, _offerSync = false, _promptOpen = false;
  bool _openingAppInfo = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_openingAppInfo) {
      if (state == AppLifecycleState.resumed) _openingAppInfo = false;
      return;
    }
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
      if (mounted) {
        await run(
          widget.rooted
              ? finishRooted
              : widget.session.tracksStandaloneExit
              ? finishStandalone
              : finishPrompt,
        );
      }
      _promptOpen = false;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> start({required bool emulatorClosed}) async {
    started = true;
    _frontendSetup = false;
    await run(() async {
      try {
        await widget.start!(emulatorClosed: emulatorClosed);
      } catch (e) {
        if (widget.rooted && !widget.session.active) {
          started = false;
          _manualStart = e is AndroidClosureUnverified;
          _frontendSetup = e is AndroidRetroArchSetupRequired;
          if (_frontendSetup) return;
        }
        rethrow;
      }
    });
  }

  Future<void> finishRooted() async {
    if (widget.emulator == 'DuckStation') {
      final state = await widget.session.finishIfDuckClosed();
      if (state == AndroidDuckState.closed) complete();
      _retroArchState =
          {
            AndroidDuckState.unknown,
            AndroidDuckState.interrupted,
          }.contains(state)
          ? AndroidRetroArchState.unknown
          : null;
      return;
    }
    if (widget.emulator == 'PPSSPP') {
      final state = await widget.session.finishIfPspClosed();
      if (state == AndroidPspState.closed) complete();
      // PPSSPP has its own lifecycle proof; an uncertain writer stays in
      // recovery and manual completion still performs the native guard.
      _retroArchState =
          state == AndroidPspState.unknown ||
              state == AndroidPspState.interrupted
          ? AndroidRetroArchState.unknown
          : null;
      return;
    }
    _retroArchState = await widget.session.finishIfRetroArchClosed();
    if (_retroArchState == AndroidRetroArchState.closed) complete();
  }

  Future<void> finishStandalone() async {
    _retroArchState = await widget.session.finishIfStandaloneClosed();
    if (_retroArchState == AndroidRetroArchState.closed) complete();
  }

  Future<void> forceClose() async {
    final confirmed = await showConsoleDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Force-close ${widget.emulator}?'),
        content: const Text(
          'Save in the emulator before force-closing it. Unsaved progress can be lost. Broomm will sync the saved files it can verify after the emulator closes.',
        ),
        actions: [
          ConsoleButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ConsoleButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Force close and sync'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.session.forceClose();
    await widget.finish();
    complete();
  }

  void complete() {
    if (!mounted) return;
    setState(() => completed = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true)
        Navigator.pop(context);
    });
  }

  Future<void> finishPrompt() async {
    final choice = await showConsoleDialog<_FinishChoice>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Finish game session?'),
        content: Text(
          'Save your progress in ${widget.emulator} first. ${androidCloseInstructions(widget.emulator)}\n\n'
          '${widget.forceCloseAvailable ? 'If Android keeps it open, use Force close after saving and quitting.' : 'If it stays open after you save and quit, use Force stop in Android App info.'}',
        ),
        actions: [
          ConsoleButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, _FinishChoice.keepPlaying),
            child: const Text('Keep playing'),
          ),
          if (widget.forceCloseAvailable)
            ConsoleButton(
              onPressed: () => Navigator.pop(c, _FinishChoice.forceClose),
              child: const Text('Force close'),
            )
          else
            ConsoleButton(
              onPressed: () => Navigator.pop(c, _FinishChoice.appInfo),
              child: const Text('Android App info'),
            ),
          ConsoleButton(
            onPressed: () => Navigator.pop(c, _FinishChoice.closed),
            child: Text(
              widget.cloudReady
                  ? 'Emulator closed · Sync progress'
                  : 'Emulator closed · Finish',
            ),
          ),
        ],
      ),
    );
    if (choice == _FinishChoice.appInfo) {
      await openAppInfo();
    } else if (choice == _FinishChoice.forceClose) {
      if (mounted) await forceClose();
    } else if (choice == _FinishChoice.closed) {
      await widget.finish();
      complete();
    }
  }

  Future<void> openAppInfo() async {
    _openingAppInfo = true;
    try {
      await widget.session.openEmulatorAppInfo();
    } catch (_) {
      _openingAppInfo = false;
      rethrow;
    }
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
    if (!widget.recovering && (widget.rooted || !widget.cloudReady)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) start(emulatorClosed: !widget.rooted);
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
      final checkExit =
          (widget.rooted || session.tracksStandaloneExit) &&
          _retroArchState != AndroidRetroArchState.unknown &&
          _retroArchState != AndroidRetroArchState.interrupted;
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
                      if (session.canCancelPreparation)
                        ConsoleButton(
                          onPressed: session.cancelPreparation,
                          child: const Text('Cancel preparation'),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        widget.recovering
                            ? 'A previous external emulator session still needs to be finished. Save and close the emulator before continuing.'
                            : session.phase.isNotEmpty
                            ? session.phase
                            : widget.rooted
                            ? 'Checking whether ${widget.emulator} is closed…'
                            : 'Broomm restores cloud progress before launching the game. Save any open progress first. ${androidCloseInstructions(widget.emulator)}',
                        style: const TextStyle(height: 1.6),
                      ),
                      if (!widget.cloudReady && !widget.recovering) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'Cloud save access is not configured for this Android emulator/profile. Progress stays in the emulator; cloud saves and states will not be synchronized.',
                          style: TextStyle(color: muted, height: 1.6),
                        ),
                      ],
                      if (_frontendSetup) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Open RetroArch to install its bundled resources. Wait for its main menu, then quit RetroArch and return here.',
                        ),
                        if (widget.resume != null)
                          ConsoleButton(
                            autofocus: true,
                            onPressed: session.busy
                                ? null
                                : () => run(widget.resume!),
                            child: const Text('Open RetroArch'),
                          ),
                      ],
                      if (error != null) ProblemNotice(error!),
                      if (error != null &&
                          !active &&
                          !started &&
                          widget.rooted &&
                          widget.emulator == 'PPSSPP' &&
                          widget.resume != null)
                        ConsoleButton(
                          onPressed: session.busy
                              ? null
                              : () => run(widget.resume!),
                          child: const Text('Open PPSSPP'),
                        ),
                      if (error != null &&
                          active &&
                          !(widget.rooted &&
                              {
                                'PPSSPP',
                                'DuckStation',
                              }.contains(widget.emulator)))
                        ConsoleButton(
                          onPressed: session.busy
                              ? null
                              : () => run(session.reconnectFolder),
                          child: const Text('Reconnect original save folder'),
                        ),
                      if (error != null &&
                          active &&
                          !(widget.rooted &&
                              {
                                'PPSSPP',
                                'DuckStation',
                              }.contains(widget.emulator)))
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
                          autofocus: !_frontendSetup,
                          onPressed: session.busy
                              ? null
                              : () => start(
                                  emulatorClosed:
                                      !widget.rooted || _manualStart,
                                ),
                          child: Text(
                            widget.rooted && !_manualStart
                                ? 'Check and play'
                                : 'Emulator closed · Sync and play',
                          ),
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
                              : checkExit
                              ? () => run(
                                  widget.rooted
                                      ? finishRooted
                                      : finishStandalone,
                                )
                              : () => run(finishPrompt),
                          child: Text(
                            checkExit
                                ? 'Check for exit'
                                : widget.rooted
                                ? 'Review and finish session'
                                : widget.cloudReady
                                ? 'Finish and sync progress'
                                : 'Finish game session',
                          ),
                        ),
                        if (widget.forceCloseAvailable) ...[
                          const SizedBox(height: 12),
                          ConsoleButton(
                            onPressed: session.busy
                                ? null
                                : () => run(forceClose),
                            child: const Text('Force close'),
                          ),
                          if (error != null)
                            ConsoleButton(
                              onPressed: session.busy
                                  ? null
                                  : () => run(openAppInfo),
                              child: const Text('Android App info'),
                            ),
                        ],
                      ] else if (!session.busy) ...[
                        if (!started) const SizedBox(height: 12),
                        ConsoleButton(
                          onPressed: () => Navigator.pop(context),
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
