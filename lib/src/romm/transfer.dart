import 'dart:async';

import 'models.dart';

class DownloadCancelled extends RommFailure {
  const DownloadCancelled()
    : super('Download cancelled. You can retry from the game page.');
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
