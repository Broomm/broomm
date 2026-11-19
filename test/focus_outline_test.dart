import 'dart:async';
import 'dart:ui' as ui;

import 'package:broomm/src/shell/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<({ByteData bytes, int width})> capture(
  WidgetTester tester,
  GlobalKey key,
) async {
  await tester.pumpAndSettle();
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
    builder: (context, navigator) => Shortcuts(
      shortcuts: consoleShortcuts,
      child: ConsoleKeyboardHost(child: navigator!),
    ),
    home: Scaffold(backgroundColor: Colors.black, body: child),
  ),
);

void main() {
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
      final edge = rightEdge(tester.getRect(find.byKey(target)), scale);
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
