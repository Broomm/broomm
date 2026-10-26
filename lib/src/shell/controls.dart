import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'navigation.dart';
import 'keyboard.dart';
export 'keyboard.dart' show ConsoleKeyboardHost;
export 'navigation.dart' show ControllerDirectionIntent;

const ink = Color(0xffedf4fa),
    muted = Color(0xff9aa9ba),
    accent = Color(0xffbef1e0),
    surface = Color(0xff141e2b);

class ConsoleButton extends StatefulWidget {
  const ConsoleButton({
    super.key,
    required this.child,
    this.onPressed,
    this.onFocus,
    this.onHover,
    this.autofocus = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
    this.fill = surface,
    this.radius = 14,
    this.label,
    this.focusNode,
    this.order,
  });
  final Widget child;
  final FutureOr<void> Function()? onPressed;
  final VoidCallback? onFocus;
  final VoidCallback? onHover;
  final bool autofocus;
  final EdgeInsetsGeometry padding;
  final Color fill;
  final double radius;
  final String? label;
  final FocusNode? focusNode;
  final double? order;
  @override
  State<ConsoleButton> createState() => _ConsoleButtonState();
}

class _ConsoleButtonState extends State<ConsoleButton> {
  final ownedNode = FocusNode();
  FocusNode get node => widget.focusNode ?? ownedNode;
  bool focused = false, hovered = false, pressing = false;
  @override
  void dispose() {
    ownedNode.dispose();
    super.dispose();
  }

  Future<void> _press() async {
    if (widget.onPressed != null && !pressing) {
      node.requestFocus();
      pressing = true;
      final scope = node.nearestScope;
      var moved = false;
      void recordFocus() {
        final current = FocusManager.instance.primaryFocus;
        if (current != null && current != node && current is! FocusScopeNode)
          moved = true;
      }

      FocusManager.instance.addListener(recordFocus);
      try {
        await widget.onPressed!();
      } finally {
        pressing = false;
        FocusManager.instance.removeListener(recordFocus);
        // Busy controls temporarily leave traversal. Recover their focus only
        // when no newer control or modal has taken ownership in the meantime.
        if (mounted && !moved && !node.hasFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                widget.onPressed != null &&
                node.canRequestFocus &&
                FocusManager.instance.primaryFocus == scope &&
                ModalRoute.of(context)?.isCurrent == true)
              requestConsoleFocus(node);
          });
          WidgetsBinding.instance.ensureVisualUpdate();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.order == null
      ? button(context)
      : FocusTraversalOrder(
          order: NumericFocusOrder(widget.order!),
          child: button(context),
        );
  Widget button(BuildContext context) => Semantics(
    button: true,
    enabled: widget.onPressed != null,
    label: widget.label,
    child: FocusableActionDetector(
      focusNode: node,
      autofocus: widget.autofocus,
      enabled: widget.onPressed != null,
      actions: {
        ControllerActivateIntent: CallbackAction<ControllerActivateIntent>(
          onInvoke: (_) {
            _press();
            return null;
          },
        ),
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _press();
            return null;
          },
        ),
      },
      onFocusChange: (value) {
        setState(() => focused = value);
        if (value) {
          widget.onFocus?.call();
          revealConsoleFocus(node);
        }
      },
      mouseCursor: widget.onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onShowHoverHighlight: (v) {
        setState(() => hovered = v);
        if (v) widget.onHover?.call();
      },
      child: GestureDetector(
        onTap: widget.onPressed == null ? null : _press,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: motionDuration(context, const Duration(milliseconds: 140)),
          curve: consoleCurve,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: focused
                ? Color.alphaBlend(
                    Colors.white.withValues(alpha: .07),
                    widget.fill,
                  )
                : widget.fill,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: focused
                  ? ink
                  : hovered
                  ? Colors.white38
                  : Colors.white.withValues(alpha: .09),
              width: 2,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: .12),
                      blurRadius: 25,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Opacity(
            opacity: widget.onPressed == null ? .45 : 1,
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

class ActionLabel extends StatelessWidget {
  const ActionLabel(this.text, {super.key, this.icon, this.trailing});
  final String text;
  final IconData? icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 12)],
      Flexible(
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      if (trailing != null) ...[const SizedBox(width: 16), trailing!],
    ],
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = accent});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: color,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.3,
    ),
  );
}

class ProblemNotice extends StatelessWidget {
  const ProblemNotice(this.message, {super.key, this.retry});
  final String message;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xff302b29),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: Color(0xffefd3aa)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xffefd3aa)),
          ),
        ),
        if (retry != null) ...[
          const SizedBox(width: 12),
          ConsoleButton(onPressed: retry, child: const Text('Retry')),
        ],
      ],
    ),
  );
}

class ConsoleField extends StatefulWidget {
  const ConsoleField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint = '',
    this.secret = false,
    this.autofocus = false,
    this.onSubmitted,
    this.maxLength = 256,
    this.controllerRequest = 0,
  });
  final String label, value, hint;
  final bool secret, autofocus;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLength;
  final int controllerRequest;
  @override
  State<ConsoleField> createState() => _ConsoleFieldState();
}

class _FinishEditingIntent extends Intent {
  const _FinishEditingIntent();
}

class _ConsoleFieldState extends State<ConsoleField> {
  late final text = TextEditingController(text: widget.value);
  final navigation = FocusNode();
  final editor = FocusNode(skipTraversal: true);
  bool opening = false, editing = false, focused = false;
  bool revealed = false;
  final visibility = FocusNode(debugLabel: 'Password visibility');
  int _keyboardSerial = 0;
  VoidCallback? _dismissKeyboard;

  @override
  void initState() {
    super.initState();
    if (widget.controllerRequest > 0)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openKeyboard();
      });
    editor.addListener(() {
      if (!editor.hasFocus && editing && mounted)
        setState(() => editing = false);
    });
  }

  @override
  void didUpdateWidget(ConsoleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controllerRequest > oldWidget.controllerRequest)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openKeyboard();
      });
    if (widget.value != text.text) {
      text.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    ++_keyboardSerial;
    _dismissKeyboard?.call();
    text.dispose();
    editor.dispose();
    navigation.dispose();
    visibility.dispose();
    super.dispose();
  }

  void beginEditing() {
    if (opening) {
      ++_keyboardSerial;
      ConsoleKeyboardHost.dismiss(context, text);
      opening = false;
    }
    if (editing) return;
    setState(() => editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && editing) editor.requestFocus();
    });
  }

  void finishEditing() {
    setState(() => editing = false);
    requestConsoleFocus(navigation);
  }

  Future<void> openKeyboard() async {
    if (opening) return;
    opening = true;
    if (editing) finishEditing();
    setState(() {});
    final serial = ++_keyboardSerial;
    _dismissKeyboard = ConsoleKeyboardHost.dismissal(context, text);
    final submit = await ConsoleKeyboardHost.edit(
      context,
      text,
      onChanged: widget.onChanged,
      maxLength: widget.maxLength,
      editor: editor,
    );
    if (!mounted || serial != _keyboardSerial) return;
    setState(() => opening = false);
    requestConsoleFocus(navigation);
    if (submit) widget.onSubmitted?.call(text.text);
  }

  @override
  Widget build(BuildContext context) => ConsoleFocusRegion(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 8),
        Actions(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                beginEditing();
                return null;
              },
            ),
            ControllerActivateIntent: CallbackAction<ControllerActivateIntent>(
              onInvoke: (_) {
                openKeyboard();
                return null;
              },
            ),
            _FinishEditingIntent: CallbackAction<_FinishEditingIntent>(
              onInvoke: (_) {
                finishEditing();
                return null;
              },
            ),
            ControllerDirectionIntent:
                CallbackAction<ControllerDirectionIntent>(
                  onInvoke: (intent) {
                    if (editing) finishEditing();
                    navigation.focusInDirection(intent.direction);
                    return null;
                  },
                ),
            if (editing)
              BackIntent: CallbackAction<BackIntent>(
                onInvoke: (_) {
                  finishEditing();
                  return null;
                },
              ),
          },
          child: Focus(
            focusNode: navigation,
            autofocus: widget.autofocus,
            skipTraversal: editing,
            onFocusChange: (value) {
              setState(() => focused = value);
              if (value) revealConsoleFocus(navigation);
            },
            child: DefaultTextEditingShortcuts(
              child: Shortcuts(
                shortcuts: editing
                    ? {
                        const SingleActivator(LogicalKeyboardKey.escape):
                            const _FinishEditingIntent(),
                        const SingleActivator(LogicalKeyboardKey.gameButtonB):
                            const _FinishEditingIntent(),
                      }
                    : const {},
                child: TextField(
                  key: ValueKey('field-${widget.label}'),
                  controller: text,
                  focusNode: editor,
                  canRequestFocus: editing || opening,
                  readOnly: !editing,
                  showCursor: editing || opening,
                  enableInteractiveSelection: editing,
                  obscureText: widget.secret && !revealed,
                  autocorrect: false,
                  enableSuggestions: !widget.secret,
                  maxLength: widget.maxLength,
                  onTap: beginEditing,
                  onChanged: widget.onChanged,
                  onSubmitted: (value) {
                    widget.onSubmitted?.call(value);
                    finishEditing();
                  },
                  decoration: InputDecoration(
                    suffixIcon: widget.secret
                        ? Actions(
                            actions: {
                              ControllerActivateIntent:
                                  CallbackAction<ControllerActivateIntent>(
                                    onInvoke: (_) {
                                      setState(() => revealed = !revealed);
                                      return null;
                                    },
                                  ),
                            },
                            child: IconButton(
                              focusNode: visibility,
                              tooltip: revealed
                                  ? 'Hide password'
                                  : 'Show password',
                              onPressed: () =>
                                  setState(() => revealed = !revealed),
                              icon: Icon(
                                revealed
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          )
                        : null,
                    hintText: widget.hint,
                    counterText: '',
                    enabledBorder: focused
                        ? OutlineInputBorder(
                            borderSide: const BorderSide(color: ink, width: 2),
                            borderRadius: BorderRadius.circular(4),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class BackIntent extends Intent {
  const BackIntent();
}

// Controller actions carry their origin explicitly. A later pointer click or
// physical-keyboard focus must never inherit a previous controller's modality.
class ControllerActivateIntent extends Intent {
  const ControllerActivateIntent();
}

// Standard Flutter controls (for example password visibility and pairing chips)
// use ActivateIntent. Fields and ConsoleButtons override controller activation
// locally, keeping controller text entry distinct from inline editing.
Object? activateConsoleFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context == null
      ? null
      : Actions.maybeInvoke(context, const ActivateIntent());
}

class HomeIntent extends Intent {
  const HomeIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class PlayGameIntent extends Intent {
  const PlayGameIntent(this.id);
  final int id;
}

class GameOptionsIntent extends Intent {
  const GameOptionsIntent();
}

Future<void> requestPlay(BuildContext context, int id) async {
  final result = Actions.maybeInvoke(context, PlayGameIntent(id));
  if (result is Future) await result;
}

final consoleShortcuts = <ShortcutActivator, Intent>{
  const SingleActivator(
    LogicalKeyboardKey.gameButtonSelect,
    includeRepeats: false,
  ): const GameOptionsIntent(),
  const SingleActivator(LogicalKeyboardKey.contextMenu, includeRepeats: false):
      const GameOptionsIntent(),
  const SingleActivator(
    LogicalKeyboardKey.f10,
    shift: true,
    includeRepeats: false,
  ): const GameOptionsIntent(),
  const SingleActivator(LogicalKeyboardKey.arrowUp):
      const DirectionalFocusIntent(TraversalDirection.up),
  const SingleActivator(LogicalKeyboardKey.arrowDown):
      const DirectionalFocusIntent(TraversalDirection.down),
  const SingleActivator(LogicalKeyboardKey.arrowLeft):
      const DirectionalFocusIntent(TraversalDirection.left),
  const SingleActivator(LogicalKeyboardKey.arrowRight):
      const DirectionalFocusIntent(TraversalDirection.right),
  const SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
      const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.numpadEnter, includeRepeats: false):
      const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.gameButtonA, includeRepeats: false):
      const ControllerActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.gameButtonB, includeRepeats: false):
      const BackIntent(),
  const SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false):
      const BackIntent(),
  const SingleActivator(LogicalKeyboardKey.home, includeRepeats: false):
      const HomeIntent(),
  const SingleActivator(LogicalKeyboardKey.gameButtonX, includeRepeats: false):
      const SearchIntent(),
  // Consume repeats locally so an ancestor's default Enter/activation shortcut
  // cannot activate the next screen while the opening key is still held.
  for (final key in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.gameButtonB,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.gameButtonX,
    LogicalKeyboardKey.gameButtonSelect,
    LogicalKeyboardKey.contextMenu,
  ])
    SingleActivator(key): const DoNothingIntent(),
};
