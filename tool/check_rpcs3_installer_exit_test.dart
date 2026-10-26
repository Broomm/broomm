@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:broomm/src/addons/rpcs3_import.dart';
import 'package:broomm/src/addons/files.dart';
import 'package:broomm/src/progress/layout.dart';
import 'package:broomm/src/romm/models.dart';
import 'package:broomm/src/romm/transfer.dart';
import 'package:broomm/src/session_lease.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory data, evidence;
  late String fixture;
  final results = <Map<String, dynamic>>[];
  setUpAll(() async {
    evidence = Directory('.tool-cache/research/platform-support').absolute;
    await evidence.create(recursive: true);
    data = await evidence.createTemp('installer-exit-');
    await File('${data.path}/writer.lock').writeAsString('');
    fixture = '${data.path}/fixture';
    final cc = await Process.run(
      '/usr/bin/xcrun',
      [
        'clang',
        '-Wall',
        '-Wextra',
        '-Werror',
        'tool/fixtures/rpcs3_installer_exit.c',
        '-o',
        fixture,
      ],
      environment: {
        'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer',
      },
    );
    expect(cc.exitCode, 0, reason: '${cc.stderr}');
  });
  tearDownAll(() async {
    await File('${evidence.path}/installer-exit-results.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'utc': DateTime.now().toUtc().toIso8601String(), 'results': results})}\n',
      flush: true,
    );
  });
  Future<Directory> run(String exe, File input, String name) async {
    final stage = await data.createTemp('$name-');
    final lease = await SessionLease.acquire(data);
    try {
      return await installRpcs3Content(
        exe,
        input.path,
        stage,
        DownloadCancellation(),
        firmware: false,
        data: data,
      );
    } finally {
      await lease.release();
    }
  }

  test(
    'the exact completed teardown is accepted through the opted-in bridge',
    () async {
      final input = await File('${data.path}/complete.pkg')
          .writeAsString('fixture');
      final user = await run(fixture, input, 'complete');
      final log = await File(
        '${user.parent.parent.parent.parent.path}/installer.log',
      ).readAsString();
      expect(log, contains('BROOMM_RPCS3_CLI_ABORT_V1'));
      results.add({'case': 'completed-fixture', 'accepted': true});
    },
  );
  test('a genuine installer failure remains a visible failure despite the orderly abort status', () async {
    final input = await File('${data.path}/failed.pkg')
        .writeAsString('fixture');
    await expectLater(
      run(fixture, input, 'failed'),
      throwsA(isA<RommFailure>()),
    );
    results.add({'case': 'failed-fixture', 'rejected': true});
  });
  test(
    'exit 86 without the bridge marker cannot spoof a completed teardown',
    () async {
      final input = await File('${data.path}/forged.pkg')
          .writeAsString('fixture');
      await expectLater(
        run(fixture, input, 'forged'),
        throwsA(isA<RommFailure>()),
      );
      results.add({'case': 'forged-fixture', 'rejected': true});
    },
  );
  for (final variant in ['rpcs3', 'rpcs3-intel']) {
    test(
      'real $variant imports the cached GT6 package without SIGABRT and matches its verified content inventory',
      () async {
        final j = jsonDecode(
          await File('assets/setup/tested-builds.json').readAsString(),
        ) as Map;
        final build = (j['builds'] as List).cast<Map>().singleWhere(
          (b) => b['id'] == variant,
        );
        final executable =
            '${Directory.current.path}/broomm-data/emulators/$variant/${build['sha256']}/${build['bundle']}/${build['executable']}';
        final input = File(
          '${Directory.current.path}/broomm-data/library/506d439865d8f46267001bdd3a1fe0e5/8010/content/dlc/BCUS98296_GRAN_TURISMO_6_ALL_DLC_PACK_FIX_byFugazi.pkg',
        );
        final clock = Stopwatch()..start();
        final user = await run(executable, input, variant);
        final title = Directory('${user.path}/dev_hdd0/game/BCUS98296');
        expect(
          (await readPs3Sfo(File('${title.path}/PARAM.SFO')))['TITLE_ID'],
          'BCUS98296',
        );
        final inventory = await addonInventory(title);
        final canonical = jsonDecode(
          await File(
            'broomm-data/addons-ps3/506d439865d8f46267001bdd3a1fe0e5/8010/current.json',
          ).readAsString(),
        ) as Map;
        expect(
          inventory,
          canonical['units']['dev_hdd0/game/BCUS98296']['files'],
        );
        final log = await File(
          '${user.parent.parent.parent.parent.path}/installer.log',
        ).readAsString();
        expect(log, contains('BROOMM_RPCS3_CLI_ABORT_V1'));
        final pid = int.parse(
          RegExp(r'RPCS3 installer PID: (\d+)').firstMatch(log)!.group(1)!,
        );
        final reports = Directory(
          '${Platform.environment['HOME']}/Library/Logs/DiagnosticReports',
        );
        var reportFound = false;
        await for (final report in reports.list(followLinks: false)) {
          if (report is! File ||
              !report.path.contains('/rpcs3-2026-10-23-') ||
              !report.path.endsWith('.ips'))
            continue;
          final lines = await report.readAsString();
          final body =
              jsonDecode(lines.substring(lines.indexOf('\n') + 1)) as Map;
          reportFound |= body['pid'] == pid;
        }
        expect(reportFound, false);
        results.add({
          'case': variant,
          'pid': pid,
          'files': inventory.length,
          'durationMs': clock.elapsedMilliseconds,
          'bridgeMarker': true,
          'outputInventoryMatches': true,
          'crashReportFound': reportFound,
        });
      },
    );
  }
}
