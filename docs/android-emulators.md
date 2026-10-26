# Android emulator status

2026-10-26. **Android parity is incomplete.** This audit separates source implementation, compilation, automated workflow tests and native emulator acceptance. The macOS matrix's green cells do not describe Android.

## Audit and implemented handoff

Previously Android had launcher input and secure credentials, but no emulator package discovery, installer, external launch or save access. Home Play and Emulator Settings reached the desktop managed-pack path. The manifest also lacked emulator package-visibility declarations.

Android now has its own settings screen and session supervisor. It lists researched Android apps under the server's platforms, detects package/version/signing identity, selects installed defaults and opens an emulator without a game. Failed enumeration preserves the previous observation and shows an error. Intel/Rosetta and other desktop-only recipes do not become Android choices. PS3 has no validated Android adapter. PS4 remains downloadable without a built-in emulator.

**Install** opens the official app/download page. **Install APK…** picks an APK, verifies that its package matches the selected emulator, stages it privately and opens Android's user-confirmed installer with a one-file read grant. Installation, upgrade signatures and unknown-source authorization remain Android operations. Actual package readback follows installer return; opening it is not installation success. Copying has a 1 GiB/60-second limit and bounded retained cache. There are no unattended updates, root, global storage access or package-manager shell commands.

Play uses a concrete exported activity and literal typed content-URI extras. Native checks cover the installed build observation, activity export and the owned library manifest. A read-only provider grants only known files from that game, with real filenames/companion relationships. Related files receive separate grants: Dolphin treats all ClipData items as discs, so ClipData contains only the selected entry. Android never enters desktop pairing, injection, motion interception or the Broomm in-game overlay.

## Coverage

🟡 = code path present, native Android acceptance outstanding; 🔴 = missing adapter; ⚪ = not applicable/upstream unavailable. **No Android gameplay or installation has been executed on this host.**

| Android app | Launch | Cloud ordinary saves | States | Automatic packages / firmware |
| --- | --- | --- | --- | --- |
| RetroArch regular/AArch64/32-bit | 🟡 ROM/core extras; core must already exist | 🔴 Storage/config adapter missing | 🔴 Core fingerprint/storage adapter missing | 🔴 Android core/BIOS setup missing |
| PPSSPP / Gold | 🟡 Content URI | 🟡 Connected Broomm Memory Stick; native SAVEDATA ZIP | 🟡 Exact APK/ABI/host/disc version | 🟡 Existing Dart native-folder/ZIP installer and owned removal; generic PSP PKG/patch execution remains unsupported |
| melonDS | 🟡 LAUNCH_ROM, Parcelable URI | 🟡 Connected custom folder; raw `.sav` | 🔴 Android state format missing | ⚪ No DS package pipeline |
| Azahar | 🟡 Exported EmulationActivity | 🟡 Connected user folder; game data/extdata | 🟡 Exact APK/ABI/host | 🔴 Android CIA importer missing |
| Dolphin / GameCube and Wii | 🟡 Exported MainActivity/startup interface | 🔴 External user-data adapter missing | 🔴 Missing adapter | 🔴 Android WAD installation/removal missing |
| DuckStation | 🟡 bootPath URI, resume disabled | 🔴 Per-game card adapter missing | 🔴 Missing adapter | 🔴 Android BIOS setup missing |
| ARMSX2 `com.armsx2` | 🟡 VIEW activity alias | 🔴 Per-game card adapter missing | 🔴 Missing adapter | 🔴 Android BIOS setup missing |
| Eden | 🟡 VIEW content URI | 🔴 External NAND/account adapter missing | ⚪ Unavailable | 🔴 Android NSP/firmware/keys/removal missing |

Unsupported cloud routes show local-only feedback and an attention badge. Unsupported package routes do not run desktop importers. RomM attachments still download with the game, but content manually installed in an external app is not claimed or uninstalled. These are remaining product requirements, not permission to declare Android complete.

## Save storage and lifecycle

For PPSSPP, melonDS and Azahar, **Configure saves** exposes a profile-specific root through Android's DocumentsProvider. Inside the emulator, the player selects **Broomm · profile · emulator** as its Memory Stick, custom save or user-data folder, respectively, then saves/exits and confirms. Folder selection is required per profile. Existing external data is not moved or adopted; explicit RomM save imports can populate the new folder. Confirmation does not prove the emulator retained its setting: native device verification remains required.

Provider IDs contain stable profile/emulator identities and never follow the active login. Only `profiles/<profile>/emulators/<emulator>/user` is exposed. Credentials, recovery snapshots and ownership records are outside the grant. Traversal, links, unknown ownership and mismatched stored roots fail without adoption. A launched session rejects access to a different profile's root, preventing an emulator still configured for an old profile from writing into the new history. File rename publishes exclusively rather than replacing a newly created destination. Recursive directory removal/root deletion is not offered.

Connected-folder Play reuses BROOMM version history, extensions, imports, named backups, conflicts and offline snapshots. PPSSPP/Azahar state groups fingerprint the APK/split APK bytes, signing/version identity, ABI and host. A changed build cannot relabel old states; its finalization omits that state group and keeps ordinary progress for review. DS states are excluded. Background retries use sealed pending snapshots rather than inspecting a potentially live external writer. Initial checking occurs before launch, not by blindly scanning external apps after download.

SessionLease remains held through preparation, handoff and finalization. `android/session.json` is published before effects; an unknown launch result retains it. Neither resume nor an activity result proves shutdown. The player saves, exits the emulator and confirms **Finish and sync progress**; still-open writable provider descriptors block capture even after confirmation. Interrupted sessions can be finished from Settings or the next Play attempt, with progress marked unclean for review. A restart never certifies a clean close. No external emulator process is terminated.

Android cannot prove that an independently opened emulator will not reopen files later. Explicit closure is necessary; descriptor observation is additional evidence. Cloud actions ask for closure too. Full unattended sync on app switching is not claimed.

## Dependencies and verification

No runtime Flutter plugin was added. [android_intent_plus](https://pub.dev/packages/android_intent_plus) is Android-only and explicitly lacks activity results; it would leave package inspection, constrained providers and writer tracking to us. Flutter's maintained, multi-platform [file_selector](https://pub.dev/packages/file_selector) provides dialogs but not an emulator storage provider or lifecycle contract. Both have BSD-style licenses and plugin/Gradle dependencies. Existing MethodChannels avoid those additional dependencies; Dart owns domain workflows, Kotlin owns Android mechanisms. Cancellation and partial results need our handling with either approach.

Kotlin 2.4.0 and its JVM are development-only Devbox dependencies in `tool/android/`, with a committed lockfile. The separate environment avoids a macOS case-insensitive profile collision between Kotlin's `license` directory and Flutter's `LICENSE` file. The main Flutter environment and machine SDK selections are unchanged. No new OS dependencies were installed.

From the repository root:

```sh
devbox run -- flutter --suppress-analytics analyze --no-pub
devbox run -- flutter --suppress-analytics test --no-pub
devbox --config tool/android run check
```

The compile helper verifies pinned API artifact hashes in `.tool-cache/research/android`, compiles all six Kotlin files against Android API 36/the exact Flutter embedding/its existing Lifecycle 2.7.0 API, and emits `bridge.jar`. It is not an APK, Gradle resource/manifest merge or Android runtime check. Delete that cache to clean compiler artifacts; delete `tool/android/.devbox` to remove its disposable environment. No API jar is bundled as a new runtime dependency. A complete project-scoped Android SDK/device is still absent here; no global SDK change was made.

The regressions cover Android-only defaults, uncertain discovery, durable profile correspondence, unknown ownership, literal arguments, concurrent launch reservation, held leases, open writers, lost replies/restart recovery, build-change state exclusion, raw DS `.sav` upload/readback and the no-pairing widget route. These are controlled API/filesystem tests, not emulator gameplay. [Evidence](android-emulators.json) records final results, source/artifact hashes and retained failures, including a corrected fake-async test deadlock, denied sandbox loopback access and repaired compile diagnostics.

Required acceptance: build/run an APK on an actual device, install/open the selected emulator builds, verify retained SAF folder selection, real save creation/loading, exact-build state loading, physical input and Android background/process behavior. Then implement each red storage/installer row. The current code does not establish compatibility for every installed emulator version.

## Primary references

- Android [package visibility](https://developer.android.com/training/package-visibility/declaring), [document access/restrictions](https://developer.android.com/training/data-storage/shared/documents-files), [custom providers](https://developer.android.com/guide/topics/providers/create-document-provider).
- [PPSSPP 1.20.4 intents](https://github.com/hrydgard/ppsspp/blob/v1.20.4/android/src/org/ppsspp/ppsspp/PpssppActivity.java), [melonDS manifest](https://github.com/rafaelvcaetano/melonDS-android/blob/master/app/src/main/AndroidManifest.xml) and [URI key](https://github.com/rafaelvcaetano/melonDS-android/blob/master/app/src/main/java/me/magnum/melonds/ui/emulator/EmulatorActivity.kt).
- Dolphin 2609 [manifest](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Android/app/src/main/AndroidManifest.xml) and [intent precedence](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Android/app/src/main/java/org/dolphinemu/dolphinemu/utils/StartupHandler.kt); EmulationActivity is not exported.
- Azahar [manifest](https://github.com/azahar-emu/azahar/blob/master/src/android/app/src/main/AndroidManifest.xml), [URI/SelectedGame reader](https://github.com/azahar-emu/azahar/blob/master/src/android/app/src/main/java/org/citra/citra_emu/activities/EmulationActivity.kt).
- Already retained [Eden](https://git.eden-emu.dev/eden-emu/eden) 0.2.1 and [ARMSX2](https://github.com/ARMSX2/ARMSX2) 90126bd Android source; [RetroArch intent reader](https://github.com/libretro/RetroArch/blob/master/frontend/drivers/platform_unix.c) and [SAF parser](https://github.com/libretro/RetroArch/blob/master/libretro-common/vfs/vfs_implementation_saf.c).
- Argosy's [emulator definitions](https://github.com/rommapp/argosy-launcher/blob/main/app/src/main/kotlin/com/nendo/argosy/data/emulator/EmulatorRegistry.kt) and [save-path audit](https://github.com/rommapp/argosy-launcher/blob/main/docs/save-id-to-path.md), including DuckStation bootPath/resumeState. Used as interface evidence, not copied code/instructions.
