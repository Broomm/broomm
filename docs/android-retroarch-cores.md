# Remaining rooted Android RetroArch cores

The owner approved this milestone after two-account GBA/SNES acceptance and
PR #3's merge. The existing Dart supervisor, libsu connection, native ownership,
OS locks, recovery and RomM contracts remain. No new runtime library is added.

GBA/mGBA and SNES/Snes9x are merged and device-verified. Current source adds
Game Boy/Game Boy Color through Gambatte. Build 1061 passed the packaged Thor
checks below. Current source also adds Stella and Beetle PCE Fast for uncompressed
cartridges; build 1062 passed their packaged Thor checks below. The next source
increment adds Genesis Plus GX and PicoDrive for four Sega platforms; packaged
gameplay remains pending. The other eight selected cores remain research.

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
cartridge staging and unsupported-disc refusal. All PR jobs passed for runtime
`32b3ec0`. Build **1062** then passed real account-2 Setup/Play/Quit on Thor:
Adventure rendered, published its manual state as primary 226 and loaded that
state on relaunch. Neutopia's Book of Revival and new File Cabinet slot 1 were
created in-game. Its 2,048-byte SRAM and manual state published as primary 227
with a state companion. Relaunch restored SRAM byte-for-byte, Continue → File
Cabinet listed the saved slot and loaded it, and the manual state loaded too.

Normal final exit left no session/swap journal or new managed native files. All
19 existing managed files, original standalone settings and eight prior GBA/SNES
progress files stayed unchanged. Five core hashes and six independent bindings
matched expectations. The reviewed 85 operational log lines had no warning or
error. This is one arm64 device/account for the two new cores; earlier GB/GBC
acceptance separately exercised both accounts. The [cartridge evidence](android-retroarch-cartridges.json)
records exact revisions, files and checks. The current macOS archive was rebuilt
from runtime `32b3ec0` and passed ZIP and source/extracted deep strict signatures:
24,348,825 bytes, SHA-256
`800aa2a46b156f5f0453538bcd3daa856487c3aa60830895b90301321a1effdf`.
It is ad-hoc signed, not notarized. The earlier GB/GBC evidence retains its own
historical runtime/build fingerprints.

## Sega cartridge increment

Current source adds **Genesis / Master System / Game Gear → RetroArch → Set up**
through Genesis Plus GX, and **32X → RetroArch → Set up** through PicoDrive.
Platform choices remain independent even when sharing a core. Version 8 reads
versions 1–7 without losing their connections and removes only the selected
binding on disconnect. Raw `.srm` remains compatible with the existing desktop
`libretro-genesis_plus_gx-v1` / `libretro-picodrive-v1` contracts. State identity
still includes the actual APK, ABI and core hash. No placeholder SRAM is created
for games that do not expose it.

Accepted uncompressed cartridges are Genesis `.md/.gen/.smd/.bin`, SMS `.sms/.sg`,
Game Gear `.gg`, and 32X `.32x/.bin/.gen/.smd/.md`. Normal Play, in-game Save or
manual state, and RetroArch Quit use the same capture/upload/readback and native
restoration workflow described above. Firmware/discs and compressed content have
no new acceptance. Existing standalone settings and other cores are preserved.

The four-ABI archives pin artifact commit
`db5b758bdb057bd52c7c93b07bf4dc10a046fc16`, retained by
`android-sega-cartridge-cores-20261107`. Every Genesis Plus GX ABI embeds
`f27655b` (1.7.4); every PicoDrive ABI embeds `1890c29` (2.05). The vendor records
retain original/archive/library/source hashes, build recipes, dependency and
license notices. PicoDrive's five submodule revisions are recorded; its nested
dr_libs miniaudio test checkout is outside these Android core inputs. The
non-commercial upstream terms and component notices remain applicable. Exact
upstream NDK build environments are not claimed reproduced.

Clean analysis and 635 Flutter tests pass with one existing native-host skip.
All seven cores' reviewed ABI archives pass verification. The production bridge
compiles and eleven real Thor filesystem groups pass, including all new cartridge
extensions, original source preservation and unsupported disc refusal. Genesis
Plus GX alone receives a 16 MiB Dart extraction bound and 2 MiB archive bound;
previous core bounds are retained. Native core streaming is verified below.
Packaged Sega gameplay remains pending.

## Cartridge ZIP preparation

Build 1067 exposed a source-boundary mismatch before launching the ZIP: native
staging still required the installed library path. The follow-up preserves that
ordinary resolver and adds a separate, transaction-bound prepared-cartridge
handoff, revalidated in the app and root-service mount namespaces. It normalizes
the private source filename to the native cartridge name. JVM checks reject
foreign transactions/names, traversal, nested and linked sources; the bridge
compiles and eleven real Thor filesystem groups pass with prepared-source
staging and wrong-transaction refusal. The failed game session retains recovery;
this is not packaged ZIP acceptance.

The Sega catalogue supplied ZIPs for Genesis, Master System and Game Gear.
Current source therefore prepares single-cartridge ZIPs for the implemented
rooted cartridge routes in Dart. The existing ZIP validator checks every entry's
path, headers, type, collision and resource bounds before extraction into a
private transaction directory. Exactly one file must have this platform's
supported cartridge extension. Archives and aggregate expanded content are
limited to 64 MiB; each entry and the native cartridge retain the 32 MiB limit.
Split/ZIP64, linked, unsafe, ambiguous and damaged archives are refused.

The native cartridge uses the archive's original save/state stem even when its
internal filename differs or is nested. Original downloads are unchanged.
Extraction is removed after native staging or failure; the journal records the
native path, extension and hash before publication, allowing normal cleanup to
retry after a lost reply. Existing uncompressed journals remain readable.
Regression checks cover nested names and progress capture/cleanup retry,
multiple cartridges, traversal, oversized entries and corrupt payload cleanup.
Analysis and all 638 Flutter tests pass with one existing native-host skip;
39 focused root tests also pass with a lost native staging reply.
Packaged ZIP gameplay remains pending; this does not add disc sets, firmware or
arcade archive support.

## Remaining boundaries

Artifacts for all four ABIs have source/architecture/dependency research. FBNeo's
arm64 library is about 73 MiB. Native core transport now streams up to 96 MiB
through a 64 KiB buffer and small ELF header, preserving descriptor/path identity,
expected hashes, cancellation and exclusive publication. The updated bridge and
all eleven filesystem groups pass. A separate 80 MiB fixture passes with an
asserted exact 32 MiB ART heap; it exercises cancelled-copy retry, writer arrival,
source replacement with a forced mtime tie and an independent public destination
appearing before publication. `app_process` overrides the requested heap with
device properties, so the low-memory check uses the existing `dalvikvm` directly,
without changing any property:

```sh
/apex/com.android.art/bin/dalvikvm -Xmx32m -Xms8m -cp /data/local/tmp/root-save-test-dex.zip app.broomm.broomm.Check_root_save_filesKt core-memory /data/local/tmp/broomm-root-test-<32 hexadecimal digits>
```

Use a fresh disposable directory and remove the pushed DEX afterward. This is
native file-mechanism acceptance; Genesis Plus GX now uses it, while the other
larger download recipes and actual core integrations remain pending. N64 save RAM
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
