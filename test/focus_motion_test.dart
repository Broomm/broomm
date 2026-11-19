import 'dart:ui';

import 'package:broomm/src/shell/focus_motion.dart';
import 'package:flutter_test/flutter_test.dart';

FocusRing shifted(FocusRing ring, Offset delta) =>
    FocusRing(ring.bounds.shift(delta), ring.radius, ring.stroke);
FocusRing scaled(FocusRing ring, double scale) => FocusRing(
  Rect.fromLTWH(
    ring.bounds.left * scale,
    ring.bounds.top * scale,
    ring.bounds.width * scale,
    ring.bounds.height * scale,
  ),
  ring.radius * scale,
  ring.stroke * scale,
);
void expectShift(FocusRing before, FocusRing after, Offset delta) {
  expect(
    (after.bounds.topLeft - before.bounds.topLeft - delta).distance,
    lessThan(.001),
  );
  expect(after.bounds.width, closeTo(before.bounds.width, .001));
  expect(after.bounds.height, closeTo(before.bounds.height, .001));
  expect(after.radius, before.radius);
}

void main() {
  const tile = FocusRing(Rect.fromLTWH(40, 160, 156, 156), 20, 3.5);
  const button = FocusRing(Rect.fromLTWH(304, 70, 244, 56), 20, 3.5);

  test('the outline shrinks while moving, travels as a circle, then expands into the target', () {
    final motion = FocusMotion(tile, button);
    expect(motion.frame(Duration.zero), tile);
    final early = motion.frame(const Duration(milliseconds: 70));
    expect(early.bounds.width, lessThan(tile.bounds.width));
    expect(early.bounds.center.dx, greaterThan(tile.bounds.center.dx));
    expect(early.bounds.center.dx, lessThan(button.bounds.center.dx));
    final circle = motion.frame(const Duration(milliseconds: 190));
    expect(circle.bounds.width, closeTo(circle.bounds.height, .001));
    expect(circle.radius, closeTo(circle.bounds.width / 2, .001));
    expect(circle.bounds.width, lessThan(20));
    expect(circle.stroke, tile.stroke);
    final expanding = motion.frame(const Duration(milliseconds: 360));
    expect(expanding.bounds.center, button.bounds.center);
    expect(expanding.bounds.width, greaterThan(circle.bounds.width));
    expect(expanding.bounds.width, lessThan(button.bounds.width));
    expect(motion.frame(const Duration(seconds: 1)), button);
    expect(motion.complete, true);
  });

  test(
    'early arrival interrupts shrinking and coincident centers only resize',
    () {
      final target = shifted(tile, const Offset(60, 0));
      final motion = FocusMotion(tile, target);
      final arrived = motion.frame(const Duration(milliseconds: 80));
      expect(arrived.bounds.center, target.bounds.center);
      expect(arrived.bounds.width, greaterThan(20));
      final expanding = motion.frame(const Duration(milliseconds: 100));
      expect(expanding.bounds.width, greaterThan(arrived.bounds.width));
      expect(motion.frame(const Duration(milliseconds: 300)), target);

      final localTarget = FocusRing(
        Rect.fromCenter(center: tile.bounds.center, width: 30, height: 60),
        6,
        3.5,
      );
      final local = FocusMotion(tile, localTarget);
      expect(local.frame(Duration.zero), tile);
      final middle = local.frame(const Duration(milliseconds: 70));
      expect(middle.bounds.center, localTarget.bounds.center);
      expect(
        middle.bounds.width,
        inExclusiveRange(localTarget.bounds.width, tile.bounds.width),
      );
      expect(local.frame(const Duration(milliseconds: 200)), localTarget);
    },
  );

  test('retargeting during expansion shrinks the visible pose without a jump or repeated growth', () {
    final first = FocusMotion(tile, button);
    var pose = first.frame(const Duration(milliseconds: 360));
    final width = pose.bounds.width;
    var previousTarget = button;
    for (final target in [tile, button, tile, button]) {
      final next = FocusMotion(
        pose,
        target,
        sourceAnchor: previousTarget,
        followSourceShape: false,
      );
      expect(next.frame(Duration.zero), pose);
      final moving = next.frame(const Duration(milliseconds: 40));
      expect(moving.bounds.width, lessThan(pose.bounds.width));
      pose = moving;
      previousTarget = target;
    }
    expect(pose.bounds.width, lessThan(width / 3));
    final finalMove = FocusMotion(
      pose,
      tile,
      sourceAnchor: button,
      followSourceShape: false,
    );
    expect(finalMove.frame(const Duration(seconds: 2)), tile);
    expect(
      finalMove.complete,
      true,
    ); // A delayed frame must catch up both clocks.
  });

  test('scroll and UI scale carry both moving and expanding rings at fixed animation time', () {
    final motion = FocusMotion(tile, button);
    const delta = Offset(-47, -83);
    final before = motion.frame(const Duration(milliseconds: 190));
    motion.updateGeometry(
      sourceAnchor: shifted(tile, delta),
      destination: shifted(button, delta),
    );
    expectShift(before, motion.frame(const Duration(milliseconds: 190)), delta);
    final expanding = motion.frame(const Duration(milliseconds: 360));
    motion.updateGeometry(
      sourceAnchor: shifted(tile, delta * 2),
      destination: shifted(button, delta * 2),
    );
    expectShift(
      expanding,
      motion.frame(const Duration(milliseconds: 360)),
      delta,
    );
    final beforeScale = motion.frame(const Duration(milliseconds: 360));
    motion.updateGeometry(
      sourceAnchor: scaled(shifted(tile, delta * 2), 1.5),
      destination: scaled(shifted(button, delta * 2), 1.5),
    );
    final afterScale = motion.frame(const Duration(milliseconds: 360));
    final expected = scaled(beforeScale, 1.5);
    expect(
      (afterScale.bounds.topLeft - expected.bounds.topLeft).distance,
      lessThan(.001),
    );
    expect(afterScale.bounds.width, closeTo(expected.bounds.width, .001));
    expect(afterScale.radius, closeTo(expected.radius, .001));
  });

  test('live resize and removed source anchors preserve the current target and interrupted pose', () {
    final motion = FocusMotion(tile, button);
    const liveSource = FocusRing(Rect.fromLTWH(-110, 120, 113, 113), 16, 3.5);
    const liveTarget = FocusRing(Rect.fromLTWH(40, 120, 156, 156), 20, 3.5);
    motion.updateGeometry(sourceAnchor: liveSource, destination: liveTarget);
    expect(motion.frame(Duration.zero), liveSource);
    final pose = motion.frame(const Duration(milliseconds: 90));
    final interrupted = FocusMotion(
      pose,
      tile,
      sourceAnchor: liveTarget,
      followSourceShape: false,
    );
    const resized = FocusRing(Rect.fromLTWH(60, 180, 234, 234), 30, 5.25);
    interrupted.updateGeometry(sourceAnchor: resized, destination: tile);
    final carried = interrupted.frame(Duration.zero);
    final expected =
        (pose.bounds.topLeft - liveTarget.bounds.topLeft) * 1.5 +
        resized.bounds.topLeft;
    expect((carried.bounds.topLeft - expected).distance, lessThan(.001));
    expect(carried.bounds.size, pose.bounds.size * 1.5);
    motion.updateGeometry(
      destination: button,
    ); // Departing control was removed.
    expect(motion.frame(const Duration(seconds: 1)), button);
  });

  test('wide, portrait, circular and overlapping controls always use valid native rounded rectangles', () {
    for (final source in [
      tile,
      button,
      const FocusRing(Rect.fromLTWH(0, 0, 4000, 50), 14, 3.5),
    ]) {
      for (final target in [
        button,
        tile,
        const FocusRing(Rect.fromLTWH(60, 180, 116, 116), 58, 3.5),
      ]) {
        final motion = FocusMotion(source, target);
        for (final ms in [0, 1, 40, 120, 200, 300, 500, 1000]) {
          final frame = motion.frame(Duration(milliseconds: ms));
          expect(frame.bounds.isFinite && !frame.bounds.isEmpty, true);
          expect(
            frame.rounded.tlRadiusX,
            inInclusiveRange(0, frame.bounds.shortestSide / 2),
          );
          expect(frame.stroke, source.stroke);
        }
        expect(motion.complete, true);
      }
    }
  });

  test(
    'portrait center travel has consistent pacing in all four directions',
    () {
      final speeds = [
        for (final distance in [186.0, 186.0, 283.0, 283.0])
          FocusTravel(distance).speed(Duration.zero),
      ];
      for (final speed in speeds) expect(speed, closeTo(speeds.first, .01));
    },
  );

  test('long travel accelerates within the bound and carries incoming speed monotonically', () {
    final short = FocusTravel(60), long = FocusTravel(800);
    expect(long.speed(Duration.zero), greaterThan(short.speed(Duration.zero)));
    expect(
      long.speed(Duration.zero),
      greaterThan(long.speed(const Duration(milliseconds: 100))),
    );
    expect(long.speed(const Duration(seconds: 1)), closeTo(0, .0001));
    final incoming = long.speed(const Duration(milliseconds: 100));
    final retarget = FocusTravel(400, speed: incoming);
    expect(retarget.speed(Duration.zero), closeTo(incoming, .0001));
    var previous = 0.0;
    for (var i = 0; i < 600; i += 5) {
      final p = retarget.progress(Duration(milliseconds: i));
      expect(p, inInclusiveRange(previous, 1));
      previous = p;
    }
  });
}
