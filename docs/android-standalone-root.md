# Android standalone root access

2026-11-08. RetroArch's eighteen platform routes/fifteen cores completed the
Thor acceptance recorded in [the core evidence](android-retroarch-cores.md).
PR #4 merged as `eb6fc60`. The owner authorized starting the standalone apps
after that milestone, with the existing two Thor accounts and normal ADB UI
control. This document separates implemented discovery from proposed save writes.

## Implemented: PPSSPP memory-stick inspection

The existing **Emulator Settings → Inspect root access** action now includes
PPSSPP memory-stick discovery for Android user 0. It reads the selected
package's native `files/memstick_dir.txt`. It never changes that selection,
creates a save connection, or reads game/configuration contents.

For **App Private Data**, discovery accepts only
`/storage/emulated/0/Android/data/<selected-package>/files`. It checks that
this directory and `/data/media/0/Android/data/<selected-package>/files` have
the same device, inode, owner, group, permissions and SELinux label in the
command's root mount namespace. It verifies a regular, singly linked
selection file and initialized `PSP/SYSTEM/ppsspp.ini`, with the selected
package's ownership and corresponding labels. Linked paths, changed
observations, incomplete responses and unavailable files fail visibly.

A different native memory-stick selection is reported as **another location**.
Discovery does not follow that path or display its potentially sensitive URI.
There is no fallback from a failed private-path check to an assumed shared
folder. Inspection retains the existing 30-second deadline, output limit and
cancellation; package identity is checked before/after it. Other emulators
keep their existing inspection behavior.

Use the normal PPSSPP launcher, finish first run, wait for the menu and choose
**Exit** before inspection. On the fresh Thor install, selecting **Skip for now
(Use App Private Data)** wrote the native selection, but exiting showed
PPSSPP's settings-save failure and did not create its PSP directories.
Opening PPSSPP again created them; its next normal Exit saved `ppsspp.ini`
and `controls.ini`. This is observed initialization behavior, not permission
to create or repair those files as root.

The regular official **PPSSPP 1.20.4** APK was installed through Broomm and
Android's installer: 45,448,397 bytes, SHA-256
`dd702a31270ecd68db37afee311d6efe08b1d4da9601d2750ce1a73bbd316c3f`.
On the Thor (Android 13, user 0, Magisk 31.1), its app UID was 10135.
The selected folder and media mirror were device 65038/inode 28074,
UID 10135/GID 1078, mode `2770`, with matching `media_rw_data_file` categories.
Native files used mode `660`; the internal selection used mode `600` and the
`app_data_file` label. These observations are not constants for other devices.

The fixed production script passed a direct read-only Thor check. Build **1107**
from PR #5's successful normal CI run also passed the complete in-app diagnostic:
**Read-only inspection completed**, the verified private path and the explicit
root-sync limitation were visible. Hashes of the selection and `ppsspp.ini`
were unchanged across each inspection. The stable-key upgrade retained Broomm's
UID and exact emulator settings. Both saved accounts restored through the normal
profile chooser without a password; the device was returned to the owner profile.
No credentials were exported or migrated.

Gold, other native selections/devices and the new save-writing route require
their own native acceptance. Existing connected-folder save support is separate;
PPSSPP root save synchronization is **not implemented** by this increment.
See the [revision, APK and device receipts](android-standalone-root.json).

## Native test seed and preservation

Broomm's normal Store downloaded **LocoRoco**, RomM 5938/platform 11. Its
528,029,604-byte CSO has SHA-256
`801662c4390a584600f59de0f14fdf8c69ed2b0c27b0f917b3e26ece87bb39e7`.
The existing bounded PSP reader verified `DISC_ID=UCUS98662`, revision `1.00`,
from the native SFO. A separately owned test copy in PPSSPP's private external
files, with native UID/GID/mode/label, booted through the native file-URI action.
This was not Broomm's content-URI game session or a cloud/account round trip.

Native touch reached the tutorial with eight LocoRocos and created three
`.ppst`/`.jpg` pairs. Slot 3 then loaded through PPSSPP's menu into the retained
tutorial location; held touch R moved/tilted the world. Android Back opened the
native menu, **Exit to menu → Exit** completed normally and the six files kept
their exact bytes and metadata. The two zero-byte `.nomedia` files retained
their content/inodes/ownership but refreshed timestamps at native startup. The
first test-harness comparison rejected that timestamp difference; the retained
before/after records establish its cause. No ordinary in-game save was produced:
`PSP/SAVEDATA` contained only `.nomedia`.

Raw Linux input and Android gamepad-event experiments did not establish physical
controller behavior. Native touch/Back observations are separate from physical
pad acceptance; no input mappings or system preferences were changed. These
unassigned native seeds remain outside both profiles and remote PSP history.

Build 1107 also passed a read-only RetroArch preservation audit: 49 earlier
progress files, both five-file Dreamcast sets, 19 managed native files, 13
original native files, four retained failed-test VMUs, fifteen core hashes and
eighteen independent bindings remained intact. Session/swap/removal journals
were absent. The roster gameplay/account/offline acceptance remains PR #4's
build-1104 evidence; this audit does not repeat or broaden those playthroughs.

The complete Flutter suite passed **727 tests**, with one existing host skip and
no failures; analysis, JVM inspection regressions and Kotlin bridge compilation
passed. CI run `42478373175` passed all checks and five target packages for
`a8a4361`. Local macOS packaging verified ZIP integrity, all seven universal
Mach-O files and source/extracted deep/strict signatures. These compile/package
checks do not establish standalone root save synchronization.

## Next save-writing increment

Keep Dart's existing session/journal/cloud decisions and PSP savedata ZIP
contract. A concrete PSP native file adapter must restrict ordinary data to
this game's verified disc-ID folders under `PSP/SAVEDATA`, respect owned
static DLC, and handle `PSP/PPSSPP_STATE` separately by exact APK/ABI and disc
revision. Do not route PSP through a pretend Libretro core.

Audit the full writable memory stick before selecting the swap boundary. In
1.20.4, native load undo uses a global `PPSSPP_STATE/load_undo.ppst` with its game
association in `ppsspp.ini`; per-slot save undo has game-prefixed files. A
game-prefix-only state swap therefore cannot establish profile isolation when
load undo is enabled. It defaults off on Android but remains user-configurable.
Preserve native preferences and standalone progress, including this auxiliary
state, rather than deleting or silently assigning them to a Broomm account.

Preserve native GID, setgid directory bits and media-file labels. Revalidate
the selected root/package at each effect; retain original/working/captured
bytes and recover interrupted exclusive publication. Existing 512 MiB total,
256 MiB/file and 4096-file bounds still apply. File transfer must remain
streamed/bounded rather than putting game saves in Binder payloads.

PPSSPP's normal **Exit** destroys its activity and joins native emulator,
render and worker threads, but the Thor keeps its Java process cached.
An absent activity, cached process, Back action or bare `onDestroy end` line
cannot establish writer closure. The release APK logged the complete finish,
`NativeApp.shutdown()` and destruction sequence, then reused its PID when
opened again. Backend recreation can also destroy an activity without native
shutdown. A future closure mechanism needs fresh, process/package-bound
positive evidence, handling lost logs, recreation, restart and abnormal exits.
No process was killed or force-stopped for these checks. Preserve RetroArch's
existing process-exit adapter.

The next implementation order is a PPSSPP-specific writer boundary, a durable
profile/private-memory-stick handoff covering auxiliary writable data, streamed
file publication/recovery, then the two-account ordinary-save/state/cloud round
trip. These remain implementation work; no new dependency or owner decision is
needed for the completed read-only increment. Physical controller verification
can be collected separately without blocking that work.

## Reproduction and cleanup

```sh
devbox --config tool/android run check-root-inspection
devbox --config tool/android run check
devbox run -- flutter --suppress-analytics test --no-pub test/android_root_inspection_test.dart
devbox run -- flutter --suppress-analytics analyze --no-pub
```

The JVM fixture exercises production parsing/subprocess bounds/cancellation,
private/shared observations and changed identity, unsafe permissions, extra
links and incomplete responses. Kotlin bridge compilation is not an APK or
Android runtime execution. Local read-only device records are under
`.tool-cache/android-root-standalone/2026-11-08/` and contain metadata/hashes,
not credentials or save contents.

On a rooted user-0 device with PPSSPP initialized, choose **Inspect root access
→ PPSSPP → Request root inspection**. Expect the verified private path or
other-location result. Unavailable storage stays a visible failure; cancel or
close to discard the observation. No settings/progress/permission cleanup is
needed. Magisk retains its own grant history. The installed emulator and its
normal first-run files remain.

The native research ROM copy and three state/thumbnail pairs are retained as
unassigned test seeds. The exact test-copy directory and all progress hashes are
in the JSON receipt. This adds one 528 MB test copy alongside the Broomm library
download. Do not remove the emulator, its whole memory stick or either profile's
progress as test cleanup. Native normal Exit was observed; there is no Broomm
PSP save transaction to finish or discard.

## Primary sources

- Official [PPSSPP download](https://www.ppsspp.org/download/) and tagged
  [Android activity](https://github.com/hrydgard/ppsspp/blob/v1.20.4/android/src/org/ppsspp/ppsspp/PpssppActivity.java).
- Tagged [memory-stick UI](https://github.com/hrydgard/ppsspp/blob/v1.20.4/UI/MemStickScreen.cpp)
  and [selection persistence](https://github.com/hrydgard/ppsspp/blob/v1.20.4/Core/Util/MemStick.cpp).
- Tagged [Android native shutdown](https://github.com/hrydgard/ppsspp/blob/v1.20.4/android/jni/app-android.cpp)
  and [native application lifecycle](https://github.com/hrydgard/ppsspp/blob/v1.20.4/UI/NativeApp.cpp).
- Tagged [state and undo storage](https://github.com/hrydgard/ppsspp/blob/v1.20.4/Core/SaveState.cpp)
  and [Android defaults/configuration](https://github.com/hrydgard/ppsspp/blob/v1.20.4/Core/Config.cpp).

This uses existing Android/root inspection mechanisms and adds no runtime
dependency. It does not establish standalone gameplay or sync acceptance.
