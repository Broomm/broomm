# RetroArch saves after owner testing

Follow-up on 2026-10-23. The [current matrix](platform-support-matrix.md) incorporates the owner's observations separately from native automated checks. Exact fixtures, commands, logs, source hashes and the macOS build are recorded in [the evidence](retroarch-save-followup.json).

The earlier “Boundary implemented; native save case pending” label meant that the file/sync code existed, while the selected short native session had not produced an ordinary save. It was incomplete verification, not a requirement for the owner to perform these tests. Selecting save-capable games exposed real errors that boot/pairing/state checks had missed.

## Corrections

**3DO / Opera:** the export supported a raw 32 KiB `.srm`, but upload verification rejected it as an unsupported console container. The concrete layout now supplies Opera's actual NVRAM path and version. Native raw export/import and BROOMM upload readback agree, including recovery of an already uploaded version after a lost acknowledgement. Native game/folder/core/global option precedence is inspected instead of assuming that `core-options.cfg` is the only settings file. Existing raw BROOMM versions are readable; no server version is renamed or deleted.

**Dreamcast / Flycast:** the pinned **6d81b99** build defaults to shared cards under `system/dc`, outside the declared per-game save folder. Its actual option is `reicast_per_content_vmus`, despite newer public documentation using a `flycast_` prefix. A session-only append configuration forces **All VMUs**, disables game-option overrides and uses `global_core_options=true` so an existing per-core `.opt` cannot override that decision. Other user preferences are inherited; the editable source settings are retained.

This binary names its private cards after the disc product ID, for example `MK-51035.A1.bin` for Crazy Taxi. The cloud boundary retains those native names inside the current game's private directory. ZIP imports accept raw 128 KiB VMU cards and reject truncated cards, firmware and console flash. Native checks inspect the emulator's open file handles to prove it uses these private cards. Its observed state filename also uses the ROM basename; that filename is normalized separately into the exact-build state group.

Older shared cards stay intact. When there is exactly one historical game, a durable migration record binds copies to that game before sync/play; the native core can perform its own legacy-name-to-product-ID migration. Interrupted copies are verified before continuing. Different existing private cards and ambiguous multi-game histories are preserved with an actionable error. Broomm does not guess which title owns an ambiguous shared card or silently replace a private card. This follow-up tests the owner's single-game Crazy Taxi history using disposable copies.

The owner's first Crazy Taxi upload was missing because the adapter was inspecting the wrong directory. The later crash correctly required explicit review, but the earlier build's tiny uploaded ZIP contained no VMU data. Resolving that old notification alone did not establish a VMU backup. The original local A1 card is still present and is the source for migration in the corrected build.

**Compressed cartridge games:** this pinned RetroArch frontend names saves after the outer ZIP, even though its content log names an inner ROM. Broomm previously looked for the inner basename. Genesis, Game Gear and Master System native tests now find and synchronize the real outer-name `.srm`; ambiguous archives still require selection/unpacking. The cloud logical name stays portable (`save/game.srm`). Existing native outer-name saves are discovered rather than replaced.

**Offline retry:** retained progress validation now accepts the underscores in actual core IDs such as `genesis_plus_gx` and `mednafen_lynx`. A retry without an installed game can reconstruct a supported raw-save boundary from its verified snapshot. Ordinary SRAM and state-only retry regressions cover native-data removal and confirmed BROOMM readback.

## What does and does not create an ordinary save

- **NES 1943:** the supplied NES 2.0 header has no battery flag or nonvolatile PRG/CHR RAM. Its native session produces no ordinary save, and Broomm does not upload an empty version. This is expected. Zelda provides a separate native 8 KiB battery-save check for the same emulator route.
- **Atari 2600:** the owner verified saved progress. The retained Asteroids upload is a state archive. The pinned Stella metadata advertises no ordinary Libretro save RAM; do not describe state-only progress as a tested cartridge SRAM upload.
- **Atari Lynx:** the BIOS is now available and launch is owner-verified. The pinned Beetle Lynx interface exposes system RAM, but returns no `RETRO_MEMORY_SAVE_RAM`; ordinary cartridge EEPROM is a core capability gap. Eye of the Beholder's native state upload/readback is verified. Supporting its ordinary cartridge EEPROM would require a separately reviewed/validated core change.
- **32X:** the owner verified Mortal Kombat II play. PicoDrive deliberately omits an all-zero EEPROM file until a game writes to it. The native NBA Jam TE test uses an explicit 8 KiB EEPROM sentinel to check native loading, retention, export/readback and restore. This does not claim a completed match or game-created save.
- **Saturn:** the catalogue was empty during this follow-up. After the owner added both BIOS files, [separate Saturn verification](saturn-verification.md) passed real provisioning, native launch/pairing/pause/remap, backup-memory round trips and matched state creation/loading/restore.
- **Jaguar CD:** native validation is deferred at the owner's request because compatible media is unavailable.

## Verification and reproduction

Final verification passes **291 Flutter tests**, **34 save-focused regressions** (included in that full suite), clean analysis and **11 native fixture cases** in one sequential run. The native cases cover nine platform routes, including the negative 1943 case, state-only Lynx, a seeded 32X EEPROM, Arcade NVRAM and fresh/legacy Dreamcast cards. Earlier native evidence plus these cases establishes ordinary-data round trips for 13 of the new RetroArch routes; the seeded 32X case is counted separately.

The save-focused native suite launches real pinned emulator/core binaries with cached authorized ROMs, joins a synthetic controller, runs briefly, closes normally and checks production capture/export/upload-readback/restore. Cartridge tests use Zelda, Sonic 3, Shining Force: The Sword of Hajya and Phantasy Star. Optical checks use copied Crash n Burn NVRAM and both existing/fresh Crazy Taxi cards; Lynx checks real serialized states. The 32X sentinel remains explicitly distinguished from game-created progress. An additional Arcade fixture exercises The Simpsons' EEPROM/NVRAM.

The native suite's RomM endpoint is an in-memory contract fixture; it does **not** upload or change the owner's server saves. It copies the owner's selected BIOS/save inputs under the production writer lease and verifies hashes. Owner-reported live Arcade/Atari results remain owner evidence. This does not establish a real two-device round trip, physical controller acceptance or another native host.

The macOS Apple Silicon development build is `build/releases/Broomm-macOS-arm64-save-fixes.zip` (**19,779,607 bytes**, SHA-256 `9db1d65d0e95f708787b6414c64b1430bd4f68f6d6e94b9c733c6707c4d06bc5`). The ZIP integrity and freshly extracted app's deep strict signature pass. The outer ad-hoc signature was refreshed after verifying the inner framework, matching the prior incremental packaging repair. This remains a checkout-bound, unnotarized build with no emulator/core/BIOS/ROM payload bundled.

```sh
devbox run -- flutter test test/retroarch_save_recovery_test.dart test/retroarch_systems_test.dart test/cloud_saves_test.dart
devbox run -- flutter test tool/check_retroarch_saves_test.dart --reporter expanded
devbox run -- flutter test
devbox run -- flutter analyze
devbox run -- bash tool/build_app.sh --release
```

The native test requires the locally cached media manifest under `.tool-cache/research/ra-save-followup/`, the pinned managed core sources, the existing 3DO/Lynx BIOS files, and the retained source saves. `BROOMM_SAVE_PLATFORMS=dc,3do,lynx,sega32` selects the optical/state/recovery subset; an empty fixture selection is an error. Native GUI checks run sequentially. All writer processes must exit before their temporary `native-*` folders are removed. Never delete normal profile progress, cloud snapshots or stable locks to retry a check.

For owner verification, close the previous Broomm build and open the updated macOS build. On 3DO, use **Options → Cloud saves → Sync / resolve conflict** to finish the retained version's readback; play/normal quit should append a later version without the format error. For Crazy Taxi, use that sync action or launch/quit normally: the sole-game legacy VMUs are copied and subsequent versions contain the native cards. Keep the original `system/dc` cards until gameplay confirms the migrated progress. Saves/states and all earlier RomM versions remain retained. The main walkthrough is also in [README.md](../README.md#verify-retroarch-save-corrections).

Primary format references: [Opera NVRAM paths](https://github.com/libretro/opera-libretro/blob/master/opera_lr_nvram.c), [Flycast VMU options](https://docs.libretro.com/library/flycast/#visual-memory-unit), [RetroArch option precedence](https://github.com/libretro/RetroArch/blob/master/runloop.c), [Beetle Lynx memory interface](https://github.com/libretro/beetle-lynx-libretro/blob/master/libretro.cpp), and [PicoDrive's save-RAM reporting](https://github.com/libretro/picodrive/blob/master/platform/libretro/libretro.c). Current upstream source is supporting research; the pinned binary's file handles, emitted files and readback establish the tested behavior.
