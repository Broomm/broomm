import 'dart:io';

import '../emulators.dart';
import '../game_launch.dart';
import '../nintendo_ds.dart';
import '../progress/layout.dart';
import '../session.dart';
import 'emulators.dart';
import 'save_plan.dart';

/// The emulator uses a user-selected Android DocumentsProvider directory whose
/// bytes remain in this profile's Broomm storage. No external app-private path
/// is guessed, copied wholesale, or made into another account's save history.
Future<ProgressLayout> androidProgressLayout(
  AndroidEmulators manager,
  String profile,
  AndroidEmulator emulator,
  GamePlatform platform,
  String rom, {
  String? contentId,
  String? package,
}) async {
  if (!manager.settingsKnown)
    throw StateError(
      'Android save-folder settings could not be read. Existing progress was kept.',
    );
  if (!manager.progressSupported(emulator))
    throw UnsupportedError(
      'Cloud saves for ${emulator.name} on Android need an emulator-specific storage adapter. External progress is kept.',
    );
  if (manager.folder(emulator, package: package) == null &&
      manager.tree(profile, emulator) == null)
    throw StateError(
      'Configure ${emulator.name}’s Broomm save folder in Emulator Settings first. Android cannot read another app’s private saves.',
    );
  final app = manager.app(emulator, package: package);
  if (app == null) throw StateError('Install ${emulator.name} first.');
  if (manager.folder(emulator, package: package) != null)
    return connectedAndroidProgress(
      manager,
      profile,
      emulator,
      platform,
      rom,
      contentId ?? File(rom).parent.path.split('/').last,
      package: package,
    );
  final root = await manager.privateRoot(profile, emulator);
  if (emulator.id == 'citra-mmj') {
    // MMJ's states have no validated Android compatibility contract yet. The
    // shared-folder session adapter also keeps its existing local states out of
    // another profile's session, without claiming to synchronize them.
    return threeDsProgressLayout(root.path, 'user', rom);
  }
  if (emulator.id == 'melonds') {
    final stem = File(rom).uri.pathSegments.last
        .replaceFirst(RegExp(r'\.[^.]+$'), '');
    return ProgressLayout(
      root.path,
      'melonds-sav-v1',
      await dsSaveIdentity(rom),
      [ProgressArea('save', 'user', prefix: stem, exact: '$stem.sav')],
      note: 'Native raw DS .sav. Select this Broomm folder as melonDS’s custom save folder. Android DS state format is not yet integrated.',
    );
  }
  final hash = await manager.fingerprint(app);
  final legacy = await gameProgressLayout(
    ResolvedSession(
      PreparedEmulator(emulator.name, root.path, '', 0, null, null),
      rom,
      hash,
      const {},
    ),
    platform.slug,
  );
  // Legacy connected roots placed states in one physical directory across APK
  // updates. Keep those bytes locally; without provenance they cannot be
  // relabelled under today's fingerprint. Reconnect for the isolated workflow.
  return ProgressLayout(
    legacy.root,
    legacy.format,
    legacy.game,
    legacy.areas.where((a) => !a.id.startsWith('states-')).toList(),
    note: legacy.note,
    rawSave: legacy.rawSave,
  );
}
