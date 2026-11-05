import 'dart:async';

import 'package:flutter/services.dart';

import 'emulators.dart';

/// A read-only observation, never a persisted grant or a save-folder binding.
class AndroidRootReport {
  AndroidRootReport._(this.values);
  final Map<String, dynamic> values;

  factory AndroidRootReport.parse(Map<String, dynamic> values, AndroidApp app) {
    final user = values['user'];
    final uid = values['uid'];
    final gid = values['gid'];
    final sdk = values['sdk'];
    bool text(String key, {int max = 256}) =>
        values[key] is String &&
        (values[key] as String).isNotEmpty &&
        (values[key] as String).length <= max &&
        !(values[key] as String).runes.any((c) => c < 32 || c == 127);
    if (values['package'] != app.package ||
        values['build'] != app.build ||
        values['version'] != app.version ||
        user is! int ||
        user < 0 ||
        uid is! int ||
        uid ~/ 100000 != user ||
        uid % 100000 < 10000 ||
        gid is! int ||
        gid < 0 ||
        sdk is! int ||
        sdk < 24 ||
        !{
          '/data/user/$user/${app.package}',
          if (user == 0) '/data/data/${app.package}',
        }.contains(values['dataDir']) ||
        !text('mode') ||
        !RegExp(r'^[0-7]{3,4}$').hasMatch(values['mode']) ||
        !text('label') ||
        !RegExp(r'^u:object_r:[a-zA-Z0-9_]+:s[0-9]+(?::[a-zA-Z0-9_,.]+)?$')
            .hasMatch(values['label']) ||
        !text('signer') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(values['signer']) ||
        !text('device') ||
        !text('android') ||
        values['abis'] is! List ||
        (values['abis'] as List).isEmpty ||
        (values['abis'] as List).length > 8 ||
        !(values['abis'] as List).every(
          (v) => v is String && RegExp(r'^[a-zA-Z0-9_-]{1,32}$').hasMatch(v),
        )) {
      throw const FormatException(
        'Root inspection returned an incomplete or mismatched identity. No save connection was created.',
      );
    }
    return AndroidRootReport._(Map.unmodifiable(values));
  }
}

/// Explicit one-shot access. Neither construction nor emulator discovery asks
/// for root. Cancellation invalidates late replies even if the native UI closes.
class AndroidRootInspector {
  AndroidRootInspector({MethodChannel? channel, this.phase})
    : channel = channel ?? const MethodChannel('app.broomm/root-inspection');
  final MethodChannel channel;
  final void Function(String)? phase;
  String? _request;
  bool _cancelled = false;
  bool _disposed = false;

  void _phase(String message) {
    try {
      phase?.call('Android root inspection: $message');
    } catch (_) {}
  }

  Future<AndroidRootReport> inspect(
    AndroidEmulator emulator,
    AndroidApp app,
  ) async {
    if (_disposed || _request != null)
      throw StateError('Root inspection is already active or closed.');
    if (!androidEmulators.contains(emulator) ||
        !emulator.packages.contains(app.package) ||
        !app.enabled) {
      throw StateError(
        'Refresh and select an enabled emulator before inspecting root access.',
      );
    }
    final request = DateTime.now().microsecondsSinceEpoch.toString();
    _request = request;
    _cancelled = false;
    _phase('requesting read-only metadata for ${app.package}.');
    try {
      final result = await channel
          .invokeMapMethod<String, dynamic>('inspect', {
            'request': request,
            'package': app.package,
            'build': app.build,
          })
          .timeout(const Duration(seconds: 35));
      if (_cancelled || _disposed)
        throw PlatformException(
          code: 'cancelled',
          message: 'Root inspection cancelled.',
        );
      if (result == null)
        throw const FormatException('Android returned no root inspection.');
      final report = AndroidRootReport.parse(result, app);
      _phase(
        'package/user/directory metadata verified for ${app.package}; no save connection created.',
      );
      return report;
    } on TimeoutException {
      await cancel();
      _phase('request timed out; no result accepted.');
      throw PlatformException(
        code: 'timeout',
        message: 'Root inspection timed out. Check your root manager and retry explicitly.',
      );
    } catch (_) {
      _phase('request failed or cancelled; no result accepted.');
      rethrow;
    } finally {
      _request = null;
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    final request = _request;
    if (request == null) return;
    _phase('cancellation requested.');
    try {
      await channel
          .invokeMethod<void>('cancel', {'request': request})
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // The native request has its own deadline. A failed cancellation reply
      // cannot turn its eventual result into an accepted observation.
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(cancel());
  }
}
