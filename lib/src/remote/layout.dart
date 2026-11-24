import 'dart:io';

import '../emulators.dart';
import '../progress/files.dart';

/// A durable journal for the layout keys temporarily owned by a remote session.
/// Call only while holding the emulator/session writer lease.
class RemoteLayout {
  static Map<String, Set<String>> keys(String name) => name == 'melonDS'
      ? {
          'Instance0.Window0': {'ScreenSizing'},
          'Instance0.Window1': {'Enabled', 'ScreenSizing', 'Width', 'Height'},
        }
      : {
          'Layout': {
            'layout_option',
            r'layout_option\default',
            'swap_screen',
            r'swap_screen\default',
          },
        };
  static File config(PreparedEmulator e) => File(
    e.name == 'melonDS'
        ? '${e.user}/melonDS.toml'
        : '${e.user}/config/qt-config.ini',
  );
  static File journal(PreparedEmulator e) =>
      File('${e.root}/remote-layout.json');
  static bool supports(PreparedEmulator e) =>
      {'melonDS', 'Azahar'}.contains(e.name);

  static Future<void> prepare(PreparedEmulator e) async {
    if (!supports(e)) return;
    await restore(e);
    if (!e.remoteScreen) return;
    final file = config(e);
    if (await file.exists() && await file.length() > 1024 * 1024) {
      throw const FormatException('Emulator layout is too large.');
    }
    final text = await file.exists() ? await file.readAsString() : '';
    if (text.length > 1024 * 1024)
      throw const FormatException('Emulator layout is too large.');
    final selected = keys(e.name);
    final saved = <String, Object?>{
      for (final section in selected.entries)
        section.key: <String, String?>{
          for (final key in section.value) key: null,
        },
    };
    var section = '';
    final seen = <String>{};
    for (final line in text.split('\n')) {
      final header = RegExp(r'^\s*\[([^\]]+)\]\s*$').firstMatch(line);
      if (header != null) section = header[1]!;
      final key = line.split('=').first.trim();
      if (selected[section]?.contains(key) == true) {
        if (!seen.add('$section.$key'))
          throw const FormatException('Duplicate emulator layout keys.');
        (saved[section] as Map<String, String?>)[key] = line;
      }
    }
    await progressWrite(journal(e), {
      'version': 1,
      'existed': await file.exists(),
      'keys': saved,
    });
  }

  static Future<void> restore(PreparedEmulator e) async {
    if (!supports(e) || !await journal(e).exists()) return;
    final data = await progressJson(journal(e));
    if (data['version'] != 1 || data['keys'] is! Map)
      throw const FormatException('Invalid remote layout recovery.');
    final selected = keys(e.name);
    final saved = <String, Map<String, String?>>{};
    for (final section in selected.entries) {
      final values = (data['keys'] as Map)[section.key];
      if (values is! Map ||
          values.keys.toSet().difference(section.value).isNotEmpty) {
        throw const FormatException('Invalid remote layout keys.');
      }
      saved[section.key] = {};
      for (final key in section.value) {
        final value = values[key];
        if (value != null &&
            (value is! String ||
                value.contains('\n') ||
                value.split('=').first.trim() != key)) {
          throw const FormatException('Invalid remote layout value.');
        }
        saved[section.key]![key] = value as String?;
      }
    }
    final file = config(e);
    if (!await file.exists() && data['existed'] == false) {
      await journal(e).delete();
      return;
    }
    if (await file.length() > 1024 * 1024)
      throw const FormatException('Emulator layout is too large.');
    final text = await file.readAsString();
    if (text.length > 1024 * 1024)
      throw const FormatException('Emulator layout is too large.');
    final output = <String>[];
    var section = '';
    void finish() {
      for (final line in saved.remove(section)?.values ?? <String?>[]) {
        if (line != null) output.add(line);
      }
    }

    for (final line in text.split('\n')) {
      final header = RegExp(r'^\s*\[([^\]]+)\]\s*$').firstMatch(line);
      if (header != null) {
        finish();
        section = header[1]!;
      }
      final key = line.split('=').first.trim();
      if (selected[section]?.contains(key) == true) {
        final original = saved[section]?.remove(key);
        if (original != null) output.add(original);
      } else {
        output.add(line);
      }
    }
    finish();
    for (final entry in saved.entries) {
      final lines = entry.value.values.whereType<String>().toList();
      if (lines.isNotEmpty) output.addAll(['[${entry.key}]', ...lines]);
    }
    await atomicText(file.path, output.join('\n'));
    await journal(e).delete();
  }
}
