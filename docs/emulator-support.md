# Initial emulator scope and setup files

The [Astris/Citra MMJ follow-up](astris-and-citra-mmj.md) adds the managed Astris macOS alternative and Android MMJ direct launch. The newer [Android installation/save milestone](android-installation-and-saves.md) adds APK acquisition and connected ordinary saves/matching states across its nine adapters (Eden has no states), including MMJ and both ARMSX2 channels. Native Android acceptance and new content/firmware installers remain outstanding. Only configured emulators have a default; successful setup selects the newly installed emulator. Historical milestone counts below retain their dates.

Android has its own installed-app settings/launch route, described in the [Android status](android-emulators.md). Connected saves use one-time folder grants, journaled profile swaps and explicit save/close confirmation on return. Compiled host code and controlled workflow tests do not establish native acceptance or content/firmware parity. Android never imports desktop bundles or opens desktop pairing.


Current implementation details are in the [colored platform matrix](platform-support-matrix.md) and [RetroArch/Wii/Switch record](retroarch-wii-switch.md). The macOS pack now includes 18 additional RetroArch platform routes with 14 pinned cores, plus Wii WAD and Switch NSP packages and automatic missing Switch resources. The setup JSON's RetroArch `cores` object maps approved core IDs to explicit local binaries; core and frontend fingerprints remain separate. This remains a pinned-roster importer, not arbitrary emulator/plugin configuration. PS4 has no built-in recipe and no special download restriction.

The [live platform support matrix](platform-support-matrix.md) enumerates the 29 platforms returned by the owner's RomM account on 2026-10-23, proposes one or two emulator choices for each, and separates current launch/save/package coverage from remaining work. The roster below remains the original product baseline; a proposed matrix row is not a tested setup recipe.

Updated 2026-10-22. The owner selected the concrete emulator roster already represented in PGCS. Managed setup/Home launch now covers RetroArch/Snes9x, Dolphin/GameCube/Wii, RPCS3, Azahar, Ryubing and melonDS on Apple Silicon, plus a separate Intel RPCS3 option through Rosetta. Other native hosts and members of the roster remain pending. See [the initial slice](managed-emulators-and-play.md), [DS/progress additions](library-and-progress-followup.md) and [Intel RPCS3 evidence](rpcs3-intel.md).

The settings follow-up groups cards under all platforms from the selected RomM server, keeps an effective platform default for Home Play, expands setup review in the selected card and offers confirmed managed removal. Unsupported platforms remain visible. Shared emulator removal preserves profile settings/progress and ROMs; interrupted removal is retryable. PS3 has native ARM and Intel choices on Apple Silicon. PS2 now offers ARMSX2 and PCSX2 through existing Rosetta, with shared ordinary cards and separate settings/states; PS1 uses DuckStation. See the [PlayStation integration](playstation-support.md). The routing/persistence foundation is recorded in [the settings follow-up](remembered-signins-and-platform-settings.md).

## Roster and systems

| System / RomM slug | macOS target | Linux target |
| --- | --- | --- |
| SNES / `snes` | RetroArch / Snes9x | RetroArch / Snes9x |
| Game Boy Advance / `gba` | RetroArch / mGBA | RetroArch / mGBA |
| Genesis / `genesis` | RetroArch / Genesis Plus GX | RetroArch / Genesis Plus GX |
| Master System / `sms` | RetroArch / Genesis Plus GX | RetroArch / Genesis Plus GX |
| Dreamcast / `dc` | RetroArch / Flycast | RetroArch / Flycast |
| GameCube / `ngc` | Dolphin | Dolphin |
| Wii / `wii` | Dolphin | Dolphin |
| PlayStation / `psx` | DuckStation | DuckStation |
| PlayStation 2 / `ps2` | ARMSX2 on ARM64; PCSX2 as applicable to the selected host/build | PCSX2 |
| PlayStation 3 / `ps3` | RPCS3 ARM; separate Intel RPCS3 option through Rosetta on Apple Silicon | RPCS3 |
| PSP / `psp` | PPSSPP | PPSSPP |
| PlayStation Vita / `psvita` | Vita3K | Vita3K |
| Original Xbox / `xbox` | xemu | xemu |
| Nintendo DS / `nds` | melonDS | melonDS |
| Nintendo 3DS / `3ds` | Azahar | Azahar |
| Wii U / `wiiu` | Cemu | Cemu |
| Switch / `switch` | Ryubing; Eden (experimental macOS ARM64); Astris (macOS 15+ ARM64) | Ryubing; Eden (native delivery pending) |

The original thirteen executable adapters, counting PCSX2 and ARMSX2 separately, are extended by the owner's Eden choice. The current macOS pack also pins 14 additional RetroArch cores; the original setup examples used four. This is an adapter inventory, not a promise that every game, peripheral, state format or upstream architecture is supported. PSP now has native game-created save/state checks; Eden has native controller/update checks and a separate Switch directory-progress boundary. See [PPSSPP/Eden evidence](psp-and-eden-support.md).

Source references: PGCS's [concrete adapter selector](../../pgcs/internal/launcher/launcher.go), [macOS ARM64 setup example](../../pgcs/examples/setup-config-macos-arm64.json), [Linux AMD64 setup example](../../pgcs/examples/setup-config-linux-amd64.json), and [launcher inventory](../../pgcs/LAUNCHERS.md). The Linux example omits Dolphin although PGCS's adapter/inventory includes it; that omission does not remove Dolphin from Broomm's requested scope. PGCS's much broader future RetroArch/core catalogue is not automatically an additional initial platform commitment.

Windows remains a product target for applicable members of this roster, with native validation later. Android selects compatible installed emulator apps or installable packages per system; do not infer an Android package or supported launch/save contract from a desktop executable name. PCSX2/ARMSX2 desktop inclusion, for example, does not define an Android PS2 integration.

## Configuration ownership

On desktop, the executable can be Broomm-managed or explicitly selected from an existing installation, but configuration is always Broomm-local. Verify the actual effective data/profile path; a command-line option or environment variable appearing in a generated launch command is not sufficient proof.

Never reuse the system-wide/default-user configuration as the session's writable profile. Generate Broomm's settings from its own adapter defaults and saved preferences. Do not copy, patch, re-sign, update, or place proxy libraries into a user-selected installation. If a required integration cannot work without that mutation, use an explicitly prepared managed installation or report the capability unavailable.

Keep shared executables and ROMs separate from per-account saves/states and generated session configuration. Preserve those writable roots during installation, manual executable replacement, retry and manifest-driven update. Android intentionally uses ordinary external emulator apps and their supported save/state handoff instead of this desktop isolation contract.

## Setup JSON contract

The owner selected a PGCS-style setup manifest for provisioning, not PGCS's Go implementation. Implement manifest parsing, plan generation, downloads, extraction, validation, receipts and publication in Dart within Broomm.

The implemented version-1 [setup file](../assets/setup/setup.json) selects local extracted application/core/resource paths for the pinned macOS arm64 builds. `tested:` aliases refer to the existing test installations in this checkout. Trusted bundle inventories, binary/core hashes and bridge symbols are application assets; manifests cannot supply commands, executable arguments, environments or hook addresses. Reading a manifest performs no installation. Remote archives, arbitrary newer binaries, system-executable selection and Android package fields need separate validated recipes; the broader workflow below remains the target.

The app workflow is:

1. User chooses a setup JSON file, including a newer file explicitly obtained through Broomm.
2. Parse and validate the complete manifest, then compute the requested host-specific install/update plan and prerequisites. Reading the file alone performs no installation.
3. Present the concrete plan and allow the user to start it. No periodic polling or newer manifest silently starts an update.
4. Download/prepare in private staging with progress, cancellation, integrity/path checks and retryable receipts. Keep the previous verified installation and all settings/progress intact on failure.
5. With no active game using the installation, publish verified artifacts and update the selected executable/build record. Verify actual binary identity rather than trust a manifest version label alone.

No automatic emulator updates. A user may also update a managed emulator manually; detect its changed build at launch, revalidate capabilities and explain applicable state compatibility. Do not undo an explicit manual change merely because an older setup manifest is remembered. A system-selected executable stays outside Broomm's updater.

Native injection libraries are Broomm application assets compiled from reviewed C source, not arbitrary plugins loaded from setup JSON. An emulator artifact may change which bridge builds are compatible; validate that relationship and preserve the last working route. Android installation must use its ordinary package/user-consent flow and cannot inherit desktop executable extraction/spawn assumptions.

BIOS/firmware/key sourcing remains separate from executable/core updates. Keep the current user-supplied planning assumption visible until that policy is decided; an emulator manifest must not silently import unrelated private saves or system configuration.

## Per-adapter acceptance record

Track build/hash, host/architecture, supported platform/core, firmware requirements, verified Broomm-local config path, save/state units and formats, controller identity/ports, graphics backend, settings application/restart rules, and manual steps/results. Mark desktop injection/overlay support separately from ordinary launching. Android tracks package/version, ROM/save/state handoff and completion/access limits; controller injection and overlays are out of scope.
