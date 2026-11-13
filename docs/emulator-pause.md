# Preserve emulator-native pause

2026-11-02. Follow-up to the [DuckStation correction](duckstation-pause.md).
The remaining desktop adapters also reconciled native pause against a permanent
"running" preference. A native pause could therefore be undone by Broomm.

## Implemented behavior

Every desktop adapter now distinguishes an explicit Broomm Resume from normal
gameplay polling. Native pause/resume survives polling and active controller
mapping publication. Pairing, Broomm's menu and assigned-controller disconnection
still enforce Pause. Explicit Play/Resume releases that gate. A release serial
preserves a quick gate/release even when no UI tick observed the intermediate
gate. Unknown/loading native state cannot acknowledge or consume a transition.

The original C transition helper is now `native/pause_transition.h` and is used
by DuckStation, both PS2 choices, Dolphin, melonDS, Azahar, PPSSPP, Ryubing,
Eden, both RPCS3 choices and Astris. RPCS3 already avoided steady Resume;
it now uses the same explicit-release and gate-reassertion rules. Each concrete
adapter retains its existing native API, readiness checks and actual readback.
Ryubing defers its F5 command until the owning window can receive it.
Its pause readback follows the live game window's title while AppKit hides
that window for pairing or the pause menu. The normal close path can resolve
the hidden game window and ask Ryubing to finish its own shutdown.
While the input gate requests Pause and the native title still reports
Running, the macOS bridge retries the hotkey at three-second intervals for
up to three minutes. Acknowledged Pause stops the retry. Explicit Resume
keeps its existing one-shot behavior.

Eden also pauses temporarily to apply controller socket changes. It resumes
after those changes only if it paused a running CPU itself. A socket change in
an already native-paused game leaves it paused. Socket confirmation precedes
Resume; a deferred command remains pending.

RetroArch uses the existing UDP command channel, through
`lib/src/retroarch_control.dart`. Normal polling observes its status. A toggle
requires a Broomm gate or pending explicit release, plus the same launched-game
identity and current session generation. Outstanding requests are not flooded;
a new explicit command revision can retry an unacknowledged transition. Native
bridge snapshots include an optional `pauseReleaseSerial` in protocol 4 so a
quick release is not lost between Dart polls. Older status fixtures default to
zero. No network protocol or RetroArch fork change is required.

No dependency, emulator source patch, system-wide setting or cloud-save format
changed. Android's external-app handoff has no Broomm pause interception.

## Verification at this revision

| Adapter | Implementation | Native execution for this correction |
| --- | --- | --- |
| DuckStation | Shared transition | ✅ Mega Man X4, pinned `0.1-12083-g00e299795`, ARM64 |
| PCSX2 / ARMSX2 | Shared transition | 🟡 C boundaries and universal compilation; PS2 gameplay pending |
| RetroArch | Explicit UDP transition | ✅ Released Broomm frontend `1.22.2 / 0.1.0`, original synthetic core |
| Ryubing | Shared transition, focus-aware F5 | ✅ Super Smash Bros. Ultimate, `1.3.3` |
| Astris | Shared transition, native backend setter | ✅ Super Smash Bros. Ultimate, `1.0.32+2398e7c80` |
| Dolphin | Shared transition, native core setter | 🟡 C boundaries and universal compilation; native gameplay pending |
| melonDS | Shared transition, Qt setter | 🟡 C boundaries and universal compilation; native gameplay pending |
| Azahar | Shared transition, guarded native readback | 🟡 C boundaries and universal compilation; native gameplay pending |
| PPSSPP | Shared transition, asynchronous core break/resume | 🟡 C boundaries and universal compilation; native gameplay pending |
| Eden | Shared transition plus socket-pause ownership | 🟡 C boundaries and universal compilation; native gameplay pending |
| RPCS3 ARM / Intel | Shared explicit transitions | 🟡 C boundaries and universal compilation; native gameplay pending |

The native checks confirm sustained native pause during ordinary polling and
active mapping/port changes, native Resume, gate pause/reassert/release, another
native pause afterward, quick gate/release and assigned-source disconnection.
Each process closes normally. RetroArch's fixture tests the actual released
frontend and Broomm session/controller bridge; its synthetic core is not console
gameplay evidence. Twenty targeted Flutter cases pass, including three new
RetroArch control regressions and existing session/UI/PlayStation cases. Three C
boundary scenarios pass normally and independently under ASan/UBSan. Analysis
and workflow lint pass. CI schedules the C checks and sanitizer checks separately.

These runs use copied reviewed emulator releases/resources, fresh disposable
profiles and read-only owner ROMs. The production validator accepts reviewed
locally re-signed bundles; a raw executable hash from before re-signing is not
substituted for that validator. The first Astris fixture stopped at that raw
hash check before launch; its corrected production-validation run passes. An
initial RetroArch fixture used Astris's disconnect encoding in the SDL fixture;
the corrected present-source mask passes without changing application behavior.

The old DS/3DS/GC/PSP and PS3 test media are no longer present in this checkout.
Their earlier integration evidence does not establish this correction's native
acceptance. Physical pads, visual input, Steam/gamescope, Linux/Windows runtime
and Intel-emulator execution remain separate verification. See the
[machine-readable evidence](emulator-pause.json) for exact source/artifact hashes
and observations.

## Build, reproduce and check

```sh
devbox run -- bash tool/build_bridges.sh
devbox run -- bash tool/check_sony_pause.sh
devbox run -- bash tool/check_sony_pause.sh --sanitize
devbox run -- flutter test --no-pub test/retroarch_pause_test.dart test/session_commands_test.dart test/game_session_screen_test.dart test/playstation_test.dart
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcrun clang \
  -dynamiclib -std=c11 -Wall -Wextra -Werror tool/fixtures/pause_core.c \
  -o build/native-pause-checks/pause-core.dylib
BROOMM_PAUSE_FIXTURES=/absolute/path/to/fixtures.json \
  devbox run -- flutter test --no-pub tool/check_emulator_pause_test.dart --reporter expanded
```

The historically named Sony C runner now tests the shared helper. Native
fixtures are opt-in and are not ordinary CI tests. Each manifest entry has
`id`, `release`, `rom` and `platform`: the reviewed release directory includes
its receipt/bundle/resources, and `rom` is existing compatible local media.
The supplied manifest examples/observations are private under
`.tool-cache/research/emulator-pause/`. RetroArch uses the compiled original
`pause_core.c` and a disposable `.bin` with arbitrary bytes. The current
multi-emulator fixture covers RetroArch/Ryubing/Astris; the separate DuckStation
fixture documents its BIOS/ROM prerequisites. These tests download nothing,
upload nothing and do not use computer-control tools.

Build after native tests have stopped:

```sh
devbox run -- bash tool/build_app.sh --release --portable --no-pub \
  --build-name=0.1.4 --build-number=1006 \
  --dart-define=BROOMM_RELEASE_VERSION=0.1.4 \
  --dart-define=BROOMM_RELEASE_TARGET=macos-universal
```

Quit Broomm and replace only the application with the
[current macOS build](../build/releases/Broomm-macOS-emulator-pause-fix.zip).
Launch a game, pause using its emulator's native menu/hotkey and leave it paused.
Then resume there, open Broomm with R3+Select, check pairing/Resume, and disconnect
an assigned pad. Do not reset profile/emulator settings. The build uses normal
production Application Support storage and is ad-hoc signed, not notarized.
Archive integrity and deep/strict signatures are verified again after extraction.

Retained logs are under `build/native-pause-checks/`; per-run native logs and
observations are below `.tool-cache/research/emulator-pause/native-*`. Remove
only disposable copied release/profile/core fixtures after their own processes
have exited. Do not remove the production data root or save-transfer backups.
