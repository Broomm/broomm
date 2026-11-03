import 'dart:io';
import 'dart:async';

import 'emulators.dart';
import 'romm/transfer.dart';

String linuxLaunchExecutable(PreparedEmulator emulator) =>
    emulator.linuxLauncher ?? emulator.executable;

// Azahar gives a cwd/user directory precedence over XDG. Every managed profile
// has a generic user directory, so launch from its private HOME to keep Azahar
// on the reviewed XDG aliases and the save/configuration tree Dart actually uses.
// Eden has the same cwd/user precedence; its Sharun loader must retain that cwd.
String linuxLaunchDirectory(PreparedEmulator emulator) =>
    {'Azahar', 'Eden'}.contains(emulator.name)
    ? '${emulator.root}/home'
    : emulator.root;

String linuxLaunchPreload(PreparedEmulator emulator, String relative) =>
    {'Azahar', 'Eden'}.contains(emulator.name)
    ? '../${relative.substring(2)}'
    : relative;

/// Use the reviewed bundle's own loader/libraries. In particular Sharun needs
/// its documented preload opt-in; invoking the native ELF with the host loader
/// would require a newer system glibc than Ubuntu's supported baseline.
Map<String, String> linuxLaunchEnvironment(PreparedEmulator emulator) {
  // This build already has $ORIGIN/../lib RUNPATH and explicitly warns before
  // SDL initialization if LD_LIBRARY_PATH is present. Keep the host override
  // out of this child rather than dismissing the emulator's warning dialog.
  if (emulator.name == 'DuckStation') return {'LD_LIBRARY_PATH': ''};
  if (emulator.linuxLauncher != null)
    return {
      'SHARUN_ALLOW_LD_PRELOAD': '1',
      'SHARUN_PRINTENV': '0',
      'SHARUN_WORKING_DIR': linuxLaunchDirectory(emulator),
    };
  final binary = File(emulator.executable);
  final libraries = emulator.name == 'RetroArch'
      ? File(emulator.sdlLibrary!).parent.path
      : emulator.name == 'Ryubing'
      ? binary.parent.path
      : '${binary.parent.parent.path}/lib';
  return {'LD_LIBRARY_PATH': libraries};
}

/// Publishes the renderer-ready signal once per launch. Status queries can
/// overlap a slow durable write; shutdown drains that write before reuse.
class LinuxWindowReadiness {
  LinuxWindowReadiness(this.publish);
  final Future<void> Function() publish;
  Future<void>? _work;
  bool _complete = false, _closed = false;
  Future<void> ready() {
    if (_closed || _complete) return Future<void>.value();
    return _work ??= Future<void>.sync(publish)
        .then((_) {
          _complete = true;
        })
        .whenComplete(() {
          _work = null;
        });
  }

  Future<void> close() async {
    _closed = true;
    try {
      await _work;
    } catch (_) {
      /* The caller reports publication failure. */
    }
  }
}

/// Stages Broomm's own small native component, never an emulator or save.
/// A relative preload path also works when the app/storage path contains spaces.
Future<String> prepareLinuxBridge(
  String source,
  String profile, {
  bool runner = false,
}) async {
  final root = Directory('$profile/.broomm-runtime');
  final type = await FileSystemEntity.type(root.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    await root.create();
    await File('${root.path}/owner')
        .writeAsString('Broomm Linux runtime 1\n', flush: true);
  } else if (type != FileSystemEntityType.directory ||
      await FileSystemEntity.type('${root.path}/owner', followLinks: false) !=
          FileSystemEntityType.file ||
      await File('${root.path}/owner').readAsString() !=
          'Broomm Linux runtime 1\n') {
    throw StateError(
      'The private native runtime has unknown ownership. Existing files were kept.',
    );
  }
  final name = runner ? 'broomm-native-run' : 'bridge.so';
  final target = File('${root.path}/$name');
  final targetType = await FileSystemEntity.type(
    target.path,
    followLinks: false,
  );
  if (targetType != FileSystemEntityType.notFound &&
      targetType != FileSystemEntityType.file)
    throw StateError(
      'The private native bridge is linked or invalid. Existing files were kept.',
    );
  final stage = await root.createTemp('.publish-');
  try {
    final file = File('${stage.path}/$name');
    final bytes = await File(source).readAsBytes();
    if (bytes.length > 4 * 1024 * 1024 ||
        bytes.length < 64 ||
        bytes[0] != 0x7f ||
        bytes[1] != 69 ||
        bytes[2] != 76 ||
        bytes[3] != 70)
      throw StateError(
        'The packaged Linux native bridge is incomplete. Use a complete Broomm build.',
      );
    await file.writeAsBytes(bytes, flush: true);
    if (runner) {
      final result = await Process.run('/bin/chmod', ['u+x', file.path]);
      if (result.exitCode != 0)
        throw const FileSystemException(
          'Could not prepare the private Linux process helper.',
        );
    }
    final copied = await file.readAsBytes();
    if (copied.length != bytes.length ||
        Iterable<int>.generate(bytes.length).any((i) => bytes[i] != copied[i]))
      throw const FileSystemException('Native bridge readback failed.');
    await file.rename(target.path);
  } finally {
    if (await stage.exists()) await stage.delete(recursive: true);
  }
  return './.broomm-runtime/$name';
}

/// A reviewed native installation command. The packaged supervisor confines
/// writes before exec and retains its inherited writer lock until every child
/// exits. All installation/publication decisions remain in Dart.
Future<Process> startLinuxInstallation(
  String executable,
  List<String> arguments,
  Directory stage, {
  String? writer,
  bool requiresDisplay = false,
  Map<String, String> environment = const {},
}) async {
  final root = await stage.resolveSymbolicLinks();
  final packaged = '${File(Platform.resolvedExecutable).parent.path}/lib';
  final development = '${Directory.current.path}/build/native';
  final sourceHelper = await File('$packaged/broomm-native-run').exists()
      ? '$packaged/broomm-native-run'
      : '$development/broomm-native-run';
  final guard = await File('$packaged/broomm-installer.so').exists()
      ? '$packaged/broomm-installer.so'
      : '$development/broomm-installer.so';
  if (!await File(sourceHelper).exists() || !await File(guard).exists())
    throw StateError(
      'The Linux installation components are missing. Use a complete Broomm build.',
    );
  for (final name in ['home', 'config', 'data', 'cache', 'tmp']) {
    final directory = Directory('$root/$name');
    final kind = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (kind != FileSystemEntityType.notFound &&
        kind != FileSystemEntityType.directory)
      throw const FileSystemException(
        'Linked installation directory was kept.',
      );
    await directory.create(recursive: true);
  }
  final relativeHelper = await prepareLinuxBridge(
    sourceHelper,
    root,
    runner: true,
  );
  final helper = File('$root/${relativeHelper.substring(2)}').absolute.path;
  final binary = File(await File(executable).resolveSymbolicLinks());
  final libraries = binary.path.endsWith('/Ryujinx')
      ? binary.parent.path
      : '${binary.parent.parent.path}/lib';
  final child = await Process.start(
    helper,
    [root, root, binary.path, ...arguments],
    workingDirectory: root,
    includeParentEnvironment: false,
    environment: {
      'HOME': '$root/home',
      'XDG_CONFIG_HOME': '$root/config',
      'XDG_DATA_HOME': '$root/data',
      'XDG_CACHE_HOME': '$root/cache',
      'TMPDIR': '$root/tmp',
      'PATH': '/usr/bin:/bin',
      'LANG': 'C.UTF-8',
      'LD_LIBRARY_PATH': libraries,
      'LD_PRELOAD': guard,
      'QT_QPA_PLATFORM': requiresDisplay
          ? (Platform.environment['DISPLAY']?.isNotEmpty == true
                ? 'xcb'
                : 'wayland')
          : 'offscreen',
      if (requiresDisplay)
        for (final key in [
          'DISPLAY',
          'WAYLAND_DISPLAY',
          'XAUTHORITY',
          'XDG_RUNTIME_DIR',
        ])
          if (Platform.environment[key] case final value?) key: value,
      'BROOMM_INSTALLER_ROOT': root,
      'BROOMM_SESSION_EXECUTABLE': binary.path,
      if (writer != null) 'BROOMM_WRITER_LOCK': writer,
      ...environment,
    },
  );
  return _LinuxInstallationProcess(child);
}

/// Cancellation must reach the supervisor, which kills and reaps its complete
/// child tree. Killing that supervisor itself would lose proof of child exit.
class _LinuxInstallationProcess implements Process {
  _LinuxInstallationProcess(this.child);
  final Process child;
  Future<int>? _exit;
  @override
  int get pid => child.pid;
  @override
  IOSink get stdin => child.stdin;
  @override
  Stream<List<int>> get stdout => child.stdout;
  @override
  Stream<List<int>> get stderr => child.stderr;
  @override
  Future<int> get exitCode => _exit ??= child.exitCode.then((code) {
    if (code < 0)
      throw const DownloadWriterUncertain(
        'The Linux installer stopped without confirming that all native writers closed. Its private data was kept. Close the installer before retrying.',
      );
    return code;
  });
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => child.kill(
    signal == ProcessSignal.sigkill ? ProcessSignal.sigterm : signal,
  );
}
