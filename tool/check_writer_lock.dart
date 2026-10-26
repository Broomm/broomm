import 'dart:io';

Future<void> main(List<String> args) async {
  final file = await File(args.single).open(mode: FileMode.append);
  try {
    await file.lock(FileLock.exclusive);
    await file.unlock();
    exitCode = 1;
  } on FileSystemException {
    exitCode = 0;
  } finally {
    await file.close();
  }
}
