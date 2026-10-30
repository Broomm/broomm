# Android emulator status

2026-10-30. **Android native acceptance and content/firmware parity remain incomplete.** APK downloading and connected save adapters now exist for the full Android roster. This table separates code, compilation/workflow tests and actual Android acceptance; macOS green cells do not describe Android. See the current [installation/save walkthrough and limits](android-installation-and-saves.md).

**Historical research, earlier on 2026-10-30:** the owner reported that the installed Android
experience does not provide working cloud saves. The [per-app parity audit](android-parity-audit.md)
separates missing Broomm adapters from upstream storage/installer limits, records
ARMSX2's missing nightly package identity, and proposes APK downloading and
one-time folder setup. That audit preceded the authorized implementation recorded
in this table and the newer [evidence record](android-installation-and-saves.json).

## Audit and implemented handoff

Previously Android had launcher input and secure credentials, but no emulator package discovery, installer, external launch or save access. Home Play and Emulator Settings reached the desktop managed-pack path. The manifest also lacked emulator package-visibility declarations.

Android now has its own settings screen and session supervisor. It lists researched Android apps under the server's platforms, detects package/version/signing identity, selects installed defaults and opens an emulator without a game. Failed enumeration preserves the previous observation and shows an error. Intel/Rosetta and other desktop-only recipes do not become Android choices. PS3 has no validated Android adapter. PS4 remains downloadable without a built-in emulator.

**Install** downloads the official compatible APK, with progress/cancellation, and hands it to Android for confirmation. DuckStation uses its official store; PPSSPP Gold remains a paid entitlement. **Install APK…** retains explicit local APK selection. Package, exported-launcher and minimum-SDK checks precede handoff; Android handles signatures/unknown-source permission. Actual package readback selects a successful new installation as default; handoff/cancellation/failed discovery do not claim success. No root, shell installer, unattended emulator updates or runtime plugin is introduced. ARMSX2 discovers stable `com.armsx2` and nightly `com.armsx2.nightly`, preferring enabled stable; connections/recovery remain package-specific.

Play uses a concrete exported activity and literal typed content-URI extras. Native checks cover the installed build observation, activity export and the owned library manifest. A read-only provider grants only known files from that game, with real filenames/companion relationships. Related files receive separate grants: Dolphin treats all ClipData items as discs, so ClipData contains only the selected entry. Android never enters desktop pairing, injection, motion interception or the Broomm in-game overlay.

## Coverage

🟡 = code path present, native Android acceptance outstanding; 🔴 = missing adapter; ⚪ = not applicable/upstream unavailable. **No Android gameplay or installation has been executed on this host.**

| Android app | Launch | Cloud ordinary saves | States | Automatic packages / firmware |
| --- | --- | --- | --- | --- |
| RetroArch regular/AArch64/32-bit | 🟡 ROM/core/config extras; core must already exist | 🟡 Own provider and per-session paths | 🟡 APK/core identity; physical groups | 🔴 Automatic core/BIOS setup deferred |
| PPSSPP / Gold | 🟡 Content URI | 🟡 Connected Broomm Memory Stick; native SAVEDATA ZIP | 🟡 Exact APK/ABI/host/disc version | 🟡 Existing Dart native-folder/ZIP installer and owned removal; generic PSP PKG/patch execution remains unsupported |
| melonDS | 🟡 LAUNCH_ROM, Parcelable URI | 🟡 Connected custom folder; raw `.sav` | 🟡 Android `.ml0`–`.ml8`; physical groups | ⚪ No DS package pipeline |
| Citra MMJ / AnTuTu variant | 🟡 GamePath URI; exported activity verified | 🟡 Shared citra-emu; journaled profile swaps | 🟡 Matching APK/ABI; legacy states retained separately | 🔴 CIA importer deferred |
| Azahar | 🟡 Exported EmulationActivity | 🟡 Connected user folder; game data/extdata | 🟡 Exact APK/ABI/host | 🔴 Android CIA importer missing |
| Dolphin / GameCube and Wii | 🟡 Exported MainActivity/startup interface | 🟡 Own provider; GCI/Wii title boundaries | 🟡 Matching Android build | 🔴 Content installers deferred; no additional Wii update requirement |
| DuckStation | 🟡 bootPath URI, resume disabled | 🟡 Shared parent; isolated shared-card swaps | 🟡 Matching Android build | 🔴 BIOS provisioning deferred |
| ARMSX2 stable + nightly | 🟡 VIEW alias; stable preferred | 🟡 Shared custom root; configured card paths | 🟡 Matching Android build | 🔴 BIOS provisioning deferred |
| Eden | 🟡 VIEW content URI | 🟡 Own provider; native account/title mapping | ⚪ Unavailable | 🔴 NSP/firmware/keys/removal deferred |

Built-in emulator Play now leads to save-folder setup when not connected, rather than silently opening a local-only session. Unsupported package routes do not run desktop importers. RomM attachments may download, but manually installed external content is not claimed or uninstalled. New stable-folder package installation is later work; the old PSP native-folder route remains a legacy path. These are remaining requirements, not Android acceptance.

Citra MMJ still requires the exact shared `citra-emu` folder and storage warning. Its incomplete own provider is not used. The current stable-folder route adds matched states; the [earlier MMJ journal](mmj-shared-saves.md) remains supported for recovery. Private Storage Access builds are rejected, and the actual emulator preference still needs user confirmation.

## Save storage and lifecycle

**Configure saves** now connects one stable emulator/package folder for every Broomm profile. Follow its app-specific location instructions, close the emulator and grant its shared root or its own provider. Setup verifies disposable file creation/write/readback/rename/delete. Each profile/game uses private working data and a journaled native swap, preserving/restoring standalone progress. Folder reselection on profile changes is no longer required. Native verification must still establish that the emulator retained and uses that choice.

Legacy profile-specific Broomm provider IDs remain readable and never follow the active login. Credentials/recovery/ownership stay outside their grant. New external connections are allowlisted per emulator/package; paths outside the selected root, ambiguous accounts and ownership changes fail without adoption. Original/working/captured copies survive interruption. Revoked access can be regranted for the original tree; explicit keep-folder resolution can finish without further writes/upload.

Play reuses BROOMM history, native extensions, explicit imports/backups, conflicts and sealed offline snapshots. State groups fingerprint APK/ABI and RetroArch core bytes; the new route isolates physical state directories too. Package/core fingerprints are cached against fresh metadata rather than fully rehashed on every launch. A changed build omits incompatible states from finalization and retains native recovery bytes. Android states are not advertised as desktop-portable.

SessionLease remains held through preparation, handoff and finalization. The general marker precedes effects; a surviving native-swap journal independently exposes recovery. On return, **Finished? Sync progress** asks the player to save/close the emulator. The owner explicitly accepts that confirmation without OS process-exit checks or blocking on a held emulator descriptor. Broomm's own transfer locks still serialize mutations. Interrupted sessions remain recoverable; no external emulator process is terminated.

Selecting **Not finished** leaves the session active. Synchronization is confirmed, not unattended on app switching. BIOS/firmware and the remaining content pipelines are outside this milestone; see the [current walkthrough](android-installation-and-saves.md) and [research](android-parity-audit.md).

## Dependencies and verification

No runtime Flutter plugin was added. [android_intent_plus](https://pub.dev/packages/android_intent_plus) is Android-only and explicitly lacks activity results; it would leave package inspection, constrained providers and writer tracking to us. Flutter's maintained, multi-platform [file_selector](https://pub.dev/packages/file_selector) provides dialogs but not an emulator storage provider or lifecycle contract. Both have BSD-style licenses and plugin/Gradle dependencies. Existing MethodChannels avoid those additional dependencies; Dart owns domain workflows, Kotlin owns Android mechanisms. Cancellation and partial results need our handling with either approach.

Kotlin 2.4.0 and its JVM are development-only Devbox dependencies in `tool/android/`, with a committed lockfile. The separate environment avoids a macOS case-insensitive profile collision between Kotlin's `license` directory and Flutter's `LICENSE` file. The main Flutter environment and machine SDK selections are unchanged. No new OS dependencies were installed.

From the repository root:

```sh
devbox run -- flutter --suppress-analytics analyze --no-pub
devbox run -- flutter --suppress-analytics test --no-pub
devbox --config tool/android run check
```

The compile helper verifies pinned API artifact hashes in `.tool-cache/research/android`, compiles all Android Kotlin sources against Android API 36/the exact Flutter embedding/its existing Lifecycle 2.7.0 API, and emits `bridge.jar`. It is not an APK, Gradle resource/manifest merge or Android runtime check. Delete that cache to clean compiler artifacts; delete `tool/android/.devbox` to remove its disposable environment. No API jar is bundled as a new runtime dependency. A complete project-scoped Android SDK/device is still absent here; no global SDK change was made.

The regressions cover Android-only defaults, uncertain discovery, durable profile correspondence, unknown ownership, literal arguments, concurrent launch reservation, held leases, lost replies/restart recovery, build-change state exclusion, raw DS `.sav` upload/readback and the no-pairing widget route. New regressions cover official APK selection/download failures, stable/nightly precedence, persistent folder connections, profile swaps, reconnect/recovery and explicit confirmation without emulator-process probing. These are controlled API/filesystem tests, not emulator gameplay. The [current evidence](android-installation-and-saves.json) records 455 passing Flutter tests and Kotlin compilation; the [initial evidence](android-emulators.json) retains its dated results and failures.

Required acceptance: build/run an APK on an actual device, install/open the selected emulator builds, verify retained SAF folder selection, real save creation/loading, exact-build state loading, physical input and Android background/process behavior. Then implement each red storage/installer row. The current code does not establish compatibility for every installed emulator version.

## Primary references

- Android [package visibility](https://developer.android.com/training/package-visibility/declaring), [document access/restrictions](https://developer.android.com/training/data-storage/shared/documents-files), [custom providers](https://developer.android.com/guide/topics/providers/create-document-provider).
- [PPSSPP 1.20.4 intents](https://github.com/hrydgard/ppsspp/blob/v1.20.4/android/src/org/ppsspp/ppsspp/PpssppActivity.java), [melonDS manifest](https://github.com/rafaelvcaetano/melonDS-android/blob/master/app/src/main/AndroidManifest.xml) and [URI key](https://github.com/rafaelvcaetano/melonDS-android/blob/master/app/src/main/java/me/magnum/melonds/ui/emulator/EmulatorActivity.kt).
- Dolphin 2609 [manifest](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Android/app/src/main/AndroidManifest.xml) and [intent precedence](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Android/app/src/main/java/org/dolphinemu/dolphinemu/utils/StartupHandler.kt); EmulationActivity is not exported.
- Azahar [manifest](https://github.com/azahar-emu/azahar/blob/master/src/android/app/src/main/AndroidManifest.xml), [URI/SelectedGame reader](https://github.com/azahar-emu/azahar/blob/master/src/android/app/src/main/java/org/citra/citra_emu/activities/EmulationActivity.kt).
- Already retained [Eden](https://git.eden-emu.dev/eden-emu/eden) 0.2.1 and [ARMSX2](https://github.com/ARMSX2/ARMSX2) 90126bd Android source; [RetroArch intent reader](https://github.com/libretro/RetroArch/blob/master/frontend/drivers/platform_unix.c) and [SAF parser](https://github.com/libretro/RetroArch/blob/master/libretro-common/vfs/vfs_implementation_saf.c).
- Argosy's [emulator definitions](https://github.com/rommapp/argosy-launcher/blob/main/app/src/main/kotlin/com/nendo/argosy/data/emulator/EmulatorRegistry.kt) and [save-path audit](https://github.com/rommapp/argosy-launcher/blob/main/docs/save-id-to-path.md), including DuckStation bootPath/resumeState. Used as interface evidence, not copied code/instructions.
