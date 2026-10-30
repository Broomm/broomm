import 'dart:convert';
import 'dart:io';

/// Reads Flutter's standard JSON reporter, independently of test exit status.
/// Only failed tests become annotations; the complete report remains an artifact.
class TestAnnotations {
  final names = <int, String>{};
  final errors = <int, List<String>>{};
  final failed = <int>{};
  bool unsuccessful = false;

  void add(Map<String, dynamic> event) {
    final id = event['testID'];
    switch (event['type']) {
      case 'testStart':
        final test = event['test'] as Map;
        names[test['id'] as int] = test['name'] as String;
      case 'error':
        errors
            .putIfAbsent(id as int, () => [])
            .add('${event['error']}\n${event['stackTrace'] ?? ''}');
      case 'testDone':
        if (event['result'] == 'failure' || event['result'] == 'error') {
          failed.add(id as int);
        }
      case 'done':
        unsuccessful = event['success'] == false;
    }
  }

  List<String> finish() {
    final ids = {...errors.keys, ...failed};
    return [
      for (final id in ids.take(20))
        annotation(
          '${names[id] ?? 'Test $id'}\n${errors[id]?.join('\n') ?? 'Failed without error details.'}',
        ),
      if (ids.length > 20)
        '::warning::${ids.length - 20} additional failing tests are in the JSON artifact.',
      if (unsuccessful && ids.isEmpty)
        annotation(
          'Flutter reported an unsuccessful run without test details.',
        ),
    ];
  }
}

String annotation(String message) {
  final clean = message.replaceAll(RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]'), '');
  final bounded = String.fromCharCodes(clean.runes.take(8000));
  final escaped = bounded
      .replaceAll('%', '%25')
      .replaceAll('\r', '%0D')
      .replaceAll('\n', '%0A');
  return '::error title=Flutter test failure::$escaped';
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart tool/ci/annotate_tests.dart <report.json>...');
    exitCode = 64;
    return;
  }
  for (final path in args) {
    final file = File(path);
    if (!await file.exists())
      continue; // Earlier toolchain failure has no report.
    try {
      if (await file.length() > 64 * 1024 * 1024) {
        throw const FormatException('Test report exceeds 64 MiB');
      }
      final result = TestAnnotations();
      await for (final line
          in file
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.isEmpty) continue;
        if (line.length > 1024 * 1024) {
          throw const FormatException('Test report line exceeds 1 MiB');
        }
        result.add((jsonDecode(line) as Map).cast<String, dynamic>());
      }
      for (final line in result.finish()) stdout.writeln(line);
    } catch (e) {
      stdout.writeln(annotation('Could not read test report $path: $e'));
      exitCode = 1;
    }
  }
}
