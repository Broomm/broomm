import 'dart:async';
import 'dart:ui' as ui;

import 'package:broomm/src/shell/controls.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<({ByteData bytes, int width})> capture(
  WidgetTester tester,
  GlobalKey key, {
  bool settle = true,
}) async {
  if (settle) await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (bytes: bytes!, width: image.width);
    } finally {
      image.dispose();
    }
  }))!;
}

Rect ringBounds(({ByteData bytes, int width}) image) {
  var left = image.width, top = image.bytes.lengthInBytes ~/ (image.width * 4);
  var right = -1, bottom = -1;
  for (var y = 0; y < image.bytes.lengthInBytes ~/ (image.width * 4); y++) {
    for (var x = 0; x < image.width; x++) {
      final color = pixel(image, Offset(x.toDouble(), y.toDouble()));
      if (color.g > .55 && color.b > .50 && color.r > .30) {
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }
  return right < left
      ? Rect.zero
      : Rect.fromLTRB(
          left.toDouble(),
          top.toDouble(),
          right + 1.0,
          bottom + 1.0,
        );
}

Color pixel(({ByteData bytes, int width}) image, Offset position) {
  final offset = (position.dy.floor() * image.width + position.dx.floor()) * 4;
  final bytes = image.bytes;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

void expectOutline(Color color) {
  expect(color.g, greaterThan(.55));
  expect(color.b, greaterThan(.50));
  expect(color.r, greaterThan(.30));
}

Offset rightEdge(Rect rect, [double scale = 1]) =>
    Offset(rect.right + 4.75 * scale, rect.center.dy);

Widget app(Widget child, GlobalKey boundary) => RepaintBoundary(
  key: boundary,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, navigator) => Shortcuts(
      shortcuts: consoleShortcuts,
      child: ConsoleKeyboardHost(child: navigator!),
    ),
    home: Scaffold(backgroundColor: Colors.black, body: child),
  ),
);

void main() {
  testWidgets(
    'the gradient rotates while the focused control and content stay still',
    (tester) async {
      final boundary = GlobalKey();
      late StateSetter update;
      var reduced = false, focused = true, builds = 0, paints = 0;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            builder: (context, navigator) => StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: reduced),
                  child: ConsoleKeyboardHost(
                    child: Scaffold(
                      backgroundColor: Colors.black,
                      body: Center(
                        child: ConsoleFocusOutline(
                          focused: focused,
                          radius: 10,
                          child: Builder(
                            builder: (context) {
                              builds++;
                              return SizedBox(
                                width: 140,
                                height: 90,
                                child: CustomPaint(
                                  painter: _PaintCounter(() => paints++),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            home: const SizedBox(),
          ),
        ),
      );
      var image = await capture(tester, boundary);
      final edge = ringBounds(image), first = image.bytes.buffer.asUint8List();
      final initialBuilds = builds, initialPaints = paints;
      await tester.pump(const Duration(seconds: 2));
      image = await capture(tester, boundary, settle: false);
      expect(ringBounds(image), edge);
      expect(listEquals(first, image.bytes.buffer.asUint8List()), false);
      expect(builds, initialBuilds);
      expect(paints, initialPaints);
      final beforeHidden = image.bytes.buffer.asUint8List();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      // Advance time before the hidden widget can rebuild. Its timer must have
      // stopped synchronously even when the OS stops delivering display frames.
      await tester.pump(const Duration(seconds: 2));
      image = await capture(tester, boundary, settle: false);
      expect(listEquals(beforeHidden, image.bytes.buffer.asUint8List()), true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      image = await capture(tester, boundary, settle: false);
      expect(listEquals(beforeHidden, image.bytes.buffer.asUint8List()), false);
      update(() => reduced = true);
      image = await capture(tester, boundary);
      final still = image.bytes.buffer.asUint8List();
      await tester.pump(const Duration(seconds: 2));
      image = await capture(tester, boundary, settle: false);
      expect(listEquals(still, image.bytes.buffer.asUint8List()), true);
      update(() {
        reduced = false;
        focused = false;
      });
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(
        ringBounds(await capture(tester, boundary, settle: false)),
        Rect.zero,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the traveling ball is a small hollow circle with constant stroke width',
    (tester) async {
      final boundary = GlobalKey();
      late StateSetter update;
      var selected = 0;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Stack(
                children: [
                  for (final (i, rect) in [
                    const Rect.fromLTWH(80, 80, 120, 100),
                    const Rect.fromLTWH(540, 220, 120, 100),
                  ].indexed)
                    Positioned.fromRect(
                      rect: rect,
                      child: ConsoleFocusOutline(
                        focused: selected == i,
                        radius: 14,
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              );
            },
          ),
          boundary,
        ),
      );
      await tester.pumpAndSettle();
      update(() => selected = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 190));
      final image = await capture(tester, boundary, settle: false);
      final circle = ringBounds(image);
      expect(circle.width, inInclusiveRange(18, 22));
      expect(circle.height, closeTo(circle.width, 1));
      expect(pixel(image, circle.center), Colors.black);
      expectOutline(pixel(image, circle.center + const Offset(7.5, 0)));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'the ring shrinks during travel, retains its pose on reversal and follows a resizing target',
    (tester) async {
      final boundary = GlobalKey();
      late StateSetter update;
      var selection = 0;
      final positions = [
        const Rect.fromLTWH(80, 80, 100, 60),
        const Rect.fromLTWH(320, 80, 140, 90),
        const Rect.fromLTWH(60, 250, 80, 40),
      ];
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Stack(
                children: [
                  for (var i = 0; i < positions.length; i++)
                    Positioned.fromRect(
                      rect: positions[i],
                      child: ConsoleFocusOutline(
                        focused: selection == i,
                        radius: i == 1 ? 25 : 8,
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              );
            },
          ),
          boundary,
        ),
      );
      final initial = ringBounds(await capture(tester, boundary));
      update(() => selection = 1);
      await tester.pump();
      expect(
        ringBounds(await capture(tester, boundary, settle: false)),
        initial,
      );
      await tester.pump(const Duration(milliseconds: 90));
      final moving = ringBounds(await capture(tester, boundary, settle: false));
      expect(moving.center.dx, greaterThan(initial.center.dx));
      expect(moving.center.dx, lessThan(positions[1].center.dx));
      expect(moving.width, lessThan(initial.width));
      update(() => selection = 2);
      await tester.pump();
      expect(
        ringBounds(await capture(tester, boundary, settle: false)),
        moving,
      );
      await tester.pump(const Duration(milliseconds: 90));
      final previousDestination = positions[2];
      update(() => positions[2] = const Rect.fromLTWH(210, 260, 110, 50));
      final finalImage = await capture(tester, boundary);
      expectOutline(pixel(finalImage, rightEdge(positions[2])));
      expect(pixel(finalImage, rightEdge(previousDestination)), Colors.black);
      expect(pixel(finalImage, rightEdge(positions[0])), Colors.black);
      expect(pixel(finalImage, rightEdge(positions[1])), Colors.black);
      expect(tester.binding.hasScheduledFrame, false);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a scrolling viewport carries the whole in-flight outline and tolerates a removed source',
    (tester) async {
      for (final axis in [Axis.horizontal, Axis.vertical]) {
        final boundary = GlobalKey(), destination = GlobalKey();
        final scroll = ScrollController();
        late StateSetter update;
        var selected = 0, removeSource = false;
        await tester.pumpWidget(
          app(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 650,
                height: 440,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return SingleChildScrollView(
                      controller: scroll,
                      scrollDirection: axis,
                      child: Flex(
                        direction: axis,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(width: 100, height: 100),
                          for (var i = 0; i < 2; i++)
                            if (i != 0 || !removeSource)
                              Padding(
                                key: ValueKey(i),
                                padding: const EdgeInsets.all(20),
                                child: ConsoleFocusOutline(
                                  key: i == 1 ? destination : null,
                                  focused: selected == i,
                                  radius: 14,
                                  child: const SizedBox(
                                    width: 120,
                                    height: 180,
                                  ),
                                ),
                              ),
                          const SizedBox(width: 900, height: 900),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            boundary,
          ),
        );
        await tester.pumpAndSettle();
        update(() => selected = 1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        final before = ringBounds(
          await capture(tester, boundary, settle: false),
        );
        scroll.jumpTo(40);
        await tester
            .pump(); // Same animation time, different viewport transform.
        final after = ringBounds(
          await capture(tester, boundary, settle: false),
        );
        final delta = axis == Axis.horizontal
            ? const Offset(-40, 0)
            : const Offset(0, -40);
        final expected = before.shift(delta);
        expect(after.left, closeTo(expected.left, 1));
        expect(after.top, closeTo(expected.top, 1));
        expect(after.right, closeTo(expected.right, 1));
        expect(after.bottom, closeTo(expected.bottom, 1));
        scroll.jumpTo(270); // Departing control is now outside the viewport.
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          ringBounds(await capture(tester, boundary, settle: false)).isEmpty,
          false,
        );
        scroll.jumpTo(0);
        update(() => removeSource = true);
        await tester.pump();
        final image = await capture(tester, boundary);
        expectOutline(
          pixel(image, rightEdge(tester.getRect(find.byKey(destination)))),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
      }
    },
  );

  testWidgets(
    'reduced motion snaps even during a transition and removing focus clears it',
    (tester) async {
      final boundary = GlobalKey();
      late StateSetter update;
      var selection = 0, reduced = false, hidden = false;
      final positions = [
        const Rect.fromLTWH(80, 80, 100, 60),
        const Rect.fromLTWH(320, 80, 100, 60),
      ];
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            builder: (context, navigator) => StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: reduced),
                  child: ConsoleKeyboardHost(
                    child: Scaffold(
                      backgroundColor: Colors.black,
                      body: Stack(
                        children: [
                          for (var i = 0; i < positions.length; i++)
                            Positioned.fromRect(
                              rect: positions[i],
                              child: Offstage(
                                offstage: hidden,
                                child: ConsoleFocusOutline(
                                  focused: selection == i,
                                  radius: 8,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            home: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      update(() => selection = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      update(() => reduced = true);
      await tester.pump();
      var image = await capture(tester, boundary, settle: false);
      expectOutline(pixel(image, rightEdge(positions[1])));
      expect(pixel(image, rightEdge(positions[0])), Colors.black);
      // The ticker already requested a frame before this preference changed
      // during build. It must stop there; the visible ring has snapped above.
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, false);
      update(() => selection = 0);
      await tester.pump();
      image = await capture(tester, boundary, settle: false);
      expectOutline(pixel(image, rightEdge(positions[0])));
      expect(tester.binding.hasScheduledFrame, false);
      update(() => hidden = true);
      await tester.pump();
      expect(
        ringBounds(await capture(tester, boundary, settle: false)),
        Rect.zero,
      );
      update(() {
        hidden = false;
        reduced = false;
        selection = 1;
      });
      await tester.pump();
      update(() => selection = -1);
      await tester.pump();
      expect(
        ringBounds(await capture(tester, boundary, settle: false)),
        Rect.zero,
      );
      await tester.pump(); // Drain the last frame requested before focus left.
      expect(tester.binding.hasScheduledFrame, false);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the outline paints above later elevated siblings and lets taps through',
    (tester) async {
      final boundary = GlobalKey(), target = GlobalKey();
      late StateSetter update;
      var focused = true, taps = 0;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Stack(
                children: [
                  Positioned(
                    left: 80,
                    top: 80,
                    child: ClipRect(
                      child: ConsoleFocusOutline(
                        focused: focused,
                        radius: 5,
                        child: SizedBox(key: target, width: 100, height: 60),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 180,
                    top: 50,
                    width: 80,
                    height: 150,
                    child: Material(
                      elevation: 30,
                      color: Colors.red,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => taps++,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          boundary,
        ),
      );
      final edge = rightEdge(tester.getRect(find.byKey(target)));
      var image = await capture(tester, boundary);
      expectOutline(pixel(image, edge));
      expect(
        pixel(image, edge + const Offset(8, 0)).toARGB32(),
        Colors.red.toARGB32(),
      );
      await tester.tapAt(edge);
      expect(taps, 1);
      update(() => focused = false);
      image = await capture(tester, boundary);
      expect(pixel(image, edge).toARGB32(), Colors.red.toARGB32());
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'the outline follows scrolling, scaling and removal of its control',
    (tester) async {
      final boundary = GlobalKey(), target = GlobalKey();
      final scroll = ScrollController();
      late StateSetter update;
      var scale = 1.0, present = true;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 400,
                  height: 250,
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: SizedBox(
                      height: 600,
                      child: Stack(
                        children: [
                          if (present)
                            Positioned(
                              left: 80,
                              top: 100,
                              child: Transform.scale(
                                scale: scale,
                                alignment: Alignment.topLeft,
                                child: ConsoleFocusOutline(
                                  focused: true,
                                  radius: 5,
                                  child: SizedBox(
                                    key: target,
                                    width: 100,
                                    height: 60,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          boundary,
        ),
      );
      var image = await capture(tester, boundary);
      expectOutline(
        pixel(image, rightEdge(tester.getRect(find.byKey(target)))),
      );
      scroll.jumpTo(30);
      update(() => scale = 1.5);
      image = await capture(tester, boundary);
      var edge = rightEdge(tester.getRect(find.byKey(target)), scale);
      expectOutline(pixel(image, edge));
      update(() => scale = .5);
      image = await capture(tester, boundary);
      edge = rightEdge(tester.getRect(find.byKey(target)), scale);
      expectOutline(pixel(image, edge));
      update(() => present = false);
      image = await capture(tester, boundary);
      expect(pixel(image, edge), Colors.black);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );

  testWidgets(
    'keyboard outlines cover neighboring keys and follow focus into a dialog',
    (tester) async {
      final boundary = GlobalKey(), dialogButton = GlobalKey();
      await tester.pumpWidget(
        app(
          ConsoleField(
            autofocus: true,
            label: 'Query',
            value: '',
            onChanged: (_) {},
          ),
          boundary,
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await tester.pumpAndSettle();
      final key = find.byWidgetPredicate(
        (widget) => widget is ConsoleButton && widget.label == '1',
      );
      final rect = tester.getRect(key);
      final edges = [
        rightEdge(rect),
        Offset(rect.left - 4.75, rect.center.dy),
        Offset(rect.center.dx, rect.bottom + 4.75),
      ];
      var image = await capture(tester, boundary);
      for (final edge in edges) {
        expectOutline(pixel(image, edge));
      }
      final context = tester.element(find.byType(ConsoleField));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            content: ConsoleButton(
              key: dialogButton,
              autofocus: true,
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close dialog'),
            ),
          ),
        ),
      );
      image = await capture(tester, boundary);
      expectOutline(
        pixel(image, rightEdge(tester.getRect(find.byKey(dialogButton)))),
      );
      final oldRing = pixel(image, edges.first);
      expect(oldRing.g, lessThan(.5));
      await tester.tap(find.text('Close dialog'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _PaintCounter extends CustomPainter {
  const _PaintCounter(this.painted);
  final VoidCallback painted;
  @override
  void paint(Canvas canvas, Size size) => painted();
  @override
  bool shouldRepaint(_PaintCounter oldDelegate) => false;
}
