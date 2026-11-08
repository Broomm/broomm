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
cartridge/save/state checks below. NES build 1077 and Jaguar builds 1079/1080
passed the scoped checks below. Lynx build 1083 passed BIOS delivery, gameplay
input and state restoration below. Opera, FBNeo, Flycast and Beetle Saturn still need their
concrete firmware/media/save integration.

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

## NES/Mesen source increment

**Nintendo Entertainment System → RetroArch → Set up** now installs Mesen 0.9.9
from the [retained four-ABI build](../vendor/android/mesen/0.9.9-0102910/README.md),
artifact `7a0fb0a`, tag `android-mesen-0.9.9-0102910`. Unlike the nightly library,
this build has exact corresponding source, compiler inputs/logs and ELF/output
hashes from Broomm CI. Source `0102910` is unchanged. Native dependencies are
Android libc/libm/libdl; C++ is linked statically. The ZIP-method metadata
erratum and original build records remain explicit in provenance.

Raw `.nes/.unf/.unif` cartridges and validated single-cartridge ZIPs use the
existing journaled profile/game staging. The earlier 32 MiB raw / 64 MiB archive
limits, 256 KiB ordinary-save limit and 16 MiB state limit remain. SRAM retains
the desktop `libretro-mesen-v1` raw contract. Version 10 settings read versions
1–9 without losing earlier bindings; older records cannot assert NES Setup.
FDS disks/BIOS, HD packs and special peripherals have no new acceptance.

Clean analysis, all 649 Flutter tests (one existing native-host skip) and 58
focused setup/download/root/build checks pass. The Kotlin bridge and native
fixture compile; all thirteen disposable Thor filesystem/launch groups pass,
including Mesen installation, raw/ZIP launch validation and unsupported FDS
refusal. All application CI jobs and five packages passed. Build 1077
(`1ecf544`) passed normal NES Setup and the downloaded Zelda cartridge on Thor:
new slot **A** persisted through normal Quit/sync and fresh Play, movement worked,
and **Load State** resumed the cave-entrance position before entering the cave.
The installed-file journal matches both published hashes; the running core
changed SRAM before live readback, while the native state remained byte-identical.
Final Quit published primary 238 and retained the gameplay state. Sword/dungeon
progression is not claimed.

All 20 earlier GB/GBC/Atari/TG16/Sega/N64 progress files, eight GBA/SNES progress
files, 19 original managed native files and 13 earlier standalone/managed files
remain unchanged. Nine core hashes, twelve independent platform bindings, both
accounts' distinct earlier histories and journal cleanup pass. All 51 reviewed
log lines are free of warnings/errors. An apparent rendering issue was traced
to inconsistent previews of repeated images: purportedly different frames were
byte-identical, with intact interface pixels. Disposable owned/upstream/driver
comparisons left installed cores, original ROMs and global settings unchanged;
their 15 temporary files were removed after normal exit. See the
[exact scoped device evidence](android-retroarch-nes.json).

## Jaguar cartridge source increment

**Atari Jaguar → RetroArch → Set up** now downloads Virtual Jaguar 3.11.0 from
its official versioned release. The [source/recipe/notice record](../vendor/android/virtualjaguar/3.11.0/README.md)
retains all four payload hashes, ELF identities and Android-only dependencies.
The library downloads directly; Broomm does not mirror the binary or embedded
boot-ROM arrays, whose independent firmware licensing is not inferred from the
main source license. No new runtime dependency is added to Broomm itself.

Raw `.j64/.jag/.rom/.abs/.cof/.bin/.prg` cartridges and validated single-cartridge
ZIPs use the existing private profile/game workflow. Cartridge EEPROM is native
128-byte big-endian data, consistent with the selected desktop core's source;
actual cross-device gameplay remains separate. Memory Track has a distinct
128 KiB native case. The 32 MiB cartridge / 64 MiB archive, 256 KiB ordinary and
16 MiB state limits remain. States require the same APK, ABI and core. Version 11
retains earlier settings; versions 1–10 cannot claim a Jaguar connection.

Clean analysis, 655 full Flutter tests (one existing native-host skip), 61
focused checks and thirteen disposable Thor filesystem/launch groups pass.
The native bridge and fixture compile. Checks cover migration, 128-byte EEPROM
cloud restore, raw cartridge formats, unsupported disc recovery, changed/large
downloads and cancellation/retry. The explicit
`devbox run -- dart tool/check_android_jaguar_download.dart` network integration
check verified all four real release assets and ELF identities, then removed
private staging. It writes a receipt under `build/test-results/` and installs
nothing. The subsequent packaged acceptance is recorded below. Jaguar CD is still deferred.

The first packaged check (`675ab8b`, build 1079) passed Setup, native rendering,
controller input and a 128-byte EEPROM publication. It exposed stale frontend
metadata: RetroArch 1.22.2's bundled `.info` describes Virtual Jaguar 2.1 and hides
states. The reviewed 3.11 release declares deterministic states and implements
serialization. Its exact four ABI/payload hashes now enable
`core_info_savestate_bypass` in Broomm's disposable session configuration.
Unreviewed cores retain their metadata policy; no installed `.info`, global
preferences or optional rewind/run-ahead preferences are rewritten.

Build **1080** (`855e6a6`) then passed the corrected Save States menu and manual
state reload. Tempest's FAT/SKINNY VECTORS preference proved the ordinary EEPROM
round trip: fresh Play restored all 128 bytes and showed the changed preference.
The 80,783-byte manual state also restored byte-for-byte; Load State left the
attract screen and resumed the saved level-start scene at score 0 with three
lives. Movement/fire inputs were exercised; no completed-level/high-score
progression is claimed. The original display preference was restored before
final Quit published primary 241, retaining the same state.

All 22 earlier additional-core progress files, eight GBA/SNES progress files,
19 managed native files and 13 original standalone/managed files stayed unchanged.
Ten core hashes, thirteen independent bindings, both accounts' distinct earlier
histories and absence of active recovery journals pass. All 86 scoped operational
log lines are free of warnings/errors. These are one arm64 Thor/account for Jaguar;
cross-device gameplay and Memory Track remain separate. The [portable evidence](android-retroarch-jaguar.json)
records exact builds, hashes, checkpoints and limits.

Analysis and all 657 Flutter tests pass (one existing native-host skip), including
50 rooted-session cases. All application CI checks and five packages passed run
`42424365012`. A separate Mesen source job had built/uploaded all four libraries
but failed in Nix installer post-job diagnostics after a network timeout; the
original failure/log remains retained. The same pinned installer now uses its
documented diagnostics opt-out. Corrected run `42424364865` passed all four native
jobs and every post-job step, with unchanged build/test deadlines and failure
handling. The current macOS archive passes source-input, ZIP and source/extracted
deep strict all-architecture signature checks; it is ad-hoc signed, not notarized.

## Lynx firmware/state source increment

The [retained four-ABI Beetle Lynx artifacts](../vendor/android/mednafen_lynx/1.24.0-fcdefcf/README.md)
identify source `fcdefcfb3c11d6d2e71be076a5d3df2e88ab73ed`. Original archives,
ELF identities, source/library hashes, Android recipes and component notices
are recorded. The exact upstream NDK environment is not claimed reproduced.
Runtime downloads pin artifact commit `a62e24ffdc352399a47516dc43cbd4f985f9c027`,
retained by `android-lynx-1.24.0-fcdefcf`; Setup installs this platform's core only.

The concrete increment uses raw/safe-ZIP `.lnx/.lyx/.bll/.o` cartridges and matched
states. The core exposes no ordinary Libretro save RAM, so Broomm must not
synthesize an empty `.srm`. Its required 512-byte `lynxboot.img` must come from
the active platform's RomM firmware catalogue, with the canonical MD5
`fcd403db69f54290b51035d82f835e7b` as well as transfer/catalogue verification.
Missing, ambiguous, corrupt and offline observations remain distinct. The
[upstream core documentation](https://docs.libretro.com/library/beetle_lynx/)
confirms the BIOS identity and state-only save capability.

Firmware lookup/download/cache decisions stay in Dart inside the existing locked
Play preparation. A verified profile-owned cache supports offline reuse;
background save inspection stays read-only. Missing/ambiguous/wrong BIOS metadata
and corrupt transfers remain visible. A damaged object is retained during repair;
unreadable/conflicting index data is an error. Preparation offers Cancel and
retains the production session lease until its writer acknowledges closure.
An uncertain download writer keeps its private stage and lease until restart.

A concrete journaled native resource under the session's private system
directory supplies the BIOS. The descriptor operation requires Lynx, exactly
512 bytes, the paired configuration nonce, SHA-256, UID/security label and
verified emulator closure. It cannot write a different firmware or save path.
Version-2 Lynx receipts precede native effects; existing version-1 transactions
remain readable. Recovery works without cache/network or the private staged
BIOS, including lost publication/cleanup replies and loss of the general session
marker. Edited resources retain captured states. Cleanup checks hashes after
verified closure; firmware never enters progress inventories/cloud bundles.
Settings version 12 preserves earlier connections. The earlier save/config
allowlists and resource bounds remain; private recovery copies now stop as soon
as their source exceeds its recorded size. No public BIOS download, shared
mutable firmware tree or new runtime dependency is added.

Use **Atari Lynx → RetroArch → Set up**, then Play a downloaded cartridge.
If the required BIOS is missing, add one `lynxboot.img` with the canonical size
and MD5 to that platform in RomM and retry Play. The BIOS stays in Broomm's
profile cache and the temporary native session system directory; it is not
included in the app or a save upload. Create a manual state, Quit RetroArch
normally and wait for sync, then launch again and Load State. Do not expect an
ordinary battery-save upload from this core. Keep private progress/recovery
directories; normal completion removes only recorded native session resources.

Clean analysis, all 670 Flutter tests (one existing native-host skip), 75 focused
checks and fourteen real Thor filesystem/launch fault groups pass. The bridge
and fixture compile. Build **1083** (`03dec28`) subsequently passed normal Setup
and Crystal Mines II Play. RomM's canonical 512-byte BIOS matched both native
copies; the second launch reused the verified cache object. Level-one movement/
action and manual Save/Load State passed. The 34,966-byte state restored
byte-for-byte and resumed the recorded scene. Both normal Quits synchronized
primary 242, with no synthetic SRAM. Temporary BIOS/session files were removed.
All 32 earlier progress files across both accounts and every previously checked
native/settings file remained unchanged, with eleven core hashes and fourteen
bindings. All 36 scoped log lines have no warnings/errors; all application CI
checks and five packages passed. This does not establish disconnected-network
Lynx play, a completed level, other ABI or cross-device gameplay. See the
[exact device evidence](android-retroarch-lynx.json).

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

Virtual Jaguar now uses the permanent source-identified release above; cartridge
device acceptance is recorded above and Memory Track gameplay remains separate. Jaguar CD remains
owner-deferred. Mesen's nightly provenance gap is resolved by its retained owned
source build. Four selected cores still need their concrete integration;
Lynx's scoped packaged acceptance is recorded above.
