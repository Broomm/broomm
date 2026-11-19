import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'focus_motion.dart';

/// One foreground layer shared by the navigator, dialogs and controller dock.
/// It only paints: focus, hit testing and control layout stay with the children.
class ConsoleFocusOverlay extends StatefulWidget {
  const ConsoleFocusOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<ConsoleFocusOverlay> createState() => _ConsoleFocusOverlayState();
}

class _ConsoleFocusOverlayState extends State<ConsoleFocusOverlay>
    with WidgetsBindingObserver {
  final _registry = _OutlineRegistry();
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _visible =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    // Hidden apps may not receive another frame to apply a widget update.
    // Stop the clock at the lifecycle boundary, before asking for a rebuild.
    if (!visible) _registry.layer?.animate = false;
    if (_visible != visible) setState(() => _visible = visible);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _OutlineScope(
    registry: _registry,
    child: _OutlineLayer(
      registry: _registry,
      animate:
          _visible &&
          !MediaQuery.disableAnimationsOf(context) &&
          TickerMode.valuesOf(context).enabled,
      child: RepaintBoundary(child: widget.child),
    ),
  );
}

class ConsoleFocusOutline extends StatelessWidget {
  const ConsoleFocusOutline({
    super.key,
    required this.focused,
    required this.radius,
    required this.child,
  });
  final bool focused;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final registry = context
        .dependOnInheritedWidgetOfExactType<_OutlineScope>()
        ?.registry;
    if (registry == null) {
      // A standalone control outside the app shell still has a foreground ring.
      return _StandaloneOutline(focused: focused, radius: radius, child: child);
    }
    return _OutlineTarget(
      registry: registry,
      focused: focused,
      radius: radius,
      child: child,
    );
  }
}

class _OutlineScope extends InheritedWidget {
  const _OutlineScope({required this.registry, required super.child});
  final _OutlineRegistry registry;
  @override
  bool updateShouldNotify(_OutlineScope oldWidget) =>
      registry != oldWidget.registry;
}

class _OutlineRegistry {
  final targets = <_RenderOutlineTarget>{};
  _RenderOutlineLayer? layer;

  void focus(_RenderOutlineTarget target, bool focused) {
    targets.remove(target);
    if (focused) targets.add(target);
    layer?.markNeedsPaint();
  }
}

class _OutlineTarget extends SingleChildRenderObjectWidget {
  const _OutlineTarget({
    required this.registry,
    required this.focused,
    required this.radius,
    required super.child,
  });
  final _OutlineRegistry registry;
  final bool focused;
  final double radius;

  @override
  _RenderOutlineTarget createRenderObject(BuildContext context) =>
      _RenderOutlineTarget(registry, focused, radius);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOutlineTarget renderObject,
  ) {
    renderObject.update(registry, focused, radius);
  }
}

class _RenderOutlineTarget extends RenderProxyBox {
  _RenderOutlineTarget(this.registry, this.focused, this.radius);
  _OutlineRegistry registry;
  bool focused;
  double radius;

  void update(_OutlineRegistry next, bool focus, double rounding) {
    if (registry != next || focused != focus) {
      if (attached) registry.focus(this, false);
      registry = next;
      focused = focus;
      if (attached) registry.focus(this, focused);
    }
    if (radius != rounding) {
      radius = rounding;
      registry.layer?.markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (focused) registry.focus(this, true);
  }

  @override
  void detach() {
    registry.focus(this, false);
    super.detach();
  }

  FocusRing? geometry(_RenderOutlineLayer layer, {bool visibleOnly = true}) {
    if (!attached || !hasSize || size.isEmpty) return null;
    RenderObject node = this;
    while (node != layer) {
      final parent = node.parent;
      if (parent == null || (visibleOnly && !parent.paintsChild(node)))
        return null;
      node = parent;
    }
    final transform = getTransformTo(layer);
    final bounds = MatrixUtils.transformRect(transform, Offset.zero & size);
    final origin = MatrixUtils.transformPoint(transform, Offset.zero);
    final scale = math.max(
      (MatrixUtils.transformPoint(transform, const Offset(1, 0)) - origin)
          .distance,
      (MatrixUtils.transformPoint(transform, const Offset(0, 1)) - origin)
          .distance,
    );
    if (!bounds.isFinite || bounds.isEmpty || !scale.isFinite || scale <= 0) {
      return null;
    }
    if (visibleOnly && !bounds.overlaps(Offset.zero & layer.size)) return null;
    return FocusRing(
      bounds.inflate(4.75 * scale),
      (radius + 4.75) * scale,
      3.5 * scale,
    );
  }
}

class _OutlineLayer extends SingleChildRenderObjectWidget {
  const _OutlineLayer({
    required this.registry,
    required this.animate,
    required super.child,
  });
  final _OutlineRegistry registry;
  final bool animate;

  @override
  _RenderOutlineLayer createRenderObject(BuildContext context) =>
      _RenderOutlineLayer(registry, animate);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOutlineLayer renderObject,
  ) {
    renderObject.animate = animate;
  }
}

class _RenderOutlineLayer extends RenderProxyBox {
  _RenderOutlineLayer(this.registry, this._animate) {
    registry.layer = this;
    _rotation.addListener(markNeedsPaint);
    _ticker = Ticker((elapsed) {
      _elapsed = elapsed;
      markNeedsPaint();
    });
  }
  final _OutlineRegistry registry;
  final _rotation = _FocusRotation();
  late final Ticker _ticker;
  bool _animate;
  int? _geometryCallback;
  _RenderOutlineTarget? _target;
  _RenderOutlineTarget? _departing;
  FocusRing? _paintedTargetRing;
  FocusRing? _painted;
  FocusMotion? _motion;
  Duration _elapsed = Duration.zero;

  set animate(bool value) {
    if (_animate == value) return;
    _animate = value;
    if (!value) {
      _ticker.stop();
      _rotation.active = false;
      _motion = null;
      _departing = null;
    }
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _watchGeometry();
  }

  void _watchGeometry() {
    // Like OverlayPortal's geometry tracker, this runs only on frames that are
    // already happening. Repaint after layout so scrolling, cached subtrees and
    // tile growth use the current transform without an idle animation loop.
    _geometryCallback = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _geometryCallback = null;
      if (!attached) return;
      if (registry.targets.isNotEmpty || _painted != null) markNeedsPaint();
      _watchGeometry();
    }, scheduleNewFrame: false);
  }

  @override
  void detach() {
    _ticker.stop();
    _rotation.active = false;
    _painted = null;
    _motion = null;
    _target = null;
    _departing = null;
    _paintedTargetRing = null;
    if (_geometryCallback != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_geometryCallback!);
      _geometryCallback = null;
    }
    super.detach();
  }

  @override
  void dispose() {
    registry.layer = null;
    _ticker.dispose();
    _rotation.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _RenderOutlineTarget? target;
    FocusRing? destination;
    // A field retains editing focus while its controller dock owns primary
    // focus. The most recently focused visible control owns the single ring.
    for (final candidate in registry.targets.toList().reversed) {
      destination = candidate.geometry(this);
      if (destination != null) {
        target = candidate;
        break;
      }
    }
    if (destination == null) {
      _ticker.stop();
      _rotation.active = false;
      _target = null;
      _departing = null;
      _paintedTargetRing = null;
      _painted = null;
      _motion = null;
      return;
    }
    if (target != _target) {
      final previous = _motion;
      _departing = _target;
      _target = target;
      _ticker.stop();
      _motion = null;
      if (_animate && _painted != null) {
        _motion = FocusMotion(
          _painted!,
          destination,
          sourceAnchor: _paintedTargetRing,
          followSourceShape: previous == null,
          incomingSpeed: previous?.speed ?? 0,
        );
        _elapsed = Duration.zero;
        _ticker.start();
      }
    }
    // Sample both controls after layout. Scrolling and selected-tile growth
    // move the ring without restarting its clocks. A source
    // outside the viewport still supplies its transform while attached; if
    // removed, motion retains its last valid source geometry until arrival.
    _motion?.updateGeometry(
      sourceAnchor: _departing?.geometry(this, visibleOnly: false),
      destination: destination,
    );
    final frame = _motion?.frame(_elapsed) ?? destination;
    _painted = frame;
    _paintedTargetRing = destination;
    _rotation.active = _animate;
    if (_motion?.complete == true) {
      _ticker.stop();
      _motion = null;
      _departing = null;
    }
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    frame.paint(canvas, _rotation.phase);
    canvas.restore();
  }
}

// A slow color cycle needs only 30 foreground updates per second. Requesting
// each frame on demand also lets finite layout/focus animations settle while
// this decoration continues. No widget rebuild or content repaint is needed.
class _FocusRotation extends ChangeNotifier {
  Timer? _timer;
  double phase = 0;
  set active(bool value) {
    if (value == (_timer != null)) return;
    if (!value) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    var previous = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      phase =
          (phase + (timer.tick - previous) * .033 / 8 * math.pi * 2) %
          (math.pi * 2);
      previous = timer.tick;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    active = false;
    super.dispose();
  }
}

class _StandaloneOutline extends StatefulWidget {
  const _StandaloneOutline({
    required this.focused,
    required this.radius,
    required this.child,
  });
  final bool focused;
  final double radius;
  final Widget child;
  @override
  State<_StandaloneOutline> createState() => _StandaloneOutlineState();
}

class _StandaloneOutlineState extends State<_StandaloneOutline> {
  final overlay = OverlayPortalController();
  final rotation = _FocusRotation();
  @override
  void initState() {
    super.initState();
    if (widget.focused) overlay.show();
  }

  @override
  void didUpdateWidget(_StandaloneOutline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused == oldWidget.focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.focused == overlay.isShowing) return;
      widget.focused ? overlay.show() : overlay.hide();
    });
  }

  @override
  void dispose() {
    rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    rotation.active =
        widget.focused &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: overlay,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context, info) => Positioned(
        left: 0,
        top: 0,
        width: info.childSize.width,
        height: info.childSize.height,
        child: IgnorePointer(
          child: Transform(
            transform: info.childPaintTransform,
            child: CustomPaint(
              painter: widget.focused
                  ? _StandalonePainter(widget.radius, rotation)
                  : null,
            ),
          ),
        ),
      ),
      child: widget.child,
    );
  }
}

class _StandalonePainter extends CustomPainter {
  _StandalonePainter(this.radius, this.rotation) : super(repaint: rotation);
  final double radius;
  final _FocusRotation rotation;
  @override
  void paint(Canvas canvas, Size size) => FocusRing(
    (Offset.zero & size).inflate(4.75),
    radius + 4.75,
    3.5,
  ).paint(canvas, rotation.phase);
  @override
  bool shouldRepaint(_StandalonePainter oldDelegate) =>
      radius != oldDelegate.radius;
}
