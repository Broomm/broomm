import 'package:flutter_test/flutter_test.dart';

import '../tool/ci/annotate_tests.dart';

void main() {
  test('test annotations retain names and failure details without command injection', () {
    final report = TestAnnotations()
      ..add({
        'type': 'testStart',
        'test': {'id': 7, 'name': r'D:\test\mmj_test.dart: save restore'},
      })
      ..add({
        'type': 'error',
        'testID': 7,
        'error': 'Expected: 100%\n::warning::not a command',
        'stackTrace': 'test/mmj_test.dart 12:3',
      })
      ..add({'type': 'testDone', 'testID': 7, 'result': 'failure'})
      ..add({'type': 'done', 'success': false});
    final lines = report.finish();
    expect(lines, hasLength(1));
    expect(lines.single, contains(r'D:\test\mmj_test.dart: save restore'));
    expect(lines.single, contains('100%25%0A::warning::not a command'));
    expect(lines.single, contains('test/mmj_test.dart 12:3'));
    expect(lines.single, isNot(contains('\n')));
  });

  test('missing error details and late asynchronous errors remain visible', () {
    final report = TestAnnotations()
      ..add({
        'type': 'testStart',
        'test': {'id': 1, 'name': 'missing details'},
      })
      ..add({'type': 'testDone', 'testID': 1, 'result': 'failure'})
      ..add({
        'type': 'testStart',
        'test': {'id': 2, 'name': 'late failure'},
      })
      ..add({'type': 'testDone', 'testID': 2, 'result': 'success'})
      ..add({
        'type': 'error',
        'testID': 2,
        'error': 'late error',
        'stackTrace': '',
      });
    final output = report.finish().join('\n');
    expect(output, contains('missing details%0AFailed without error details.'));
    expect(output, contains('late failure%0Alate error'));
  });

  test('passing reports are quiet and failure output is bounded', () {
    final passing = TestAnnotations()..add({'type': 'done', 'success': true});
    expect(passing.finish(), isEmpty);
    final failures = TestAnnotations();
    for (var id = 0; id < 30; id++) {
      failures.add({
        'type': 'error',
        'testID': id,
        'error': 'x' * 20000,
        'stackTrace': '',
      });
    }
    expect(failures.finish(), hasLength(21));
    expect(failures.finish().first.length, lessThan(8100));
    expect(failures.finish().last, contains('10 additional failing tests'));
  });
}
