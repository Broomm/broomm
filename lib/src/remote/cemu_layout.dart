import 'dart:io';

import 'package:xml/xml.dart';

import '../cemu.dart';
import '../emulators.dart';
import '../progress/files.dart';

/// Only the owned second-window settings are restored after the writer exits.
/// A versioned portable anchor remains in the durable journal across upgrades.
class CemuRemoteLayout {
  static const keys = {
    'fullscreen',
    'open_pad',
    'pad_size',
    'pad_maximized',
    'window_maximized',
  };
  static File journal(String root) => File('$root/cemu-remote-layout.json');
  static Future<void> prepare(PreparedEmulator e) async {
    await restore(e.root);
    if (!e.remoteScreen) return;
    final file = File('${e.user}/settings.xml');
    final document = cemuXml(
      await file.exists() ? await readCemuXml(file) : '<content/>',
      'content',
    );
    final saved = <String, String?>{};
    for (final key in keys) {
      final nodes = document.rootElement.findElements(key).toList();
      if (nodes.length > 1)
        throw const FormatException('Duplicate Cemu window settings.');
      saved[key] = nodes.isEmpty ? null : nodes.single.toXmlString();
    }
    final relative = file.path
        .substring(e.root.length + 1)
        .replaceAll('\\', '/');
    _path(relative);
    await progressWrite(journal(e.root), {
      'version': 1,
      'config': relative,
      'keys': saved,
    });
    await atomicText(
      file.path,
      patchCemuSettings(document.toXmlString(), {
        'fullscreen': false,
        'open_pad': true,
        'pad_size': <String, Object>{'x': 1600, 'y': 900},
        'pad_maximized': Platform.isMacOS,
        'window_maximized': true,
      }),
    );
  }

  static void _path(String value) {
    if (!RegExp(r'^launcher/[a-f0-9]{64}/(?:Cemu/)?portable/settings\.xml$')
        .hasMatch(value))
      throw const FormatException('Unrecognized private Cemu layout location.');
  }

  static Future<void> restore(String root) async {
    final record = journal(root);
    if (!await record.exists()) return;
    final data = await progressJson(record);
    if (data['version'] != 1 ||
        data['config'] is! String ||
        data['keys'] is! Map ||
        (data['keys'] as Map).keys.toSet().difference(keys).isNotEmpty)
      throw const FormatException('Invalid Cemu layout recovery.');
    _path(data['config']);
    final file = await progressFile(Directory(root), data['config']);
    final document = cemuXml(await readCemuXml(file), 'content');
    for (final key in keys) {
      final nodes = document.rootElement.findElements(key).toList();
      if (nodes.length > 1)
        throw const FormatException('Duplicate Cemu window settings.');
      final value = (data['keys'] as Map)[key];
      XmlElement? original;
      if (value != null) {
        if (value is! String || value.length > 4096)
          throw const FormatException('Invalid Cemu window preference.');
        final saved = cemuXml(
          '<content>$value</content>',
          'content',
        ).rootElement.childElements.toList();
        if (saved.length != 1 || saved.single.name.qualified != key)
          throw const FormatException('Invalid Cemu window preference.');
        original = saved.single.copy();
      }
      for (final node in nodes) node.remove();
      if (original != null) document.rootElement.children.add(original);
    }
    await atomicText(file.path, '${document.toXmlString(pretty: true)}\n');
    await record.delete();
  }
}
