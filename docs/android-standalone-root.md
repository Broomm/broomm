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

The fixed production script passed a direct read-only Thor check. Hashes of
the native selection and `ppsspp.ini` were unchanged before/after it.
The in-app diagnostic, Gold package, other devices and new save-writing
route require their own native acceptance. Existing connected-folder save
support is separate; PPSSPP root save synchronization is **not implemented**
by this increment.

## Next save-writing increment

Keep Dart's existing session/journal/cloud decisions and PSP savedata ZIP
contract. A concrete PSP native file adapter must restrict ordinary data to
this game's verified disc-ID folders under `PSP/SAVEDATA`, respect owned
static DLC, and handle `PSP/PPSSPP_STATE` separately by exact APK/ABI and disc
revision. Do not route PSP through a pretend Libretro core.

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

## Primary sources

- Official [PPSSPP download](https://www.ppsspp.org/download/) and tagged
  [Android activity](https://github.com/hrydgard/ppsspp/blob/v1.20.4/android/src/org/ppsspp/ppsspp/PpssppActivity.java).
- Tagged [memory-stick UI](https://github.com/hrydgard/ppsspp/blob/v1.20.4/UI/MemStickScreen.cpp)
  and [selection persistence](https://github.com/hrydgard/ppsspp/blob/v1.20.4/Core/Util/MemStick.cpp).
- Tagged [Android native shutdown](https://github.com/hrydgard/ppsspp/blob/v1.20.4/android/jni/app-android.cpp)
  and [native application lifecycle](https://github.com/hrydgard/ppsspp/blob/v1.20.4/UI/NativeApp.cpp).

This uses existing Android/root inspection mechanisms and adds no runtime
dependency. It does not establish standalone gameplay or sync acceptance.
