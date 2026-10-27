import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broomm/src/progress/digest.dart';

import '../tool/release/common.dart';
import '../tool/release/package.dart' show javaProperty, writeBuildRecord;
import '../tool/release/publish.dart';
import '../tool/release/version.dart';

void main() {
  test('packaged application inventory retains the full release identity and every top-level bundle entry', () async {
    final root = await Directory.systemTemp.createTemp(
      'broomm-release-inventory-',
    );
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/broomm.exe').writeAsString('fixture');
    await Directory('${root.path}/data').create();
    await writeBuildRecord(root, '0.1.1-rc2', '1010', 'a' * 40, 'windows-x64');
    final record = jsonDecode(
      await File('${root.path}/broomm-release.json').readAsString(),
    ) as Map;
    expect(record['version'], '0.1.1-rc2');
    expect(record['target'], 'windows-x64');
    expect(
      (record['entries'] as List).toSet(),
      (await root.list().toList())
          .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toSet(),
    );
  });
  test('Teddy release channels advance from stable tags, with numeric candidate ordering', () {
    expect(nextVersion('0.1', 'main', []), '0.1.0');
    expect(nextVersion('0.1', 'develop', []), '0.1.0-rc1');
    final tags = [
      'v0.1.9',
      'v0.1.11',
      'v0.1.12-rc2',
      'v0.1.12-rc10',
      'v2.0.7',
      'upstream-9',
    ];
    expect(nextVersion('0.1', 'main', tags), '0.1.12');
    expect(nextVersion('0.1', 'develop', tags), '0.1.12-rc11');
    expect(nextVersion('0.2', 'develop', tags), '0.2.0-rc1');
    expect(nextVersion('0.1', 'develop', [...tags, 'v0.1.12']), '0.1.13-rc1');
    for (final base in ['1', 'v1.2', '01.2', '1.02', '1.2.3', '1.2\n3.4']) {
      expect(() => nextVersion(base, 'main', []), throwsFormatException);
    }
  });

  test('older reruns do not promote a channel backwards', () {
    expect(canPromote('0.1.0', 'main', ['v0.1.1']), isFalse);
    expect(canPromote('0.1.2-rc2', 'develop', ['v0.1.2-rc10']), isFalse);
    expect(canPromote('0.2.0', 'main', ['v0.1.99', 'v0.2.0-rc9']), isTrue);
    expect(canPromote('0.1.9', 'main', ['v0.1.10']), isFalse);
  });

  test('real Git ledger: PRs, retries, stale plans and release ownership never mutate tags', () async {
    final root = await Directory.systemTemp.createTemp('broomm-release-git-');
    addTearDown(() => root.delete(recursive: true));
    Future<String> inspect(List<String> args) async {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: root.path,
      );
      if (result.exitCode != 0)
        throw StateError('Fixture Git failed: ${result.stderr}');
      return (result.stdout as String).trim();
    }

    await inspect(['init', '--initial-branch=main']);
    await inspect([
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.invalid',
      'commit',
      '--allow-empty',
      '-m',
      'fixture',
    ]);
    final sha = await inspect(['rev-parse', 'HEAD']);
    Map<String, String> env(
      String branch,
      String run, {
      String event = 'push',
    }) => {
      'GITHUB_EVENT_NAME': event,
      'GITHUB_REF_NAME': branch,
      'GITHUB_SHA': sha,
      'GITHUB_RUN_ID': run,
      'GITHUB_RUN_NUMBER': run,
      'PR_NUMBER': '7',
    };
    final develop = env('develop', '1');
    expect(
      (await releaseVersion('0.1', develop, inspect: inspect))['version'],
      '0.1.0-rc1',
    );
    expect(await inspect(['tag', '--list']), '');
    await validatePublication('0.1', {
      ...develop,
      'RELEASE_VERSION': '0.1.0-rc1',
    }, inspect: inspect);
    expect(await inspect(['tag', '--list']), '');
    await inspect(['tag', 'v0.1.0-rc1', sha]);
    expect(
      (await releaseVersion('0.1', develop, inspect: inspect))['version'],
      '0.1.0-rc1',
    );
    await inspect(['tag', 'v0.1.0', sha]);
    final tags = await inspect(['tag', '--list']);
    final preview = await releaseVersion(
      '0.1',
      env('7/merge', '2', event: 'pull_request'),
      inspect: inspect,
    );
    expect(preview['version'], '0.1.1-pr7.2');
    expect(preview['build_number'], '1002');
    expect(preview['publish'], 'false');
    await expectLater(
      validatePublication('0.1', {
        ...env('7/merge', '2', event: 'pull_request'),
        'RELEASE_VERSION': '0.1.1',
      }, inspect: inspect),
      throwsStateError,
    );
    await expectLater(
      validatePublication('0.1', {
        ...env('main', '3'),
        'RELEASE_VERSION': '0.1.2',
      }, inspect: inspect),
      throwsStateError,
    );
    await expectLater(
      validatePublication('0.1', {
        ...env('main', '3'),
        'GITHUB_SHA': 'a' * 40,
        'RELEASE_VERSION': '0.1.0',
      }, inspect: inspect),
      throwsStateError,
    );
    expect(await inspect(['tag', '--list']), tags);
    expect(await inspect(['rev-parse', 'HEAD']), sha);
  });

  group('complete release staging', () {
    late Directory root, dist;
    const sha = '0123456789012345678901234567890123456789';
    final env = {
      'RELEASE_VERSION': '0.1.0',
      'RELEASE_TAG': 'v0.1.0',
      'GITHUB_SHA': sha,
      'GITHUB_REPOSITORY': 'owner/broomm',
      'PRERELEASE': 'false',
      'PROMOTE': 'true',
    };
    setUp(() async {
      root = await Directory.systemTemp.createTemp('broomm-release-assets-');
      dist = await Directory('${root.path}/dist').create();
      for (final target in releaseTargets.entries) {
        final name = 'Broomm-0.1.0-${target.key}';
        final file = await File('${dist.path}/$name.${target.value}')
            .writeAsString('payload ${target.key}');
        final hash = await progressFileHash(file);
        await File('${file.path}.sha256')
            .writeAsString('$hash  ${file.uri.pathSegments.last}\n');
        await File('${dist.path}/$name.json').writeAsString(
          jsonEncode({
            'product': 'Broomm',
            'version': '0.1.0',
            'sha': sha,
            'target': target.key,
            'sha256': hash,
            'bytes': await file.length(),
          }),
        );
      }
    });
    tearDown(() => root.delete(recursive: true));

    Future<List<List<String>>> publish({
      bool failUpload = false,
      bool incomplete = false,
      bool public = false,
    }) async {
      final calls = <List<String>>[];
      await publishRelease(
        dist,
        env,
        invoke: (args) async {
          calls.add(args);
          if (args.first == 'api')
            return jsonEncode([
              public
                  ? [
                      {'tag_name': 'v0.1.0', 'draft': false},
                    ]
                  : [],
            ]);
          if (args[1] == 'upload' && failUpload)
            throw StateError('Controlled upload failure');
          if (args[1] == 'view')
            return jsonEncode({
              'isDraft': true,
              'assets': incomplete
                  ? []
                  : [
                      for (final f in await dist.list().toList())
                        {
                          'name': f.uri.pathSegments.last,
                          'size': (f as File).lengthSync(),
                        },
                    ],
            });
          return '';
        },
      );
      return calls;
    }

    test(
      'only publishes after all five checksums and draft upload readback',
      () async {
        final calls = await publish();
        expect(calls.where((a) => a.contains('--draft')).length, 1);
        expect(calls.last, contains('--draft=false'));
        expect(calls[calls.length - 2].take(2), ['release', 'view']);
        expect(
          calls.where((a) => a.length > 1 && a[1] == 'upload').single.length,
          21,
        );
      },
    );

    test(
      'failed upload or incomplete readback leaves the release private',
      () async {
        for (final fail in [true, false]) {
          final calls = <List<String>>[];
          await expectLater(
            publishRelease(
              dist,
              env,
              invoke: (args) async {
                calls.add(args);
                if (args.first == 'api') return '[[]]';
                if (args[1] == 'upload' && fail)
                  throw StateError('Controlled failure');
                if (args[1] == 'view') return '{"isDraft":true,"assets":[]}';
                return '';
              },
            ),
            throwsStateError,
          );
          expect(calls.any((a) => a.contains('--draft=false')), isFalse);
        }
      },
    );

    test('corrupt, incomplete or mixed-commit payloads fail before creating a draft', () async {
      final files = await dist.list().toList();
      final file = files.whereType<File>().firstWhere(
        (f) => f.path.endsWith('.apk'),
      );
      await file.writeAsString('changed bytes');
      final calls = <List<String>>[];
      await expectLater(
        publishRelease(
          dist,
          env,
          invoke: (args) async {
            calls.add(args);
            return '[[]]';
          },
        ),
        throwsStateError,
      );
      expect(calls.every((a) => a.first == 'api'), isTrue);
      await file.delete();
      await expectLater(
        validateReleaseAssets(dist, '0.1.0', sha),
        throwsStateError,
      );
    });

    test('a completed publication is immutable even if a rerun has no staged assets', () async {
      for (final f in await dist.list().toList()) {
        await f.delete();
      }
      final calls = await publish(public: true);
      expect(calls.length, 1);
    });

    test(
      'unexpected assets and mismatched commit metadata cannot be uploaded',
      () async {
        final extra = await File('${dist.path}/unrelated.txt')
            .writeAsString('private');
        await expectLater(
          validateReleaseAssets(dist, '0.1.0', sha),
          throwsStateError,
        );
        await extra.delete();
        await expectLater(
          validateReleaseAssets(dist, '0.1.0', 'a' * 40),
          throwsStateError,
        );
      },
    );
  });

  test('keystore properties preserve special characters without turning values into settings', () {
    expect(javaProperty(' a=b:c\\d\nx\ry\tz'), r'\ a\=b\:c\\d\nx\ry\tz');
  });
}
