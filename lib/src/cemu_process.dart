import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'emulators.dart';
import 'linux_runtime.dart';
import 'progress/file_hash.dart';
import 'progress/files.dart';
import 'session.dart' show ResolvedSession;

int _launcherProcessId() => pid;

/// A retained native process plus an unpredictable admission receipt. The
/// Windows launcher is a pre-entry injector; its exit waits for the actual Cemu
/// child. Cemu itself holds writer.lock on every host, through launcher death.
abstract interface class CemuControlProcess {
  int get pid;
  Map<String, Object>? get target;
  Future<void> admit();
  Future<Map<String, dynamic>?> receipt();
  Future<int> command({required bool active, bool quit = false});
  Future<bool> state({bool? paused});
}

class CemuProcess implements Process, CemuControlProcess {
  CemuProcess._(
    this._child,
    this.root,
    this.executable,
    this.writer,
    this.guard,
    this.token,
    this.secondaryTitles,
  ) : _pid = _child.pid;
  static const channel = MethodChannel('app.broomm/remote');
  final Process _child;
  final String root, executable, writer, guard, token;
  final List<String> secondaryTitles;
  int _pid;
  int _revision = 0;
  Map<String, dynamic>? _identity;
  Map<String, dynamic>? _latest;
  bool _ended = false;
  bool get admitted => _identity != null;
  static Future<CemuProcess> start({
    required ResolvedSession resolved,
    required String dataRoot,
    required String project,
    required List<String> arguments,
    bool supervised = false,
  }) async {
    final e = resolved.emulator;
    if (await gameFileHash(e.executable) != resolved.executableHash)
      throw StateError(
        'Cemu’s private executable changed. Existing progress was kept; verify setup.',
      );
    final name = Platform.isMacOS
        ? 'broomm-cemu.dylib'
        : Platform.isWindows
        ? 'broomm-cemu-guard.dll'
        : 'broomm-cemu.so';
    final packaged = Platform.isMacOS
        ? '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/native/$name'
        : Platform.isWindows
        ? '${File(Platform.resolvedExecutable).parent.path}/$name'
        : '${File(Platform.resolvedExecutable).parent.path}/lib/$name';
    final guard = await File(packaged).exists()
        ? packaged
        : '$project/build/native/$name';
    if (Platform.isMacOS && guard.contains(':'))
      throw StateError(
        'The Cemu bridge path contains a colon. Move Broomm to a path without colons.',
      );
    if (!await File(guard).exists())
      throw StateError(
        'The Cemu writer bridge is missing. Use a complete Broomm build.',
      );
    final nonce = '${progressNonce()}${progressNonce()}';
    final root = await Directory(e.root).resolveSymbolicLinks();
    final writer =
        '${await Directory(dataRoot).resolveSymbolicLinks()}/writer.lock';
    final state = File('$root/cemu-status.json');
    if (await state.exists()) await state.delete();
    await atomicText('$root/cemu-command.txt', '$nonce 1 0 0\n');
    for (final dir in ['home', 'config', 'data', 'cache'])
      await Directory('$root/$dir').create(recursive: true);
    final environment = <String, String>{
      'BROOMM_CEMU_SUPERVISED': supervised ? '1' : '0',
      'HOME': resolved.home ?? '$root/home',
      'XDG_CONFIG_HOME': '$root/config',
      'XDG_DATA_HOME': '$root/data',
      'XDG_CACHE_HOME': '$root/cache',
      'TMPDIR': '$root/cache',
      if (Platform.isLinux) ...linuxLaunchEnvironment(e),
      if (Platform.isLinux) 'GDK_BACKEND': 'x11',
      'BROOMM_CEMU_ROOT': root,
      'BROOMM_CEMU_WRITER': writer,
      'BROOMM_CEMU_STATUS': state.path,
      'BROOMM_CEMU_COMMAND': '$root/cemu-command.txt',
      'BROOMM_CEMU_TOKEN': nonce,
      if (e.remoteScreen) 'BROOMM_REMOTE_SCREEN': '1',
      ...resolved.native,
    };
    final Process process;
    if (Platform.isMacOS) {
      String quote(String value) =>
          '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
      final policy = '$root/cemu-readonly.sb';
      await atomicText(
        policy,
        '(version 1)\n(allow default)\n(deny file-write* (require-all '
        '(require-not (subpath ${quote(root)})) '
        '(require-not (subpath ${quote(await Directory.systemTemp.resolveSymbolicLinks())})) '
        '(require-not (literal ${quote(writer)}))))\n',
      );
      process = await Process.start(
        '/usr/bin/sandbox-exec',
        [
          '-f',
          policy,
          '/usr/bin/env',
          'DYLD_INSERT_LIBRARIES=$guard',
          e.executable,
          ...arguments,
        ],
        workingDirectory: root,
        environment: environment,
      );
    } else if (Platform.isLinux) {
      final preload = await prepareLinuxBridge(guard, root);
      process = await Process.start(
        e.executable,
        arguments,
        workingDirectory: root,
        environment: {
          ...environment,
          'LD_PRELOAD': [
            preload,
            if ((Platform.environment['LD_PRELOAD'] ?? '').isNotEmpty)
              Platform.environment['LD_PRELOAD']!,
          ].join(':'),
        },
      );
    } else if (Platform.isWindows) {
      if (supervised) {
        final launcherPid = _launcherProcessId();
        final owner = await channel
            .invokeMapMethod<String, Object>('processIdentity')
            .timeout(const Duration(seconds: 2));
        if (owner?['pid'] != launcherPid ||
            owner?['birth'] is! String ||
            !RegExp(r'^[0-9]{1,20}$').hasMatch(owner!['birth'] as String))
          throw StateError(
            'Windows could not confirm the Cemu launcher identity.',
          );
        environment['BROOMM_CEMU_LAUNCHER_PID'] = '$launcherPid';
        environment['BROOMM_CEMU_LAUNCHER_BIRTH'] = owner['birth'] as String;
      }
      final helper = '${File(guard).parent.path}/broomm-cemu-run.exe';
      if (!await File(helper).exists())
        throw StateError(
          'The Cemu Windows launcher is missing. Use a complete Broomm package.',
        );
      process = await Process.start(
        helper,
        [guard, e.executable, ...arguments],
        workingDirectory: root,
        environment: environment,
      );
    } else {
      throw UnsupportedError('Cemu hosting is available on desktop only.');
    }
    final titles = (resolved.native['BROOMM_CEMU_PAD_TITLES'] ?? 'GamePad View')
        .split('|');
    final result = CemuProcess._(
      process,
      root,
      e.executable,
      writer,
      guard,
      nonce,
      titles,
    );
    unawaited(process.exitCode.then((_) => result._ended = true));
    return result;
  }

  Map<String, Object>? get target {
    final identity = _identity;
    if (identity == null || _ended) return null;
    return {
      'name': 'Cemu',
      'pid': pid,
      'executable': executable,
      'writer': writer,
      'secondaryTitles': secondaryTitles,
      if (_latest?['remoteCapture'] is List &&
          (_latest!['remoteCapture'] as List).length == 5 &&
          (_latest!['remoteCapture'] as List).first is num &&
          ((_latest!['remoteCapture'] as List).first as num) > 0)
        'remoteCapture': _latest!['remoteCapture'] as List,
      if (Platform.isMacOS) ...{
        'seconds': identity['seconds'] as int,
        'microseconds': identity['microseconds'] as int,
      } else
        'birth': identity['birth'] as String,
      if (Platform.isWindows) ...{'guard': guard, 'guardToken': token},
    };
  }

  Future<Map<String, dynamic>?> receipt() async {
    final file = File('$root/cemu-status.json');
    if (!await file.exists()) return null;
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > 2048)
      throw StateError(
        'Cemu’s native receipt is invalid. Input remains blocked.',
      );
    final data = jsonDecode(await file.readAsString());
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['token'] != token ||
        data['pid'] is! int ||
        data['pid'] < 1 ||
        data['ack'] is! int ||
        data['ack'] < 0 ||
        data['sample'] is! int ||
        data['sample'] < 1 ||
        data['applicationReady'] is! bool ||
        data['title'] is! String ||
        !RegExp(r'^[0-9a-f]{16}$').hasMatch(data['title']) ||
        (!Platform.isMacOS &&
            (data['birth'] is! String ||
                !RegExp(r'^[0-9]{1,20}$').hasMatch(data['birth']))) ||
        (Platform.isMacOS &&
            (data['seconds'] is! int ||
                data['seconds'] < 1 ||
                data['microseconds'] is! int ||
                data['microseconds'] < 0 ||
                data['microseconds'] >= 1000000)))
      throw StateError(
        'Cemu did not confirm its native writer identity. Input remains blocked.',
      );
    if (_identity == null) {
      if (!Platform.isWindows && data['pid'] != _child.pid)
        throw StateError('Cemu’s native receipt belongs to another process.');
      _identity = data;
      _pid = data['pid'];
    } else if (data['pid'] != pid ||
        data['birth'] != _identity!['birth'] ||
        data['seconds'] != _identity!['seconds'] ||
        data['microseconds'] != _identity!['microseconds']) {
      throw StateError(
        'Cemu’s writer identity changed. Input remains blocked.',
      );
    }
    _latest = data;
    return data;
  }

  Future<void> admit() async {
    final until = DateTime.now().add(const Duration(seconds: 15));
    while (!_ended && DateTime.now().isBefore(until)) {
      if ((await receipt())?['applicationReady'] == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw StateError(
      _ended ? 'Cemu exited before establishing its private writer.' : 'Cemu has not confirmed its writer. Close its window normally; local progress remains protected.',
    );
  }

  Future<int> command({required bool active, bool quit = false}) async {
    final revision = ++_revision;
    await atomicText(
      '$root/cemu-command.txt',
      '$token ${revision + 1} ${active ? 1 : 0} ${quit ? 1 : 0}\n',
    );
    return revision + 1;
  }

  Future<bool> state({bool? paused}) async {
    final identity =
        target ?? (throw StateError('Cemu’s process identity is unavailable.'));
    final value = await channel
        .invokeMapMethod<String, Object>('cemuState', {
          ...identity,
          if (paused != null) 'paused': paused,
        })
        .timeout(const Duration(seconds: 4));
    if (value?['paused'] is! bool)
      throw StateError(
        'The operating system did not confirm Cemu’s pause state.',
      );
    if (paused != null && value!['paused'] != paused)
      throw StateError('Cemu did not reach the requested kernel pause state.');
    return value!['paused'] as bool;
  }

  @override
  int get pid => _pid;
  @override
  Future<int> get exitCode => _child.exitCode;
  @override
  Stream<List<int>> get stdout => _child.stdout;
  @override
  Stream<List<int>> get stderr => _child.stderr;
  @override
  IOSink get stdin => _child.stdin;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => false;
}
