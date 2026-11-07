# Remaining rooted Android RetroArch cores

The owner approved this milestone after two-account GBA/SNES acceptance and
PR #3's merge. The existing Dart supervisor, libsu connection, native ownership,
OS locks, recovery and RomM contracts remain. No new runtime library is added.

GBA/mGBA and SNES/Snes9x are merged and device-verified. Current source adds
Game Boy/Game Boy Color through Gambatte. Build 1061 passed the packaged Thor
checks below. Current source also adds Stella and Beetle PCE Fast for uncompressed
cartridges; build 1062 passed their packaged Thor checks below. The next source
increment adds Genesis Plus GX and PicoDrive for four Sega platforms; builds
1066/1069 passed the scoped device checks below. N64 build 1073 passed the scoped
cartridge/save/state checks below. Seven other selected cores remain research.

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
records exact revisions, files and checks. That increment's macOS archive was rebuilt
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
restoration workflow described above. The ZIP checks below add compressed
cartridge acceptance. Firmware/discs have no new acceptance. Existing standalone
settings and other cores are preserved.

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

Build **1069**, runtime `f00df30`, passed three real ZIP launches. Sonic 3 rendered
Angel Island, responded to movement/jump, and uploaded/read back SRAM and a
manual gameplay state as primary 230. Relaunch restored every byte of its
604-byte SRAM; the core subsequently expanded it to 65,536 bytes with only
`0xff` padding. RetroArch loaded the gameplay state. The in-game File List
reload was not captured, so ordinary save acceptance is limited to file restore.

Phantasy Star created slot 1 named A in-game, published SRAM/state as primary
231, and loaded it through Continue after relaunch. The manual state loaded
independently; final hashes were unchanged. Defenders of Oasis published SRAM
and a manual state, then loaded the state. After a navigation mistake restarted
only the new disposable game, a further synchronized relaunch explicitly used
Continue → Game 1 / Level 1 / Chapter 1 and resumed the throne-room scene.
Its final autosave is primary 234; the manual-state hash stayed unchanged.

Earlier build **1066**, runtime `dd7f36d`, rendered Chaotix with PicoDrive and
opened Scenario Quest. Its manual title state published as primary 228 and
loaded on relaunch. No ordinary SRAM was created; completed 32X gameplay is
not claimed.

Normal final exit removed all new native session files and journals. All 19
existing managed native files, 13 pre-existing standalone/managed files, eight
prior GBA/SNES progress files and eleven earlier GB/GBC/Atari/TG16 progress
files remained unchanged. Seven core hashes and ten independent bindings
matched; both accounts' prior histories stayed synchronized and distinct.
The original account remains selected. The reviewed 158 build-1069 operational
lines had no warnings/errors. Exact receipts are in the [Sega evidence](android-retroarch-sega.json).

This is one arm64 device/account for Sega; earlier GB/GBC acceptance separately
used both accounts. All five packages and macOS/Linux/native Android checks
passed for `f00df30`, but the independent Windows updater fixture missed its
existing eight-second readiness deadline. Its helper remained alive without
output or an installer log before cleanup. The failure is retained, unmasked
and unresolved; PR #4 remains draft. The macOS archive for this runtime passed
ZIP integrity and source/extracted deep strict signatures: 24,348,825 bytes,
SHA-256 `ef2d4dbae46ae2516612c809fae8321867dd84bd9bc586d6fe63b69424ad21e4`.
It is ad-hoc signed, not notarized.

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

Build 1068 then passed private staging but refused Android launch because that
adapter still compared the complete `.zip` filename with the extracted cartridge
name. The next correction accepts the original archive stem plus a core-accepted
extension, preserving raw filename matching and the selected game/profile/config
correspondence. The complete production launch validator is now exercised by
the native fixture for raw and ZIP cases across the implemented cores, including
wrong stems, raw-extension changes, different games/profiles and core mismatch.
Build 1069 subsequently passed ZIP launch and the scoped save/state checks
above for all three downloaded Sega ZIPs.

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
Packaged ZIP acceptance is scoped to the three Sega games above; this does not add disc sets, firmware or
arcade archive support.

## Nintendo 64 source increment

Current source adds **Nintendo 64 → RetroArch → Set up** using the retained
[Mupen64Plus-Next archives](../vendor/android/mupen64plus_next/3.0-15bada8/README.md).
The four archives pin artifact `bb01c67`, retained by
`android-mupen64plus-next-20261107`, and embed source `15bada8`.
Android uses `mupen64plus_next_gles3_libretro_android.so`; the logical core and
desktop-compatible `libretro-mupen64plus_next-v1` save identity stay unchanged.
ARM versions identify Vulkan and x86 versions GLES3. Exact upstream build
reproduction is not claimed; recipe, dependencies and notices are recorded.

Raw `.z64/.v64/.n64` cartridges up to 64 MiB, or exactly one such cartridge in
a validated ZIP, use the journaled private staging workflow. N64 ZIP input and
aggregate expanded content are bounded to 128 MiB. Ordinary save files retain
all 296,960 bytes of EEPROM, four controller paks, SRAM and Flash RAM. N64 states
have a 32 MiB per-file boundary because this source's uncompressed serialized
state is 16,793,412 bytes. Other cores retain their earlier limits; configuration
remains 256 KiB and aggregate native progress remains 64 MiB/128 files.
Version 9 settings read versions 1–8 without losing earlier bindings. Recovery
retains the selected core and original platform, including the N64 limits.

Clean analysis, all 642 Flutter tests (one existing native-host skip) and 51
focused setup/root/download tests pass. The final 42-test root suite also
passes after the limit helper cleanup. Thirteen real
Thor filesystem groups pass in disposable storage, including full SRAM,
interrupted large-state publication/retry, exact 64 MiB cartridge staging and
oversized refusal without widening earlier limits.

Build **1073**, runtime `d30e81f`, passed normal N64 Setup with all earlier cores
and bindings retained. Super Mario 64 (8 MiB `.z64`, RomM 937) rendered, accepted
analog movement and jump, and saved a manual gameplay state outside the castle.
Changing its in-game STEREO preference to MONO exercised EEPROM-backed ordinary
saving. Normal Quit uploaded/read back primary 235 with all 296,960 native save
bytes and a 1,358,566-byte compressed state. A fresh Play restored both files
byte-for-byte, File Select showed MONO and Load State returned to the gameplay
scene. No completed star or in-game slot progression is claimed.

The final session returned audio to STEREO and synchronized primary 236, keeping
the gameplay state unchanged. All 19 earlier managed native files, 13 original
standalone/managed files, eight earlier GBA/SNES progress files and 18 earlier
GB/GBC/Atari/TG16/Sega progress files stayed unchanged. Both accounts' earlier
histories remain distinct. Eight core hashes, eleven platform bindings and
native cleanup passed; 81 reviewed operational lines had no warning/error.
All CI checks and five packages passed. This is one arm64 device/account for
N64; other byte orders, ZIP, controller-pak/Flash behavior and 64 MiB titles do
not gain gameplay acceptance from these checks. The [exact evidence](android-retroarch-n64.json)
retains files, checkpoints, package identities and observation hashes.

This does not add 64DD/Transfer Pak media or texture-pack installation. The [upstream core guide](https://docs.libretro.com/library/mupen64plus/)
describes broader core capabilities separately from Broomm's accepted scope.

The Windows diagnostic follow-up `cf75b58` passed all CI jobs in
[run 42412917045](https://github.com/Broomm/broomm/actions/runs/42412917045).
Its native updater became ready after 1,770 ms (`Process.start`: 7 ms). This
successful execution does not identify the earlier timeout's cause; the
failure-only observation remains enabled without altering the pass deadline.

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
larger download recipes and actual core integrations remain pending. Saturn
backup cartridges still exceed the existing small-save boundary; N64's concrete
limits are implemented in the source increment above.

Disc content needs safe file-set staging and firmware from RomM. Opera and FBNeo
have nested native saves. Flycast requires private VMUs on every port and its
option prefix differs between builds. New Beetle Saturn builds default to a new
frontend SRAM mode; preserve the existing Mednafen save contract explicitly.
Stella and the inspected Beetle Lynx expose no ordinary Libretro save RAM.

Virtual Jaguar has a permanent [3.11.0 Android release](https://github.com/libretro/virtualjaguar-libretro/releases/tag/v3.11.0)
with a clean source identifier. Current source/metadata advertises Jaguar CD
and Memory Track; media/device acceptance remains pending. Mesen omits a Git
revision in its binary, so exact build-source provenance still needs resolution.
