import 'dart:async';

import 'package:broomm/src/retroarch_control.dart';
import 'package:broomm/src/session.dart' show retroStatusMatches;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native pause survives polling and active controller publications',
    () async {
      var paused = true, toggles = 0;
      final control = RetroArchPauseControl(
        query: () async =>
            'GET_STATUS ${paused ? 'PAUSED' : 'PLAYING'} snes,Game',
        toggle: () {
          toggles++;
          paused = !paused;
        },
        matches: (s) => retroStatusMatches(s, '/roms/Game.sfc'),
        current: () => true,
      );
      expect(
        await control.update(blocked: true, releaseSerial: 0, revision: 1),
        1,
      );
      expect(
        await control.update(blocked: false, releaseSerial: 1, revision: 2),
        0,
      );
      expect(toggles, 1);
      paused = true;
      for (var revision = 2; revision < 8; revision++) {
        expect(
          await control.update(
            blocked: false,
            releaseSerial: 1,
            revision: revision,
          ),
          1,
        );
      }
      expect(toggles, 1);
      paused = false;
      expect(
        await control.update(blocked: false, releaseSerial: 1, revision: 8),
        0,
      );
      expect(toggles, 1);
    },
  );

  test(
    'gate reasserts pause and quick release survives an in-flight query',
    () async {
      var paused = false, toggles = 0;
      Completer<String?>? held;
      final control = RetroArchPauseControl(
        query: () async => held != null
            ? held.future
            : 'GET_STATUS ${paused ? 'PAUSED' : 'PLAYING'} snes,Game',
        toggle: () {
          toggles++;
          paused = !paused;
        },
        matches: (s) => retroStatusMatches(s, '/roms/Game.sfc'),
        current: () => true,
      );
      expect(
        await control.update(blocked: true, releaseSerial: 0, revision: 1),
        1,
      );
      paused = false; // Native Resume cannot bypass an active controller gate.
      expect(
        await control.update(blocked: true, releaseSerial: 0, revision: 1),
        1,
      );
      expect(
        await control.update(blocked: false, releaseSerial: 1, revision: 2),
        0,
      );
      paused = true;
      held = Completer<String?>();
      final inFlight = control.update(
        blocked: false,
        releaseSerial: 1,
        revision: 2,
      );
      await control.update(blocked: true, releaseSerial: 1, revision: 3);
      await control.update(blocked: false, releaseSerial: 2, revision: 4);
      final reply = held;
      held = null;
      reply.complete('GET_STATUS PAUSED snes,Game');
      expect(await inFlight, 0);
      expect(toggles, 4);
      paused = true;
      expect(
        await control.update(blocked: false, releaseSerial: 2, revision: 4),
        1,
      );
      expect(toggles, 4);
    },
  );

  test('unknown/foreign replies and ended sessions cannot toggle; retries are explicit', () async {
    String? reply;
    var live = true, toggles = 0;
    Completer<String?>? held;
    final control = RetroArchPauseControl(
      query: () async => held != null ? held.future : reply,
      toggle: () => toggles++,
      matches: (s) => retroStatusMatches(s, '/roms/Game.sfc'),
      current: () => live,
    );
    for (final value in [
      null,
      'GET_STATUS CONTENTLESS',
      'GET_STATUS PAUSED snes,Other',
    ]) {
      reply = value;
      expect(
        await control.update(blocked: false, releaseSerial: 1, revision: 2),
        isNull,
      );
    }
    expect(toggles, 0);
    reply = 'GET_STATUS PAUSED snes,Game';
    await control.update(blocked: false, releaseSerial: 1, revision: 2);
    await control.update(blocked: false, releaseSerial: 1, revision: 2);
    expect(
      toggles,
      1,
      reason: 'A missing acknowledgement must not flood toggle commands.',
    );
    await control.update(blocked: false, releaseSerial: 1, revision: 3);
    expect(
      toggles,
      2,
      reason: 'An explicit retry can resend the unacknowledged transition.',
    );
    held = Completer<String?>();
    final inFlight = control.update(
      blocked: true,
      releaseSerial: 1,
      revision: 4,
    );
    live = false;
    held.complete('GET_STATUS PLAYING snes,Game');
    expect(await inFlight, isNull);
    expect(toggles, 2);
  });
}
