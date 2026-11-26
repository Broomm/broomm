import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/remote/service.dart';
import 'package:broomm/src/shell/app.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ShellModel model;
  late RemoteScreenService remote;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('broomm-shell-remote-');
    model = ShellModel(ShellStorage(root));
    await model.start();
    remote = RemoteScreenService(root, hostEnabled: false);
    for (final channel in [
      const MethodChannel('app.broomm/prototype'),
      RemoteScreenService.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });
  tearDown(() async {
    await remote.close();
    if (!model.disposed) model.dispose();
    await model.finishDownloads();
    await model.finishCloud();
    if (await root.exists()) await root.delete(recursive: true);
    for (final channel in [
      const MethodChannel('app.broomm/prototype'),
      RemoteScreenService.channel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets(
    'external remote owner drains startup behind a real settings lock before fixture deletion',
    (tester) async {
      final child = (await tester.runAsync(
        () => Process.start('dart', [
          'test/support/hold_library_lock.dart',
          '${root.path}/remote-screen.lock',
        ]),
      ))!;
      var released = false;
      Future<void> release() async {
        if (released) return;
        released = true;
        child.stdin.writeln('release');
        await child.stdin.close();
        expect(await child.exitCode, 0);
      }

      try {
        expect(
          await tester.runAsync(
            () => child.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .first,
          ),
          'held',
        );
        await tester.runAsync(() async {
          unawaited(remote.start());
        });
        await tester.pumpWidget(BroommApp(model: model, remoteService: remote));
        await tester.pumpWidget(const SizedBox());
        var closed = false;
        late Future<void> closing;
        await tester.runAsync(() async {
          closing = remote.close().whenComplete(() => closed = true);
        });
        await tester.pump();
        expect(
          closed,
          false,
          reason: 'Unmounting cannot finish an outstanding history write.',
        );
        await tester.runAsync(release);
        await tester.runAsync(() => closing);
        expect(remote.history.code, matches(RegExp(r'^[a-f0-9]{16}$')));
        // Windows must be able to remove the storage immediately, without retries.
        await tester.runAsync(() async {
          model.dispose();
          await model.finishDownloads();
          await model.finishCloud();
          await root.delete(recursive: true);
        });
        expect(await tester.runAsync(root.exists), false);
      } finally {
        await tester.runAsync(release);
        await tester.runAsync(remote.close);
      }
    },
  );

  testWidgets(
    'failed remote startup releases its settings handle and preserves the invalid record',
    (tester) async {
      const invalid = '{"version":1}';
      await tester.runAsync(() => remote.history.file.writeAsString(invalid));
      await tester.runAsync(remote.start);
      await tester.pumpWidget(BroommApp(model: model, remoteService: remote));
      expect(remote.error, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(remote.close);
      expect(await tester.runAsync(remote.history.file.readAsString), invalid);
      await tester.runAsync(() async {
        model.dispose();
        await model.finishDownloads();
        await model.finishCloud();
        await root.delete(recursive: true);
      });
      expect(await tester.runAsync(root.exists), false);
    },
  );
}
