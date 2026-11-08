import 'dart:convert';
import 'dart:io';

import '../progress/digest.dart';
import '../progress/files.dart';
import 'emulators.dart';
import 'flycast.dart';
import 'save_plan.dart';

/// Transaction-bound Dreamcast firmware, console identity and local preferences.
/// Session supervision supplies the lease and closure evidence; this class owns
/// no launch, account selection or cloud save decisions.
class AndroidFlycastSessionResources {
  AndroidFlycastSessionResources(this.manager, this.plan);
  final AndroidEmulators manager;
  final AndroidSavePlan plan;
  String get config {
    final value = plan.launch['configPath'];
    if (value == null ||
        !RegExp(
          r'^files/Broomm/[a-f0-9]{32}/[1-9][0-9]*/config-[a-f0-9]{32}\.cfg$',
        ).hasMatch(value)) {
      throw const FormatException('Invalid Dreamcast resource configuration.');
    }
    return value;
  }

  String get nonce => config.split('/').last.substring(7, 39);
  String get base => config.substring(0, config.lastIndexOf('/'));
  String get options => '$base/options-$nonce.opt';
  String get system => '$base/system-$nonce/dc';
  String get bios => '$system/dc_boot.bin';
  String get console => '$system/dc_nvmem.bin';
  Set<String> get fallbacks => {
    for (final p in ['A', 'B', 'C', 'D'])
      for (final s in [1, 2]) '$system/vmu_save_$p$s.bin',
  };
  int limit(String path) => path == options
      ? 262144
      : path == bios
      ? 2097152
      : path == console || fallbacks.contains(path)
      ? 131072
      : throw const FormatException('Foreign Flycast resource path.');
  Directory directory(Map r) => Directory(
    '${manager.data.path}/android/shared-session/${r['transaction']}',
  );

  Map<String, dynamic> validate(Map r) {
    if (!r.containsKey('rootFlycastConsoleBefore') ||
        r['rootFirmware'] != null ||
        r['rootOperaFirmware'] != null ||
        r['rootSaturnFirmware'] != null ||
        !plan.rooted ||
        plan.launch['coreName'] != 'flycast' ||
        plan.launch['platform'] != 'dc' ||
        r['version'] != 5 ||
        r['coreName'] != 'flycast' ||
        r['rootPlatform'] != 'dc' ||
        r['rootConfigPath'] != config ||
        !config.startsWith('files/Broomm/${r['profile']}/${r['rom']}/') ||
        !RegExp(
          r'^files/Broomm/[a-f0-9]{32}/[1-9][0-9]*/config-[a-f0-9]{32}\.cfg$',
        ).hasMatch(config) ||
        r['transaction'] != nonce) {
      throw const FormatException(
        'Dreamcast resource recovery identity changed. All copies were kept.',
      );
    }
    final resources = r['rootFlycastResources'],
        before = r['rootFlycastConsoleBefore'];
    if (before != null &&
        (before is! Map ||
            before.length != 3 ||
            before['bytes'] != 131072 ||
            !RegExp(r'^[a-f0-9]{32}$')
                .hasMatch(before['object'] as String? ?? '') ||
            !RegExp(r'^[a-f0-9]{64}$')
                .hasMatch(before['sha256'] as String? ?? ''))) {
      throw const FormatException(
        'Invalid previous Dreamcast console identity.',
      );
    }
    // Earlier v5 records always supplied a boot ROM. An explicit new marker
    // distinguishes native HLE from a damaged record missing its known BIOS.
    final boot = r['rootFlycastBoot'] ?? 'rom';
    if (boot != 'rom' && boot != 'hle-fallback')
      throw const FormatException('Invalid Dreamcast boot resource mode.');
    final keys = {
      options,
      if (boot == 'rom') bios,
      if (before != null) console,
    };
    if (resources is! Map ||
        resources.length != keys.length ||
        !resources.keys.toSet().containsAll(keys)) {
      throw const FormatException('Dreamcast resource recovery is incomplete.');
    }
    for (final e in resources.entries) {
      final m = e.value;
      if (m is! Map ||
          m.length != 2 ||
          m['bytes'] is! int ||
          m['bytes'] < 0 ||
          m['bytes'] > limit(e.key) ||
          e.key != options && m['bytes'] != limit(e.key) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(m['sha256'] as String? ?? '') ||
          e.key == console && m['sha256'] != before['sha256']) {
        throw const FormatException('Invalid Dreamcast recovery resource.');
      }
    }
    if (r['rootFlycastCapture'] case final Object captured) {
      if (captured is! Map ||
          captured.length != 2 ||
          !RegExp(r'^[a-f0-9]{32}$')
              .hasMatch(captured['directory'] as String? ?? '')) {
        throw const FormatException('Invalid Dreamcast resource capture.');
      }
      inventory(captured['files']);
    }
    return resources.cast<String, dynamic>();
  }

  Map<String, dynamic> inventory(Object? value) {
    if (value is! Map || value.length > 11)
      throw const FormatException('Invalid Dreamcast resource inventory.');
    final files = value.cast<String, dynamic>();
    for (final e in files.entries) {
      final max = limit(e.key), m = e.value;
      if (m is! Map ||
          m.length != 3 ||
          m['bytes'] is! int ||
          m['bytes'] < 0 ||
          m['bytes'] > max ||
          e.key != options && m['bytes'] != max ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(m['sha256'] as String? ?? '') ||
          !RegExp(
            '^${plan.binding['uid']} [0-9]+ [0-7]{3} ${RegExp.escape(plan.binding['label']!)}\$',
          ).hasMatch(m['metadata'] as String? ?? '')) {
        throw const FormatException(
          'Dreamcast resource metadata changed. Recovery was kept.',
        );
      }
    }
    return files;
  }

  Future<Map<String, dynamic>> list() async => inventory(
    await manager.channel.invokeMapMethod<String, dynamic>('rootFlycastList', {
      ...plan.arguments,
      'configPath': config,
    }),
  );
  bool same(Map a, Map b) =>
      a.length == b.length &&
      a.keys.every(
        (k) =>
            b[k] is Map &&
            a[k]['sha256'] == b[k]['sha256'] &&
            a[k]['bytes'] == b[k]['bytes'] &&
            a[k]['metadata'] == b[k]['metadata'],
      );

  Future<void> checkedCopy(File source, File target, Map m) async {
    await target.create(exclusive: true);
    final out = await target.open(mode: FileMode.writeOnly);
    try {
      var count = 0;
      await for (final bytes in source.openRead()) {
        count += bytes.length;
        if (count > m['bytes'])
          throw StateError('A Dreamcast recovery source grew during copy.');
        await out.writeFrom(bytes);
      }
      await out.flush();
    } finally {
      await out.close();
    }
    if (await target.length() != m['bytes'] ||
        await progressFileHash(target) != m['sha256'] ||
        await progressFileHash(source) != m['sha256']) {
      throw StateError('A Dreamcast recovery copy changed.');
    }
  }

  Future<void> stage(Map<String, dynamic> r) async {
    final images = plan.flycastResources;
    if (images == null ||
        images.length > 1 ||
        images.isNotEmpty && images.single.name != 'dc_boot.bin') {
      throw StateError('Prepare the Dreamcast boot resources before Play.');
    }
    final prior = plan.flycastConsole;
    final current = await readAndroidFlycastConsole(Directory(plan.root));
    if (current?.object != prior?.object || current?.sha256 != prior?.sha256) {
      throw StateError(
        'The Dreamcast console identity changed during preparation. Try Play again.',
      );
    }
    r['rootFlycastConsoleBefore'] = prior?.record;
    r['rootFlycastBoot'] = images.isEmpty ? 'hle-fallback' : 'rom';
    final text = utf8.encode(androidFlycastOptionsText(plan.flycastOptions));
    final optionFile = await progressFile(
      directory(r),
      'flycast-incoming/options.opt',
      createParents: true,
    );
    await optionFile.create(exclusive: true);
    await optionFile.writeAsBytes(text, flush: true);
    final records = <String, dynamic>{
      options: {
        'bytes': text.length,
        'sha256': await progressFileHash(optionFile),
      },
      if (images.isNotEmpty)
        bios: {'bytes': images.single.bytes, 'sha256': images.single.sha256},
      if (prior != null) console: {'bytes': 131072, 'sha256': prior.sha256},
    };
    r['rootFlycastResources'] = records;
    validate(r);
    if (images.isNotEmpty)
      await checkedCopy(
        images.single.file,
        await progressFile(directory(r), 'flycast-incoming/dc_boot.bin'),
        records[bios],
      );
    if (prior != null)
      await checkedCopy(
        prior.file,
        await progressFile(directory(r), 'flycast-incoming/dc_nvmem.bin'),
        records[console],
      );
  }

  Future<void> install(Map r) async {
    for (final e in validate(r).entries) {
      final name = e.key == options ? 'options.opt' : e.key.split('/').last;
      final source = await progressFile(directory(r), 'flycast-incoming/$name');
      if (await source.length() != e.value['bytes'] ||
          await progressFileHash(source) != e.value['sha256']) {
        throw StateError(
          'Dreamcast resource staging changed. Recovery was kept.',
        );
      }
      await manager.channel.invokeMethod<void>('rootFlycastReplace', {
        ...plan.arguments,
        'path': e.key,
        'configPath': config,
        'before': null,
        'after': e.value['sha256'],
        'source': source.path,
        'token': '${r['transaction']}-in',
      });
    }
    final actual = await list(), expected = validate(r);
    if (actual.length != expected.length ||
        expected.keys.any(
          (k) =>
              actual[k]?['sha256'] != expected[k]['sha256'] ||
              actual[k]?['bytes'] != expected[k]['bytes'],
        )) {
      throw StateError(
        'Dreamcast resource installation could not be confirmed.',
      );
    }
  }

  Future<void> capture(
    Map<String, dynamic> r,
    File journal,
    void Function(String) warning,
  ) async {
    final expected = validate(r),
        files = await list(),
        capture = progressNonce();
    // Quarantine every known mutable/fallback resource before interpreting modes.
    // A mode change cannot lose VMUs simply because normal selectors exclude them.
    for (final e in files.entries) {
      final target = await progressFile(
        directory(r),
        'flycast-captures/$capture/${e.key == options ? 'options.opt' : e.key.split('/').last}',
        createParents: true,
      );
      await manager.channel.invokeMethod<void>('rootFlycastRead', {
        ...plan.arguments,
        'path': e.key,
        'configPath': config,
        'target': target.path,
        ...e.value as Map,
      });
      if (await target.length() != e.value['bytes'] ||
          await progressFileHash(target) != e.value['sha256'])
        throw StateError('Dreamcast resource capture failed verification.');
    }
    if (!same(files, await list()))
      throw StateError('Dreamcast resources changed during capture.');
    r['rootFlycastCapture'] = {'directory': capture, 'files': files};
    await progressWrite(journal, r);
    if (files[bios]?['sha256'] != expected[bios]?['sha256'] ||
        !files.containsKey(console) ||
        !files.containsKey(options)) {
      throw StateError(
        'Dreamcast BIOS, console flash or session options are missing or changed. Recovery copies were kept.',
      );
    }
    if (fallbacks.any(files.containsKey)) {
      throw StateError(
        'Flycast changed VMU storage during play. Game progress and fallback VMUs were kept in private recovery. Finish without changing the emulator folder to retain these copies for manual recovery.',
      );
    }
    final optionFile = await progressFile(
      directory(r),
      'flycast-captures/$capture/options.opt',
    );
    final actual = parseAndroidFlycastOptions(await optionFile.readAsBytes());
    if (androidFlycastRequiredOptions.entries.any(
      (e) => actual[e.key] != e.value,
    )) {
      throw StateError(
        'Flycast changed its VMU storage options during play. All game and resource copies were kept in private recovery. Finish without changing the emulator folder to retain them for manual recovery.',
      );
    }
    validateAndroidFlycastWorkingProgress(
      r['selected'] as String,
      (r['working'] as Map).cast<String, dynamic>(),
      ((r['rootFlycastHeldProgress'] as Map)['files'] as Map)
          .cast<String, dynamic>(),
    );
    await publishAndroidFlycastConsole(
      Directory(plan.root),
      (r['rootFlycastConsoleBefore'] as Map?)?.cast<String, dynamic>(),
      await progressFile(
        directory(r),
        'flycast-captures/$capture/dc_nvmem.bin',
      ),
      files[console]['sha256'],
    );
    try {
      await writeAndroidFlycastPreferences(
        Directory(plan.root),
        plan.game,
        actual,
      );
    } catch (_) {
      warning(
        'Flycast core preferences could not be saved. Game progress remains available for synchronization.',
      );
    }
  }

  Future<void> cleanup(Map r) async {
    final original = validate(r), captured = r['rootFlycastCapture'] as Map?;
    final expected = captured == null ? original : inventory(captured['files']);
    if (fallbacks.any(expected.containsKey))
      throw StateError('Fallback Dreamcast VMUs still require recovery.');
    if (captured != null) {
      if (!expected.keys.toSet().containsAll({options, console}) ||
          expected[bios]?['sha256'] != original[bios]?['sha256']) {
        throw StateError(
          'Dreamcast resource capture is incomplete. Recovery was kept.',
        );
      }
      final saved = await readAndroidFlycastConsole(Directory(plan.root));
      if (saved?.sha256 != expected[console]?['sha256'])
        throw StateError(
          'Keep the captured Dreamcast console identity before native cleanup.',
        );
    }
    final native = await list();
    if (native.keys.any(
      (k) =>
          expected[k] == null ||
          native[k]['sha256'] != expected[k]['sha256'] ||
          native[k]['bytes'] != expected[k]['bytes'],
    )) {
      throw StateError(
        'Dreamcast resources changed after capture. Native copies were kept.',
      );
    }
    for (final path in [bios, options, console]) {
      if (expected[path] == null) continue;
      await manager.channel.invokeMethod<void>('rootFlycastReplace', {
        ...plan.arguments,
        'path': path,
        'configPath': config,
        'before': expected[path]['sha256'],
        'after': null,
        'token': '${r['transaction']}-out',
      });
    }
  }
}
