import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../progress/digest.dart';
import 'cdp.dart';
import 'launch_target.dart';

typedef SteamAssets = Future<List<int>> Function(String path);

class SteamInstallation {
  const SteamInstallation(this.appId);
  final int appId;
}

/// Explicit, current-account CEF installation. Never edits shortcuts.vdf or
/// restarts Steam; a durable intent and a native-context job join lost replies.
class SteamInstaller {
  SteamInstaller({
    required this.loadAsset,
    bool? enabled,
    Future<SteamConnection> Function()? connect,
    Future<SteamLaunchTarget> Function()? launchTarget,
  }) : enabled =
           enabled ??
           (Platform.isLinux || Platform.isMacOS || Platform.isWindows),
       connect = connect ?? SteamCef.connect,
       launchTarget = launchTarget ?? SteamLaunchTarget.resolve;
  final bool enabled;
  final SteamAssets loadAsset;
  final Future<SteamConnection> Function() connect;
  final Future<SteamLaunchTarget> Function() launchTarget;
  bool _busy = false;

  Future<SteamInstallation> install(
    Directory storage, {
    void Function(String)? phase,
  }) async {
    if (!enabled)
      throw UnsupportedError('Add to Steam is available on desktop systems.');
    if (_busy) throw StateError('Add to Steam is already running.');
    _busy = true;
    RandomAccessFile? lock;
    SteamConnection? client;
    try {
      final target = await launchTarget();
      SteamLaunchTarget.validate(target.executable);
      SteamLaunchTarget.validate(target.directory);
      // Load and validate bounded local assets before external changes.
      final script = utf8.decode(await loadAsset('assets/steam/bridge.js'));
      if (script.length > 32768 ||
          !script.contains('async function broommSteam(request)'))
        throw StateError(
          'The bundled Steam integration is incomplete. Reinstall Broomm.',
        );
      final artwork = <String, List<int>>{};
      for (final kind in ['cover', 'horizontal', 'hero', 'logo']) {
        artwork[kind] = await _png('assets/steam/$kind.png');
      }
      final icon = await _png('assets/branding/broomm-icon.png');
      await storage.create(recursive: true);
      final directory = Directory(
        '${await storage.resolveSymbolicLinks()}/steam',
      );
      await _directory(directory);
      final guard = File('${directory.path}/installation.lock');
      await _regular(guard);
      lock = await guard.open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.exclusive);
      } on FileSystemException {
        throw StateError(
          'Another Broomm process is adding a Steam shortcut. Let it finish and retry.',
        );
      }
      phase?.call('Connecting to Steam…');
      client = await connect();
      final connection = client;
      Future<Map<String, dynamic>> call(Map<String, dynamic> input) async {
        final response = await connection.evaluate(
          '($script)(${jsonEncode(input)})',
        );
        if (response['error'] case final String error) throw StateError(error);
        return response;
      }

      final context = await call({'op': 'context'});
      final account = context['account'];
      final session = context['session'];
      if (account is! String ||
          !RegExp(r'^\d{17}$').hasMatch(account) ||
          session is! String ||
          !RegExp(r'^[a-f0-9-]{36}$').hasMatch(session))
        throw StateError(
          'Steam did not identify its active account and session.',
        );
      final receipt = File('${directory.path}/$account.json');
      await _regular(receipt);
      Map<String, dynamic>? saved;
      if (await receipt.exists()) {
        if (await receipt.length() > 16384)
          throw StateError(
            'The Steam receipt is damaged. Keep it for recovery before adding again.',
          );
        final data = jsonDecode(await receipt.readAsString());
        if (data is! Map<String, dynamic> ||
            data['version'] != 1 ||
            data['account'] != account ||
            data['target'] is! String ||
            data['previous'] is! String ||
            data['session'] is! String ||
            data['token'] is! String ||
            (data['id'] != null && !_id(data['id'])))
          throw StateError(
            'The Steam receipt is damaged. Keep it for recovery before adding again.',
          );
        saved = data;
      }
      final previous = saved?['previous'] ?? target.executable;
      final base = <String, dynamic>{
        'account': account,
        'target': target.executable,
        'previous': previous,
        'id': saved?['id'],
      };
      phase?.call('Finding the Broomm shortcut…');
      final inspection = await call({...base, 'op': 'inspect'});
      final ids = inspection['ids'];
      if (ids is! List || !ids.every(_id))
        throw StateError('Steam shortcut inspection was incomplete.');
      if (ids.length > 1)
        throw StateError(
          'Multiple shortcuts launch this Broomm copy. Remove the duplicate shortcuts in Steam, then retry.',
        );
      if (ids.isEmpty &&
          saved?['id'] != null &&
          saved?['session'] == session &&
          saved?['complete'] != true)
        throw StateError(
          'Steam has not exposed the pending Broomm shortcut yet. Wait for its library, or restart Steam normally, then retry.',
        );
      int? id = ids.isEmpty ? null : ids.single as int;
      var token = _token();
      if (saved != null && saved['id'] == null && saved['session'] == session) {
        // Never issue another native create after a lost reply in this session.
        if (saved['target'] != target.executable)
          throw StateError(
            'A Steam shortcut request for another Broomm location is pending. Restart Steam normally, then retry from this copy.',
          );
        token = saved['token'] as String;
      }
      var record = <String, dynamic>{
        'version': 1,
        'account': account,
        'session': session,
        'token': token,
        'target': target.executable,
        'previous': previous,
        'id': id,
      };
      await _publish(receipt, utf8.encode(jsonEncode(record)));
      if (id == null) {
        phase?.call('Adding Broomm to your Steam library…');
        final created = await call({...base, 'op': 'create', 'token': token});
        if (!_id(created['id']))
          throw StateError(
            'Steam has not confirmed the new shortcut. Retry Add to Steam.',
          );
        id = created['id'] as int;
        record = {...record, 'id': id};
        await _publish(receipt, utf8.encode(jsonEncode(record)));
      }
      final iconFile = File('${directory.path}/broomm.png');
      await _publish(iconFile, icon);
      phase?.call('Configuring the Broomm shortcut…');
      await call({
        ...base,
        'op': 'configure',
        'id': id,
        'directory': target.directory,
        'icon': iconFile.path,
      });
      // After field readback the current path is the only accepted owned target.
      record = {...record, 'previous': target.executable};
      await _publish(receipt, utf8.encode(jsonEncode(record)));
      for (final entry in artwork.entries) {
        phase?.call('Installing Steam ${entry.key} artwork…');
        final digest = ProgressDigest.sha256()..add(entry.value);
        final result = await call({
          ...base,
          'previous': target.executable,
          'op': 'artwork',
          'id': id,
          'kind': entry.key,
          'sha256': digest.finish(),
          'data': base64Encode(entry.value),
        });
        if (result['verified'] != true)
          throw StateError(
            'The Broomm shortcut was added, but Steam artwork is incomplete. Retry Add to Steam.',
          );
      }
      await _publish(
        receipt,
        utf8.encode(jsonEncode({...record, 'complete': true})),
      );
      return SteamInstallation(id);
    } finally {
      try {
        await client?.close();
      } finally {
        try {
          await lock?.close();
        } finally {
          _busy = false;
        }
      }
    }
  }

  Future<List<int>> _png(String path) async {
    final data = await loadAsset(path);
    if (data.length < 24 ||
        data.length > 4 * 1024 * 1024 ||
        !const [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ].asMap().entries.every((e) => data[e.key] == e.value))
      throw StateError(
        'The bundled Broomm artwork is invalid. Reinstall Broomm.',
      );
    return data;
  }
}

bool _id(dynamic value) => value is int && value > 0 && value <= 0xffffffff;
String _token() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
Future<void> _regular(File file) async {
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type != FileSystemEntityType.file &&
      type != FileSystemEntityType.notFound)
    throw FileSystemException(
      'A linked or foreign Steam receipt was preserved',
      file.path,
    );
}

Future<void> _directory(Directory directory) async {
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    await directory.create();
  } else if (type != FileSystemEntityType.directory) {
    throw FileSystemException(
      'A linked or foreign Steam directory was preserved',
      directory.path,
    );
  }
}

Future<void> _publish(File destination, List<int> bytes) async {
  await _regular(destination);
  final stage = await destination.parent.createTemp('.pending-');
  try {
    final file = File('${stage.path}/entry');
    await file.writeAsBytes(bytes, flush: true);
    await _regular(destination);
    await file.rename(destination.path);
    final saved = await destination.readAsBytes();
    if (saved.length != bytes.length ||
        !bytes.asMap().entries.every((e) => saved[e.key] == e.value))
      throw const FileSystemException(
        'The Steam installation receipt could not be confirmed',
      );
  } finally {
    await stage.delete(recursive: true);
  }
}
