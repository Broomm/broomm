import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'installation.dart';
import 'releases.dart';
import 'transport.dart';

typedef UpdateCheck = Future<AppUpdate?> Function(
  String current,
  bool candidates,
  String target,
);

class ApplicationUpdates extends ChangeNotifier {
  ApplicationUpdates({
    this.current = broommReleaseVersion,
    String? target,
    UpdateCheck? check,
    ApplicationInstaller Function()? installer,
  }) : target =
           target ??
           (broommReleaseTarget.isEmpty
               ? updateTarget(Platform.operatingSystem, Abi.current())
               : broommReleaseTarget),
       checkForUpdates =
           check ??
           ((current, candidates, target) =>
               UpdateTransport().latest(current, candidates, target)),
       createInstaller = installer ?? ApplicationInstaller.new;
  final String current;
  final String? target;
  final UpdateCheck checkForUpdates;
  final ApplicationInstaller Function() createInstaller;
  AppUpdate? available;
  bool checking = false, busy = false, handedOff = false, disposed = false;
  bool checkFailed = false;
  String status = '';
  String? failureDiagnostic;
  double? progress;
  String channel = 'auto';
  int _generation = 0;
  Timer? _timer;
  ApplicationInstaller? _installer;
  PreparedAppUpdate? _prepared;
  Future<void>? _work;
  Future<void>? _cleanupWork;
  bool _cancelRequested = false;
  ({String message, bool problem})? completionNotice;
  bool get supported => target != null && AppVersion.parse(current) != null;
  bool get candidates =>
      channel == 'rc' ||
      channel == 'auto' && AppVersion.parse(current)?.rc != null;
  Future<void> cleanup(Directory data) async {
    if (!supported) return;
    final work = () async {
      completionNotice = await cleanupApplicationUpdates(
        await UpdateLocation.discover(data),
        current: current,
      );
    }();
    _cleanupWork = work;
    try {
      await work;
    } finally {
      if (identical(_cleanupWork, work)) _cleanupWork = null;
    }
  }

  void emit() {
    if (!disposed) notifyListeners();
  }

  void start(String selected) {
    channel = selected;
    _timer?.cancel();
    if (!supported) {
      status = 'Development build. Install an official release to enable application updates.';
      emit();
      return;
    }
    unawaited(check());
    _timer = Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(check()),
    );
  }

  Future<void> setChannel(String selected) async {
    if (busy || !{'auto', 'stable', 'rc'}.contains(selected)) return;
    channel = selected;
    if (!candidates && available?.version.rc != null) available = null;
    await check();
  }

  Future<void> check() async {
    if (!supported || busy || disposed) return;
    final generation = ++_generation;
    checking = true;
    checkFailed = false;
    emit();
    try {
      final result = await checkForUpdates(current, candidates, target!);
      if (generation != _generation || disposed) return;
      if (_prepared != null &&
          available?.version.toString() != result?.version.toString()) {
        await _prepared!.discard();
        _prepared = null;
      }
      available = result;
      status = result == null
          ? 'Broomm is up to date.'
          : 'Broomm ${result.version} is available.';
    } catch (_) {
      if (generation == _generation && !disposed) {
        checkFailed = true;
        // Failed observation is not evidence that an existing offer vanished.
        status = 'Could not check GitHub for updates. Check your connection and retry.';
      }
    } finally {
      if (generation == _generation && !disposed) {
        checking = false;
        emit();
      }
    }
  }

  Future<void> install(
    Directory data, {
    required Future<void> Function() quiesce,
    required Future<void> Function() exit,
  }) {
    if (busy || available == null || disposed || handedOff)
      return _work ?? Future.value();
    final work = _install(data, quiesce: quiesce, exit: exit);
    _work = work;
    return work.whenComplete(() {
      if (identical(_work, work)) _work = null;
    });
  }

  Future<void> _install(
    Directory data, {
    required Future<void> Function() quiesce,
    required Future<void> Function() exit,
  }) async {
    ++_generation;
    checking = false;
    _cancelRequested = false;
    failureDiagnostic = null;
    busy = true;
    status = 'Preparing update…';
    progress = null;
    emit();
    var last = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      try {
        await _cleanupWork;
      } catch (_) {
        /* Optional cleanup cannot authorize or block installation. */
      }
      if (_cancelRequested || disposed)
        throw const UpdateFailure('Update cancelled.');
      _installer = createInstaller();
      _prepared ??= await _installer!.prepare(available!, data, (
        phase,
        fraction,
      ) {
        if (disposed) return;
        if (phase != status ||
            DateTime.now().difference(last).inMilliseconds >= 100 ||
            fraction == 1) {
          last = DateTime.now();
          status = phase;
          progress = fraction;
          emit();
        }
      });
      _installer!.transport.check();
      if (disposed) throw const UpdateFailure('Update cancelled.');
      status = 'Finishing saves and pausing downloads…';
      progress = null;
      emit();
      await quiesce();
      _installer!.transport.check();
      if (disposed) throw const UpdateFailure('Update cancelled.');
      // OS handoff cannot be revoked like a download. Fence cancellation before
      // entering it, including while the helper/Android installer acknowledges.
      handedOff = true;
      status = 'Starting the update installer…';
      emit();
      final ready = await _prepared!.start();
      if (!ready) {
        handedOff = false;
        status = 'Allow Broomm to install updates in Android settings, then choose Continue installation.';
        return;
      }
      if (_prepared!.apk != null) {
        handedOff = true;
        _prepared = null;
        status = 'Confirm the update in Android’s installer. Android will retain your Broomm data.';
        return;
      }
      await _prepared!.commit();
      handedOff = true;
      status = 'Installing update and restarting Broomm…';
      emit();
      await exit();
    } catch (e) {
      final failedPhase = status;
      // Do not stringify transport errors or captured object graphs: they can
      // include signed redirect URLs or credentials held by UI callbacks.
      if (_installer?.transport.cancelled != true) {
        failureDiagnostic =
            'updates/controller.dart: ${e.runtimeType} during $failedPhase'
            '${e is FileSystemException && e.osError != null ? ' (OS error ${e.osError!.errorCode})' : ''}';
      }
      handedOff = false;
      var cleanupFailed = false;
      if (_prepared != null) {
        try {
          await _prepared!.discard();
        } catch (_) {
          cleanupFailed = true;
        } finally {
          _prepared = null;
        }
      }
      status = _installer?.transport.cancelled == true
          ? 'Update cancelled. Your existing installation was kept.'
          : e is UpdateFailure
          ? e.message
          : e is StateError
          ? '${e.message}'
          : 'The update could not be installed during this step: $failedPhase Your existing application and data were kept. Retry when ready.';
      if (cleanupFailed) status += ' Recovery files could not be removed and were kept in the installation folder.';
    } finally {
      if (!handedOff || target == 'android-universal') busy = false;
      _installer?.transport.close();
      emit();
    }
  }

  void cancel() {
    if (handedOff) return;
    _cancelRequested = true;
    _installer?.cancel();
  }

  void androidInstallerReturned() {
    handedOff = false;
    status = 'If Android did not install the update, choose Retry update.';
    emit();
  }

  Future<void> finish() async {
    cancel();
    await _work;
  }

  @override
  void dispose() {
    disposed = true;
    ++_generation;
    _timer?.cancel();
    cancel();
    final work = _work ?? Future<void>.value();
    unawaited(
      work
          .then((_) async {
            if (_prepared != null) {
              if (handedOff) {
                await _prepared!.lease.close();
              } else {
                await _prepared!.discard();
              }
              _prepared = null;
            }
          })
          .catchError((Object _) {}),
    );
    super.dispose();
  }
}
