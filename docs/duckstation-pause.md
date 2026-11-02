# DuckStation native pause correction

The later [all-adapter correction](emulator-pause.md) expands this initial Sony
fix to the remaining desktop emulators. The scope below describes the initial
DuckStation milestone; use the newer build/evidence for current sources.

2026-11-02. The owner reports that pausing a PS1 game in DuckStation immediately
resumes it. The cause is Broomm's native bridge, rather than a DuckStation setting.

## Cause and behavior

The PlayStation bridge compared native pause state with Broomm's desired state
on each UI tick. During normal gameplay the desired state is running. Once a
previous resume was acknowledged, the bridge treated any later native pause as
a mismatch and queued another `CoreThread::setSystemPaused(false)`.

`native/pause_transition.h` now distinguishes a pending explicit Broomm resume from
steady gameplay. A pairing/menu/disconnect gate continues enforcing Pause.
Releasing that gate can issue Resume, with asynchronous acknowledgement and
without repeated queued requests. After acknowledgement, polling only observes
independent native pause/resume changes. Publishing active controller routes
again does not resume a native pause. An explicit Broomm Play/Resume after its
own gate still resumes the game.

The sampling worker publishes a monotonically increasing release serial before
clearing its desired Pause. Even if the UI tick misses a quick gate/release
pair while already paused, it still observes the explicit Resume request.

This small transition mechanism is shared by the existing Sony adapters
(DuckStation, PCSX2 and ARMSX2). It does not change other emulator adapters,
controller mapping, configuration, save formats or synchronization. No emulator
implementation code, library, service or dependency was added.

## Verification

- **Reproduced with the old bridge:** real DuckStation
  `0.1-12083-g00e299795`, macOS ARM64, Mega Man X4. The native pause test fails
  after seven seconds: pause expected `1`, observed `0` during gameplay polling.
  Its bridge log records the native test pause followed by Broomm's Resume.
- **Fixed real-emulator test:** the same executable/game passes. Checks retain
  native pause through repeated fresh samples and an
  active routing revision, retain native resume, enforce/release Broomm's
  pairing gate (including a quick gate/release), retain a subsequent native pause and pause on assigned-source
  disconnection. Shutdown is normal. Native pause actions invoke the same
  core-thread setter used by the frontend; no computer-use tools were used.
- **Three C boundary regressions pass**, independently with and without
  AddressSanitizer/UndefinedBehaviorSanitizer: native pause/resume, Broomm gate
  ownership, and asynchronous/unknown observations and missed UI gate ticks
  without command flooding.
  Both runs are scheduled independently in native macOS CI and retain logs.
- **Ten existing Flutter PlayStation/session-command cases pass**, including
  private configuration, BIOS, card/cloud round trips and command ordering.
  Static analysis is clean. Workflow lint passes.
- Universal SDL2/SDL3 bridge libraries compile and their signatures verify.
  The fresh application/archive and extracted application signature checks are
  recorded in the [evidence](duckstation-pause.json).

The native run uses a copied, exact-hash DuckStation bundle and copied BIOS in
a disposable profile. It only reads the owner's installed ROM. Original
settings, memory cards, save states and RomM saves are untouched. Two synthetic
SDL controllers exercise routing; no physical-controller or visual owner
acceptance is claimed. Native PS2 and Linux/Windows/Android execution were not
performed for this correction. Other native adapters have separate pause
implementations and are outside this fix.

## Reproduction and owner check

```sh
devbox run -- bash tool/build_bridges.sh
devbox run -- bash tool/check_sony_pause.sh
devbox run -- bash tool/check_sony_pause.sh --sanitize
devbox run -- flutter test --no-pub test/playstation_test.dart test/session_commands_test.dart
BROOMM_PAUSE_FIXTURE_SOURCE="$HOME/Library/Application Support/Broomm" \
  devbox run -- flutter test --no-pub tool/check_duckstation_pause_test.dart --reporter expanded
```

The integration fixture requires the pinned DuckStation already installed in
that data root, the owner's existing PS1 BIOS/profile and Mega Man X4 CHD. It
does not download anything. `tool/check_duckstation_pause_test.dart` lists these
explicit local prerequisites; it is a native integration fixture, not a default
network-free CI test. Test-only actions 4/5 request native Pause/Resume only
when the existing session-test opt-in is enabled. Ordinary Broomm launches do
not expose them.

Install the [updated macOS build](../build/releases/Broomm-macOS-duckstation-pause-fix.zip)
and launch a PS1 game normally. Pause through DuckStation's own menu/hotkey:
it should stay paused until resumed. Then open Broomm's controller menu with
R3+Select, resume and check controller disconnection/pairing normally. Replacing
the application does not replace the managed DuckStation installation or its
saved data. The local application uses production Application Support storage.
It is ad-hoc signed, not notarized.

Native evidence remains under `.tool-cache/research/duckstation-pause/native-*`.
Remove disposable fixture copies only after their child processes have exited;
retain their `bridge.log`, `broomm.log` and observations when diagnosing failures.
The owner data root is not a cleanup target.
