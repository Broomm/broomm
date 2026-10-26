import 'dart:convert';
import 'dart:io';

Future<String> dsSaveIdentity(String path) async {
  final h = await File(path)
      .openRead(0, 0x20)
      .fold<List<int>>([], (a, b) => a..addAll(b));
  if (h.length != 0x20)
    throw const FormatException('Truncated Nintendo DS header');
  final code = ascii.decode(h.sublist(12, 16), allowInvalid: true);
  if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(code))
    throw const FormatException('No verified Nintendo DS game code');
  return '$code-${h[0x1e].toRadixString(16).padLeft(2, '0')}';
}
