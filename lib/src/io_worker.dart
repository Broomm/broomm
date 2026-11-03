import 'dart:async';
import 'dart:isolate';

import 'romm/transfer.dart';

/// Concrete I/O operations pass a top-level entry point and data, never a UI
/// closure/client. Completion includes writer closure and isolate exit before
/// callers may release locks or delete staging. Cancellation drains the work.
class IoWorker<T> {
  IoWorker(this.operation, this.arguments);
  final Future<T> Function(Object?, IoContext) operation;
  final Object? arguments;
  SendPort? _control;
  bool _cancelled = false, _started = false;
  void cancel() {
    _cancelled = true;
    _control?.send('cancel');
  }

  Future<T> run({
    DownloadCancellation? cancellation,
    void Function(Object?)? progress,
  }) async {
    if (_started) throw StateError('An I/O worker can only run once.');
    _started = true;
    cancellation?.check();
    final events = ReceivePort(), exited = Completer<void>();
    List? result;
    Object? callbackError;
    StackTrace? callbackStack;
    final prior = cancellation?.abort;
    if (cancellation != null) cancellation.abort = cancel;
    final messages = events.listen((message) {
      if (message == null) {
        if (!exited.isCompleted) exited.complete();
      } else if (message is List && message.isNotEmpty) {
        if (message.first == 'ready') {
          _control = message[1] as SendPort;
          _control!.send(_cancelled ? 'cancel' : 'start');
        } else if (message.first == 'progress' &&
            callbackError == null &&
            !_cancelled) {
          try {
            progress?.call(message[1]);
          } catch (error, stack) {
            callbackError = error;
            callbackStack = stack;
            cancel();
          }
        } else if (message.first == 'closed') {
          result = message;
          _control?.send('finish');
        }
        // VM errors can contain URLs or credentials. Never surface their text.
      }
    });
    try {
      await Isolate.spawn(
        _runIo,
        <Object?>[events.sendPort, operation, arguments],
        onExit: events.sendPort,
        onError: events.sendPort,
        errorsAreFatal: true,
      );
      await exited.future;
      if (result == null || result![1] == 'uncertain')
        throw const DownloadWriterUncertain();
      if (callbackError != null)
        Error.throwWithStackTrace(callbackError!, callbackStack!);
      cancellation?.check();
      if (_cancelled) throw const DownloadCancelled();
      if (result![1] == 'error') throw result![2] as Object;
      return result![2] as T;
    } finally {
      if (cancellation != null) cancellation.abort = prior;
      _control = null;
      await messages.cancel();
      events.close();
    }
  }
}

class IoContext {
  IoContext(this._events);
  final SendPort _events;
  final cancellation = DownloadCancellation();
  bool writerOpen = false;
  final _clock = Stopwatch()..start();
  int _last = -150000;
  Object? _phase;
  void progress(Object? value, {Object? phase, bool force = false}) {
    if (force ||
        phase != _phase ||
        _clock.elapsedMicroseconds - _last >= 150000) {
      _phase = phase;
      _last = _clock.elapsedMicroseconds;
      _events.send(['progress', value]);
    }
  }
}

Future<void> _runIo(List<Object?> args) async {
  final events = args[0] as SendPort, controls = ReceivePort();
  final context = IoContext(events);
  final start = Completer<void>(), finish = Completer<void>();
  controls.listen((message) {
    if (message == 'cancel') {
      context.cancellation.cancel();
      if (!start.isCompleted) start.complete();
    } else if (message == 'start' && !start.isCompleted) {
      start.complete();
    } else if (message == 'finish' && !finish.isCompleted) {
      finish.complete();
    }
  });
  events.send(['ready', controls.sendPort]);
  List<Object?> result;
  try {
    await start.future.timeout(const Duration(seconds: 20));
    context.cancellation.check();
    final operation = args[1] as Future<Object?> Function(Object?, IoContext);
    result = ['closed', 'success', await operation(args[2], context)];
  } catch (error) {
    result = ['closed', 'error', error];
  }
  if (context.writerOpen) result = ['closed', 'uncertain', null];
  events.send(result);
  try {
    await finish.future.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    // The parent is gone; this worker has already closed its file.
  }
  controls.close();
}
