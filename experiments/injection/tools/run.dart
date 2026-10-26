// Research launcher only. Uses literal arguments and private bundle/config copies.
import 'dart:convert';
import 'dart:io';

import 'control-file.dart';
import 'retroarch-command.dart' as retro_control;

final root = Directory.current.absolute.path;
final base = '$root/experiments/injection';

Future<ProcessResult> command(String executable, List<String> args) async {
  final result = await Process.run(executable, args);
  if (result.exitCode != 0) {
    throw StateError('$executable exited ${result.exitCode}: ${result.stderr}');
  }
  return result;
}

Future<void> stopFixtureChildren() async {
  // RPCS3 can spawn a separate fatal-error dialog after its parent exits.
  // Only this experiment's copied executable paths qualify for cleanup.
  for (var attempt = 0; attempt < 30; attempt++) {
    final result = await Process.run('/bin/ps', ['-axo', 'pid=,comm=']);
    if (result.exitCode != 0)
      throw StateError('Cannot verify private fixture processes');
    var found = false;
    for (final line in const LineSplitter().convert(result.stdout as String)) {
      final match = RegExp(r'^\s*(\d+)\s+(.+)$').firstMatch(line);
      if (match != null &&
          match[2]!.startsWith('$base/sessions/') &&
          match[2]!.contains('.app/Contents/MacOS/')) {
        found = true;
        Process.killPid(
          int.parse(match[1]!),
          attempt < 20 ? ProcessSignal.sigterm : ProcessSignal.sigkill,
        );
      }
    }
    if (!found) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Private emulator test did not stop');
}

Future<void> main(List<String> args) async {
  if (args.length < 2 || !['prepare', 'run'].contains(args[0])) {
    stderr.writeln(
      'Usage: dart run.dart prepare|run RetroArch|Dolphin|RPCS3|Azahar|Ryubing [emulator arguments...]',
    );
    exitCode = 64;
    return;
  }
  final inventory = jsonDecode(
    await File('$base/artifacts/local-installations.json').readAsString(),
  ) as Map;
  final name = args[1];
  final original = inventory[name] as Map?;
  if (original == null) throw ArgumentError('Unknown emulator $name');
  final session = '$base/sessions/${name.toLowerCase()}';
  final bundleName = (original['bundle'] as String).split('/').last;
  final bundle = '$session/$bundleName';
  final relativeExecutable = (original['executable'] as String).substring(
    (original['bundle'] as String).length,
  );
  final executable = '$bundle$relativeExecutable';
  await Directory(session).create(recursive: true);
  if (!await Directory(bundle).exists()) {
    await command('/bin/cp', ['-cR', original['bundle'] as String, bundle]);
  }
  // RPCS3's macOS executable-dir helper deliberately resolves outside the bundle.
  final user = name == 'RPCS3' ? '$session/portable' : '$session/user';
  await Directory(user).create(recursive: true);
  await Directory('$session/user').create(recursive: true);
  for (final path in [
    'config',
    'cache',
    'data',
    'saves',
    'states',
    'screenshots',
    'system',
  ]) {
    await Directory('$session/$path').create(recursive: true);
  }
  final metadata = {
    'name': name,
    'bundle': bundle,
    'executable': executable,
    'user': user,
    'sdl_major': original['sdl_major'],
    if (original['sdl_library'] != null)
      'sdl_library': (original['sdl_library'] as String).replaceFirst(
        original['bundle'] as String,
        bundle,
      ),
  };
  await File('$session/installation.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(metadata));
  if (args[0] == 'prepare') {
    stdout.writeln('Prepared private $name bundle and data root in $session');
    return;
  }
  final guard = await File('$base/sessions/session.lock')
      .open(mode: FileMode.append);
  await guard.lock(FileLock.blockingExclusive);
  await stopFixtureChildren();
  final control = File('$session/control.txt');
  await publishControl(control.path, 0, 0, 0);
  final probeLog = File('$session/probe.log');
  final stamp = DateTime.now().microsecondsSinceEpoch;
  for (final name in ['probe', 'process']) {
    for (var part = 0; part < 10; part++) {
      final old = File('$session/$name.log${part == 0 ? '' : '.$part'}');
      if (old.existsSync())
        await old.rename(
          '$session/$name-$stamp.log${part == 0 ? '' : '.$part'}',
        );
    }
  }
  await probeLog.writeAsString('');
  final log = File('$session/process.log').openWrite();
  final denyPaths = [
    '${Platform.environment['HOME']}/Library',
    '${Platform.environment['HOME']}/.config',
    '$root/roms',
    '/Users/ptrschneider/Projects/pgcs',
    '/Users/ptrschneider/Projects/teddy',
  ];
  String seatbeltString(String s) =>
      '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  final sandbox = File('$session/readonly-inputs.sb');
  await sandbox.writeAsString(
    '(version 1)\n(allow default)\n(deny file-write* ${denyPaths.map((p) => '(subpath ${seatbeltString(p)})').join(' ')})\n',
  );
  final childArgs = <String>[
    if (name == 'Dolphin') ...['-u', user],
    if (name == 'Ryubing') ...['-r', user],
    ...args.skip(2),
  ];
  final nativeSymbols = <String, String>{};
  final allSymbols =
      (await command('/usr/bin/nm', ['-arch', 'arm64', executable])).stdout
          as String;
  final symbolFile = File('$session/local-symbols.txt');
  await symbolFile.writeAsString(
    RegExp(
      r'^([0-9a-f]+) [tT] _(SDL_\S+|_ZNK11GMainWindow10metaObjectEv|_ZNK11main_window10metaObjectEv|_ZN11GMainWindow11OnPauseGameEv|_ZN11GMainWindow12OnResumeGameEb|_ZN11main_window13OnPlayOrPauseEv)$',
      multiLine: true,
    ).allMatches(allSymbols).map((m) => '${m[1]} ${m[2]}').join('\n'),
  );
  if (name == 'Dolphin') {
    final symbols = allSymbols;
    for (final entry in {
      'BROOMM_CORE_SYSTEM': '__ZN4Core6System11GetInstanceEv',
      'BROOMM_CORE_STATE': '__ZN4Core8GetStateERNS_6SystemE',
      'BROOMM_CORE_SET_STATE': '__ZN4Core8SetStateERNS_6SystemENS_5StateEbb',
    }.entries) {
      final match = RegExp(
        '^([0-9a-f]+) [tT] ${entry.value}\$',
        multiLine: true,
      ).firstMatch(symbols);
      if (match == null)
        throw StateError(
          'Pinned Dolphin control symbol missing: ${entry.value}',
        );
      nativeSymbols[entry.key] = match[1]!;
    }
  }
  if (name == 'RPCS3') {
    final status = RegExp(
      r'^([0-9a-f]+) [SBD] _Emu$',
      multiLine: true,
    ).firstMatch(allSymbols);
    if (status == null) throw StateError('RPCS3 status object symbol missing');
    nativeSymbols['BROOMM_EMU_STATUS'] = status[1]!;
  }
  // Apple platform tools strip DYLD_* before their own main(). Supply the
  // insertion path to env as data, inside seatbelt, immediately before exec.
  final process = await Process.start(
    '/usr/bin/sandbox-exec',
    [
      '-f',
      sandbox.path,
      '/usr/bin/env',
      if (Platform.environment['BROOMM_NO_INJECT'] != '1')
        'DYLD_INSERT_LIBRARIES=$base/build/probe-sdl${original['sdl_major']}.dylib',
      executable,
      ...childArgs,
    ],
    workingDirectory: session,
    environment: {
      'BROOMM_PROBE_LOG': probeLog.path,
      'BROOMM_PROBE_CONTROL': control.path,
      'BROOMM_SYMBOL_FILE': symbolFile.path,
      'BROOMM_VIRTUAL_PADS': '1',
      if (metadata['sdl_library'] != null)
        'BROOMM_SDL_LIBRARY': metadata['sdl_library'] as String,
      'SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS': '1',
      'SDL_JOYSTICK_HIDAPI': '0',
      'XDG_CONFIG_HOME': '$session/config',
      'XDG_CACHE_HOME': '$session/cache',
      'XDG_DATA_HOME': '$session/data',
      if (name == 'RPCS3') ...{
        'BROOMM_CACHE_FROM':
            '${Platform.environment['HOME']}/Library/Caches/rpcs3',
        'BROOMM_CACHE_TO': '$session/cache',
      },
      if (name == 'Ryubing') 'BROOMM_PAUSE_APPKIT_F5': '1',
      ...nativeSymbols,
    },
  );
  stdout.writeln('$name pid=${process.pid}; logs=$session');
  process.stdout.listen(log.add);
  process.stderr.listen(log.add);
  final result = process.exitCode;
  var exited = false;
  result.then((_) => exited = true);
  final seconds =
      int.tryParse(Platform.environment['BROOMM_PROBE_SECONDS'] ?? '') ?? 36;
  for (var second = 0; second < seconds && !exited; second++) {
    if (name == 'RetroArch' && (second == 16 || second == 20)) {
      final replies = await retro_control.commands([
        'GET_STATUS',
        'PAUSE_TOGGLE',
        'GET_STATUS',
      ]);
      await File('$session/command-status.log')
          .writeAsString(replies.join('\n'), mode: FileMode.append);
    }
    if (second == 12) await publishControl(control.path, 1, 1, 0);
    if (second == 16) await publishControl(control.path, 1, 1, 1);
    if (second == 20) await publishControl(control.path, 1, 1, 0);
    if (second == 22) await publishControl(control.path, 2, 1, 0);
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  if (!exited) {
    process.kill(ProcessSignal.sigterm);
    await Future.any([
      result,
      Future<void>.delayed(const Duration(seconds: 5)),
    ]);
    if (!exited) process.kill(ProcessSignal.sigkill);
  }
  final status = await result;
  await stopFixtureChildren();
  await log.close();
  await guard.unlock();
  await guard.close();
  stdout.writeln(
    '$name exit=$status; probe log bytes=${await probeLog.length()}',
  );
}
