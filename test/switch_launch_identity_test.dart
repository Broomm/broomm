import 'package:broomm/src/switch_launch_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const start =
      '[   1.346605] Core <Info> core/core.cpp:327:Load: Loading Super';
  const end = ' Smash Bros. Ultimate (01006A800016E000) ...\n';
  test(
    'Eden identifies a split loader line with interleaved driver output',
    () {
      for (final stderr in [false, true]) {
        final identity = SwitchLaunchIdentity('Eden');
        identity.add(start.codeUnits, stderr: stderr);
        identity.add(
          'ATTENTION: default value of option vk_xwayland_wait_ready overridden by environment.\n'
              .codeUnits,
          stderr: !stderr,
        );
        identity.add(end.codeUnits, stderr: stderr);
        expect(identity.program, '01006a800016e000');
      }
    },
  );

  test('independent pipes cannot manufacture a loaded title observation', () {
    final identity = SwitchLaunchIdentity('Eden');
    identity.add(start.codeUnits, stderr: false);
    identity.add(end.codeUnits, stderr: true);
    expect(identity.program, isNull);
    identity.add('\n$start$end'.codeUnits, stderr: true);
    expect(identity.program, '01006a800016e000');
    identity.add(
      '$start Other (0100000000001000) ...\n'.codeUnits,
      stderr: false,
    );
    expect(identity.program, '01006a800016e000');
  });

  test(
    'large output bursts retain loader records and supported family syntax',
    () {
      final eden = SwitchLaunchIdentity('Eden');
      eden.add('${'noise\n' * 10000}$start$end'.codeUnits, stderr: false);
      expect(eden.program, '01006a800016e000');
      for (final emulator in ['Ryubing', 'Astris']) {
        final identity = SwitchLaunchIdentity(emulator);
        identity.add('$start$end'.codeUnits, stderr: false);
        expect(identity.program, isNull);
        identity.add(
          '${'log\n' * 10000}Loader Start: Application Loaded: Smash ['
              .codeUnits,
          stderr: false,
        );
        identity.add('01006A800016E000] [64-bit]\n'.codeUnits, stderr: false);
        expect(identity.program, '01006a800016e000');
      }
    },
  );
}
