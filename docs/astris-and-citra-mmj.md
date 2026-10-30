# Astris and Citra MMJ

2026-10-29. Astris is now a macOS Switch alternative; Citra MMJ is an Android 3DS alternative. Only configured emulators can be defaults. Successful setup selects the newly installed emulator, including when another default exists. Cancelled Android installation or failed discovery does not change it.

## Setup and use

On Apple Silicon with macOS 15+, choose **Emulator Settings → Nintendo Switch → Astris → Set up**, review the expanded card and confirm. Broomm downloads reviewed Astris **1.0.32+2398e7c80**. Other configured alternatives remain selectable. Missing firmware/keys use the existing RomM contract: one firmware ZIP, `prod.keys` and `title.keys` under the platform's BIOS/firmware catalogue. Existing resources are retained.

Play uses Broomm's loading/pairing screens: L1+R1 joins, L3+R1 changes face orientation, hold Start to play, and R3+Select opens the paused menu. Disconnecting a paired source returns to pairing. Physical controller/gyro acceptance remains an owner check. Open emulator retains the existing independent OS handoff without hiding or blocking Broomm.

Astris keeps separate private settings, console accounts, save indexes and content selections. Ordinary saves use Broomm's logical Switch save format/history; native identities remain private to the backend. Save states are unavailable. Download Updates and DLC invokes Astris's own content API in private staging, verifies application identity and native records, then publishes through journaled ownership. Repeated checks reuse content. Deletion removes owned selections and unreferenced NSPs, preserving progress and unrelated native records. It does not operate on Ryubing's configuration.

On Android, **Nintendo 3DS → Citra MMJ** detects `org.citra.emu` and performance variant `com.antutu.ABenchMark`. Discovery and APK selection require its exported `org.citra.emu.ui.EmulationActivity`, preventing the unrelated benchmark from matching. Install opens the official releases; Install APK uses Android's confirmation. Actual installation readback updates the requesting server's default and survives restart.

MMJ receives the game's content URI in `GamePath` and skips desktop pairing/overlays. The 2026-10-30 [shared-folder follow-up](mmj-shared-saves.md) implements ordinary cloud saves with a user-granted shared `citra-emu` tree, profile-private copies and journaled native save swaps. Private Android/data storage, MMJ cloud states and automatic CIA installation remain unsupported. Android device/APK gameplay acceptance is outstanding.

### Storage investigation correction — 2026-10-30

The fixed directory explains why Broomm's existing connected-folder adapter cannot be reused directly; it does not establish that MMJ cloud saves are impossible. The earlier investigation omitted MMJ's exported [UserPathProvider](https://github.com/weihuoya/citra/blob/master/src/android/app/src/main/java/org/citra/emu/UserPathProvider.java). That provider exposes the app-specific external files directory, including scoped-storage `citra-emu`, through Android's document system. Its root does not expose the legacy shared-storage directory; that mode needs a separate user-selected external-storage grant.

Source inspection shows read/write access to existing files and deletion, but no `createDocument` or `isChildDocument` override despite advertised creation/child-query flags. Android's [provider contract](https://developer.android.com/reference/android/provider/DocumentsProvider) requires child checks for document-tree access. Creating missing save files/directories and obtaining a usable persistent tree grant therefore remain unresolved for this provider. These are source findings, not device results; actual released APK variants must be checked.

The owner then selected shared storage as the supported assumption. That [adapter is now implemented](mmj-shared-saves.md) using Android's standard external-storage provider, with explicit warnings and a separate ownership/restore journal. It does not depend on MMJ's incomplete provider. Returning to Broomm is not proof of emulator shutdown. Ordinary saves, cloud states and CIA installation remain distinct capabilities; native Android runtime verification has not been completed. No new dependency was introduced.

## Integration and failure handling

Astris uses SwiftUI/GameController and a NativeAOT backend. Its maintainer documents [Launch Services document launch](https://github.com/V380-Ori/Astris.Binaries/issues/54); direct binary launch was unreliable in disposable checks. Original Broomm Objective-C interop calls the frontend's actual controller API and observes backend button/pause state. Virtual source identities stay alive because native input readers retain them; unpairing disables player mappings. Broomm does not fabricate console-port readback.

Dart owns session supervision and progress. The `open -W` helper is separate from the emulator: kernel writer ownership, executable path, process birth and retained AppKit application identity identify the writer. A native receipt distinguishes normal shutdown from a crash. Losing the helper cannot release the writer or finalize progress. Failed/late launches revoke a random admission ticket; the bridge checks it and the original launcher's birth before settings/save initialization. FIFO keepers release pending log readers after failed requests. Scoped inspector cancellation targets the retained application identity and waits for the native writer to exit.

Private frontend preferences use a local plist and an isolated defaults suite, without reading/writing Astris's system preference domain. The child write policy allows its private root and the macOS temporary directory required for Cocoa atomic publication, as existing gameplay does. System emulator installations remain untouched.

The official DMG is pinned to SHA-256 `661f01a47816b3baeda5c6c924f92d32e7a2bf42db98483c259207f0eb5feb6f`, 12,924,928 bytes; unchanged `libryujinx.dylib` is `dc0d0e6c9fc6664897cbdb21f82a5987dceac5ff1bb926b3bbefb06266532088`. The upstream repository is binary-only; matching implementation source is unavailable there. No emulator implementation is copied. `tool/capture_astris_setup.dart` explicitly captures reviewed inputs; imported manifests cannot supply hook addresses/commands. Four precompiled universal bridges use the existing Apple SDK. No new runtime package, emulator, APK, firmware, key or ROM is bundled.

## Verification and reproduction

Native host: M1 Pro, macOS 27.0.1, Xcode 27.1; Devbox Flutter 3.47.0 / Dart 3.13.0. Supplied Super Smash Bros. Ultimate base media, update v2031616 and one DLC were read-only or cloned into disposable storage. Production profiles and RomM progress were not modified.

Native checks cover launch, first frame, pause/resume, two synthetic paired sources, backend button readback, live face remapping, menu chord, disconnection, normal teardown, game-created save ZIP export/import, update/DLC inspection, selection publication/reuse/removal and progress preservation. These do not establish physical input/gyro, in-game DLC recognition, every title, older macOS releases or another native host. Kotlin compilation is not an APK build or Android execution. [Evidence](astris-and-citra-mmj.json) records checks and archive identity.

```sh
devbox run -- bash tool/build_bridges.sh
devbox run -- flutter analyze --no-pub
devbox run -- flutter test --no-pub --exclude-tags full-size-save
devbox run -- flutter test --no-pub test/playstation_test.dart --tags full-size-save --concurrency=1
devbox --config tool/android run check
```

For real media checks, set `BROOMM_ASTRIS_FIXTURE` to a disposable directory, `BROOMM_ASTRIS_ROM` to the supplied NSP/XCI, and `BROOMM_ASTRIS_PROFILE` to a 32-character lowercase hex test profile. First setup also needs `BROOMM_ASTRIS_RESOURCES` containing `prod_keys`, `title_keys`, `switch_firmware`; optional `BROOMM_ASTRIS_LOCK_ROOT` holds that source installation's lock while copying. Run `devbox run -- flutter test --no-pub tool/check_astris_test.dart --reporter expanded`. Then set `BROOMM_ASTRIS_UPDATE` and `BROOMM_ASTRIS_DLC` to native NSPs and run `devbox run -- flutter test --no-pub tool/check_astris_packages_test.dart --reporter expanded`.

The checks create private installations, settings, saves, export snapshots and APFS clones. Remove only the disposable fixture after its native writer exits. The final archive is **20,612,171 bytes**, SHA-256 `175f95f08f67752b1f04fcb411df78a80f6d8bf0de0dd68e20f315d5f36c11f5`. ZIP integrity, fresh-extraction signatures and all seven universal Mach-O signatures are verified. The [current macOS build](../build/releases/Broomm-macOS-astris-citra.zip) uses normal Application Support storage and retains existing accounts/downloads/progress when copied to Applications. It is ad-hoc signed, not notarized.

Primary Android references: [MMJ releases](https://github.com/weihuoya/citra/releases), [EmulationActivity](https://github.com/weihuoya/citra/blob/master/src/android/app/src/main/java/org/citra/emu/ui/EmulationActivity.java), [CitraDirectory](https://github.com/weihuoya/citra/blob/master/src/android/app/src/main/java/org/citra/emu/utils/CitraDirectory.java) and [manifest](https://github.com/weihuoya/citra/blob/master/src/android/app/src/main/AndroidManifest.xml). These are interface evidence, not imported instructions or copied code.
