import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/updates/installation.dart';
import 'package:broomm/src/updates/releases.dart';

void main() {
  testWidgets(
    'Android permission retry renews installer retention and hands off exactly one private APK',
    (t) async {
      var requests = 0;
      String? supplied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(updateChannel, (
        call,
      ) async {
        expect(call.method, 'install');
        supplied = (call.arguments as Map)['path'] as String;
        return ++requests > 1;
      });
      await t.runAsync(() async {
        final root = await Directory.systemTemp.createTemp(
          'broomm-android-update-',
        );
        try {
          final stage = await Directory('${root.path}/.broomm-update-fixture')
              .create();
          final marker = await File('${stage.path}/broomm-update.json')
              .writeAsString(
                jsonEncode({
                  'product': 'Broomm',
                  'format': 1,
                  'version': '0.1.1',
                  'build_target': 'android-universal',
                  'target': null,
                  'archive': 'Broomm-0.1.1-android-universal.apk',
                }),
              );
          final old = DateTime.now().subtract(const Duration(days: 2));
          await marker.setLastModified(old);
          final apk = await File(
            '${stage.path}/Broomm-0.1.1-android-universal.apk',
          ).writeAsBytes([1, 2, 3]);
          final lease = await UpdateLease.acquire(root);
          final prepared = PreparedAppUpdate(
            stage,
            UpdateLocation(root, 'android'),
            lease,
            apk: apk,
          );
          expect(await prepared.start(), isFalse);
          await expectLater(
            UpdateLease.acquire(root),
            throwsA(isA<UpdateFailure>()),
          );
          expect(await prepared.start(), isTrue);
          expect(supplied, apk.path);
          expect(requests, 2);
          expect(
            (await marker.stat()).modified.isAfter(
              old.add(const Duration(days: 1)),
            ),
            isTrue,
          );
          await cleanupApplicationUpdates(UpdateLocation(root, 'android'));
          expect(await apk.exists(), isTrue);
          final released = await UpdateLease.acquire(root);
          await released.close();
        } finally {
          await root.delete(recursive: true);
        }
      });
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        updateChannel,
        null,
      );
    },
  );

  testWidgets(
    'rejected Android handoff keeps existing data and permits a clean retry',
    (t) async {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(updateChannel, (
        _,
      ) async {
        throw PlatformException(
          code: 'update-install',
          message: 'Rejected fixture APK',
        );
      });
      await t.runAsync(() async {
        final root = await Directory.systemTemp.createTemp(
          'broomm-android-update-failed-',
        );
        try {
          final stage = await Directory('${root.path}/.broomm-update-fixture')
              .create();
          await File('${stage.path}/broomm-update.json').writeAsString('{}');
          final apk = await File('${stage.path}/update.apk').writeAsBytes([1]);
          final progress = await File('${root.path}/progress.sav')
              .writeAsString('keep');
          final prepared = PreparedAppUpdate(
            stage,
            UpdateLocation(root, 'android'),
            await UpdateLease.acquire(root),
            apk: apk,
          );
          await expectLater(
            prepared.start(),
            throwsA(isA<PlatformException>()),
          );
          await prepared.discard();
          expect(await progress.readAsString(), 'keep');
          expect(await stage.exists(), isFalse);
          final lease = await UpdateLease.acquire(root);
          await lease.close();
        } finally {
          await root.delete(recursive: true);
        }
      });
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        updateChannel,
        null,
      );
    },
  );
}
