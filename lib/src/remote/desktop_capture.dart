import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Linux/Windows use the already-bundled WebRTC window capturer. Native host
/// interop verifies process birth, executable, writer and the exact window ID.
class DesktopWindowCapture {
  DesktopWindowCapture({
    required this.problem,
    Future<Map<String, Object>?> Function(Map<String, Object>)? inspect,
    Future<List<DesktopCapturerSource>> Function()? windows,
    Future<MediaStream> Function(Map<String, dynamic>)? capture,
  }) : _query = inspect ?? _nativeTarget,
       _windows = windows ?? _nativeWindows,
       _capture = capture ?? _nativeCapture;
  static const _channel = MethodChannel('app.broomm/remote');
  final void Function(String) problem;
  final Future<Map<String, Object>?> Function(Map<String, Object>) _query;
  final Future<List<DesktopCapturerSource>> Function() _windows;
  final Future<MediaStream> Function(Map<String, dynamic>) _capture;
  static Future<Map<String, Object>?> _nativeTarget(
    Map<String, Object> target,
  ) => _channel.invokeMapMethod<String, Object>('captureTarget', target);
  static Future<List<DesktopCapturerSource>> _nativeWindows() =>
      desktopCapturer.getSources(types: [SourceType.Window]);
  static Future<MediaStream> _nativeCapture(Map<String, dynamic> constraints) =>
      navigator.mediaDevices.getDisplayMedia(constraints);
  Timer? _watch;
  bool _closed = false, _checking = false;
  Map<String, Object>? _target;

  Future<Map<String, Object>> _inspect(Map<String, Object> target) async {
    final value = await _query(target).timeout(const Duration(seconds: 2));
    final window = value?['window'];
    if (window is! int || window <= 0)
      throw StateError('The emulator window could not be verified.');
    if (target['window'] != null && target['window'] != window)
      throw StateError('The verified emulator window was replaced.');
    return {...target, 'window': window};
  }

  Future<MediaStream> open(Map<String, Object> target) async {
    if (_closed) throw StateError('Capture cancelled.');
    final verified = await _inspect(target);
    if (_closed) throw StateError('Capture cancelled.');
    final sources = await _windows().timeout(const Duration(seconds: 5));
    final matches = sources
        .where(
          (source) =>
              source.type == SourceType.Window &&
              source.id == '${verified['window']}',
        )
        .toList();
    if (matches.length != 1)
      throw StateError(
        'The verified emulator window is not available to WebRTC. Check desktop capture permissions and Retry screen.',
      );
    await _inspect(verified);
    if (_closed) throw StateError('Capture cancelled.');
    final stream = await _capture({
      'audio': false,
      'video': {
        'deviceId': {'exact': matches.single.id},
        'mandatory': {'frameRate': 60.0},
        'cursor': 'never',
      },
    });
    try {
      if (_closed) throw StateError('Capture cancelled.');
      await _inspect(verified);
      if (_closed) throw StateError('Capture cancelled.');
      _target = verified;
      _watch = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => unawaited(_verify()),
      );
      return stream;
    } catch (_) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop().timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
      try {
        await stream.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {
        /* Preserve the capture failure. */
      }
      rethrow;
    }
  }

  Future<void> _verify() async {
    if (_closed || _checking || _target == null) return;
    _checking = true;
    try {
      await _inspect(_target!);
    } catch (_) {
      if (!_closed) {
        close();
        problem(
          'The emulator window or its process changed. Use Retry screen.',
        );
      }
    } finally {
      _checking = false;
    }
  }

  void close() {
    _closed = true;
    _watch?.cancel();
    _watch = null;
    _target = null;
  }
}
