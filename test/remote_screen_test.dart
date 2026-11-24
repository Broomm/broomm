import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:broomm/src/remote/connection.dart';

import 'package:broomm/src/remote/protocol.dart';
import 'package:broomm/src/remote/history.dart';
import 'package:broomm/src/remote/layout.dart';
import 'package:broomm/src/remote/service.dart';
import 'package:broomm/src/emulators.dart';
import 'package:broomm/src/shell/remote_screen.dart';
import 'package:broomm/src/shell/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-remote-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          RemoteScreenService.channel,
          (_) async => null,
        );
  });
  tearDown(() async {
    await root.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(RemoteScreenService.channel, null);
  });

  test('connection addresses handle IPv4 IPv6 and reject unrelated URLs', () {
    expect(RemoteAddress.parse('192.168.1.20').label, '192.168.1.20:43187');
    expect(RemoteAddress.parse('[::1]:43200').uri.host, '::1');
    for (final value in [
      'http://example.com',
      'ws://user@host',
      'host:70000',
      'host/path',
      'host?secret=x',
      'x\u0000',
    ]) {
      expect(
        () => RemoteAddress.parse(value),
        throwsFormatException,
        reason: value,
      );
    }
    expect(
      () => RemotePad.read({
        'buttons': 0,
        'axes': [0, 0, 0, 0, -1, 0],
      }),
      throwsFormatException,
    );
    expect(
      RemotePad.read({
        'buttons': 5,
        'axes': [-32768, 32767, 0, 0, 0, 32767],
      }).buttons,
      5,
    );
  });

  test(
    'successful hosts persist recent order and bounded history across restarts',
    () async {
      final history = RemoteHistory(root);
      await history.load();
      final originalCode = history.code;
      for (var i = 1; i <= 14; i++) {
        await history.remember(
          RemoteAddress.parse('192.168.1.$i:43187'),
          '0123456789abcdef',
        );
      }
      await history.remember(
        RemoteAddress.parse('192.168.1.8:43187'),
        'fedcba9876543210',
      );
      final reopened = RemoteHistory(root);
      await reopened.load();
      expect(reopened.code, originalCode);
      expect(reopened.hosts.length, 12);
      expect(reopened.hosts.first, {
        'address': '192.168.1.8:43187',
        'code': 'fedcba9876543210',
      });
      expect(reopened.hosts.map((h) => h['address']).toSet().length, 12);
    },
  );

  test('remote layout restores only its keys after interruption', () async {
    final e = PreparedEmulator(
      'melonDS',
      root.path,
      '/not-launched',
      2,
      null,
      null,
      userDirectory: '${root.path}/launcher/portable',
    );
    await Directory(e.user).create(recursive: true);
    final file = RemoteLayout.config(e);
    await file.writeAsString(
      '[Instance0.Window0]\nScreenSizing = 2\nScreenRotation = 1\n',
    );
    e.remoteScreen = true;
    await RemoteLayout.prepare(e);
    await file.writeAsString(
      '[Instance0.Window0]\nScreenSizing = 4\nScreenRotation = 3\n[Instance0.Window1]\nEnabled = true\nScreenSizing = 5\n',
    );
    // A new session recovers the durable record before preparing its own layout.
    e.remoteScreen = false;
    await RemoteLayout.prepare(e);
    expect(await file.readAsString(), contains('ScreenSizing = 2'));
    expect(await file.readAsString(), contains('ScreenRotation = 3'));
    expect(await file.readAsString(), isNot(contains('Enabled = true')));
    expect(await RemoteLayout.journal(e).exists(), false);
  });

  test(
    'Azahar layout restores default flags and preserves unrelated preferences',
    () async {
      final e = PreparedEmulator(
        'Azahar',
        root.path,
        '/not-launched',
        2,
        null,
        null,
      );
      await Directory('${e.user}/config').create(recursive: true);
      final file = RemoteLayout.config(e);
      await file.writeAsString(
        '[Layout]\nlayout_option=2\nlayout_option\\default=true\n',
      );
      e.remoteScreen = true;
      await RemoteLayout.prepare(e);
      await file.writeAsString(
        '[Layout]\nlayout_option=4\nlayout_option\\default=false\nswap_screen=false\n[Renderer]\nresolution_factor=3\n',
      );
      await RemoteLayout.restore(e);
      expect(await file.readAsString(), contains('layout_option=2'));
      expect(
        await file.readAsString(),
        contains('layout_option\\default=true'),
      );
      expect(await file.readAsString(), contains('resolution_factor=3'));
      expect(await file.readAsString(), isNot(contains('swap_screen=')));
    },
  );

  test('LAN authentication gates controls and successful connections survive service restart', () async {
    final actions = <String>[];
    var hostClock = 0;
    final host = RemoteScreenService(
      root,
      hostEnabled: true,
      listenPort: 0,
      onAction: actions.add,
      monotonicMillis: () => hostClock,
    );
    final clientRoot = await root.createTemp('client-');
    final client = RemoteScreenService(
      clientRoot,
      hostEnabled: false,
      monotonicMillis: () => 0,
    );
    await host.start();
    await client.start();
    try {
      expect(host.port, isNotNull, reason: host.error);
      final previousEndpoint = host.newInputSocket()!;
      await File(previousEndpoint).writeAsString('stale endpoint');
      expect(host.newInputSocket(), isNot(previousEndpoint));
      final discovery = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final reply = Completer<Datagram>();
      discovery.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = discovery.receive();
        if (packet != null && !reply.isCompleted) reply.complete(packet);
      });
      discovery.send(
        utf8.encode('BROOMM_DISCOVER1'),
        InternetAddress.loopbackIPv4,
        host.port!,
      );
      final packet = await reply.future.timeout(const Duration(seconds: 2));
      expect(jsonDecode(utf8.decode(packet.data))['port'], host.port);
      discovery.close();
      final address = '127.0.0.1:${host.port}';
      await client.connect(address, 'wrong-code');
      expect(client.connected, false);
      expect(client.history.hosts, isEmpty);
      expect(actions, isEmpty);
      await client.connect(address, host.history.code);
      expect(client.connected, true, reason: client.error);
      client.action('accept');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(actions, contains('accept'));
      final history = RemoteHistory(clientRoot);
      await history.load();
      expect(history.hosts.first['address'], address);
      final disconnected = Completer<void>();
      client.addListener(() {
        if (!client.connected && !disconnected.isCompleted)
          disconnected.complete();
      });
      hostClock = 1000;
      client.action('back');
      await disconnected.future.timeout(const Duration(seconds: 2));
      expect(actions, isNot(contains('back')));
      await client.disconnect();
      expect(host.hasGuest, false);
    } finally {
      await client.close();
      await host.close();
    }
  });

  test(
    'transport rejects an oversized length before allocating its payload',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final connected = Socket.connect('127.0.0.1', server.port);
      final accepted = await server.first;
      final socket = await connected;
      final peer = RemoteConnection(accepted);
      final error = Completer<Object>();
      peer.listen(
        (_) => fail('Oversized frame was delivered'),
        onError: (Object e) => error.complete(e),
      );
      final header = Uint8List(5)..[0] = 1;
      ByteData.sublistView(header).setUint32(1, 1024 * 1024 + 1);
      socket.add(header);
      await socket.flush();
      expect(
        await error.future.timeout(const Duration(seconds: 2)),
        isA<FormatException>(),
      );
      socket.destroy();
      await peer.close();
      await server.close();
    },
  );

  testWidgets(
    'remote screen exposes both roles and controller editable connection fields',
    (t) async {
      t.view.physicalSize = const Size(360, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      final service = (await t.runAsync(() async {
        final service = RemoteScreenService(root, hostEnabled: false);
        await service.start();
        return service;
      }))!;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: ConsoleKeyboardHost(child: RemoteScreen(service: service)),
            ),
          ),
        ),
      );
      expect(find.text('Use this device as a host'), findsOneWidget);
      await t.runAsync(() async {
        await t.tap(find.text('Use this device as a remote screen'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await t.pump();
      expect(find.text('Host address'), findsOneWidget);
      expect(find.text('Connection code'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      final host = (await t.runAsync(() async {
        final host = RemoteScreenService(
          await root.createTemp('host-'),
          hostEnabled: true,
          listenPort: 0,
        );
        await host.start();
        await service.connect('127.0.0.1:${host.port}', host.history.code);
        return host;
      }))!;
      await t.pump();
      expect(
        find.text('Waiting for a compatible emulator to be launched.'),
        findsOneWidget,
      );
      expect(find.text('Disconnect'), findsOneWidget);
      expect(t.takeException(), isNull);
      if (Platform.environment['BROOMM_REMOTE_PREVIEW'] == '1') {
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('.tool-cache/research/remote-screen');
          await dir.create(recursive: true);
          await File('${dir.path}/waiting.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.runAsync(service.disconnect);
      await t.runAsync(host.close);

      await t.pumpWidget(const SizedBox());
      await t.runAsync(service.close);
    },
  );
}
