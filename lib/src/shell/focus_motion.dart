import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show SweepGradient, GradientRotation;

/// One native rounded rectangle, including the small hollow traveling circle.
class FocusRing {
  const FocusRing(this.bounds, this.radius, this.stroke);
  final Rect bounds;
  final double radius, stroke;

  RRect get rounded => RRect.fromRectAndRadius(
    bounds,
    Radius.circular(radius.clamp(0.0, bounds.shortestSide / 2)),
  );

  void paint(Canvas canvas, double rotation) {
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = SweepGradient(
          colors: const [
            Color(0xffdef9ef),
            Color(0xffa7e5d2),
            Color(0xff75c8be),
            Color(0xffa5ded8),
            Color(0xffdef9ef),
          ],
          transform: GradientRotation(rotation),
        ).createShader(bounds),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FocusRing &&
      bounds == other.bounds &&
      radius == other.radius &&
      stroke == other.stroke;
  @override
  int get hashCode => Object.hash(bounds, radius, stroke);
}

double _ease(double t) => 1 - math.pow(1 - t.clamp(0.0, 1.0), 3).toDouble();

/// Position and size have independent clocks: arrival interrupts shrinking.
/// A new instance captures the visible ring and starts shrinking again.
class FocusMotion {
  FocusMotion(
    FocusRing source,
    FocusRing destination, {
    FocusRing? sourceAnchor,
    bool followSourceShape = true,
    double incomingSpeed = 0,
  }) : _captured = source,
       _source = source,
       _anchor = sourceAnchor ?? source,
       _liveAnchor = sourceAnchor ?? source,
       _followSourceShape = followSourceShape,
       _target = destination,
       _travel = FocusTravel(
         (destination.bounds.center - source.bounds.center).distance,
         speed: incomingSpeed,
       );

  final FocusRing _captured, _anchor;
  FocusRing _source, _target, _liveAnchor;
  final bool _followSourceShape;
  final FocusTravel _travel;
  Duration _elapsed = Duration.zero;
  Duration? _arrivedAt;
  FocusRing? _expansionFrom;
  double? _expansionUnits;
  bool _complete = false;
  bool get complete => _complete;

  double get speed => _arrivedAt == null ? _travel.speed(_elapsed) : 0;

  void updateGeometry({
    FocusRing? sourceAnchor,
    required FocusRing destination,
  }) {
    if (sourceAnchor != null && sourceAnchor != _liveAnchor) {
      _liveAnchor = sourceAnchor;
      if (_followSourceShape) {
        _source = sourceAnchor;
      } else {
        // Carry an interrupted pose with its control without stretching the
        // snapshot when that control's selected-tile layout changes size.
        final scale = sourceAnchor.stroke / _anchor.stroke;
        final offset =
            sourceAnchor.bounds.topLeft - _anchor.bounds.topLeft * scale;
        _source = FocusRing(
          Rect.fromLTWH(
            _captured.bounds.left * scale + offset.dx,
            _captured.bounds.top * scale + offset.dy,
            _captured.bounds.width * scale,
            _captured.bounds.height * scale,
          ),
          _captured.radius * scale,
          _captured.stroke * scale,
        );
      }
    }
    _target = destination;
  }

  FocusRing _shrinking(Duration elapsed, Offset center) {
    final progress = _ease(elapsed.inMicroseconds / 160000);
    final units = _target.stroke / 3.5;
    return FocusRing(
      Rect.fromCenter(
        center: center,
        width: lerpDouble(_source.bounds.width, 16 * units, progress)!,
        height: lerpDouble(_source.bounds.height, 16 * units, progress)!,
      ),
      lerpDouble(_source.radius, 8 * units, progress)!,
      lerpDouble(_source.stroke, _target.stroke, _travel.progress(elapsed))!,
    );
  }

  FocusRing frame(Duration elapsed) {
    _elapsed = elapsed;
    if (complete) return _target;
    final movement = _travel.progress(elapsed);
    final center = Offset.lerp(
      _source.bounds.center,
      _target.bounds.center,
      movement,
    )!;
    if (_arrivedAt == null &&
        (movement >= 1 ||
            (center - _target.bounds.center).distance <=
                .5 * _target.stroke / 3.5)) {
      // If a frame is delayed, use the actual travel deadline so it cannot
      // postpone expansion or leave an invisible app's motion unfinished.
      _arrivedAt = movement >= 1 ? _travel.duration : elapsed;
      _expansionFrom = _shrinking(_arrivedAt!, _target.bounds.center);
      _expansionUnits = _target.stroke;
    }
    if (elapsed == Duration.zero) return _source;
    if (_arrivedAt case final arrived?) {
      final t = _ease((elapsed - arrived).inMicroseconds / 140000);
      if (t >= 1) {
        _complete = true;
        return _target;
      }
      final from = _expansionFrom!, scale = _target.stroke / _expansionUnits!;
      return FocusRing(
        Rect.fromCenter(
          center: _target.bounds.center,
          width: lerpDouble(
            from.bounds.width * scale,
            _target.bounds.width,
            t,
          )!,
          height: lerpDouble(
            from.bounds.height * scale,
            _target.bounds.height,
            t,
          )!,
        ),
        lerpDouble(from.radius * scale, _target.radius, t)!,
        _target.stroke,
      );
    }
    return _shrinking(elapsed, center);
  }
}

/// Monotone center travel, retaining bounded incoming speed on a retarget.
class FocusTravel {
  FocusTravel(this.distance, {double speed = 0}) {
    var interval = (distance / 1100).clamp(.09, .36);
    if (speed > 0 && distance > 0)
      interval = math.min(interval, (3 * distance / speed).clamp(.06, .36));
    seconds = interval;
    slope = distance <= 0
        ? 0
        : speed > 0
        ? (speed * seconds / distance).clamp(0.0, 3.0)
        : 3;
  }
  final double distance;
  late final double seconds, slope;
  Duration get duration => Duration(microseconds: (seconds * 1e6).ceil());
  double progress(Duration elapsed) {
    final t = (elapsed.inMicroseconds / 1e6 / seconds).clamp(0.0, 1.0);
    return ((-2 * t * t * t + 3 * t * t) + (t * t * t - 2 * t * t + t) * slope)
        .clamp(0.0, 1.0);
  }

  double speed(Duration elapsed) {
    final t = (elapsed.inMicroseconds / 1e6 / seconds).clamp(0.0, 1.0);
    return distance /
        seconds *
        ((-6 * t * t + 6 * t) + (3 * t * t - 4 * t + 1) * slope);
  }
}
