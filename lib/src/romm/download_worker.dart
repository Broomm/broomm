import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'content_download.dart';
import 'models.dart';
import 'transfer.dart';

/// A single private transfer. The owner keeps its game/library locks until
/// both a closed-writer result and isolate exit have been observed.
class RommDownloadWorker {
  RommDownloadWorker(
    this.uri,
    this.access,
    this.bytes,
    this.destination,
    this.deadline,
  );
  final Uri uri;
  final String access, destination;
  final int bytes;
  final Duration deadline;
  SendPort? _control;
  bool _cancelled = false, _started = false;
  void cancel() {
    _cancelled = true;
    _control?.send('cancel');
  }

  Future<void> run({
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    if (_started) throw StateError('A download worker can only run once.');
    _started = true;
    final events = ReceivePort(), exited = Completer<void>();
    List? result;
    Object? callbackError;
    StackTrace? callbackStack;
    final prior = cancellation.abort;
    cancellation.abort = cancel;
    final messages = events.listen((message) {
      if (message == null) {
        if (!exited.isCompleted) exited.complete();
        return;
      }
      if (message is! List || message.isEmpty) return;
      if (message.first == 'ready') {
        _control = message[1] as SendPort;
        _control!.send(
          _cancelled || cancellation.cancelled ? 'cancel' : 'start',
        );
      } else if (message.first == 'progress' &&
          callbackError == null &&
          !_cancelled) {
        try {
          onProgress(message[1] as int);
        } catch (error, stack) {
          callbackError = error;
          callbackStack = stack;
          cancel();
        }
      } else if (message.first == 'closed') {
        result = message;
        _control?.send('finish');
      }
      // VM error messages are intentionally not printed: they may contain
      // request data. Missing closed-writer evidence is handled after exit.
    });
    try {
      await Isolate.spawn(
        _runRommDownload,
        <Object>[
          events.sendPort,
          uri.toString(),
          access,
          bytes,
          destination,
          deadline.inMicroseconds,
        ],
        onExit: events.sendPort,
        onError: events.sendPort,
        errorsAreFatal: true,
      );
      await exited.future;
      if (result == null || result![1] == 'uncertain')
        throw const DownloadWriterUncertain();
      if (callbackError != null)
        Error.throwWithStackTrace(callbackError!, callbackStack!);
      cancellation.check();
      if (_cancelled || result![1] == 'cancelled')
        throw const DownloadCancelled();
      if (result![1] != 'success')
        throw RommFailure(result![2] as String, status: result![3] as int?);
    } finally {
      cancellation.abort = prior;
      _control = null;
      await messages.cancel();
      events.close();
    }
  }
}

Future<void> _runRommDownload(List<Object> arguments) async {
  final events = arguments[0] as SendPort, controls = ReceivePort();
  final start = Completer<void>(), finish = Completer<void>();
  final cancellation = DownloadCancellation();
  final client = HttpClient()
    ..connectionTimeout = Duration(microseconds: arguments[5] as int)
    ..idleTimeout = const Duration(seconds: 15)
    ..maxConnectionsPerHost = 4;
  controls.listen((message) {
    if (message == 'cancel') {
      cancellation.cancel();
      client.close(force: true);
      if (!start.isCompleted) start.complete();
    } else if (message == 'start' && !start.isCompleted) {
      start.complete();
    } else if (message == 'finish' && !finish.isCompleted) {
      finish.complete();
    }
  });
  events.send(['ready', controls.sendPort]);
  var writerOpen = false;
  var result = <Object?>[
    'closed',
    'error',
    'The download worker could not finish. Retry the download.',
    null,
  ];
  try {
    await start.future.timeout(const Duration(seconds: 20));
    cancellation.check();
    final clock = Stopwatch()..start();
    var last = -120000;
    await downloadRommContent(
      client,
      Uri.parse(arguments[1] as String),
      arguments[2] as String,
      arguments[3] as int,
      File(arguments[4] as String),
      deadline: Duration(microseconds: arguments[5] as int),
      cancellation: cancellation,
      writerState: (open) => writerOpen = open,
      onProgress: (received) {
        if (clock.elapsedMicroseconds - last >= 120000 ||
            received == arguments[3]) {
          last = clock.elapsedMicroseconds;
          events.send(['progress', received]);
        }
      },
    );
    result = ['closed', 'success', '', null];
  } on DownloadCancelled {
    result = ['closed', 'cancelled', '', null];
  } on RommFailure catch (error) {
    result = ['closed', 'error', error.message, error.status];
  } catch (_) {
    /* Keep credentials/URLs/native stack details out of messages. */
  } finally {
    client.close(force: true);
  }
  if (writerOpen) result = ['closed', 'uncertain', '', null];
  // The shared transfer has closed its file before this acknowledgement. The
  // parent acknowledges receipt before normal exit; no native writer is killed.
  events.send(result);
  try {
    await finish.future.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    /* Parent died/stopped responding; writer is closed. */
  }
  controls.close();
}
