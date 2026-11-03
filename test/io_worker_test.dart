import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:broomm/src/io_worker.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> heldWriter(Object? arguments, IoContext io) async {
  final a = arguments as List;
  final output = await File(a[0] as String).open(mode: FileMode.writeOnly);
  io.writerOpen = true;
  final release = ReceivePort();
  try {
    await output.writeByte(7);
    io.progress(release.sendPort, force: true);
    await io.cancellation.whenCancelled;
    (a[1] as SendPort).send('cancelled');
    await release.first;
  } finally {
    await output.close();
    io.writerOpen = false;
    release.close();
  }
}

Future<void> lostWriter(Object? arguments, IoContext io) async {
  final output = await File(arguments as String).open(mode: FileMode.writeOnly);
  await output.writeByte(9);
  await output.close();
  Isolate.exit(); // Deliberately omit the closed-writer acknowledgement.
}

void main() {
  test(
    'cancellation waits for the real writer to close and exit before returning',
    () async {
      final root = await Directory.systemTemp.createTemp('broomm-io-');
      final cancelled = ReceivePort(), opened = Completer<SendPort>();
      final cancel = DownloadCancellation();
      final file = File('${root.path}/payload');
      var finished = false;
      final work = IoWorker(heldWriter, [file.path, cancelled.sendPort])
          .run(
            cancellation: cancel,
            progress: (value) => opened.complete(value as SendPort),
          )
          .whenComplete(() => finished = true);
      final assertion = expectLater(work, throwsA(isA<DownloadCancelled>()));
      try {
        final release = await opened.future;
        cancel.cancel();
        expect(await cancelled.first, 'cancelled');
        expect(finished, isFalse);
        release.send('release');
        await assertion;
        await file.rename('${root.path}/closed');
        expect(await File('${root.path}/closed').readAsBytes(), [7]);
      } finally {
        cancelled.close();
        await root.delete(recursive: true);
      }
    },
  );
  test('missing closed-writer evidence reports uncertainty and retains the private file', () async {
    final root = await Directory.systemTemp.createTemp('broomm-io-lost-');
    try {
      final file = File('${root.path}/payload');
      await expectLater(
        IoWorker(lostWriter, file.path).run(),
        throwsA(isA<DownloadWriterUncertain>()),
      );
      expect(await file.readAsBytes(), [9]);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
