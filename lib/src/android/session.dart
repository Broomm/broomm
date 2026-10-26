import 'dart:io';

import 'package:flutter/foundation.dart';

import '../progress/files.dart';
import '../progress/service.dart';
import '../progress/layout.dart';
import '../session_lease.dart';
import 'emulators.dart';

/// A separate supervisor for external Android activities. Activity resume/result
/// is not writer-exit evidence. The owner explicitly confirms emulator closure.
/// A durable marker blocks new sessions after process/activity destruction.
class AndroidGameSession extends ChangeNotifier {
  AndroidGameSession(this.manager, this.cloud);
  final AndroidEmulators manager;
  final CloudSaves cloud;
  SessionLease? _lease;
  CloudGame? _game;
  bool _launched = false;
  bool busy = false, active = false, disposed = false;
  String phase = '', error = '';
  File get marker => File('${manager.data.path}/android/session.json');

  Future<Map<String, dynamic>?> pending() async {
    if (!await progressExists(marker.path)) return null;
    final value = await progressJson(marker);
    if (value['version'] != 1 ||
        !RegExp(r'^[a-f0-9]{32}$')
            .hasMatch(value['profile'] as String? ?? '') ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['server'] as String? ?? '') ||
        value['rom'] is! int ||
        (value['rom'] as int) < 1 ||
        !androidEmulators.any((e) => e.id == value['emulator']))
      throw const FormatException(
        'Android session recovery record is invalid. Progress was kept.',
      );
    return value;
  }

  Future<void> start({
    required String server,
    required String profile,
    required int rom,
    required AndroidEmulator emulator,
    required AndroidApp app,
    required List<String> files,
    required String selected,
    String? core,
    CloudGame? game,
    ProgressResolver? resolve,
    Future<CloudGame?> Function()? prepare,
  }) async {
    if (![
          server,
          profile,
        ].every((v) => RegExp(r'^[a-f0-9]{32}$').hasMatch(v)) ||
        rom < 1)
      throw const FormatException('Invalid Android session identity');
    if (busy || active)
      throw StateError('An Android game session is already active.');
    busy = true;
    error = '';
    _emit();
    try {
      _lease = await SessionLease.acquire(manager.data);
      if (await pending() != null)
        throw StateError(
          'Close the previous Android emulator and finish its session before launching another game.',
        );
      await manager.ensureNoWriters();
      _game = game;
      _launched = false;
      // Publish before sync or handoff. An exception/unknown platform reply
      // keeps the marker until closure is confirmed; it cannot be a false exit.
      await progressWrite(
        await progressFile(
          manager.data,
          'android/session.json',
          createParents: true,
        ),
        {
          'version': 1,
          'server': server,
          'profile': profile,
          'rom': rom,
          'emulator': emulator.id,
          'package': app.package,
          'selected': selected,
        },
      );
      active = true;
      _game = prepare == null ? game : await prepare();
      if (_game != null) {
        if (_game!.server != server ||
            _game!.profile != profile ||
            _game!.rom != rom)
          throw StateError(
            'Android progress belongs to another game or profile. No cloud save was changed.',
          );
        await progressWrite(marker, {
          ...(await pending())!,
          'stateAreas': [
            for (final area in _game!.layout.areas)
              if (area.id.startsWith('states-')) area.id,
          ],
        });
        phase = 'Checking BROOMM cloud saves…';
        _emit();
        await cloud.beforePlay(_game!, resolve: resolve);
      }
      phase = 'Opening ${emulator.name}…';
      _emit();
      await manager.launch(
        emulator,
        app,
        files,
        selected,
        core: core,
        profile: profile,
      );
      _launched = true;
      phase =
          'Game handed to ${emulator.name}. Save and exit the emulator, then finish this session.';
    } catch (e) {
      error = '$e';
      if (!active) {
        await _lease?.release();
        _lease = null;
      }
      rethrow;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> finish({
    required bool emulatorClosed,
    CloudGame? recovery,
  }) async {
    if (!emulatorClosed)
      throw StateError('Close the emulator before synchronizing progress.');
    if (busy) throw StateError('The Android session is still busy.');
    busy = true;
    error = '';
    _emit();
    try {
      final record = await pending();
      if (record == null) {
        if (active)
          throw StateError(
            'The Android recovery record is missing. Progress was kept; do not launch another emulator.',
          );
        active = false;
        await _lease?.release();
        _lease = null;
        return;
      }
      _lease ??= await SessionLease.acquire(manager.data);
      await manager.ensureNoWriters();
      var game = recovery ?? _game;
      var changedBuild = false;
      if (game != null) {
        if (game.profile != record['profile'] ||
            game.server != record['server'] ||
            game.rom != record['rom'])
          throw StateError(
            'Choose the original Android game profile before synchronizing its session.',
          );
        final recorded = (record['stateAreas'] as List? ?? []).toSet();
        final current = game.layout.areas
            .where((a) => a.id.startsWith('states-'))
            .map((a) => a.id)
            .toSet();
        changedBuild =
            recorded.length != current.length || !recorded.containsAll(current);
        if (changedBuild) {
          final layout = game.layout;
          game = CloudGame(
            server: game.server,
            profile: game.profile,
            user: game.user,
            rom: game.rom,
            client: game.client,
            layout: ProgressLayout(
              layout.root,
              layout.format,
              layout.game,
              layout.areas.where((a) => !a.id.startsWith('states-')).toList(),
              note: layout.note,
              rawSave: layout.rawSave,
            ),
          );
        }
        phase = 'Keeping your progress safe…';
        _emit();
        // A restart is unclean recovery, requiring the existing explicit
        // conflict/review flow. Mere resume never certifies a clean shutdown.
        await cloud.afterPlay(
          game,
          _game == null || !_launched || changedBuild ? 1 : 0,
        );
      }
      await manager.releaseGrants();
      await marker.delete();
      active = false;
      _game = null;
      _launched = false;
      phase = game == null
          ? 'Session finished. Progress remains in the external emulator.'
          : 'Session finished. Local recovery and pending cloud transfers were retained.';
      await _lease?.release();
      _lease = null;
    } catch (e) {
      error = '$e';
      rethrow;
    } finally {
      busy = false;
      _emit();
    }
  }

  void _emit() {
    if (!disposed) notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    // Keep the durable marker. Releasing our coordinator is not evidence that
    // the independently owned Android emulator process has exited.
    _lease?.release();
    _lease = null;
    super.dispose();
  }
}
