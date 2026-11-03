import 'dart:convert';
import 'dart:io';

import 'host.dart';

const broommDesktopId = 'app.broomm.broomm';
const _launcherOwner = 'X-Broomm-Managed=true';

String _desktopString(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r')
    .replaceAll('\t', r'\t');

String _execArgument(String value) {
  // Desktop strings are decoded before Exec quoting and percent expansion.
  final quoted = value
      .replaceAllMapped(RegExp(r'[\\"`$]'), (m) => '\\${m[0]}')
      .replaceAll('%', '%%');
  return _desktopString('"$quoted"');
}

class LauncherInstallation {
  const LauncherInstallation(this.desktopFile, this.fileIconApplied);
  final String desktopFile;
  final bool fileIconApplied;
}

/// The user explicitly installs a launcher for this bundle. No app relocation,
/// global installation, shell command or emulator/profile mutation is involved.
class LinuxLauncher {
  LinuxLauncher({
    bool? enabled,
    Map<String, String>? environment,
    String? executable,
    Future<bool> Function()? fileIcon,
  }) : enabled = enabled ?? Platform.isLinux,
       environment = environment ?? Platform.environment,
       executable = executable ?? Platform.resolvedExecutable,
       fileIcon = fileIcon ?? DesktopHost().setExecutableIcon;
  final bool enabled;
  final Map<String, String> environment;
  final String executable;
  final Future<bool> Function() fileIcon;
  bool _busy = false;

  Directory get dataHome {
    final xdg = environment['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty && File(xdg).isAbsolute) {
      _path(xdg);
      return Directory(xdg);
    }
    final home = environment['HOME'];
    if (home == null || home.isEmpty || !File(home).isAbsolute)
      throw StateError(
        'Your home directory could not be found. Set HOME or an absolute XDG_DATA_HOME and retry.',
      );
    _path(home);
    return Directory('$home/.local/share');
  }

  static void _path(String value) {
    if (value.length > 4096 || value.contains(RegExp(r'[\x00-\x1f\x7f]')))
      throw const FormatException(
        'The application or launcher directory has an unsupported path.',
      );
  }

  Future<LauncherInstallation> install() async {
    if (!enabled)
      throw UnsupportedError('Launcher installation is available on Linux.');
    if (_busy) throw StateError('Launcher installation is already running.');
    _busy = true;
    RandomAccessFile? lock;
    try {
      _path(executable);
      final binary = File(await File(executable).resolveSymbolicLinks());
      _path(binary.path);
      if ((await binary.stat()).mode & 0x49 == 0)
        throw StateError(
          'Broomm is not executable. Extract the complete application bundle and retry.',
        );
      // GIO checks the executable before expanding %% in Exec, rejecting even
      // correctly escaped percent signs. Fail before publishing a dead entry.
      if (binary.path.contains('=') || binary.path.contains('%'))
        throw StateError(
          'Your desktop launcher cannot use an executable path containing = or %. Move Broomm to another folder and retry.',
        );
      final source = File('${binary.parent.path}/data/broomm.png');
      await _regular(source);
      if (!await source.exists() || await source.length() > 2 * 1024 * 1024)
        throw StateError(
          'The application icon is missing. Extract the complete Broomm bundle and retry.',
        );
      final iconBytes = await source.readAsBytes();
      if (iconBytes.length < 8 ||
          !const [
            137,
            80,
            78,
            71,
            13,
            10,
            26,
            10,
          ].asMap().entries.every((e) => iconBytes[e.key] == e.value))
        throw StateError(
          'The bundled Broomm icon is invalid. Extract the complete application bundle and retry.',
        );
      final home = dataHome;
      await home.create(recursive: true);
      final base = await home.resolveSymbolicLinks();
      final apps = Directory('$base/applications');
      final icons = Directory('$base/icons/hicolor/512x512/apps');
      await _directory(apps);
      final guard = File('${apps.path}/.$broommDesktopId.install.lock');
      await _regular(guard);
      lock = await guard.open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      final desktop = File('${apps.path}/$broommDesktopId.desktop');
      final icon = File('${icons.path}/$broommDesktopId.png');
      await _regular(desktop);
      await _regular(icon);
      final exists = await desktop.exists();
      if (exists &&
          (await desktop.length() > 16384 ||
              !const LineSplitter()
                  .convert(await desktop.readAsString())
                  .contains(_launcherOwner)))
        throw StateError(
          'A launcher already exists at ${desktop.path}. It was kept. Move it aside before installing this Broomm launcher.',
        );
      if (!exists &&
          await icon.exists() &&
          (await icon.length() > 2 * 1024 * 1024 ||
              !_same(await icon.readAsBytes(), iconBytes)))
        throw StateError(
          'A different application icon already exists at ${icon.path}. It was kept.',
        );
      await _directory(icons);
      final text =
          '[Desktop Entry]\nType=Application\nName=Broomm\n'
          'Comment=Your games, together.\n'
          'Exec=${_execArgument(binary.path)}\n'
          'TryExec=${_desktopString(binary.path)}\n'
          'Path=${_desktopString(binary.parent.path)}\n'
          'Icon=$broommDesktopId\nTerminal=false\nCategories=Game;\n'
          'StartupNotify=true\nStartupWMClass=$broommDesktopId\n$_launcherOwner\n';
      await _publish(icon, iconBytes);
      await _publish(desktop, utf8.encode(text));
      // Optional file-manager metadata must never undo a successful launcher.
      var applied = false;
      try {
        applied = await fileIcon();
      } catch (_) {
        /* UI reports availability. */
      }
      return LauncherInstallation(desktop.path, applied);
    } finally {
      try {
        await lock?.close();
      } finally {
        _busy = false;
      }
    }
  }
}

bool _same(List<int> a, List<int> b) =>
    a.length == b.length && a.asMap().entries.every((e) => e.value == b[e.key]);
Future<void> _regular(File file) async {
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file)
    throw FileSystemException(
      'A linked or foreign launcher file was kept',
      file.path,
    );
}

Future<void> _directory(Directory dir) async {
  final type = await FileSystemEntity.type(dir.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    await _directory(dir.parent);
    await dir.create();
  } else if (type != FileSystemEntityType.directory) {
    throw FileSystemException('A linked launcher directory was kept', dir.path);
  }
}

Future<void> _publish(File file, List<int> bytes) async {
  final stage = await file.parent.createTemp('.broomm-launcher-');
  try {
    final pending = File('${stage.path}/entry');
    await pending.writeAsBytes(bytes, flush: true);
    if (!_same(await pending.readAsBytes(), bytes))
      throw const FileSystemException('Launcher write could not be verified');
    await _regular(file);
    await pending.rename(file.path);
    if (!_same(await file.readAsBytes(), bytes))
      throw const FileSystemException(
        'Launcher installation could not be verified',
      );
  } finally {
    await stage.delete(recursive: true);
  }
}
