import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/romm/client.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/shell/library.dart';
import 'package:broomm/src/session_lease.dart';

class UnknownWriter extends RommClient {
  UnknownWriter() : super(Uri.parse('http://example.invalid'));
  @override
  Future<void> downloadFile(
    RommFile f,
    File destination, {
    required DownloadCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    await destination.writeAsString('retained partial', flush: true);
    throw const DownloadWriterUncertain();
  }
}

Future<void> main(List<String> args) async {
  final data = Directory(args.single),
      library = GameLibrary(Directory(args.single));
  const server = '0123456789abcdef0123456789abcdef';
  const game = RommGame(
    id: 1,
    name: 'Fixture',
    platformId: 4,
    platform: 'GameCube',
    bytes: 9,
    fsName: 'Game.iso',
    fullPath: 'roms/ngc/Game.iso',
    files: [
      RommFile(
        id: 10,
        romId: 1,
        name: 'Game.iso',
        fullPath: 'roms/ngc/Game.iso',
        bytes: 9,
      ),
    ],
  );
  final client = UnknownWriter();
  var retained = false, blocked = false;
  try {
    await library.install(
      serverId: server,
      userId: 1,
      game: game,
      client: client,
      cancellation: DownloadCancellation(),
      progress: (_) {},
    );
  } on DownloadWriterUncertain {
    retained = true;
  }
  try {
    await library.install(
      serverId: server,
      userId: 1,
      game: game,
      client: client,
      cancellation: DownloadCancellation(),
      progress: (_) {},
    );
  } on RommFailure {
    blocked = true;
  }
  if (!await Directory('${data.path}/library/$server').exists())
    throw StateError('Private stage disappeared');
  final lease = await SessionLease.acquire(data);
  lease.retainForUncertainWriter();
  await lease.release();
  var sessionBlocked = false;
  try {
    await SessionLease.acquire(data);
  } on StateError {
    sessionBlocked = true;
  }
  stdout.writeln(
    jsonEncode({
      'retained': retained,
      'retryBlocked': blocked,
      'sessionBlocked': sessionBlocked,
    }),
  );
  await stdout.flush();
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  client.close();
}
