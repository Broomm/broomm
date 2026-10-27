import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/progress/digest.dart';
import 'package:broomm/src/progress/zip.dart';
import 'package:broomm/src/updates/controller.dart';
import 'package:broomm/src/updates/helpers.dart';
import 'package:broomm/src/updates/installation.dart';
import 'package:broomm/src/updates/releases.dart';
import 'package:broomm/src/updates/transport.dart';
import 'package:broomm/src/shell/model.dart';
import 'package:broomm/src/shell/storage.dart';

import 'download_queue_test.dart' show QueuedRomm, queuedFixture;
import 'remembered_signin_test.dart' show MemoryCredentials;
import 'shell_model_test.dart' show settleModel;

Map<String, dynamic> updateRelease(
  String version, {
  String target = 'windows-x64',
  bool draft = false,
}) {
  final name = updatePackage(version, target);
  return {
    'tag_name': 'v$version',
    'draft': draft,
    'prerelease': version.contains('-rc'),
    'assets': [
      for (final n in [name, '$name.sha256', 'Broomm-$version-$target.json'])
        {
          'name': n,
          'state': 'uploaded',
          'size': 10,
          'browser_download_url':
              'https://github.com/$broommRepository/releases/download/v$version/$n',
        },
    ],
  };
}

class MemoryUpdateTransport extends UpdateTransport {
  final responses = <String, List<int>>{};
  bool corrupt = false;
  @override
  Future<List<int>> bytes(
    Uri uri, {
    required int limit,
    bool api = false,
    bool missing = false,
  }) async => responses[uri.pathSegments.last]!;
  @override
  Future<void> download(
    ReleaseAsset asset,
    File destination,
    void Function(double) progress,
  ) async {
    check();
    await destination.writeAsBytes(
      corrupt ? [1, 2, 3] : responses[asset.name]!,
    );
    progress(1);
  }
}

class HandoffFixture extends PreparedAppUpdate {
  HandoffFixture(super.stage, super.location, super.lease, this.starting);
  final Future<bool> Function() starting;
  bool started = false, committed = false;
  @override
  Future<bool> start() {
    started = true;
    return starting();
  }

  @override
  Future<void> commit() async {
    committed = true;
    await super.commit();
  }
}

class PreparedFixtureInstaller extends ApplicationInstaller {
  PreparedFixtureInstaller(this.fixture);
  final PreparedAppUpdate fixture;
  @override
  Future<PreparedAppUpdate> prepare(
    AppUpdate update,
    Directory data,
    void Function(String, double?) progress,
  ) async => fixture;
}

Future<(AppUpdate, MemoryUpdateTransport, Directory)> updateFixture(
  Directory root,
) async {
  final target = await Directory('${root.path}/installation with spaces')
      .create();
  final payload = await Directory('${root.path}/source').create();
  Future<void> bundle(Directory dir, String version) async {
    await File('${dir.path}/broomm.exe')
        .writeAsString('private fixture $version');
    await File('${dir.path}/flutter_windows.dll').writeAsString('fixture');
    await Directory('${dir.path}/data').create();
    await File('${dir.path}/broomm-release.json').writeAsString(
      jsonEncode({
        'product': 'Broomm',
        'target': 'windows-x64',
        'version': version,
        'sha': 'a' * 40,
        'entries': [
          'broomm.exe',
          'flutter_windows.dll',
          'data',
          'broomm-release.json',
        ],
      }),
    );
  }

  await bundle(target, '0.1.0');
  await bundle(payload, '0.1.1');
  final zip = File('${root.path}/fixture.zip');
  await ProgressZip.write(zip, payload, [
    'broomm.exe',
    'flutter_windows.dll',
    'broomm-release.json',
  ]);
  // ZIP contains explicit data files so the bundle's required directory exists.
  await File('${payload.path}/data/fixture').writeAsString('asset');
  await zip.delete();
  await ProgressZip.write(zip, payload, [
    'broomm.exe',
    'flutter_windows.dll',
    'broomm-release.json',
    'data/fixture',
  ]);
  final release = updateRelease('0.1.1');
  (release['assets'] as List).first['size'] = await zip.length();
  final update = selectUpdate([release], '0.1.0', false, 'windows-x64')!;
  final transport = MemoryUpdateTransport();
  final hash = await progressFileHash(zip);
  transport.responses.addAll({
    update.package.name: await zip.readAsBytes(),
    update.checksum.name: utf8.encode('$hash  ${update.package.name}\n'),
    update.record.name: utf8.encode(
      jsonEncode({
        'schema_version': 1,
        'product': 'Broomm',
        'target': 'windows-x64',
        'version': '0.1.1',
        'sha256': hash,
        'sha': 'a' * 40,
        'bytes': await zip.length(),
      }),
    ),
  });
  return (update, transport, target);
}

Future<void> waitFor(File file) async {
  final until = DateTime.now().add(const Duration(seconds: 8));
  while (!await file.exists()) {
    if (DateTime.now().isAfter(until))
      fail('Expected fixture checkpoint was not reached: ${file.path}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  for (final early in [true, false]) {
    test(early ? 'cancellation before OS handoff prevents installer startup' : 'OS handoff fences cancellation and rejected exit disarms the committed helper', () async {
      final root = await Directory.systemTemp.createTemp(
        'broomm-update-handoff-',
      );
      final quiet = Completer<void>(),
          releaseQuiet = Completer<void>(),
          started = Completer<void>(),
          releaseStart = Completer<void>();
      final stage = await Directory('${root.path}/stage').create();
      final original = await File('${root.path}/application')
          .writeAsString('keep');
      final fixture = HandoffFixture(
        stage,
        UpdateLocation(root, 'windows'),
        await UpdateLease.acquire(root),
        () async {
          started.complete();
          await releaseStart.future;
          return true;
        },
      );
      final installer = PreparedFixtureInstaller(fixture);
      final updates = ApplicationUpdates(
        current: '0.1.0',
        target: 'windows-x64',
        installer: () => installer,
      );
      updates.available = selectUpdate(
        [updateRelease('0.1.1')],
        '0.1.0',
        false,
        'windows-x64',
      );
      var exitCalled = false;
      final work = updates.install(
        root,
        quiesce: () async {
          quiet.complete();
          if (early) await releaseQuiet.future;
        },
        exit: () async {
          exitCalled = true;
          throw StateError('Controlled OS exit refusal');
        },
      );
      try {
        if (early) {
          await quiet.future;
          updates.cancel();
          releaseQuiet.complete();
        } else {
          await started.future;
          expect(updates.handedOff, isTrue);
          updates.cancel();
          expect(installer.transport.cancelled, isFalse);
          releaseStart.complete();
        }
        await work;
        expect(fixture.started, !early);
        expect(fixture.committed, !early);
        expect(exitCalled, !early);
        expect(updates.handedOff, isFalse);
        expect(updates.busy, isFalse);
        if (!early) {
          expect(await File('${stage.path}/cancel').exists(), isTrue);
          expect(await File('${stage.path}/commit').exists(), isFalse);
        }
        expect(await original.readAsString(), 'keep');
      } finally {
        if (!releaseQuiet.isCompleted) releaseQuiet.complete();
        if (!releaseStart.isCompleted) releaseStart.complete();
        await work;
        updates.dispose();
        await root.delete(recursive: true);
      }
    });
  }

  test('update shutdown refuses a failed queue checkpoint and keeps ownership until a successful retry', () async {
    final root = await Directory.systemTemp.createTemp('broomm-update-queue-');
    late QueuedRomm api;
    final model = ShellModel(
      ShellStorage(root),
      credentials: MemoryCredentials(),
      clientFactory: (uri) => api = QueuedRomm(uri),
    );
    try {
      await model.start();
      await model.addServer('https://queue.example');
      await model.login('Player', 'fixture');
      await settleModel(model);
      final progress = await File('${root.path}/progress.sav')
          .writeAsString('keep');
      final transfer = model.downloadGame(queuedFixture(1));
      await api.started.future;
      final queue = File(
        '${root.path}/downloads/${model.server!.id}/${model.profile!.id}/queue.json',
      );
      final saved = await queue.rename('${queue.path}.fixture');
      final blocked = await Directory(queue.path).create();
      final stopping = model.finishDownloads(requireCheckpoint: true);
      api.release.complete();
      await expectLater(stopping, throwsA(isA<StateError>()));
      await transfer;
      expect(model.downloads.map((j) => j.game.id), [1]);
      final other = DownloadQueueStore(
        root,
        model.server!.id,
        model.profile!.id,
      );
      await expectLater(other.open(), throwsA(isA<DownloadQueueInUse>()));
      await blocked.delete();
      await saved.rename(queue.path);
      await model.finishDownloads(requireCheckpoint: true);
      expect(model.downloads, isEmpty);
      final jobs = await other.open();
      expect(jobs.map((j) => j.game.id), [1]);
      await other.close();
      expect(await progress.readAsString(), 'keep');
    } finally {
      if (!api.release.isCompleted) api.release.complete();
      await model.finishDownloads();
      await model.finishCloud();
      model.dispose();
      await root.delete(recursive: true);
    }
  });

  test('completed and failed update receipts report once while preserving recovery bundles', () async {
    final root = await Directory.systemTemp.createTemp(
      'broomm-update-receipt-',
    );
    addTearDown(() => root.delete(recursive: true));
    final loc = UpdateLocation(
      root,
      'windows',
      target: '${root.path}/application',
    );
    final stage = await Directory('${root.path}/.broomm-update-receipt')
        .create();
    await File('${stage.path}/broomm-update.json').writeAsString(
      jsonEncode({
        'product': 'Broomm',
        'format': 1,
        'target': loc.target,
        'version': '0.1.1',
        'build_target': 'windows-x64',
        'archive': updatePackage('0.1.1', 'windows-x64'),
      }),
    );
    await Directory('${stage.path}/previous').create();
    await File('${stage.path}/installed').writeAsString('installed');
    expect(
      (await cleanupApplicationUpdates(loc, current: '0.1.1'))?.problem,
      false,
    );
    expect(await cleanupApplicationUpdates(loc, current: '0.1.1'), isNull);
    await File('${stage.path}/reported').delete();
    await File('${stage.path}/failed').writeAsString('failed');
    expect(
      (await cleanupApplicationUpdates(loc, current: '0.1.0'))?.problem,
      true,
    );
    expect(await Directory('${stage.path}/previous').exists(), isTrue);
  });

  test('installation lease fences an independent Dart process and releases its stable lock', () async {
    final root = await Directory.systemTemp.createTemp(
      'broomm-update-os-lock-',
    );
    addTearDown(() => root.delete(recursive: true));
    final packages = jsonDecode(
      await File('.dart_tool/package_config.json').readAsString(),
    ) as Map;
    final flutter = (packages['packages'] as List).cast<Map>().singleWhere(
      (p) => p['name'] == 'flutter',
    );
    final package = File('.dart_tool/package_config.json').absolute.uri
        .resolve(flutter['rootUri'] as String);
    final sdkDart = Directory.fromUri(package).uri
        .resolve(
          '../../bin/cache/dart-sdk/bin/${Platform.isWindows ? 'dart.exe' : 'dart'}',
        )
        .toFilePath();
    final script = await File('${root.path}/lock.dart').writeAsString(
      "import 'dart:io'; Future<void> main(List<String> args) async { final f = await File(args[0]).open(mode: FileMode.append); try { await f.lock(FileLock.exclusive, 0, 1); } on FileSystemException { exitCode = 24; } finally { await f.close(); } }",
    );
    Future<int> child() async {
      final p = await Process.start(sdkDart, [
        script.path,
        '${root.path}/.broomm-updates.lock',
      ]);
      final drain = Future.wait([
        p.stdout.drain<void>(),
        p.stderr.drain<void>(),
      ]);
      try {
        return await p.exitCode.timeout(const Duration(seconds: 10));
      } finally {
        p.kill();
        await p.exitCode;
        await drain;
      }
    }

    final lease = await UpdateLease.acquire(root);
    try {
      expect(await child(), 24);
    } finally {
      await lease.close();
    }
    expect(await child(), 0);
  });

  test('release selection orders stable/RC numerically across families without downgrades', () {
    final releases = [
      updateRelease('0.2.0-rc2'),
      updateRelease('0.2.0-rc10'),
      updateRelease('0.1.9'),
      updateRelease('1.0.0', draft: true),
    ];
    expect(
      '${selectUpdate(releases, '0.1.0', false, 'windows-x64')!.version}',
      '0.1.9',
    );
    expect(
      '${selectUpdate(releases, '0.1.0', true, 'windows-x64')!.version}',
      '0.2.0-rc10',
    );
    expect(
      '${selectUpdate([...releases, updateRelease('0.2.0')], '0.2.0-rc10', true, 'windows-x64')!.version}',
      '0.2.0',
    );
    expect(selectUpdate(releases, '0.2.0', true, 'windows-x64'), isNull);
    expect(selectUpdate(releases, '0.1.0-dev', true, 'windows-x64'), isNull);
    expect(updateTarget('linux', Abi.linuxArm64), 'linux-arm64');
    expect(updateTarget('windows', Abi.windowsArm64), isNull);
  });

  test('incomplete, ambiguous, foreign or wrong-version assets never become offers', () {
    for (final change in <void Function(Map)>[
      (r) => (r['assets'] as List).removeLast(),
      (r) => (r['assets'] as List).add((r['assets'] as List).first),
      (r) => (r['assets'] as List).first['browser_download_url'] =
          'https://evil.example/app.zip',
      (r) => (r['assets'] as List).first['browser_download_url'] =
          'https://github.com/other/repo/releases/download/v0.1.1/app.zip',
      (r) => r['tag_name'] = 'v0.1.2',
    ]) {
      final release = updateRelease('0.1.1');
      change(release);
      expect(selectUpdate([release], '0.1.0', true, 'windows-x64'), isNull);
    }
    final hash = 'a' * 64;
    expect(parseUpdateChecksum('$hash  Broomm.zip\n', 'Broomm.zip'), hash);
    expect(
      () => parseUpdateChecksum(
        '$hash  Broomm.zip\n$hash  Broomm.zip',
        'Broomm.zip',
      ),
      throwsA(isA<UpdateFailure>()),
    );
  });

  test('prepare verifies and stages the complete application without replacing current files', () async {
    final root = await Directory.systemTemp.createTemp(
      'broomm-update-prepare-',
    );
    addTearDown(() => root.delete(recursive: true));
    final (update, transport, current) = await updateFixture(root);
    final prepared = await ApplicationInstaller(
      transport: transport,
      location: UpdateLocation(root, 'windows', target: current.path),
    ).prepare(update, root, (_, _) {});
    expect(
      await File('${current.path}/broomm.exe').readAsString(),
      contains('0.1.0'),
    );
    expect(
      await File('${prepared.payload}/broomm.exe').readAsString(),
      contains('0.1.1'),
    );
    await expectLater(UpdateLease.acquire(root), throwsA(isA<UpdateFailure>()));
    await prepared.discard();
    expect(await prepared.stage.exists(), isFalse);
    final lease = await UpdateLease.acquire(root);
    await lease.close();
  });

  test('corrupt downloads and contradictory metadata retain installation and release ownership', () async {
    for (final corrupt in [true, false]) {
      final root = await Directory.systemTemp.createTemp(
        'broomm-update-invalid-',
      );
      try {
        final (update, transport, current) = await updateFixture(root);
        transport.corrupt = corrupt;
        if (!corrupt)
          transport.responses[update.record.name] = utf8.encode('{}');
        await expectLater(
          ApplicationInstaller(
            transport: transport,
            location: UpdateLocation(root, 'windows', target: current.path),
          ).prepare(update, root, (_, _) {}),
          throwsA(isA<UpdateFailure>()),
        );
        expect(
          await File('${current.path}/broomm.exe').readAsString(),
          contains('0.1.0'),
        );
        expect(
          (await root.list().toList()).where(
            (e) => e.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('.broomm-update-'),
          ),
          isEmpty,
        );
        final lease = await UpdateLease.acquire(root);
        await lease.close();
      } finally {
        await root.delete(recursive: true);
      }
    }
  });

  test('extra personal files prevent whole-folder replacement', () async {
    final root = await Directory.systemTemp.createTemp(
      'broomm-update-personal-',
    );
    addTearDown(() => root.delete(recursive: true));
    final (_, transport, current) = await updateFixture(root);
    transport.close();
    final personal = await File('${current.path}/personal.sav')
        .writeAsString('keep');
    await expectLater(
      validateApplicationBundle(current, 'windows-x64'),
      throwsA(isA<UpdateFailure>()),
    );
    expect(await personal.readAsString(), 'keep');
  });

  test('cancelled transport never stages an install and failed checks retain last known offer', () async {
    final updater = ApplicationUpdates(
      current: '0.1.0',
      target: 'windows-x64',
      check: (_, _, _) async => throw StateError('offline'),
    );
    updater.available = selectUpdate(
      [updateRelease('0.1.1')],
      '0.1.0',
      false,
      'windows-x64',
    );
    await updater.check();
    expect(updater.available, isNotNull);
    expect(updater.checkFailed, isTrue);
    updater.dispose();
    final transport = UpdateTransport();
    transport.cancel();
    expect(transport.check, throwsA(isA<UpdateFailure>()));
  });

  test('cleanup keeps handed-off recovery, active stages and unrelated directories', () async {
    final root = await Directory.systemTemp.createTemp('broomm-update-clean-');
    addTearDown(() => root.delete(recursive: true));
    for (final name in ['old', 'recovery', 'foreign', 'incomplete']) {
      final dir = await Directory('${root.path}/.broomm-update-$name').create();
      final marker = await File('${dir.path}/broomm-update.json').writeAsString(
        jsonEncode({
          'product': name == 'foreign' ? 'Other' : 'Broomm',
          'format': 1,
          'version': '0.1.1',
          'build_target': name == 'incomplete' ? 'unknown' : 'windows-x64',
          'target': null,
          'archive': updatePackage('0.1.1', 'windows-x64'),
        }),
      );
      await marker.setLastModified(
        DateTime.now().subtract(const Duration(days: 2)),
      );
      if (name == 'recovery') await Directory('${dir.path}/previous').create();
    }
    final loc = UpdateLocation(root, 'windows');
    final lock = await UpdateLease.acquire(root);
    await expectLater(
      cleanupApplicationUpdates(loc),
      throwsA(isA<UpdateFailure>()),
    );
    await lock.close();
    await cleanupApplicationUpdates(loc);
    expect(
      await Directory('${root.path}/.broomm-update-old').exists(),
      isFalse,
    );
    expect(
      await Directory('${root.path}/.broomm-update-recovery').exists(),
      isTrue,
    );
    expect(
      await Directory('${root.path}/.broomm-update-foreign').exists(),
      isTrue,
    );
    expect(
      await Directory('${root.path}/.broomm-update-incomplete').exists(),
      isTrue,
    );
  });

  test('native installer waits for original process and commit, restarts, and rolls back failed publication', () async {
    final root = await Directory.systemTemp.createTemp('broomm-update-helper-');
    addTearDown(() => root.delete(recursive: true));
    for (final scenario in ['install', 'cancel', 'no-commit', 'rollback']) {
      final dir = await Directory('${root.path}/$scenario with spaces')
          .create();
      final target = await Directory('${dir.path}/application').create();
      final payload = await Directory('${dir.path}/new').create();
      final stage = await Directory('${dir.path}/stage').create();
      final old = await File('${target.path}/old')
          .writeAsString('previous application');
      await File('${dir.path}/progress.sav').writeAsString('keep progress');
      final binary = await File('${payload.path}/broomm')
          .writeAsString('#!/bin/sh\ntouch "\$(dirname "\$0")/restarted"\n');
      if (scenario != 'rollback')
        await Process.run('/bin/chmod', ['u+x', binary.path]);
      final parent = await Process.start('/bin/sh', [
        '-c',
        'while [ ! -e "\$1" ]; do sleep 0.05; done',
        'fixture',
        '${dir.path}/release',
      ]);
      final script = await File('${stage.path}/install.sh')
          .writeAsString(unixUpdateHelper);
      if (Platform.isMacOS)
        await File('${stage.path}/rename.js')
            .writeAsString(macExclusiveRenameScript);
      final claim = await File('${dir.path}/claim').writeAsString(stage.path);
      final helper = await Process.start('/bin/sh', [
        script.path,
        '${parent.pid}',
        target.path,
        payload.path,
        '${stage.path}/previous',
        stage.path,
        'linux',
        claim.path,
      ]);
      try {
        await waitFor(File('${stage.path}/ready'));
        expect(await old.readAsString(), 'previous application');
        if (scenario != 'no-commit')
          await File('${stage.path}/commit').writeAsString('install');
        if (scenario == 'cancel')
          await File('${stage.path}/cancel').writeAsString('cancel');
        await File('${dir.path}/release').writeAsString('exit');
        await parent.exitCode.timeout(const Duration(seconds: 5));
        expect(
          await helper.exitCode.timeout(const Duration(seconds: 8)),
          scenario == 'rollback' ? 1 : 0,
        );
        if (scenario == 'install') {
          await waitFor(File('${target.path}/restarted'));
          expect(
            await File('${stage.path}/previous/old').readAsString(),
            'previous application',
          );
          expect(await File('${stage.path}/installed').exists(), isTrue);
        } else {
          expect(await old.readAsString(), 'previous application');
          expect(await File('${stage.path}/installed').exists(), isFalse);
        }
        expect(
          await File('${dir.path}/progress.sav').readAsString(),
          'keep progress',
        );
        expect(await claim.exists(), isFalse);
      } finally {
        parent.kill();
        helper.kill();
        await parent.exitCode;
        await helper.exitCode;
      }
    }
  }, testOn: '!windows');

  test('native Windows helper acknowledges startup and cancels without replacement', () async {
    final root = await Directory.systemTemp.createTemp(
      'broomm-update-windows-',
    );
    addTearDown(() => root.delete(recursive: true));
    final script = await File('${root.path}/install.ps1')
        .writeAsString(windowsUpdateHelper);
    final claim = await File('${root.path}/claim').writeAsString(root.path);
    final helper = await Process.start(
      '${Platform.environment['SystemRoot']}/System32/WindowsPowerShell/v1.0/powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
        '$pid',
        '${root.path}/current',
        '${root.path}/new',
        '${root.path}/previous',
        root.path,
        'windows',
        claim.path,
      ],
    );
    try {
      await waitFor(File('${root.path}/ready'));
      await File('${root.path}/cancel').writeAsString('cancel');
      expect(await helper.exitCode.timeout(const Duration(seconds: 8)), 0);
      expect(await claim.exists(), isFalse);
      expect(await File('${root.path}/installed').exists(), isFalse);
    } finally {
      helper.kill();
      await helper.exitCode;
    }
  }, testOn: 'windows');

  test('native macOS helper replaces a private app bundle and relaunches it through Launch Services', () async {
    final root = await Directory.systemTemp.createTemp(
      'broomm-update-macos-native-',
    );
    addTearDown(() => root.delete(recursive: true));
    final target = await Directory('${root.path}/application with spaces.app')
        .create();
    await File('${target.path}/old').writeAsString('previous application');
    final payload = await Directory(
      '${root.path}/new/broomm.app/Contents/MacOS',
    ).create(recursive: true);
    final resources = await Directory('${payload.parent.path}/Resources')
        .create();
    await File('${payload.parent.path}/Info.plist').writeAsString(
      '''<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>app.broomm.update-fixture.${DateTime.now().microsecondsSinceEpoch}</string><key>CFBundleExecutable</key><string>broomm</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>''',
    );
    final source = await File('${root.path}/main.c').writeAsString(r'''
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
  (void)argc;
  char path[4096]; snprintf(path, sizeof(path), "%s", argv[0]);
  char *slash = strrchr(path, '/'); if (!slash) return 2; *slash = 0;
  strcat(path, "/../Resources/restarted");
  FILE *out = fopen(path, "w"); if (!out) return 3;
  fputs("native launch", out); return fclose(out);
}
''');
    final compiled = await Process.run(
      '/usr/bin/xcrun',
      ['clang', source.path, '-o', '${payload.path}/broomm'],
      includeParentEnvironment: false,
      environment: {
        'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer',
        'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
      },
    );
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
    final stage = await Directory('${root.path}/stage').create();
    final script = await File('${stage.path}/install.sh')
        .writeAsString(unixUpdateHelper);
    await File('${stage.path}/rename.js')
        .writeAsString(macExclusiveRenameScript);
    final claim = await File('${root.path}/claim').writeAsString(stage.path);
    final parent = await Process.start('/bin/sh', [
      '-c',
      'while [ ! -e "\$1" ]; do sleep 0.05; done',
      'fixture',
      '${root.path}/release',
    ]);
    final helper = await Process.start('/bin/sh', [
      script.path,
      '${parent.pid}',
      target.path,
      payload.parent.parent.path,
      '${stage.path}/previous',
      stage.path,
      'macos',
      claim.path,
    ]);
    try {
      await waitFor(File('${stage.path}/ready'));
      await File('${stage.path}/commit').writeAsString('install');
      await File('${root.path}/release').writeAsString('exit');
      await parent.exitCode;
      expect(await helper.exitCode.timeout(const Duration(seconds: 10)), 0);
      await waitFor(File('${target.path}/Contents/Resources/restarted'));
      expect(
        await File('${stage.path}/previous/old').readAsString(),
        'previous application',
      );
      expect(await File('${stage.path}/installed').exists(), isTrue);
      expect(await claim.exists(), isFalse);
      expect(await resources.exists(), isFalse);
    } finally {
      parent.kill();
      helper.kill();
      await parent.exitCode;
      await helper.exitCode;
    }
  }, testOn: 'mac-os');

  test('native macOS exclusive rename preserves existing empty and nonempty destinations', () async {
    final root = await Directory.systemTemp.createTemp(
      'broomm-update-exclusive-',
    );
    addTearDown(() => root.delete(recursive: true));
    final source = await Directory('${root.path}/source 日本 🎮').create();
    await File('${source.path}/application').writeAsString('new');
    final script = await File('${root.path}/rename.js')
        .writeAsString(macExclusiveRenameScript);
    for (final occupied in [false, true]) {
      final destination = await Directory(
        '${root.path}/${occupied ? 'nonempty' : 'empty'} 日本',
      ).create();
      if (occupied)
        await File('${destination.path}/personal.sav').writeAsString('keep');
      final result = await Process.run('/usr/bin/osascript', [
        '-l',
        'JavaScript',
        script.path,
        source.path,
        destination.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(await File('${source.path}/application').readAsString(), 'new');
      expect(await File('${destination.path}/application').exists(), isFalse);
      if (occupied)
        expect(
          await File('${destination.path}/personal.sav').readAsString(),
          'keep',
        );
    }
    final destination = '${root.path}/published';
    expect(
      (await Process.run('/usr/bin/osascript', [
        '-l',
        'JavaScript',
        script.path,
        source.path,
        destination,
      ])).exitCode,
      0,
    );
    expect(await source.exists(), isFalse);
    expect(await File('$destination/application').readAsString(), 'new');
  }, testOn: 'mac-os');
}
