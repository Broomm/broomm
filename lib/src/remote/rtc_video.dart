import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'connection.dart';

/// Descriptions and candidates are accepted only over the authenticated link.
/// Never log their contents: they contain connection credentials and addresses.
Map<String, dynamic> readVideoSignal(RemoteSignal signal) {
  if (signal.text.length > 65536)
    throw const FormatException('Video signal too large.');
  final value = jsonDecode(signal.text);
  if (value is! Map<String, dynamic> ||
      value['id'] is! int ||
      value['id'] < 1 ||
      value['id'] > 0x7fffffff) {
    throw const FormatException('Invalid video session.');
  }
  switch (value['type']) {
    case 'offer':
    case 'answer':
      final sdp = value['sdp'];
      if (sdp is! String ||
          sdp.isEmpty ||
          sdp.length > 60000 ||
          sdp.contains('\u0000')) {
        throw const FormatException('Invalid video description.');
      }
    case 'candidate':
      final candidate = value['candidate'],
          mid = value['mid'],
          line = value['line'];
      if (candidate is! String ||
          candidate.length > 4096 ||
          candidate.contains('\u0000') ||
          (mid != null && (mid is! String || mid.length > 128)) ||
          (line != null && (line is! int || line < 0 || line > 32))) {
        throw const FormatException('Invalid video candidate.');
      }
    default:
      throw const FormatException('Unknown video signal.');
  }
  return value;
}

Map<String, Object> readVideoReport(Object? value) {
  if (value is! Map || !{'send', 'receive'}.contains(value['role'])) {
    throw const FormatException('Invalid video statistics.');
  }
  final result = <String, Object>{'role': value['role']};
  for (final key in ['fps', 'width', 'height', 'dropped', 'lost']) {
    final number = value[key];
    final max = key == 'fps'
        ? 240
        : {'width', 'height'}.contains(key)
        ? 8192
        : 0x7fffffff;
    if (number is! num || !number.isFinite || number < 0 || number > max) {
      throw const FormatException('Invalid video statistics.');
    }
    result[key] = number;
  }
  for (final key in ['codec', 'implementation']) {
    final text = value[key];
    if (text is! String ||
        !RegExp(r'^[a-zA-Z0-9_ ./+():-]{1,120}$').hasMatch(text)) {
      throw const FormatException('Invalid video statistics.');
    }
    result[key] = text;
  }
  return result;
}

String formatVideoReport(Map<String, Object> value) =>
    'Remote WebRTC ${value['role']}: ${(value['fps'] as num).toStringAsFixed(1)} fps, '
    '${value['width']}x${value['height']}, ${value['codec']}, implementation ${value['implementation']}, '
    'dropped ${value['dropped']}, lost ${value['lost']}';

Future<RTCPeerConnection> defaultVideoPeer() => createPeerConnection({
  'iceServers': <Object>[],
  'sdpSemantics': 'unified-plan',
  'bundlePolicy': 'max-bundle',
});

/// One video-only peer. Broomm owns authentication, capture identity and input;
/// libwebrtc owns media transport, codec negotiation and native rendering.
class RemoteRtcVideo {
  RemoteRtcVideo({
    required this.id,
    required this.sender,
    required this.send,
    required this.changed,
    required this.problem,
    this.event,
    this.report,
    this.openPeer = defaultVideoPeer,
  });
  final Future<RTCPeerConnection> Function() openPeer;
  final int id;
  final bool sender;
  final FutureOr<void> Function(RemoteSignal) send;
  final void Function() changed;
  final void Function(String) problem;
  final void Function(String)? event;
  final void Function(Map<String, Object>)? report;
  RTCPeerConnection? _peer;
  MediaStream? _local, _remote;
  RTCVideoRenderer? renderer;
  bool firstFrame = false,
      _closed = false,
      _remoteSet = false,
      _statsBusy = false;
  final _candidates = <RTCIceCandidate>[];
  final _localCandidates = <Map<String, dynamic>>[];
  bool _localAnnounced = false;
  Future<void> _signals = Future.value(), _outgoing = Future.value();
  int _queuedSignals = 0;
  int _pending = 0;
  Timer? _deadline, _stats;
  final _previous = <String, (double, double)>{};
  final _clock = Stopwatch()..start();

  Future<T> _acquire<T>(
    Future<T> work,
    Future<void> Function(T) release,
  ) async {
    var abandoned = false;
    unawaited(
      work.then((value) async {
        if (abandoned || _closed) await release(value);
      }, onError: (Object _) {}),
    );
    try {
      final value = await work.timeout(const Duration(seconds: 10));
      if (_closed) throw StateError('Video session cancelled.');
      return value;
    } catch (_) {
      abandoned = true;
      rethrow;
    }
  }

  Future<void> _createPeer() async {
    _peer = await _acquire<RTCPeerConnection>(openPeer(), _releasePeer);
    if (_closed) {
      await _releasePeer(_peer!);
      _peer = null;
      throw StateError('Video cancelled.');
    }
    final peer = _peer!;
    peer.onIceCandidate = (candidate) {
      if (!_closed && candidate.candidate?.isNotEmpty == true) {
        final value = <String, dynamic>{
          'type': 'candidate',
          'candidate': candidate.candidate,
          'mid': candidate.sdpMid,
          'line': candidate.sdpMLineIndex,
        };
        if (_localAnnounced) {
          _send(value);
        } else if (_localCandidates.length < 64) {
          _localCandidates.add(value);
        } else {
          _fail('Too many video candidates. Reconnect.');
        }
      }
    };
    peer.onConnectionState = (state) {
      if (!_closed &&
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _fail('Video connection failed. Use Retry screen.');
      }
    };
    if (!sender) {
      final view = RTCVideoRenderer();
      await _acquire(view.initialize().then((_) => view), (r) => r.dispose());
      if (_closed) {
        await view.dispose();
        throw StateError('Video cancelled.');
      }
      renderer = view;
      view.onFirstFrameRendered = () {
        if (_closed) return;
        firstFrame = true;
        _deadline?.cancel();
        changed();
      };
      peer.onTrack = (track) {
        if (_closed || track.track.kind != 'video' || track.streams.isEmpty)
          return;
        _remote = track.streams.first;
        unawaited(
          view.setSrcObject(stream: _remote).catchError((Object _) {
            if (!_closed) _fail('Video display failed. Use Retry screen.');
          }),
        );
      };
      _deadline = Timer(const Duration(seconds: 15), () {
        if (!_closed && !firstFrame)
          _fail('No video frames received. Use Retry screen.');
      });
      changed();
    }
    _stats = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_report()),
    );
  }

  Future<void> startSender(Future<void> Function(MediaStream) capture) async {
    try {
      await _createPeer();
      _local = await _acquire<MediaStream>(
        createLocalMediaStream('Broomm secondary screen'),
        (s) => s.dispose(),
      );
      if (_closed) {
        await _local!.dispose();
        _local = null;
        return;
      }
      await capture(_local!);
      if (_closed) return;
      // The pinned native bridge attaches the track after stream creation.
      // ignore: deprecated_member_use
      await _local!.getMediaTracks();
      if (_closed) return;
      final tracks = _local!.getVideoTracks();
      if (tracks.length != 1)
        throw StateError('The captured video track is unavailable.');
      final transceiver = await _peer!.addTransceiver(
        track: tracks.single,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.SendOnly,
          streams: [_local!],
          sendEncodings: [
            RTCRtpEncoding(
              maxBitrate: 20000000,
              maxFramerate: 60,
              scaleResolutionDownBy: 1.0,
            ),
          ],
        ),
      );
      final capabilities = await getRtpSenderCapabilities('video');
      final codecs = capabilities.codecs ?? [];
      final h264 = codecs
          .where((c) => c.mimeType.toLowerCase() == 'video/h264')
          .toList();
      if (h264.isNotEmpty) {
        await transceiver.setCodecPreferences([
          ...h264,
          ...codecs.where((c) => c.mimeType.toLowerCase() != 'video/h264'),
        ]);
      }
      if (_closed) return;
      final offer = await _peer!.createOffer({
        'offerToReceiveAudio': false,
        'offerToReceiveVideo': false,
      });
      await _peer!.setLocalDescription(offer);
      if (!_closed) _description('offer', offer.sdp);
    } catch (_) {
      if (!_closed) _fail('Could not start WebRTC video. Use Retry screen.');
      rethrow;
    }
  }

  void signal(Map<String, dynamic> message) {
    if (_closed || message['id'] != id) return;
    if (++_pending > 32) {
      _fail('Too many pending video messages. Reconnect.');
      return;
    }
    _signals = _signals
        .then((_) async {
          if (_closed) return;
          final type = message['type'];
          if (type == 'offer') {
            if (sender || _peer != null)
              throw StateError('Unexpected video offer.');
            await _createPeer();
          }
          final peer = _peer;
          if (type == 'candidate') {
            final candidate = RTCIceCandidate(
              message['candidate'],
              message['mid'],
              message['line'],
            );
            if (!_remoteSet) {
              if (_candidates.length >= 64)
                throw StateError('Too many video candidates.');
              _candidates.add(candidate);
            } else {
              await peer!.addCandidate(candidate);
            }
            return;
          }
          if (peer == null ||
              (sender && type != 'answer') ||
              (!sender && type != 'offer') ||
              _remoteSet) {
            throw StateError('Unexpected video description.');
          }
          await peer.setRemoteDescription(
            RTCSessionDescription(message['sdp'], type),
          );
          _remoteSet = true;
          for (final candidate in _candidates) {
            await peer.addCandidate(candidate);
          }
          _candidates.clear();
          if (type == 'offer' && !_closed) {
            final answer = await peer.createAnswer({
              'offerToReceiveAudio': false,
            });
            await peer.setLocalDescription(answer);
            if (!_closed) _description('answer', answer.sdp);
          }
        })
        .timeout(const Duration(seconds: 12))
        .catchError((Object _) {
          if (!_closed) _fail('Video negotiation failed. Use Retry screen.');
        })
        .whenComplete(() => _pending--);
  }

  void _description(String type, String? sdp) {
    _send({'type': type, 'sdp': sdp});
    _localAnnounced = true;
    for (final candidate in _localCandidates) {
      _send(candidate);
    }
    _localCandidates.clear();
  }

  void _send(Map<String, dynamic> value) {
    if (_closed) return;
    if (++_queuedSignals > 64) {
      _fail('Too many outgoing video messages. Reconnect.');
      return;
    }
    final signal = RemoteSignal(jsonEncode({'id': id, ...value}));
    _outgoing = _outgoing
        .then((_) async {
          if (!_closed)
            await Future.sync(() => send(signal))
                .timeout(const Duration(seconds: 2));
        })
        .catchError((Object _) {
          if (!_closed) _fail('Could not send video setup. Reconnect.');
        })
        .whenComplete(() => _queuedSignals--);
  }

  void _fail(String message) {
    if (_closed) return;
    problem(message);
    unawaited(close());
  }

  Future<void> _report() async {
    if (_closed || _statsBusy || _peer == null) return;
    _statsBusy = true;
    try {
      final reports = await _peer!.getStats().timeout(
        const Duration(seconds: 2),
      );
      if (_closed) return;
      final codecs = {
        for (final r in reports.where((r) => r.type == 'codec')) r.id: r.values,
      };
      for (final sample in reports) {
        final v = sample.values;
        if (!{'inbound-rtp', 'outbound-rtp'}.contains(sample.type) ||
            (v['kind'] ?? v['mediaType']) != 'video')
          continue;
        final count = v[sender ? 'framesEncoded' : 'framesDecoded'];
        if (count is! num) continue;
        final now = _clock.elapsedMilliseconds.toDouble();
        final previous = _previous[sample.id];
        _previous[sample.id] = (count.toDouble(), now);
        final fps = previous == null
            ? 'starting'
            : ((count - previous.$1) * 1000 / (now - previous.$2))
                  .toStringAsFixed(1);
        final codec = codecs[v['codecId']];
        final value = readVideoReport({
          'role': sender ? 'send' : 'receive',
          'fps': double.tryParse(fps) ?? 0,
          'width': v['frameWidth'] ?? 0,
          'height': v['frameHeight'] ?? 0,
          'codec': codec?['mimeType'] ?? 'unknown',
          'implementation':
              v[sender ? 'encoderImplementation' : 'decoderImplementation'] ??
              'unknown',
          'dropped': v['framesDropped'] ?? 0,
          'lost': v['packetsLost'] ?? 0,
        });
        event?.call(formatVideoReport(value));
        report?.call(value);
      }
    } catch (_) {
      /* Stats never interrupt video or controls. */
    } finally {
      _statsBusy = false;
    }
  }

  static Future<void> _releasePeer(RTCPeerConnection peer) async {
    try {
      await peer.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await peer.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void>? _closing;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _deadline?.cancel();
    _stats?.cancel();
    _candidates.clear();
    _localCandidates.clear();
    final peer = _peer;
    _peer = null;
    final view = renderer;
    renderer = null;
    if (peer != null) await _releasePeer(peer);
    for (final stream in [_local, _remote].whereType<MediaStream>()) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop().timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
      try {
        await stream.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    _local = _remote = null;
    if (view != null) {
      try {
        await view.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    changed();
  }
}
