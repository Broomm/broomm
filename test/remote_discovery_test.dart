import 'dart:async';
import 'dart:io';

import 'package:broomm/src/remote/service.dart';
import 'package:flutter_test/flutter_test.dart';

class DiscoverySocket extends Stream<RawSocketEvent>
    implements RawDatagramSocket {
  final events = StreamController<RawSocketEvent>();
  bool closed = false;
  @override
  bool broadcastEnabled = false;
  @override
  int send(List<int> buffer, InternetAddress address, int port) =>
      buffer.length;
  @override
  void close() {
    closed = true;
  }

  // Keep queued callbacks independently controllable after close, matching an
  // error already enqueued by the OS when a search is replaced.
  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => events.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('asynchronous no-route errors expose manual connection fallback without escaping', () async {
    final root = await Directory.systemTemp.createTemp('remote-discovery-');
    final socket = DiscoverySocket();
    final service = RemoteScreenService(
      root,
      hostEnabled: false,
      datagramSocket: (_) async => socket,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          RemoteScreenService.channel,
          (_) async => null,
        );
    try {
      await service.start();
      await service.discover();
      final reported = Completer<void>();
      service.addListener(() {
        if (service.discoveryError != null && !reported.isCompleted)
          reported.complete();
      });
      socket.events.addError(const SocketException('No route to host'));
      await reported.future.timeout(const Duration(seconds: 2));
      expect(service.discoveryError, contains('Enter the host address'));
      expect(service.error, isNull);
      expect(socket.closed, true);
      final replacement = DiscoverySocket();
      // The failure does not poison a subsequent discovery or service startup.
      final next = RemoteScreenService(
        await root.createTemp('next-'),
        hostEnabled: false,
        datagramSocket: (_) async => replacement,
      );
      try {
        await next.start();
        await next.discover();
        expect(next.discoveryError, isNull);
      } finally {
        await next.close();
        await replacement.events.close();
      }
    } finally {
      await service.close();
      await socket.events.close();
      await root.delete(recursive: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(RemoteScreenService.channel, null);
    }
  });
  test(
    'host advertisement failure preserves the active TCP connection',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'remote-advertisement-',
      );
      final socket = DiscoverySocket();
      final host = RemoteScreenService(
        root,
        hostEnabled: true,
        listenPort: 0,
        datagramSocket: (_) async => socket,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            RemoteScreenService.channel,
            (_) async => null,
          );
      final client = RemoteScreenService(
        await root.createTemp('client-'),
        hostEnabled: false,
      );
      try {
        await host.start();
        await client.start();
        await client.connect('127.0.0.1:${host.port}', host.history.code);
        expect(client.connected, true);
        socket.events.addError(
          const SocketException('Network became unreachable'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(host.discoveryError, isNotNull);
        expect(host.port, isNotNull);
        expect(host.hasGuest, true);
        expect(client.connected, true);
        expect(host.error, isNull);
      } finally {
        await client.close();
        await host.close();
        await socket.events.close();
        await root.delete(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(RemoteScreenService.channel, null);
      }
    },
  );
  test('a delayed error from the old search cannot close or report failure for the new search', () async {
    final root = await Directory.systemTemp.createTemp('remote-discovery-');
    final first = DiscoverySocket(), second = DiscoverySocket();
    var calls = 0;
    final service = RemoteScreenService(
      root,
      hostEnabled: false,
      datagramSocket: (_) async => calls++ == 0 ? first : second,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          RemoteScreenService.channel,
          (_) async => null,
        );
    try {
      await service.start();
      await service.discover();
      await service.discover();
      expect(first.closed, true);
      first.events.addError(const SocketException('Old search failed'));
      await Future<void>.delayed(Duration.zero);
      expect(second.closed, false);
      expect(service.discoveryError, isNull);
      second.events.addError(const SocketException('Current search failed'));
      await Future<void>.delayed(Duration.zero);
      expect(second.closed, true);
      expect(service.discoveryError, contains('Current search failed'));
    } finally {
      await service.close();
      await first.events.close();
      await second.events.close();
      await root.delete(recursive: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(RemoteScreenService.channel, null);
    }
  });
}
