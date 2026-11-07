# Remaining rooted Android RetroArch cores

The owner approved this milestone after two-account GBA/SNES acceptance and
PR #3's merge. The existing Dart supervisor, libsu connection, native ownership,
OS locks, recovery and RomM contracts remain. No new runtime library is added.

GBA/mGBA and SNES/Snes9x are merged and device-verified. Current source adds
Game Boy/Game Boy Color through Gambatte; packaged gameplay/RTC checks are
pending. The other twelve selected cores remain research, not implementation.

## Gambatte source and behavior

The [four retained official archives](../vendor/android/gambatte/0.5.0-netlink-77f2567/README.md)
identify source `77f2567d718b8973d02caa2daa8dce4953faf811`. Provenance includes
archive/library checksums, ELF ABIs, GPL-2.0 license and Android build recipe.
Downloads pin artifact commit `d58888fe71f5a1975e931522d91eb2a2f22fcac7`, retained
by `android-gambatte-0.5.0-netlink-77f2567`. All four libraries need only Android
libc, libm and libdl. The upstream NDK environment is not claimed reproduced.

GB and GBC setup remain independent even though they share one core. Version 6
settings retain versions 1–5 and existing GBA/SNES/shared-folder connections.
The desktop `libretro-gambatte-v1` contract carries SRAM and RTC together in a
native ZIP when both exist. States retain the APK/ABI/core group. Missing working
clock data preserves recovery instead of publishing deletion. Both session and
swap receipts retain the original platform if the general marker is missing.

Workflow checks cover migration, independent setup, SRAM/RTC cloud readback,
state companions, original native restoration and missing-clock recovery. Nine
production filesystem groups passed on Thor in disposable storage, including
bounded SRAM/RTC selection, exclusion of another title's clock and GBC ROM
staging. These file/workflow checks do not establish GB/GBC gameplay.

## Walkthrough and verification

Use a rooted Android user-0 device, the regular official RetroArch APK and a saved
RomM account. Complete RetroArch's first open if Setup requests it. Choose
**Emulator Settings → Game Boy or Game Boy Color → RetroArch → Set up**, then Play.
This increment accepts an uncompressed `.gb`, `.gbc` or `.dmg`; compressed GB
content has no new root acceptance. Save in-game or create a manual state, Quit
normally, and wait for Broomm's sync confirmation. Verify an RTC game separately.

Setup installs only Gambatte and keeps other cores. Native session files stay
inside RetroArch's Broomm-owned game boundary. Normal completion restores original
save bytes and removes recorded ROM/configuration files. Profile progress and
recovery stay in Broomm. Remove confirms external-app uninstall with Android,
then clears connections after verified absence while retaining Broomm progress.

```sh
devbox run -- flutter --suppress-analytics test --no-pub test/android_root_saves_test.dart test/android_core_download_test.dart test/android_setup_test.dart
devbox run --config tool/android -- bash check_bridge.sh
devbox run --config tool/android -- bash build_root_save_test.sh
```

Run the compiled fixture through `app_process` with a fresh
`/data/local/tmp/broomm-root-test-<32 hexadecimal digits>` directory. It removes
only that disposable root; remove its pushed DEX afterward. Keep real saves,
snapshots, journals and stable lock files. Local evidence is under
`.tool-cache/android-retroarch-cores/2026-11-07`.

## Remaining boundaries

Artifacts for all four ABIs have source/architecture/dependency research. FBNeo's
arm64 library is about 73 MiB, exceeding current core limits. Larger files need
bounded streaming with identity/readback and interruption checks. N64 save RAM
and Saturn backup cartridges also exceed the existing small-save boundary.

Disc content needs safe file-set staging and firmware from RomM. Opera and FBNeo
have nested native saves. Flycast requires private VMUs on every port and its
option prefix differs between builds. New Beetle Saturn builds default to a new
frontend SRAM mode; preserve the existing Mednafen save contract explicitly.
Stella and the inspected Beetle Lynx expose no ordinary Libretro save RAM.

Virtual Jaguar has a permanent [3.11.0 Android release](https://github.com/libretro/virtualjaguar-libretro/releases/tag/v3.11.0)
with a clean source identifier. Current source/metadata advertises Jaguar CD
and Memory Track; media/device acceptance remains pending. Mesen omits a Git
revision in its binary, so exact build-source provenance still needs resolution.
