import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

const consoleMotion = Duration(milliseconds: 180);
const consoleCurve = Curves.easeOutCubic;

class ControllerDirectionIntent extends Intent {
  const ControllerDirectionIntent(this.direction);
  final TraversalDirection direction;
}

Future<T?> showConsoleDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: barrierDismissible,
  animationStyle: AnimationStyle(
    duration: motionDuration(context),
    reverseDuration: motionDuration(context),
    curve: consoleCurve,
    reverseCurve: consoleCurve,
  ),
);

class ConsolePageTransitionsBuilder extends PageTransitionsBuilder {
  const ConsolePageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = animation.drive(CurveTween(curve: consoleCurve));
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(.025, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

Duration motionDuration(
  BuildContext context, [
  Duration duration = consoleMotion,
]) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// Traversal must not perform Flutter's default instant scroll before the
/// focused control has a chance to reveal itself with motion.
class ConsoleTraversalPolicy extends ReadingOrderTraversalPolicy {
  ConsoleTraversalPolicy() : super(requestFocusCallback: requestConsoleFocus);
}

void requestConsoleFocus(
  FocusNode node, {
  ScrollPositionAlignmentPolicy? alignmentPolicy,
  double? alignment,
  Duration? duration,
  Curve? curve,
}) {
  node.requestFocus();
  revealConsoleFocus(node);
}

/// The visual unit belonging to its descendant controls (a card, or a field
/// including its label). Lazy viewports also declare their actual end rows here;
/// the last mounted grid child is not necessarily the end of the collection.
class ConsoleFocusRegion extends InheritedWidget {
  const ConsoleFocusRegion({
    super.key,
    required super.child,
    this.axis = Axis.vertical,
    this.leading = false,
    this.trailing = false,
  });
  final Axis axis;
  final bool leading, trailing;

  @override
  bool updateShouldNotify(ConsoleFocusRegion oldWidget) =>
      axis != oldWidget.axis ||
      leading != oldWidget.leading ||
      trailing != oldWidget.trailing;
}

/// An eager scroll view knows all its controls, including those offscreen. The
/// first/last visual row can therefore reveal the page's heading/footer as well
/// as the focused control. Nested scroll views own their edges independently.
class ConsoleScrollView extends SingleChildScrollView {
  const ConsoleScrollView({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.padding,
    super.primary,
    super.physics,
    super.controller,
    this.centerZone,
    required super.child,
  });
  final double? centerZone;

  @override
  Widget build(BuildContext context) =>
      _ConsoleScrollEdges(centerZone: centerZone, child: super.build(context));
}

class _ConsoleScrollEdges extends StatefulWidget {
  const _ConsoleScrollEdges({required this.child, this.centerZone});
  final Widget child;
  final double? centerZone;
  @override
  State<_ConsoleScrollEdges> createState() => _ConsoleScrollEdgesState();
}

class _ConsoleScrollEdgesState extends State<_ConsoleScrollEdges> {
  final focus = FocusNode(canRequestFocus: false, skipTraversal: true);
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ScrollEdgesScope(
    state: this,
    child: Focus(focusNode: focus, child: widget.child),
  );
}

class _ScrollEdgesScope extends InheritedWidget {
  const _ScrollEdgesScope({required this.state, required super.child});
  final _ConsoleScrollEdgesState state;
  @override
  bool updateShouldNotify(_ScrollEdgesScope oldWidget) => false;
}

_ConsoleScrollEdgesState? _edgesFor(ScrollableState scrollable) {
  _ConsoleScrollEdgesState? result;
  scrollable.context.visitAncestorElements((element) {
    if (element.widget is Scrollable) return false;
    if (element.widget case _ScrollEdgesScope scope) {
      result = scope.state;
      return false;
    }
    return true;
  });
  return result;
}

final _pendingReveals = <FocusNode>{};

/// Reveal the whole visual unit when it fits, otherwise keep the active control
/// visible. Edge snapping is bounded by that visibility requirement: a long
/// noninteractive footer must never push the selected card offscreen.
void revealConsoleFocus(FocusNode node) {
  if (!_pendingReveals.add(node)) return;
  if (node.context case final context? when node.canRequestFocus) {
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      final position = scrollable.position;
      if (position.hasPixels && position.isScrollingNotifier.value)
        position.jumpTo(position.pixels);
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _pendingReveals.remove(node);
    final context = node.context;
    if (context == null || !context.mounted || !node.hasFocus) return;
    final target = context.findRenderObject();
    if (target == null || !target.attached) return;
    final duration = motionDuration(context);
    var currentContext = context;
    var scrollable = Scrollable.maybeOf(currentContext);
    while (scrollable != null) {
      final object = currentContext.findRenderObject()!;
      final viewport = RenderAbstractViewport.maybeOf(object);
      final position = scrollable.position;
      if (viewport != null && position.hasContentDimensions) {
        var rect = MatrixUtils.transformRect(
          target.getTransformTo(object),
          target.paintBounds,
        ).intersect(object.paintBounds).inflate(12);
        var leading = false, trailing = false;
        // Regions inside a nested viewport belong to that viewport only. For an
        // outer page use its visible viewport bounds, not the inner scroll's
        // potentially very long contents.
        context.visitAncestorElements((element) {
          if (element == scrollable!.context) return false;
          if (element.widget case ConsoleFocusRegion region
              when region.axis == position.axis &&
                  Scrollable.maybeOf(element) == scrollable) {
            leading |= region.leading;
            trailing |= region.trailing;
            final regionObject = element.findRenderObject();
            if (regionObject != null && regionObject.attached) {
              final bounds = MatrixUtils.transformRect(
                regionObject.getTransformTo(object),
                regionObject.paintBounds,
              );
              final extent = position.axis == Axis.vertical
                  ? bounds.height
                  : bounds.width;
              if (extent <= position.viewportDimension)
                rect = extent + 24 <= position.viewportDimension
                    ? bounds.inflate(12)
                    : bounds;
            }
          }
          return true;
        });
        if (_edgesFor(scrollable) case final edges?) {
          final selected = node.rect;
          final vertical = position.axis == Axis.vertical;
          final before = vertical ? selected.top : selected.left;
          final after = vertical ? selected.bottom : selected.right;
          var first = true, last = true;
          for (final other in edges.focus.traversalDescendants) {
            if (other == node ||
                other.context == null ||
                Scrollable.maybeOf(other.context!, axis: position.axis) !=
                    scrollable)
              continue;
            final bounds = other.rect;
            if ((vertical ? bounds.bottom : bounds.right) <= before + .5)
              first = false;
            if ((vertical ? bounds.top : bounds.left) >= after - .5)
              last = false;
          }
          final reversed = axisDirectionIsReversed(position.axisDirection);
          leading |= reversed ? last : first;
          trailing |= reversed ? first : last;
        }
        final start = viewport
            .getOffsetToReveal(object, 0, rect: rect, axis: position.axis)
            .offset;
        final end = viewport
            .getOffsetToReveal(object, 1, rect: rect, axis: position.axis)
            .offset;
        var desired = leading
            ? position.minScrollExtent
            : trailing
            ? position.maxScrollExtent
            : position.pixels;
        if (_edgesFor(scrollable)?.widget.centerZone case final zone?) {
          final center = (start + end) / 2;
          final radius = position.viewportDimension * zone / 2;
          desired = position.pixels
              .clamp(center - radius, center + radius)
              .toDouble();
        }
        final offset = desired
            .clamp(math.min(start, end), math.max(start, end))
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        if ((offset - position.pixels).abs() > .5) {
          if (duration == Duration.zero) {
            position.jumpTo(offset);
          } else {
            unawaited(
              position.animateTo(
                offset,
                duration: duration,
                curve: consoleCurve,
              ),
            );
          }
        } else if (position.isScrollingNotifier.value ||
            offset != position.pixels) {
          // A newer, already-visible selection must stop a previous reveal
          // animation before it can carry that selection out of the viewport.
          position.jumpTo(offset);
        }
      }
      currentContext = scrollable.context;
      scrollable = Scrollable.maybeOf(currentContext);
    }
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}

/// Keyboard arrows and native controller directions use the same local graph.
/// Text editors retain their own keyboard shortcuts inside this boundary.
class ConsoleDirections extends StatelessWidget {
  const ConsoleDirections({
    super.key,
    required this.onDirection,
    required this.child,
  });
  final bool Function(TraversalDirection) onDirection;
  final Widget child;

  void move(TraversalDirection direction) {
    if (!onDirection(direction)) {
      FocusManager.instance.primaryFocus?.focusInDirection(direction);
    }
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
        onInvoke: (intent) => move(intent.direction),
      ),
      ControllerDirectionIntent: CallbackAction<ControllerDirectionIntent>(
        onInvoke: (intent) => move(intent.direction),
      ),
    },
    child: child,
  );
}

/// Center short status/menu content while keeping its actions reachable in a
/// resized window or when accessibility text increases the content height.
class ConsoleScrollBody extends StatelessWidget {
  const ConsoleScrollBody({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ConsoleScrollView(
      padding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: math.max(0, constraints.maxHeight - 24),
        ),
        child: Center(child: child),
      ),
    ),
  );
}

/// Only the current screen owns focus and handles input during the entrance
/// animation. Background workflows retain their existing cancellation rules.
class ConsoleScreenTransition extends StatefulWidget {
  const ConsoleScreenTransition({
    super.key,
    required this.identity,
    required this.child,
  });
  final Object identity;
  final Widget child;
  @override
  State<ConsoleScreenTransition> createState() =>
      _ConsoleScreenTransitionState();
}

class _ConsoleScreenTransitionState extends State<ConsoleScreenTransition>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    value: 1,
    duration: consoleMotion,
  );
  late final animation = CurvedAnimation(
    parent: controller,
    curve: consoleCurve,
  );

  @override
  void didUpdateWidget(ConsoleScreenTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.identity != oldWidget.identity) {
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.value = 1;
      } else {
        controller.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) controller.value = 1;
  }

  @override
  void dispose() {
    animation.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, .018),
        end: Offset.zero,
      ).animate(animation),
      child: KeyedSubtree(key: ValueKey(widget.identity), child: widget.child),
    ),
  );
}
