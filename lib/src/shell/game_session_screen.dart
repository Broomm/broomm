import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_model.dart';
import '../catalogue.dart';
import '../host.dart';
import '../widgets/pairing_screen.dart';
import 'controls.dart';
import 'navigation.dart';

class GameSessionScreen extends StatefulWidget {
  const GameSessionScreen({
    super.key,
    required this.model,
    required this.game,
    this.beforeClose,
    this.launcherController,
  });
  final PrototypeModel model;
  final LaunchGame game;
  final Future<void> Function()? beforeClose;
  final void Function(String)? launcherController;
  @override
  State<GameSessionScreen> createState() => _GameSessionScreenState();
}

class _GameSessionScreenState extends State<GameSessionScreen> {
  PrototypeModel get m => widget.model;
  bool leaving = false;
  @override
  void initState() {
    super.initState();
    m.addListener(changed);
    DesktopHost.channel.setMethodCallHandler((call) async {
      if (call.method == 'closeRequested') {
        await widget.beforeClose?.call();
        if (m.session.finalizingProgress) await m.session.stop();
        await m.stop(close: true);
      }
      // Pairing buttons belong to the live tester/chords, not UI shortcuts.
      // Before startup and after writer exit, console dialogs/cancel actions
      // need launcher navigation while there is no emulator SDL event source.
      if (call.method == 'controller' &&
          m.screen == Screen.loading &&
          !m.session.running)
        widget.launcherController?.call(call.arguments as String);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(m.select(widget.game));
    });
  }

  void changed() {
    if (!leaving &&
        m.screen == Screen.library &&
        !m.session.running &&
        !m.busy) {
      leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    m.removeListener(changed);
    super.dispose();
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (m.screen == Screen.menu)
        unawaited(m.play());
      else if (m.screen == Screen.playing)
        unawaited(m.menu());
      else
        unawaited(m.stop());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        m.screen == Screen.pairing &&
        node.hasPrimaryFocus &&
        m.canPlay) {
      unawaited(m.play());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: m,
    builder: (context, _) => PopScope(
      canPop: !m.session.running && !m.busy,
      child: Focus(
        autofocus: true,
        onKeyEvent: key,
        child: Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(.7, -.3),
                radius: 1.5,
                colors: [
                  Color(0xff203d40),
                  Color(0xff101c28),
                  Color(0xff080f19),
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width > 850 ? 48 : 24,
                  24,
                  MediaQuery.sizeOf(context).width > 850 ? 48 : 24,
                  22,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.all_inclusive_rounded,
                          color: accent,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'broomm',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -1,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            widget.game.emulator,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.game.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, color: muted),
                    ),
                    const SizedBox(height: 14),
                    if (m.error != null) ProblemNotice(m.error!),
                    Expanded(
                      child: ConsoleScreenTransition(
                        identity: m.screen,
                        child: switch (m.screen) {
                          Screen.pairing => PairingScreen(model: m),
                          Screen.menu => ConsoleScrollBody(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Eyebrow('Take a moment'),
                                  const SizedBox(height: 18),
                                  const Text(
                                    'Game paused',
                                    style: TextStyle(
                                      fontSize: 42,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  ConsoleButton(
                                    autofocus: true,
                                    onPressed: m.busy ? null : m.showPairing,
                                    child: const ActionLabel(
                                      'Controller pairing',
                                      icon: Icons.sports_esports_outlined,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  const Text(
                                    'Hold Start to resume · Esc to return',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Screen.playing => ConsoleScrollBody(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.sports_esports_outlined,
                                  color: accent,
                                  size: 64,
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'Your game is running',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'R3 + Select opens controller pairing and the game menu.',
                                  style: TextStyle(color: muted),
                                ),
                                const SizedBox(height: 24),
                                ConsoleButton(
                                  onPressed: () => m.menu(),
                                  child: const Text('Open game menu'),
                                ),
                              ],
                            ),
                          ),
                          _ => ConsoleScrollBody(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Eyebrow(
                                    m.session.finalizingProgress
                                        ? 'Keeping your progress safe'
                                        : 'Getting your game ready',
                                  ),
                                  const SizedBox(height: 28),
                                  const SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  Text(
                                    m.session.finalizingProgress
                                        ? 'Syncing progress…'
                                        : 'Loading ${widget.game.emulator}…',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  if (!m.session.finalizingProgress &&
                                      widget.game.emulator.startsWith(
                                        'RPCS3',
                                      )) ...[
                                    LinearProgressIndicator(
                                      value:
                                          m.session.status?.loading?.fraction,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      m.session.status?.loading?.description ??
                                          'Waiting for RPCS3 loading progress…',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: muted),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Current loading phase · progress may reset between phases',
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                  ],
                                  Text(
                                    m.notice,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: muted,
                                      height: 1.6,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    m.session.finalizingProgress
                                        ? 'Your local recovery copy stays on this device if the transfer cannot finish.'
                                        : 'Pairing appears when the game and controller input are ready.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 26),
                                  ConsoleButton(
                                    onPressed: m.session.finalizingProgress
                                        ? m.session.cancelProgressTransfer
                                        : m.busy
                                        ? null
                                        : () => m.stop(),
                                    child: Text(
                                      m.session.finalizingProgress
                                          ? 'Keep local save and finish later'
                                          : 'Cancel launch',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Progress stays private to this profile · Cloud sync uses its BROOMM save history',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
