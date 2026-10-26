import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final file = await File(args.single).open(mode: FileMode.append);
  try {
    await file.lock(FileLock.exclusive);
    stdout.writeln('held');
    await stdout.flush();
    await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  } finally {
    await file.close();
  }
}
