import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import '../romm/transfer.dart';
import 'digest.dart';

/// A read-only worker: cancellation never abandons a filesystem writer or a
/// publication. macOS uses its existing CommonCrypto ABI; other hosts use the
/// SDK digest. No compiler, helper executable or extra runtime is shipped.
Future<String> gameFileHash(
  String path, {
  DownloadCancellation? cancellation,
  void Function(int)? progress,
}) async {
  cancellation?.check();
  final messages = ReceivePort();
  final result = Completer<String>();
  SendPort? control;
  Isolate? worker;
  Timer? cancellationDeadline;
  var cancelled = false, timedOut = false, active = true;
  void cancel() {
    if (!active || result.isCompleted) return;
    cancelled = true;
    control?.send('cancel');
    cancellationDeadline ??= Timer(const Duration(seconds: 5), () {
      // Only this read-only isolate is stopped. No external PID is signalled.
      worker?.kill(priority: Isolate.immediate);
      if (!result.isCompleted) result.completeError(const DownloadCancelled());
    });
  }

  final subscription = messages.listen((message) {
    if (message is SendPort) {
      control = message;
      if (cancelled) control!.send('cancel');
    } else if (message is int) {
      progress?.call(message);
    } else if (message is List && message.length == 2 && message[0] == 'ok') {
      if (!result.isCompleted) result.complete(message[1] as String);
    } else if (message is List &&
        message.length == 3 &&
        message[0] == 'error') {
      if (!result.isCompleted)
        result.completeError(
          message[1] as Object,
          StackTrace.fromString(message[2] as String),
        );
    } else if (!result.isCompleted) {
      result.completeError(
        StateError(
          'The file-check worker stopped before completing. Retry the operation.',
        ),
      );
    }
  });
  final deadline = Timer(const Duration(minutes: 5), () {
    timedOut = true;
    cancel();
  });
  if (cancellation != null)
    unawaited(cancellation.whenCancelled.then((_) => cancel()));
  try {
    worker = await Isolate.spawn(
      _hashFile,
      [path, messages.sendPort],
      onError: messages.sendPort,
      onExit: messages.sendPort,
      errorsAreFatal: true,
    );
    if (cancelled) control?.send('cancel');
    final hash = await result.future;
    if (timedOut)
      throw StateError(
        'Checking the game file timed out. The game and progress were kept.',
      );
    cancellation?.check();
    return hash;
  } catch (_) {
    if (timedOut)
      throw StateError(
        'Checking the game file timed out. The game and progress were kept.',
      );
    cancellation?.check();
    rethrow;
  } finally {
    active = false;
    deadline.cancel();
    cancellationDeadline?.cancel();
    await subscription.cancel();
    messages.close();
    worker?.kill(priority: Isolate.immediate);
  }
}

Future<void> _hashFile(List<Object> request) async {
  final path = request[0] as String, reply = request[1] as SendPort;
  final control = ReceivePort();
  var cancelled = false;
  control.listen((_) => cancelled = true);
  reply.send(control.sendPort);
  _AppleSha256? native;
  try {
    final file = File(path), before = await File(path).stat();
    if (before.type != FileSystemEntityType.file)
      throw const FileSystemException('Choose a regular game file.');
    if (Platform.isMacOS) native = _AppleSha256();
    final digest = native == null ? ProgressDigest.sha256() : null;
    final clock = Stopwatch()..start();
    var read = 0, last = 0;
    reply.send(0);
    await for (final bytes in file.openRead()) {
      if (cancelled) throw const DownloadCancelled();
      if (native == null) {
        digest!.add(bytes);
      } else {
        native.add(bytes);
      }
      read += bytes.length;
      if (clock.elapsedMilliseconds - last >= 150) {
        last = clock.elapsedMilliseconds;
        reply.send(read);
      }
    }
    if (cancelled) throw const DownloadCancelled();
    final after = await file.stat();
    if (read != before.size ||
        before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed)
      throw const FileSystemException(
        'The game file changed during its identity check. Retry after its writer has closed.',
      );
    final hash = native?.finish() ?? digest!.finish();
    native?.close();
    native = null;
    reply.send(['ok', hash]);
  } catch (error, stack) {
    reply.send(['error', error, stack.toString()]);
  } finally {
    native?.close();
    control.close();
  }
}

/// CC_SHA256_CTX in the approved Apple SDK: count[2], hash[8], wbuf[16],
/// all uint32_t. Keep this small OS adapter separate from identity decisions.
class _AppleSha256 {
  static final _lib = DynamicLibrary.open('/usr/lib/libSystem.B.dylib');
  static final _malloc = _lib
      .lookupFunction<
        Pointer<Uint8> Function(IntPtr),
        Pointer<Uint8> Function(int)
      >('malloc');
  static final _free = _lib
      .lookupFunction<
        Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)
      >('free');
  static final _init = _lib
      .lookupFunction<
        Int32 Function(Pointer<Uint8>),
        int Function(Pointer<Uint8>)
      >('CC_SHA256_Init');
  static final _update = _lib
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Uint32),
        int Function(Pointer<Uint8>, Pointer<Uint8>, int)
      >('CC_SHA256_Update');
  static final _finish = _lib
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Pointer<Uint8>),
        int Function(Pointer<Uint8>, Pointer<Uint8>)
      >('CC_SHA256_Final');
  final Pointer<Uint8> _context = _malloc(104),
      _buffer = _malloc(65536),
      _output = _malloc(32);
  _AppleSha256() {
    if (_context == nullptr || _buffer == nullptr || _output == nullptr) {
      close();
      throw StateError('Not enough memory to check the game file.');
    }
    if (_init(_context) != 1) {
      close();
      throw StateError('The system file digest could not initialize.');
    }
  }
  void add(List<int> bytes) {
    for (var offset = 0; offset < bytes.length; offset += 65536) {
      final count = (bytes.length - offset).clamp(0, 65536);
      _buffer.asTypedList(count).setRange(0, count, bytes, offset);
      if (_update(_context, _buffer, count) != 1)
        throw StateError('The system file digest failed.');
    }
  }

  String finish() {
    if (_finish(_output, _context) != 1)
      throw StateError('The system file digest did not finish.');
    return _output
        .asTypedList(32)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void close() {
    _free(_context);
    _free(_buffer);
    _free(_output);
  }
}
