# Remaining rooted Android RetroArch cores

The owner approved this milestone after two-account GBA/SNES acceptance and
PR #3's merge. The existing Dart supervisor, libsu connection, native ownership,
OS locks, recovery and RomM contracts remain. No new runtime library is added.

GBA/mGBA and SNES/Snes9x are merged and device-verified. Current source adds
Game Boy/Game Boy Color through Gambatte. Build 1061 passed the packaged Thor
checks below. Current source also adds Stella and Beetle PCE Fast for uncompressed
cartridges; their packaged device checks remain pending. The other ten selected
cores remain research, not implementation.

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

Build **1061**, runtime `4037c0b`, subsequently passed real Thor checks through
normal Setup/Play/Quit. Pokémon Crystal's new character A, 32,768-byte SRAM,
8-byte RTC and manual state uploaded/read back as account 2's primary 222.
The next launch restored both native save files byte-for-byte, showed Continue
with the character and clock, and loaded the manual state. Account 3 instead
showed New Game without Continue and published separate primary 224.

GB Tetris published account 2's level-selection state as primary 223 and account
3's distinct level-0 gameplay state as primary 225. After switching back,
account 2 loaded its own earlier state and resumed level-5 play. This Tetris
release has no SRAM/RTC; the physical ordinary-save check used Crystal.
Both saved sign-ins opened without credential re-entry after the data-preserving
upgrade. All eight prior GBA/SNES progress files and all 19 existing managed
native files stayed unchanged, alongside the original standalone configuration.
New session ROM/config/save/state files were cleaned up, every tested checkpoint
was synchronized, and the original account was left selected. This is one
arm64 device, not cross-device or four-ABI gameplay acceptance. Exact hashes,
builds and scoped results are in the [evidence record](android-retroarch-cores.json).

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

## Atari 2600 and TG16 cartridge increment

Explicit Setup now provisions Stella for Atari 2600 and Beetle PCE Fast for
TG16 HuCards. Use uncompressed `.a26`/`.bin` and `.pce` respectively. Disc images,
firmware and compressed cartridges have no new acceptance. Version 7 settings
retain versions 1–6, including independent GB/GBC bindings. PCE SRAM retains the
desktop raw `.srm` contract; states accompany ordinary saves separately. Stella
exposes no ordinary Libretro save RAM and uses the existing state-only bundle
contract. No placeholder SRAM is created.

The retained four-ABI archives live under `vendor/android/stella/8.0-pre-20261107`
and `vendor/android/mednafen_pce_fast/1.31.0.0-2de1ce1`, pinned to artifact commit
`48b34a0671b41d9b20853cc823805af1d49f0b75`. Source notices, original URLs, ELF
identities, hashes and Android recipes are retained. Stella identifies 8.0_pre;
x86 embeds `ba51417`, while the other three embed `5d206d7`. Per-ABI corresponding
sources are recorded rather than attributing one source revision to all four.
PCE Fast embeds `2de1ce1` on every ABI. Neither upstream build is claimed reproduced.

Clean analysis and all 628 Flutter tests pass, with one existing native-host
skip. The updated Kotlin bridge compiles and ten native Thor filesystem fault
groups pass. Tests exercise version-6 migration, independent setup/removal,
state-only and raw-SRAM cloud readback/restoration into fresh profile storage,
cartridge staging and unsupported-disc refusal. Real Stella/PCE gameplay remains
pending the new APK.

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
