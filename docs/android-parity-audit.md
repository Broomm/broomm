# Android parity: feasibility and limits

Research date: **2026-10-30**. This is an audit and implementation proposal,
not a claim of Android acceptance. The owner requested investigation before
fixes. No application behavior was changed for this audit. No emulator was run
on an Android device here. Existing macOS acceptance does not establish Android
save, package or firmware support.

The owner subsequently authorized APK installation/discovery and connected
saves, accepting explicit closure confirmation and deferring BIOS/content work.
See the [implemented milestone](android-installation-and-saves.md) for current
behavior. The findings below retain the pre-implementation audit state.

## What Broomm actually has

The Android roster in `lib/src/android/emulators.dart` has nine concrete app
adapters: RetroArch, PPSSPP/Gold, melonDS, Azahar, Citra MMJ/AnTuTu, Dolphin,
Eden, ARMSX2 and DuckStation. Android has no built-in RPCS3, PCSX2, Ryubing or
Astris adapter. PS4 remains downloadable without a built-in emulator.

Package discovery and launch are implemented. **Install currently opens a web
page. It does not download an APK.** The separate **Install APK…** action already
stages a selected APK, checks its package, asks Android to install it, and reads
back the installed package. Therefore the missing automatic download is a
Broomm implementation gap, not an Android requirement.

Save code exists for PPSSPP, melonDS, Azahar and, in the current working tree,
Citra MMJ. None has native Android acceptance recorded. The first three require
selecting Broomm's folder *inside the emulator*, currently once per Broomm
profile. MMJ requires a grant to its actual shared `citra-emu` folder. The
remaining five app adapters have no Android save storage implementation.
PPSSPP/Azahar have state boundaries; melonDS/MMJ state sync is missing. Other
apps' state boundaries are missing too; Eden has no upstream save states.

Downloaded attachments are not evidence that an emulator has installed DLC.
PPSSPP's supported native folder/ZIP path is wired. Android CIA, WAD and Eden
content/firmware publication are absent. The current Android experience is
incomplete and should not be presented as desktop parity.

Sources: [current coverage](android-emulators.md),
`lib/src/android/{emulators,progress,session}.dart`,
`android/app/src/main/kotlin/app/broomm/broomm/BroommEmulators.kt`, and
`lib/src/addons/{azahar_import,package_import,eden}.dart`.

## Access models: what a permission can and cannot do

Android's ordinary shared-folder picker can grant persistent read/write access
to a selected folder. Modern Android prevents using that picker to select
another app's `Android/data` directory through the system external-storage
provider. Broad all-files permission also does not grant access to other apps'
private data. Requesting more permissions is not a universal solution.
[Android folder access](https://developer.android.com/training/data-storage/shared/documents-files),
[all-files limits](https://developer.android.com/training/data-storage/manage-all-files).

There is an important additional route: an emulator can expose its own files
through a **DocumentsProvider**. Dolphin, Eden and RetroArch do this. The user
selects the emulator's entry in the system picker's sidebar; its provider can
then grant access to data the system external-storage provider cannot expose.
This uses the emulator's cooperation, not a bypass of Android isolation.
[Android custom providers](https://developer.android.com/guide/topics/providers/create-document-provider).

Three proposed setup patterns cover most of the roster:

1. **Select a shared folder in both apps:** PPSSPP's Memory Stick, melonDS's save
   and state folders, Azahar's user folder, MMJ's shared root, and compatible
   ARMSX2 custom data folders. Some emulators can instead select Broomm's own
   provider. Settings held privately by the emulator still need an initial user
   selection if no exported configuration API exists.
2. **Grant the emulator's own provider:** Dolphin, Eden and RetroArch. The user
   grants Broomm that root once. Broomm then reads/writes the relevant title's
   files through document URIs.
3. **Private-only data without a usable provider:** cannot be synchronized by
   an ordinary third-party app. A user export/import, a supported relocation, or
   an upstream interface is necessary. This applies to some legacy/channel
   variants and specifically ARMSX2's current BIOS destination.

One-time permission/setup is compatible with automatic synchronization afterward.
It does not require the player to export and import every save manually. A
folder grant also does not establish that the emulator is really using it;
setup needs a retained-setting/readback and actual save/load check.

## Per-app feasibility

The colors describe **proposed integration effort**, not completed support:
🟢 comparatively direct file integration; 🟡 concrete adapter/format work;
🔴 no confirmed fully automatic route for the stated case; ⚪ not applicable.
All routes need native Android validation.

| App / platform | Saves and states | Initial setup required | Updates / DLC | BIOS / firmware |
| --- | --- | --- | --- | --- |
| **RetroArch** / listed RA platforms | 🟡 Grant its provider or configure shared save/state folders. Reuse core-specific ordinary-save layouts; fingerprint Android frontend/core for states. | Grant RetroArch's data root; verify selected core/config and effective save/system paths. | ⚪ No console package pipeline for the current RA roster. ROMset/BIOS/CHD dependencies are separate. | 🟡 Download RomM resources into the effective core system folder. Android core acquisition/selection also needs implementation. |
| **PPSSPP / Gold** / PSP | 🟢 Native `PSP/SAVEDATA` and `PSP/PPSSPP_STATE`, with build-compatible states. Existing Broomm code needs real validation and better setup/profile handling. | Select one Memory Stick folder in PPSSPP and grant/connect it to Broomm. | 🟡 Native DLC directories/ZIPs are feasible. PSP content placement is title-specific; arbitrary Sony PKG files and executable patches are not universally supported. | ⚪ No console BIOS required. |
| **melonDS** / DS | 🟢 Ordinary `.sav`; 🟡 add Android states. Custom state location can be the save directory. | Disable save-next-to-ROM for Broomm's read-only ROM URI; choose a custom save folder and an accessible state location. | ⚪ Ordinary DS cartridges have no general update/DLC package workflow. DSiWare is a distinct future scope. | 🟡 Ordinary DS can use built-in support. If external DS BIOS/firmware is selected, provision its folder then select/enable it. DSi additionally needs its own BIOS/firmware/NAND. |
| **Azahar** / 3DS | 🟢 User-folder save/extdata layout; 🟡 confirm states against the exact APK and format. | Select a shared/Broomm user folder once; grant Broomm the same root when external. | 🟡 CIA installation needs an Android implementation. The inspected app installs via its private worker/JNI, not an exported install-and-report API. | 🟡 No universal boot-ROM requirement; titles/features may need keys, seeds or system data. Populate supported resources under the selected user root. |
| **Citra MMJ** / 3DS | 🟡 Journaled ordinary-save swaps already exist in the working tree; state sync still needs a format/build adapter. | **Same agreed MMJ setup:** use the normal shared `citra-emu` directory, grant it in Broomm and acknowledge the storage warning. Private Storage Access variants are not covered by that contract. | 🟡 Same CIA format work; MMJ's own installer is an internal JNI operation. Folder access alone does not install a CIA. | 🟡 User-root resources, with MMJ-specific paths and format checks. |
| **Dolphin** / GameCube + Wii | 🟡 Its complete provider exposes user data. Add per-game GCI/card/Wii-title handling and matched states. | Select **Dolphin** in the picker and grant its user root. Verify memory-card mode; do not treat a shared multi-game card or all NAND as one game's save. | 🟡 Wii WAD installation is feasible with a new validated Dart importer/public upstream API. Broomm's existing importer runs a desktop process; Dolphin Android's JNI installer is internal. GameCube has no equivalent pipeline. | 🟢 Most GC/Wii games need no external BIOS. Optional IPL/NAND/IOS resources are separate, feature-specific imports; preserve existing console identity. |
| **Eden** / Switch | 🟡 Complete provider exposes NAND/account saves. Bind the native account/title identity, then mirror only the selected game's save/device areas. ⚪ No upstream save states. | Grant **Eden** in the picker; initialize and identify the native account. Do not replace its console/account database. | 🟡 Existing Dart NSP/NCA staging is reusable, with Android provider publication/readback and ownership tracking. No desktop injection should be needed for this route. | 🟡 Existing Dart resource staging is reusable. Install the agreed **one firmware ZIP + `prod.keys` + `title.keys`** into Eden's actual directories; validate/reload after closure. |
| **ARMSX2** / PS2 | 🟡 Shared custom data root can support cards and states. Exact current-build state behavior needs verification; an older open issue reports states ignoring the chosen root. | GitHub build: choose a writable shared custom data folder, enable its requested all-files access, grant that folder to Broomm. Private/Play-style storage may prevent this route. | ⚪ No general PS2 update/DLC package pipeline in the current scope. | 🔴 Current code imports/pins BIOS in app-private `externalFilesDir/bios`, even with shared data. Broomm can download and guide the import; completely automatic private placement has no confirmed public interface. |
| **DuckStation** / PS1 | 🟡 New Android beta supports selectable document-provider locations for data categories. Use accessible memory-card/state directories and per-game cards. Legacy app behavior needs a separate contract. | In a supported new beta, select shared/Broomm locations for cards, states and BIOS. A legacy build may need migration/export first. | ⚪ No general PS1 update/DLC package pipeline. | 🟡 Download into the selected BIOS folder and verify emulator recognition; legacy private-only BIOS storage is a separate constraint. |

## Upstream evidence and implications

**RetroArch.** Its document provider implements creation, deletion, renaming,
child checks and file access. It is enabled by the API-19 resource override on
supported modern Android versions. The sideloaded build exposes its app data;
the Play build additionally separates user data. `CONFIGFILE` and `LIBRETRO`
intent extras are consumed by the frontend. This gives us a concrete integration
route, including provider access to app-owned configuration/core directories.
It does not prove that copying a core there makes that specific APK load it:
ABI, permissions, dynamic-loading policy, core availability and the actual
resolved config paths still need validation. Keep Android core acquisition
separate from the desktop custom RetroArch release.
[Provider](https://github.com/libretro/RetroArch/blob/715d38f57745409f7b97b4f1eb70b848d3c2e4c8/pkg/android/phoenix/src/com/retroarch/browser/provider/RetroDocumentsProvider.java),
[enabled resource](https://github.com/libretro/RetroArch/blob/715d38f57745409f7b97b4f1eb70b848d3c2e4c8/pkg/android/phoenix/res/values-v19/bools.xml),
[intent reader](https://github.com/libretro/RetroArch/blob/715d38f57745409f7b97b4f1eb70b848d3c2e4c8/frontend/drivers/platform_unix.c).

RA BIOS requirements remain core/platform-specific: Opera/3DO, Beetle Lynx,
Beetle Saturn and some arcade sets need their own resources; Flycast has its own
system/flash layout. Game-specific dependencies and optional BIOS for other
cores must follow the selected core's contract. Automatic provisioning must use
RomM's platform resources and the current pinned core metadata, not accept an
arbitrary file because its name contains “BIOS.” The deferred Jaguar CD media
case stays deferred. Some cores expose no ordinary SRAM at all: Atari 2600 and
the currently selected Lynx route rely on states rather than inventing an empty
ordinary save. See [platform boundaries](platform-support-matrix.md).

**PPSSPP and melonDS.** PPSSPP persists its Memory Stick selection separately
and supports document paths. Its official DLC guide says placement varies by
game, often under `PSP/SAVEDATA`. Preserve DLC versus writable-save ownership
even where both use that parent. melonDS defaults to saving beside the ROM;
when launched without a known parent tree it falls back to its private saves
directory. Broomm's read-only game grant cannot serve as a writable save tree.
Its source explicitly permits a separate save root and state location.
[PPSSPP initialization](https://github.com/hrydgard/ppsspp/blob/v1.20.4/UI/NativeApp.cpp),
[DLC formats](https://www.ppsspp.org/docs/getting-started/how-to-install-dlc/),
[melonDS folder decisions](https://github.com/rafaelvcaetano/melonDS-android/blob/c42995caff0144f37ad9791dc9bc96d82e8a6f65/app/src/main/java/me/magnum/melonds/impl/SharedPreferencesSettingsRepository.kt).

**Azahar/MMJ CIA imports.** Azahar's picker schedules `CiaInstallWorker`; MMJ's
picker calls `NativeLibrary.InstallCIA`. Their inspected exported launch
contracts do not offer a corresponding external install-completion API. Broomm
cannot call another app's private Java/JNI method using an intent. A proper Dart
CIA importer can be implemented against accessible native title storage, but it
must handle title identity, tickets/TMD/content and relevant metadata, applicable
encryption and seeds, plus installation/removal/readback. Existing CIA metadata
parsing is not already that installer. A manual emulator import is a fallback,
not fulfillment of automatic installation.
[Azahar worker scheduling](https://github.com/azahar-emu/azahar/blob/01623d2fb707317410225c0eced82e3e0c84edc1/src/android/app/src/main/java/org/citra/citra_emu/ui/main/MainActivity.kt),
[MMJ installer](https://github.com/weihuoya/citra/blob/302b0c3bc4312bc96489c11584a97664894b343f/src/android/app/src/main/java/org/citra/emu/ui/MainActivity.java).

**Dolphin.** Its own `${applicationId}.user` provider exposes the initialized
user directory with full file operations. The separately exported startup
activity interprets supplied URIs as games/discs. WAD installation in its UI
calls internal `WiiUtils.installWAD`; handing it a WAD URI is not evidence of a
confirmed NAND installation. A Dart importer must preserve ticket/title/shared
content semantics and Wii save data when removing a package.
[Provider](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Android/app/src/main/java/org/dolphinemu/dolphinemu/features/DocumentProvider.kt),
[startup](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Android/app/src/main/java/org/dolphinemu/dolphinemu/utils/StartupHandler.kt),
[installer call](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Android/app/src/main/java/org/dolphinemu/dolphinemu/ui/main/MainPresenter.kt).

**Eden.** Its provider exposes the external app-data root. The inspected firmware
UI extracts NCAs into `nand/system/Contents/registered` and reinitializes the
system. This is distinct from encrypted NSP installation through its internal
native installer. Broomm already has Dart NSP extraction, NCA validation,
title association and common-ticket/title-key handling for desktop Eden; adapt
that implementation and its documented limits rather than assume a native
Android bridge is required. Firmware ZIP layout also needs Eden's flat NCA
layout, not blindly copying Ryubing's `.nca/00` layout.
[Eden provider](https://git.eden-emu.dev/eden-emu/eden/src/tag/v0.2.1/src/android/app/src/main/java/org/yuzu/yuzu_emu/features/DocumentProvider.kt),
[install actions](https://git.eden-emu.dev/eden-emu/eden/src/tag/v0.2.1/src/android/app/src/main/java/org/yuzu/yuzu_emu/utils/InstallableActions.kt),
`lib/src/addons/eden.dart`, `lib/src/progress/eden.dart`,
`lib/src/switch_firmware.dart`.

**ARMSX2.** Current 2.9.1 source resolves a custom data root, but separately
imports/migrates the active BIOS to its private BIOS directory and pins that
location. Its shared `bios` mirror is copy-only, not the boot source. A launcher-
prepared setup check skips onboarding only if a valid BIOS is already in the
private destination; it does not itself import a BIOS from a supplied URI.
The exported `romlibrary` provider is recent-game metadata, not a writable user-
data document provider. A BIOS import/public provider upstream would close
this gap without root or emulator patching. The open state-folder report
concerns 2.6.8; current source passes the selected root to the core. Neither
fact establishes current 2.9.1 device behavior.
[2.9.1 runtime](https://github.com/ARMSX2/ARMSX2/blob/2.9.1/platforms/android/app/src/main/java/com/armsx2/runtime/MainActivityRuntime.kt),
[BIOS importer](https://github.com/ARMSX2/ARMSX2/blob/2.9.1/platforms/android/app/src/main/java/com/armsx2/ui/bios/BiosManagerViewModel.kt),
[manifest](https://github.com/ARMSX2/ARMSX2/blob/2.9.1/platforms/android/app/src/main/AndroidManifest.xml),
[state-folder report](https://github.com/ARMSX2/ARMSX2/issues/661).

**DuckStation.** The official Android beta was rewritten and now advertises
individually selectable data locations supporting document providers. It
requires Android 7+, retains saves/cards/BIOS on migration but does not migrate
all settings. Current public master has no Android frontend source, so the
desktop code and older Android launch extras cannot prove this beta's exact
behavior. Validate both its launch contract and saved folder choices on-device.
Do not silently migrate a user's installed app during setup.
[Official beta and migration notes](https://downloads.duckstation.org/android-testing/).

## ARMSX2 discovery defect

Broomm currently allows/queries **only `com.armsx2`** in both the Dart roster and
Android manifest. Upstream stable defaults to that ID, but nightly uses
**`com.armsx2.nightly`**, which Broomm cannot discover. Older installations can
also carry `come.nanodata.armsx2` or `.debug`; these need their own inspected
activity/version contracts rather than blindly reusing the current namespace.
[Current build identity](https://github.com/ARMSX2/ARMSX2/blob/2.9.1/platforms/android/app/build.gradle.kts),
[nightly identity](https://github.com/ARMSX2/ARMSX2/blob/2.9.1/.github/workflows/nightly.yml),
[historical package report](https://github.com/ARMSX2/ARMSX2/issues/134).

This is a confirmed discovery gap and a plausible explanation of the owner's
symptom. The installed APK's actual identity/version is not known here. If it
is already stable `com.armsx2`, this gap alone does not explain the failure;
inspect package visibility/enabled state and the actual discovery exception.
Opening Broomm's download page does not record which APK the browser installed.
Do not recommend uninstalling to resolve detection: that can remove private
saves. Obtain the device's Android version and ARMSX2 channel/version/APK name
before claiming a definitive diagnosis of that device.

## APK download and installation proposal

Clicking **Install** should resolve the selected official compatible APK,
download it with progress/cancellation, inspect its package/activity/version/
ABI/signing information, and feed the existing Android installer. Android may
ask the user to allow this source and confirm installation. Read back the actual
installed package before reporting success or selecting it as default. A
signature/channel mismatch must not be “fixed” by uninstalling progress.
Emulator upgrades remain user-initiated.
[Android installation API](https://developer.android.com/reference/android/content/pm/PackageInstaller).

| App | Official automatic-download candidate | Relevant limit |
| --- | --- | --- |
| RetroArch | Official buildbot stable APKs; regular, AArch64 and 32-bit variants are linked on its platform page. | Select actual device/app ABI and retain package identity. Core downloads are separate. |
| PPSSPP | Official website's current free APK. | Gold remains a paid/store entitlement; do not replace it silently or claim a free Gold download. |
| melonDS | GitHub release APK (`app-gitHub-prod-release.apk`, 2.0.1 at audit). | Preserve source/signing channel and required Android version. |
| Azahar | GitHub vanilla APK (2126.2 at audit). | Do not select an AAB, libretro archive or unrelated variant by filename order. |
| MMJ | GitHub normal shared-storage APK (20251112 at audit). | Storage Access/AnTuTu builds need explicit distinct handling. |
| Dolphin | Official Dolphin download page links release APKs (2609a currently advertised). | Inspected storage source was 2609; compare any hotfix before adopting it. |
| Eden | Official Forgejo release links to standard/optimized/legacy/ChromeOS APKs (0.2.1 at audit). | Choose compatible standard variant unless a different variant is explicitly supported. |
| ARMSX2 | Official GitHub 2.9.1 assets include legacy ARMv8.0 and several ARMv8.2/SDK variants. | `arm64-v8a` alone does not prove ARMv8.2 CPU support. Match OS/minimum SDK and CPU; target SDK in the name is not by itself the minimum Android version. |
| DuckStation | Play Store, plus the official Android beta page. | Beta page explicitly requests linking to the page and prohibits redistribution. Do not bundle/rehost it; establish whether in-app direct downloading is permitted before depending on a hotlink. Keep store/page fallback. |

Primary release feeds/pages:
[RetroArch](https://www.retroarch.com/?page=platforms),
[PPSSPP](https://www.ppsspp.org/download/),
[melonDS](https://github.com/rafaelvcaetano/melonDS-android/releases/tag/2.0.1),
[Azahar](https://github.com/azahar-emu/azahar/releases/tag/2126.2),
[MMJ](https://github.com/weihuoya/citra/releases/tag/20251112),
[Dolphin](https://dolphin-emu.org/download/),
[Eden](https://git.eden-emu.dev/eden-emu/eden/releases/tag/v0.2.1),
[ARMSX2](https://github.com/ARMSX2/ARMSX2/releases/tag/2.9.1),
[DuckStation](https://downloads.duckstation.org/android-testing/).

Argosy also has a concrete download-then-installer workflow. It is useful
interface evidence, not imported code or proof that its save paths are
accessible to Broomm. A path in a registry is not a permission grant.
[Argosy downloader](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/emulator/EmulatorDownloadManager.kt).

## Profiles, synchronization and uninstall correctness

The proposed target is **one stable granted emulator folder**, with Broomm
holding private per-profile progress and journaled per-title copy/swap operations
around a session. Avoid making the user reselect an emulator folder on each
Broomm profile change. Preserve any original standalone save and restore it
after the session, as in the agreed MMJ design. A provider root must retain a
stable identity: never silently redirect an already-open descriptor to a new
active profile. Shared game/install content stays separate from writable saves.

Reuse the server/account/game-scoped **BROOMM** history and timestamped native
extensions, conflict baselines, explicit existing-save imports/backups, offline
pending snapshots and recovery. Android ordinary saves should share existing
desktop formats where the actual native format matches. States require their
own exact frontend/core/ABI/host compatibility identity; “cloud states” does not
promise Android-to-macOS state interchange.

There is no general Android notification proving a third-party native emulator
has flushed and stopped its game. Returning to Broomm or receiving an Activity
result can occur while it still runs. The current explicit **Finish and sync
progress** flow is a limitation, not fully automatic session completion.
Implement app-specific closure signals where available; otherwise retain an
explicit closure confirmation. Shared-folder writers cannot be tracked merely
by counting Broomm provider descriptors. A quiet/stable file is not proof that a
writer will not reopen it. Do not replace a native card or NAND while it is live.

Android can stop Broomm in the background. Durable session/transfer checkpoints
and resumable scheduled uploads are needed; “always running in the background”
cannot be assumed. Sealed pending snapshots can retry safely without reopening
live emulator data. Reboot, revoked grants and a missing SD card must leave
progress recoverable rather than be interpreted as an empty save.

Automatic add-on removal needs receipts for files Broomm actually installed,
content references shared by other installed versions, and platform-specific
metadata cleanup. Deleting a game must preserve saves and unrelated manually
installed content. The external Android emulator remains installed. A revoked
folder grant means cleanup is pending, not successful. These rules apply even
where the external emulator shares installations across Broomm profiles.

## Suggested implementation sequence and acceptance

1. Correct package/channel detection and implement official APK downloading;
   distinguish installed, launch-capable, folder-connected and cloud-ready in
   the UI. Keep installation and setup outcomes separate.
2. Replace per-profile folder reselection with stable-folder progress handoff;
   finish/verify PPSSPP, melonDS, Azahar and MMJ. Add Dolphin and RetroArch
   provider adapters, then DuckStation and ARMSX2 shared-card adapters and Eden
   account saves. Add each supported native state format with its build identity.
3. Provision accessible BIOS/key/firmware directories from RomM. Handle ARMSX2's
   private BIOS import honestly as assisted setup until an automatic public
   route is established. Do not mark that step automatic merely because the
   download succeeded.
4. Adapt Eden's existing Dart content staging to Android. Implement and test
   real CIA and Wii WAD installation/removal, rather than offering manual imports
   as completed automatic support. Finish native PSP formats with explicit
   unsupported-content feedback.

Each app needs on-device save creation → upload → remote history inspection →
local replacement → download → in-game load; two-profile separation; offline
changes/conflicts; interrupted swap/restart recovery; revoked grants and
still-running emulator refusal. Package-capable apps additionally need real
update/DLC detection in-game, idempotent repeat and removal while preserving
save/standalone content. BIOS-capable apps need a first-run missing-resource
test and successful subsequent boot without redownloading. Installation needs
both a fresh APK and upgrade/cancel/failure/readback tests.

The precise device ARMSX2 identity and legacy DuckStation contracts remain
unverified. No new dependency, root/Shizuku requirement, emulator fork or APK
redistribution was approved or introduced by this audit.

Retained source snapshots and official release metadata are in the ignored
`.tool-cache/research/android-parity-audit/` directory; the committed
[evidence index](android-parity-audit.json) records selected source hashes,
refs and known collection failures. Research helpers only perform bounded
read-only public HTTP requests. They do not run or modify external emulators.
