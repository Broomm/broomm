import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final child = await Process.start(
    args[0],
    [args[3]],
    environment: {
      'DYLD_INSERT_LIBRARIES': args[1],
      'BROOMM_INSTALLER_WRITER_LOCK': args[2],
    },
  );
  final ready = await child.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first
      .timeout(const Duration(seconds: 5));
  if (ready != 'ready') exit(1);
  stdout.writeln('ready');
  await stdout.flush();
  exit(
    0,
  ); // deliberately leave the native child, whose writer lock must survive
}
