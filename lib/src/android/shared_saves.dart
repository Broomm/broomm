import 'dart:io';

import '../progress/files.dart';
import '../progress/digest.dart';
import '../progress/layout.dart';
import '../progress/service.dart';
import '../progress/store.dart';
import '../progress/zip.dart';
import '../retroarch.dart';
import 'emulators.dart';
import 'save_plan.dart';
import 'opera.dart';
import 'saturn.dart';
import 'flycast_session.dart';

/// One journaled external-folder transaction. The session holds SessionLease;
/// the session supplies emulator-closure evidence before save operations.
class SharedAndroidSaves {
  SharedAndroidSaves(this.manager, {this.phase});
  final AndroidEmulators manager;
  final void Function(String)? phase;
  File get journal => File('${manager.data.path}/android/shared-swap.json');
  Future<bool> get pending => progressExists(journal.path);
  Directory directory(Map record) => Directory(
    '${manager.data.path}/android/shared-session/${record['transaction']}',
  );
  Map<String, dynamic> inventory(Object? value, AndroidSavePlan plan) {
    if (value is! Map || value.length > (plan.rooted ? 128 : progressMaxFiles))
      throw const FormatException('Invalid Android save inventory');
    final files = value.cast<String, dynamic>();
    var total = 0;
    for (final e in files.entries) {
      progressRelative(e.key);
      if (plan.localKey(e.key) == null)
        throw const FormatException(
          'Android save is outside the selected game',
        );
      final v = e.value;
      if (v is! Map ||
          v['bytes'] is! int ||
          v['bytes'] < 0 ||
          v['bytes'] >
              (plan.rooted
                  ? _rootProgressLimit(plan, e.key)
                  : progressMaxFileBytes) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(v['sha256'] as String? ?? ''))
        throw const FormatException('Invalid Android save metadata');
      if (plan.rooted &&
          plan.launch['coreName'] == 'flycast' &&
          e.key.contains('/saves/') &&
          v['bytes'] != 131072)
        throw const FormatException(
          'Dreamcast VMU is incomplete. Existing progress was kept.',
        );
      if (plan.rooted &&
          plan.launch['coreName'] == 'opera' &&
          e.key.contains('/saves/') &&
          v['bytes'] != 32768)
        throw const FormatException(
          'Opera NVRAM is incomplete. Existing progress was kept.',
        );
      if (plan.rooted &&
          plan.launch['coreName'] == 'mednafen_saturn' &&
          e.key.contains('/saves/') &&
          v['bytes'] != _rootProgressLimit(plan, e.key))
        throw const FormatException(
          'Saturn backup memory is incomplete. Existing progress was kept.',
        );
      if (plan.rooted &&
          (v['metadata'] is! String ||
              !RegExp(
                '^${plan.binding['uid']} [0-9]+ [0-7]{3} ${RegExp.escape(plan.binding['label']!)}\$',
              ).hasMatch(v['metadata'] as String)))
        throw const FormatException(
          'Root save ownership metadata is incomplete.',
        );
      total += v['bytes'] as int;
      if (total >
          (plan.rooted
              ? (plan.launch['coreName'] == 'flycast' ? 128 : 64) * 1024 * 1024
              : progressMaxBytes))
        throw const FormatException('Android progress exceeds its size limit');
    }
    return files;
  }

  bool same(Map a, Map b) =>
      progressEntriesDigest(a.cast<String, dynamic>()) ==
          progressEntriesDigest(b.cast<String, dynamic>()) &&
      a.keys.every((key) => a[key]['metadata'] == b[key]['metadata']);
  Future<Map<String, dynamic>> list(AndroidSavePlan plan) async => inventory(
    await manager.channel.invokeMapMethod<String, dynamic>(
      plan.method('List'),
      {
        ...plan.arguments,
        'areas': plan.remoteAreas.map((a) => a.selector).toList(),
      },
    ),
    plan,
  );
  Future<Map<String, dynamic>> record(
    CloudGame game,
    AndroidSavePlan plan,
  ) async {
    final r = await progressJson(journal);
    if (!{1, 2, 3, 4, 5}.contains(r['version']) ||
        r['server'] != game.server ||
        r['profile'] != game.profile ||
        r['rom'] != game.rom ||
        r['title'] != plan.game ||
        r['emulator'] != plan.emulator.id ||
        r['tree'] != plan.binding['tree'] ||
        r['package'] != plan.binding['package'] ||
        (r['rootPlatform'] != null &&
            r['rootPlatform'] != plan.launch['platform']) ||
        plan.binding.entries.any((e) => r[e.key] != e.value) ||
        !RegExp(r'^[a-f0-9]{32}$')
            .hasMatch(r['transaction'] as String? ?? '') ||
        !{
          'installing',
          'installed',
          'captured',
          'restoring',
          'restored',
        }.contains(r['phase']))
      throw const FormatException(
        'Android save recovery identity changed. Reconnect the original emulator/profile.',
      );
    inventory(r['original'], plan);
    inventory(r['working'], plan);
    if (r['captured'] != null) inventory(r['captured'], plan);
    _lynxFirmware(r, plan);
    _operaFirmware(r, plan);
    _saturnFirmware(r, plan);
    _flycastResources(r, plan);
    if (r['rootFlycastHeldProgress'] case final Object held) {
      if (r['version'] != 5 ||
          held is! Map ||
          held.length != 2 ||
          !RegExp(r'^captures/[a-f0-9]{32}/native$')
              .hasMatch(held['directory'] as String? ?? ''))
        throw const FormatException('Invalid held Dreamcast progress capture.');
      inventory(held['files'], plan);
    }
    return r;
  }

  AndroidFlycastSessionResources? _flycastResources(
    Map r,
    AndroidSavePlan plan,
  ) {
    if (r['version'] != 5) {
      if (r.containsKey('rootFlycastResources') ||
          r.containsKey('rootFlycastConsoleBefore') ||
          r.containsKey('rootFlycastCapture') ||
          r.containsKey('rootFlycastHeldProgress') ||
          plan.launch['coreName'] == 'flycast')
        throw const FormatException('Dreamcast recovery record is incomplete.');
      return null;
    }
    final resources = AndroidFlycastSessionResources(manager, plan);
    resources.validate(r);
    return resources;
  }

  Map<String, dynamic>? _lynxFirmware(Map r, AndroidSavePlan plan) {
    if ({3, 4, 5}.contains(r['version'])) return null;
    if (r['version'] == 1) {
      if (r['rootFirmware'] != null ||
          plan.launch['coreName'] == 'mednafen_lynx')
        throw const FormatException(
          'Lynx firmware recovery record is incomplete.',
        );
      return null;
    }
    final f = r['rootFirmware'], config = r['rootConfigPath'];
    if (!plan.rooted ||
        plan.launch['coreName'] != 'mednafen_lynx' ||
        plan.launch['platform'] != 'lynx' ||
        f is! Map ||
        f.length != 3 ||
        f['bytes'] != 512 ||
        config is! String ||
        config != plan.launch['configPath'] ||
        !config.startsWith('files/Broomm/${r['profile']}/${r['rom']}/') ||
        f['path'] != _lynxFirmwarePath(config) ||
        f['path'] != plan.launch['lynxFirmwarePath'] ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(f['sha256'] as String? ?? ''))
      throw const FormatException(
        'Lynx firmware recovery identity changed. Files were kept.',
      );
    return f.cast<String, dynamic>();
  }

  Map<String, dynamic> _operaFirmware(Map r, AndroidSavePlan plan) {
    if (r['version'] != 3) {
      if (r['rootOperaFirmware'] != null || plan.launch['coreName'] == 'opera')
        throw const FormatException(
          'Opera firmware recovery record is incomplete.',
        );
      return {};
    }
    final resources = r['rootOperaFirmware'], config = r['rootConfigPath'];
    if (!plan.rooted ||
        plan.launch['coreName'] != 'opera' ||
        r['coreName'] != 'opera' ||
        r['rootFirmware'] != null ||
        plan.launch['platform'] != '3do' ||
        resources is! Map ||
        resources.length > 2 ||
        config is! String ||
        config != plan.launch['configPath'] ||
        !config.startsWith('files/Broomm/${r['profile']}/${r['rom']}/'))
      throw const FormatException(
        'Opera firmware recovery identity changed. Files were kept.',
      );
    final system = _operaSystemDirectory(config);
    if (r['transaction'] !=
        config.substring(config.lastIndexOf('/config-') + 8, config.length - 4))
      throw const FormatException(
        'Opera disc and firmware transaction identities differ. Recovery was kept.',
      );
    var bios = 0, fonts = 0;
    for (final entry in resources.entries) {
      final spec = androidOperaFirmware[entry.key], value = entry.value;
      if (spec == null ||
          value is! Map ||
          value.length != 3 ||
          value['path'] != '$system/${entry.key}' ||
          value['bytes'] != spec.$1 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String? ?? ''))
        throw const FormatException(
          'Invalid Opera firmware recovery resource. Files were kept.',
        );
      if ((entry.key as String).contains('kanji')) {
        fonts++;
      } else {
        bios++;
      }
    }
    if (bios > 1 || fonts > 1)
      throw const FormatException(
        'Ambiguous Opera firmware recovery resources.',
      );
    return resources.cast<String, dynamic>();
  }

  Map<String, dynamic> _saturnFirmware(Map r, AndroidSavePlan plan) {
    if (r['version'] != 4) {
      if (r['rootSaturnFirmware'] != null ||
          plan.launch['coreName'] == 'mednafen_saturn')
        throw const FormatException(
          'Saturn firmware recovery record is incomplete.',
        );
      return {};
    }
    final resources = r['rootSaturnFirmware'], config = r['rootConfigPath'];
    if (!plan.rooted ||
        plan.launch['coreName'] != 'mednafen_saturn' ||
        r['coreName'] != 'mednafen_saturn' ||
        r['rootFirmware'] != null ||
        plan.launch['platform'] != 'saturn' ||
        resources is! Map ||
        resources.length < 2 ||
        resources.length > 3 ||
        config is! String ||
        config != plan.launch['configPath'] ||
        !config.startsWith('files/Broomm/${r['profile']}/${r['rom']}/'))
      throw const FormatException(
        'Saturn firmware recovery identity changed. Files were kept.',
      );
    final system = _operaSystemDirectory(config);
    if (r['transaction'] !=
        config.substring(config.lastIndexOf('/config-') + 8, config.length - 4))
      throw const FormatException(
        'Saturn disc and firmware transaction identities differ. Recovery was kept.',
      );
    if (!resources.keys.toSet().containsAll({'sega_101.bin', 'mpr-17933.bin'}))
      throw const FormatException(
        'Saturn regional BIOS recovery resources are incomplete. Files were kept.',
      );
    for (final entry in resources.entries) {
      final spec = androidSaturnFirmware[entry.key], value = entry.value;
      if (spec == null ||
          value is! Map ||
          value.length != 3 ||
          value['path'] != '$system/${entry.key}' ||
          value['bytes'] != spec.$1 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String? ?? ''))
        throw const FormatException(
          'Invalid Saturn firmware recovery resource. Files were kept.',
        );
    }
    return resources.cast<String, dynamic>();
  }

  Future<void> copy(File from, File to, Map metadata) async {
    await to.create(exclusive: true);
    final out = await to.open(mode: FileMode.writeOnly);
    try {
      var count = 0;
      await for (final b in from.openRead()) {
        count += b.length;
        if (count > metadata['bytes'])
          throw StateError(
            'A private Android recovery source grew during copy.',
          );
        await out.writeFrom(b);
      }
      await out.flush();
    } finally {
      await out.close();
    }
    if (await to.length() != metadata['bytes'] ||
        await progressFileHash(to) != metadata['sha256'] ||
        await progressFileHash(from) != metadata['sha256'])
      throw StateError('A private Android recovery copy changed.');
  }

  Future<void> read(
    Map r,
    AndroidSavePlan plan,
    Map<String, dynamic> files,
    String where,
  ) async {
    phase?.call(
      '${plan.emulator.name}: keeping ${files.length} save files in private recovery.',
    );
    for (final e in files.entries) {
      final target = await progressFile(
        directory(r),
        '$where/${e.key}',
        createParents: true,
      );
      await manager.channel.invokeMethod<void>(plan.method('Read'), {
        ...plan.arguments,
        'path': e.key,
        'target': target.path,
        ...e.value as Map,
      });
      if (await target.length() != e.value['bytes'] ||
          await progressFileHash(target) != e.value['sha256'])
        throw StateError('Android snapshot failed verification.');
    }
    if (!same(await list(plan), files))
      throw StateError(
        'Emulator saves changed during capture. Close it and retry; recovery copies were kept.',
      );
  }

  Future<void> begin(
    CloudGame game,
    AndroidSavePlan plan,
    String build, {
    required String selected,
  }) async {
    if (await pending)
      throw StateError('Finish the previous connected-folder game first.');
    if (plan.root !=
        '${manager.data.path}/profiles/${game.profile}/emulators/${plan.emulator.id}')
      throw const FormatException(
        'Android save root belongs to another profile',
      );
    final boot = plan.lynxBootImage;
    final lynx = plan.rooted && plan.launch['coreName'] == 'mednafen_lynx';
    final opera = plan.rooted && plan.launch['coreName'] == 'opera';
    final saturn = plan.rooted && plan.launch['coreName'] == 'mednafen_saturn';
    final flycast = plan.rooted && plan.launch['coreName'] == 'flycast';
    if (flycast &&
            (plan.flycastDisc == null ||
                plan.flycastDisc!.file.path != selected ||
                plan.flycastResources == null) ||
        !flycast &&
            (plan.flycastDisc != null ||
                plan.flycastResources != null ||
                plan.flycastConsole != null))
      throw StateError(
        'Prepare the verified Dreamcast disc and resources before Play.',
      );
    if (lynx && boot == null || !lynx && boot != null)
      throw StateError(
        'Prepare the verified Lynx BIOS before starting this session.',
      );
    final operaResources = plan.operaResources;
    if (opera &&
            (operaResources == null ||
                plan.operaDisc == null ||
                plan.operaDisc!.file.path != selected ||
                operaResources.map((f) => f.name).join('\n') !=
                    androidOperaResourceNames(plan.operaOptions).join('\n')) ||
        !opera && (operaResources != null || plan.operaDisc != null))
      throw StateError(
        'Prepare the verified Opera disc and selected firmware before starting this session.',
      );
    final saturnResources = plan.saturnResources;
    if (saturn &&
            (saturnResources == null ||
                plan.saturnDisc == null ||
                plan.saturnDisc!.file.path != selected ||
                saturnResources.map((f) => f.name).join('\n') !=
                    androidSaturnResourceNames(plan.saturnOptions)
                        .join('\n')) ||
        !saturn && (saturnResources != null || plan.saturnDisc != null))
      throw StateError(
        'Prepare the verified Saturn disc and firmware before starting this session.',
      );
    await manager.channel.invokeMethod<void>(
      plan.method('Check'),
      plan.arguments,
    );
    final r = <String, dynamic>{
      'version': flycast
          ? 5
          : saturn
          ? 4
          : opera
          ? 3
          : lynx
          ? 2
          : 1,
      'transaction': opera || saturn || flycast
          ? plan.launch['transaction']
          : progressNonce(),
      ...plan.arguments,
      'server': game.server,
      'profile': game.profile,
      'rom': game.rom,
      'title': plan.game,
      'build': build,
      'selected': selected,
      if (plan.rooted) 'rootConfigPath': plan.launch['configPath'],
      if (plan.rooted && plan.launch['platform'] != null)
        'rootPlatform': plan.launch['platform'],
      if (plan.rooted && plan.launch['stateGroup'] != null)
        'rootStateGroup': plan.launch['stateGroup'],
      'phase': 'installing',
      'original': await list(plan),
      'working': <String, dynamic>{},
      if (lynx)
        'rootFirmware': {
          'path': plan.launch['lynxFirmwarePath'],
          'bytes': 512,
          'sha256': boot!.sha256,
        },
      if (opera)
        'rootOperaFirmware': {
          for (final image in operaResources!)
            image.name: {
              'path':
                  '${_operaSystemDirectory(plan.launch['configPath']!)}/${image.name}',
              'bytes': image.bytes,
              'sha256': image.sha256,
            },
        },
      if (saturn)
        'rootSaturnFirmware': {
          for (final image in saturnResources!)
            image.name: {
              'path':
                  '${_operaSystemDirectory(plan.launch['configPath']!)}/${image.name}',
              'bytes': image.bytes,
              'sha256': image.sha256,
            },
        },
    };
    _lynxFirmware(r, plan);
    final operaFirmware = _operaFirmware(r, plan);
    final saturnFirmware = _saturnFirmware(r, plan);
    await progressDirectory(directory(r));
    if (flycast) await AndroidFlycastSessionResources(manager, plan).stage(r);
    if (boot != null) {
      if (await boot.file.length() != 512)
        throw const FormatException(
          'The verified Lynx BIOS changed before staging.',
        );
      await copy(
        boot.file,
        await progressFile(
          directory(r),
          'firmware/lynxboot.img',
          createParents: true,
        ),
        {'bytes': 512, 'sha256': boot.sha256},
      );
    }
    for (final image in operaResources ?? <AndroidOperaResource>[]) {
      await copy(
        image.file,
        await progressFile(
          directory(r),
          'firmware/${image.name}',
          createParents: true,
        ),
        {'bytes': image.bytes, 'sha256': image.sha256},
      );
    }
    for (final image in saturnResources ?? <AndroidSaturnResource>[]) {
      await copy(
        image.file,
        await progressFile(
          directory(r),
          'firmware/${image.name}',
          createParents: true,
        ),
        {'bytes': image.bytes, 'sha256': image.sha256},
      );
    }
    await read(r, plan, r['original'] as Map<String, dynamic>, 'original');
    final working = r['working'] as Map<String, dynamic>;
    for (final e in (await plan.files()).entries) {
      final remote = plan.remotePath(e.key),
          metadata = {
            'bytes': await e.value.length(),
            'sha256': await progressFileHash(e.value),
            if (plan.rooted)
              'metadata':
                  (r['original'] as Map)[remote]?['metadata'] ??
                  '${plan.binding['uid']} ${plan.binding['uid']} 600 ${plan.binding['label']}',
          };
      if (working.containsKey(remote))
        throw const FormatException('Ambiguous Android save mapping');
      working[remote] = metadata;
      await copy(
        e.value,
        await progressFile(
          directory(r),
          'working/$remote',
          createParents: true,
        ),
        metadata,
      );
    }
    if (saturn)
      verifyAndroidSaturnWorking(
        plan.saturnOptions,
        retroStateStem(selected),
        working.keys,
      );
    inventory(working, plan);
    await progressWrite(
      await progressFile(
        manager.data,
        'android/shared-swap.json',
        createParents: true,
      ),
      r,
    );
    await apply(r, plan, 'original', 'working', 'working');
    if (flycast) await _flycastResources(r, plan)!.install(r);
    final firmware = _lynxFirmware(r, plan);
    if (firmware != null) {
      await manager.channel.invokeMethod<void>('rootLynxFirmware', {
        ...plan.arguments,
        'path': firmware['path'],
        'configPath': plan.launch['configPath'],
        'before': null,
        'after': firmware['sha256'],
        'source': (await progressFile(
          directory(r),
          'firmware/lynxboot.img',
        )).path,
        'token': '${r['transaction']}-in',
      });
    }
    for (final entry in operaFirmware.entries) {
      await manager.channel.invokeMethod<void>('rootOperaFirmware', {
        ...plan.arguments,
        'path': entry.value['path'],
        'configPath': plan.launch['configPath'],
        'before': null,
        'after': entry.value['sha256'],
        'source': (await progressFile(
          directory(r),
          'firmware/${entry.key}',
        )).path,
        'token': '${r['transaction']}-in',
      });
    }
    for (final entry in saturnFirmware.entries) {
      await manager.channel.invokeMethod<void>('rootSaturnFirmware', {
        ...plan.arguments,
        'path': entry.value['path'],
        'configPath': plan.launch['configPath'],
        'before': null,
        'after': entry.value['sha256'],
        'source': (await progressFile(
          directory(r),
          'firmware/${entry.key}',
        )).path,
        'token': '${r['transaction']}-in',
      });
    }
    await configure(r, plan);
    r['phase'] = 'installed';
    await progressWrite(journal, r);
  }

  /// A pending native session keeps its original physical state group. A newer
  /// core may capture those bytes for recovery but cannot relabel them as its own.
  Future<AndroidSavePlan> recoveryPlan(
    CloudGame game,
    AndroidSavePlan current,
  ) async {
    if (!current.rooted) return current;
    final r = await progressJson(journal);
    final group = r['rootStateGroup'];
    if (group != null &&
        (group is! String ||
            !RegExp(r'^states-[a-f0-9]{16}-android$').hasMatch(group)))
      throw const FormatException('Invalid rooted state recovery group.');
    final save = current.remoteAreas.singleWhere((a) => a.local.id == 'save');
    final base = save.remote.substring(0, save.remote.length - '/saves'.length);
    final config = r['rootConfigPath'] ?? current.launch['configPath'];
    if (config is! String ||
        !RegExp('^${RegExp.escape(base)}/config-[a-f0-9]{32}\\.cfg\$')
            .hasMatch(config))
      throw const FormatException(
        'Invalid rooted configuration recovery path.',
      );
    final localBase = save.local.path.substring(
      0,
      save.local.path.length - '/saves'.length,
    );
    final stateTemplate = current.areas.singleWhere(
      (a) => a.id.startsWith('states-'),
    );
    final state = group == null
        ? null
        : ProgressArea(
            group as String,
            '$localBase/$group',
            prefix: stateTemplate.prefix,
            pattern: stateTemplate.pattern,
          );
    final plan = AndroidSavePlan(
      ProgressLayout(current.root, current.format, current.game, [
        save.local,
        if (state != null) state,
      ], rawSave: current.rawSave),
      current.emulator,
      current.binding,
      [save, if (state != null) AndroidSaveArea(state, '$base/states/$group')],
      launch: {
        ...current.launch,
        'configPath': config,
        'configNative': '${current.binding['dataDir']}/$config',
        if (current.launch['coreName'] == 'mednafen_lynx')
          'lynxFirmwarePath': _lynxFirmwarePath(config),
        if (group != null) 'stateGroup': group as String,
      },
      operaOptions: current.operaOptions,
      saturnOptions: current.saturnOptions,
      flycastOptions: current.flycastOptions,
      flycastNativeOptions: current.flycastNativeOptions,
    );
    await record(game, plan);
    return plan;
  }

  Future<void> configure(Map<String, dynamic> r, AndroidSavePlan plan) async {
    for (final name in ['config', 'options']) {
      final path = plan.launch['${name}Path'],
          text = plan.launch['${name}Text'];
      if (path == null || text == null) continue;
      final source = await progressFile(
        directory(r),
        'configuration/$name',
        createParents: true,
      );
      await source.writeAsString(text, flush: true);
      final after = await progressFileHash(source);
      if (plan.rooted) {
        if (path != r['rootConfigPath'])
          throw const FormatException('Invalid rooted session configuration.');
        r['configuration'] = {path: after};
        // Retain the exact owned bytes before publication, including when the
        // native write succeeds but its reply or the next checkpoint is lost.
        await progressWrite(journal, r);
      }
      await manager.channel.invokeMethod<void>(plan.method('Replace'), {
        ...plan.arguments,
        'path': path,
        if (plan.launch['stateGroup'] case final group?) 'stateGroup': group,
        'before': null,
        'after': after,
        'source': source.path,
        'token': '${r['transaction']}-in',
      });
    }
  }

  Future<String> stageRootRom(CloudGame game, AndroidSavePlan plan) async {
    final r = await record(game, plan);
    var source = File(r['selected'] as String);
    var name = source.uri.pathSegments.last;
    progressRelative(name);
    final extensions = _rootRomExtensions(plan);
    final extension = name.split('.').last.toLowerCase();
    if ((!extensions.contains(extension) && extension != 'zip') ||
        extensions.isEmpty ||
        !plan.rooted ||
        r['phase'] != 'installed')
      throw StateError(
        'Rooted RetroArch requires one supported cartridge, uncompressed or in a ZIP.',
      );
    Directory? extraction;
    String? checkedRomHash;
    try {
      if (plan.launch['coreName'] == 'flycast') {
        final disc = plan.flycastDisc;
        if (disc == null ||
            disc.file.path != source.path ||
            await source.length() != disc.bytes)
          throw StateError(
            'The verified Dreamcast disc changed before staging. Recovery was kept.',
          );
        checkedRomHash = disc.sha256;
      } else if (plan.launch['coreName'] == 'mednafen_saturn') {
        final disc = plan.saturnDisc;
        if (disc == null ||
            disc.file.path != source.path ||
            await source.length() != disc.bytes)
          throw StateError(
            'The verified Saturn disc changed before staging. Recovery was kept.',
          );
        checkedRomHash = disc.sha256;
      } else if (plan.launch['coreName'] == 'opera') {
        final disc = plan.operaDisc;
        if (disc == null ||
            disc.file.path != source.path ||
            await source.length() != disc.bytes)
          throw StateError(
            'The verified 3DO disc changed before staging. Recovery was kept.',
          );
        checkedRomHash = disc.sha256;
      } else if (plan.launch['coreName'] == 'fbneo') {
        // The core consumes the complete multi-chip ROMset. Broomm validates
        // ZIP structure and bounds without extracting or renaming its chips.
        phase?.call('Checking the complete FBNeo ROMset…');
        checkedRomHash = await progressFileHash(source);
        final zip = await ProgressZip.read(
          source,
          maxBytes: _rootRomLimit(plan) * 4,
          maxEntryBytes: _rootRomLimit(plan),
        );
        if (zip.entries.isEmpty)
          throw const FormatException('The FBNeo ROMset is empty.');
        phase?.call('Verifying the FBNeo ROMset…');
        if (await progressFileHash(source) != checkedRomHash)
          throw StateError(
            'The FBNeo ROMset changed during inspection. Existing progress was kept. Try again.',
          );
      } else if (extension == 'zip') {
        phase?.call('Checking and extracting the cartridge…');
        final before = await progressFileHash(source);
        final zip = await ProgressZip.read(
          source,
          maxBytes: _rootRomLimit(plan) * 2,
          maxEntryBytes: _rootRomLimit(plan),
        );
        final cartridges = zip.entries
            .where(
              (e) => extensions.contains(e.name.split('.').last.toLowerCase()),
            )
            .toList();
        if (cartridges.length != 1)
          throw StateError(
            'The ZIP must contain exactly one supported cartridge.',
          );
        extraction = await directory(r).createTemp('cartridge-');
        final contents = Directory('${extraction.path}/contents');
        await zip.extract(contents);
        if (await progressFileHash(source) != before)
          throw StateError(
            'The game archive changed during extraction. Try again.',
          );
        final cartridge = cartridges.single;
        source = await progressFile(contents, cartridge.name);
        final rawExtension = cartridge.name.split('.').last.toLowerCase();
        // Keep the original archive's save/state stem, independently of its
        // internal filename. Existing profile and desktop progress still match.
        name = '${retroStateStem(r['selected'] as String)}.$rawExtension';
        progressRelative(name);
        source = await source.rename(
          (await progressFile(extraction, name)).path,
        );
        r['romStageExtension'] = rawExtension;
      }
      final config = plan.launch['configPath']!;
      final parent = config.substring(0, config.lastIndexOf('/'));
      final path = '$parent/rom-${r['transaction']}/$name';
      final bytes = await source.length();
      if (bytes < 1 || bytes > _rootRomLimit(plan))
        throw StateError(
          'The RetroArch game file must be between 1 byte and ${_rootRomLimit(plan) ~/ (1024 * 1024)} MiB.',
        );
      final hash = checkedRomHash ?? await progressFileHash(source);
      r['romStage'] = path;
      r['romStageSha256'] = hash;
      await progressWrite(journal, r);
      return (await manager.channel.invokeMethod<String>('rootStageRom', {
        ...plan.arguments,
        'path': path,
        'source': source.path,
        'sha256': hash,
        if (extraction != null) 'preparedCartridge': true,
      }))!;
    } finally {
      // Native staging has finished (or failed) before its private source goes.
      // The durable native path/hash already covers a lost staging reply.
      await extraction?.delete(recursive: true);
    }
  }

  Future<void> apply(
    Map<String, dynamic> r,
    AndroidSavePlan plan,
    String beforeKey,
    String afterKey,
    String source,
  ) async {
    final before = inventory(r[beforeKey], plan),
        after = inventory(r[afterKey], plan),
        paths = {...before.keys, ...after.keys}.toList()..sort();
    for (final path in paths) {
      final file = after[path] == null
          ? null
          : await progressFile(directory(r), '$source/$path');
      if (file != null && await progressFileHash(file) != after[path]['sha256'])
        throw StateError(
          'Android recovery copy is damaged. Native files were kept.',
        );
      await manager.channel.invokeMethod<void>(plan.method('Replace'), {
        ...plan.arguments,
        'path': path,
        'before': before[path]?['sha256'],
        'after': after[path]?['sha256'],
        'source': file?.path,
        if (plan.rooted) 'metadata': after[path]?['metadata'],
        'token': '${r['transaction']}-${afterKey == 'working' ? 'in' : 'out'}',
      });
    }
    if (!same(await list(plan), after))
      throw StateError(
        'Emulator files changed during replacement. Recovery copies were kept.',
      );
  }

  Future<bool> capture(
    CloudGame game,
    CloudSaves cloud,
    AndroidSavePlan plan,
  ) async {
    final r = await record(game, plan);
    if (r['phase'] == 'restoring' || r['phase'] == 'restored') return false;
    if (r['phase'] == 'installing') {
      await apply(r, plan, 'original', 'working', 'working');
      r.addAll({
        'captured': r['working'],
        'capture': 'working',
        'phase': 'restoring',
      });
      await progressWrite(journal, r);
      return false;
    }
    final files = await list(plan), capture = 'captures/${progressNonce()}';
    // Flycast validates its native legacy-card renames after holding all new
    // game/resource bytes. Other cores still require every installed path.
    if (plan.rooted &&
        plan.launch['coreName'] != 'flycast' &&
        (r['working'] as Map).keys.any((path) => !files.containsKey(path)))
      throw StateError(
        'An installed RetroArch save or state is missing. Recovery copies were kept; restore the working file before syncing.',
      );
    if (files.isEmpty)
      cloud.notice(
        'No save files were found in ${plan.emulator.name}’s connected folder. If you saved in-game, check its folder and memory-card settings.',
        false,
      );
    await read(r, plan, files, '$capture/native');
    final flycast = _flycastResources(r, plan);
    if (flycast != null) {
      // Hold new game progress before inspecting mandatory console/VMU modes.
      // A failed auxiliary check must not leave the only new copy in RetroArch.
      r['rootFlycastHeldProgress'] = {
        'directory': '$capture/native',
        'files': files,
      };
      await progressWrite(journal, r);
      await flycast.capture(
        r,
        journal,
        (message) => cloud.notice(message, false),
      );
    }
    final canonical = Directory('${directory(r).path}/$capture/profile');
    final layout = ProgressLayout(
      canonical.path,
      game.layout.format,
      game.layout.game,
      game.layout.areas,
      rawSave: game.layout.rawSave,
    );
    for (final e in files.entries) {
      final key = plan.localKey(e.key)!;
      if (!game.layout.areas.any((a) => key.startsWith('${a.id}/')))
        continue; // Changed-build states stay in retained native capture.
      await copy(
        await progressFile(directory(r), '$capture/native/${e.key}'),
        await layout.target(key),
        e.value as Map,
      );
    }
    final store = cloud.store(game);
    await store.recover();
    final snapshot = await ProgressStore(
      store.directory,
      layout,
      game.rom,
      game.user,
      ownerRoot: manager.data,
    ).capture();
    await store.restore(snapshot, await store.state());
    r.addAll({
      'captured': files,
      'capture': '$capture/native',
      'phase': 'captured',
    });
    await progressWrite(journal, r);
    return true;
  }

  Future<void> restoreOriginal(CloudGame game, AndroidSavePlan plan) async {
    final r = await record(game, plan);
    if (r['phase'] == 'captured') {
      if (!same(await list(plan), inventory(r['captured'], plan)))
        throw StateError(
          'The emulator wrote more progress after capture. Close it and finish again.',
        );
      r['phase'] = 'restoring';
      await progressWrite(journal, r);
    }
    if (r['phase'] == 'restoring') {
      await apply(r, plan, 'captured', 'original', 'original');
      r['phase'] = 'restored';
      await progressWrite(journal, r);
    }
    if (r['phase'] != 'restored')
      throw StateError('Capture progress before restoring standalone saves.');
    if (r['romStage'] case final String path when plan.rooted) {
      final config = plan.launch['configPath']!;
      final parent = config.substring(0, config.lastIndexOf('/'));
      final selected = r['selected'] as String;
      var name = File(selected).uri.pathSegments.last;
      if (r['romStageExtension'] case final Object extension) {
        if (!name.toLowerCase().endsWith('.zip') ||
            extension is! String ||
            !_rootRomExtensions(plan).contains(extension))
          throw const FormatException(
            'Rooted cartridge staging identity changed.',
          );
        name = '${retroStateStem(selected)}.$extension';
      }
      final hash = r['romStageSha256'];
      if (path != '$parent/rom-${r['transaction']}/$name' ||
          hash is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))
        throw const FormatException(
          'Rooted cartridge staging identity changed.',
        );
      await manager.channel.invokeMethod<void>('rootRemoveRom', {
        ...plan.arguments,
        'path': path,
        'sha256': hash,
      });
    }
    if (plan.rooted && r['configuration'] != null) {
      final configuration = r['configuration'];
      if (configuration is! Map ||
          configuration.length != 1 ||
          configuration.entries.any(
            (e) =>
                e.key != r['rootConfigPath'] ||
                e.key != plan.launch['configPath'] ||
                e.value is! String ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(e.value as String),
          ))
        throw const FormatException('Invalid rooted configuration cleanup.');
      for (final e in configuration.entries) {
        await manager.channel.invokeMethod<void>(plan.method('Replace'), {
          ...plan.arguments,
          'path': e.key,
          'before': e.value,
          'after': null,
          'token': '${r['transaction']}-out',
        });
      }
    }
    final firmware = _lynxFirmware(r, plan);
    if (firmware != null) {
      await manager.channel.invokeMethod<void>('rootLynxFirmware', {
        ...plan.arguments,
        'path': firmware['path'],
        'configPath': plan.launch['configPath'],
        'before': firmware['sha256'],
        'after': null,
        'token': '${r['transaction']}-out',
      });
    }
    for (final entry in _operaFirmware(r, plan).entries) {
      await manager.channel.invokeMethod<void>('rootOperaFirmware', {
        ...plan.arguments,
        'path': entry.value['path'],
        'configPath': plan.launch['configPath'],
        'before': entry.value['sha256'],
        'after': null,
        'token': '${r['transaction']}-out',
      });
    }
    for (final entry in _saturnFirmware(r, plan).entries) {
      await manager.channel.invokeMethod<void>('rootSaturnFirmware', {
        ...plan.arguments,
        'path': entry.value['path'],
        'configPath': plan.launch['configPath'],
        'before': entry.value['sha256'],
        'after': null,
        'token': '${r['transaction']}-out',
      });
    }
    await _flycastResources(r, plan)?.cleanup(r);
    await progressWrite(await progressFile(directory(r), 'completed.json'), r);
    await journal.delete();
  }

  Future<void> keepFolder(String server, String profile, int rom) async {
    final r = await progressJson(journal);
    if (r['server'] != server ||
        r['profile'] != profile ||
        r['rom'] != rom ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(r['transaction'] as String? ?? ''))
      throw const FormatException('Android recovery identity changed');
    await progressWrite(
      await progressFile(directory(r), 'kept-shared-folder.json'),
      {
        ...r,
        'resolution': 'user-kept-folder',
        'resolved': DateTime.now().toUtc().toIso8601String(),
      },
    );
    await journal.delete();
  }
}

String _lynxFirmwarePath(String config) {
  final match = RegExp(
    r'^(files/Broomm/[a-f0-9]{32}/[1-9][0-9]*)/config-([a-f0-9]{32})\.cfg$',
  ).firstMatch(config);
  if (match == null)
    throw const FormatException('Invalid Lynx firmware session configuration.');
  return '${match[1]}/system-${match[2]}/lynxboot.img';
}

String _operaSystemDirectory(String config) {
  final match = RegExp(
    r'^(files/Broomm/[a-f0-9]{32}/[a-zA-Z0-9_-]{1,128})/config-([a-f0-9]{32})\.cfg$',
  ).firstMatch(config);
  if (match == null)
    throw const FormatException(
      'Invalid Opera firmware session configuration.',
    );
  return '${match[1]}/system-${match[2]}';
}

Set<String> _rootRomExtensions(AndroidSavePlan plan) =>
    switch (plan.binding['access']) {
      'root-gba-v1' => {'gba'},
      'root-snes-v1' => {'sfc', 'smc'},
      'root-gameboy-v1' => {'gb', 'gbc', 'dmg'},
      'root-cartridge-v1' => switch (plan.launch['platform']) {
        '3do' => {'chd', 'iso', 'bin'},
        'saturn' => {'chd'},
        'dc' => {'chd'},
        'atari2600' => {'a26', 'bin'},
        'tg16' => {'pce'},
        'genesis' => {'md', 'gen', 'smd', 'bin'},
        'sms' => {'sms', 'sg'},
        'gamegear' => {'gg'},
        'sega32' => {'32x', 'bin', 'gen', 'smd', 'md'},
        'n64' => {'z64', 'v64', 'n64'},
        'nes' => {'nes', 'unf', 'unif'},
        'jaguar' => {'j64', 'jag', 'rom', 'abs', 'cof', 'bin', 'prg'},
        'lynx' => {'lnx', 'lyx', 'bll', 'o'},
        'arcade' => {'zip'},
        _ => {},
      },
      _ => {},
    };

int _rootRomLimit(AndroidSavePlan plan) =>
    (switch (plan.launch['platform']) {
      '3do' || 'saturn' => 1024,
      'dc' => 2048,
      'arcade' => 128,
      'n64' => 64,
      _ => 32,
    }) *
    1024 *
    1024;

int _rootProgressLimit(AndroidSavePlan plan, String path) {
  if (plan.launch['coreName'] == 'flycast')
    return path.contains('/states/') ? 64 * 1024 * 1024 : 131072;
  if (plan.launch['coreName'] == 'mednafen_saturn' && path.contains('/saves/'))
    return path.endsWith('.smpc')
        ? 12
        : path.endsWith('.4mb.bcr')
        ? 4 * 1024 * 1024
        : path.endsWith('.bcr')
        ? 512 * 1024
        : 32768;
  if (plan.launch['coreName'] == 'opera' && path.contains('/saves/'))
    return 32768;
  final n64 = plan.launch['coreName'] == 'mupen64plus_next';
  if (path.contains('/states/')) return (n64 ? 32 : 16) * 1024 * 1024;
  return n64 ? 296960 : 262144;
}
