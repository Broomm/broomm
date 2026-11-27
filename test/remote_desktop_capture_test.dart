import 'dart:async';

import 'package:broomm/src/remote/desktop_capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WindowSource implements DesktopCapturerSource {
  WindowSource(this.id, this.name, this.type);
  @override
  final String id, name;
  @override
  final SourceType type;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CaptureTrack implements MediaStreamTrack {
  int stops = 0;
  @override
  Future<void> stop() async {
    ++stops;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CaptureStream implements MediaStream {
  final track = CaptureTrack();
  int disposals = 0;
  @override
  List<MediaStreamTrack> getTracks() => [track];
  @override
  Future<void> dispose() async {
    ++disposals;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const target = <String, Object>{'pid': 123, 'birth': '456', 'name': 'Cemu'};
void main() {
  test('desktop capture selects the verified native window ID instead of a matching title or monitor', () async {
    final stream = CaptureStream();
    final inspected = <Map<String, Object>>[];
    Map<String, dynamic>? constraints;
    final capture = DesktopWindowCapture(
      problem: fail,
      inspect: (value) async {
        inspected.add(Map.of(value));
        return {'window': 42};
      },
      windows: () async => [
        WindowSource('42', 'Desktop', SourceType.Screen),
        WindowSource('99', 'GamePad View', SourceType.Window),
        WindowSource('42', 'Different display title', SourceType.Window),
      ],
      capture: (value) async {
        constraints = value;
        return stream;
      },
    );
    try {
      expect(await capture.open(target), same(stream));
      expect(inspected.map((v) => v['window']), [null, 42, 42]);
      expect(constraints!['audio'], false);
      expect((constraints!['video'] as Map)['deviceId'], {'exact': '42'});
      expect(stream.disposals, 0); // Ownership passes to the RTC session.
    } finally {
      capture.close();
      await stream.dispose();
    }
  });
  test('desktop capture cancellation disposes a late native stream and starts no watcher', () async {
    final requested = Completer<void>(), pending = Completer<MediaStream>();
    final stream = CaptureStream();
    var problems = 0;
    final capture = DesktopWindowCapture(
      problem: (_) => problems++,
      inspect: (_) async => {'window': 42},
      windows: () async => [
        WindowSource('42', 'GamePad View', SourceType.Window),
      ],
      capture: (_) {
        requested.complete();
        return pending.future;
      },
    );
    final opening = capture.open(target);
    final rejected = expectLater(opening, throwsStateError);
    await requested.future;
    capture.close();
    pending.complete(stream);
    await rejected;
    expect(stream.track.stops, 1);
    expect(stream.disposals, 1);
    expect(problems, 0);
  });
  test('replacement of the native window during acquisition releases media instead of publishing another window', () async {
    final stream = CaptureStream();
    var inspections = 0;
    final capture = DesktopWindowCapture(
      problem: fail,
      inspect: (_) async => {'window': ++inspections == 3 ? 43 : 42},
      windows: () async => [
        WindowSource('42', 'GamePad View', SourceType.Window),
      ],
      capture: (_) async => stream,
    );
    try {
      await expectLater(capture.open(target), throwsStateError);
      expect(stream.track.stops, 1);
      expect(stream.disposals, 1);
    } finally {
      capture.close();
    }
  });
}
