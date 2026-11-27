part of 'session.dart';

extension _CemuSession on GameSession {
  Future<void> _launchCemu(
    PreparedEmulator e,
    TestGame selected,
    String rom,
  ) async {
    final resolved =
        _resolved ??
        (throw StateError('Cemu requires a resolved managed profile.'));
    final sources =
        cemuControllers ??
        (throw StateError('Cemu’s controller source adapter is unavailable.'));
    final title =
        e.contentId ??
        (throw StateError('Cemu’s native title identity was not inspected.'));
    log = SessionLog('${e.root}/broomm.log', onProblem: onProblem);
    log!.write('Launching ${selected.id} with Cemu');
    final control = _cemu = CemuSessionControl(
      sources,
      title,
      changed: (next) {
        if (_process == null || next.pid != _process!.pid) return;
        status = next;
        onStatus?.call(next);
      },
      problem: (message) => onControlLost?.call(message),
    );
    await control.prepare();
    await RemoteLayout.prepare(e);
    final arguments = await const CemuAdapter().prepare(
      e,
      selected,
      rom,
      control.input.port!,
    );
    cancellation.check();
    final child = await CemuProcess.start(
      resolved: resolved,
      dataRoot: dataRoot,
      project: project,
      arguments: arguments,
      supervised: true,
    );
    _process = child;
    final sessionLog = log!;
    final stdoutDone = Completer<void>(), stderrDone = Completer<void>();
    child.stdout.listen(
      sessionLog.output,
      onDone: stdoutDone.complete,
      onError: (Object error) {
        sessionLog.write('Cemu stdout failed: $error');
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
    );
    child.stderr.listen(
      sessionLog.output,
      onDone: stderrDone.complete,
      onError: (Object error) {
        sessionLog.write('Cemu stderr failed: $error');
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
    );
    _exitDone = child.exitCode.then((code) async {
      _process = null;
      try {
        await control.close();
      } catch (error) {
        onProblem?.call('Cemu input cleanup needs attention: $error');
      }
      try {
        await Future.wait([stdoutDone.future, stderrDone.future])
            .timeout(const Duration(seconds: 1));
      } on TimeoutException {
        sessionLog.write('Cemu output did not finish closing.');
      }
      sessionLog.write('Cemu exited with status $code');
      try {
        if (finalizeProgress != null) {
          finalizingProgress = true;
          onFinalizingProgress?.call();
        }
        await finalizeProgress?.call(code);
      } catch (error) {
        onProblem?.call(
          'Cemu progress remains local; cloud finalization failed: $error',
        );
      }
      try {
        await _release();
      } catch (error) {
        onProblem?.call('Cemu session cleanup needs attention: $error');
      } finally {
        onExit?.call(code);
      }
    });
    try {
      await control.attach(child);
    } catch (_) {
      if (_process == null) await _exitDone;
      rethrow;
    }
    cancellation.check();
    await onStarted?.call();
  }
}
