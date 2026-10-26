import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controls.dart';
import 'navigation.dart';

class ConsoleKeyboardHost extends StatefulWidget {
  const ConsoleKeyboardHost({super.key, required this.child});
  final Widget child;

  /// Native gamepad actions share the dock's command handling with Flutter
  /// game-key events. Outside the active dock they retain ordinary navigation.
  static bool controller(BuildContext context, String action) =>
      context.getInheritedWidgetOfExactType<_KeyboardScope>()?.host.controller(
        action,
      ) ??
      false;
  static Future<bool> edit(
    BuildContext context,
    TextEditingController text, {
    required ValueChanged<String> onChanged,
    required int maxLength,
    required FocusNode editor,
  }) => context.dependOnInheritedWidgetOfExactType<_KeyboardScope>()!.host.open(
    text,
    onChanged,
    maxLength,
    context,
    editor,
  );
  static VoidCallback dismissal(
    BuildContext context,
    TextEditingController text,
  ) {
    final host = context
        .dependOnInheritedWidgetOfExactType<_KeyboardScope>()!
        .host;
    return () {
      if (identical(host.text, text)) host.close(defer: true);
    };
  }

  static void dismiss(BuildContext context, TextEditingController text) {
    final host = context
        .dependOnInheritedWidgetOfExactType<_KeyboardScope>()
        ?.host;
    if (host != null && identical(host.text, text)) host.close();
  }

  @override
  State<ConsoleKeyboardHost> createState() => _KeyboardHostState();
}

class _KeyboardScope extends InheritedWidget {
  const _KeyboardScope({required this.host, required super.child});
  final _KeyboardHostState host;
  @override
  bool updateShouldNotify(_KeyboardScope old) => false;
}

class _KeyboardHostState extends State<ConsoleKeyboardHost>
    with WidgetsBindingObserver {
  TextEditingController? text;
  ValueChanged<String>? changed;
  int maxLength = 256;
  FocusNode? editor;
  Completer<bool>? done;
  final _keyboardKey = GlobalKey<_SteamKeyboardState>();
  final focus = FocusScopeNode(debugLabel: 'On-screen keyboard');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed)
      _keyboardKey.currentState?.holdShift(false);
  }

  bool controller(String action) {
    if (text == null) return false;
    final keys = _keyboardKey.currentState;
    if (keys == null) return false;
    if (action == 'shift-up') {
      keys.holdShift(false);
      return true;
    }
    if (!focus.hasFocus) return false;
    switch (action) {
      case 'space':
        keys.insert(' ');
      case 'search':
        keys.erase();
      case 'caps':
        keys.toggleCaps();
      case 'shift-down':
        keys.holdShift(true);
      case 'shift-up':
        keys.holdShift(false);
      case 'caret-left':
        keys.caret(-1);
      case 'caret-right':
        keys.caret(1);
      case 'home':
      case 'keyboard-enter':
        close(submit: true);
      default:
        return false;
    }
    return true;
  }

  KeyEventResult gameKey(FocusNode _, KeyEvent event) {
    final button = event.logicalKey;
    final action = button == LogicalKeyboardKey.gameButtonLeft2
        ? (event is KeyUpEvent ? 'shift-up' : 'shift-down')
        : {
            LogicalKeyboardKey.gameButtonY: 'space',
            LogicalKeyboardKey.gameButtonX: 'search',
            LogicalKeyboardKey.gameButtonThumbLeft: 'caps',
            LogicalKeyboardKey.gameButtonLeft1: 'caret-left',
            LogicalKeyboardKey.gameButtonRight1: 'caret-right',
            LogicalKeyboardKey.gameButtonStart: 'home',
            LogicalKeyboardKey.gameButtonRight2: 'keyboard-enter',
          }[button];
    if (action == null ||
        text == null ||
        !focus.hasFocus && action != 'shift-up')
      return KeyEventResult.ignored;
    if (event is KeyDownEvent || button == LogicalKeyboardKey.gameButtonLeft2)
      controller(action);
    return KeyEventResult.handled;
  }

  Future<bool> open(
    TextEditingController value,
    ValueChanged<String> onChanged,
    int limit,
    BuildContext anchor,
    FocusNode editorNode,
  ) {
    close();
    final complete = Completer<bool>();
    setState(() {
      text = value;
      changed = onChanged;
      maxLength = limit;
      editor = editorNode;
      done = complete;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(text, value) && anchor.mounted)
        Scrollable.ensureVisible(
          anchor,
          alignment: .35,
          duration: motionDuration(anchor),
          curve: consoleCurve,
        );
    });
    return complete.future;
  }

  void close({bool submit = false, bool defer = false}) {
    if (done == null) return;
    _keyboardKey.currentState?.holdShift(false);
    final current = done!;
    done = null;
    final owner = text;
    if (defer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(text, owner) && done == null)
          setState(() => text = null);
      });
    } else if (mounted)
      setState(() => text = null);
    current.complete(submit);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    done?.complete(false);
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _KeyboardScope(
    host: this,
    child: Focus(
      canRequestFocus: false,
      onKeyEvent: gameKey,
      child: Actions(
        actions: text == null
            ? {}
            : {
                BackIntent: CallbackAction<BackIntent>(
                  onInvoke: (_) {
                    close();
                    return null;
                  },
                ),
                SearchIntent: CallbackAction<SearchIntent>(
                  onInvoke: (_) {
                    if (focus.hasFocus) _keyboardKey.currentState?.erase();
                    return null;
                  },
                ),
              },
        child: Column(
          children: [
            Expanded(child: widget.child),
            if (text != null)
              SizedBox(
                height: math.min(MediaQuery.sizeOf(context).height * .43, 300),
                child: Material(
                  color: const Color(0xff0b141f),
                  elevation: 24,
                  child: FocusScope(
                    node: focus,
                    parentNode: editor,
                    child: Shortcuts(
                      shortcuts: consoleShortcuts,
                      child: Actions(
                        actions: {
                          BackIntent: CallbackAction<BackIntent>(
                            onInvoke: (_) {
                              close();
                              return null;
                            },
                          ),
                          SearchIntent: CallbackAction<SearchIntent>(
                            onInvoke: (_) {
                              if (focus.hasFocus)
                                _keyboardKey.currentState?.erase();
                              return null;
                            },
                          ),
                          ControllerActivateIntent:
                              CallbackAction<ControllerActivateIntent>(
                                onInvoke: (_) => activateConsoleFocus(),
                              ),
                          ControllerDirectionIntent:
                              CallbackAction<ControllerDirectionIntent>(
                                onInvoke: (i) {
                                  FocusManager.instance.primaryFocus
                                      ?.focusInDirection(i.direction);
                                  return null;
                                },
                              ),
                        },
                        child: _SteamKeyboard(
                          key: _keyboardKey,
                          text: text!,
                          changed: changed!,
                          maxLength: maxLength,
                          close: () => close(submit: true),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _SteamKeyboard extends StatefulWidget {
  const _SteamKeyboard({
    super.key,
    required this.text,
    required this.changed,
    required this.maxLength,
    required this.close,
  });
  final TextEditingController text;
  final ValueChanged<String> changed;
  final int maxLength;
  final VoidCallback close;
  @override
  State<_SteamKeyboard> createState() => _SteamKeyboardState();
}

class _SteamKeyboardState extends State<_SteamKeyboard> {
  bool shift = false, caps = false, heldShift = false;
  bool get shifted => shift || heldShift;
  void holdShift(bool value) {
    if (heldShift != value) setState(() => heldShift = value);
  }

  void toggleCaps() => setState(() => caps = !caps);
  void insert(String value) {
    final t = widget.text, s = t.selection;
    final start = s.isValid ? s.start : t.text.length,
        end = s.isValid ? s.end : t.text.length;
    final result = t.text.replaceRange(start, end, value);
    if (result.characters.length > widget.maxLength) return;
    t.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    widget.changed(result);
    if (shift && value.isNotEmpty) setState(() => shift = false);
  }

  void erase() {
    final t = widget.text, s = t.selection;
    var start = s.isValid ? s.start : t.text.length;
    final end = s.isValid ? s.end : start;
    if (start == end && start > 0)
      start -= t.text.substring(0, start).characters.last.length;
    t.selection = TextSelection(baseOffset: start, extentOffset: end);
    insert('');
  }

  void caret(int direction) {
    final t = widget.text;
    final offset = t.selection.isValid
        ? t.selection.extentOffset
        : t.text.length;
    final left = t.text.substring(0, offset), right = t.text.substring(offset);
    final next = direction < 0
        ? offset - (left.isEmpty ? 0 : left.characters.last.length)
        : offset + (right.isEmpty ? 0 : right.characters.first.length);
    t.selection = TextSelection.collapsed(offset: next);
  }

  Widget key(
    String label,
    VoidCallback action, {
    int flex = 2,
    bool first = false,
    String? secondary,
    IconData? icon,
    String? hint,
  }) => Expanded(
    flex: flex,
    child: Padding(
      padding: const EdgeInsets.all(2),
      child: ConsoleButton(
        label: label == ' ' ? 'Space' : label,
        autofocus: first,
        radius: 5,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        onPressed: action,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hint != null) ...[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .12),
                      border: Border.all(color: accent.withValues(alpha: .5)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        hint,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                icon != null
                    ? Icon(icon, size: 22)
                    : Text(
                        secondary == null
                            ? (label == ' ' ? 'Space' : label)
                            : '$secondary\n$label',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: secondary == null ? 15 : 12,
                          height: 1.15,
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final upper = shifted != caps;
    String glyph(String ch) {
      const plain = "[]\\;',./", shifted = "{}|:\"<>?";
      final pos = plain.indexOf(ch);
      return pos >= 0
          ? (this.shifted ? shifted[pos] : ch)
          : (upper ? ch.toUpperCase() : ch);
    }

    Widget letters(String row) => Row(
      children: [
        for (final ch in row.characters)
          key(glyph(ch), () => insert(glyph(ch))),
      ],
    );
    return FocusTraversalGroup(
      policy: ConsoleTraversalPolicy(),
      child: Padding(
        key: const ValueKey('console-keyboard'),
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (var i = 0; i < 13; i++)
                    key(
                      (shifted ? '~!@#\$%^&*()_+' : '`1234567890-=')[i],
                      () => insert(
                        (shifted ? '~!@#\$%^&*()_+' : '`1234567890-=')[i],
                      ),
                      first: i == 1,
                      secondary: shifted ? null : '~!@#\$%^&*()_+'[i],
                    ),
                  key(
                    'Backspace',
                    erase,
                    flex: 4,
                    icon: Icons.backspace_outlined,
                    hint: 'X',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  key('Tab', () => insert('    '), flex: 3),
                  Expanded(flex: 24, child: letters('qwertyuiop[]\\')),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  key(
                    caps ? 'Caps ●' : 'Caps',
                    toggleCaps,
                    flex: 4,
                    hint: 'L3',
                  ),
                  Expanded(flex: 22, child: letters("asdfghjkl;'")),
                  key('Enter', widget.close, flex: 4, hint: 'R2'),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  key(
                    shifted ? 'Shift ●' : 'Shift',
                    () => setState(() => shift = !shift),
                    flex: 5,
                    hint: 'Hold L2',
                  ),
                  Expanded(flex: 20, child: letters('zxcvbnm,./')),
                  key(
                    'Shift',
                    () => setState(() => shift = !shift),
                    flex: 5,
                    hint: 'Hold L2',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  const Spacer(flex: 3),
                  key(' ', () => insert(' '), flex: 17, hint: 'Y'),
                  key(
                    'Move cursor left',
                    () => caret(-1),
                    icon: Icons.arrow_left_rounded,
                    hint: 'L1',
                  ),
                  key(
                    'Move cursor right',
                    () => caret(1),
                    icon: Icons.arrow_right_rounded,
                    hint: 'R1',
                  ),
                  key('Paste', () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (mounted && data?.text != null) insert(data!.text!);
                  }, flex: 4),
                  key('Done', widget.close, flex: 4, hint: 'Start'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
