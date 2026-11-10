# Linux x64 RetroArch milestone — 2026-11-02

Current Broomm syncs only ordinary in-game saves. Save states remain local.
Earlier state-transfer observations describe their tested builds. See the
[current save contract](slotted-saves-and-ps3-iso.md#save-states-and-recovery).

The owner selected RetroArch first, then standalone Linux emulators. This adds
the first managed Linux runtime; it does not enable macOS recipes on Linux.
The earlier [audit](linux-managed-setup-audit.md) records the original gap.

## Implemented behavior

Linux x64 automatically selects `assets/setup/linux-x64/setup.json`. Emulator
Settings offers the existing explicit review/setup flow for RetroArch and its
nineteen platform routes: SNES plus the eighteen `retroSystems` entries. It
downloads Broomm/retroarch v0.1.0 and fifteen reviewed official Libretro cores.
No companion pack, JSON import, compiler or system emulator is needed. Standalone
Linux recipes and managed Linux ARM64 remain unavailable in this milestone.

The frontend is RetroArch 1.22.2, revision
`1b8917df23625bcf40b67ba6476d9bfb0d30dc65`, with SDL 3.4.0. Its archive SHA-256
is `5822d9c90cee8ef4af8a994c563bd426fcaa8ae70e0eda07eeb512f31cbadfbf`;
its executable SHA-256 is
`a6e405d589d423bbf566eaa760702dbe98dd179fe0cebeb16ebaba024d379339`.
The Linux manifest records all package/core hashes, native library metadata,
licenses and upstream URLs. The frontend includes upstream notices. Libretro's
individual core URLs are mutable nightly endpoints: changed upstream bytes are
rejected and require a reviewed recipe update, while verified installed copies
remain reusable. Broomm never silently adopts a new core or updates emulators.

Setup uses the existing Dart ZIP reader with private staging, entry/CRC/resource
validation and cancellation. Full package/file hashes and ELF architecture checks
happen during setup or explicit verification. Launch checks the bound file tree
and file metadata, including ctime, rather than hashing executable/core payloads
again. This is a local integrity cache, not protection against a privileged actor
who can forge files and metadata. Changed/missing/linked data requires verification
and preserves existing files and progress.

Each profile has private HOME/XDG, saves, states, firmware, cache and preferences.
The initial renderer uses RetroArch's SDL3 OpenGL context (`gl_sdl3`). The small
original C bridge is copied into a reserved owned runtime folder; its relative
preload path supports storage paths containing spaces. It resolves public SDL
3.4 APIs from the emulator's own runtime, discovers physical source identities
there and exposes stable virtual player ports. Trigger ranges are converted
explicitly; native logical-pad readback checks neutral/full/release. Pairing, both face-button swaps,
the menu chord, release gating and disconnect requests use the existing Dart UI.
Pause/resume uses identity-checked native RetroArch commands and preserves pauses
made inside RetroArch. No emulator implementation source or new runtime library
is added to Broomm.

The bridge prefers Linux Landlock ABI 3 or newer (normally kernel 6.2+) to restrict
filesystem mutations to the private profile, allowing writes to existing GPU,
audio and input devices. Kernels without that feature use the original C
adapter's user/mount namespace fallback, retaining the native PID/UID, a read-only
outside filesystem and a writable private root after dropping administrative
capabilities. The Thor's native filesystem/lifecycle checks pass; physical
RetroArch gameplay on this fallback is separate acceptance. Kernels without
either usable boundary fail closed and retain data. No
OS permissions, services or system emulator configuration are changed. A native
writer lock survives the launcher. Open emulator starts an independent no-game
window; Broomm neither hides nor watches it, and the native child retains locks.

GTK host interop preserves decorations and window geometry, forwards close and
termination requests to Dart, and offers a five-second native fallback if Dart
does not acknowledge. Recovery retains a pidfd, checks executable/profile paths,
UID, process birth and live lock ownership, then supports Show, graceful Close
and explicitly confirmed Force quit through the existing UI. Graceful Close is
checkpointed and sent once per native process, including after Broomm restarts:
RetroArch treats a second termination signal as a hard exit. Inspection
never opens/closes the coordinator inode, which would release the caller's own
POSIX lock. On Btrfs, `/proc/locks` uses the filesystem device while `stat` may
use a subvolume device. Recovery confirms the actual open file and its fdinfo
lock; it never accepts inode equality alone or treats failed inspection as empty.

## Native evidence and limits

Host: owner's CachyOS x86_64, kernel 7.3.0-4-cachyos, native Wayland. Development
used the checked-in Devbox/Flutter 3.47.0 environment with project-contained
rootless Nix/Devbox caches and the already provisioned host Clang. No OS package,
system service or global SDK selection was installed/changed. The existing
Broomm process, account data and partial Switch download were left running.
The owner authorized reusing only desktop connection settings in memory; the
test wrapper neither prints nor stores those values.

- All fifteen Linux cores load natively, report Libretro ABI 1 and return native
  library/version/extension metadata. This does not establish gameplay for each.
- The complete bundled recipe installs the frontend and all fifteen core packages
  through production validation and publication, using private public-archive
  caches. Normal setup uses their HTTPS sources.
- An original battery-backed NES NROM program runs in the real Mesen core. Native
  memory readback proves source input and live face changes reach the core.
  Menu/disconnect pause, independent native pause/resume, release gating and
  repeated launches pass. Actual window logs confirm Wayland hide/show behavior.
- A real 8 KiB `.srm` and a native state pass production capture, BROOMM upload,
  readback and explicit restoration against the in-memory RomM test server. Boot
  counters survive relaunch. This is not a write to the owner's RomM server or a
  claim of cross-device/core state compatibility.
- Independent no-game configuration starts, holds the native locks and releases
  them on ordinary native Quit. Production recovery targets the actual RetroArch
  writer; its first SIGTERM exits successfully and flushes the native save.
- Four kernel checks pass independently, including ASan/UBSan. Production host
  tests cover coordinator retention, stable recovery tokens, Show, one graceful
  signal, explicit force and invalidated handles; Btrfs receives a native check. A typed, OS-locked stop
  checkpoint prevents a second hard-exit signal after a launcher restart and
  preserves unknown/linked checkpoint data.
- All 474 Flutter tests pass on macOS. All 406 applicable Flutter tests pass on
  Linux, with 21 existing platform-specific skips. The affected setup/core suites
  pass on both. Analysis, formatting and workflow/ShellCheck pass.

Physical pads, Home evdev permissions, Steam Input, Steam Big Picture, gamescope,
fullscreen/compositor focus and visual acceptance remain owner/native checks.
Linux currently hides the emulator and restores the existing launcher window for
pairing/settings; it is not a GPU-rendered overlay. Three held-write regressions additionally cover overlapping renderer-ready publication,
retry and shutdown draining; the original overlapping `.pending` rename failure
is corrected without changing pause or save contracts. Native BIOS/save cases for
the other cores remain separate from their successful ABI probes and shared Dart
boundaries. Standalone Linux emulators, Linux ARM64, Windows and Android receive
no new emulator-runtime acceptance from this work. See [machine-readable evidence](linux-retroarch.json).

## Try it and reproduce

Close the older Linux Broomm normally first so it checkpoints downloads. Run the
new extracted `bundle/broomm` directly from the desktop session, outside Devbox,
to keep the normal `~/.config/broomm` data and Secret Service. Open **Emulator
Settings → RetroArch → Review setup → Start setup**, then play an installed RA
game. BIOS-dependent routes use the existing RomM provisioning flow. Pair using
L1+R1; hold Start to play; test R3+Select, native pause, face switching and
disconnect/reconnect. Please verify that Steam/gamescope restores the intended
surface. Exit normally and inspect cloud status before another device.

Developer checks (inside the Linux Devbox SDK, from the repo root):

```sh
bash tool/build_linux_bridges.sh
bash tool/check_linux_native.sh
BROOMM_NATIVE_SANITIZERS=1 bash tool/check_linux_native.sh
bash tool/ci/build_linux.sh --debug --no-pub
bash tool/check_linux_host.sh
flutter test tool/check_linux_retroarch_test.dart --reporter expanded
```

The last test requires a working desktop connection and the reviewed public ZIPs
under `.tool-cache/research/linux/`: `retroarch-linux-x64.zip` and
`cores/<id>.zip`. It generates its own NES media and private `integration-*`
profiles; it never needs owner ROMs/credentials. Use the existing approved native
compiler via child-scoped `BROOMM_LINUX_CC`/`BROOMM_LINUX_CXX` overrides when it is
not named clang-18. `tool/linux_desktop_test.py` is an opt-in SSH test helper;
reading a running desktop process's connection requires explicit owner approval.

Test logs and fixture observations remain in the project-owned cache. After all
their native writers have exited and locks are free, the corresponding
`integration-*` fixtures and public download caches may be removed. Do not delete
production `session.lock`/`writer.lock`, profiles, cloud recovery or downloads.
CI schedules Linux kernel/sanitizer checks independently and recovery adapter
checks on both build architectures; hosted results are still pending.

The November 5 checkpoint CI follow-up corrects the optional namespace backend's
capability probe: namespace creation alone does not establish mount permission.
[Ubuntu's documented restriction](https://documentation.ubuntu.com/release-notes/24.04/#unprivileged-user-namespace-restrictions)
can allow creation while denying capabilities inside that namespace. The fixture
independently checks a private mount operation before selecting that optional
case. Automatic confinement, outside-write/symlink rejection, process ownership
and capability-drop assertions remain mandatory when their backend is available;
production setup failures are not reclassified as unsupported observations.
The original failing run and correction are recorded in IMPLEMENTATION.md.

The delivered local packages are version **0.1.6 (1013)** with the official
update stream enabled for newer releases, production data locations and no
checkout binding. [macOS ZIP](../build/releases/Broomm-macOS-linux-retroarch.zip)
is 20,648,053 bytes, SHA-256
`4e33c654db8017e84b1223c368ce68e76512b9084231d63a57a590455529edde`;
it is universal, ad-hoc signed and not notarized.
[Linux x64 TAR.GZ](../build/releases/Broomm-Linux-x64-RetroArch-CachyOS.tar.gz)
is 11,247,709 bytes, SHA-256
`077de3c979303c15a71a6e6258fdda848ba2b5b0acc00db057ecf28e6c281f1f`.
The Linux artifact was built/checked on CachyOS with glibc 2.44; it is not an
Ubuntu baseline acceptance claim. Official CI still builds with its Ubuntu
24.04 compiler baseline. Both archives include source provenance, setup recipes
and precompiled Broomm interop, without games, emulator payloads, firmware,
credentials or owner progress. No commit, push or hosted run occurred.
