// Version/tag policy adapted from Teddy's release workflow. No Git mutations.
import 'dart:convert';
import 'dart:io';

final releaseTagPattern = RegExp(
  r'^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-rc([1-9][0-9]*))?$',
);

void validateBase(String base) {
  if (!RegExp(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$').hasMatch(base)) {
    throw const FormatException(
      'version.txt must contain MAJOR.MINOR, e.g. 0.1',
    );
  }
}

String nextVersion(String base, String branch, Iterable<String> tags) {
  validateBase(base);
  if (branch != 'main' && branch != 'develop') {
    throw const FormatException('Unknown release channel');
  }
  final matches = tags
      .map(releaseTagPattern.firstMatch)
      .nonNulls
      .where((m) => '${m[1]}.${m[2]}' == base)
      .toList();
  var patch = 0;
  for (final m in matches.where((m) => m[4] == null)) {
    final candidate = int.parse(m[3]!) + 1;
    if (candidate > patch) patch = candidate;
  }
  final core = '$base.$patch';
  if (branch == 'main') return core;
  var rc = 1;
  for (final m in matches.where(
    (m) => int.parse(m[3]!) == patch && m[4] != null,
  )) {
    final candidate = int.parse(m[4]!) + 1;
    if (candidate > rc) rc = candidate;
  }
  return '$core-rc$rc';
}

bool canPromote(String version, String branch, Iterable<String> tags) {
  final current = releaseTagPattern.firstMatch('v$version');
  if (current == null) return false;
  List<int> key(RegExpMatch m) => [
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4] ?? '0'),
  ];
  final own = key(current);
  for (final peer
      in tags
          .map(releaseTagPattern.firstMatch)
          .nonNulls
          .where((m) => (m[4] == null) == (branch == 'main'))) {
    final other = key(peer);
    for (var i = 0; i < own.length; i++) {
      if (own[i] > other[i]) break;
      if (own[i] < other[i]) return false;
    }
  }
  return true;
}

typedef GitCommand = Future<String> Function(List<String> arguments);

Future<String> git(List<String> args) async {
  final result = await Process.run(
    'git',
    args,
  ).timeout(const Duration(minutes: 2));
  if (result.exitCode != 0)
    throw StateError('Git inspection failed (${args.first}).');
  return (result.stdout as String).trim();
}

String requiredEnvironment(Map<String, String> env, String key) {
  final value = env[key];
  if (value == null || value.isEmpty || RegExp(r'[\x00\r\n]').hasMatch(value)) {
    throw FormatException('Missing or invalid $key');
  }
  return value;
}

Future<Map<String, String>> releaseVersion(
  String base,
  Map<String, String> env, {
  GitCommand inspect = git,
}) async {
  validateBase(base);
  final event = requiredEnvironment(env, 'GITHUB_EVENT_NAME');
  final branch = requiredEnvironment(env, 'GITHUB_REF_NAME');
  final sha = requiredEnvironment(env, 'GITHUB_SHA');
  final runId = requiredEnvironment(env, 'GITHUB_RUN_ID');
  final runNumber = int.parse(requiredEnvironment(env, 'GITHUB_RUN_NUMBER'));
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(sha) ||
      !RegExp(r'^[1-9][0-9]*$').hasMatch(runId) ||
      runNumber < 1 ||
      runNumber + 1000 > 2100000000) {
    throw const FormatException('Invalid workflow identity/build number');
  }
  if (await inspect(['rev-parse', 'HEAD']) != sha) {
    throw StateError('Checkout does not match the workflow commit.');
  }
  final publish = event == 'push' && {'main', 'develop'}.contains(branch);
  final tags = (await inspect([
    'tag',
    '--list',
    'v*',
  ])).split('\n').where((t) => releaseTagPattern.hasMatch(t)).toList()..sort();
  String? version;
  if (publish) {
    for (final tag in tags) {
      final match = releaseTagPattern.firstMatch(tag)!;
      if ((match[4] == null) != (branch == 'main') ||
          !tag.startsWith('v$base.'))
        continue;
      final message = await inspect([
        'for-each-ref',
        '--format=%(contents)',
        'refs/tags/$tag',
      ]);
      Object? reservation;
      try {
        reservation = jsonDecode(message);
      } on FormatException {
        /* Lightweight tag. */
      }
      if (reservation is Map && reservation['run_id'] == runId) {
        if (reservation['sha'] != sha || reservation['branch'] != branch) {
          throw StateError(
            'Tag reservation belongs to another commit/channel.',
          );
        }
        version = tag.substring(1);
        break;
      }
      if (await inspect(['cat-file', '-t', 'refs/tags/$tag']) == 'commit' &&
          await inspect(['rev-parse', '$tag^{commit}']) == sha) {
        version = tag.substring(1);
        break;
      }
    }
  }
  version ??= nextVersion(base, publish ? branch : 'main', tags);
  if (!publish) {
    final pr = requiredEnvironment(env, 'PR_NUMBER');
    if (event != 'pull_request' || !RegExp(r'^[1-9][0-9]*$').hasMatch(pr)) {
      throw const FormatException(
        'Only pushes and pull requests are supported.',
      );
    }
    version += '-pr$pr.$runId';
  }
  return {
    'version': version,
    'core': version.split('-').first,
    'tag': 'v$version',
    'build_number': '${1000 + runNumber}',
    'publish': '$publish',
    'promote': '${publish && canPromote(version, branch, tags)}',
    'prerelease': '${publish && branch == 'develop'}',
  };
}

Future<void> validatePublication(
  String base,
  Map<String, String> env, {
  GitCommand inspect = git,
}) async {
  validateBase(base);
  final branch = requiredEnvironment(env, 'GITHUB_REF_NAME');
  if (env['GITHUB_EVENT_NAME'] != 'push' ||
      !{'main', 'develop'}.contains(branch)) {
    throw StateError('Only main/develop pushes can publish.');
  }
  final version = requiredEnvironment(env, 'RELEASE_VERSION');
  final m = releaseTagPattern.firstMatch('v$version');
  if (m == null ||
      '${m[1]}.${m[2]}' != base ||
      (m[4] == null) != (branch == 'main')) {
    throw const FormatException(
      'Release version does not match this channel/base.',
    );
  }
  final sha = requiredEnvironment(env, 'GITHUB_SHA');
  if (await inspect(['rev-parse', 'HEAD']) != sha)
    throw StateError('Wrong checkout.');
  final tags = (await inspect(['tag', '--list', 'v*'])).split('\n');
  if (tags.contains('v$version')) {
    if (await inspect(['rev-parse', 'v$version^{commit}']) != sha) {
      throw StateError(
        'This version belongs to another commit; rerun all jobs.',
      );
    }
  } else if (version != nextVersion(base, branch, tags)) {
    throw StateError('Release version is stale; rerun all jobs.');
  }
}

Future<void> main(List<String> args) async {
  final base = (await File('version.txt').readAsString()).trim();
  if (args.length == 1 && args.single == '--check') {
    await validatePublication(base, Platform.environment);
    return;
  }
  if (args.isNotEmpty)
    throw const FormatException(
      'Usage: dart tool/release/version.dart [--check]',
    );
  final output = await releaseVersion(base, Platform.environment);
  await File(requiredEnvironment(Platform.environment, 'GITHUB_OUTPUT'))
      .writeAsString(
        output.entries.map((e) => '${e.key}=${e.value}\n').join(),
        mode: FileMode.append,
      );
  stdout.writeln(jsonEncode(output));
}
