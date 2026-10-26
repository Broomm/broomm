# RetroArch expansion, Wii/Switch packages and Switch firmware

Implemented on 2026-10-23. This extends the pinned macOS arm64 pack. The [colored platform matrix](platform-support-matrix.md) separates code, native game checks, save-producing fixtures and outstanding prerequisites. The [evidence record](retroarch-wii-switch.json) contains source/output fingerprints and results. No PGCS code, Go helper or new Dart/package dependency was added.

The subsequent [owner-test save follow-up](retroarch-save-followup.md) corrects the ZIP basename assumption, Opera raw NVRAM readback, Flycast VMU paths/options and retained offline retry. Its new native checks and owner reports supersede the missing-BIOS/five-route/save-case statements below, which describe this original milestone.

## Delivered behavior

RetroArch now has 18 additional platform recipes backed by 14 independently pinned cores. Emulator Settings shows the appropriate core under each server platform; shared frontend installation does not falsely mark a missing core ready. Setup JSON `cores` entries install verified local binaries without replacing the frontend or other cores. Unknown core IDs/commands are rejected. Removing RetroArch validates its core-pack receipts and retains altered/unrecognized files and all profile progress; interrupted private core stages carry an ownership receipt. Configured alternatives/defaults retain the existing platform workflow. Core source URL, archive/binary hashes, license metadata and actual native version are in [retroarch-cores.json](../assets/setup/retroarch-cores.json).

Each profile/game/core gets its own `core-data/<core>/<RomM ID>/saves` and `states`. Simple cores normalize native SRAM/RTC names at the cloud boundary; a ZIP uses its one playable inner member's basename. Multiple candidate ROMs in an archive require unpacking/selection. Complex cores capture their whole private per-game save directory for NVRAM/VMU/backup RAM. A single SRAM exports as `.srm`; multi-file progress exports as a real ZIP. State compatibility includes both frontend and core hashes. Legacy SNES storage stays separate. Default core button labels, sticks/triggers and live testers use the existing pairing/pause/remap workflow; special peripherals/full Jaguar keypad are not complete.

Core firmware comes from an explicitly supplied `bios` resource or matching firmware records in the active RomM platform, with MD5 verification and private publication. Only the concrete console/media's firmware is considered; unrelated arcade/CD accessories are not fetched. Required missing BIOS files block launch with a repair instruction. Existing resources are retained. The current server snapshot lacks the BIOS needed by 3DO, Lynx and Saturn.

Home downloads and **Options → Download Updates and DLC** now include Wii and Switch. Both preserve completed base media on failure, reuse unchanged sources, import in disposable native staging, apply privately to each profile and retain saves/states on removal. A stable session/native writer lease excludes live game writers. Transfers/cancellation cannot publish incomplete native content. API content roles are retained in new library receipts so root-level package files are not offered as base games.

**Wii:** read WAD title/version/region metadata, reject system/IOS titles and unrelated channel updates/DLC, then call the pinned Dolphin native importer. Game-channel WADs are included as owned base content; disc games can receive attached DLC WADs. For disc/DLC associations that use different title namespaces, RomM's attachment is the association and the native region must match. Tickets/content are tracked independently from data directories. Shared NAND content uses its SHA-1 identity and preserves the console's existing content.map IDs; it never copies an importer's fresh map over a private console. Files subsequently used by other native titles are retained. Empty historical map rows may remain after payload removal, matching native index semantics. WiiWare and owned DLC save directories now have explicit cloud boundaries. Legacy installed WADs can prepare their base content at launch without a network dependency.

**Switch:** the disposable pinned Ryubing scanner decrypts native CNMT/NCA metadata, selects the highest detected update and enables DLC. It does not infer IDs or versions from filenames. Broomm reads this exact binary's `updates.json` and `dlc.json` schema (`is_enabled`, `path`, numeric title_id), validates package/title correspondence, rewrites staging paths to immutable managed package paths, then publishes selection metadata with preimage/recovery journals. Existing foreign selections are retained. Generations remain available while another installed version, inactive profile or retained native preimage references them. Removing the final reference collects those packages. A durable deletion intent authorizes retry even if recursive cleanup already removed an inner manifest.

**Switch automatic resources:** on missing resources before play or package inspection, require exactly one `.zip`, `prod.keys`, and `title.keys` in that platform's RomM BIOS/firmware catalogue. Verify downloads against RomM MD5, validate key-file structure, safely extract bounded NCA files, then publish the native `registered/<NCA ID>.nca/00` layout. Standard raw NCAs and installed `.nca/00` ZIP layouts are supported. No typo alias is accepted. Configured private keys/firmware and console/account identities are preserved; this provisions missing resources rather than automatically updating them. Linked, ambiguous, damaged or conflicting resources are kept with an actionable error. The public ZIP reader's default save limits remain unchanged; firmware extraction requests explicit larger bounds.

PS4 has no built-in shadPS4 entry and no special browsing/download restriction. Generic custom-emulator setup imports remain a future extension; the current importer is still pinned to the supported roster.

## Native findings and corrections

The original Switch check timed out even though native scanning had succeeded: this build writes `is_enabled` and `path`, rather than the field names inferred from the source reference. A disposable path-open trace established that the real base and add-on NSPs were opened; inspecting the native JSON established the contract. The corrected import passes the actual Pokémon Quest update and five DLC packages. Empty checksum strings in its RomM metadata are absence, not a zero CRC.

RetroArch's first save checks exposed two separate issues. The deprecated `-s` override bypassed the configured save directory seen by cores, so save RAM now uses the native basename and private save-directory configuration. More importantly, closing its Cocoa window in parallel with QUIT bypassed normal save-RAM teardown. The bridge now stops SDL sampling and leaves exit to the verified network command path; the managed configuration disables the frontend's quit-confirmation gate. GB/GBA/Jaguar/N64/PCE/GBC subsequently produced native SRAM, and their exported/imported ordinary-save digests matched. Native SNES pairing/remapping/close also passed with the same shutdown correction.

A firmware test initially overlapped a RetroArch GUI run and failed Ryubing's focus-dependent F5 pause acknowledgement. The unchanged firmware check passes when native GUI checks run sequentially. This is why focus-sensitive native checks are not run in parallel and why these results do not claim gamescope/fullscreen/physical-input acceptance.

## Verification

Final checks: **278 Flutter tests**, clean static analysis, **six native macOS Runner tests**, **15 native package/core/installer regressions**, the 13-title RetroArch suite, Switch firmware initialization, legacy SNES and real 14-core removal with unchanged private progress. The release archive passes ZIP integrity and strict/deep signature checks after fresh extraction.

- All 14 real core libraries pass full binary hashes, `retro_api_version`, system name/version/extensions and ABI loading.
- Thirteen real cached RomM titles pass launch, synthetic-controller join, native pause/resume, live face remap, native state creation and normal close: GB, GBC, GBA, NES, Genesis, Atari 2600, Jaguar, N64, 32X, Game Gear, Master System, PCE and Arcade. GB/GBC/GBA/Jaguar/N64/PCE also produce ordinary native saves and pass local export/import round trips. These are short automated native sessions, not owner gameplay.
- Two real WiiWare examples (My Life as a King / My Life as a Darklord) pass native WAD/DLC import, repeat without transfer/import, second private profile, shared-content handling and uninstall with progress retained.
- Real Pokémon Quest passes native update + five DLC inspection, repeat without transfer, second private profile and all-profile uninstall with progress retained.
- A fresh private Switch installation provisions a ZIP constructed from the supplied firmware plus supplied keys, recognizes native firmware **22.5.0**, loads the supplied 3D World title, acknowledges readiness/pause and exits normally. A second provision does no transfers. This tests the exact RomM response/download contract with local source fixtures; the live Switch firmware catalogue was empty at inspection, so no live firmware HTTP download is claimed.
- Package transaction tests cover changed foreign files, original restoration, multiple owners, cancellation, empty API checksums, partial deletion recovery and retained Wii DLC progress. ZIP/key tests cover ambiguity, rejected typo, NCA collisions and interruption. Existing native writer-lock/orphan and real ARM/Intel RPCS3 installer regressions pass.

The remaining native media checks are 3DO, Jaguar CD, Lynx, Dreamcast and Saturn, with required BIOS prerequisites where applicable. No automatic arcade parent/BIOS/CHD dependency acquisition or per-game special-peripheral mapping is claimed. In-game DLC recognition, native save creation for the WiiWare/DLC titles, physical controller feel, remote cross-device round trips and non-macOS runtime packs remain separate acceptance work. No owner game process, progress directory or remote save was changed by the isolated tests.

## Walkthrough and reproduction

Use Devbox and the pre-provisioned Apple SDK. Existing pinned emulator bundles remain local source inputs, rather than downloads embedded in the app. For a new development checkout, explicitly prepare the additional core cache:

```sh
devbox run -- dart tool/prepare_retroarch_cores.dart
devbox run -- bash tool/build_bridges.sh
devbox run -- flutter analyze
devbox run -- flutter test
devbox run -- flutter test tool/check_game_packages_test.dart tool/check_wii_packages_test.dart tool/check_retroarch_cores_test.dart tool/check_installer_guard_test.dart tool/check_rpcs3_installer_exit_test.dart --concurrency=1
devbox run -- flutter test tool/check_retroarch_play_test.dart
devbox run -- flutter test tool/check_retroarch_remove_test.dart
devbox run -- flutter test tool/check_switch_firmware_test.dart
BROOMM_SMOKE_GAMES=smw devbox run -- flutter test tool/smoke_managed_test.dart
devbox run -- bash tool/build_app.sh --release
```

The core preparation command is an explicit developer action, never app startup or an emulator auto-update. It verifies both archive and extracted binary hashes, confines extraction and refuses changed cached binaries or changed rolling provider artifacts. Its cache-hit checks pass for all 14 current pinned cores. A future provider rebuild may require an explicit new reviewed recipe; it cannot silently replace this pack.

Native fixtures require the cached authorized test media/firmware. Test artifacts/logs live under `.tool-cache/research/ra-wii-switch/`. Temporary fixture installs may be removed after their children have exited. Never remove an active writer lock or delete normal Broomm profile progress. The main application walkthrough is in [README.md](../README.md#retroarch-wii-and-switch-follow-up).

## Source provenance and distribution

A late packaging attempt found a missing generated Flutter Swift-package source after debug/release build transitions. Configuration-only regeneration did not restore it; cleaning generated build outputs and performing a full build through the approved SDK wrapper did. Native artifacts were restored with identical hashes, and final checks/archive verification passed. Build failure and repair logs are retained with the evidence; no SDK installation or global selection change was needed.

Dolphin uses the existing hash-pinned **2609** bundle. [WiiUtils.cpp](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Core/Core/WiiUtils.cpp) establishes native WAD effects. `native/dolphin_installer.inc` is original narrow C interop: executable hash plus ARM64 instruction guard, main-queue dispatch after initialization, native completion marker and no title boot. It links only pre-provisioned Apple AppKit/libSystem through the existing universal installer guard. It is not a copied emulator implementation or a domain workflow in C.

The supplied Ryubing runtime reports **1.3.3**. A [source reference snapshot](https://github.com/Leuconoe/Ryubing/tree/793ca017ff4f6e48b798a62d2486405bfc42ef39) helped locate the scanner and native firmware ZIP layout; it is a mirror/reference, not proof of exact binary equivalence. Actual binary JSON and native firmware/game checks establish the delivered contract. Native source versions can differ from published plist/source metadata.

RetroArch **1.22.2**, its existing SDL3 bridge and Snes9x core remain pinned. Additional cores come from [Libretro's official macOS ARM64 buildbot](https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/) and [primary core-info metadata](https://github.com/libretro/libretro-core-info). The binary-reported versions supersede stale info-file version labels. Primary source repositories and source-build entry points are recorded with each core; these are upstream prebuilt artifacts, not Broomm source builds. Reproducing upstream compilation requires the matching source/submodule/toolchain configuration; an archive hash and source hint alone are not a reproducible-build claim.

Core metadata licenses include GPL, LGPL, MPL, mixed and non-commercial terms (notably FBNeo, Genesis Plus GX, Opera and PicoDrive). Review corresponding source, original notices, bundled assets/embedded BIOS provenance and redistribution terms before shipping emulator payloads. This app archive ships only Broomm and its original native bridges; it includes no emulator, core, firmware, key or ROM binary. The C bridges' source/build recipe and hashes remain in the repository and evidence record; no new OS dependency was installed.
