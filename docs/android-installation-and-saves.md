# Android APK installation and connected saves

2026-10-30. This milestone implements APK acquisition/discovery and connected
save folders for the nine Android adapters. **Native Android acceptance remains
pending.** Flutter filesystem/channel regressions, Kotlin compilation and a
macOS application build do not establish real Android emulator behavior.

## Adopted scope

- Detect current ARMSX2 **`com.armsx2`** and **`com.armsx2.nightly`**, using their
  shared source namespace **`com.armsx2.MainActivity`**. Prefer enabled stable
  when both are installed. Keep their folder connections separate. Recovery and
  Return to emulator retain the package used by the original session.
- The owner accepts **explicit emulator-closure confirmation**. Returning from
  an emulator offers **Finished? Sync progress**. No process-exit hook or polling
  is added. Broomm explains that the emulator must be saved/closed first and
  honors the confirmation. Broomm's own save-transfer locks still prevent
  concurrent file operations; those are not emulator-process checks.
- BIOS/firmware provisioning and new content installers remain deferred. No
  additional Wii update integration is planned: the owner has no such media.
  Existing desktop WAD/DLC behavior is retained. Android has no pairing or
  injection/overlay stage.

## Install flow

**Emulator Settings → platform → Install** downloads the selected official APK
with byte progress and cancellation, then hands its private file to Android's
installer. Android still controls unknown-source permission, install confirmation
and upgrade signing compatibility. Broomm checks package, exported launcher and
minimum SDK; a successful download/handoff is not installation success.
Installed package readback selects a newly installed emulator as default. No
existing emulator or its data is uninstalled to bypass a signing failure.

PPSSPP uses its official free APK. melonDS, Azahar vanilla, MMJ normal shared-
storage and ARMSX2 use their official stable GitHub release assets; unsupported
or ambiguous assets fail visibly rather than choosing the first APK. ARMSX2
downloads the conservative ARMv8.0/SDK26 variant for ARM64 devices, avoiding
assuming every ARM64 CPU supports ARMv8.2. RetroArch uses its official 1.22.2
ABI-specific APK, Dolphin uses 2609a, and Eden uses its standard 0.2.1 APK.
These are explicit installs, not automatic emulator updates.

**DuckStation** opens its official Play Store listing; its beta page requests
linking rather than redistribution. **PPSSPP Gold** remains detectable and is
not replaced or uninstalled; downloading PPSSPP installs the free package.
**Install APK…** remains available for a user-provided compatible APK, including
ARMSX2 nightly. The installer receives a one-file, read-only capability.
Partial/failed downloads are discarded; redirected download hosts are confined
to the official delivery services. No runtime plugin or emulator APK is bundled.

## Connect once, use every Broomm profile

Close the emulator, then choose **Configure saves** on its card. Read its
instructions, configure the emulator's location and grant Broomm the same root.
The picker needs a shared folder or the emulator's own provider, not another
app's private `Android/data` directory through the system storage provider.
Setup probes create/write/readback/rename/delete using a random disposable file;
it does not overwrite an existing save or import standalone progress.

| App | Exact setup contract |
| --- | --- |
| PPSSPP / Gold | Select a shared **Memory Stick root** in PPSSPP, then grant that root in Broomm. It contains `PSP/SAVEDATA` and `PSP/PPSSPP_STATE`. |
| melonDS | Turn off saving beside the ROM. Select a custom save directory and set **Save state location → Save directory**. Grant that exact directory. Native `.sav` and `.ml0`–`.ml8` files are handled separately. |
| Azahar | Select a shared user-data root in Azahar, then grant it in Broomm. It contains `sdmc` and `states`. |
| Citra MMJ | Use the normal shared **Internal storage/citra-emu** folder and grant it. Private Storage Access builds remain unsupported. Verify MMJ's actual setting; Broomm cannot read that private preference. |
| Dolphin | Initialize it, then choose **Dolphin** from the picker's sidebar and grant the full user-data root. For GameCube set **both slots to GCI Folder**. Other games' GCI headers are excluded; Wii title saves are separate from NAND contents. |
| RetroArch | Install the required core and save its config. Choose **RetroArch → Core Data/app data**, containing `cores` and `files`. Broomm writes an independent configuration for the session with private save/state paths. It preserves global frontend settings and prevents automatic overrides from redirecting progress. Flycast/Opera use explicit per-game VMU/NVRAM options; accessible existing core options are retained, otherwise these two use core defaults with those required save options. Other cores retain their configured option path. |
| ARMSX2 | Use the GitHub build's shared custom **App Data Folder** and its requested all-files permission. Use standard global memory cards; disable per-game cards. Grant the complete root containing `PCSX2-Android.ini`, `memcards` and `sstates`. Configured card/state paths must remain within that grant. |
| DuckStation | Use a version with selectable locations. Under one shared parent put memory cards in `memcards` and states in `savestates`; use **Shared Between All Games**, with `shared_card_1.mcd` and `shared_card_2.mcd`. Grant the parent. Where accessible, settings are checked; private settings require the player's confirmation of this contract. Older private-only versions need migration first. |
| Eden | Initialize its console account and configure keys/firmware in Eden itself. Grant **Eden** from the picker sidebar. This adapter currently requires one unambiguous native console account; multiple Broomm profiles share it through isolated title-save swaps. Missing/ambiguous native accounts fail without replacement. |

Connection identity includes emulator and Android package, not the active RomM
profile. No folder reselection is required when switching Broomm profiles.
Server/account/game progress remains private under Broomm's normal profile
storage. An installed emulator without a connected folder leads to Emulator
Settings before Play; it no longer silently launches with unsynchronized saves.

Existing profile-specific Broomm provider roots and the original MMJ journal
remain readable for compatibility/recovery. Use Configure saves to adopt the
new shared connection before starting another game. Legacy ordinary progress
remains available for recovery/cloud actions; its unprovenanced states stay
local rather than being silently assigned to a newly computed build group.

## Session and cloud behavior

Play restores the current profile's **BROOMM** history into its private working
copy. Before native launch, a durable journal and complete original/working
copies are made; only the selected game's boundaries are swapped into the
external folder. On return, choose **Not finished** to leave the session active,
or save/close the emulator and confirm **Emulator closed · Sync progress**.
Broomm captures native progress, uses the existing cloud conflict/offline
pipeline, and restores the external app's original standalone saves. Shared
PlayStation cards are therefore isolated per Broomm profile/game while playing.
Existing external progress is not silently adopted into a RomM account.

Ordinary save formats/extensions match the existing adapters: DS raw `.sav`,
single SRAM `.srm`, native PlayStation cards, and native directory ZIPs for
multi-file systems. Timestamped BROOMM history, explicit **Use existing save
file**, named backups and offline pending snapshots remain the same workflows.
An empty session creates no empty remote save. A message explains when no save
files were found, so a folder mismatch is visible if the player did save.

State compatibility includes APK bytes and Android ABI, plus the actual
RetroArch core bytes when applicable. Installation timestamps invalidate caches
and launch observations, but do not split identical APKs into different state
groups across devices. Hashes are cached against fresh package/file metadata;
unchanged executables are not fully hashed on each launch. State groups have
**separate physical directories and cloud identities**, so a changed core/APK
cannot relabel old files as current. Eden has no states. Matching Android state
groups do not establish Android-to-desktop state portability.

Eden reads, rather than replaces, native account metadata. A bounded Android OS
AES primitive supports Dart identification of encrypted NSP/XCI headers with
the already configured `prod.keys`; it does not provision keys or firmware.
Per-title account/device saves follow 0.2.1's native choice: use the future path
only when that exact title path exists, otherwise use its legacy path. Another
title's account directory is not evidence of migration for this title.

## Recovery, effects and cleanup

Keep the emulator closed while finishing recovery. **Finish previous game
session** remains reachable after Broomm restarts. A surviving shared-swap
journal also exposes recovery if the general session marker was lost.
**Reconnect original save folder** restores a revoked grant without changing
the recorded identity or abandoning progress. A different selected tree is
rejected. Interrupted replacements resume from expected before/after hashes and
verified private copies; outside writes remain a conflict rather than deletion.

If normal recovery cannot complete, **Keep emulator folder unchanged · Finish**
(MMJ retains its existing label) ends the session without further native writes
or uploading uncertain progress. Original, working and captured recovery data
remain under `android/shared-session/<transaction>` or the legacy MMJ directory.
This is an explicit resolution, not automatic deletion. A pending offline save
is also sealed in the existing cloud store; connection restoration can retry it
without reading a live external writer.

Do not delete an unfinished session's marker/journal, snapshots, stable locks or
cloud pending data. Completed private recovery directories may be archived or
removed only after checking that normal restoration completed and all desired
progress/states are retained/synchronized. Clearing Android app data or
uninstalling Broomm deletes its private working/recovery copies; export/sync
first. Removing a game preserves these progress roots. This milestone does not
uninstall external Android apps or their manually installed packages.

## Verification

```sh
devbox run -- flutter --suppress-analytics analyze --no-pub
devbox run -- flutter --suppress-analytics test --no-pub
devbox --config tool/android run check
```

Focused regressions are in `test/android_apk_download_test.dart`,
`test/android_folder_sync_test.dart`, `test/android_emulators_test.dart` and
`test/mmj_shared_saves_test.dart`. They cover real Dart files/journals/cloud
history behind controlled Android boundaries: selected official assets,
download/cancel/truncation/redirect failure, stable/nightly precedence and
separate connections, two profiles, native DS extension/states, offline capture,
revoked/reconnected grants, interrupted mutation, standalone restoration, path
escape refusal, Eden account/path correspondence, core-cache invalidation,
physical state isolation and the return-confirmation widget.

The Kotlin command compiles against pinned APIs; **it is not an APK build or
Android execution**. This host still has no full Android SDK/device. Required
device acceptance: install/upgrade/cancel each official APK, retain the exact
folder choices, create/load a real save and state, inspect BROOMM history, play
two profiles, retry offline, revoke/regrant a folder, and recover an interrupted
session. DuckStation beta settings and ARMSX2 custom-folder behavior especially
need that native check. The [evidence record](android-installation-and-saves.json)
keeps local results and limitations separate from acceptance.
