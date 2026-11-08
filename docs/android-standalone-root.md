# Android standalone root access

2026-11-08. RetroArch's eighteen platform routes/fifteen cores completed the
Thor acceptance recorded in [the core evidence](android-retroarch-cores.md).
PR #4 merged as `eb6fc60`. The owner authorized starting the standalone apps
after that milestone, with the existing two Thor accounts and normal ADB UI
control. This document separates implemented discovery from proposed save writes.

## Rooted PSP session implementation — acceptance pending

PR #5 stays unmerged until the PSP round trip is complete. The current source
adds a concrete PPSSPP route through the compact desktop-style **Set up** actions;
the earlier read-only build-1107 evidence below remains separate. No additional
runtime dependency is introduced.

The writing route requires Android 11+, Android user 0, the exact reviewed
regular universal APK below, initialized App Private Data and a verified normal
Exit. Gold, other APKs and other memory-stick selections keep their shared-folder
route; they are not silently adopted. Setup failures expose **Use shared folder**.
Actual native ABI is read from PPSSPP's ELF library. State groups bind the signed
APK hash, that ABI and the native disc revision, independently of installation
time. They do not relabel connected-folder or desktop states.

Each server/profile owns a complete native private memory stick in a nonce-bound
directory beneath PPSSPP's external private files. Dart persists its ownership,
new console MAC, reviewed preference/control seeds and handoff before selecting
it through PPSSPP's native `memstick_dir.txt`. Original standalone contents and
settings are not overwritten. Complete native shutdown is required before
selection, file effects, capture or restoration. Native **Exit** can leave its
Java process cached; the adapter requires the pinned finish/shutdown/destroy
sequence, UID/PID/kernel lifetime, native activity and cached-state checks.
Backgrounding, bare destruction, incomplete logs and changed identity remain
unknown. Automatic completion requires fresh evidence from this launch; manual
review still cannot override an active/unknown writer.
If preparation cannot verify shutdown, **Open PPSSPP** opens the existing native
selection without starting synchronization. Use its **Exit**, then **Check and
play**; the retry still runs every closure and ownership guard. Launcher failures
remain visible. This recovery action has two UI regressions; device verification
of the new action is pending.

**Open emulator** selects the same private profile and detaches immediately,
without a game marker, lifetime watcher or Broomm quit restriction. Its durable
settings loan is reconciled after closure at the next save/setup action. Settings,
native console identity and auxiliary undo remain private to that account.
Changes to native game files are sealed before cloud synchronization; a
two-sided Broomm/native change requires an explicit source choice with both
copies retained. Missing previously known saves/states are damaged recovery,
not an empty observation.

Game synchronization keeps the existing native PSP savedata ZIP contract and
build-specific state/thumbnail/slot-undo areas. Owned static DLC stays excluded
from game cloud exports and is staged through its reviewed native destinations.
Global undo/settings and other memory-stick files instead have a full private
backup in Broomm storage. Normal Remove first backs up every owned PSP profile,
then uses Android's confirmed uninstall; reinstall restores the last verified
private backup only for the same APK/ABI and preserves the console MAC. Unknown
or changed installations, damaged ownership, missing known files and incompatible
backups retain recovery and fail visibly; resetting an emulator outside Broomm
does not authorize adopting a different storage generation.

Transfers use caller-owned file descriptors and 64 KiB buffers, never Binder save
arrays. Inventories are paged below Binder's transaction budget and must merge
completely without duplicates. Game limits remain 4096 files, 256 MiB/file and
512 MiB total; private profile backups are separately bounded at 8192 files,
1 GiB/file and 2 GiB total, also subject to bounded metadata records and operation
deadlines. Keep two verified full backups; retain failed captures separately
(at most eight before review). Session working/capture directories and completed
receipts remain under Broomm's private `android/shared-session`; no automatic
deletion of uncertain progress is added.

For a device check, install the new PR APK over the retained Broomm preview,
choose **Emulator Settings → PSP → PPSSPP → Set up**, open PPSSPP once if asked,
choose **Skip for now / App Private Data**, wait for its menu and use **Exit**.
On the Thor its initial first open needed a second normal open/Exit to initialize
settings. Retry **Check setup** and allow Magisk. Download LocoRoco from RomM,
choose **Play**, make an ordinary save and manual state, then use Android Back
and PPSSPP's **Exit to menu → Exit**. Expected: automatic sync, a restored
standalone selection and no cross-account progress. Returning while PPSSPP is
running must keep the session active. The observations verified below remain
separate from the earlier native seed/research results.

Build 1111 (`eac1db0`, full CI APK) now passes content-URI LocoRoco launch, native
manual-state capture, automatic normal-Exit synchronization and standalone-pointer
restoration. Account 2 published two state/thumbnail pairs as primary 255;
account 3 began with empty native slots and published its own language-screen
pair as primary 257, with a distinct memory-stick nonce and console MAC. Both
checkpoints are acknowledged and both private profiles have verified backups.
These observations establish state isolation, not an ordinary SAVEDATA round trip;
ordinary LocoRoco saving, replay/offline and removal/reinstall acceptance remain
pending. Expired native shutdown logs correctly refused preparation without
selecting a profile; a fresh native menu open/Exit allowed the retry.

All sixteen original PSP files were unchanged after the first Broomm session.
The subsequent explicit standalone menu open/Exit changed native `ppsspp.ini`
(upstream increments RunCount on load); its earlier contents were held by hash,
so an exact field-only delta is not claimed. The other fifteen files remain
unchanged. An unintended adjacent account-3 TG16 launch was closed by the owner;
no signal/interruption command ran. The repeated RetroArch preservation audit
passes all 49 earlier progress files, nineteen managed native files, thirteen
original files, fifteen cores and eighteen connections. ADB injected gamepad/menu
events remain inconclusive; owner closure is recorded separately from automated
PSP touch checks. All native Windows CI checks and five platform packages passed
for `eac1db0`.

Build 1112 (`d990333`) also replayed account 2's retained slot 2 after switching
back from account 3. Normal Exit kept both state pairs byte-identical and primary
255 unchanged. The complete CI run and five platform packages pass. Its local
macOS ZIP passed archive integrity, seven universal Mach-O checks and deep/strict
source/extracted signatures.

For ordinary saves, Broomm downloaded Lumines II from the owner's RomM catalogue
(5939, native `ULUS10183`, revision 1.00). Its confirmed-empty load dialog led to
a new game-local profile with the first avatar and native **Save completed**
(64 KB Play Data). Cloud publication and ordinary reload are not yet established.
The live-writer check brought the existing Broomm activity above the paused native
game: Broomm reported PPSSPP still running, retained every journal unchanged and
made no capture or remote publication. The subsequent **Return to emulator**
reused PPSSPP's activity but Android removed the Broomm activity above it; normal
native Exit then returned to the launcher. Its save and session journal remain
retained for recovery. The correction launches rooted PSP in its own Android
task, relying on app lifecycle and the native shutdown proof rather than an
Activity result. Two new UI regressions cover normal completion without a result
and retention of live/unknown writers; all 25 emulator/UI cases, targeted analysis
and bridge compilation pass. Device re-execution and fresh packaging are pending.

The retained ordinary save subsequently recovered as primary **258**: four files
under `ULUS10183GAME01`, including an 18,504-byte `DATA.BIN`. All PSP journals
cleared and the standalone selection was restored. Build **1113** loaded the
64 KB Play Data through **Continue → native Load → Load completed**, then showed
the original first avatar. Injected Odin `ABS_HAT0Y` changed the native menu;
physical button actuation is not claimed. Its full CI run/five packages and
macOS archive/signature checks pass. Task inspection also showed the first
handoff change never ran: rooted PSP has no shared-folder provider marker.
The current correction sends a separate `rootedPsp` launch flag from the Dart
session; the real workflow regression verifies it without that provider marker.
Non-root handoff remains unchanged and invalid emulator/profile combinations
are refused before Android effects. All 36 focused UI/workflow cases, targeted
analysis and bridge compilation pass; the corrected packaged task behavior,
two-account ordinary saves, offline and reinstall checks remain pending.

Some black/static ADB captures came from the Thor's transient **Burn-in Protection
Refresher** window, which covered the app and consumed test taps. The CLI test
harness now inspects the current input-window list and waits for that overlay
to clear before actions/capture. Device preferences were not changed. Earlier
inconclusive injected-input observations do not establish emulator input failures.

```sh
devbox run -- flutter --suppress-analytics test --no-pub test/android_psp_root_test.dart
devbox --config tool/android run check-root-inspection
devbox --config tool/android run check
devbox --config tool/android run -- bash build_root_psp_test.sh
```

The last command builds a development-only `app_process` fixture, not shipped
application behavior. Its `inspect` mode is read-only. Its `files <32-hex nonce>`
mode uses a newly owned, unassigned memory stick with fixed test server/profile
identities, plus a private `/data/local/tmp/broomm-psp-files-<nonce>` directory.
It creates only test files, temporarily selects/restores that stick without
launching an emulator, and records all paths and results for scoped cleanup.
Its `cleanup <same nonce>` mode requires the original selection, verified
test ownership and only recognized fixture paths before removing those test
directories. It refuses extra/linked/foreign files. Retain the deployment/result
receipts; this mode is not an emulator or account reset.
Do not remove account profiles, the original native memory stick or retained
failed progress as fixture cleanup. Device execution requires an initialized,
normally exited pinned PPSSPP and explicit ADB/root test authorization.

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
