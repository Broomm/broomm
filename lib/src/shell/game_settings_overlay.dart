import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_model.dart';
import 'controls.dart';
import 'navigation.dart';

class GameSettingsOverlay extends StatefulWidget {
  const GameSettingsOverlay({
    super.key,
    required this.model,
    required this.enabled,
  });

  final PrototypeModel model;
  final bool enabled;

  // Use the same native launcher events as Home. The emulator bridge still
  // owns the opening chord, input gate, and the separate pairing screen.
  static bool controller(String input) {
    final context = FocusManager.instance.primaryFocus?.context;
    final overlay = context
        ?.findAncestorStateOfType<_GameSettingsOverlayState>();
    if (overlay == null || ModalRoute.isCurrentOf(overlay.context) == false)
      return false;
    overlay.controller(input);
    return true;
  }

  @override
  State<GameSettingsOverlay> createState() => _GameSettingsOverlayState();
}

class _GameSettingsOverlayState extends State<GameSettingsOverlay> {
  final pairing = FocusNode(debugLabel: 'Controller pairing');
  final close = FocusNode(debugLabel: 'Close game');
  PrototypeModel get m => widget.model;
  bool get ready => widget.enabled && !m.busy && m.screen == Screen.menu;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) focusPairing();
  }

  @override
  void didUpdateWidget(GameSettingsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) focusPairing();
  }

  void focusPairing() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ready && ModalRoute.isCurrentOf(context) != false)
        requestConsoleFocus(pairing);
    });
  }

  void controller(String input) {
    if (!ready) return;
    switch (input) {
      case 'up':
        requestConsoleFocus(pairing);
      case 'down':
        requestConsoleFocus(close);
      case 'accept':
        final target = close.hasFocus ? close : pairing;
        if (target.context case final context?)
          Actions.maybeInvoke(context, const ControllerActivateIntent());
      case 'home': // The launcher maps the physical Start/Menu button to Home.
        unawaited(m.play());
    }
  }

  @override
  void dispose() {
    pairing.dispose();
    close.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    autofocus: true,
    onKeyEvent: (_, event) {
      if (event.logicalKey != LogicalKeyboardKey.gameButtonStart)
        return KeyEventResult.ignored;
      if (event is KeyDownEvent) controller('home');
      return KeyEventResult.handled;
    },
    child: ConsoleScrollBody(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Settings overlay',
              style: TextStyle(fontSize: 38, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 10),
            Text(
              m.stopping ? m.notice : 'Game paused',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 24),
            ConsoleButton(
              focusNode: pairing,
              onPressed: widget.enabled ? m.showPairing : null,
              child: const ActionLabel(
                'Controller pairing',
                icon: Icons.sports_esports_outlined,
              ),
            ),
            const SizedBox(height: 10),
            ConsoleButton(
              focusNode: close,
              onPressed: widget.enabled ? () => m.stop() : null,
              child: const ActionLabel('Close game', icon: Icons.stop_rounded),
            ),
            const SizedBox(height: 18),
            const Text(
              'D-pad / left stick: move · A: select · Start / Esc: resume',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
