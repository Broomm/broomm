import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:broomm/src/remote/video_decoder.dart';

import 'package:broomm/src/remote/connection.dart';
import 'package:broomm/src/remote/protocol.dart';
import 'package:broomm/src/remote/service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:broomm/src/shell/remote_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'active status arriving after a frame preserves the pending image',
    () async {
      final root = await Directory.systemTemp.createTemp('remote-video-');
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peer = Completer<RemoteConnection>();
      server.listen((socket) {
        final connection = RemoteConnection(socket);
        connection.listen((data) {
          if (data is! String) return;
          if (jsonDecode(data)['type'] == 'hello') {
            connection.add(
              jsonEncode({'type': 'ready', 'version': remoteProtocol}),
            );
            peer.complete(connection);
          }
        });
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            RemoteScreenService.channel,
            (_) async => null,
          );
      final service = RemoteScreenService(root, hostEnabled: false);
      try {
        await service.start();
        await service.connect('127.0.0.1:${server.port}', 'test-code');
        final remote = await peer.future;
        final received = Completer<void>();
        service.addListener(() {
          if (service.frame != null && !received.isCompleted)
            received.complete();
        });
        final bytes = Uint8List.fromList([255, 216, 255, 217]);
        remote.add(bytes);
        await received.future.timeout(const Duration(seconds: 2));
        final status = Completer<void>();
        service.addListener(() {
          if (service.status == 'melonDS secondary screen' &&
              !status.isCompleted)
            status.complete();
        });
        remote.add(
          jsonEncode({
            'type': 'status',
            'message': 'melonDS secondary screen',
            'touch': true,
          }),
        );
        await status.future.timeout(const Duration(seconds: 2));
        expect(service.frame, orderedEquals(bytes));
        final cleared = Completer<void>();
        service.addListener(() {
          if (service.frame == null && !cleared.isCompleted) cleared.complete();
        });
        remote.add(
          jsonEncode({
            'type': 'status',
            'message': 'Starting a new capture',
            'clear': true,
          }),
        );
        await cleared.future.timeout(const Duration(seconds: 2));
        expect(service.frame, isNull);
      } finally {
        await service.close();
        if (peer.isCompleted) await (await peer.future).close();
        await server.close();
        await root.delete(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(RemoteScreenService.channel, null);
      }
    },
  );
  test('decoder completes active frame, drops superseded JPEGs and recovers errors', () async {
    final calls = <int>[], delivered = <ui.Image>[];
    final pending = <int, Completer<ui.Image>>{};
    final failed = Completer<void>();
    final decoder = RemoteFrameDecoder(
      onImage: delivered.add,
      onError: () {
        if (!failed.isCompleted) failed.complete();
      },
      decode: (bytes) {
        calls.add(bytes.first);
        return (pending[bytes.first] = Completer<ui.Image>()).future;
      },
    );
    Future<ui.Image> image() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
          .drawColor(const ui.Color(0xff00ff00), ui.BlendMode.src);
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(1, 1);
      } finally {
        picture.dispose();
      }
    }

    try {
      decoder.add(Uint8List.fromList([1]));
      decoder.add(Uint8List.fromList([2]));
      decoder.add(Uint8List.fromList([3]));
      final first = await image();
      pending[1]!.complete(first);
      await Future<void>.delayed(Duration.zero);
      expect(calls, [1, 3]);
      expect(delivered, [first]);
      pending[3]!.completeError(const FormatException('broken frame'));
      await failed.future;
      decoder.add(Uint8List.fromList([4]));
      final next = await image();
      pending[4]!.complete(next);
      await Future<void>.delayed(Duration.zero);
      expect(delivered, [first, next]);
    } finally {
      decoder.dispose();
      for (final image in delivered) {
        image.dispose();
      }
    }
  });

  test(
    'decoder discards in-flight results across pause and disposal',
    () async {
      final pending = <Completer<ui.Image>>[], delivered = <ui.Image>[];
      final decoder = RemoteFrameDecoder(
        onImage: delivered.add,
        decode: (_) {
          final work = Completer<ui.Image>();
          pending.add(work);
          return work.future;
        },
      );
      Future<ui.Image> image() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
            .drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
        final picture = recorder.endRecording();
        try {
          return await picture.toImage(1, 1);
        } finally {
          picture.dispose();
        }
      }

      decoder.add(Uint8List(1));
      decoder.pause(true);
      decoder.pause(false);
      decoder.add(Uint8List(1));
      final stale = await image();
      pending[0].complete(stale);
      await Future<void>.delayed(Duration.zero);
      expect(stale.debugDisposed, true);
      expect(delivered, isEmpty);
      decoder.dispose();
      final closed = await image();
      pending[1].complete(closed);
      await Future<void>.delayed(Duration.zero);
      expect(closed.debugDisposed, true);
      expect(delivered, isEmpty);
    },
  );

  test(
    'host progresses without paint ACKs and ignores obsolete capture events',
    () async {
      final root = await Directory.systemTemp.createTemp('remote-host-video-');
      final captures = <Map<dynamic, dynamic>>[];
      final credits = <int>[];
      final captureReady = Completer<void>();
      final noFrames = Completer<void>();
      final actions = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(RemoteScreenService.channel, (call) async {
            if (call.method == 'capture' && call.arguments is Map) {
              captures.add(call.arguments as Map);
              if (captures.length == 1) await captureReady.future;
            }
            if (call.method == 'nextFrame')
              credits.add((call.arguments as Map)['id'] as int);
            return null;
          });
      final host = RemoteScreenService(
        root,
        hostEnabled: true,
        listenPort: 0,
        monotonicMillis: () => 0,
        onAction: actions.add,
        onEvent: (event) {
          if (event.contains('No video frames') && !noFrames.isCompleted)
            noFrames.complete();
        },
      );
      RemoteConnection? peer;
      final received = <Object>[];
      Future<void> until(bool Function() done) async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (!done()) {
          if (DateTime.now().isAfter(deadline))
            fail('Remote video transition did not complete.');
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      Future<void> native(String method, Object arguments) async {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'app.broomm/remote',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall(method, arguments),
              ),
              (_) {},
            );
      }

      try {
        await host.start();
        peer = RemoteConnection(await Socket.connect('127.0.0.1', host.port!));
        peer.listen(received.add);
        peer.add(
          jsonEncode({
            'type': 'hello',
            'code': host.history.code,
            'version': remoteProtocol,
            'sent': 0,
          }),
        );
        await until(() => host.hasGuest);
        host.setGame(99, 'melonDS', {
          'seconds': 1,
          'remoteCapture': [5, 0, 20, 800, 600],
        });
        await until(() => captures.isNotEmpty);
        final firstId = captures.first['id'] as int;
        final jpeg = Uint8List.fromList([255, 216, 255, 217]);
        await native('frame', {'id': firstId, 'bytes': jpeg});
        await until(
          () =>
              received.whereType<Uint8List>().length == 1 &&
              credits.length == 1,
        );
        await native('frame', {'id': firstId, 'bytes': jpeg});
        await until(
          () =>
              received.whereType<Uint8List>().length == 2 &&
              credits.length == 2,
        );
        host.setGame(100, 'melonDS', {
          'seconds': 2,
          'remoteCapture': [6, 0, 20, 800, 600],
        });
        await native('frame', {'id': firstId, 'bytes': jpeg});
        await native('captureError', {
          'id': firstId,
          'message': 'cancelled startup',
        });
        captureReady.complete();
        await until(() => captures.length == 2);
        final secondId = captures.last['id'] as int;
        await native('frame', {'id': firstId, 'bytes': jpeg});
        await native('captureError', {
          'id': firstId,
          'message': 'old stream stopped',
        });
        await noFrames.future.timeout(const Duration(seconds: 6));
        peer.add(jsonEncode({'type': 'action', 'action': 'accept', 'sent': 0}));
        await until(() => actions.contains('accept'));
        await native('frame', {'id': secondId, 'bytes': jpeg});
        await until(() => received.whereType<Uint8List>().length == 3);
        expect(credits.where((id) => id == firstId).length, 2);
        final statuses = received
            .whereType<String>()
            .map(jsonDecode)
            .where((m) => m['type'] == 'status')
            .map((m) => m['message'])
            .toList();
        expect(statuses, isNot(contains(contains('old stream stopped'))));
        expect(statuses, isNot(contains(contains('cancelled startup'))));
        expect(statuses.last, 'melonDS secondary screen');
      } finally {
        if (!captureReady.isCompleted) captureReady.complete();
        host.setGame(null, null, null);
        await peer?.close();
        await host.close();
        await root.delete(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(RemoteScreenService.channel, null);
      }
    },
    skip: Platform.isMacOS ? false : 'Native hosting is staged for macOS.',
  );
  testWidgets(
    'streamed images paint without filling ImageCache or re-decoding unchanged frames',
    (t) async {
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final initialCache = PaintingBinding.instance.imageCache.currentSize;
      Future<Uint8List> png(Color color) async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(4, 3);
        picture.dispose();
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List();
        } finally {
          image.dispose();
        }
      }

      final red = (await t.runAsync(() => png(Colors.red)))!;
      final blue = (await t.runAsync(() => png(Colors.blue)))!;
      var decoded = 0, painted = 0;
      var ready = Completer<void>();
      Future<void> waitDecoded() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (!ready.isCompleted) {
          if (DateTime.now().isAfter(deadline))
            fail('Image codec did not complete.');
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await t.pump();
        }
      }

      Widget view(Uint8List bytes) => MaterialApp(
        home: Scaffold(
          body: RemoteVideo(
            bytes: bytes,
            touchEnabled: false,
            onTouch: (_) {},
            onDisplayed: () => painted++,
            onDecoded: (_) {
              decoded++;
              if (!ready.isCompleted) ready.complete();
            },
          ),
        ),
      );
      await t.pumpWidget(view(red));
      await waitDecoded();
      await t.pump();
      expect(decoded, 1);
      expect(painted, 1);
      await t.pumpWidget(view(red));
      await t.pump();
      expect(decoded, 1);
      ready = Completer<void>();
      await t.pumpWidget(view(blue));
      await waitDecoded();
      await t.pump();
      final raw = t.widget<RawImage>(find.byType(RawImage));
      final pixels = await t.runAsync(() => raw.image!.toByteData());
      expect(
        pixels!.getUint8(2),
        (Colors.blue.b * 255).round(),
      ); // Actual decoded/painted source is blue.
      expect(decoded, 2);
      expect(painted, 2);
      expect(PaintingBinding.instance.imageCache.currentSize, initialCache);
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    },
  );
}
