import 'package:broomm/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> progress({
    int files = 10,
    int done = 2,
    int modules = 100,
    int completed = 25,
    int bits = 0,
    int known = 0,
  }) => {
    'filesTotal': files,
    'filesDone': done,
    'modulesTotal': modules,
    'modulesDone': completed,
    'totalBits': bits,
    'knownBits': known,
  };
  test('RPCS3 progress uses its native module estimate and permits a new phase to reset independently of input readiness', () {
    final first = Rpcs3Loading.read(progress())!;
    expect(first.fraction, .25);
    expect(
      Rpcs3Loading.read(
        progress(
          modules: 0xffffffff,
          completed: 1,
          bits: 1 << 48,
          known: 1 << 47,
        ),
      )!.fraction,
      closeTo(1 / (0xffffffff * 2.0), 1e-20),
    );
    expect(first.description, 'Files 2 / 10 · Modules 25 / 100');
    expect(Rpcs3Loading.read(progress(bits: 200, known: 100))!.fraction, .125);
    expect(Rpcs3Loading.read(progress(completed: 0))!.fraction, 0);
    expect(
      Rpcs3Loading.read(progress(modules: 0, completed: 0))!.fraction,
      isNull,
    );
  });
  test('missing, torn, malformed and reset counters are optional and cannot break controller status parsing', () {
    for (final value in [
      null,
      {},
      progress(done: 11),
      progress(completed: 101),
      progress(bits: 2, known: 3),
      progress(files: 0, done: 0, modules: 0, completed: 0),
      {...progress(), 'modulesDone': -1},
      {...progress(), 'filesDone': 1.5},
    ]) {
      final s = BridgeStatus({
        'protocol': 4,
        'pid': 1,
        'sample': 1,
        'ack': 0,
        'requestSerial': 0,
        'request': 'initial',
        'blocked': true,
        'paused': -1,
        'window': [0, 0, 1, 1],
        'devices': [],
        'loading': value,
      });
      expect(s.loading, isNull);
      expect(s.inputReady, false);
    }
  });
}
