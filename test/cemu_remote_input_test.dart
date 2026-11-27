import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broomm/src/remote/cemu_input.dart';
import 'package:broomm/src/remote/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _hex(String text) => Uint8List.fromList([
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
]);
// Independently generated DSU client packets, CRC32 cross-checked with zlib.
final _version = _hex('44535543e9030400e4f70ac80403020100001000');
final _info = _hex('44535543e903090040cd431304030201010010000100000000');
final _data = _hex('44535543e9030c00d8c84d2204030201020010000100000000000000');

Uint8List _seal(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  view.setUint32(8, 0, Endian.little);
  view.setUint32(8, dsuCrc32(bytes), Endian.little);
  return bytes;
}

class _CemuPeer {
  _CemuPeer(this.socket, this.port) {
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      for (Datagram? packet; (packet = socket.receive()) != null;) {
        frames.add(packet!.data);
      }
    });
  }
  final RawDatagramSocket socket;
  final int port;
  final frames = StreamController<Uint8List>.broadcast();
  Future<Uint8List> query(Uint8List request, int kind, {int? at}) {
    final response = frames.stream.firstWhere(
      (bytes) =>
          ByteData.sublistView(bytes).getUint32(16, Endian.little) == kind &&
          (at == null ||
              ByteData.sublistView(bytes).getUint64(68, Endian.little) ==
                  at * 1000),
    );
    socket.send(request, InternetAddress.loopbackIPv4, port);
    return response.timeout(const Duration(seconds: 2));
  }

  Future<void> close() async {
    socket.close();
    await frames.close();
  }
}

void _valid(Uint8List bytes, int length) {
  expect(bytes.length, length);
  expect(ascii.decode(bytes.sublist(0, 4)), 'DSUS');
  final view = ByteData.sublistView(bytes);
  expect(view.getUint16(4, Endian.little), 1001);
  expect(view.getUint16(6, Endian.little), length - 16);
  final checked = Uint8List.fromList(bytes);
  ByteData.sublistView(checked).setUint32(8, 0, Endian.little);
  expect(view.getUint32(8, Endian.little), dsuCrc32(checked));
}

void main() {
  late CemuRemoteInput server;
  late _CemuPeer peer;
  var now = 0;
  setUp(() async {
    now = 0;
    server = CemuRemoteInput(milliseconds: () => now);
    await server.start();
    peer = _CemuPeer(
      await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0),
      server.port!,
    );
  });
  tearDown(() async {
    await server.close();
    await peer.close();
  });

  test('Cemu DSU requests read buttons, analog extremes and GamePad touch without an OS device', () async {
    expect(dsuCrc32(ascii.encode('123456789')), 0xcbf43926);
    _valid(await peer.query(_version, 0x100000), 24);
    server.pad(
      const RemotePad((1 << 0) | (1 << 1) | (1 << 9) | (1 << 11), [
        -32768,
        32767,
        32767,
        -32768,
        32767,
        0,
      ]),
      true,
    );
    server.touch(const RemoteTouch(true, 853, 479));
    final info = await peer.query(_info, 0x100001);
    _valid(info, 32);
    expect(info[21], 2);
    final state = await peer.query(_data, 0x100002, at: now);
    _valid(state, 100);
    expect(state[36], 1 << 4); // Up.
    expect(
      state[37],
      1 | (1 << 2) | (1 << 5) | (1 << 6),
    ); // ZL, L, east, south.
    expect(state.sublist(40, 44), [0, 0, 255, 255]);
    expect(state.sublist(54, 56), [0, 255]);
    expect(state[56], 1);
    final view = ByteData.sublistView(state);
    expect(view.getUint16(58, Endian.little), 1920);
    expect(view.getUint16(60, Endian.little), 942);

    final other = _CemuPeer(
      await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0),
      server.port!,
    );
    try {
      await other.query(_data, 0x100002, at: now);
      // Both subscriptions receive the same periodic sample with a valid CRC.
      now = 1;
      final next = peer.frames.stream.firstWhere(
        (v) => ByteData.sublistView(v).getUint64(68, Endian.little) == 1000,
      );
      final second = other.frames.stream.firstWhere(
        (v) => ByteData.sublistView(v).getUint64(68, Endian.little) == 1000,
      );
      for (final sample in await Future.wait([
        next,
        second,
      ]).timeout(const Duration(seconds: 2))) {
        _valid(sample, 100);
      }
    } finally {
      await other.close();
    }
  });

  test('bad CRC, truncated packets, unsupported versions and invalid indices do not receive data', () async {
    final seen = <Uint8List>[];
    final observation = peer.frames.stream.listen(seen.add);
    try {
      for (final packet in [
        Uint8List.fromList(_version)..[8] ^= 1,
        Uint8List.fromList(_version.sublist(0, 19)),
        _seal(Uint8List.fromList(_info)..[24] = 5),
        _seal(Uint8List.fromList(_version)..[4] = 0),
        _seal(Uint8List.fromList(_data)..[20] = 4),
      ]) {
        peer.socket.send(packet, InternetAddress.loopbackIPv4, server.port!);
      }
      final valid = await peer.query(_info, 0x100001);
      _valid(valid, 32);
      expect(seen.length, 1);
      expect(valid[21], 0);
    } finally {
      await observation.cancel();
    }
  });

  test('quick taps span a sample, stale input releases, and closing frees the exact UDP port', () async {
    server.pad(const RemotePad(1, [0, 0, 0, 0, 0, 0]), true);
    server.touch(const RemoteTouch(true, 100, 50));
    server.touch(RemoteTouch.released);
    expect((await peer.query(_data, 0x100002, at: now))[56], 1);
    now = 21;
    expect((await peer.query(_data, 0x100002, at: now))[56], 0);
    now = 351;
    final stale = await peer.query(_data, 0x100002, at: now);
    expect(stale[21], 0);
    expect(stale.sublist(36, 40), [0, 0, 0, 0]);
    expect(stale[56], 0);
    final port = server.port!;
    await server.close();
    final replacement = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
    );
    replacement.close();
  });
}
