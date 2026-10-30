import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

/// Astris requires Launch Services for its security-scoped game URL. The open
/// command is only a launch request: kernel writer ownership and process birth
/// identify the emulator, and its native normal-exit receipt distinguishes a
/// completed session from a crash. No PID-only termination is offered.
class AstrisProcess implements Process {
  AstrisProcess._(
    this._launcher,
    this._identity,
    this._native,
    this._root,
    this._out,
    this._err,
  ) {
    exitCode = _wait();
  }
  final Process _launcher;
  final List<int> _identity;
  final AstrisProcessIdentity _native;
  final String _root;
  final StreamController<List<int>> _out, _err;

  static Future<AstrisProcess> start({
    required String executable,
    String? rom,
    required String root,
    required String writer,
    required String guard,
    required Map<String, String> environment,
    void Function(Process)? observeRequest,
    void Function(String)? onProblem,
  }) async {
    final native = AstrisProcessIdentity(guard, writer, executable);
    final owner = native.launchOwner();
    final random = Random.secure();
    final token = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final ticket = File('$root/astris-launch-ticket');
    final type = await FileSystemEntity.type(ticket.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file)
      throw StateError('Astris launch admission is linked or invalid.');
    final publication = await Directory(root).createTemp('.astris-admission-');
    try {
      final pending = File('${publication.path}/ticket');
      await pending.writeAsString(token, flush: true);
      await pending.rename(ticket.path);
    } finally {
      await publication.delete(recursive: true);
    }
    for (final name in [
      'astris-stdout.pipe',
      'astris-stderr.pipe',
      'astris-exit.json',
    ]) {
      final file = File('$root/$name');
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.notFound)
        await file.delete();
    }
    final pipes = ['$root/astris-stdout.pipe', '$root/astris-stderr.pipe'];
    final created = await Process.run('/usr/bin/mkfifo', [
      '-m',
      '600',
      ...pipes,
    ]);
    if (created.exitCode != 0)
      throw StateError('Astris logging pipes could not be prepared.');
    // An RDWR, nonblocking keeper prevents a failed OS launch from leaving
    // Dart's asynchronous FIFO open blocked forever. Release after native exit.
    try {
      for (final path in pipes) native.holdPipe(path);
    } catch (_) {
      native.releasePipes();
      rethrow;
    }
    final out = StreamController<List<int>>(),
        err = StreamController<List<int>>();
    Future<void> receive(
      Stream<List<int>> source,
      StreamController<List<int>> target,
    ) {
      final done = Completer<void>();
      source.listen(
        target.add,
        onError: target.addError,
        onDone: done.complete,
      );
      return done.future;
    }

    final nativeOut = receive(File(pipes[0]).openRead(), out);
    final nativeErr = receive(File(pipes[1]).openRead(), err);
    Future<void>? requestOut, requestErr;
    try {
      final launcher = await Process.start(
        '/usr/bin/open',
        [
          '-W',
          '-n',
          '-a',
          File(executable).parent.parent.parent.path,
          '--stdout',
          pipes[0],
          '--stderr',
          pipes[1],
          for (final entry in environment.entries) ...[
            '--env',
            '${entry.key}=${entry.value}',
          ],
          '--env',
          'BROOMM_ASTRIS_TOKEN=$token',
          '--env',
          'BROOMM_LAUNCHER_PID=${owner[0]}',
          '--env',
          'BROOMM_LAUNCHER_SECONDS=${owner[1]}',
          '--env',
          'BROOMM_LAUNCHER_MICROSECONDS=${owner[2]}',
          if (rom != null) rom,
        ],
        includeParentEnvironment: false,
        environment: {'PATH': '/usr/bin:/bin'},
      );
      observeRequest?.call(launcher);
      requestOut = receive(launcher.stdout, out);
      requestErr = receive(launcher.stderr, err);
      var launcherEnded = false;
      unawaited(
        launcher.exitCode.then((_) {
          launcherEnded = true;
        }),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (true) {
        final identity = native.writer();
        if (identity != null) {
          native.capture(identity);
          return AstrisProcess._(launcher, identity, native, root, out, err)
            .._onProblem = onProblem;
        }
        if (launcherEnded || DateTime.now().isAfter(deadline)) {
          // Revoke admission before releasing the caller's lease. A delayed
          // Launch Services child must fail in its constructor, before settings
          // or saves initialize. A constructor already admitted owns writer.lock.
          await ticket.delete();
          final admitted = native.writer();
          if (admitted != null) {
            native.capture(admitted);
            final child = AstrisProcess._(
              launcher,
              admitted,
              native,
              root,
              out,
              err,
            );
            child.kill(ProcessSignal.sigterm);
            return child;
          }
          throw StateError(
            'Astris did not establish its private game writer. Its local data was kept.',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    } catch (_) {
      if (await ticket.exists()) await ticket.delete();
      native.releasePipes();
      unawaited(out.stream.drain<void>().catchError((Object _) {}));
      unawaited(err.stream.drain<void>().catchError((Object _) {}));
      rethrow;
    } finally {
      unawaited(
        Future.wait([nativeOut, if (requestOut != null) requestOut])
            .then((_) => out.close()),
      );
      unawaited(
        Future.wait([nativeErr, if (requestErr != null) requestErr])
            .then((_) => err.close()),
      );
    }
  }

  void Function(String)? _onProblem;

  Future<int> _wait() async {
    // Never infer emulator exit from open's exit code. Keep exclusion even if
    // the helper is interrupted while the actual application remains alive.
    var uncertain = false;
    while (true) {
      try {
        if (!_native.alive(_identity) && _native.writer() == null) break;
        uncertain = false;
      } catch (e) {
        if (!uncertain) _onProblem?.call('$e');
        uncertain = true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _native.releasePipes();
    _native.releaseApplication();
    try {
      final file = File('$_root/astris-exit.json');
      if (await file.length() > 1024) return -1;
      final receipt = jsonDecode(await file.readAsString()) as Map;
      return receipt['pid'] == pid && receipt['normal'] == true ? 0 : -1;
    } on FileSystemException {
      return -1;
    } on FormatException {
      return -1;
    }
  }

  @override
  int get pid => _identity[0];
  @override
  late final Future<int> exitCode;
  @override
  IOSink get stdin => _launcher.stdin;
  @override
  Stream<List<int>> get stdout => _out.stream;
  @override
  Stream<List<int>> get stderr => _err.stream;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      (signal == ProcessSignal.sigterm || signal == ProcessSignal.sigkill) &&
      _native.stop(_identity, force: signal == ProcessSignal.sigkill);
}

/// Existing native interop only; no runtime package or process-list parsing.
class AstrisProcessIdentity {
  AstrisProcessIdentity(String library, this.lock, this.executable) {
    final native = DynamicLibrary.open(library);
    _writer = native
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint64>),
          int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint64>)
        >('broomm_native_writer');
    _alive = native
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, Pointer<Uint64>),
          int Function(Pointer<Uint8>, Pointer<Uint64>)
        >('broomm_native_alive');
    _hold = native
        .lookupFunction<
          Int32 Function(Pointer<Uint8>),
          int Function(Pointer<Uint8>)
        >('broomm_log_pipe');
    _capture = native
        .lookupFunction<
          Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint64>),
          Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint64>)
        >('broomm_application_capture');
    _stop = native
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint64>, Int32),
          int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint64>, int)
        >('broomm_application_stop');
    _release = native
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('broomm_application_release');
    _owner = native
        .lookupFunction<
          Int32 Function(Pointer<Uint64>),
          int Function(Pointer<Uint64>)
        >('broomm_launch_owner');
  }
  final String lock, executable;
  late final int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint64>)
  _writer;
  late final int Function(Pointer<Uint8>, Pointer<Uint64>) _alive;
  late final int Function(Pointer<Uint8>) _hold;
  late final Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint64>) _capture;
  late final int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint64>, int)
  _stop;
  late final void Function(Pointer<Void>) _release;
  late final int Function(Pointer<Uint64>) _owner;
  Pointer<Void> _application = nullptr;
  final _pipes = <int>[];
  static final _system = DynamicLibrary.process();
  static final _allocate = _system
      .lookupFunction<
        Pointer<Uint8> Function(IntPtr, IntPtr),
        Pointer<Uint8> Function(int, int)
      >('calloc');
  static final _free = _system
      .lookupFunction<
        Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)
      >('free');
  static final _close = _system
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');

  void holdPipe(String path) {
    final bytes = utf8.encode(path);
    if (bytes.length >= 4096 || bytes.contains(0))
      throw StateError('Invalid Astris logging path.');
    final memory = _allocate(1, bytes.length + 1);
    if (memory == nullptr)
      throw StateError('Astris logging could not allocate memory.');
    try {
      memory.asTypedList(bytes.length).setAll(0, bytes);
      final fd = _hold(memory);
      if (fd < 0) throw StateError('Astris logging pipe could not be opened.');
      _pipes.add(fd);
    } finally {
      _free(memory);
    }
  }

  void releasePipes() {
    for (final fd in _pipes) _close(fd);
    _pipes.clear();
  }

  T _inspect<T>(
    T Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint64>) action,
  ) {
    final a = utf8.encode(lock), b = utf8.encode(executable);
    if (a.length >= 4096 || b.length >= 4096 || a.contains(0) || b.contains(0))
      throw StateError('Invalid Astris process identity path.');
    final memory = _allocate(1, 8192 + 24);
    if (memory == nullptr)
      throw StateError('Astris process inspection could not allocate memory.');
    try {
      memory.asTypedList(a.length).setAll(0, a);
      final path = memory + 4096;
      path.asTypedList(b.length).setAll(0, b);
      return action(memory, path, (memory + 8192).cast<Uint64>());
    } finally {
      _free(memory);
    }
  }

  List<int>? writer() => _inspect((a, b, out) {
    final result = _writer(a, b, out);
    if (result < 0)
      throw StateError(
        'Astris game writer identity could not be confirmed. Its local data was kept.',
      );
    return result == 0 ? null : out.asTypedList(3).toList();
  });
  List<int> launchOwner() => _inspect((a, b, out) {
    if (_owner(out) != 1)
      throw StateError('The launcher process identity could not be confirmed.');
    return out.asTypedList(3).toList();
  });
  bool alive(List<int> identity) => _inspect((a, b, out) {
    out.asTypedList(3).setAll(0, identity);
    final result = _alive(b, out);
    if (result < 0)
      throw StateError(
        'Astris process exit could not be confirmed. Its local data was kept.',
      );
    return result == 1;
  });
  void capture(List<int> identity) => _inspect((a, b, out) {
    out.asTypedList(3).setAll(0, identity);
    _application = _capture(b, out);
    if (_application == nullptr)
      throw StateError(
        'Astris application identity could not be captured. Its local data was kept.',
      );
  });
  bool stop(List<int> identity, {required bool force}) => _inspect((a, b, out) {
    out.asTypedList(3).setAll(0, identity);
    return _stop(_application, b, out, force ? 1 : 0) == 1;
  });
  void releaseApplication() {
    _release(_application);
    _application = nullptr;
  }
}
