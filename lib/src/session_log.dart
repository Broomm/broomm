import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

// One bounded logging worker per session. File I/O, rotation, output decoding
// and escape removal never run on Flutter's UI isolate.
class SessionLog {
  SessionLog(this.path, {this.onProblem, this.source = 'session.dart'}) {
    _start();
  }
  final String path;
  final String source;
  final void Function(String)? onProblem;
  static const _limit = 8 * 1024 * 1024;
  final _events = ReceivePort();
  final _pending = Queue<(String, Object, int)>();
  final _flushers = <Completer<void>>[];
  final _closed = Completer<void>();
  Isolate? _worker;
  SendPort? _port;
  List<(String, Object, int)>? _batch;
  Timer? _retry;
  int _bytes = 0;
  bool _closing = false, _finished = false, _overflow = false;
  String? _failure;

  void _start() {
    _events.listen((message) {
      if (message is SendPort) {
        _port = message;
        _send();
      } else if (message is List && message.first == 'ack') {
        final written = message[1] as int;
        final batch = _batch!;
        _batch = null;
        for (var i = 0; i < written; i++) _bytes -= batch[i].$3;
        for (var i = batch.length - 1; i >= written; i--)
          _pending.addFirst(batch[i]);
        if (message.length > 2) {
          _report('Session logging failed: ${message[2]}');
          _retry = Timer(const Duration(seconds: 1), () {
            _retry = null;
            _send();
          });
        } else {
          _failure = null;
          _send();
        }
      } else if (message is List && message.first == 'closed') {
        _finish();
      } else if (message == null && !_finished) {
        if (!_closing || _bytes > 0) _report('Session logging worker stopped');
        _finish();
      } else if (message is List) {
        _report('Session logging worker failed: ${message.first}');
      }
    });
    Isolate.spawn(
      _logWorker,
      [_events.sendPort, path, source],
      onError: _events.sendPort,
      onExit: _events.sendPort,
    ).then(
      (worker) {
        _worker = worker;
        if (_finished) worker.kill(priority: Isolate.immediate);
      },
      onError: (Object e) {
        _report('Session logging could not start: $e');
        _finish();
      },
    );
  }

  void _report(String problem) {
    if (_failure != problem) {
      _failure = problem;
      onProblem?.call(problem);
    }
  }

  void write(String message, {String level = 'info'}) =>
      _add((level, message), message.length * 3 + 128);
  void output(List<int> bytes) => _add(bytes, bytes.length + 128);
  void _add(Object value, int size) {
    if (_closing || _finished) return;
    if (size > _limit - _bytes) {
      if (!_overflow) {
        _overflow = true;
        onProblem?.call(
          'Session logging backlog exceeded 8 MiB; some emulator output was omitted.',
        );
      }
      return;
    }
    _pending.add((DateTime.now().toUtc().toIso8601String(), value, size));
    _bytes += size;
    _send();
  }

  void _send() {
    if (_port == null || _batch != null || _retry != null || _finished) return;
    if (_pending.isEmpty) {
      _overflow = false;
      for (final waiter in _flushers) {
        if (!waiter.isCompleted) waiter.complete();
      }
      _flushers.clear();
      if (_closing) _port!.send(null);
      return;
    }
    final batch = <(String, Object, int)>[];
    var size = 0;
    while (_pending.isNotEmpty && batch.length < 64 && size < 65536) {
      final entry = _pending.removeFirst();
      batch.add(entry);
      size += entry.$3;
    }
    _batch = batch;
    _port!.send(batch);
  }

  Future<void> flush() {
    if (_finished || _bytes == 0) return Future.value();
    final done = Completer<void>();
    _flushers.add(done);
    return done.future;
  }

  Future<void> close() async {
    if (_finished) return;
    _closing = true;
    _send();
    try {
      await _closed.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      _report(
        'Session log could not finish writing before close; some output may be missing.',
      );
      _finish();
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _retry?.cancel();
    _worker?.kill(priority: Isolate.immediate);
    _events.close();
    _pending.clear();
    _batch = null;
    _bytes = 0;
    for (final waiter in _flushers) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _flushers.clear();
    _closed.complete();
  }
}

void _logWorker(List<Object> args) async {
  final reply = args[0] as SendPort, input = ReceivePort();
  final disk = _LogDisk(args[1] as String);
  final source = args[2] as String;
  reply.send(input.sendPort);
  await for (final message in input) {
    if (message == null) {
      disk.close();
      input.close();
      reply.send(['closed']);
      return;
    }
    var written = 0;
    try {
      for (final (timestamp, value, _)
          in message as List<(String, Object, int)>) {
        final level = value is (String, String) ? value.$1 : 'info';
        final text = value is (String, String)
            ? value.$2
            : value is String
            ? value
            : utf8.decode(value as List<int>, allowMalformed: true);
        final clean = text
            .replaceAll(RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]'), '')
            .trim();
        for (final line in clean.split('\n')) {
          // Bound individual records without splitting UTF-16 surrogate pairs.
          for (var start = 0; start < line.length;) {
            var end = (start + 16384).clamp(0, line.length);
            if (end < line.length &&
                line.codeUnitAt(end - 1) >= 0xd800 &&
                line.codeUnitAt(end - 1) <= 0xdbff)
              end--;
            disk.write(
              utf8.encode(
                '$timestamp $level $source ${line.substring(start, end)}\n',
              ),
            );
            start = end;
          }
        }
        written++;
      }
      reply.send(['ack', written]);
    } catch (e) {
      disk.close();
      reply.send(['ack', written, '$e']);
    }
  }
}

class _LogDisk {
  _LogDisk(this.path);
  final String path;
  RandomAccessFile? _file;
  int _size = 0;
  void write(List<int> bytes) {
    if (_file == null) {
      _file = File(path).openSync(mode: FileMode.append);
      _size = _file!.lengthSync();
    }
    if (_size + bytes.length > 1024 * 1024) {
      close();
      for (var i = 9; i >= 1; i--) {
        final target = File('$path.$i'),
            source = File(i == 1 ? path : '$path.${i - 1}');
        if (target.existsSync()) target.deleteSync();
        if (source.existsSync()) source.renameSync(target.path);
      }
      _file = File(path).openSync(mode: FileMode.append);
      _size = 0;
    }
    _file!.writeFromSync(bytes);
    _size += bytes.length;
  }

  void close() {
    final file = _file;
    _file = null;
    file?.closeSync();
  }
}
