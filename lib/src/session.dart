import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'catalogue.dart';
import 'emulators.dart';
import 'pairing.dart';
import 'session_log.dart';
import 'session_lease.dart';
export 'session_log.dart';

class ResolvedSession {
  const ResolvedSession(
    this.emulator,
    this.rom,
    this.executableHash,
    this.native, {
    this.home,
    this.readOnly = const [],
    this.coreHash,
  });
  final PreparedEmulator emulator;
  final String rom, executableHash;
  final Map<String, String> native;
  final String? home;
  final String? coreHash;
  final List<String> readOnly;
}

class Rpcs3Loading {
  Rpcs3Loading(
    this.filesTotal,
    this.filesDone,
    this.modulesTotal,
    this.modulesDone,
    this.totalBits,
    this.knownBits,
  );
  final int filesTotal,
      filesDone,
      modulesTotal,
      modulesDone,
      totalBits,
      knownBits;
  static Rpcs3Loading? read(Object? value) {
    if (value is! Map) return null;
    final fields = [
      'filesTotal',
      'filesDone',
      'modulesTotal',
      'modulesDone',
      'totalBits',
      'knownBits',
    ];
    if (fields.any(
      (k) =>
          value[k] is! int ||
          (value[k] as int) < 0 ||
          (value[k] as int) > 9007199254740991,
    ))
      return null;
    final v = Rpcs3Loading(
      value['filesTotal'],
      value['filesDone'],
      value['modulesTotal'],
      value['modulesDone'],
      value['totalBits'],
      value['knownBits'],
    );
    if ([
      v.filesTotal,
      v.filesDone,
      v.modulesTotal,
      v.modulesDone,
    ].any((n) => n > 0xffffffff))
      return null;
    if (v.filesDone > v.filesTotal ||
        v.modulesDone > v.modulesTotal ||
        v.knownBits > v.totalBits ||
        (v.filesTotal == 0 && v.modulesTotal == 0))
      return null;
    return v;
  }

  // RPCS3 estimates remaining modules as it discovers files. This is the
  // current native phase, not a whole-launch percentage or an ETA.
  double? get fraction {
    if (modulesTotal == 0) return null;
    final useBits = knownBits > 0 && totalBits > 0;
    final known = useBits ? knownBits : filesTotal;
    final total = useBits ? totalBits : filesTotal;
    final estimate =
        modulesTotal.toDouble() *
        (total > 0 ? total : 1) /
        (known > 0 ? known : 1);
    return (modulesDone / estimate).clamp(0, 1);
  }

  String get description => [
    if (filesTotal > 0) 'Files $filesDone / $filesTotal',
    if (modulesTotal > 0) 'Modules $modulesDone / $modulesTotal',
  ].join(' · ');
}

class BridgeStatus {
  BridgeStatus(Map<String, dynamic> j)
    : pid = j['pid'] as int,
      sample = j['sample'] as int,
      ack = j['ack'] as int,
      requestSerial = j['requestSerial'] as int,
      request = j['request'] as String,
      requestDevice = j['requestDevice'] as int?,
      blocked = j['blocked'] as bool,
      paused = j['paused'] as int,
      window = (j['window'] as List)
          .cast<num>()
          .map((n) => n.toDouble())
          .toList(),
      devices = (j['devices'] as List)
          .map(
            (d) =>
                ControllerDevice.fromJson(Map<String, dynamic>.from(d as Map)),
          )
          .toList(),
      testSourceIds = (j['testSourceIds'] as List? ?? []).cast<int>(),
      connectedPorts = j['connectedPorts'] as int? ?? 0,
      consolePorts = j['consolePorts'] as int? ?? -1,
      pspButtons = j['pspButtons'] as int? ?? 0,
      switchButtons = j['switchButtons'] as int? ?? 0,
      nativeProgram = j['nativeProgram'] as String?,
      appActive = j['appActive'] as bool? ?? false,
      inputReady = j['inputReady'] as bool? ?? false,
      loading = Rpcs3Loading.read(j['loading']) {
    if (j['protocol'] != 4)
      throw const FormatException(
        'Unsupported controller bridge protocol. Rebuild Broomm and its native bridges.',
      );
  }
  final int pid, sample, ack, requestSerial, paused;
  final String request;
  final int? requestDevice;
  final bool blocked;
  final List<double> window;
  final List<ControllerDevice> devices;
  final List<int> testSourceIds;
  final int connectedPorts, consolePorts, pspButtons, switchButtons;
  final String? nativeProgram;
  final bool appActive, inputReady;
  final Rpcs3Loading? loading;
}

class GameSession {
  GameSession(
    this.project, {
    this.onStatus,
    this.onExit,
    this.onProblem,
    this.testInputs = false,
    this.testPreconnected = false,
    this.testMotion = false,
    this.managedRoot,
    this.resolve,
    this.preparationLease,
  });
  final String project;
  final String? managedRoot;
  final Future<ResolvedSession> Function(LaunchGame)? resolve;
  final SessionLease? preparationLease;
  GameSession? _preparation;
  String? nativeProgramId;
  ResolvedSession? _resolved;
  String? _romPath;
  final bool testInputs;
  final bool testPreconnected;
  final bool testMotion;
  void Function(BridgeStatus)? onStatus;
  void Function(int)? onExit;
  void Function(String)? onProblem;
  void Function(String)? onControlLost;

  /// Runs after the native writer exits and before releasing SessionLease.
  Future<void> Function(int)? finalizeProgress;
  void Function()? onFinalizingProgress;
  void Function()? cancelProgressTransfer;
  bool finalizingProgress = false;
  Process? _process;
  Future<void>? _exitDone;
  Future<void> _commands = Future<void>.value();
  SessionLease? _guard;
  Timer? _timer;
  bool _polling = false, _stopping = false;
  bool _bridgeLost = false;
  int _revision = 0, _sample = -1, _generation = 0;
  DateTime _lastUpdate = DateTime.now();
  PreparedEmulator? emulator;
  TestGame? game;
  BridgeStatus? status;
  SessionLog? log;
  RawDatagramSocket? _retro;
  StreamSubscription<RawSocketEvent>? _retroSubscription;
  Completer<String>? _retroReply;
  String? _retroMessage;
  bool _retroBusy = false;
  int _retroPort = 0;
  int _retroPaused = -1;
  String get dataRoot => managedRoot ?? '$project/prototype-data';
  SessionLease get ownerLease =>
      _guard ?? (throw StateError('No active game session owner'));
  bool get running => _process != null;
  int? get processId => _process?.pid;

  Future<void> launch(TestGame selected) async {
    if (running) throw StateError('A game is already running');
    if (_guard != null)
      throw StateError('The previous session is still closing');
    final generation = ++_generation;
    _retroPaused = -1;
    _retroBusy = false;
    _retroMessage = null;
    _retroReply = null;
    _stopping = false;
    status = null;
    nativeProgramId = null;
    _bridgeLost = false;
    if (!Platform.isMacOS)
      throw UnsupportedError(
        'This prototype’s native bridge currently supports macOS arm64.',
      );
    final metadata = File('$dataRoot/installations.json');
    if (resolve == null && !await metadata.exists())
      throw StateError('Run devbox run prototype-prepare first.');
    final rom = File(
      resolve == null ? '$project/roms/${selected.rom}' : selected.rom,
    );
    if (!await rom.exists())
      throw StateError('Test ROM is missing: ${rom.path}');
    if (preparationLease case final inherited?) {
      if (!inherited.active ||
          inherited.key != await Directory(dataRoot).resolveSymbolicLinks())
        throw StateError('Save initialization has no active session owner');
      _guard = inherited;
    } else {
      _guard = await SessionLease.acquire(Directory(dataRoot));
    }
    try {
      final Map<String, dynamic> raw;
      final PreparedEmulator e;
      if (resolve != null) {
        _resolved = await resolve!(selected);
        if (_stopping || generation != _generation)
          throw StateError('Game preparation cancelled');
        e = _resolved!.emulator;
        raw = {
          'executable_sha256': _resolved!.executableHash,
          'native': _resolved!.native,
        };
      } else {
        final inventory = jsonDecode(await metadata.readAsString()) as Map;
        raw = Map<String, dynamic>.from(
          inventory['emulators'][selected.emulator] as Map,
        );
        e = PreparedEmulator.fromJson(raw);
      }
      _romPath = rom.path;
      emulator = e;
      game = selected;
      // Keep version-sensitive native ABI addresses tied to the exact prepared executable.
      final hash = await Process.run('/usr/bin/shasum', [
        '-a',
        '256',
        e.executable,
      ]).timeout(const Duration(seconds: 20));
      if (hash.exitCode != 0 ||
          (hash.stdout as String).split(' ').first !=
              raw['executable_sha256']) {
        throw StateError(
          'The prepared ${e.name} executable changed. Re-run prototype-prepare before using its bridge.',
        );
      }
      final bundled =
          '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/native/broomm-sdl${e.sdlMajor}.dylib';
      final bridge = Platform.isMacOS && await File(bundled).exists()
          ? bundled
          : '$project/build/native/broomm-sdl${e.sdlMajor}.dylib';
      if (!await File(bridge).exists())
        throw StateError(
          'Native bridge missing. Run devbox run prototype-prepare.',
        );
      log = SessionLog('${e.root}/broomm.log', onProblem: onProblem);
      log!.write('Launching ${selected.id} with ${e.name}');
      for (final path in [
        'config',
        'cache',
        'data',
        'saves',
        'states',
        'system',
        'screenshots',
      ]) {
        await Directory('${e.root}/$path').create(recursive: true);
      }
      if (e.name == 'RetroArch') {
        _retro = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        // Ask the OS for a free emulator endpoint; bind again is inherently racy,
        // and every reply is verified against the actual launched content below.
        final reservation = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        _retroPort = reservation.port;
        reservation.close();
        _retroSubscription = _retro!.listen((event) {
          if (event != RawSocketEvent.read) return;
          final datagram = _retro?.receive();
          if (datagram == null ||
              datagram.port != _retroPort ||
              !datagram.address.isLoopback)
            return;
          final text = utf8.decode(datagram.data, allowMalformed: true).trim();
          final pending = _retroReply;
          if (pending != null && !pending.isCompleted) pending.complete(text);
        });
      }
      final args = await EmulatorAdapter.forName(e.name)
          .prepare(e, selected, rom.path, _retroPort);
      _revision = 0;
      _sample = -1;
      status = null;
      _stopping = false;
      await command([], active: false);
      final snapshot = File('${e.root}/bridge-status.json');
      if (await snapshot.exists()) await snapshot.delete();
      if (testInputs) {
        // A retained private profile may have ended with a disconnected or
        // held synthetic source. Test controls are per-process commands, not
        // persistent profile preferences. Production never enables this path.
        await atomicText('${e.root}/test-input.txt', '0 0 3');
      }
      String quoted(String s) =>
          '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
      final deny = [
        Platform.environment['HOME'] != null
            ? '${Platform.environment['HOME']}/Library'
            : null,
        Platform.environment['HOME'] != null
            ? '${Platform.environment['HOME']}/.config'
            : null,
        '$project/roms',
        ...?_resolved?.readOnly,
        '/Users/ptrschneider/Projects/pgcs',
        '/Users/ptrschneider/Projects/teddy',
      ].whereType<String>();
      await atomicText(
        '${e.root}/readonly.sb',
        resolve == null
            ? '(version 1)\n(allow default)\n(deny file-write* ${deny.map((p) => '(subpath ${quoted(p)})').join(' ')})\n'
            : '(version 1)\n(allow default)\n(deny file-write* (require-all '
                  '(require-not (subpath ${quoted(await Directory(e.root).resolveSymbolicLinks())})) '
                  '(require-not (subpath ${quoted(await Directory.systemTemp.resolveSymbolicLinks())})) '
                  '(require-not (literal ${quoted('$dataRoot/writer.lock')}))))\n',
      );
      final process = await Process.start(
        '/usr/bin/sandbox-exec',
        [
          '-f',
          '${e.root}/readonly.sb',
          '/usr/bin/env',
          'DYLD_INSERT_LIBRARIES=$bridge',
          e.executable,
          ...args,
        ],
        workingDirectory: e.root,
        environment: {
          if (_resolved?.home != null) 'HOME': _resolved!.home!,
          'BROOMM_PROBE_LOG': '${e.root}/bridge.log',
          'BROOMM_SESSION': '1',
          'BROOMM_WRITER_LOCK': '$dataRoot/writer.lock',
          if (testInputs) 'BROOMM_SESSION_TEST': '1',
          if (testInputs && testPreconnected) 'BROOMM_TEST_PRECONNECTED': '1',
          if (testInputs) 'BROOMM_TEST_INPUT': '${e.root}/test-input.txt',
          if (testInputs && testMotion)
            'BROOMM_TEST_MOTION': '${e.root}/test-motion.txt',
          'BROOMM_SESSION_COMMAND': '${e.root}/bridge-command.txt',
          'BROOMM_SESSION_STATUS': snapshot.path,
          'BROOMM_SYMBOL_FILE': '${e.root}/local-symbols.txt',
          if (e.sdlLibrary != null) 'BROOMM_SDL_LIBRARY': e.sdlLibrary!,
          'SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS': '1',
          'SDL_GAMECONTROLLER_USE_BUTTON_LABELS': '0',
          if (selected.controllerTarget == ControllerTarget.wii) ...{
            'BROOMM_DOLPHIN_WII': '1',
            'BROOMM_WII_CONFIG': '${e.user}/Config/WiimoteNew.ini',
          },
          'XDG_CONFIG_HOME': '${e.root}/config',
          'XDG_CACHE_HOME': e.cacheDirectory ?? '${e.root}/cache',
          'XDG_DATA_HOME': '${e.root}/data',
          if (e.name == 'RPCS3') ...{
            'BROOMM_CACHE_FROM':
                '${Platform.environment['HOME']}/Library/Caches/rpcs3',
            'BROOMM_CACHE_TO': e.cacheDirectory ?? '${e.root}/cache',
          },
          if (e.name == 'RetroArch') 'BROOMM_RETROARCH': '1',
          if (e.name == 'Azahar' || e.name == 'Eden')
            'BROOMM_DEFER_SDL_WATCHES': '1',
          if (e.name == 'melonDS') 'BROOMM_MELONDS': '1',
          if (e.name == 'Eden') 'BROOMM_EDEN': '1',
          if (e.name == 'PPSSPP') ...{
            'BROOMM_PPSSPP': '1',
            'BROOMM_PSP_MEMSTICK': e.user,
          },
          if (e.name == 'DuckStation' ||
              e.name == 'PCSX2' ||
              e.name == 'ARMSX2')
            'BROOMM_PLAYSTATION': '1',
          if (e.name == 'Ryubing') 'BROOMM_PAUSE_APPKIT_F5': '1',
          // SDL 2.30's GCController notification can pump Avalonia reentrantly
          // from HID enumeration and deadlock the UI/SDL threads on macOS 27.
          // Keep HIDAPI/IOKit enabled; scope this workaround to this child.
          if (e.name == 'Ryubing') 'SDL_JOYSTICK_MFI': '0',
          ...Map<String, String>.from(raw['native'] as Map),
        },
      );
      _process = process;
      _lastUpdate = DateTime.now();
      final sessionLog = log!;
      var identityOutput = '';
      void output(List<int> bytes) {
        sessionLog.output(bytes);
      }

      void stdoutOutput(List<int> bytes) {
        output(bytes);
        if (e.name == 'Ryubing' && nativeProgramId == null) {
          identityOutput =
              '$identityOutput${String.fromCharCodes(bytes.take(32768))}';
          final match = RegExp(
            r'Loader Start: Application Loaded: [^\r\n]*\[(010[0-9a-fA-F]{13})\] \[64-bit\]',
          ).firstMatch(identityOutput);
          if (match != null) nativeProgramId = match[1]!.toLowerCase();
          if (identityOutput.length > 32768)
            identityOutput = identityOutput.substring(
              identityOutput.length - 32768,
            );
        }
      }

      final stdoutDone = Completer<void>(), stderrDone = Completer<void>();
      process.stdout.listen(
        stdoutOutput,
        onDone: stdoutDone.complete,
        onError: (Object e) {
          sessionLog.write('Emulator stdout failed: $e');
          if (!stdoutDone.isCompleted) stdoutDone.complete();
        },
      );
      process.stderr.listen(
        output,
        onDone: stderrDone.complete,
        onError: (Object e) {
          sessionLog.write('Emulator stderr failed: $e');
          if (!stderrDone.isCompleted) stderrDone.complete();
        },
      );
      _exitDone = process.exitCode.then((code) async {
        _timer?.cancel();
        _process = null;
        try {
          await Future.wait([stdoutDone.future, stderrDone.future])
              .timeout(const Duration(seconds: 1));
        } on TimeoutException {
          sessionLog.write(
            'Emulator output did not finish closing; ending log capture.',
          );
        }
        try {
          log?.write('Emulator exited with status $code');
        } catch (e) {
          onProblem?.call('Session logging failed: $e');
        }
        try {
          if (finalizeProgress != null) {
            finalizingProgress = true;
            onFinalizingProgress?.call();
          }
          await finalizeProgress?.call(code);
        } catch (e) {
          onProblem?.call(
            'Progress is retained locally; cloud save finalization failed: $e',
          );
        }
        try {
          await _release();
        } catch (e) {
          onProblem?.call('Session cleanup failed: $e');
        } finally {
          onExit?.call(code);
        }
      });
      _timer = Timer.periodic(
        const Duration(milliseconds: 32),
        (_) => unawaited(_poll(generation)),
      );
    } catch (_) {
      await _release();
      rethrow;
    }
  }

  Future<void> _poll(int generation) async {
    if (_polling || !running) return;
    final process = _process;
    _polling = true;
    try {
      final file = File('${emulator!.root}/bridge-status.json');
      if (await file.exists()) {
        if (await file.length() > 32768)
          throw StateError('Bridge response exceeded its limit');
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (!identical(process, _process) || generation != _generation) return;
        if (json['pid'] != process!.pid)
          throw StateError('Bridge belongs to a different process');
        final next = BridgeStatus(json);
        if (next.sample != _sample) {
          _bridgeLost = false;
          _lastUpdate = DateTime.now();
          _sample = next.sample;
          if (emulator!.name == 'RetroArch') {
            _retroMessage = next.blocked ? 'pause' : 'resume';
            unawaited(_updateRetro(generation));
            json['paused'] = _retroPaused;
          }
          status = BridgeStatus(json);
          if (emulator?.name == 'Eden' &&
              RegExp(r'^010[0-9a-f]{13}$')
                  .hasMatch(status?.nativeProgram ?? ''))
            nativeProgramId = status!.nativeProgram;
          onStatus?.call(status!);
          if (next.request == 'game-ended' && !_stopping) {
            unawaited(
              stop().catchError((Object e) {
                final problem =
                    'The game ended, but its emulator could not close: $e';
                onProblem?.call(problem);
                onControlLost?.call(problem);
              }),
            );
          }
        }
      }
      final silenceLimit = Duration(seconds: _sample < 0 ? 90 : 5);
      if (!_stopping &&
          !_bridgeLost &&
          DateTime.now().difference(_lastUpdate) > silenceLimit) {
        _bridgeLost = true;
        status = null; // A stale pause observation is not an acknowledgement.
        const problem =
            'The emulator’s controller bridge is not responding. '
            'Pause could not be confirmed. Close the emulator normally to end '
            'the session; Broomm has kept its local progress in place.';
        onProblem?.call(problem);
        onControlLost?.call(problem);
      }
    } catch (e) {
      if (generation == _generation && identical(process, _process))
        onProblem?.call('Controller bridge: $e');
    } finally {
      _polling = false;
    }
  }

  Future<String?> _queryRetro(String command) async {
    final socket = _retro;
    if (socket == null) return null;
    final reply = Completer<String>();
    _retroReply = reply;
    socket.send(
      utf8.encode('$command\n'),
      InternetAddress.loopbackIPv4,
      _retroPort,
    );
    try {
      return await reply.future.timeout(const Duration(milliseconds: 350));
    } on TimeoutException {
      return null;
    } finally {
      if (identical(_retroReply, reply)) _retroReply = null;
    }
  }

  Future<void> _updateRetro(int generation) async {
    if (_retroBusy || _stopping) return;
    _retroBusy = true;
    try {
      final state = await _queryRetro('GET_STATUS');
      if (generation != _generation || _stopping) return;
      if (state == null) return;
      if (!state.contains('PLAYING') && !state.contains('PAUSED')) return;
      // Never toggle a different network-command server's game.
      if (!retroStatusMatches(state, _romPath)) return;
      final paused = state.contains('PAUSED');
      final wanted = _retroMessage == 'pause';
      if (paused != wanted) {
        _retro!.send(
          utf8.encode('PAUSE_TOGGLE'),
          InternetAddress.loopbackIPv4,
          _retroPort,
        );
      }
      final after = await _queryRetro('GET_STATUS');
      if (generation == _generation &&
          after != null &&
          retroStatusMatches(after, _romPath))
        _retroPaused = after.contains('PAUSED') ? 1 : 0;
    } catch (e) {
      if (generation == _generation && running)
        onProblem?.call('RetroArch control: $e');
    } finally {
      if (generation == _generation) _retroBusy = false;
    }
  }

  Future<int> command(
    List<PlayerAssignment> players, {
    required bool active,
    bool quit = false,
  }) async {
    final e = emulator!;
    final generation = _generation;
    final ids = [
      for (var p = 0; p < 4; p++)
        p < players.length ? players[p].deviceId : 4294967295,
    ];
    final swaps = [
      for (var p = 0; p < 4; p++)
        p < players.length && players[p].swapFaces ? 1 : 0,
    ];
    final snapshot = List<PlayerAssignment>.of(players);
    final modes = [
      for (var p = 0; p < 4; p++)
        p < snapshot.length ? snapshot[p].wiiMode.index : WiiMode.nunchuk.index,
    ];
    final revision = ++_revision;
    final gyro = [
      for (var p = 0; p < 4; p++)
        p < snapshot.length && snapshot[p].gyroEnabled ? 1 : 0,
    ];
    final write = _commands.then((_) async {
      if (generation != _generation) throw StateError('The game session ended');
      if (game?.controllerTarget == ControllerTarget.wii && !quit) {
        await const DolphinAdapter().prepareWii(
          e,
          snapshot,
          revision,
          devices: status?.devices ?? [],
        );
      }
      await atomicText(
        '${e.root}/bridge-command.txt',
        '$revision ${active ? 1 : 0} ${active || quit ? 0 : 1} ${ids.join(' ')} ${swaps.join(' ')} ${quit ? 1 : 0} ${modes.join(' ')} ${gyro.join(' ')}\n',
      );
      return revision;
    });
    // Keep publication ordered, while allowing recovery after a failed write.
    // Each caller still receives its own error.
    _commands = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  Future<void> waitFor(
    bool Function(BridgeStatus) ready, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final process = _process;
    final until = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(until) &&
        process != null &&
        identical(process, _process)) {
      if (status != null && status!.pid == process.pid && ready(status!))
        return;
      await Future<void>.delayed(const Duration(milliseconds: 32));
    }
    throw StateError(
      identical(process, _process) && process != null
          ? 'The emulator did not acknowledge the controller/pause change '
                '(revision ${status?.ack}/$_revision, paused ${status?.paused}, '
                'input blocked ${status?.blocked}). You can retry or close the game.'
          : 'The emulator exited.',
    );
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) {
      _stopping = true;
      await _preparation?.stop();
      await _exitDone;
      return;
    }
    _stopping = true;
    await command([], active: false, quit: true);
    if (emulator!.name == 'RetroArch')
      _retro?.send(
        utf8.encode('QUIT'),
        InternetAddress.loopbackIPv4,
        _retroPort,
      );
    final result = await process.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw StateError(
        'The emulator is still open. Close its window normally, then try again. Broomm has kept the game and its data in place.',
      ),
    );
    await _exitDone;
    if (result != 0)
      throw StateError(
        'Emulator exited with status $result. Its local progress and logs have been retained.',
      );
  }

  Future<void> _release() async {
    finalizingProgress = false;
    ++_generation;
    _stopping = true;
    _resolved = null;
    _romPath = null;
    _timer?.cancel();
    await _commands;
    await log?.close();
    log = null;
    await _retroSubscription?.cancel();
    _retro?.close();
    _retro = null;
    _retroSubscription = null;
    final pending = _retroReply;
    _retroReply = null;
    if (pending != null && !pending.isCompleted) pending.complete('');
    final guard = _guard;
    _guard = null;
    if (guard != null && preparationLease == null) {
      await guard.release();
    }
  }

  /// Native cold initialization is supervised under the parent's unchanged
  /// lease. It closes normally before any cloud snapshot or restore can run.
  Future<String> initializeSwitchStorage(
    ResolvedSession resolved,
    LaunchGame game,
  ) async {
    final guard = _guard;
    if (guard == null ||
        !guard.active ||
        running ||
        !{'Ryubing', 'Eden'}.contains(resolved.emulator.name))
      throw StateError(
        'Switch save initialization needs the launch session owner',
      );
    final child = GameSession(
      project,
      managedRoot: dataRoot,
      resolve: (_) => Future.value(resolved),
      preparationLease: guard,
    );
    _preparation = child;
    try {
      await child.launch(game);
      await child.waitFor(
        (s) => s.inputReady && s.paused == 1 && child.nativeProgramId != null,
        timeout: const Duration(minutes: 2),
      );
      final program = child.nativeProgramId;
      if (program == null)
        throw StateError(
          'The Switch emulator did not acknowledge the loaded game identity.',
        );
      await child.stop();
      return program;
    } finally {
      if (child.running) await child.stop();
      _preparation = null;
    }
  }
}

bool retroStatusMatches(String status, String? rom) {
  if (rom == null) return false;
  final name = File(rom).uri.pathSegments.last;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final text = status.trim();
  if (!RegExp(r'^GET_STATUS (PLAYING|PAUSED) ').hasMatch(text)) return false;
  final separator = text.indexOf(',');
  if (separator < 0) return false;
  final content = text.substring(separator + 1);
  return content == stem ||
      RegExp('^${RegExp.escape(stem)},crc32=[0-9a-fA-F]+\$').hasMatch(content);
}
