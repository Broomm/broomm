import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app_model.dart';
import 'src/catalogue.dart';
import 'src/host.dart';
import 'src/widgets/pairing_screen.dart';
import 'src/shell/controls.dart';
import 'src/shell/navigation.dart';

class BroommPrototype extends StatefulWidget {
  const BroommPrototype({super.key, required this.model, this.onReturn});
  final PrototypeModel model;
  final VoidCallback? onReturn;
  @override
  State<BroommPrototype> createState() => _BroommPrototypeState();
}

class _BroommPrototypeState extends State<BroommPrototype> {
  PrototypeModel get m => widget.model;
  final focus = FocusNode();
  final gameNodes = [
    for (final game in testGames) FocusNode(debugLabel: game.title),
  ];

  void libraryInput(String input) {
    m.libraryInput(input);
    if (m.screen == Screen.library && input != 'accept')
      requestConsoleFocus(gameNodes[m.selected]);
  }

  @override
  void initState() {
    super.initState();
    DesktopHost.channel.setMethodCallHandler((call) async {
      if (call.method == 'controller') {
        if (call.arguments == 'back' &&
            m.screen == Screen.library &&
            widget.onReturn != null)
          widget.onReturn!();
        else
          libraryInput(call.arguments as String);
      }
      if (call.method == 'closeRequested') await m.stop(close: true);
    });
  }

  @override
  void dispose() {
    focus.dispose();
    for (final node in gameNodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.escape &&
        m.screen == Screen.library &&
        widget.onReturn != null) {
      widget.onReturn!();
      return KeyEventResult.handled;
    }
    if (m.screen == Screen.library &&
        (node.hasPrimaryFocus ||
            gameNodes.contains(FocusManager.instance.primaryFocus))) {
      final action = {
        LogicalKeyboardKey.arrowLeft: 'left',
        LogicalKeyboardKey.arrowUp: 'up',
        LogicalKeyboardKey.arrowRight: 'right',
        LogicalKeyboardKey.arrowDown: 'down',
        LogicalKeyboardKey.enter: 'accept',
        LogicalKeyboardKey.gameButtonA: 'accept',
      }[k];
      if (action != null) {
        libraryInput(action);
        return KeyEventResult.handled;
      }
    } else if (k == LogicalKeyboardKey.escape) {
      if (m.screen == Screen.pairing || m.screen == Screen.loading)
        unawaited(m.stop());
      else if (m.screen == Screen.menu)
        unawaited(m.play());
      else
        unawaited(m.menu());
      return KeyEventResult.handled;
    } else if (k == LogicalKeyboardKey.enter &&
        m.screen == Screen.pairing &&
        node.hasPrimaryFocus &&
        m.canPlay) {
      unawaited(m.play());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Broomm · Controller lab',
    debugShowCheckedModeBanner: false,
    builder: (context, child) => Shortcuts(
      shortcuts: consoleShortcuts,
      child: Actions(
        actions: {
          ControllerActivateIntent: CallbackAction<ControllerActivateIntent>(
            onInvoke: (_) => activateConsoleFocus(),
          ),
        },
        child: FocusTraversalGroup(
          policy: ConsoleTraversalPolicy(),
          child: child!,
        ),
      ),
    ),
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffb4d4ff),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xff0d1420),
      textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Helvetica Neue'),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
    home: Focus(
      autofocus: true,
      focusNode: focus,
      onKeyEvent: key,
      child: ListenableBuilder(
        listenable: m,
        builder: (context, _) => Scaffold(
          backgroundColor: m.screen == Screen.menu || m.screen == Screen.pairing
              ? const Color(0xf50d1420)
              : null,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 28, 40, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text(
                        'broomm',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Text(
                        'CONTROLLER LAB',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 2,
                          color: Colors.white54,
                        ),
                      ),
                      const Spacer(),
                      if (m.screen == Screen.library && widget.onReturn != null)
                        TextButton.icon(
                          onPressed: widget.onReturn,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back to Broomm'),
                        ),
                      if (m.session.game != null)
                        Text(
                          m.session.game!.platform,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      if (m.busy) ...[
                        const SizedBox(width: 18),
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 28),
                  if (m.error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xff503b30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        m.error!,
                        style: const TextStyle(color: Color(0xffffdbb8)),
                      ),
                    ),
                  Expanded(
                    child: ConsoleScreenTransition(
                      identity: m.screen,
                      child: switch (m.screen) {
                        Screen.library => library(context),
                        Screen.loading => loading(context),
                        Screen.pairing => pairing(context),
                        Screen.menu => menu(context),
                        Screen.playing => playing(context),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget library(BuildContext context) {
    final game = testGames[m.selected];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose a game',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your supplied test ROMs',
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ConsoleScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < testGames.length; index++)
                        Builder(
                          builder: (context) {
                            final g = testGames[index];
                            final selected = m.selected == index;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 9),
                              child: ConsoleButton(
                                autofocus: index == m.selected,
                                focusNode: gameNodes[index],
                                fill: selected
                                    ? const Color(0xff263b55)
                                    : const Color(0xff151f2e),
                                onPressed: () => m.select(g),
                                onFocus: () => m.highlight(index),
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: Color(g.color),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.sports_esports_outlined,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            g.title,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${g.platform}  ·  ${g.emulator}',
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (selected)
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'D-pad / arrows: choose     A / Enter: select',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
        const SizedBox(width: 36),
        Expanded(
          flex: 4,
          child: Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(game.color).withValues(alpha: 0.6),
                  const Color(0xff111a29),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'LOCAL PROTOTYPE',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    color: Colors.white60,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.sports_esports_outlined,
                  size: 70,
                  color: Colors.white70,
                ),
                const SizedBox(height: 20),
                Text(
                  game.title,
                  style: const TextStyle(
                    fontSize: 31,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${game.emulator} · Up to ${game.players} ${game.players == 1 ? 'player' : 'players'}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Pair your controllers, then play.\nR3 + Select opens controller pairing during the game.',
                  style: TextStyle(height: 1.7, color: Colors.white70),
                ),
                const Spacer(),
                if (m.notice.isNotEmpty)
                  Text(
                    m.notice,
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget pairing(BuildContext context) => PairingScreen(model: m);

  Widget loading(BuildContext context) => ConsoleScrollBody(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 28),
          Text(
            'Loading ${m.loadingGame?.emulator ?? 'emulator'}…',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Text(
            m.loadingGame?.title ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 20),
          Text(
            m.notice,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 12),
          const Text(
            'Controller pairing will appear when the game is loaded and ready.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, height: 1.6),
          ),
          const SizedBox(height: 28),
          TextButton(
            autofocus: true,
            onPressed: m.busy ? null : () => unawaited(m.stop()),
            child: const Text('Cancel launch'),
          ),
        ],
      ),
    ),
  );

  Widget menu(BuildContext context) => ConsoleScrollBody(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.pause_circle_outline,
            size: 42,
            color: Colors.white60,
          ),
          const SizedBox(height: 24),
          const Text(
            'Game paused',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            m.session.game?.title ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 40),
          FilledButton.icon(
            autofocus: true,
            onPressed: m.busy ? null : m.showPairing,
            icon: const Icon(Icons.sports_esports_outlined),
            label: const Text('Controller pairing'),
          ),
          const SizedBox(height: 28),
          const Text(
            'Bottom face button: select     Hold Start / Esc: resume',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    ),
  );
  Widget playing(BuildContext context) => ConsoleScrollBody(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.sports_esports_outlined, size: 60),
        const SizedBox(height: 24),
        Text(m.session.game?.title ?? '', style: const TextStyle(fontSize: 28)),
        const SizedBox(height: 16),
        const Text('R3 + Select opens the menu'),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => unawaited(m.menu()),
          child: const Text('Open menu'),
        ),
      ],
    ),
  );
}
