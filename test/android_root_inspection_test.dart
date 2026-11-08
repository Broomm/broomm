import 'dart:async';

import 'package:broomm/src/android/emulators.dart';
import 'package:broomm/src/android/root_inspection.dart';
import 'package:broomm/src/shell/android_root_inspection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const channel = MethodChannel('app.broomm/root-inspection-test');
final emulator = androidEmulators.singleWhere((e) => e.id == 'retroarch');
final app = AndroidApp('com.retroarch.aarch64', '1.22.2', 'a' * 64);
Map<String, dynamic> report() => {
  'package': app.package,
  'version': app.version,
  'build': app.build,
  'user': 0,
  'uid': 10123,
  'gid': 10123,
  'dataDir': '/data/user/0/${app.package}',
  'mode': '700',
  'label': 'u:object_r:app_data_file:s0:c123,c256,c512,c768',
  'signer': 'b' * 64,
  'device': 'Thor fixture',
  'android': '13',
  'sdk': 33,
  'abis': ['arm64-v8a'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late AndroidRootInspector inspector;
  late Future<Object?> Function(MethodCall) handler;
  setUp(() {
    calls = [];
    inspector = AndroidRootInspector(channel: channel);
    handler = (call) async => call.method == 'inspect' ? report() : null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  });
  tearDown(() {
    inspector.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'explicit inspection binds selected package/build without connecting saves',
    () async {
      expect(calls, isEmpty);
      final value = await inspector.inspect(emulator, app);
      expect(value.values['dataDir'], '/data/user/0/${app.package}');
      expect(calls.map((c) => c.method), ['inspect']);
      expect(calls.single.arguments, containsPair('package', app.package));
      expect(calls.single.arguments, containsPair('build', app.build));
      expect(calls.single.arguments, isNot(contains('path')));
      expect(() => value.values['uid'] = 0, throwsUnsupportedError);
    },
  );

  test(
    'mismatched or incomplete observations cannot become accepted access',
    () async {
      for (final change in [
        {'package': 'com.retroarch'},
        {'build': 'c' * 64},
        {'user': 10},
        {'dataDir': '/data/user/0/foreign'},
        {'uid': 9999},
        {'signer': null},
        {'label': '?'},
        {'label': 'u:object_r:app_data_file:s0\u001b'},
        {'abis': <String>[]},
      ]) {
        handler = (_) async => {...report(), ...change};
        await expectLater(
          inspector.inspect(emulator, app),
          throwsFormatException,
        );
      }
      handler = (_) async => {
        ...report(),
        'user': 10,
        'uid': 1010123,
        'gid': 1010123,
        'dataDir': '/data/user/10/${app.package}',
      };
      expect((await inspector.inspect(emulator, app)).values['user'], 10);
    },
  );

  test('PPSSPP discovery retains native app-private metadata without a save connection', () async {
    final psp = androidEmulators.singleWhere((e) => e.id == 'ppsspp');
    final selected = AndroidApp(psp.packages.first, '1.20.4', 'c' * 64);
    final memory = {
      'kind': 'private',
      'path': '/storage/emulated/0/Android/data/${selected.package}/files',
      'gid': 1078,
      'mode': '2770',
      'label': 'u:object_r:media_rw_data_file:s0:c123,c256,c512,c768',
      'device': 65038,
      'inode': 28074,
    };
    Map<String, dynamic> pspReport() => {
      ...report(),
      'package': selected.package,
      'version': selected.version,
      'build': selected.build,
      'dataDir': '/data/user/0/${selected.package}',
      'memoryStick': memory,
    };
    handler = (_) async => pspReport();
    final value = await inspector.inspect(psp, selected);
    expect(value.values['memoryStick'], memory);
    expect(calls.map((c) => c.method), ['inspect']);
    expect(
      () => (value.values['memoryStick'] as Map)['gid'] = 0,
      throwsUnsupportedError,
    );
    for (final change in [
      {'path': '/storage/emulated/0/Android/data/foreign/files'},
      {'mode': '2777'},
      {'label': report()['label']},
      {'device': 0},
      {'inode': '28074'},
      {'extra': true},
    ]) {
      handler = (_) async => {
        ...pspReport(),
        'memoryStick': {...memory, ...change},
      };
      await expectLater(
        inspector.inspect(psp, selected),
        throwsFormatException,
      );
    }
    handler = (_) async => {
      ...pspReport(),
      'memoryStick': {'kind': 'other'},
    };
    expect((await inspector.inspect(psp, selected)).values['memoryStick'], {
      'kind': 'other',
    });
  });

  test(
    'cancel rejects a late success and permits an explicit fresh request',
    () async {
      final pending = Completer<Object?>();
      final started = Completer<void>();
      handler = (call) async {
        if (call.method == 'inspect') {
          started.complete();
          return pending.future;
        }
        return null;
      };
      final request = inspector.inspect(emulator, app);
      final rejected = expectLater(
        request,
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      await started.future;
      await expectLater(inspector.inspect(emulator, app), throwsStateError);
      await inspector.cancel();
      expect(calls.last.arguments['request'], calls.first.arguments['request']);
      pending.complete(report());
      await rejected;
      handler = (call) async => report();
      expect(
        (await inspector.inspect(emulator, app)).values['package'],
        app.package,
      );
    },
  );

  testWidgets(
    'dialog requests no root until chosen; denial stays visible and retry is explicit',
    (tester) async {
      handler = (_) async => throw PlatformException(
        code: 'failed',
        message: 'Root access denied.',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AndroidRootInspectionDialog(
              emulator: emulator,
              app: app,
              inspector: inspector,
            ),
          ),
        ),
      );
      expect(calls, isEmpty);
      await tester.tap(find.text('Request root inspection'));
      await tester.pumpAndSettle();
      expect(find.text('Root access denied.'), findsOneWidget);
      expect(find.text('Read-only inspection completed'), findsNothing);
      handler = (_) async => report();
      await tester.tap(find.text('Inspect again'));
      await tester.pumpAndSettle();
      expect(find.text('Read-only inspection completed'), findsOneWidget);
      expect(calls.map((c) => c.method), ['inspect', 'inspect']);
    },
  );

  test('failure logs distinguish bounded stages without leaking platform diagnostics', () async {
    inspector.dispose();
    final phases = <String>[];
    inspector = AndroidRootInspector(channel: channel, phase: phases.add);
    for (final code in ['directory-unavailable', 'secret-code']) {
      handler = (_) async => throw PlatformException(
        code: code,
        message: 'secret diagnostic',
        details: 'secret details',
      );
      await expectLater(
        inspector.inspect(emulator, app),
        throwsA(isA<PlatformException>()),
      );
      expect(
        phases.last,
        contains(code == 'directory-unavailable' ? code : 'platform failure'),
      );
      expect(phases.join(), isNot(contains('secret')));
    }
    handler = (_) async => report();
    expect((await inspector.inspect(emulator, app)).values['uid'], 10123);
  });

  testWidgets(
    'closing the inspection cancels its native request without accepting a late reply',
    (tester) async {
      final pending = Completer<Object?>();
      handler = (call) async =>
          call.method == 'inspect' ? pending.future : null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AndroidRootInspectionDialog(
              emulator: emulator,
              app: app,
              inspector: inspector,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Request root inspection'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(calls.map((c) => c.method), ['inspect', 'cancel']);
      pending.complete(report());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unresponsive bridge times out and cancels instead of enabling sync',
    (tester) async {
      final pending = Completer<Object?>();
      handler = (call) async =>
          call.method == 'inspect' ? pending.future : null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AndroidRootInspectionDialog(
              emulator: emulator,
              app: app,
              inspector: inspector,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Request root inspection'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 35));
      await tester.pumpAndSettle();
      expect(find.textContaining('Root inspection timed out.'), findsOneWidget);
      expect(calls.map((c) => c.method), ['inspect', 'cancel']);
      pending.complete(report());
      await tester.pumpAndSettle();
      expect(find.text('Read-only inspection completed'), findsNothing);
    },
  );
}
