# PlayStation and PlayStation 2 integration

The managed macOS Apple Silicon pack adds **DuckStation** for PS1 and **ARMSX2** plus **PCSX2 through an already installed Rosetta** for PS2. Each uses the emulator's existing SDL3 runtime and native pause methods. This adds no Dart dependency, helper service or emulator source patch. Linux, Windows and Android packages/native acceptance remain outstanding; Android retains the simpler external-app scope.

## Use and storage

1. Open **Emulator Settings → PlayStation → DuckStation → Set up**, or **PlayStation 2 → ARMSX2 / PCSX2 → Set up**. Review and start the setup in that card. These development recipes copy the reviewed private bundles under `prototype-data/{duckstation,armsx2,pcsx2}/`; they do not download arbitrary emulator releases. Both PS2 choices can be installed, with one selected as default. PCSX2 requires existing Rosetta on Apple Silicon; Broomm does not install it.
2. Put a raw **512 KiB PS1 BIOS** or **4 MiB PS2 BIOS** in that platform's RomM BIOS/firmware catalogue and rescan. Naming it `bios.bin` selects it ahead of other candidates. Without that name, exactly one compatible-sized `.bin` must exist. Broomm downloads it on the first launch for this profile, verifies RomM's checksum and the supported native structure, and reuses it. An existing invalid BIOS is preserved and reported. BIOS selection among multiple regional images and ZIP BIOS imports are outside this initial route.
3. Download a game, select **Play**, join with **L1+R1**, then hold **Start**. PS1 and PS2 expose two normal controller ports, with DualShock / DualShock 2 testers. Multitap, wheels, light guns and pressure-sensitive face buttons are not implemented. Use **L3+R1** to swap both face pairs. **R3+Select** opens the paused Broomm menu; controller reassignment applies in the same process. Disconnecting an assigned source pauses and reopens pairing.
4. Quit normally so the native emulator flushes its cards before cloud capture. Use the game's **Cloud saves** menu for explicit imports/backups/conflict resolution. Automatic versions use the account/game's `BROOMM` slot. One PS1 card exports as `.mcd`; one PS2 card as `.ps2`; multiple cards travel together as a native ZIP. A card without a game save can be created/formatted by the emulator or game; its presence alone does not establish a completed in-game save point.
5. **Open emulator** opens the same profile's private configuration without a game. Rendering preferences survive subsequent launches. Broomm refreshes its owned controller bindings, card/state paths and pause/focus behavior before gameplay. Close configuration normally before launching a game or changing emulator setup.

All paths below are relative to `broomm-data/profiles/<profile-id>/emulators/` in checkout builds:

| Data | Private path |
| --- | --- |
| DuckStation configuration | `duckstation/home/Library/Application Support/DuckStation/settings.ini` |
| DuckStation BIOS | `duckstation/system/bios.bin` |
| PS1 cards | `duckstation/games/<rom-id>/cards/card1.mcd`, `card2.mcd` |
| PS1 states | `duckstation/games/<rom-id>/states/` |
| PCSX2 configuration | `ps2/user/pcsx2/PCSX2/inis/PCSX2.ini` |
| ARMSX2 configuration | `ps2/user/armsx2/ARMSX2/inis/PCSX2.ini` |
| Shared PS2 BIOS | `ps2/system/bios.bin` |
| Shared PS2 cards | `ps2/games/<rom-id>/cards/slot1.ps2`, `slot2.ps2` |
| PS2 states | `ps2/games/<rom-id>/states/{pcsx2,armsx2}/` |

PS2 ordinary card data is shared between the two choices for the same profile/game. Their settings, caches and native state directories remain separate. Cloud state groups include the exact executable hash and host. Switching the default refreshes the cloud layout; it does not import an incompatible state into the other engine. Profiles and different RomM ROM records have independent cards, including different releases/discs. A single M3U launch can describe multiple PS1 discs, but disc switching and identity across separately downloaded ROM records still need explicit coverage.

The pinned PS2 `-datapath` argument is the parent of the actual product directory: native startup appends `PCSX2` or `ARMSX2`. DuckStation reads the child-only private `HOME` rather than a system settings path. No system emulator, normal home configuration or owner save is modified. Removing a managed executable or downloaded game preserves profile progress; remove disposable test roots only after all their emulator processes exit. Never delete a live lock file.

## Native formats and limits

PS1 accepts raw 128 KiB memory cards with the native `MC` header, including compatible raw files imported under another extension. PS2 accepts raw 8/16/32/64 MiB cards with ECC, a native formatted header or the initial blank-card header. Headered cards, folder cards and individual-game exports such as `.gme`, `.psv`, `.psu` need explicit conversion first. ZIP imports must contain only recognized cards; ambiguous names and unrelated content are rejected. No BIOS, settings or foreign state files are imported as a save.

Both native console sockets are configured with their normal pad type. An unassigned source delivers neutral input; dynamically unplugging an unassigned emulated socket is still a gap. This differs from Dolphin's implemented per-run socket switching. The native test checks source disconnection/reassignment, not an in-game count of plugged Sony controllers.

The entry chooser supports PS1 CHD/CUE/CCD/M3U/PBP/ISO/BIN/EXE and PS2 CHD/ISO/CSO/BIN/GZ/ELF. PS1 playlists/descriptors take priority over their raw tracks. Native checks use one CHD per platform; advertising an emulator-supported extension does not verify every media format, region, game or multidisc workflow. These consoles have no Broomm update/DLC package pipeline in this milestone.

## Pinned upstream builds and provenance

| Choice | Official release | Execution tested |
| --- | --- | --- |
| DuckStation | `0.1-12083-g00e299795`, macOS universal | ARM64 slice |
| PCSX2 | `v2.8.2`, `fd9d310`, macOS Qt | x86-64 through existing Rosetta |
| ARMSX2 | `nightly-20261023`, `90126bdfea`, macOS ARM64 | ARM64 |

Official archive sizes/digests were checked before extraction. Only private test copies were ad-hoc signed to permit the existing injection mechanism. [The evidence record](playstation-support.json) distinguishes original and prepared executable hashes. Trusted file/link inventories and reviewed native symbols are in `assets/setup/`; manifests cannot introduce hook addresses or arbitrary binaries. `tool/capture_playstation_setup.dart` reproduces metadata only for these reviewed prepared executable hashes.

Reference source informed independently written Dart configuration and C interop. DuckStation's pinned source license is **CC BY-NC-ND 4.0**; PCSX2 and ARMSX2 use **GPLv3**. Preserve all upstream bundle notices. Emulator payloads, BIOS files and ROMs are excluded from the Broomm app ZIP. This local-source development recipe is separate from a distributable emulator installer and its corresponding license/notices requirements.

The pause bridge calls the exact build's Qt core/emulation-thread method, which marshals to the owning thread. DuckStation acknowledgment comes from UI-thread flags updated by native started/paused/resumed notifications. PS2 acknowledgment reads the native atomic VM state. Input remains gated until native pause and the requested routing revision are confirmed. Physical SDL devices are filtered from the emulator's numbered input routes; Broomm's own source discovery still reads them directly.

Primary sources: [DuckStation release](https://github.com/stenzek/duckstation/releases/tag/latest), [pinned DuckStation source](https://github.com/stenzek/duckstation/tree/00e299795), [PCSX2 2.8.2](https://github.com/PCSX2/pcsx2/releases/tag/v2.8.2), [ARMSX2 desktop nightly](https://github.com/ARMSX2/ARMSX2/releases/tag/nightly-20261023). Source archive hashes, runtime hashes and verification results are retained in the evidence record.

## Verification and reproduction

```sh
devbox run -- dart tool/capture_playstation_setup.dart
devbox run -- bash tool/build_bridges.sh
devbox run -- flutter test test/playstation_test.dart --reporter expanded
devbox run -- flutter test tool/check_playstation_test.dart --reporter expanded
devbox run -- flutter test tool/smoke_managed_test.dart --reporter expanded
```

The native check expects the reviewed prepared bundles plus the owner's read-only cached Crash Bash and Harvest Moon: Save the Homeland media/BIOS listed in `.tool-cache/research/playstation/media.json`. It creates a disposable `native-*` data root, installs real managed copies, provisions actual BIOS bytes through the production firmware workflow, boots each emulator, joins a synthetic controller, pauses/remaps, disconnects/reassigns, saves native states and performs cloud upload/readback/native export/restore through an in-memory RomM contract fixture. PS2 also loads a native state. PS1 state creation and snapshot restoration are separate from an in-emulator state-load check. No owner-server save writes or changes to the owner's progress are part of this test.

Final results, source/build fingerprints, failed diagnostic runs and release output are recorded in [playstation-support.json](playstation-support.json). The support matrix distinguishes this native automation from physical-controller, in-game save-point, cross-device and non-macOS acceptance. The existing separate Flutter window remains the desktop menu implementation; this milestone does not establish gamescope overlay behavior.

On 2026-10-23, analysis and **299 Flutter tests** pass, including eight PlayStation regressions. The sequential three-emulator native suite passes in **3m28s**; the existing six-game managed regression passes in **4m28s**. The universal SDL2/SDL3 bridges compile for ARM64 and x86-64; separate Clang static-analysis runs report no analyzer findings. No runtime sanitizer run is claimed. The macOS release and freshly extracted ZIP pass archive integrity and deep/strict ad-hoc signature verification.

| Native check | Ordinary data exercised | States exercised |
| --- | --- | --- |
| DuckStation / Crash Bash | 131,072-byte native `.mcd`, upload/readback/export/restore | Native slot and resume files; exact snapshot restore |
| ARMSX2 / Harvest Moon: Save the Homeland | Two native blank 8,650,752-byte ECC cards, ZIP upload/readback/restore | Native slot save/load; matching snapshot restore |
| PCSX2 / same title/profile | Same cards retained from ARMSX2, separate native settings | Native slot save/load; separate state group with prior engine states retained in cloud history |

Native diagnostics caught the PS2 product suffix added to `-datapath` and missing `.mcd`/`.ps2` recognition during cloud-version readback; both are corrected and covered. Failed test attempts also exposed a neutral-input/readiness race in the harness and restore code in the harness that discarded its sync checkpoint. The accepted run uses an explicit fresh-sample barrier and retains that checkpoint. Earlier logs remain available; they are not counted as passing checks.
