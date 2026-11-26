import 'dart:io';

import '../progress/files.dart';
import 'protocol.dart';

class RemoteHistory {
  RemoteHistory(this.directory);
  final Directory directory;
  List<Map<String, String>> hosts = [];
  String code = '';
  Future<void>? _writes;
  File get file => File('${directory.path}/remote-screen.json');

  Future<void> load() => _locked(() async {
    if (await file.exists()) {
      await _read();
    } else {
      code = progressNonce().substring(0, 16);
      await _save();
    }
  });

  Future<void> _read() async {
    final json = await progressJson(file);
    if (json['version'] != 1 ||
        json['code'] is! String ||
        json['hosts'] is! List) {
      throw const FormatException('Invalid saved remote screen settings.');
    }
    final savedCode = json['code'] as String;
    if (!RegExp(r'^[a-f0-9]{16}$').hasMatch(savedCode)) {
      throw const FormatException('Invalid remote connection code.');
    }
    final saved = <Map<String, String>>[];
    for (final host in (json['hosts'] as List).take(12)) {
      if (host is! Map ||
          host['address'] is! String ||
          host['code'] is! String ||
          !RegExp(r'^[a-f0-9]{16}$').hasMatch(host['code'])) {
        throw const FormatException('Invalid saved remote host.');
      }
      final address = RemoteAddress.parse(host['address']).label;
      if (!saved.any((h) => h['address'] == address)) {
        saved.add({'address': address, 'code': host['code']});
      }
    }
    code = savedCode;
    hosts = saved;
  }

  Future<void> remember(RemoteAddress address, String accessCode) =>
      _locked(() async {
        // Re-read under the OS lock so another Broomm process's history is retained.
        await _read();
        hosts.removeWhere((h) => h['address'] == address.label);
        hosts.insert(0, {'address': address.label, 'code': accessCode});
        hosts = hosts.take(12).toList();
        await _save();
      });

  Future<void> _save() async {
    await progressWrite(file, {'version': 1, 'code': code, 'hosts': hosts});
    if (!Platform.isWindows) {
      final result = await Process.run(
        Platform.isAndroid ? '/system/bin/chmod' : '/bin/chmod',
        ['600', file.path],
      );
      if (result.exitCode != 0)
        throw const FileSystemException(
          'Remote connection settings could not be made private.',
        );
    }
  }

  Future<void> _locked(Future<void> Function() operation) {
    final work = (_writes ?? Future<void>.value()).then((_) async {
      await progressDirectory(directory);
      final lockFile = await progressFile(directory, 'remote-screen.lock');
      final lock = await lockFile.open(mode: FileMode.append);
      try {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (true) {
          try {
            await lock.lock(FileLock.exclusive);
            break;
          } on FileSystemException {
            if (DateTime.now().isAfter(deadline))
              throw const FileSystemException(
                'Remote settings are in use. Retry the connection.',
              );
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
        }
        await operation();
      } finally {
        await lock.close();
      }
    });
    _writes = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return work;
  }
}
