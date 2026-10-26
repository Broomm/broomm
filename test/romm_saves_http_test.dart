import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';

void main() {
  late Directory tmp;
  late HttpServer server;
  late RommClient client;
  late Future<void> Function(HttpRequest) handle;
  var id = 4;
  var payload = <int>[0, 1, 255, 13, 10];
  Map<String, dynamic> record({String name = 'broomm'}) => {
    'id': id,
    'rom_id': 42,
    'user_id': 3,
    'file_name': name,
    'file_size_bytes': payload.length,
    'emulator': 'Broomm',
    'slot': null,
    'updated_at': '2026-10-22T12:00:00Z',
    'missing_from_fs': false,
  };
  Future<void> json(HttpRequest r, Object j) async {
    r.response.headers.contentType = ContentType.json;
    r.response.write(jsonEncode(j));
    await r.response.close();
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('broomm-save-http-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = RommClient(Uri.parse('http://127.0.0.1:${server.port}/prefix'));
    handle = (r) async {
      if (r.uri.path.endsWith('/users/me')) {
        await json(r, {'id': 3, 'username': 'owner'});
        return;
      }
      r.response.statusCode = 404;
      await r.response.close();
    };
    server.listen((r) async {
      expect(
        r.headers.value(HttpHeaders.authorizationHeader),
        startsWith('Bearer rmm_'),
      );
      await handle(r);
    });
    await client.loginToken('rmm_${'a' * 64}');
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  test('a BROOMM slot upload sends native bytes and lets RomM insert its timestamp before the extension', () async {
    handle = (r) async {
      if (r.method == 'GET') {
        expect(r.uri.path, '/prefix/api/saves/4');
        await json(r, {
          ...record(name: 'Broomm [2026-10-22_20-00-00].sav'),
          'slot': 'BROOMM',
        });
        return;
      }
      expect(r.method, 'POST');
      expect(r.uri.path, '/prefix/api/saves');
      expect(r.uri.queryParameters, {
        'rom_id': '42',
        'emulator': 'Broomm',
        'slot': 'BROOMM',
        'overwrite': 'true',
        'autocleanup': 'false',
      });
      final body = latin1.decode(
        await r.fold<List<int>>([], (a, b) => a..addAll(b)),
      );
      expect(body, contains('name="saveFile"; filename="Broomm.sav"'));
      expect(body, contains(latin1.decode(payload)));
      await json(r, {
        ...record(name: 'Broomm [2026-10-22_20-00-00].sav'),
        'slot': 'BROOMM',
        'updated_at': '2026-10-22T12:00:00.412392Z',
      });
    };
    final file = File('${tmp.path}/native.sav');
    await file.writeAsBytes(payload);
    final saved = await client.uploadSave(
      42,
      file,
      name: 'Broomm.sav',
      slot: 'BROOMM',
      cancellation: DownloadCancellation(),
    );
    expect(saved.versioned, true);
    expect(saved.name, 'Broomm [2026-10-22_20-00-00].sav');
    expect(saved.updated, '2026-10-22T12:00:00Z');
    expect(await file.readAsBytes(), payload);
  });
  test('upload timestamp canonicalization rejects real content or revision changes', () async {
    final file = File('${tmp.path}/native.sav');
    await file.writeAsBytes(payload);
    for (final changed in [
      {'content_hash': 'changed'},
      {'updated_at': '2026-10-22T12:00:01Z'},
      {'file_name': 'Different.sav'},
    ]) {
      handle = (r) async {
        if (r.method == 'POST') await r.drain<void>();
        await json(r, {
          ...record(name: 'Broomm [2026-10-22_20-00-00].sav'),
          'slot': 'BROOMM',
          'updated_at': '2026-10-22T12:00:00.412392Z',
          if (r.method == 'GET') ...changed,
        });
      };
      await expectLater(
        client.uploadSave(
          42,
          file,
          name: 'Broomm.sav',
          slot: 'BROOMM',
          cancellation: DownloadCancellation(),
        ),
        throwsA(isA<RommFailure>()),
      );
      expect(await file.readAsBytes(), payload);
    }
  });
  test('state companions use the state endpoint and field without writing another save-slot entry', () async {
    var uploads = 0;
    handle = (r) async {
      if (r.method == 'POST') {
        expect(r.uri.path, '/prefix/api/states');
        expect(r.uri.queryParameters.containsKey('slot'), false);
        final body = latin1.decode(
          await r.fold<List<int>>([], (a, b) => a..addAll(b)),
        );
        expect(
          body,
          contains(
            'name="stateFile"; filename="Broomm [2026-10-22_20-00-00].zip"',
          ),
        );
        uploads++;
        await json(r, record(name: 'Broomm [2026-10-22_20-00-00].zip'));
      } else if (r.uri.path.endsWith('/content')) {
        expect(r.uri.path, '/prefix/api/states/4/content');
        r.response.add(payload);
        await r.response.close();
      } else if (r.uri.path.endsWith('/states'))
        await json(r, [record(name: 'Broomm [2026-10-22_20-00-00].zip')]);
      else
        await json(r, record(name: 'Broomm [2026-10-22_20-00-00].zip'));
    };
    final file = File('${tmp.path}/states.zip');
    await file.writeAsBytes(payload);
    final state = await client.uploadState(
      42,
      file,
      name: 'Broomm [2026-10-22_20-00-00].zip',
      cancellation: DownloadCancellation(),
    );
    expect(state.stateAsset, true);
    expect(state.managed, false);
    expect((await client.states(42)).single.stateAsset, true);
    expect((await client.state(state.id)).stateAsset, true);
    final output = File('${tmp.path}/readback');
    await client.downloadState(
      state,
      output,
      cancellation: DownloadCancellation(),
    );
    expect(await output.readAsBytes(), payload);
    expect(uploads, 1);
  });
  test('login requests save-write permission while read-only accounts can still browse', () async {
    final requested = <String>[];
    handle = (r) async {
      if (r.uri.path.endsWith('/api/token')) {
        final form = Uri.splitQueryString(await utf8.decoder.bind(r).join());
        requested.add(form['scope']!);
        if (form['scope']!.contains('assets.write')) {
          r.response.statusCode = 403;
          await r.response.close();
          return;
        }
        await json(r, {
          'access_token': 'readonly-access',
          'refresh_token': 'readonly-refresh',
          'token_type': 'bearer',
          'expires': 900,
        });
      } else {
        await json(r, {'id': 3, 'username': 'owner'});
      }
    };
    // This client starts without a credential; token requests have no bearer.
    // The outer fixture's header assertion is specific to its token client, so
    // use a separate real server for this password grant.
    final auth = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    auth.listen(handle);
    final passwordClient = RommClient(
      Uri.parse('http://127.0.0.1:${auth.port}'),
    );
    try {
      final user = await passwordClient.login('owner', 'not-persisted');
      expect(user.id, 3);
      expect(passwordClient.readOnlyLogin, true);
      expect(requested.first, contains('assets.write'));
      expect(requested.last, isNot(contains('assets.write')));
    } finally {
      passwordClient.close();
      await auth.close(force: true);
    }
  });

  test('real multipart POST/PUT and asset download use literal names, fixed namespace, no retention and no optimistic marking', () async {
    final source = File('${tmp.path}/source');
    await source.writeAsBytes(payload);
    var uploads = 0;
    handle = (r) async {
      if (r.method == 'POST' || r.method == 'PUT') {
        expect(
          r.uri.path,
          uploads == 0 ? '/prefix/api/saves' : '/prefix/api/saves/4',
        );
        if (uploads == 0) {
          expect(r.uri.queryParameters, {
            'rom_id': '42',
            'emulator': 'Broomm',
            'overwrite': 'false',
            'autocleanup': 'false',
          });
        }
        final type = r.headers.contentType!;
        expect(type.mimeType, 'multipart/form-data');
        final body = await r.fold<List<int>>([], (a, b) => a..addAll(b));
        final text = latin1.decode(body);
        expect(text, contains('name="saveFile"; filename="broomm"'));
        expect(text, contains(latin1.decode(payload)));
        expect(text, endsWith('--${type.parameters['boundary']}--\r\n'));
        uploads++;
        await json(r, record());
      } else if (r.uri.path.endsWith('/content')) {
        expect(r.uri.queryParameters, {'optimistic': 'false'});
        r.response.contentLength = payload.length;
        r.response.add(payload);
        await r.response.close();
      } else if (r.uri.path.endsWith('/saves/4')) {
        await json(r, record());
      } else {
        await json(r, [record()]);
      }
    };
    final created = await client.uploadSave(
      42,
      source,
      name: 'broomm',
      cancellation: DownloadCancellation(),
    );
    await client.uploadSave(
      42,
      source,
      name: 'broomm',
      replace: created,
      cancellation: DownloadCancellation(),
    );
    final saves = await client.saves(42);
    expect(saves.single.managed, true);
    final dest = File('${tmp.path}/received');
    await client.downloadSave(
      created,
      dest,
      cancellation: DownloadCancellation(),
    );
    expect(await dest.readAsBytes(), payload);
    expect(uploads, 2);
  });

  test('redirects, truncated content and write permission failures retain source bytes and have actionable errors', () async {
    final source = File('${tmp.path}/source');
    await source.writeAsBytes(payload);
    handle = (r) async {
      r.response.statusCode = 403;
      await r.response.close();
    };
    await expectLater(
      client.uploadSave(
        42,
        source,
        name: 'broomm',
        cancellation: DownloadCancellation(),
      ),
      throwsA(
        isA<RommFailure>().having((e) => e.status, 'permission status', 403),
      ),
    );
    expect(await source.readAsBytes(), payload);
    handle = (r) async {
      r.response.statusCode = 302;
      r.response.headers.set('location', 'https://other.invalid/collect');
      await r.response.close();
    };
    final save = RommSave.fromJson(record());
    await expectLater(
      client.downloadSave(
        save,
        File('${tmp.path}/redirect'),
        cancellation: DownloadCancellation(),
      ),
      throwsA(
        isA<RommFailure>().having((e) => e.status, 'redirect status', 302),
      ),
    );
    expect(await File('${tmp.path}/redirect').exists(), false);
    handle = (r) async {
      r.response.contentLength = 2;
      r.response.add([0, 1]);
      await r.response.close();
    };
    await expectLater(
      client.downloadSave(
        save,
        File('${tmp.path}/short'),
        cancellation: DownloadCancellation(),
      ),
      throwsA(isA<RommFailure>()),
    );
    expect(await source.readAsBytes(), payload);
  });
}
