# Linux ARM64 standalone support audit — 2026-11-04

**Deferred — 2026-11-05:** the owner requested a release checkpoint and moved
the next milestone to [root-backed Android access](android-installation-and-saves.md#next-milestone-root-backed-storage-access).
Retain the implemented ARM64 packages, page-size selection, native confinement
and input/display-preference fixes. Installation and fixture results below do
not resolve Thor's Eden startup/shutdown failures, Azahar dual-screen SIGABRT or
melonDS physical window-width report. Those cases remain open in the
[gameplay investigation](thor-gameplay-investigation.md). No custom Eden build
is authorized, and no Android root implementation is claimed here.

## Why the platform cards are missing

The bundled Linux ARM64 recipe now includes RetroArch, separate Armada
DS/3DS entries, Dolphin, Eden, DuckStation, ARMSX2, RPCS3 and PPSSPP.
These entries apply to every Linux ARM64 host; no Armada distro detection is
required. Each package has its own ARM64 executable inventory and native hook
metadata. Existing desktop firmware, add-on and cloud-progress adapters retain
their private profile contracts. This does not establish performance or title
compatibility on every ARM device.

| Console | ARM64 package selected | Current native evidence / remaining acceptance |
| --- | --- | --- |
| GameCube / Wii | [Dolphin 2609-166 / d182533d363e](https://dolphin-emu.org/download/) ARM64 AppImage | 🟢 Install/two profiles and GC/Wii native CPU-session lifecycle pass on Thor, including all four Wii modes. 🟡 Physical gameplay remains separate. |
| Switch | [Eden 0.2.1](https://git.eden-emu.dev/eden-emu/eden/releases/tag/v0.2.1) aarch64 Clang-PGO AppImage | 🟡 Recipe and pinned static SDL2 table initialize on Thor. Existing firmware, keys, DLC, updates and save adapters are reused; native game/NCE acceptance remains. |
| PlayStation | [DuckStation 0.1-12083](https://github.com/stenzek/duckstation/releases/tag/v0.1-12083) ARM64 AppImage | 🟢 Install/two profiles and native CPU-session lifecycle pass on Thor. Private BIOS and memory-card adapter reused; 🟡 physical gameplay remains. |
| PlayStation 2 | [ARMSX2 nightly-20261031 / cb78946d6e](https://github.com/ARMSX2/ARMSX2/releases/tag/nightly-20261031) | 🟢 4K install/two profiles and native CPU-session lifecycle pass on Thor. Kernel page size selects 4K/16K packages, executable inventories and symbol maps. 16K selection is tested, not native-executed on this 4K host. |
| PlayStation 3 | [RPCS3 0.0.42-20031 d08d568d](https://github.com/RPCS3/rpcs3-binaries-linux-arm64/releases/tag/build-d08d568d5edf4f21508d9b8e471197e6d6f499ad) | 🟡 Recipe, SDL3 dispatch and native status/progress symbols initialize on Thor. Firmware/package/cloud adapters reused; game performance is separate. |
| PSP | [PPSSPP 1.20.4](https://github.com/hrydgard/ppsspp/releases/tag/v1.20.4) anylinux aarch64 AppImage | 🟢 Install/two profiles and native PSP2048 lifecycle pass on Thor. Existing native debugger pause, memory-stick and cloud adapters are reused; 🟡 physical gameplay remains. |

ARMSX2's stable 2.8.4 release has Android APKs rather than these Linux packages,
so the pinned Linux nightly is explicit in the card. `getpagesize()` selects the
running kernel variant. Both builds retain the same PS2 profile/card data;
build hashes continue to isolate incompatible save states. An installed build
from the other page size remains recognized but cannot execute until the
matching setup is installed. A page size with no reviewed package produces an
actionable error only when that emulator is selected.

### ARM64 controller binding

RPCS3's SDL3 exports use ADRP/LDR/BR; PPSSPP's SDL2 uses a balanced frame prologue
around ADRP/LDR/BR. The previous decoder recognized only the MOV-to-X16 variant
used by the Armada packages. The decoder now matches these complete reviewed
forms from the export entry and validates every participating register. It
never scans beyond a return/jump into an adjacent export. Fixtures cover direct,
framed and MOV stubs plus wrong-register, broken-stack and adjacent-export
rejections. They passed natively on Thor with strict Clang 18 warnings.

Dolphin, DuckStation, ARMSX2 and RPCS3 report SDL3 3.4.16/3.4.14 as pinned;
PPSSPP reports SDL2 2.32.8. Eden's stripped static SDL2 2.33.0 uses the inspected
`0x2209dd8` dispatch table. All six native processes remained alive during
isolated startup, with private writes active and the matching runtime bound.
RPCS3 initializes its controller subsystem when a game starts, not on its empty
main window. These probes used child-only X11 and disposable profiles. No live
library, console identity or progress was modified.

Local Flutter analysis and 64 related setup, upgrade, PlayStation, PSP,
firmware and PS3 add-on regressions passed. Those include official package to
inventory correspondence, 4K/16K selection, alternate-build recognition,
wrong-page execution rejection and unchanged private save identities. Native
installation/lifecycle execution is recorded below when completed; compilation
or recipe validation alone is not gameplay acceptance.

### Production installation and native lifecycle checks

The production `ManagedEmulators.install` workflow installed all six exact
AppImages from its normal download cache. ELF/inventory validation and private
publication passed without package overrides. Two independently resolved
profiles used the same executable and different writable roots. Pair resolution
took Dolphin 3,727 ms, RPCS3 580 ms, DuckStation 522 ms, PPSSPP 3,961 ms, Eden
3,246 ms and ARMSX2 408 ms on this host. These are profile preparation times,
not gameplay performance or network-download speed.

The actual `GameSession` then passed five native cases: GC, Wii, PS1, PS2 and
PSP. Original tiny console CPU loops and public PSP2048 exercised initial native
pause, two test sources, live face remap, native user-pause preservation,
R3 + Select, disconnect/rejoin routing and normal shutdown. Wii applied and
read back all four layouts. These use the emulator's real SDL/Qt/debugger
runtime and Broomm's test virtual sources; they do not replace owner-performed
physical controller, gyro, title gameplay or Gaming Mode acceptance.

RPCS3's real headless firmware importer installed the reference PS3UPDAT.PUP
(206,197,916 bytes), and `liblv2.sprx` readback matched after private publication.
The native importer shim compiles under fortified Clang headers and explicitly
rejects incomplete marker writes. A host Python abort fixture confirmed the
expected marker/status and the closed-stderr failure status independently.
The original firmware-free CPU experiment first lacked its overlay font and
then the firmware prerequisite; neither failure was counted as game success.
A directory left by that failed disposable boot was preserved under held writer
and session locks before firmware was copied to a fresh target.

Exact package inventories/maps are versioned. Full setup/native logs and
disposable profiles remain in the Thor project under
`.tool-cache/arm64-standalone/`, with local captures under
`.tool-cache/research/linux-arm64-standalone/`. No production progress was copied
into those tests or replaced by them. Test BIOS/firmware copies remain private
and are not in the application or repository.

### Final build and remaining runtime limits

The current sources build as a Linux ARM64 release in the Thor's project-local
Devbox environment. The first link mixed Flutter wrapper GTK 3.24.52/Pango
1.57.1 with the project's GTK 3.24.43/Pango 1.52.2. Reusing the CI native-tool
isolation approach with the already provisioned Clang/linker fixed that local
SDK issue; no OS package was installed or host SDK selection changed.

Packaging now normalizes all ELF paths before executing the process-helper
check. Otherwise the helper can resolve the development libc through its old
RPATH while using the host interpreter. Native bundle regressions pass both
traversal orders, helper-only dependency normalization, relocation, rejected
non-executable helper, rejected missing dependency and rejected SDK interpreter.
The complete ARM64 bundle has no Nix loader/dependency paths and all its bundled
setup assets match the source inventories.

RPCS3's Basic Water game-session check did **not** reach paused/running state on
this Thor. The same private configuration stopped in native `starting` state
with production LLVM settings and without Broomm's injected bridge. That
comparison does not establish an upstream defect or general PS3 incompatibility;
it leaves this title/host startup case unresolved. Package setup, SDL binding
and real PUP installation pass, but PS3 game/controller acceptance is not green.
The Switch CPU experiment stopped at Eden's explicit missing-decryption-keys
prompt. No existing console keys were exported for this check. Eden game/NCE,
updates/DLC and cloud round trips on the Thor require a configured owner game;
these results do not turn the pre-existing shared adapters into new native
acceptance claims.

A current Linux preview is on the Thor at
`~/Downloads/Broomm-Linux-arm64-standalone-preview/broomm`, alongside the running
installation. Close Broomm before launching it; it uses the normal production
data location. No existing application bundle was replaced while running.
The local archive is `build/releases/Broomm-Linux-arm64-standalone-preview.tar.gz`
(SHA-256 `f399382bf6453407ea2465ff5f454c1874cfce1a463d9a442524e6914990718f`).
A current universal macOS preview is
`build/releases/Broomm-macOS-linux-arm64-support-preview.zip`; deep/strict
signature verification on the built and freshly extracted app, ZIP integrity,
and all ARM64 setup asset readbacks pass. Both are `0.1.14-dev` previews, not a
new GitHub release. Physical and Gamescope acceptance remain owner testing.

## Thor archive failure

The owner's Thor is Armada `20261010.c3d178c`, aarch64, kernel `7.2.6`, 4 KiB
pages. Both Armada packages downloaded and passed package verification. Azahar
then failed in 191 ms and melonDS in 208 ms during extraction. The native process
supervisor required Landlock ABI 3 before executing the AppImage; its failure
returned status 73 without an explanatory diagnostic. The Thor kernel's Landlock
query returns `ENOSYS`, and its active LSM list is only `capability`. A recent
kernel version therefore did not establish the feature's availability.

The same requirement appears in the injected SDL/RetroArch bridges, so fixing
only extraction would leave game launch broken. Runtime availability must be
checked, with the same storage ownership/lifecycle rules on either backend.

### Alternatives and selected implementation

- **Landlock:** retain the existing preferred backend, which needs no process
  wrapper and does not change the emulator PID or display context.
- **Existing bubblewrap:** a child-only probe succeeds on the Thor. Using it as
  the production fallback would add an external runtime prerequisite and wrapper
  process/identity behavior to session supervision. It is not selected for the
  application.
- **Direct kernel namespaces:** use unprivileged user/mount namespaces inside
  the existing C interop, keep the original PID/UID/GID, make the inherited mount
  tree recursively read-only, then enable writes only for the private root.
  Drop namespace capabilities and set no-new-privileges before provider code
  runs. This avoids a new shipped runtime dependency, but needs native checks
  for filesystem escapes, process/lock ownership, devices and emulator startup.

The native write policy now contains the namespace fallback for missing/old
Landlock. Failure remains closed; it does not silently run unconfined. Archive
failures now include the kernel-policy error in their diagnostics. No root,
system package, service, kernel setting or global mount table is changed.
See Linux's [mount attributes](https://man7.org/linux/man-pages/man2/mount_setattr.2.html),
[user namespaces](https://man7.org/linux/man-pages/man7/user_namespaces.7.html)
and [capability semantics](https://man7.org/linux/man-pages/man7/capabilities.7.html).

A disposable kernel probe on the actual Thor confirmed private-file writes,
blocked outside creation/truncation and symlink escapes (`EROFS`), permitted
`/dev/null` I/O, dropped capabilities and denied remounts. The original parent
mount table and outside file remained unchanged. This probe is **not** acceptance
of the compiled Broomm helpers or emulator launch.

The pinned, development-only `tool/native-linux` Devbox environment provides
Clang 18.1.8 and X11 headers for native testing on image-based hosts without OS
packages. Bootstrap tools and all Nix/Devbox caches live in the isolated Thor
project `~/Projects/broomm-thor-fix/.tool-cache`; none ships with Broomm.

### Native follow-up and installed preview

After reconnecting, the affected RetroArch/SDL2/SDL3 bridges and native process
supervisor compiled on the Thor with Clang 18.1.8 and `-Wall -Wextra -Werror`.
The kernel fixtures passed automatic fallback and direct namespace confinement,
outside creation/truncation/removal, symlink escape rejection, capability drop,
denied remounts, stable PID/UID/GID, and unchanged parent mounts. Process fixtures
passed writer exclusion, normal completion, cancellation and adopted-daemon
drain. SDL dispatch and SDK control identity/framing fixtures also passed.

The initial full development build stopped in the installer shim
because Nix's fortified headers warn about two previously unchecked marker
writes. It was not counted as a successful full build or suppressed by relaxing
warnings. The first check compiled only the affected components. The standalone
follow-up checks both marker writes explicitly and fails an incomplete marker
instead of accepting an unconfirmed importer teardown; the complete native build
then compiles with the same strict warnings. A separate host-loader/Nix-libc mismatch in the test tooling was
corrected by stripping development RPATHs and using Armada's native interpreter
for the preview binaries; those tools are not runtime dependencies.

The exact reviewed AppImages then ran through the compiled supervisor **outside
Devbox**: melonDS extracted successfully in **0.370 s** (236 files), Azahar in
**1.577 s** (2,574 files), with no stderr. Both expected entries and AArch64 ELF
executables were present. Both launchers ran their supported `--help` command
with the new injected private-write policy, recorded configuration mode active,
and exited zero without forced termination or stderr. These are real extraction
and CLI startup checks, not game/input/rendering acceptance. No DS/3DS raw ROM
was discovered in the Thor's usual installed-content paths for a gameplay check.

With Broomm closed and both session/writer locks held, four components in
`~/Applications/Broomm/lib` were replaced atomically and read back by hash:
`broomm-native-run`, `broomm-sdl2.so`, `broomm-sdl3.so` and `broomm-retroarch.so`.
The originals and replacement hashes remain in
`~/Applications/Broomm-native-before-armada-fix-20261104T212008Z`.
The application version remains 0.1.14; this is a local native preview, not a
newly published GitHub release. No live emulator settings, saves, installed
games or firmware were changed. Diagnostic copies and logs remain under ignored
local `.tool-cache/research/thor-armada/` and the isolated Thor project.

To test, reopen the same Broomm/Steam shortcut and retry **Setup** for both Armada
cards. Expect extraction to complete and the normal setup publication/default
selection. Then test game launch, controller pairing, top/bottom views, touch,
overlay pause and normal close. **End-to-end UI setup and physical dual-screen,
controller and gameplay acceptance remain owner verification.** Native Linux x64
execution of this correction also remains a separate check.

For rollback, close Broomm and all its emulators, then restore those four backed-up
files to `~/Applications/Broomm/lib` with their original names/modes. Do not clear
profile data or progress. The isolated `~/Projects/broomm-thor-fix` toolchain and
fixtures may be removed once all test children have exited and no further native
checks need them; keep the native backup until the new flow has been accepted.

Analysis and 27 setup/managed-emulator Flutter regressions pass on macOS. The
current macOS preview was rebuilt and its archive/checksum and extracted deep,
strict code signature verified. These checks do not verify the changed Linux C
helpers. The separate Thor native results above establish the actual Linux
checks performed. A full packaged Linux app/release build was not produced by
the local native-component replacement.
