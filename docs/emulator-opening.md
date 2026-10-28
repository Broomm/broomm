# Independent emulator configuration launch

Updated 2026-10-28. **Emulator Settings → Open emulator** hands the no-game app to
the OS and returns after the launch request. Broomm stays visible and navigable.
There is no retained emulator process, readiness/exit poll, stdout subscription,
game-active flag, exit notification, automatic focus restoration or requirement
to close that emulator before quitting Broomm. Only an in-flight launch request
is finished during Broomm shutdown. Startup request failures are visible and
allow retry.

## Private data and OS handoff

Normal managed-profile resolution, existing native settings arguments and
private HOME/XDG/user paths are retained. No controller/game startup is run.
Complete macOS app bundles use `/usr/bin/open -n -a <exact bundle>` without `-W`,
with explicit child-only environment values. The portable melonDS copy lacks
bundle metadata and uses a detached process. OS launch requests use literal
argument arrays, not shell command strings.

The existing precompiled native writer guard acquires the coordinator and writer
locks before native settings writers initialize. A conflicting or linked lock
is rejected nonblockingly. Locks live inside the independent emulator process
until its native teardown; they do not keep Broomm alive or block read-only UI
navigation. Actions needing the same writable data still require that emulator
to close. The guard applies the same Dart-supplied private write policy through
the existing macOS sandbox facility because a Launch Services child does not
inherit a `sandbox-exec` wrapper. It also selects the private working directory.
PPSSPP's scoped preferences and Eden's Vulkan-probe handling remain in place.
No dependency, helper service, OS installation or system configuration change
is introduced.

## Azahar warning

Pinned Azahar 2126.1.2 [shows the direct-executable warning](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/citra_qt/citra_qt.cpp#L497)
when its [terminal heuristic](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/common/apple_utils.cpp#L9)
finds a parent other than PID 1. Its warning recommends `open Azahar.app` and
mentions missing camera functionality when started directly. The corrected
no-game action uses that bundle launch mechanism. A real native launch has
parent PID 1, making this exact warning condition false. This is not a camera
emulation test.

Gameplay's separately supervised controller/overlay launch is unchanged by
this no-game fix; its earlier direct-launch warning workaround remains there.
No arbitrary modal dialog dismissal is added to the configuration action.

## Verification and reproduction

Use the pinned Devbox environment and approved Xcode SDK:

```sh
devbox run -- flutter analyze --no-pub
devbox run -- flutter test --no-pub
devbox run -- flutter test test/emulator_configuration_test.dart test/open_emulator_test.dart --reporter expanded
devbox run -- env BROOMM_CONFIGURATION_SANITIZERS=1 flutter test test/emulator_configuration_test.dart --reporter expanded
devbox run -- bash tool/build_bridges.sh
devbox run -- flutter test tool/check_installer_guard_test.dart --reporter expanded
devbox run -- flutter test tool/check_setup_portability_test.dart --reporter expanded
devbox run -- bash tool/build_app.sh --release --portable
```

UI/model regressions verify no hide/show calls or game-session state, independent
navigation/shutdown, recoverable launch rejection and coalescing of a pending
request. Native fixtures verify Launch Services parenting, private writes,
rejection of writes outside the private profile and coordinator/writer locking.
The race case holds the production coordinator before starting the native
fixture; a linked coordinator also fails before its main function. Existing
installer-only regressions run independently. The guard also receives Clang
static analysis and a separate UBSan trap-mode fixture run.

The real-app check uses exact pinned Azahar 2126.1.2, PCSX2 2.8.2,
ARMSX2 nightly-20261023 and PPSSPP 1.20.4 archives in
`.tool-cache/research/setup-portability/`. It installs into disposable profiles,
checks parent identity and real writer exclusion, then closes only its own test
processes. A first experiment that waited five seconds for readiness failed on
cold Rosetta startup: timestamps showed the native constructor reached nine
seconds after launch. Production now has no readiness wait. The harness alone
waits up to twenty seconds to observe its native fixture. The failed test's exact
private process was identified, closed and confirmed exited.

No owner profile, game, credential or remote RomM save is changed by these checks.
Only these four actual no-game emulator launches are rechecked here. Other
emulators, camera use, physical controller input, gameplay and native
Linux/Windows/Android acceptance are not established by these macOS tests.
Do not delete live lock files. After fixture processes exit, disposable roots
and logs in `.tool-cache/research/emulator-opening/` and the private
setup-portability test installations may be removed. Preserve production data.

On macOS 27.0.1 / Xcode 27.1, analysis and all **421 Flutter tests** pass. The
four real no-game applications pass, as do four configuration tests under
UBSan trap instrumentation and the five existing native installer regressions.
Clang analysis reports no findings. Kernel lock observation in the integration
harness uses a separate read-only `F_GETLK` fixture: macOS `lsof` did not expose
the record lock, and acquiring it from the test would itself create contention.
The test probe and compiler are not shipped or required by users.

The current [macOS test build](../build/releases/Broomm-macOS-independent-emulator-launch.zip)
is **20,480,144 bytes**, SHA-256
`efc4bef497e693c297e4d52efd7770af77473101ce809519905f6ed017c9b4c4`.
It is a universal app with precompiled universal bridges, uses normal Application
Support storage, and passes ZIP integrity plus source/fresh-extraction
strict/deep/all-architecture signature and native guard readbacks. The local
package is ad-hoc signed and has development self-installation disabled;
official CI releases enable the normal updater. It includes no emulator, game,
firmware, credential or save payload. The [verification record](emulator-opening.json)
retains exact hashes, host and remaining acceptance limits.
