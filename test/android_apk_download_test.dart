import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/android/apk_download.dart';
import 'package:broomm/src/android/emulators.dart';

class ApkHeaders extends Fake implements HttpHeaders {
  ApkHeaders([this.location]);
  final String? location;
  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class ApkReply extends Stream<List<int>> implements HttpClientResponse {
  ApkReply(this.bytes, {int? length, this.statusCode = 200, String? location})
    : contentLength = length ?? bytes.length,
      headers = ApkHeaders(location);
  final List<int> bytes;
  @override
  final int contentLength, statusCode;
  @override
  final HttpHeaders headers;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class ApkRequest extends Fake implements HttpClientRequest {
  ApkRequest(this.reply);
  final HttpClientResponse reply;
  @override
  final HttpHeaders headers = ApkHeaders();
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async => reply;
}

class ApkClient extends Fake implements HttpClient {
  ApkClient(this.reply);
  final HttpClientResponse Function(Uri) reply;
  final requests = <Uri>[];
  bool closed = false;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests.add(url);
    return ApkRequest(reply(url));
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;
  setUp(
    () async => data = await Directory.systemTemp.createTemp('broomm-apk-'),
  );
  tearDown(() async => data.delete(recursive: true));
  test('official assets select shared MMJ and vanilla Azahar, excluding storage-access and bundle variants', () {
    Map<String, dynamic> release(List<String> names) => {
      'assets': [
        for (final name in names)
          {
            'name': name,
            'browser_download_url':
                'https://github.com/official/project/releases/download/tag/$name',
          },
      ],
    };
    final mmj = AndroidApkDownload.githubAsset(
      'citra-mmj',
      release([
        'Citra_MMJ_20251112_StorageAccess.apk',
        'Citra_MMJ_20251112_Antutu.apk',
        'Citra_MMJ_20251112.apk',
      ]),
    );
    expect(mmj.path, endsWith('/Citra_MMJ_20251112.apk'));
    final azahar = AndroidApkDownload.githubAsset(
      'azahar',
      release([
        'azahar-android-googleplay-2126.2.apk',
        'azahar-android-vanilla-2126.2.aab',
        'azahar-android-vanilla-2126.2.apk',
      ]),
    );
    expect(azahar.path, endsWith('/azahar-android-vanilla-2126.2.apk'));
    expect(
      () => AndroidApkDownload.githubAsset(
        'armsx2',
        release(['ARMSX2-2.9.1-a15-armv8.2-sdk35.apk']),
      ),
      throwsStateError,
    );
  });
  test('Install downloads the complete APK before handing a private file to Android; only readback confirms installation', () async {
    const channel = MethodChannel('app.broomm/apk-test');
    final payload = [0x50, 0x4b, 3, 4, 1, 2, 3];
    String? path;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'installed') return [];
          if (call.method == 'device')
            return {
              'abis': ['arm64-v8a'],
              'sdk': 35,
            };
          if (call.method == 'installDownloadedApk') {
            path = (call.arguments as Map)['path'];
            expect(await File(path!).readAsBytes(), payload);
            return null;
          }
          throw StateError(call.method);
        });
    final manager = AndroidEmulators(data, channel: channel, enabled: true);
    await manager.load();
    final client = ApkClient((_) => ApkReply(payload));
    try {
      await HttpOverrides.runZoned(
        () => manager.install(
          androidEmulators.singleWhere((e) => e.id == 'ppsspp'),
        ),
        createHttpClient: (_) => client,
      );
      expect(path, isNotNull);
      expect(calls, contains('installDownloadedApk'));
      expect(calls, isNot(contains('installPage')));
      expect(manager.installed, isEmpty);
      expect(client.closed, true);
    } finally {
      manager.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
  test('truncated and cancelled APK transfers discard partial data and do not reach an installer', () async {
    final client = ApkClient((_) => ApkReply([1, 2], length: 20)),
        downloader = AndroidApkDownload(client: client);
    await expectLater(
      downloader.download(
        data,
        Uri.parse('https://www.ppsspp.org/files/app.apk'),
        (_, _) {},
      ),
      throwsFormatException,
    );
    final folder = Directory('${data.path}/android/apks');
    expect(await folder.list().isEmpty, true);
    final cancel = AndroidApkDownload(
      client: ApkClient((_) => ApkReply([1, 2])),
    );
    cancel.cancel();
    await expectLater(
      cancel.download(
        data,
        Uri.parse('https://www.ppsspp.org/files/app.apk'),
        (_, _) {},
      ),
      throwsStateError,
    );
    expect(await folder.list().isEmpty, true);
  });
  test(
    'unrecognized redirects are rejected before fetching another host',
    () async {
      final client = ApkClient(
        (_) => ApkReply(
          [],
          statusCode: 302,
          location: 'https://unrelated.invalid/app.apk',
        ),
      );
      final downloader = AndroidApkDownload(client: client);
      await expectLater(
        downloader.download(
          data,
          Uri.parse('https://github.com/project/releases/app.apk'),
          (_, _) {},
        ),
        throwsFormatException,
      );
      expect(client.requests, hasLength(1));
      expect(await Directory('${data.path}/android/apks').list().isEmpty, true);
    },
  );
}
