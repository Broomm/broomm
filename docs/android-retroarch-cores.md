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
input and state restoration below. FBNeo build 1087 passed complete-ROMset
gameplay, NVRAM/state restoration and two-account separation below. The Opera
increment covers self-contained disc images and native NVRAM; build 1090 passed
the packaged checks below. Saturn now has concrete source and packaged device
acceptance below. Multi-file media remains unfinished. Flycast now has the
concrete source increment below; packaged acceptance remains pending.

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

## FinalBurn Neo ZIP/save source increment

The [four retained archives](../vendor/android/fbneo/1.0.0.03-20261107/README.md)
pin each ABI's actual embedded source: ARM64/x86 use `d15071a`, ARMv7/x64 use
`4cdb31f`. Corresponding source/archive/library hashes, ELF identities, original
Android recipes, complete non-commercial FBNeo/MAME terms and component notices
are retained. The inspected Libretro wrappers are identical; driver/build
differences remain explicit. Runtime downloads pin `299e4ce74bebac3fb7d84a49c8f065e2b3f17c49`,
also retained by `android-fbneo-1.0.0.03-20261107`. Exact upstream NDK reproduction
is not claimed. No ROM or BIOS is bundled.

Use **Arcade → RetroArch → Set up**, then Play a complete matching ZIP ROMset
from RomM. Keep its original driver filename, such as `simpsons2p.zip`, and all
required chips together. Broomm validates archive paths/links/collisions and size
bounds, then stages the intact ZIP; it never chooses one chip or extracts the
set as a cartridge. The concrete bounds are 128 MiB compressed, 512 MiB total
expanded and 128 MiB per entry. Rooted 7z needs conversion to ZIP with names
preserved. Parent/BIOS/CHD acquisition and special arcade peripherals have no new
implementation; incomplete/incompatible ROMsets remain visible native errors.
The [upstream ROMset guidance](https://docs.libretro.com/library/fbneo/) explains
the need for matching sets and required BIOS dependencies.

The ordinary cloud ZIP retains `save/fbneo/<driver>.fs/.nv/.hi/.memcard` and the
game-private `save/fbneo/shared.memcard`. It synthesizes no cartridge `.srm`.
Native selectors select these names for the requested driver inside the resolved
profile/game, preserving other drivers and excluding temporary/error files.
States keep the existing APK/ABI/core compatibility group. Save and Quit
normally, wait for Broomm's sync, then Play again and verify native NVRAM and a
manual Load State. Keep the private progress/recovery directories. Normal
completion restores recorded native originals and removes session ROM/config
files; other installed cores and standalone settings are retained.

Version 13 reads earlier settings without claiming an old Arcade connection.
State recovery uses its original recorded group independently of ordinary-save
filename rules, including a lost general marker. Missing NVRAM cannot publish
deletion. All 676 Flutter tests (one existing native-host skip), 81 focused
checks and fifteen disposable Thor filesystem/launch groups pass, with clean
analysis and compiled bridge/fixture. Native cases include nested files,
wrong-core/foreign-path refusal, interrupted publication and exact 128 MiB
streamed ROMset staging. All four permanent URLs also pass a real production download, checksum and ELF
check. Inspection retains its exact hash through native handoff; a deterministic
source-replacement regression preserves recovery. The initial migration and fault-fixture failures and
their diagnostics are retained; no assertion or deadline was relaxed. These
checks alone do not establish packaged FBNeo gameplay, other ABI or cross-device play.

Build **1087**, runtime `36c9e8d`, subsequently passed normal Arcade Setup and
The Simpsons (`simpsons2p.zip`, RomM 718) Play on the Thor. The intact ROMset
passed the native chip check and reached stage-one Marge gameplay with movement
and action input. Normal Quit published the nested 128-byte NVRAM and a
5,654-byte manual state as primary 243. Fresh Play restored both byte-for-byte;
Load State resumed the recorded gameplay scene.

Account 3 began with an empty working inventory and published a distinct
3,745-byte character-selection state as primary 244. Returning to account 2
restored its original NVRAM/state hashes and gameplay scene. Final normal Quit
retained primary 243 without duplicate publication. The default NVRAM contents
match between accounts; this test establishes separation with distinct states.
Both saved sign-ins opened without password re-entry. All 33 earlier progress
files, 19 managed native files, 13 original standalone/managed files, twelve
cores and fifteen platform bindings remained intact. Journals and owned native
session files were removed; all 85 scoped log lines have no warnings/errors.
Application CI `42430012291` passed all checks and five packages; independent
Mesen run `42430012217` passed all four jobs. See the
[builds, hashes and scoped evidence](android-retroarch-fbneo.json). This one
self-contained ROMset does not establish the full driver catalogue, completed
stages, special peripherals, other ABI gameplay or cross-device play.

## Opera self-contained disc source increment

Use **3DO → RetroArch → Set up**, then Play one self-contained CHD v5, ISO or
BIN image from RomM. Runtime downloads pin `7d8f0c9accdf3fb80985000276e3a7767756fe17`
and `android-opera-1.0.0-370d9a2`. Settings version 14 reads versions 1–13 and
preserves earlier independent connections. The concrete disc boundary is 1 GiB
for both file and CHD logical size. Parent CHDs, incomplete headers and CUE sets
are refused; multi-file transport remains unfinished. Inspection is cancellable,
and its exact header/hash identity remains bound through streamed native staging.
Earlier cartridge/archive/state limits and disc-path refusals stay unchanged.
Core/configuration/options are rechecked after lengthy preparation; external
edits stop Play before cloud inspection or native save effects.

The retained core defaults to its embedded open-source Opera Boot. A selected
external BIOS or Japanese font is obtained from the active 3DO platform in RomM,
verified against canonical size/MD5 and transfer/hash checks, and retained in an
immutable profile cache. Existing cache objects survive failed repair. Native
copies live only in the configuration's private system directory; firmware never
enters cloud progress. Add exactly one matching selected resource to RomM if
requested, or choose the built-in boot ROM in RetroArch. No retail BIOS download
from a public service is added.

Game/folder/core/global option precedence selects the raw NVRAM key. Conflicting,
unreadable or included option files fail visibly. The exact native 32 KiB files
retain `save/opera/per_game/<stem>.<0–9>.srm`,
`save/opera/shared/nvram.<0–9>.srm` and recognized legacy filenames. A shared-mode
file is still private to this profile/game. All versions travel together as
needed; a truncated/missing working file retains recovery. Empty/relative
configuration and global-option paths now resolve against RetroArch's original
configuration directory on every rooted route, preserving native options across
temporary launch configurations. Explicit configured paths remain selected.

Version-3 resource receipts bind exact core/configuration/transaction identity
and retain version-1/2 compatibility. Recovery does not depend on cache/staged
firmware or the general marker. Quit normally and wait for sync; native resources,
ROM and configuration are cleaned only after verified closure, preserving
standalone settings and earlier progress. Do not remove private progress/cache
or recovery directories. APK/ABI/core-matched manual states use the existing
supervisor.

All 688 Flutter tests (one existing native-host skip), 96 focused cases, clean analysis and four
real production ABI downloads pass. Seventeen native filesystem/launch groups
pass, including exact NVRAM size, scoped option reads, firmware ownership and
lost-reply/edited-resource refusal. The exact 1 GiB native image fixture staged
in 3,349 ms under the unchanged 30-second deadline. The original cartridge-disc
refusal assertion caught and verified the correction of an overbroad path change;
initial helper/type/import/test-path failure logs remain retained. These source
checks do not establish packaged Opera gameplay or selected external BIOS use.
Build **1090**, runtime `09ccf43`, subsequently passed normal 3DO Setup and
Alone in the Dark (RomM 6021) on the Thor using the embedded boot ROM. Emily's
Save Game 1, 32,768-byte native NVRAM and 1,274,682-byte manual state published
as primary 245. Fresh Play restored both files byte-for-byte. Before any state
load, the native saved-slot list recognized slot 1 and the game's own Load a
Saved Game resumed the attic save. Manual Load State independently resumed the
recorded gameplay scene, with movement/action inputs exercised.

Account 3 started with an empty working inventory and published different
32 KiB initialized NVRAM and a 732,765-byte introduction state as primary 246;
no account-3 in-game progress is claimed. Returning to account 2 restored its
original two files and state scene. Final normal Quit retained primary 245.
All 37 earlier progress files, 19 managed native files, 13 original standalone/
managed files, thirteen core hashes and sixteen platform bindings stayed intact.
Both saved accounts opened without passwords, native session files/journals
were cleaned, and all 145 scoped operational lines have no warnings/errors.

One ADB keyboard event introduced a native Virtual device before the Thor
controller and occupied port 1. Selecting Ayn Odin in that unsaved session
configuration restored input; later hardware-event launches assigned it to
port 1 normally. The saved standalone configuration and runtime defaults were
unchanged. The [device record](android-retroarch-opera.json) retains that
diagnostic, exact payloads, upgrade identity and limits. Application CI
`42434249241` passed all checks/five packages and Mesen run `42434249252` passed
all four native jobs. This is one arm64 device/self-contained CHD; selected
external BIOS/font use, other ABI gameplay, cross-device play and completed-game
progression are not newly established.

## Remaining boundaries

Opera's [retained four-ABI build](../vendor/android/opera/1.0.0-370d9a2/README.md)
identifies source `370d9a2`. Its pinned source includes and defaults to an
open-source 128 KiB Opera Boot ROM, unlike the older external-BIOS-only metadata.
All four libraries contain the exact compressed source-header bytes. Provenance
records the uncompressed hash and the referenced upstream boot source separately;
an Android NDK or source-to-boot rebuild is not claimed. Complete FreeDO modified
LGPL/non-commercial terms, GPL-2.0-only boot license and component notices are
retained. No retail BIOS/game is included. This artifact preparation enables no
new route by itself; the concrete Opera source increment above remains separate
from packaged device acceptance.

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
larger download recipes and actual core integrations remain pending. Saturn now has its own exact backup-memory bounds below; N64's concrete limits
are implemented in the source increment above.

Multi-file disc content still needs safe file-set staging. Opera now has
self-contained image transport and selected firmware preparation; FBNeo's scoped
nested-save acceptance is recorded above. Flycast requires private VMUs on every port and its
option prefix differs between builds. The pinned Beetle Saturn defaults to Libretro SRAM, matching the desktop `.srm`
contract; selected Mednafen file modes are retained by the concrete increment below.
Stella and the inspected Beetle Lynx expose no ordinary Libretro save RAM.

Virtual Jaguar now uses the permanent source-identified release above; cartridge
device acceptance is recorded above and Memory Track gameplay remains separate. Jaguar CD remains
owner-deferred. Mesen's nightly provenance gap is resolved by its retained owned
source build. Flycast still needs concrete integration; Saturn's scoped packaged acceptance is recorded below. Opera's scoped device acceptance is recorded above. Lynx's scoped packaged acceptance
is recorded above.


## Beetle Saturn source increment

The retained v1.32.1 `30f4c12` four-ABI build is pinned to artifact commit
`88b71d142171be9a44d45a61779a6fba198391f9`, also held by
`android-beetle-saturn-1.32.1-30f4c12`. Its core-info display version is stale;
provenance retains source, ABI, ELF dependencies, original recipes and licenses.
No retail firmware or game is bundled, and exact upstream NDK reproduction is
not claimed. Independent Setup adds Saturn without reconfiguring other platforms.
Version 15 retains all earlier settings versions and connections.

Use **Emulator Settings → Saturn → RetroArch → Set up**, then Play one
self-contained CHD v5 of at most 1 GiB physical/logical size, without a parent.
First Play obtains `sega_101.bin` and `mpr-17933.bin` (524,288 bytes each) from this
platform's RomM firmware catalogue after canonical size/MD5 and transfer checks.
Explicit KOF95/Ultraman cartridge choices require their canonical 2 MiB ROM image.
Immutable cache objects are retained on repair. Multi-file CUE delivery and
special-cartridge auto-detection remain separate work; no descriptor is handed
to RetroArch without its tracks.

Read-only inspection follows actual game/folder/core/global option precedence.
It rejects ambiguous/includes/conflicting options rather than guessing. Defaults
retain the desktop `.srm` contract. User-selected Mednafen `.bkr`, shared filenames,
12-byte console settings, 512 KiB and 4 MiB backup cartridges keep native names.
Existing internal/cart data whose filename disagrees with the selected native mode
blocks launch visibly; no silent conversion or progress deletion is performed.
Shared options remain isolated to each Broomm profile/game. Core, ABI, configuration
and options are checked again after long preparation, before external effects.

The version-4 journal binds core/platform/configuration, disc and resource
transaction identities. Firmware stays outside ordinary saves and state groups.
Lost replies recover without the original firmware cache, staged resource or
general session marker; incompatible/foreign records preserve recovery. Native
operations retain closure, UID/label, path/descriptor, exclusive publication and
readback checks. Ordinary save lengths are exact; truncated SRAM/cartridges are
damaged recovery, not empty progress. Previous native/core limits stay scoped.

Clean analysis, bridge compilation, 91 focused tests, four real versioned ABI
downloads and nineteen native fault groups pass. The native groups include
4 MiB cart, resource-copy lost replies, writer arrival, source replacement,
idempotent cleanup, options and CHD handoff. The existing exact-1-GiB transport
fixture passes in 2,754 ms under its unchanged 30-second deadline. The new
missing-marker case caught and fixed absent version-4 session discovery; its
original assertions remain. Initial compiler/fixture and sandbox diagnostics are
retained locally.

The full macOS run has 697 passes, one existing host skip and an unrelated Astris
application-capture error. All three Astris cases pass separately; that diagnostic
does not erase the full-run failure. Packaged BIOS/game/save/state and two-account
Thor checks are recorded below. After verification, Quit normally and wait for sync,
verify a native in-game save independently of manual Load State, switch accounts,
and confirm their different data. Keep Broomm snapshots/cache/recovery and stable
locks; native session discs/configuration/BIOS are cleaned after verified exit.


## Beetle Saturn device acceptance

Thor build **1093**, source `277113b`, passed ordinary Saturn Setup and Play with
one self-contained USA CHD of The Legend of Oasis (RomM displays The Story of
Thor 2). Both actual staged regional BIOS files matched canonical MD5 and
transfer SHA-256. Native movement/jump and Aquaria System 0 / Cartridge 0 saves
were exercised. Normal Quit published 32 KiB SRAM, a 512 KiB backup cartridge,
12-byte console settings and a 1,848,374-byte manual state as primary 247.

Fresh Play restored all four hashes before any load. Native Continue displayed
both saved slots and loaded System 0 into Aquaria. A separate fresh process loaded
Cartridge 0 before any manual state load. Manual Load State then independently
resumed the original save-circle scene. One intervening test input intended as
soft-reset actually entered Save mode and saved Cartridge 0 again; normal Quit
preserved that copy as primary 248. It is not counted as a cartridge load. The
subsequent verified cartridge load/state restore published primary 249, retaining
the original cartridge bytes from the state and native console-clock settings.

Account 3 began with empty working data and disabled Continue. Its New Game
opening dialogue, initialized SRAM/cartridge and state published different hashes
as primary 250; no second-account in-game save is claimed. Returning to account 2
restored all four primary-249 hashes and its gameplay state. Final normal Quit
retained primary 249 without another publication. Both saved sign-ins opened
without passwords. All 41 earlier progress files, 19 managed native files,
13 original standalone/managed files, fourteen core hashes and seventeen platform
bindings remained intact; journals were cleared and all 163 scoped log lines
had no warnings/errors.

Application CI `42449620564` passed all checks and five packages; independent
Mesen CI `42449620562` passed all four native jobs and post-job steps. The current
universal Mac archive has verified input fingerprints, ZIP integrity and
source/extracted deep strict signatures. The local full-suite Astris capture
failure recorded above is still unresolved. See the [exact evidence](android-retroarch-saturn.json).
This establishes one arm64 device/game, default native backup modes and both
saved accounts. Other ABI gameplay, cross-device play, completed-game progress,
special cartridges and selected Mednafen/shared/4 MiB modes remain separate.
CUE transport and special-cartridge auto-detection are unfinished.


## Native writer checks at progress publication

The root service now verifies closure before and after ordinary save/file
operations, with another native check immediately before publication or removal.
Previously those operations relied on Dart's earlier observation; immutable
firmware/core operations already had their own native closure callbacks. A
writer arriving during staging blocks public replacement and keeps the old
save/private stage for a closed retry. A live or unknown writer also blocks
idempotent replay and ROM cleanup. Read-only inspection/lifecycle calls remain
available during gameplay.

Bridge and fixture compilation and all 21 disposable Thor native groups pass.
Two new groups deterministically hold the writer gate and change it at the
staged-publication checkpoint, verifying old-save preservation, retained pending
ROMs, cleanup refusal and successful closed retries. Packaged application
acceptance of this additional guard remains pending; Saturn build 1093 predates
it. Native image transport still completes its exact 1 GiB case within the
unchanged deadline (2,769 ms). No new library or global device setting is used.


## Flycast source increment

The retained four-ABI `7adbf3c` build is pinned to artifact commit `f51373b` and
`android-flycast-7adbf3c`. ZIP/payload hashes, ELF classes/machines, Android-only
system dependencies, original CMake inputs, GPL-2.0-or-later and conservative
component notices are retained in [provenance](../vendor/android/flycast/7adbf3c/README.md).
All four ELF Android notes identify API 21 / NDK r29; this is inspected build
metadata, not an independently reproduced NDK recipe. No BIOS/game is bundled.
Independent Dreamcast Setup retains all previous cores and connections; settings
version 16 reads versions 1–15 and refuses forged older Dreamcast bindings.

Use **Emulator Settings → Dreamcast → RetroArch → Set up**. Complete the standard
RetroArch first open if requested. Add canonical `dc_boot.bin` (2,097,152 bytes,
MD5 `e10c53c2f8b90bab96ead2d368858623`) to Dreamcast firmware in RomM. Play a
self-contained CHD v5 of at most 2 GiB physical/logical size, without a parent.
Firmware transfer/cache validation and read-only disc hashing are cancellable;
core, ABI, configuration and actual option precedence are checked again after
preparation. CUE/GDI/M3U/CDI and Naomi/Atomiswave remain outside this increment.

All VMU ports use private game/profile storage. Native disc game-ID and legacy
outer-filename `.[A-D][12].bin` names retain the desktop ordinary-save contract;
VMUs are exactly 131,072 bytes, with at most eight of each naming generation.
No arbitrary `.bin` or console flash is a game save. Flycast alone has a 64 MiB
state cap and 128 MiB total progress cap; earlier limits stay unchanged. States
retain exact frontend APK, ABI and core fingerprints.

The selected core's mutable console flash is `system/dc/dc_nvmem.bin`, not the
older initial `dc_flash.bin` dump. Broomm retains it locally across one profile's
games as immutable historical objects with an atomically published current index.
It is never uploaded as one game's VMU and never replaces the standalone console
identity. Missing or damaged known flash blocks sync. Version-5 session resources
bind every native path to the core, profile/game and configuration nonce. Source
cache loss, missing general marker, partial install and lost publication/cleanup
replies retain recovery; readback confirms publication before native cleanup.

A private copy of selected core options supplies All VMUs and disabled linked
DreamPotato storage. Other options persist per game without rewriting global
RetroArch files. Normal core teardown in the pinned frontend flushes options
independently of `config_save_on_exit`; packaged persistence still needs device
acceptance. Verified Remove clears these private preference files across owned
profiles, retaining saves/states, console objects, firmware cache and historical
recovery. Linked or unrecognized storage blocks configuration cleanup.

If VMU mode/linked storage is changed during play, Broomm holds the new ordinary
saves/states and captures fallback VMUs before reporting the problem. It does
not guess which card is authoritative or publish incomplete progress. Retain
`android/shared-session/<transaction>/captures/<capture>/native` and
`flycast-captures/<capture>` under Broomm's private files root. **Keep emulator
folder unchanged · Finish** explicitly retains those copies and the native folder
for manual recovery without upload. Do not delete the directory or uninstall
RetroArch before recovering the intended VMUs. This exceptional mode change has
no automatic card-conversion UI; normal supplied settings do not require it.

All 107 focused cases and four actual production downloads pass; native bridge
and fixture compile. All 26 disposable Thor native groups pass, including an
exact 64 MiB state and an exact 2 GiB image staged in 4,496 ms under the unchanged
30-second deadline. The new interrupted-link case first reproduced the own-stage
metadata failure, then passed after exact inode/hash/UID/label/closure recovery.
Extra links, changed checksums and writers still refuse cleanup for
Flycast/Lynx/Opera/Saturn. No assertion or timeout was relaxed; the failed fixture
and matching AndroidRuntime stack are retained. This is native mechanism and
Dart workflow verification, not packaged Dreamcast gameplay/firmware/VMU/state
or two-account acceptance. The final whole suite has 714 passes and one existing host skip, with clean
analysis and 357 unchanged input fingerprints. See the [source evidence](android-retroarch-flycast-source.json). Multi-file media remains unfinished.
