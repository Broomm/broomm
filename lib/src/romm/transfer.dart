import 'dart:async';

import 'models.dart';

class DownloadCancelled extends RommFailure {
  const DownloadCancelled()
    : super('Download cancelled. You can retry from the game page.');
}

class DownloadWriterUncertain extends RommFailure {
  const DownloadWriterUncertain([
    String message = 'The background download stopped without confirming its file was closed. Local data was kept. Restart Broomm before retrying.',
  ]) : super(message);
}

class DownloadCancellation {
  final _event = Completer<void>();
  Future<void> get whenCancelled => _event.future;
  bool cancelled = false;
  void Function()? abort;
  void check() {
    if (cancelled) throw const DownloadCancelled();
  }

  void cancel() {
    cancelled = true;
    if (!_event.isCompleted) _event.complete();
    abort?.call();
  }
}
