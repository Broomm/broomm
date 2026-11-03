# Setup and content throughput — 2026-11-02

The owner confirmed Linux RetroArch gameplay but reported all cores installing
from one card, slow emulator downloads, and long Dolphin/Eden verification.
Eden later completed, then appeared stuck installing Smash updates/DLC without
opening an emulator. These are distinct phases: Eden's NCA installation is Dart
file preparation, so it does not open Eden. A game waits for its content task.

## Cause and correction

The old setup checked a downloaded archive, hashed every extracted file, copied
the application, hashed those files again, and recorded launch metadata using
thousands of UI-isolate filesystem operations. Eden has 2,769 regular files and
372 links; Dolphin has 3,018 files and five links. Linux hashing started a fresh
isolate per file. Metadata validation also repeatedly walked each file's parent
path through the Flutter event loop. Owner logs show Eden's final verification
phase lasting about 197 seconds; its archive checksum took about 0.68 seconds.

Downloaded reviewed packages now receive one archive checksum, then safe
inventory/link/size checks and required ELF architecture checks. They do not get
another full file-content scan. Folder imports without verified package bytes
retain reviewed fingerprints. macOS signature preparation/seal checks and the
installation's executable identity remain. Linux launch metadata and structural
inspection run in background workers; ordinary launch does not rehash the app.
Copying an AppDir also runs outside the UI isolate. Setup logs phase durations.

The same measured UI I/O scheduling issue affected non-ROM payload downloads.
Default emulator archives, application updates, Android APKs, RomM firmware,
save/state assets, RomM posters and SteamGridDB images now use background I/O.
Game/add-on RomM content already did. Token refresh and account association stay
on the calling side; only a current access-token snapshot enters worker memory.
Small API metadata and uploads retain their current routes. Explicit HTTP clients
and HttpOverrides retain their transport behavior rather than being replaced.
No dependency, OS package, network setting or global emulator setting was added.

Cancellation waits for worker completion, closed-file acknowledgement and exit.
Progress is bounded. Callback failures cancel and drain the operation. A missing
acknowledgement retains private data; setup/content owners retain their session
lease when an uncertain worker could affect recovery. Save-download workers write
only a unique private directory: an uncertain directory is never imported or
removed. Existing publication/checkpoint/ownership and archive path protections
remain in place.

## RetroArch scope

Each platform review filters the recipe to the frontend plus that core, including
imported setup recipes and Home's missing-emulator flow. A second core reuses the
existing executable and retains other cores. macOS's legacy separate Snes9x file
is optional when installing another platform and can be installed later. A
frontend configured for GB can open its no-game settings without SNES. A platform
without its core stays unconfigured. Already installed extra cores are retained.
Explicit developer bulk setup still accepts a complete recipe.

## Switch content

Eden's native-content extractor previously streamed and hashed multi-gigabyte
NCAs on the UI isolate, with no byte feedback. It now runs on a background worker,
checks the native content ID during its initial stream, reports byte progress,
and returns its inventory only after closure. It no longer rereads each freshly
written NCA just to recalculate the same hash.

Immutable content uses per-profile metadata-bound verification receipts, with
absolute file identities, size, modification/change times and mode. New content's
first verified hash is propagated across awaited OS copy/rename operations with
source/destination checks; unchanged files avoid repeated full hashes. Missing
or changed metadata triggers a fresh hash. Old installations populate the receipt
on first verification. The generation inventory retains structure/link checks;
external changes still cause the existing ownership conflict rather than silent
overwrite or deletion. Journal/readback ordering is unchanged. Saves, console
accounts and writable progress are outside this cache. No native emulator fork,
key export or remote RomM write is required.

## Measured native Linux results

Read-only native Flutter probes use the same disposable Eden/Dolphin AppDirs.
Times are milliseconds; warm filesystem state and other host activity apply.

| Phase | Eden before | Eden after | Dolphin before | Dolphin after |
| --- | ---: | ---: | ---: | ---: |
| Extracted application verification | 10,620 | 148 | 9,858 | 114 |
| Record launch metadata | 23,319 | 316 | 29,384 | 381 |

Fresh setup, including actual official network downloads, extraction and
publication: **Eden 7,965 ms**, **Dolphin 13,221 ms**. A separate native check
installs NES/Mesen, then GB/Gambatte: exactly those two cores exist and the
frontend executable modification time is unchanged. These are native GTK
measurements, not a Dart CLI inference. Firmware/network conditions can differ.

The first real-content experiment used the owner's local Smash base, update and
99 DLC files, copied into a separate test profile on the same Linux host. All
100 packages and 203 NCA units installed successfully. Before the content-receipt
correction, staging took 64,319 ms and staging/application took 164,314 ms. Keys
stayed on the Linux host; no production profile, save or RomM object was changed.
With metadata receipts, initial staging takes **34,850 ms**, first staging/apply
**65,757 ms**, and a second application of unchanged content **4,426 ms**. The
full second timing run including that repeat is 70,183 ms. Both initial native
experiments use the same 100 packages and 203 units; filesystem cache/load varies.

The native game test then exposed three Linux launch defects: Eden selected the
generic cwd/user portable folder instead of the configured XDG profile; its
Wayland recommendation dialog blocked boot; and console logging was disabled,
so the existing bounded loaded-title parser never received the native ID.
Eden now launches from its private HOME (including Sharun's cwd/preload settings),
sets the supported hide-warning preference without forcing a graphics backend,
and enables POSIX console output to stderr. No extra console window is opened.
All old files remain in place. Native Smash now passes in nine seconds: loaded
title `01006a800016e000`, initial pause/readiness, one virtual controller connected,
resume, pause and normal shutdown. Real physical input/gameplay remain owner
acceptance. The native configuration guard/startup check passes independently.
The test alone restores host driver discovery hidden by Devbox's XDG paths;
production desktop/network settings remain unchanged.

Primary pinned upstream contracts: [frontend startup and backend warning](https://git.eden-emu.dev/eden-emu/eden/src/tag/v0.2.1/src/yuzu/main_window.cpp),
[warning/console keys](https://git.eden-emu.dev/eden-emu/eden/src/tag/v0.2.1/src/qt_common/config/uisettings.h),
[UI category parsing](https://git.eden-emu.dev/eden-emu/eden/src/tag/v0.2.1/src/qt_common/config/qt_config.cpp),
and [POSIX console output](https://git.eden-emu.dev/eden-emu/eden/src/tag/v0.2.1/src/yuzu/debugger/console.cpp).
These are source audits and configuration, not copied emulator code.

## Verification and owner walkthrough

Portable regressions cover: drain-before-return cancellation and missing writer
acknowledgement; verified-package structural checks versus folder fingerprints;
one-core recipe selection and sequential shared-frontend installation; no-game
configuration without SNES; successful/cancelled Eden inventory publication;
metadata ties across different paths, restart, outside writes, missing/linked
files, native ownership and interrupted journal recovery. Native Linux and macOS
suites remain separate from Windows/Android device acceptance. No native bridge
or ABI changed in this follow-up.

1. Close the old app normally. Extract the Linux preview in a new folder and run
   `bundle/broomm`, retaining `lib/` and `data/`. The macOS preview replaces only
   the app bundle. Existing production data stays in place. Previews intentionally
   disable application updates until a regular CI build replaces them.
2. In Emulator Settings, review/confirm one RetroArch platform. Only its core
   becomes ready. A second platform reuses the frontend; no other core downloads.
   Existing extra cores remain installed. Optional Reset all emulators retains
   saves, states, pending cloud progress and game content.
3. Set up Dolphin/Eden. Compare phases and the duration logs. Ordinary downloaded
   setup should not scan every application file's contents.
4. On Smash → Options → Download Updates and DLC, observe byte progress during
   large content preparation. Wait for confirmed completion, then Play. Retry
   after cancellation must preserve prior content and progress. Unchanged content
   should avoid repeated large-file scans; old content can require one migration
   check. Physical input/Steam/gamescope/gameplay remain owner verification.
5. Delete only test application archives/extracted apps to clean up a preview.
   Keep production game/progress/recovery directories and lock files. Disposable
   investigation fixtures live under the project `.tool-cache/research/` trees.

Run checks in the project Devbox environment:

```sh
devbox run -- flutter --suppress-analytics test --no-pub
devbox run -- flutter --suppress-analytics analyze --no-pub
```


Final validation: **508 macOS tests** and **438 Linux tests** pass; Linux retains
22 existing platform skips. Analysis, required Dart formatting and workflow/shell
lint pass. The native nine-second Smash test verifies loaded identity, virtual
controller assignment, resume/pause and normal shutdown; it does not establish
physical-controller gameplay. Windows/Android native execution remains pending.
Completed disposable emulator/content profiles and copied keys were removed
only after their writers exited. Production accounts, games and saves were kept.

- [Linux x64 preview](../build/releases/Broomm-Linux-x64-setup-speed-eden-preview.tar.gz):
  normal app entry point, complete native dependency audit, archive readback and
  production updater extraction/executable-mode checks pass. Also extracted at
  `~/Downloads/Broomm-Linux-setup-speed-eden-preview/bundle/broomm` on the test host.
  Built on CachyOS; official Ubuntu/other-host CI remains separate.
- [macOS preview](../build/releases/Broomm-macOS-setup-speed-eden-preview.zip): current
  universal sources, source/fresh-extraction deep/strict/all-architecture code
  signatures and archive/native/asset readbacks pass. Ad-hoc signed, not notarized.
- [Exact test, source, timing, archive and signature record](setup-throughput.json).

Both previews identify as `0.1.7-dev` and disable application updates until a
regular CI build is installed. No commit, push, tag or release was created.
