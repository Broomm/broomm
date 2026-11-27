import 'dart:io';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

/// Cemu's bounded UTF-8 XML files. There is no DTD/entity network resolution.
XmlDocument cemuXml(String text, String root) {
  if (text.length > 1024 * 1024 ||
      text.contains(RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false)) ||
      text.contains('\u0000'))
    throw const FormatException(
      'Cemu XML is oversized or unsupported. Existing data was kept.',
    );
  var depth = 0, elements = 0;
  for (final event in parseEvents(text)) {
    if (event is XmlStartElementEvent) {
      if (++elements > 10000 || ++depth > 32)
        throw const FormatException('Cemu XML exceeds its structure limits.');
      if (event.isSelfClosing) --depth;
    } else if (event is XmlEndElementEvent) {
      --depth;
    }
  }
  final document = XmlDocument.parse(text);
  if (document.rootElement.name.qualified != root ||
      document.descendants.whereType<XmlElement>().length > 10000 ||
      document.descendants.whereType<XmlElement>().any(
        (e) => e.ancestors.length > 32,
      ))
    throw const FormatException(
      'Unsupported Cemu XML structure. Existing data was kept.',
    );
  return document;
}

Future<String> readCemuXml(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() > 1024 * 1024)
    throw const FormatException(
      'Cemu metadata is missing, linked or oversized. Existing data was kept.',
    );
  return file.readAsString();
}

String cemuTitleId(String value) {
  final id = value.trim().toLowerCase();
  // Ordinary Wii U applications only: updates, DLC and system titles cannot
  // select a different save tree through this boundary.
  if (!RegExp(r'^00050000[0-9a-f]{8}$').hasMatch(id) || id.endsWith('00000000'))
    throw const FormatException(
      'This Wii U file has no supported base-game title ID.',
    );
  return id;
}

String? _uniqueText(XmlElement root, String name) {
  final entries = root.findElements(name).toList();
  if (entries.length > 1 || entries.any((e) => e.childElements.isNotEmpty))
    throw const FormatException(
      'Duplicate or nested Cemu metadata. Existing data was kept.',
    );
  return entries.isEmpty ? null : entries.single.innerText;
}

/// A decrypted RPX is paired with code/app.xml and meta/meta.xml in its own
/// native title directory. Neither a filename nor catalogue text supplies ID.
Future<String> cemuRpxTitle(String rom) async {
  final file = File(rom);
  if (!file.path.toLowerCase().endsWith('.rpx') ||
      file.parent.uri.pathSegments
              .where((p) => p.isNotEmpty)
              .last
              .toLowerCase() !=
          'code')
    throw const FormatException(
      'Choose the RPX inside a decrypted Wii U title’s code directory.',
    );
  final app = cemuXml(
    await readCemuXml(File('${file.parent.path}/app.xml')),
    'app',
  );
  final id = cemuTitleId(_uniqueText(app.rootElement, 'title_id') ?? '');
  final metadata = File('${file.parent.parent.path}/meta/meta.xml');
  if (await metadata.exists()) {
    final meta = cemuXml(await readCemuXml(metadata), 'menu');
    if (cemuTitleId(_uniqueText(meta.rootElement, 'title_id') ?? '') != id)
      throw const FormatException(
        'The Wii U application and metadata identify different games.',
      );
  }
  return id;
}

/// Read Cemu's own fresh catalogue from an isolated, no-game inspection run.
/// The caller supplies canonical paths; archive metadata must match that exact
/// file and contain one base title, even when updates/DLC share its WUA.
String cemuCatalogueTitle(String text, String canonicalRom) {
  return cemuCatalogueCandidate(text, canonicalRom) ??
      (throw const FormatException(
        'Cemu has not identified this Wii U file. No save was selected.',
      ));
}

String? cemuCatalogueCandidate(String text, String canonicalRom) {
  final root = cemuXml(text, 'title_list').rootElement;
  final ids = <String>{};
  for (final title in root.findElements('title')) {
    if (_uniqueText(title, 'path') != canonicalRom) continue;
    final value = title.getAttribute('titleId') ?? '';
    if (!value.toLowerCase().startsWith('00050000')) continue;
    ids.add(cemuTitleId(value));
  }
  if (ids.isEmpty) return null;
  if (ids.length != 1)
    throw const FormatException(
      'Cemu did not identify exactly one base game in this Wii U file. No save was selected.',
    );
  return ids.single;
}

/// Edits only concrete owned keys and keeps unrelated element values/comments.
String patchCemuSettings(String source, Map<String, Object> values) {
  final document = cemuXml(
    source.trim().isEmpty ? '<content/>' : source,
    'content',
  );
  void patch(XmlElement parent, Map<String, Object> changes) {
    for (final entry in changes.entries) {
      if (!RegExp(r'^[A-Za-z_][A-Za-z_0-9]*$').hasMatch(entry.key))
        throw const FormatException('Invalid Cemu settings key.');
      final matches = parent.findElements(entry.key).toList();
      if (matches.length > 1)
        throw const FormatException(
          'Duplicate Cemu settings. Existing settings were kept.',
        );
      final element = matches.isEmpty
          ? XmlElement(XmlName.parts(entry.key))
          : matches.single;
      if (matches.isEmpty) parent.children.add(element);
      if (entry.value is Map<String, Object>) {
        patch(element, entry.value as Map<String, Object>);
      } else {
        if (element.childElements.isNotEmpty)
          throw const FormatException(
            'Unsupported nested Cemu setting. Existing settings were kept.',
          );
        element.innerText = '${entry.value}';
      }
    }
  }

  patch(document.rootElement, values);
  return '${document.toXmlString(pretty: true)}\n';
}

String cemuControllerProfile(int port) {
  if (port < 1 || port > 65535) throw ArgumentError.value(port, 'port');
  // Cemu VPAD mapping IDs -> Cemu's DSU raw-state button/axis IDs (v2.6).
  // DSU face bits are DS4 positions; Nintendo A/B and X/Y are swapped here.
  const mapping = <int, int>{
    1: 13,
    2: 14,
    3: 12,
    4: 15,
    5: 10,
    6: 11,
    7: 42,
    8: 43,
    9: 3,
    10: 0,
    11: 4,
    12: 6,
    13: 7,
    14: 5,
    15: 1,
    16: 2,
    17: 39,
    18: 45,
    19: 44,
    20: 38,
    21: 41,
    22: 47,
    23: 46,
    24: 40,
  };
  final builder = XmlBuilder();
  builder.element(
    'emulated_controller',
    nest: () {
      builder.element('type', nest: 'Wii U GamePad');
      builder.element(
        'controller',
        nest: () {
          builder.element('api', nest: 'DSUController');
          builder.element('uuid', nest: '0');
          builder.element('display_name', nest: 'Broomm GamePad');
          builder.element('ip', nest: '127.0.0.1');
          builder.element('port', nest: port);
          builder.element('motion', nest: false);
          builder.element(
            'axis',
            nest: () {
              builder.element('deadzone', nest: '0.12');
              builder.element('range', nest: '1');
            },
          );
          builder.element(
            'mappings',
            nest: () {
              for (final entry in mapping.entries) {
                builder.element(
                  'entry',
                  nest: () {
                    builder.element('mapping', nest: entry.key);
                    builder.element('button', nest: entry.value);
                  },
                );
              }
            },
          );
        },
      );
    },
  );
  return '${builder.buildDocument().toXmlString(pretty: true)}\n';
}
