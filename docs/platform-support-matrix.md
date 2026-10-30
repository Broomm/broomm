# RomM platform and emulator support matrix

**Emulator additions, 2026-10-29, Android follow-up 2026-10-30:** [Astris (macOS 15+ ARM64) and Citra MMJ (Android)](astris-and-citra-mmj.md) are now selectable. Astris has native launch/controller/update/DLC and ordinary-save ZIP checks. Android's nine adapters now have 🟡 [connected ordinary saves and matching states](android-installation-and-saves.md) (Eden has no states), plus official APK acquisition and stable/nightly ARMSX2 detection. Native Android acceptance and new content/firmware installers remain outstanding. Defaults require a configured emulator and successful setup changes the default. Older evidence remains scoped to its emulator/host.

**Setup delivery, 2026-10-27:** all twelve macOS frontends and all fifteen RetroArch cores now download through bundled recipes; no external pack/import is required. RetroArch uses Broomm/retroarch v0.1.0. Seven official Libretro builds replace the offline core inputs; the other eight libraries retain their hashes. Native ABI, thirteen game/state cases, four BIOS-based routes and Genesis/Master System/Game Gear/Arcade native save round trips pass. Existing cores remain usable until explicit setup; ordinary saves are retained and incompatible states have separate physical and cloud identities. Earlier per-platform evidence below retains its stated scope. Other desktop frontends are published and verified, but their Broomm core/bridge acceptance is pending. See [delivery status](managed-setup-downloads.md) and [new core versions](retroarch-public-cores.md).

**Android update, 2026-10-30:** the [separate Android table](android-emulators.md#coverage) records APK acquisition, one-time folder setup, profile-isolated save/state swaps and remaining native storage/package gaps. Returning from an emulator offers explicit closure confirmation before synchronization. Android native acceptance is outstanding. The green cells below retain their stated macOS scope.

Snapshot: **2026-10-23**, **romm.docubi.casa / RomM 5.4.0**: **29 platforms, 7,660 ROM records**, including versions/regions. The earlier authenticated inventory is retained; read-only test media downloads did not modify the catalogue or server saves.

**28 platforms have progress adapters**, including **18 additional RetroArch routes using 14 pinned cores**. Native macOS game checks now cover **17** of those RA routes, plus PS1 through DuckStation and PS2 through both ARMSX2 and PCSX2/Rosetta. **Fourteen** RA routes have ordinary native-data export/readback/restore checks; 32X additionally has a seeded EEPROM load/round-trip check, without a completed-match claim. Atari 2600 and Lynx use cloud states because the pinned cores expose no ordinary cartridge-save interface. Saturn BIOS provisioning and native progress are verified; Jaguar CD validation is deferred at the owner’s request. PSP now has two native game-created save/state checks through PPSSPP. Switch additionally offers Eden with native input/update checks; its macOS distribution is experimental. PS4 has no built-in emulator.

🟢 = implemented with the indicated native evidence. 🟡 = implemented boundary with the stated prerequisite or native check outstanding. 🔴 = missing integration. ⚪ = not applicable/unavailable. **A green cell does not establish every title, physical input, cross-device cloud acceptance or another host.** `RA` means RetroArch. The delivered runtime pack remains **macOS arm64**; Linux/Steam/gamescope, Windows and Android native delivery remain outstanding.

## Current support

| Platform (`slug`) | ROMs | Emulator | Launch | Updates / DLC | Cloud saves | Cloud states |
| --- | ---: | --- | --- | --- | --- | --- |
| 3DO Interactive Multiplayer (`3do`) | 33 | RetroArch / Opera | 🟢 Owner + native game checked | ⚪ No package pipeline | 🟢 Native NVRAM round trip; readback fixed | 🟢 Owner + native state checked |
| Arcade (`arcade`) | 897 | RetroArch / FinalBurn Neo | 🟢 Native game checked | ⚪ No package pipeline | 🟢 Owner cloud + native NVRAM checked | 🟢 Matched build checked |
| Atari 2600 (`atari2600`) | 44 | RetroArch / Stella | 🟢 Native game checked | ⚪ No package pipeline | ⚪ No cartridge SRAM in pinned core | 🟢 Owner cloud progress verified |
| Atari Jaguar (`jaguar`) | 14 | RetroArch / Virtual Jaguar | 🟢 Native game checked | ⚪ No package pipeline | 🟢 Native file round trip | 🟢 Matched build checked |
| Atari Jaguar CD (`atari-jaguar-cd`) | 2 | RetroArch / Virtual Jaguar | ⚪ Native validation deferred | ⚪ No package pipeline | ⚪ Deferred | ⚪ Deferred |
| Atari Lynx (`lynx`) | 15 | RetroArch / Beetle Lynx | 🟢 Owner + native game checked | ⚪ No package pipeline | ⚪ Cartridge EEPROM not exposed by core | 🟢 Native cloud state checked |
| Dreamcast (`dc`) | 136 | RetroArch / Flycast | 🟢 Owner + native game checked | ⚪ No package pipeline | 🟢 Native VMU round trip; paths fixed | 🟢 Native matched state checked |
| Game Boy (`gb`) | 586 | RetroArch / Gambatte | 🟢 Native game checked | ⚪ No package pipeline | 🟢 Native file round trip | 🟢 Matched build checked |
| Game Boy Advance (`gba`) | 1045 | RetroArch / mGBA | 🟢 Native game checked | ⚪ No package pipeline | 🟢 Native file round trip | 🟢 Matched build checked |
| Game Boy Color (`gbc`) | 558 | RetroArch / Gambatte | 🟢 Native game checked | ⚪ No package pipeline | 🟢 Native file round trip | 🟢 Matched build checked |
| Nintendo 3DS (`3ds`) | 515 | Azahar | 🟢 Integrated (macOS) | 🟢 Implemented: CIA | 🟢 Implemented | 🟢 Matched build |
| Nintendo 64 (`n64`) | 304 | RetroArch / Mupen64Plus-Next | 🟢 Native game checked | ⚪ No package pipeline | 🟢 Native file round trip | 🟢 Matched build checked |
| Nintendo DS (`nds`) | 539 | melonDS | 🟢 Integrated (macOS) | ⚪ No package pipeline | 🟢 Implemented | 🟢 Matched build |
| Nintendo Entertainment System (`nes`) | 710 | RetroArch / Mesen | 🟢 Native game checked | ⚪ No package pipeline | 🟢 Native SRAM upload/readback/restore | 🟢 Matched build checked |
| Nintendo GameCube (`ngc`) | 137 | Dolphin | 🟢 Integrated (macOS) | ⚪ No package pipeline | 🟢 Implemented | 🟢 Matched build |
| Nintendo Switch (`switch`) | 76 | Ryubing / Eden / Astris (macOS 15+ ARM64) | 🟢 Native checks for all three (macOS) | 🟢 Native NSP selection / NAND | 🟢 Implemented; native Astris ZIP and seeded Eden checks | ⚪ Unavailable |
| PlayStation (`psx`) | 248 | DuckStation ARM64 (macOS) | 🟢 Native game / pairing checked | ⚪ No package pipeline | 🟢 Native .mcd round trip | 🟢 Native state creation / snapshot restore |
| PlayStation 2 (`ps2`) | 160 | ARMSX2 ARM64 / PCSX2 Intel through Rosetta (macOS) | 🟢 Both native game / pairing checked | ⚪ No package pipeline | 🟢 Shared native cards round trip | 🟢 Separate native state load / restore |
| PlayStation 3 (`ps3`) | 30 | RPCS3 ARM / RPCS3 Intel / Rosetta (macOS) | 🟢 Integrated (macOS) | 🟢 Implemented: PKG + RAP | 🟢 Implemented | ⚪ Unavailable |
| PlayStation 4 (`ps4`) | 20 | None built in | 🔴 No built-in emulator | ⚪ No built-in installer | ⚪ No integration | ⚪ No integration |
| PlayStation Portable (`psp`) | 139 | PPSSPP ARM64 (macOS) | 🟢 Two native games / pairing checked | 🟡 Native folders / ZIP; patch execution limited | 🟢 Native game-created savedata round trip | 🟢 Native state save / load / restore |
| Sega 32X (`sega32`) | 16 | RetroArch / PicoDrive | 🟢 Owner + native game checked | ⚪ No package pipeline | 🟢 Native EEPROM load/round trip | 🟢 Matched build checked |
| Sega Game Gear (`gamegear`) | 52 | RetroArch / Genesis Plus GX | 🟢 Native game checked | ⚪ No package pipeline | 🟢 Native SRAM upload/readback/restore | 🟢 Matched build checked |
| Sega Master System/Mark III (`sms`) | 94 | RetroArch / Genesis Plus GX | 🟢 Native game checked | ⚪ No package pipeline | 🟢 Native SRAM upload/readback/restore | 🟢 Matched build checked |
| Sega Mega Drive/Genesis (`genesis`) | 154 | RetroArch / Genesis Plus GX | 🟢 Native game checked | ⚪ No package pipeline | 🟢 Native SRAM upload/readback/restore | 🟢 Matched build checked |
| Sega Saturn (`saturn`) | 71 | RetroArch / Beetle Saturn | 🟢 Native game checked | ⚪ No package pipeline | 🟢 Native backup-memory round trip | 🟢 Native state load / restore checked |
| Super Nintendo Entertainment System (`snes`) | 779 | RetroArch / Snes9x | 🟢 Integrated (macOS) | ⚪ No package pipeline | 🟢 Implemented | 🟢 Matched build |
| TurboGrafx-16/PC Engine (`tg16`) | 92 | RetroArch / Beetle PCE Fast | 🟢 Native game checked | ⚪ No package pipeline | 🟢 Native file round trip | 🟢 Matched build checked |
| Wii (`wii`) | 194 | Dolphin | 🟢 Integrated (macOS) | 🟢 WAD titles / DLC / tickets | 🟢 Implemented | 🟢 Matched build |

Cloud-save adapters use the existing **BROOMM** slot history and native file extensions. A single supported RetroArch SRAM/Opera NVRAM is exported as `.srm`; companion files and VMUs travel together in a native ZIP. Compressed cartridge saves follow this frontend’s outer ZIP basename. Flycast preserves native disc-ID card names in an isolated game directory. The owner’s Atari 2600 upload is a state archive, rather than an ordinary cartridge save. Save states stay in exact frontend/core/build/host compatibility groups. RPCS3, Ryubing and Eden have no state sync. ROMset revisions and disc dependencies are content requirements, not DLC installers. Most older cartridges have no update/DLC workflow; a game without battery-backed storage may only produce save states.

## Concrete gaps

| Platform | Remaining checks / limits |
| --- | --- |
| 3DO Interactive Multiplayer | Owner verified launch and states. Native Crash n Burn NVRAM export/readback/restore passes after the raw .srm fix. BIOS is now present in RomM. Physical/cross-device acceptance remains separate. |
| Arcade | Owner reports cloud saves verified. Native The Simpsons NVRAM export/readback/restore checked separately. Original ROMset filename and matching FBNeo set/BIOS required; parent/CHD acquisition and driver-specific controls remain gaps. |
| Atari 2600 | Owner verified cloud progress; retained Asteroids evidence is a save-state archive. Pinned Stella advertises no Libretro save RAM. Paddles and special peripherals remain outside this pad route. |
| Atari Jaguar | Default pad/EEPROM/state route exercised; full keypad/ProController and native physical input remain gaps. |
| Atari Jaguar CD | Deferred at the owner’s request: no compatible test media available. The existing adapter/core remains; no extra CD work is included in this follow-up. |
| Atari Lynx | lynxboot.img is now present and owner verified launch. Eye of the Beholder native save-state upload/readback passes. Pinned Beetle Lynx exposes system RAM but no save RAM, so ordinary cartridge EEPROM is an upstream capability gap, not an unexecuted Broomm save test. Rotation/peripheral coverage remains separate. |
| Dreamcast | Crazy Taxi fresh and legacy VMUs pass native handle inspection, cloud readback and restore. Saves use native disc product IDs; console flash stays private and outside cloud saves. Sole-game legacy shared cards migrate without deleting originals; ambiguous histories need explicit migration. Owner crash prompted the expected review; original missing upload was a VMU path bug. |
| Game Boy | Native SRAM and states exercised; RTC multi-file unit round trip covered; physical gameplay and cross-device acceptance pending. |
| Game Boy Advance | Native raw SRAM/RTC and states exercised; game-specific flash/EEPROM coverage and cross-device acceptance pending. |
| Game Boy Color | Native SRAM and states exercised; physical gameplay and cross-device acceptance pending. |
| Nintendo 3DS | Decrypted CIA only; verify additional extdata/title cases and native hosts |
| Nintendo 64 | Native SRAM and states exercised; Controller Pak and nonstandard/64DD peripherals need additional coverage. |
| Nintendo DS | Raw .sav supported; DSV/container conversion and DSi scope remain separate |
| Nintendo Entertainment System | Zelda native 8 KiB SRAM upload/readback/restore passes. Owner’s NES 1943 header has no nonvolatile memory and a native session confirms no ordinary save or empty upload. FDS/peripheral coverage remains separate. |
| Nintendo GameCube | GCI-folder saves only; raw shared cards and additional formats need validation |
| Nintendo Switch | Ryubing keeps native highest-version NSP selection. Eden has native controller/pause/remap checks, one update NSP plus multiple DLC native NAND installation, private firmware/keys, and seeded save-directory cloud round trip. Pokémon Quest update is loaded by native Eden. In-game DLC recognition, game-created Eden saves, longer gameplay and physical/other-host acceptance remain; no save states. |
| PlayStation | Crash Bash CHD boot, automatic BIOS bytes, pause/live remap, disconnect/reassignment, native .mcd export/readback/restore and native states pass. No completed save-point or in-emulator state-load claim. Two pad sockets stay configured; dynamic emulated unplugging, multitap, multidisc switching, physical input and other hosts remain. |
| PlayStation 2 | Harvest Moon: Save the Homeland CHD boot, BIOS, pause/live remap, disconnect/reassignment and native card/state round trips pass in ARMSX2 ARM64 and PCSX2/Rosetta. Cards share one profile/game boundary; states/settings remain engine-specific. Tested cards were native blank cards, not completed in-game progress. Dynamic emulated unplugging, multitap, pressure-sensitive controls, physical input and other hosts remain. |
| PlayStation 3 | Known installer teardown now handled; per-title savedata mappings and gameplay verification |
| PlayStation 4 | No built-in emulator or shadPS4 recipe. Browsing/download/removal remain ordinary. Arbitrary custom-emulator JSON imports are a requested future extension; current importer remains pinned-roster only. |
| PlayStation Portable | N+ and Puzzle Bobble Pocket CSO boot, actual native buttons, pause/live remap, disconnect/reassignment and native state load/restore pass. N+ is the required game-created savedata round trip; Puzzle Bobble ordinary progress depends on reaching a save point, with state-only cloud bundles checked otherwise. Native destination/ZIP DLC ownership is exercised with fixtures; generic PKG/game-specific patch execution, real PSP DLC gameplay, unknown homebrew identities, ZSO/CSO2, physical pads and other hosts remain. |
| Sega 32X | Owner verified Mortal Kombat II launch. NBA Jam TE native EEPROM load/export/restore passes with an explicitly seeded 8 KiB fixture; this does not claim a completed match or game-created save. PicoDrive deliberately suppresses all-zero EEPROM files. Native states were already checked. |
| Sega Game Gear | Shining Force: The Sword of Hajya compressed-ROM native SRAM upload/readback/restore passes. Physical input and cross-device acceptance remain separate. |
| Sega Master System/Mark III | Phantasy Star compressed-ROM native SRAM upload/readback/restore passes. Physical input and special peripherals remain separate. |
| Sega Mega Drive/Genesis | Sonic 3 compressed-ROM native SRAM upload/readback/restore passes after correcting outer-ZIP save names. Six-button/EEPROM title coverage and cross-device acceptance remain separate; Mega-CD is outside this route. |
| Sega Saturn | The Legend of Oasis passed automatic BIOS provisioning, native launch/pairing/pause/live remap, backup RAM/cartridge/settings export/readback/restore and state creation/loading/restore. Both regional BIOS files match expected checksums; only the USA game was booted. Multidisc, game-specific cartridges, in-game save-point progress, physical input and cross-device acceptance remain separate. |
| Super Nintendo Entertainment System | Existing Snes9x path retained; packed SNES cloud saves remain unvalidated. Quit now flushes through the native frontend. |
| TurboGrafx-16/PC Engine | Native cartridge SRAM and states exercised; System Card required for CD media; CD and 6-button modes need coverage. |
| Wii | WAD game/channel and DLC imports, tickets/shared content, two-profile removal and progress retention exercised. In-game DLC and new WiiWare/DLC save gameplay still need owner acceptance. |

## Package and firmware coverage

- 🟢 **3DS / Azahar:** decrypted CIA updates/DLC, private deployment and owned uninstall.
- 🟢 **PS3 / RPCS3 ARM and Intel:** PKG/RAP, automatic missing PUP installation and owned uninstall. Native installer teardown remains guarded.
- 🟢 **Wii / Dolphin:** WAD game channels, matching channel updates, DLC, tickets and shared NAND contents. System/IOS WADs are rejected. Disc/DLC association comes from the RomM game attachment, with native region validation. Base and DLC progress are kept when content is removed.
- 🟢 **Switch / Ryubing and Eden:** Ryubing native NSP metadata scanning selects updates and enables DLC without booting the game. Eden installs validated native NCAs into its own NAND, currently accepting one update NSP and multiple DLC NSPs; native Pokémon Quest update loading is verified. Missing firmware/keys can be installed from exactly **one firmware ZIP, `prod.keys`, and `title.keys`** in the platform's RomM BIOS/firmware catalogue. Existing configured resources are retained. No automatic emulator/firmware update is introduced.
- 🟢 **PS1 / PS2:** missing profile-private `bios.bin` is provisioned from the matching RomM platform, with checksum/native format validation and reuse. PS1 uses a 512 KiB image; both PS2 engines share a 4 MiB image. No update/DLC package pipeline applies in this milestone.
- 🟡 **PSP / PPSSPP:** private memstick, per-title native DLC files/ZIP, owned cleanup and cloud/state boundaries implemented. Generic patch execution and real DLC gameplay remain separate. No BIOS is needed.

## Scope and next work

PS4 has no custom runtime restriction and no shadPS4 entry. A user-provided generic emulator JSON format is a future extension: today's setup importer accepts the pinned supported roster only. It must not be described as an already working arbitrary-emulator plugin system.

The earlier generic “native save case pending” label reflected incomplete testing, not a requirement that the owner test these boundaries. This follow-up uses save-capable titles and the actual native files; see the [save findings and evidence](retroarch-save-followup.md). Saturn’s [separate native check](saturn-verification.md) closes its BIOS and backup-memory prerequisite. The [PlayStation integration](playstation-support.md) adds three native emulator checks and private memory-card/cloud boundaries. Remaining cases include deferred Jaguar CD media and title-specific checks such as a game-created 32X EEPROM write. Full Jaguar keypad/special peripherals and native Linux/Steam validation remain separate. PPSSPP/Eden physical input and other hosts still require acceptance. Arcade media must use its original set name and a matching FBNeo set; automatic parent/BIOS/CHD dependency resolution is not implemented. Android retains its external-app handoff scope without desktop controller injection or overlays.

Cemu/Wii U, Vita3K/PS Vita and xemu/original Xbox remain in the approved roster but are absent from this server inventory. RetroAchievements and PC/Proton runners remain deferred.

## Evidence and sources

The [implementation and native evidence](retroarch-wii-switch.md), [machine-readable record](retroarch-wii-switch.json), [pinned cores](../assets/setup/retroarch-cores.json), [runtime routes](../lib/src/game_launch.dart) and [progress boundaries](../lib/src/progress/layout.dart) distinguish integration from verification. The [JSON inventory](platform-support-matrix.json) retains exact platform IDs/counts. [PPSSPP/Eden implementation and evidence](psp-and-eden-support.md) retain native results, formats and remaining limits.

Primary references: [Libretro core catalogue](https://docs.libretro.com/guides/core-list/), [FBNeo media requirements](https://docs.libretro.com/library/fbneo/), [Virtual Jaguar](https://docs.libretro.com/library/virtual_jaguar/), [Mupen64Plus-Next](https://docs.libretro.com/library/mupen64plus/), [Beetle Saturn](https://docs.libretro.com/library/beetle_saturn/), [Genesis Plus GX](https://docs.libretro.com/library/genesis_plus_gx/), [PicoDrive](https://docs.libretro.com/library/picodrive/), [Dolphin's pinned WAD importer](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Core/Core/WiiUtils.cpp), [RPCS3](https://github.com/RPCS3/rpcs3), [DuckStation](https://github.com/stenzek/duckstation), [ARMSX2](https://github.com/ARMSX2/ARMSX2/releases), [PCSX2](https://github.com/PCSX2/pcsx2) and [PPSSPP DLC guidance](https://www.ppsspp.org/docs/getting-started/how-to-install-dlc/).

Core licenses differ from RetroArch's license. Some selected cores have non-commercial or mixed terms. No emulator, BIOS, keys or ROM payload is bundled in the Broomm app ZIP. The pinned local-source recipes do not authorize redistribution without their own corresponding-source/notices review.
