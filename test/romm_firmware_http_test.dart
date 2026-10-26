import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';

void main() {
  late HttpServer server;
  late RommClient client;
  late Directory data;
  late Future<void> Function(HttpRequest) handle;
  final payload = [0x53, 0x43, 0x45, 0x55, 0x46];
  Map<String, dynamic> record() => {
    'id': 9,
    'platform_id': 7,
    'file_name': 'PS3 firmware #1.pup',
    'file_size_bytes': payload.length,
    'md5_hash': 'a' * 32,
    'missing_from_fs': false,
  };
  Future<void> json(HttpRequest r, Object value) async {
    r.response.headers.contentType = ContentType.json;
    r.response.write(jsonEncode(value));
    await r.response.close();
  }

  setUp(() async {
    data = await Directory.systemTemp.createTemp('broomm-firmware-http-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handle = (r) => json(r, {'id': 3, 'username': 'Player'});
    server.listen((r) async {
      expect(
        r.headers.value(HttpHeaders.authorizationHeader),
        startsWith('Bearer rmm_'),
      );
      await handle(r);
    });
    client = RommClient(Uri.parse('http://127.0.0.1:${server.port}/prefix'));
    await client.loginToken('rmm_${'a' * 64}');
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
    await data.delete(recursive: true);
  });
  test('firmware discovery filters the platform and downloads an encoded filename under the server prefix', () async {
    handle = (r) async {
      if (r.uri.path == '/prefix/api/firmware') {
        expect(r.uri.queryParameters, {'platform_id': '7', 'missing': 'false'});
        await json(r, [record()]);
      } else {
        expect(r.uri.pathSegments, [
          'prefix',
          'api',
          'firmware',
          '9',
          'content',
          'PS3 firmware #1.pup',
        ]);
        expect(r.uri.hasFragment, false);
        expect(r.headers.value(HttpHeaders.acceptEncodingHeader), 'identity');
        r.response.contentLength = payload.length;
        r.response.add(payload);
        await r.response.close();
      }
    };
    final firmware = (await client.firmware(7)).single;
    final output = File('${data.path}/download');
    var received = 0;
    await client.downloadFirmware(
      firmware,
      output,
      cancellation: DownloadCancellation(),
      onProgress: (n) => received = n,
    );
    expect(await output.readAsBytes(), payload);
    expect(received, payload.length);
  });
  test('redirects, denied access and changed firmware sizes are rejected before publishing content', () async {
    final firmware = RommFirmware.fromJson(record());
    for (final code in [302, 403, 200]) {
      var calls = 0;
      handle = (r) async {
        calls++;
        r.response.statusCode = code;
        if (code == 302)
          r.response.headers.set(HttpHeaders.locationHeader, '/elsewhere');
        if (code == 200) r.response.add([1, 2]);
        await r.response.close();
      };
      final output = File('${data.path}/download-$code');
      await expectLater(
        client.downloadFirmware(
          firmware,
          output,
          cancellation: DownloadCancellation(),
          onProgress: (_) {},
        ),
        throwsA(isA<RommFailure>()),
      );
      expect(calls, 1);
      // A chunked response may leave private partial bytes; its caller owns
      // staging cleanup. It must never be accepted as complete firmware.
      if (code != 200) expect(await output.exists(), false);
      if (await output.exists())
        expect(await output.length(), lessThan(payload.length));
    }
  });
  test('unsafe or unverifiable firmware metadata is never accepted for installation', () {
    for (final change in [
      {'file_name': '../firmware.pup'},
      {'md5_hash': ''},
      {'missing_from_fs': true},
      {'file_size_bytes': 0},
    ]) {
      expect(
        () => RommFirmware.fromJson({...record(), ...change}),
        throwsA(isA<RommFailure>()),
      );
    }
  });
}
