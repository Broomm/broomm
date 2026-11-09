import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broomm/src/android/duck_states.dart';
import 'package:flutter_test/flutter_test.dart';

/// Envelope fixture only; native emulator payload validity is checked on Thor.
Uint8List duckStateEnvelope(String publication) {
  final path = utf8.encode(
    '/android_content/app.broomm.broomm.games.documents/document@$publication/Game.chd',
  );
  final bytes = Uint8List(224 + path.length + 16),
      h = ByteData.sublistView(bytes);
  void field(int offset, int n) => h.setUint32(offset, n, Endian.little);
  field(0, 0x43435544);
  field(4, 97);
  field(168, path.length);
  field(172, 224);
  field(204, 16);
  field(208, 16);
  field(212, 224 + path.length);
  bytes.setRange(224, 224 + path.length, path);
  return bytes;
}

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('duck-state-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  test('native media correspondence accepts a regranted publication and refuses another game without modifying the state', () async {
    final bytes = duckStateEnvelope('a' * 32),
        file = await File('${temp.path}/state.sav').writeAsBytes(bytes);
    await validateAndroidDuckState(file, 'a' * 32);
    await expectLater(
      validateAndroidDuckState(file, 'b' * 32),
      throwsFormatException,
    );
    expect(await file.readAsBytes(), bytes);
  });
  test('truncated and overlapping state resources cannot be adopted as complete progress', () async {
    final bytes = duckStateEnvelope('a' * 32),
        file = await File('${temp.path}/state.sav')
            .writeAsBytes(bytes.sublist(0, bytes.length - 1));
    await expectLater(
      validateAndroidDuckState(file, 'a' * 32),
      throwsFormatException,
    );
    final h = ByteData.sublistView(bytes);
    h.setUint32(212, 224, Endian.little);
    await file.writeAsBytes(bytes);
    await expectLater(
      validateAndroidDuckState(file, 'a' * 32),
      throwsFormatException,
    );
  });
  test('unknown native format and an external media provider stay outside the reviewed state group', () async {
    final bytes = duckStateEnvelope('a' * 32),
        h = ByteData.sublistView(bytes),
        file = File('${temp.path}/state.sav');
    h.setUint32(4, 98, Endian.little);
    await file.writeAsBytes(bytes);
    await expectLater(
      validateAndroidDuckState(file, 'a' * 32),
      throwsFormatException,
    );
    h.setUint32(4, 97, Endian.little);
    bytes[224] = 88;
    await file.writeAsBytes(bytes);
    await expectLater(
      validateAndroidDuckState(file, 'a' * 32),
      throwsFormatException,
    );
  });
}
