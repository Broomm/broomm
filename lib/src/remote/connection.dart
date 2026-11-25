import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// WebRTC descriptions/ICE use a separately bounded, negotiated message kind.
class RemoteSignal {
  const RemoteSignal(this.text);
  final String text;
}

/// Length-prefixed messages are bounded before allocation. A slow peer cannot
/// build an unbounded input or video queue in either Broomm instance.
class RemoteConnection extends Stream<Object> {
  RemoteConnection(this.socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    _messages = StreamController<Object>(
      sync: true,
      onPause: () => _subscription.pause(),
      onResume: () => _subscription.resume(),
    );
    _subscription = socket.listen(
      _read,
      onError: (Object error, StackTrace stack) {
        if (!_closed) _messages.addError(error, stack);
        unawaited(close());
      },
      onDone: () => unawaited(close()),
    );
  }
  final Socket socket;
  late final StreamController<Object> _messages;
  late final StreamSubscription<Uint8List> _subscription;
  final _header = Uint8List(5);
  int _headerUsed = 0, _used = 0, _kind = 0;
  Uint8List? _payload;
  final Queue<({Uint8List data, Completer<void>? sent})> _output = Queue();
  Completer<void>? _activeWrite;
  bool _sending = false, _closed = false;

  @override
  StreamSubscription<Object> listen(
    void Function(Object)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _messages.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  void _read(Uint8List chunk) {
    var offset = 0;
    try {
      while (offset < chunk.length && !_closed) {
        if (_payload == null) {
          final count = (5 - _headerUsed).clamp(0, chunk.length - offset);
          _header.setRange(_headerUsed, _headerUsed + count, chunk, offset);
          offset += count;
          _headerUsed += count;
          if (_headerUsed < 5) return;
          final size = ByteData.sublistView(_header).getUint32(1);
          _kind = _header[0];
          if ((_kind != 0 && _kind != 1 && _kind != 2) ||
              size == 0 ||
              size >
                  (_kind == 0
                      ? 2048
                      : _kind == 2
                      ? 65536
                      : 1024 * 1024)) {
            throw const FormatException(
              'Remote message exceeds its size limit.',
            );
          }
          _payload = Uint8List(size);
          _used = 0;
        }
        final payload = _payload!;
        final count = (payload.length - _used).clamp(0, chunk.length - offset);
        payload.setRange(_used, _used + count, chunk, offset);
        offset += count;
        _used += count;
        if (_used == payload.length) {
          _payload = null;
          _headerUsed = 0;
          _messages.add(
            _kind == 0
                ? utf8.decode(payload)
                : _kind == 2
                ? RemoteSignal(utf8.decode(payload))
                : payload,
          );
        }
      }
    } catch (e, stack) {
      _messages.addError(e, stack);
      unawaited(close());
    }
  }

  void add(Object value) => _enqueue(value, null);

  /// Completion bounds the encoder by the socket writer, not remote painting.
  Future<void> sendFrame(Uint8List bytes) {
    final sent = Completer<void>();
    _enqueue(bytes, sent);
    return sent.future;
  }

  Future<void> sendSignal(RemoteSignal signal) {
    final sent = Completer<void>();
    _enqueue(signal, sent);
    return sent.future;
  }

  void _enqueue(Object value, Completer<void>? sent) {
    if (_closed) {
      sent?.completeError(StateError('Remote connection closed.'));
      return;
    }
    final text = value is String;
    final signal = value is RemoteSignal;
    final bytes = text
        ? utf8.encode(value)
        : signal
        ? utf8.encode(value.text)
        : value as List<int>;
    if (bytes.isEmpty ||
        bytes.length >
            (text
                ? 2048
                : signal
                ? 65536
                : 1024 * 1024) ||
        _output.length >= 32) {
      sent?.completeError(StateError('Remote write exceeded its limit.'));
      unawaited(close());
      return;
    }
    final data = Uint8List(5 + bytes.length);
    data[0] = text
        ? 0
        : signal
        ? 2
        : 1;
    ByteData.sublistView(data).setUint32(1, bytes.length);
    data.setRange(5, data.length, bytes);
    _output.add((data: data, sent: sent));
    if (!_sending) unawaited(_write());
  }

  Future<void> _write() async {
    _sending = true;
    try {
      while (_output.isNotEmpty && !_closed) {
        final next = _output.removeFirst();
        _activeWrite = next.sent;
        socket.add(next.data);
        await socket.flush().timeout(const Duration(seconds: 2));
        if (next.sent?.isCompleted == false) next.sent!.complete();
        _activeWrite = null;
      }
    } catch (_) {
      await close();
    } finally {
      _sending = false;
    }
  }

  Future<void> close([int? code, String? reason]) async {
    if (_closed) return;
    _closed = true;
    if (_activeWrite?.isCompleted == false)
      _activeWrite!.completeError(StateError('Remote connection closed.'));
    for (final pending in _output) {
      if (pending.sent?.isCompleted == false)
        pending.sent!.completeError(StateError('Remote connection closed.'));
    }
    _output.clear();
    socket.destroy();
    await _subscription.cancel();
    unawaited(_messages.close());
  }
}
