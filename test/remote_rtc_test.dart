import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/remote/connection.dart';
import 'package:broomm/src/remote/rtc_video.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class HeldPeer implements RTCPeerConnection {
  int closes = 0, disposals = 0;
  @override
  Future<void> close() async {
    closes++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('video descriptions have a distinct bounded transport without weakening control limits', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = server.first;
    final outgoing = RemoteConnection(
      await Socket.connect('127.0.0.1', server.port),
    );
    final incoming = RemoteConnection(await accepted);
    final received = incoming.first;
    final description = jsonEncode({
      'id': 1,
      'type': 'offer',
      'sdp': 'v=0\r\n${'x' * 8000}',
    });
    try {
      outgoing.add(RemoteSignal(description));
      final signal = await received.timeout(const Duration(seconds: 2));
      expect(signal, isA<RemoteSignal>());
      expect(readVideoSignal(signal as RemoteSignal)['sdp'], contains('v=0'));
    } finally {
      await outgoing.close();
      await incoming.close();
      await server.close();
    }
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peer = listener.first;
    final raw = await Socket.connect('127.0.0.1', listener.port);
    final bounded = RemoteConnection(await peer);
    final rejected = expectLater(bounded, emitsError(isA<FormatException>()));
    raw.add([2, 0, 1, 0, 1]); // 65,537 bytes: reject before allocating payload.
    await raw.flush();
    await rejected;
    await bounded.close();
    raw.destroy();
    await listener.close();
  });

  test('signaling validates sessions and media diagnostics reject non-finite or log-injected data', () {
    expect(
      readVideoSignal(
        const RemoteSignal(
          '{"id":1,"type":"candidate","candidate":"candidate:1","mid":"0","line":0}',
        ),
      )['id'],
      1,
    );
    for (final value in [
      {'id': 0, 'type': 'offer', 'sdp': 'v=0'},
      {'id': 1, 'type': 'offer', 'sdp': 'x' * 60001},
      {'id': 1, 'type': 'candidate', 'candidate': 'x', 'line': -1},
      {'id': 1, 'type': 'unexpected'},
    ]) {
      expect(
        () => readVideoSignal(RemoteSignal(jsonEncode(value))),
        throwsFormatException,
      );
    }
    final report = <String, Object>{
      'role': 'receive',
      'fps': 60,
      'width': 1440,
      'height': 1080,
      'codec': 'video/H264',
      'implementation': 'MediaCodec',
      'dropped': 0,
      'lost': 0,
    };
    expect(formatVideoReport(readVideoReport(report)), contains('1440x1080'));
    expect(
      () => readVideoReport({...report, 'fps': double.nan}),
      throwsFormatException,
    );
    expect(
      () => readVideoReport({...report, 'implementation': 'codec\nforged log'}),
      throwsFormatException,
    );
  });

  test('cancelled peer acquisition disposes its eventual native handle without starting capture', () async {
    final ready = Completer<RTCPeerConnection>();
    final peer = HeldPeer();
    var captures = 0;
    final errors = <String>[];
    final video = RemoteRtcVideo(
      id: 1,
      sender: true,
      send: (_) {},
      changed: () {},
      problem: errors.add,
      openPeer: () => ready.future,
    );
    final starting = video.startSender((_) async {
      captures++;
    });
    final failed = expectLater(starting, throwsStateError);
    await video.close();
    ready.complete(peer);
    await failed;
    await Future<void>.delayed(Duration.zero);
    expect(captures, 0);
    expect(peer.closes, 1);
    expect(peer.disposals, 1);
    expect(errors, isEmpty);
  });
}
