# Implementation plan

## Beetle Lynx artifact preparation — 2026-11-07

Four unmodified Android ABI archives identify Beetle Lynx 1.24.0 source
`fcdefcf`. Source/archive/library hashes, ELF identities, Android-only system
dependencies, original Android recipes and component notices are retained,
including Handy, Blip_Buffer and libretro-common terms. Local inspection verifies
each archive and embedded revision; an upstream NDK rebuild is not claimed.
No BIOS is bundled. Firmware/session implementation and packaged Lynx acceptance
remain pending; this artifact preparation enables no new application route.

## Rooted Jaguar device acceptance and independent core CI — 2026-11-07

Build 1079 (`675ab8b`) passed Jaguar Setup and Tempest 2000 launch/input. Normal
Quit published its native 128-byte EEPROM as primary 239. The real menu check
found that RetroArch 1.22.2's bundled Virtual Jaguar 2.1 metadata disables states,
despite the reviewed 3.11 core providing them. The correction uses the frontend's
documented metadata override in the disposable session configuration only for
the exact reviewed ABI/payload hashes. Unknown cores retain the inherited policy;
standalone metadata/preferences are untouched.
Clean analysis, all 657 Flutter tests (one existing native-host skip) and all
50 rooted-session regressions pass. The initial sandboxed test harness could not
bind its loopback socket; the native rerun passed without changing tests.

Build 1080 (`855e6a6`) passed the corrected native menu, manual Save/Load State,
normal Quit/sync and fresh Play. Both the 128-byte EEPROM and 80,783-byte state
restored byte-for-byte; Load State resumed the saved level-start scene with
score 0 and three lives. The original display preference was restored before
final primary 241, retaining the state. All 22 earlier additional-core progress
files, eight GBA/SNES files, 19 managed native files and 13 original standalone/
managed files stayed unchanged. Ten cores, thirteen bindings, both accounts'
distinct earlier histories and journal cleanup pass; 86 scoped log lines have
no warning/error. No completed level, Memory Track or cross-device gameplay
claim is made. See the [exact device evidence](docs/android-retroarch-jaguar.json).

All application jobs and five packages passed run `42422129526`. In the separate
Mesen run `42422129552`, all four native libraries built and uploaded, but x86's
Nix installer post-job diagnostics request timed out and its old bundled promise
handler crashed. The workflow now invokes the same pinned installer directly
with its supported diagnostics opt-out before Devbox. Build/test steps, deadlines
and failure handling are unchanged; workflow lint passes. Corrected run
`42424364865` passed all four native jobs and every post-job step. Application
run `42424365012` passed all checks and all five packages. The original failed
job/log is retained. The current macOS package passes archive, input-fingerprint
and source/extracted deep strict all-architecture signature checks. Five selected
cores remain pending; PR #4 stays draft.

## Rooted Jaguar cartridge source increment — 2026-11-07

Independent Jaguar Setup downloads Virtual Jaguar 3.11.0 directly from its
official tagged four-ABI release with pinned payload hashes. Exact source,
upstream build recipes, ELF dependencies and component notices are recorded;
the firmware-array provenance boundary is explicit and no release binary or
boot-ROM array is mirrored. Settings version 11 retains versions 1–10 and
earlier connections. Cartridge/ZIP staging, raw EEPROM and matched states use
the existing Dart supervisor and journaled native file boundary. Jaguar CD
remains deferred; earlier size limits are unchanged.

Clean analysis, all 655 Flutter tests (one existing native-host skip), 61 focused
checks and thirteen disposable Thor filesystem/launch groups pass. The native
bridge and fixture compile. All four official assets pass a real production
download/ELF check. Packaged Jaguar gameplay remains pending; five other
selected cores remain research. See the [scope and walkthrough](docs/android-retroarch-cores.md#jaguar-cartridge-source-increment).

## Rooted NES/Mesen device acceptance — 2026-11-07

Current source adds independent NES Setup using the four-ABI Mesen build retained
at `7a0fb0a`, with exact source `0102910` and original compiler records/notices.
Version 10 preserves earlier connections. Raw/ZIP `.nes/.unf/.unif` cartridges,
desktop-compatible SRAM and matched states use the existing profile/game
supervision and recovery. Earlier resource limits remain unchanged; FDS disks
and HD packs have no new acceptance.

Clean analysis, all 649 Flutter tests (one existing native-host skip), 58 focused
checks and thirteen disposable Thor filesystem/launch groups pass. The native
bridge and fixture compile. All application CI jobs and five packages passed.
Build 1077 (`1ecf544`) passed normal NES Setup, Zelda slot-A SRAM restoration,
gameplay/input and manual-state reload at the cave entrance. Journal-installed
SRAM/state hashes match the published checkpoint; the running core changed SRAM
before readback, so live SRAM byte identity is not claimed. Final Quit published
primary 238 and retained the manual state. All earlier saves/settings, nine core
hashes, twelve platform bindings and both accounts' distinct earlier histories
remain intact; 51 reviewed log lines contain no warnings/errors. An apparent
graphics problem was an inconsistent image preview, disproved by identical PNG
bytes and pixel checks; no graphics behavior was changed. Six other selected
cores remain research. See the [device evidence](docs/android-retroarch-nes.json)
and [scope and walkthrough](docs/android-retroarch-cores.md#nesmesen-source-increment).

## Pinned Android Mesen build preparation — 2026-11-07

The exact Mesen 0.9.9 source archive and recipe/license inputs are retained.
A separate four-ABI CI job builds that source using the privately staged,
already licensed NDK 29.0.14206865. It records source/tool/output hashes,
compiler logs and ELF dependencies before any runtime download pin is accepted.
Source inspection, three owning regressions, analysis and workflow lint pass
locally. All four ABIs passed native compilation in CI run `42416669733`; their
checksums, ELF identities, Android-only dependencies, original logs/records and
component licenses are retained. A ZIP-method metadata label was corrected
against the actual archive without rewriting historical build records. Mesen
gameplay remains pending; that build-preparation increment enabled no app
behavior. The subsequent source increment is recorded above.

## Rooted Nintendo 64 device acceptance — 2026-11-07

Current source adds independent N64 Setup, pinned four-ABI Mupen64Plus-Next
delivery with its actual Android GLES3 filename, raw/ZIP cartridge staging up
to 64 MiB, the full 296,960-byte native save and 32 MiB states. Earlier cores'
limits remain unchanged. Version 9 settings retain earlier bindings; core-aware
file mechanics and original platform records retain recovery behavior.

Clean analysis, all 642 Flutter tests (one existing native-host skip), 51 focused
Dart checks and thirteen native Thor filesystem groups pass. The final 42-test
root suite also passes after the limit helper cleanup. Native checks include
exact 64 MiB staging, oversized refusal, full SRAM and interrupted large-state
recovery. Build 1073 (`d30e81f`) passed normal N64 Setup, Super Mario 64 rendering,
analog movement/jump, EEPROM-backed audio-preference synchronization and manual
gameplay-state reload. The complete native save/state restored byte-for-byte;
final Quit restored STEREO and synchronized without changing the gameplay state.
All earlier saves/settings, eight cores, eleven bindings and both accounts'
distinct earlier histories remain intact. The reviewed 81 log lines have no
warning/error; all CI jobs passed. No completed-star or controller-pak gameplay
claim is made. See the [device evidence](docs/android-retroarch-n64.json) and
[concrete scope](docs/android-retroarch-cores.md#nintendo-64-source-increment).
Seven other cores remain research.
The separate Windows diagnostic revision `cf75b58` passed all CI jobs; native
readiness was 1,770 ms. The earlier failure's cause remains unknown.

## Sega cartridge device acceptance — 2026-11-07

Build 1069 (`f00df30`) passed the three downloaded Sega ZIP launches, Sonic 3
gameplay/manual-state reload, Phantasy Star in-game SRAM/state reload and
Defenders of Oasis Continue/state reload. Build 1066 verified Chaotix rendering,
menu and title-state reload, without claiming ordinary SRAM or completed 32X
gameplay. Native cleanup, seven core hashes, ten platform bindings and all prior
save/settings preservation checks pass. Both accounts' earlier histories remain
distinct; Sega used the original account. See the [exact scope and
receipts](docs/android-retroarch-sega.json).

The preceding ZIP sections record the failures and corrections that led to
1069; their pending status is historical. All five current packages and
macOS/Linux/native Android checks passed. The separate Windows updater fixture
missed its unchanged eight-second readiness deadline with a live helper and no
output/install log. Its cause remains unresolved; the failure has not been
retried, skipped or masked. PR #4 stays draft; eight other cores remain research.

## Rooted cartridge ZIP preparation — 2026-11-07

Build 1067's first ZIP check exposed the native adapter's library-only source
guard. The follow-up keeps that guard and separately validates a normalized
cartridge inside the exact session transaction on both sides of the root mount
namespace. Foreign transactions, filenames, traversal and links are refused.
The bridge and native fixture compile; JVM path checks and eleven disposable
Thor filesystem groups pass. Packaged ZIP acceptance remains pending.

Build 1068 passed that private source handoff, then exposed the launch adapter's
separate exact-filename check. The follow-up accepts the unchanged archive stem
with the validated extracted extension and retains core/game/profile/configuration
checks. The complete production launch validator is included in the disposable
Android fixture, with raw/ZIP routes and wrong filename, game, core and profile
cases. Packaged ZIP acceptance remains pending.

The updated bridge and fixture compile; all twelve Thor fixture groups pass,
including the actual launch validator. The previously passing 638-test Dart
suite is unchanged by this native-only correction.

Sega catalogue checks found ordinary single-cartridge ZIP downloads, which the
earlier rooted handoff refused. Current source validates ZIP structure and
extracts privately in Dart before the existing native cartridge staging. It
requires exactly one supported cartridge, keeps the archive's save/state stem,
retains the 32 MiB cartridge limit and bounds archives/expanded content to 64 MiB.
The downloaded game stays unchanged. Durable staging records cover cleanup after
a lost native reply. Focused regressions pass for nested names, cleanup retry,
ambiguous/unsafe entries, oversized payloads and corrupt extraction. Analysis
and all 638 Flutter tests pass, with one existing native-host skip; the focused
39-test root suite also passes with a lost native staging reply. Packaged ZIP
gameplay remains pending.

## Rooted Sega cartridges — 2026-11-07

Current source adds independent Genesis, Master System and Game Gear Setup via
Genesis Plus GX, plus 32X via PicoDrive. Four-ABI downloads pin retained artifact
`db5b758`, corresponding source, submodule provenance and notices. Version 8
settings preserve earlier connections. Uncompressed cartridges use the existing
raw SRAM/state contracts and journaled profile/game boundary. Genesis Plus GX's
larger library uses bounded streaming; other core download limits stay unchanged.

Clean analysis and all 635 Flutter tests pass with one existing native-host skip.
The production bridge compiles and all eleven Thor filesystem groups pass,
including Sega cartridge staging and the large-core faults below. Packaged Sega
gameplay is pending; the other eight cores remain research. See the
[core walkthrough](docs/android-retroarch-cores.md#sega-cartridge-increment).

## Large Android core transport — 2026-11-07

The next remaining-core prerequisite streams native core inspection/staging with
a 96 MiB bound, a small ELF header and descriptor identity checks. Cancellation,
writer exclusion, exclusive publication and interrupted-link recovery remain.
The bridge compiles; all eleven filesystem groups pass on Thor. The separate
80 MiB fixture also passes directly through ART with an asserted exact 32 MiB
heap, including cancelled-copy retry, a forced timestamp tie/source replacement
and a destination appearing before publication. No additional core delivery or
gameplay support is claimed by this native prerequisite.

## Rooted Atari 2600 and TG16 cartridges — 2026-11-07

Current source adds independent Setup for Stella and Beetle PCE Fast with pinned
four-ABI archives and exact source notices. Version 7 settings preserve existing
connections. Uncompressed Atari `.a26`/`.bin` and TG16 `.pce` use the existing
journaled native boundary, raw PCE SRAM, state-only Stella progress and
build-matched states. No disc/firmware or compressed-content acceptance is added.
Clean analysis and 628 Flutter tests pass with one existing native-host skip;
the bridge compiles and ten real Thor filesystem groups pass in disposable
storage. Build 1062 passed normal Setup, Adventure state upload/reload and
Neutopia's in-game File Cabinet SRAM plus manual-state round trip. All five
installed cores, six platform bindings and prior progress/settings were
preserved; native temporary files were removed. See [scope and
provenance](docs/android-retroarch-cores.md#atari-2600-and-tg16-cartridge-increment).

## Remaining rooted RetroArch cores — 2026-11-07

PR #3 merged as `e92c584` after the GBA/SNES and offline-profile checks below.
The next branch starts with GB/GBC through Gambatte: independent platform setup,
immutable four-ABI archives, SRAM/RTC and exact-build states. Version 6 settings
retain GBA/SNES connections; session and swap receipts retain the original
platform for recovery. Native staging accepts the concrete uncompressed GB/GBC
extensions and bounded SRAM/clock selectors.

Analysis and all 623 Flutter tests pass, with one existing native-host skip. The compiled
production bridge and nine native filesystem fault groups pass, including real
Thor SRAM/RTC selection and GBC staging in disposable storage. All PR build jobs
passed. Build 1061 passed normal GB/GBC Setup, Crystal SRAM/RTC/state upload and
reload, and separate Tetris/Crystal state histories for both accounts. All prior
GBA/SNES progress and standalone settings were preserved; temporary native files
were removed and the original account remains selected. Other cores are
researched, not yet implemented. See [scope, device evidence and remaining
boundaries](docs/android-retroarch-cores.md).

## Offline activation, rooted save states and SNES — 2026-11-07

Current source adds explicit saved-profile activation during transport outages,
persisted per-account allow/deny receipts, identity-checked reconnection and
immediate refresh-token rotation persistence. Read-only credential failures and
online auth/game rejection remain distinct from connectivity. Home exposes
offline status and retry; game access is checked before launch effects.

Rooted RetroArch now supports GBA/mGBA and SNES/Snes9x with independent setup
bindings, fixed versioned four-ABI core downloads, SRAM and build-isolated
states/thumbnails. Descriptor transport avoids Binder payload limits; the Dart
transaction retains original native metadata and old state provenance during
core-change recovery. Missing working files retain recovery. Ordinary save
formats stay compatible with the desktop contracts.

Clean analysis and all 619 Flutter tests pass, with one existing native-host skip.
CI for runtime `c614999` passed on Windows, Linux and macOS and built all five packages. Eight native
fault groups passed on the Thor, including large descriptor transfers, bounded
inventory and interrupted state publication. Build 1057 passed packaged checks
with both accounts: offline restart/activation, queued GBA state isolation,
reconnection, older save/state restoration, automatic Snes9x setup, and separate
SNES SRAM/state upload and in-emulator reload. Existing original SRAM and
standalone settings were preserved. Final inspection found retained temporary
session configurations. The follow-up journals their hashes before publication
and removes only matching owned files, with interrupted publication, edited-file
and lost-cleanup-reply regressions. Build 1058 passed the packaged cleanup check
with GBA/user 2 and SNES/user 3: both states loaded, generated configurations
were removed, and all 19 existing managed native files stayed unchanged. Both
accounts remain synchronized on the Thor, with the original account selected.
See the [walkthrough and scoped device
evidence](docs/android-root-access.md#offline-profiles-rooted-states-and-snes--2026-11-07).
The current [macOS package](build/releases/Broomm-macOS-offline-states-snes-preview.zip)
is **24,349,989 bytes**, SHA-256
`09129651e6ea162379b99b1620373af9f42bfc6929a6926a2b73c27466a4fe41`.
Source/extracted deep strict signatures, ZIP integrity and all seven universal
Mach-O payloads pass. It is ad-hoc signed, not notarized. Exact revisions,
artifact fingerprints and results are in the [portable evidence](docs/android-offline-states-snes.json).

## Rooted Android reliability checks — 2026-11-07

The installed build 1054 passed Thor checks for live-writer exclusion, offline
save capture and reconnect, durable restart recovery, denied/regranted root,
revoked-root recovery, a real changed-device/changed-cloud conflict and exact
original-save restoration followed by in-game file-list verification.
Standalone configuration stayed byte-identical. Two authenticated accounts
used separate native saves; an inactive account's queued upload stayed paused
until its owner was selected. Seven current native fault groups also passed in
disposable Android storage. Known-profile activation after an offline restart
is an identified product gap, distinct from pending-save durability. See
[the device record and limits](docs/android-root-reliability.md).

## Unified Android setup and versioned mGBA — 2026-11-07

Android retains compact cards with the desktop **Set up / Verify setup**,
**Remove**, **Open emulator** and **Set as default** actions. Setup guides
installation and first open, requests root and provisions mGBA for GBA
RetroArch, or guides the existing shared-folder grant. It resumes from package
readback and verifies resources before publishing a fresh root connection.
Only configured platforms participate in default selection. Optional APK
imports and explicit reinstall remain inside Verify setup.

The four reviewed mGBA archives are mirrored under
`vendor/android/mgba/0.11-212-7a12d6d` with original hashes, MPL license and
exact source provenance. Download URLs pin artifact commit `c6156ac`, retained
by tag `android-mgba-0.11-212-7a12d6d`. These are the previously tested bytes.
The installer retains ABI, checksum and exclusive publication checks.

The owner selected external-app uninstall and configuration clearing for
Remove. Android owns uninstall confirmation. A durable removal record blocks
play while the result is uncertain. Confirmed absence permits cleanup of
connections, legacy provider registrations and defaults. Cancellation retains
setup, and interrupted cleanup is idempotently resumable. Broomm's saved
progress and game content are retained.

Analysis, 54 focused tests and the full 605-test Flutter suite pass, with one
existing native-host skip. The Android bridge and device regression archive
compile. The isolated Activity fixture passed on the Thor and verifies intent
construction, cancellation/readback, late callbacks and the folder-permission
request-code collision fix. It captures intents in a test Activity. The owner
subsequently accepted the packaged setup/removal flow on the Thor with build
1054. Device logs confirmed uninstall, official APK installation, mGBA setup and
a fresh root connection matching RetroArch's new UID. PR #2 merged as `f4857e0`.

## Emulator first-open guidance — 2026-11-07

The owner confirmed that opening RetroArch separately restored the normal menu.
The installation and save-folder dialogs now ask players to open each Android
emulator once, finish its first-run setup and permissions, then close it before
playing from Broomm. Rooted RetroArch retains its resource-readiness check.
The owner requested keeping this source change for the next feature build.

## Standard RetroArch first open on rooted Android — 2026-11-06

The owner confirmed the build 1052 controller fix and reported missing
settings icons and a pixelated font. The Thor's APK matched the official
RetroArch 1.22.2 arm64 download by SHA-256. The APK included the menu resources,
while the installed stock menu directories were empty. Direct gameplay skipped
the normal Android launcher that initializes RetroArch's bundled files.

Rooted GBA setup now offers RetroArch's standard first open when bundled menu
resources are missing. Direct play checks readiness before creating a game
journal or synchronizing saves. The user can open RetroArch from that screen
and retry play after quitting. The package installer and configured custom
asset directories are preserved. The Kotlin bridge compiled, the disposable
resource check passed on the Thor, and focused Dart tests verified that
incomplete setup creates no game journal and can be retried. On 2026-11-07,
the owner confirmed that opening RetroArch separately restored its normal
appearance. The Broomm prompt still needs packaged-device acceptance. See
[the first-run walkthrough](docs/android-root-access.md#automatic-mgba-setup).

## Cold RetroArch controller profiles — 2026-11-06

Build 1050 downloaded and verified mGBA on a fresh Thor and launched Minish Cap.
The owner reported the Odin fallback notice and that Back no longer opened the
menu. RetroArch's standalone configuration was empty and the default profile
directory had no files. The APK contains the Odin Controller profile for
8224/273, including Back as Menu Toggle. F1 opened the menu over ADB and the
owner closed RetroArch and confirmed sync before the second clean uninstall.

The rooted launch now stages Android profiles from the verified installed APK
under a build-specific Broomm directory when the default profiles are missing.
It uses that directory in the generated session config and preserves explicit
controller preferences. The owner confirmed this works on the Thor with
build 1052.

## Automatic mGBA setup on rooted Android — 2026-11-06

The owner confirmed the older Minish Cap save loaded in-game. PR #1 merged into
`main` as `f7ffa1a`. The Thor's RetroArch package and app-owned private and shared
data were removed before the new cold-install test.

The GBA card can now use the existing root service to inspect the installed
RetroArch ABI and reuse a compatible mGBA. If the core is missing, Dart verifies
the selected Libretro ZIP and stages the checked payload in Broomm's private
storage. The root service revalidates ABI, identity and closure before exclusive
publication. A missing standalone configuration uses RetroArch defaults with
Broomm's isolated session overrides. Cold setup and gameplay on the Thor are
pending. See [source provenance and the setup walkthrough](docs/android-root-access.md#automatic-mgba-setup).

## Verified RetroArch closure on rooted Android — 2026-11-06

The GBA session verifies RetroArch is idle before starting without a prompt.
The bound root service observes the verified package UID and identifies the
launched process using its PID and kernel start time. On return to Broomm, it
matches the observed process to Android's exit history and checks for a live
writer before save capture and restoration. A normal exit allows automatic
sync. A running process leaves the session active. Unknown and interrupted
exits keep recovery available, with unclean progress kept locally for review.
Shared-folder sessions use the existing explicit confirmation.

## Compact Android emulator settings and independent GBA binding — 2026-11-06

Android emulator cards show the app, a short status and compact actions.
Setup instructions remain in the dialogs. **Inspect root access** is a
single page action with an installed-emulator picker when needed.

Settings version 4 stores the GBA root binding separately from the shared
folder. Existing version 3 root bindings load into the new slot, preserving
their package and recovery identity. GBA prefers its root connection, and
other RetroArch systems retain their shared-folder route. Disconnecting GBA
root saves returns to the configured folder and retains progress. Regressions
exercise both layouts, legacy settings migration and the page action.

The Android pre-launch screen separates **Sync and play** and **Back** by 12
logical pixels. A widget regression checks the gap between the touch targets.

## Root connection reuse and Thor save verification — 2026-11-06

The owner confirmed Minish Cap gameplay and sync on build 1042. Broomm's
completed swap journal records a changed 8 KiB save. RomM save 199 was
uploaded and downloaded for verification, the previous emulator file was
restored, the staged ROM was removed and the active journals cleared. The
standalone save hash still matches its original value. Loading save 199 in a
subsequent gameplay session remains unverified.

Build 1042 starts a Magisk shell for each privileged call. The follow-up
starts the existing non-daemon root service lazily and keeps its binder for
the Broomm activity, including emulator handoff. Each request still verifies
package identity and uses the same deadline and file lock. Connection loss
reports failure without replaying an uncertain operation. Activity destruction
releases the binding. See [the device check](docs/android-root-access.md#root-connection-reuse--2026-11-06).

The owner confirmed the notification fix on build 1043. After an initial
permission failure, one service startup served 18 successful operations
through play and sync. Broomm uploaded and verified RomM save 203 and cleared
the active journals. The cancelled macOS baseline check was requested again.

## Rooted GBA launch handoff — 2026-11-06

The owner reported a black screen and an Android not-responding dialog on the
Thor with build 1040. RetroArch 1.22.2 received Broomm's `content://` ROM URI
and stopped during startup. Broomm downloaded existing RomM save 180 for ROM
2338, installed it for the session and captured the same 8,192 bytes after
closure. This establishes a download and unchanged capture. The game did not
run, so a new save upload and in-game restore remain unverified.

The rooted GBA route now stages the selected verified `.gba` as a private,
read-only native file and passes that path to RetroArch. It bounds the transfer
to 32 MiB and checks the staged bytes before handoff. The save journal records
the staging identity before the copy and removes it after confirmed closure
and save restoration. Earlier journals are still recoverable. Dart regressions
and the disposable native file harness passed. See
[the Thor launch evidence](docs/android-root-access.md#thor-launch-failure--2026-11-06).

Build 1041 exposed two integration errors before it could hand off the game.
The app passed an absolute library path across a namespace boundary, and the
recovery call omitted the staged ROM checksum. The app now sends a validated
library-relative path, which the service resolves in its own namespace. The
recovery call passes the journaled checksum and can finish an existing restored
swap. An isolated launch on the Thor loaded the actual ROM by native path and
initialized mGBA, video and audio. The corrected packaged handoff and a
changed-save round trip remain pending.

## Rooted Android GBA ordinary-save route — 2026-11-05

The owner installed mGBA, saved RetroArch's configuration and selected The Minish
Cap (RomM ROM 2338). A verified ROM-only test copy and owner-created save establish
its actual 128 KiB `.srm` under `RetroArch/saves/mGBA`; the active configuration
is external `Android/data`, outside the previous adapter's candidates. The
standalone test save, existing macOS save and remote RomM progress remain intact.
Automatic Android core download inside Broomm is now an explicit subsequent
setup requirement; manual mGBA setup is temporary.

The owner approved libsu **6.0.0 core/service** after the recorded dependency
comparison. The modules are strictly pinned, restricted to their JitPack group,
hash-verified through Gradle, and accompanied by bundled license/source notices.
A non-daemon bound root service performs only package-bound filesystem operations;
Dart retains save plans, session leases, profile/cloud decisions and recovery.
The native service keeps an OS lock through its actual effects, bounds requests
and payloads, rejects unknown access/path/identity observations, preserves native
ownership/mode/SELinux labels, flushes staged data and directories, and resumes
interrupted staging/publication using the Dart journal's operation token.

**Connect GBA root saves** explicitly verifies the installed mGBA core and current
configuration before persisting a separate root identity. GBA sessions use exact
ordinary-save selection and generated configuration under the emulator's private
`files/Broomm/<profile>/<content>` boundary. Standalone shared-storage saves are
not adopted or overwritten. Existing save journals own snapshot/install/capture/
restore, including denial and interrupted writes. Save states, other rooted
emulator routes and automatic core installation are not implemented by this slice.
Read-only root inspection and existing folder connections remain available.
RetroArch receives its frontend startup extras. The shared-I/O lock now resolves
Android's trusted framework filesDir alias while still refusing linked children.

Five new Dart cases pass for explicit/persisted setup and profile boundaries,
ordinary-save capture/restoration with metadata, and interrupted/revoked access
with identity refusal. A missing previously installed working save retains
recovery and cannot become an empty upload. Same-named games use distinct
local working paths based on content identity, with separate profile readback. The Kotlin bridge compiles. The actual file primitives
pass an isolated root harness on the Thor: replacement and metadata restoration,
changed/linked paths, interrupted stage/link publication, expired requests and
a held production lock excluding a separate Android process. Fixture files were
removed; no emulator save was used by that harness. These results do not yet
establish in-app launch or a real RomM round trip. The owner subsequently
confirmed the packaged Binder/core/config connection in build 1038 after
reopening Broomm. A follow-up obtains Magisk permission before registering the
libsu binding, reports startup phases and refuses late replies. It also unifies
the root and app transfer-lock path, initializes the inode as the app, and fixes
the launcher/provider library boundary to the actual `files/broomm/library`.
Native path/lock regressions pass; the updated APK still needs device checks.
All **581 Flutter tests** pass (one existing Linux-only skip on macOS), static
analysis and workflow/shell lint are clean, and Kotlin compilation plus native
inspection/lock regressions pass. The new lock cases accept the trusted Android
filesDir alias and reject linked child paths. The fresh universal macOS archive
is [Broomm-macOS-rooted-gba-preview.zip](build/releases/Broomm-macOS-rooted-gba-preview.zip),
24,323,563 bytes, SHA-256
`50a88c76a8e9bebb2b5bc17458669ca6dbe214edb845c55676cebdf87b5c5442`.
ZIP integrity and source/fresh-extraction deep/strict/all-architecture signatures
pass; all seven Mach-O payloads are universal. It remains ad-hoc signed, uses
normal Application Support and disables development self-updates. PR APK and
in-app device acceptance remain separate checks. Actions run
[42122253927](https://github.com/Broomm/broomm/actions/runs/42122253927)
passes every check/package job for `2efaba2`. Its verified APK build 1038 is
installed on the Thor for the packaged root-connection check; it precedes the
additional missing-save guard. No Broomm progress/recovery existed before the
approved reinstall, and the standalone Minish Cap hash remains unchanged. See the
[implementation and walkthrough](docs/android-root-access.md). Final application source `bcc0f07` passes all checks and
packages in [run 42127441352](https://github.com/Broomm/broomm/actions/runs/42127441352).
Its hash-verified APK **build 1040** is installed on the Thor; owner launch/save/
sync acceptance is pending. The reinstall again confirmed no Broomm progress
or recovery data beforehand.

## Magisk root-inspection namespace correction — 2026-11-05

The owner confirms successful RetroArch installation through build 1035 and
an explicit Magisk grant to Broomm. Root inspection still failed: Android's
isolated app namespace hides the other app's directory despite UID zero.
The exact command was reproduced read-only on the Thor under Broomm's UID and
namespace: inherited namespace fails; Magisk's command-local global namespace
(`su -M`) returns complete RetroArch owner/mode/SELinux metadata. The adapter now
uses that option, preserving package/user/path verification and bounded output,
cancellation and timeout. It never changes root-manager policy or emulator files.

Fixed stage codes distinguish unreadable request, unverified root identity,
hidden/unresolved directory and metadata failure. Dart logs allowlisted codes
without exposing platform diagnostics. Native regressions cover those refusal
boundaries; the exact updated device script returns exit 62 in the isolated
namespace and a complete report in the global namespace. This is native script
evidence. The owner subsequently confirmed **Read-only inspection completed**
inside Broomm build **1036** on the Thor with Magisk. This completes the first
read-only root-inspection acceptance gate for this device/frontend combination;
mGBA core/save-path verification and a real save round trip remain pending. See the
[device evidence](docs/android-root-access.md#thor-magisk-namespace-failure--2026-11-05).

Local evidence and build results are under `.tool-cache/android-root-failure/`.
All 576 Flutter tests pass (one existing Linux-only skip on macOS), static
analysis is clean, native process regressions pass and the Android bridge
compiles with its two existing updater deprecation warnings. The current
[universal macOS archive](build/releases/Broomm-macOS-root-namespace-preview.zip)
is 24,328,539 bytes, SHA-256
`be387ddec322a9bdaeb916e16c76586035795e3247a1cdb2004590e080ef6a9c`.
ZIP integrity and source/fresh-extraction deep/strict/all-architecture signatures
pass; all seven Mach-O files are universal. Version `0.1.16-dev` remains ad-hoc
signed with normal Application Support and disabled development self-updates.

## Android app-namespace APK alias correction — 2026-11-05

The owner reproduced `android-emulator: Invalid downloaded APK` on build 1034.
Its app log confirms another complete transfer and immediate path rejection.
The previous correction fixed the missing `broomm` component but did not account
for Android's isolated app mount namespace: read-only `/proc/<pid>/root` and
`nsenter -t <pid> -m -- readlink -f ...` show `/data/user/0` is a symlink to
`/data/data` inside Broomm, while the ADB root shell sees a directory. The earlier
shell-only canonical-path observation did not establish the app's view.

The downloaded APK validator now resolves only the framework-supplied files
root. It accepts the exact logical or canonical staging filename, rejects
traversal/foreign paths and any linked component below that root, and returns
the canonical file for package inspection and the one-file provider grant.
Failure messages identify the rejected boundary without exposing account data.
No application-storage migration or save-path change is made. Regression cases
reproduce the trusted root alias, canonical grant readback, file/directory links
under the aliased root and a foreign user's staging path. Native JVM checks and
Android bridge compilation pass (the two existing updater warnings remain).
The new alias regression fails against the previous validator and passes with
the correction. All 28 affected Flutter tests pass. The current universal
[macOS archive](build/releases/Broomm-macOS-android-path-alias-preview.zip) is
24,328,539 bytes, SHA-256
`30291d5245ce431ff60403cae99031ed3e5fd94732c5ac2e274e70112efeddb3`.
Archive integrity and source/fresh-extraction deep/strict/all-architecture
signatures pass; all seven Mach-O files are universal. Version `0.1.16-dev`
uses normal Application Support, ad-hoc signing and disabled development
self-updates. Updated APK installer acceptance still requires device execution.

Evidence and build logs are under `.tool-cache/android-apk-rejection/`.

## Android downloaded APK handoff and visible feedback — 2026-11-05

The Thor's installed PR build 1033 successfully requested install permission;
the owner granted it and the OS app-op confirms `allow`. Read-only inspection
of Broomm's own log shows two complete RetroArch APK downloads (183,956,821
bytes each), then immediate handoff failure. Native code and the content
provider expected `files/android/apks`, while ShellStorage and the downloader
use `files/broomm/android/apks`. Both native consumers now share one validated
staging-path check. Foreign/nested paths, links, traversal, missing/empty files
and the existing size/name constraints remain rejected.

The Install and Install APK actions now open an installation dialog with
permission guidance, transfer progress/cancellation and persistent failure
feedback with retry/close. Previously these appeared only above the long
settings list, outside the owner's GBA viewport. Successful OS handoff closes
the dialog without claiming package installation; existing readback owns that
decision. Native handoff errors now include their platform reason in phase logs.

Regression checks exercise the production JVM path validator and the actual
scrolled settings card's permission, transfer, handoff, failure/retry, imported
APK failure and cancellation feedback. All **575 Flutter tests pass** (one
existing Linux-only skip on macOS), static analysis is clean, JVM path checks
pass and the Android bridge compiles with only the two existing updater
deprecation warnings. Workflow/shell lint pass. The current universal
[macOS archive](build/releases/Broomm-macOS-install-handoff-preview.zip) is
24,328,544 bytes, SHA-256
`b7c786b9fb6fe14559328d22d7f74a5b8763600b5fa62bcb683eb340b72bb34f`.
ZIP integrity and source/fresh-extraction deep/strict/all-architecture code
signatures pass; all seven Mach-O files are universal. Version `0.1.16-dev`
remains ad-hoc signed, uses normal Application Support and disables development
self-updates. Logs and the source-bound package receipt are under
`.tool-cache/android-install-handoff/`. Read-only device inspection also confirms
the staging directory has the expected canonical path on the Thor.
The updated Android installer handoff still needs native
acceptance; no emulator save writes or root-save round trip are claimed.

## Android emulator install permission — 2026-11-05

After PR #1's APK was installed on the Thor (Android 13, user 0; Broomm
0.1.16/build 1032), the owner found only Install/Install APK on the GBA card.
Read-only ADB inspection confirmed no RetroArch package. The root action is
intentionally installed-app-only; install permission does not control discovery.
The owner requested automatic guidance when Broomm lacks APK-install permission.

Emulator installation previously relied on the system installer's missing-source
dialog. Install and Install APK now check permission before a transfer/picker,
request Broomm's per-source settings only when needed and resume the chosen action
after OS readback. Denial, timeout, closure and revoked handoff remain failures,
without a new pending default or false installation result. Granted permission
is reused; store handoffs are unchanged. Dart retains the installation workflow;
the Kotlin adapter only owns OS permission inspection/settings activity results.
The card wording now explicitly says **Emulator app not installed**.

Three regression cases cover grant/reuse/store bypass, denial/unknown status
without effects, and concurrent requests/failure/retry. The existing download
case now checks permission before transfer. Thirty-one focused Flutter cases,
analysis and Kotlin compilation pass locally (only the two existing updater
deprecation warnings). Native permission grant/denial and resumed installation
remain owner/device acceptance. See the [walkthrough](docs/android-installation-and-saves.md#install-flow).

The full local suite passes **572 tests** (one existing Linux-only skip); after
the final concurrent-store exclusion correction, analysis and all 31 affected
cases pass again. The fresh universal
[macOS preview](build/releases/Broomm-macOS-install-permission-preview.zip) is
24,325,544 bytes, SHA-256
`10526ac97dc71f676f1e4c13a3862c669d7bbe16d267ef76933f4491db2d8717`.
ZIP integrity and source/fresh-extraction deep/strict/all-architecture signatures
pass; all seven Mach-O files are universal. Version `0.1.16-dev` remains ad-hoc
signed, uses normal Application Support and has development self-updates disabled.
Logs and the source-bound packaging receipt are retained under
`.tool-cache/android-install-permission/`. No device permission was changed;
the Android 13 app-op inspection reports its default state. The new Android
permission flow still requires the updated PR APK and owner/native acceptance.

## Rooted Android: first implementation increment — 2026-11-05

The owner selected the Thor running Android and GBA for the first real save
round trip. Emulator Settings now provides **Inspect root access** for installed
emulators. A separate explicit request invokes a bounded read-only Android
adapter. It verifies the selected enabled package/launcher, signing/build
observation, current Android user, resolved private data-directory boundary,
UID/GID, mode and SELinux label. Reports are temporary; no root save connection,
privileged save write, lifecycle probe or successful cloud status is inferred.
Denial, unavailable access, cancellation, timeout and incomplete/mismatched
observations remain visible. Connected-folder sync is unchanged.

The adapter uses existing Android/JVM APIs and a fixed `su` inspection script;
no root library, manager, service, native payload or SDK pin is added. Workflows
and future save transactions remain in Dart. The [implementation record](docs/android-root-access.md)
includes the alternatives, commands, effects, verification and remaining
acceptance. ADB inspection found no connected device. The Thor's Android/root
manager, installed RetroArch/mGBA, save-path correspondence and real upload /
restore / in-game load still need native evidence before progressing to writes.

Local analysis is clean; **569 Flutter tests pass**, with one existing Linux-only
test skipped on macOS. The 37 focused Android cases include six new root-flow
regressions. Kotlin bridge compilation passes with the two existing updater
deprecation warnings; JVM process regressions and workflow/shell lint pass.
Android APK creation stops at **No Android SDK found**. No Android native root
execution, root-manager compatibility or save round trip is claimed.

The fresh [universal macOS preview](build/releases/Broomm-macOS-root-inspection-preview.zip)
is **24,325,487 bytes**, SHA-256
`b96d9c9f05d2cc7f472787c3a8f60440f87944591f4af933454bad2cb4bf25cc`.
Archive integrity and source/fresh-extraction deep/strict/all-architecture
signatures pass; all seven Mach-O files contain ARM64 and x86_64. Version
`0.1.15-dev` uses production Application Support, ad-hoc signing and disabled
development self-updates. It does not provide Android runtime acceptance.

The following checkpoint describes the preceding published release; it does
not include this working-tree increment.

**Checkpoint — 2026-11-05:** the owner deferred further Linux ARM64 work and
requested committing/pushing the current implementation to generate a release
build. [v0.1.15 is published](https://github.com/Broomm/broomm/releases/tag/v0.1.15)
from `79ef7e8`, with [every release gate and all five packages passing](https://github.com/Broomm/broomm/actions/runs/42053405473).
Preserve the implemented ARM64 packages, kernel confinement, launcher
input fix and emulator display-preference correction. Eden startup/shutdown and
Azahar dual-screen failures remain unresolved; no custom Eden build or added Qt
SDK is authorized. Physical melonDS window-width acceptance remains open.

The next milestone is **Android through a root-backed access route**, starting
with device/root capability and selected-emulator storage/lifecycle inspection,
then one real save round trip before expanding the roster. This is an adopted
direction, not implemented root support. Existing Android APK acquisition and
connected-folder workflows retain their stated scope and native-verification
gaps. No new root dependency or root-manager choice is made by this checkpoint.
See [the staged work and acceptance](docs/android-installation-and-saves.md#next-milestone-root-backed-storage-access).

Checkpoint validation on macOS: static analysis, formatting and workflow/shell
lint pass; the main Flutter suite passes 561 tests, with one Linux-only GIO
case skipped on this host. The two full-size save cases pass separately, and
the current macOS universal release app builds successfully. Logs
and JSON reports remain under `.tool-cache/checkpoint-*` and
`build/test-results/checkpoint-*`. Native Linux, Windows and Android release
checks remain separate CI results; these Mac checks do not establish Android
root support or resolve the deferred Thor gameplay failures.

The first [checkpoint release run](https://github.com/Broomm/broomm/actions/runs/42046704526)
builds all five targets successfully and passes macOS/Windows checks plus native
macOS acceptance. Publication is blocked by Linux checks: the pinned Devbox CLI
download failed with curl exit 22, and independently scheduled kernel/sanitizer
fixtures reached the new direct-namespace assertion. The optional backend's
probe had checked namespace creation without checking mount capabilities.
Ubuntu can permit the former while denying the latter. The fixture now probes
mount privilege independently, reports the unavailable operation, and retains
mandatory automatic confinement plus all save-boundary assertions. Any actual
production sandbox setup failure still fails with its backend/errno visible.
This changes test capability detection, not application confinement or emulator
behavior. The corrected hosted run above passes Linux kernel/sanitizer and
full-size save checks plus the other release gates. No
dependency pin, host security setting or acceptance threshold is changed.

The Thor gameplay investigation reproduces Eden/Smash and Azahar crashes
without Broomm's input bridge or process supervisor. Single-core Eden survives
bounded startup checks but still hangs in the owner's retry; it is not a
verified workaround. Azahar's failure follows its Vulkan
second-screen lease path. Neither has confirmed gameplay acceptance from this
investigation. The owner will configure fullscreen in the emulators. Broomm
now preserves the existing native fullscreen/windowed settings and removes
the unnecessary PlayStation `-nofullscreen` arguments. Forty affected Flutter
tests pass on each of macOS and native ARM64 Linux; analysis is clean. melonDS
window width still needs owner verification in the original launch flow.
See [the findings and limits](docs/thor-gameplay-investigation.md).

The owner's next Eden launch hung after scheduler assertions at 4.549 s,
with the process alive and consuming about three CPU cores. Runtime logs
confirmed NCE and multicore still enabled. The bridge stayed responsive but
native readiness/pause remained unknown; startup-failure feedback is still a
gap. This was a read-only diagnosis, with no live settings or progress changes.

The next owner retry confirms single-core NCE active for Captain Toad 1.4.2.
Native pause is acknowledged, then the first-launch/shutdown path stalls; the
owner also cannot close normally. Private Desktop Mode controls reproduce the
paused-exit problem. A native-Stop prototype and skipping controller
reconfiguration do not resolve it. No production change from those probes is
deployed. The owner approved the [project-local GDB plan](docs/eden-native-debugging.md)
after its initial approval-review rejection. Pinned GDB 15.1 is provisioned for
native ARM64 diagnosis, with its Devbox recipe and lock retained in the project.
The later Gaming Mode probe runs the actual `GameSession` workflow and reproduces
the paused-close timeout. GDB-started comparisons capture a native lock cycle:
the CPU thread waits for the process-list mutex owned by the shutdown thread,
while native close waits for that shutdown. Single-core JIT and two private
close-order prototypes still fail. The stock GCC build also crashes Smash;
an unpaused Captain Toad startup/close comparison succeeds, without gameplay
acceptance. An Eden process-list patch is prepared and passes application to the
pinned source, but is not compiled or deployed. On November 5 the owner declined
the custom Eden build and stopped that investigation; no additional Qt SDK or
modified Eden is authorized. The subsequent Azahar investigation is also
deferred at the checkpoint above. Nine temporary Eden
profile roots were removed; live bridges and all 291 current application build
inputs remain unchanged. See [native evidence and the rebuild proposal](docs/eden-native-debugging.md).

The Thor launcher performance investigation found synchronous evdev descriptor
closes blocking the UI thread during its two-second discovery scan. A measured
scan took 315.61 ms. Linux navigation now filters non-gamepads using sysfs and
owns discovery/polling/teardown in a dedicated Dart isolate. The same-device
Thor event-loop comparison reduced the maximum gap from 285.915 ms to 9.212 ms,
with no gaps above 33 ms after the fix. Native macOS/ARM64 input races and
seventeen related Flutter regressions pass; packaged Gaming Mode visual/input
acceptance remains owner testing. See [evidence and preview](docs/linux-input-performance.md).

The Thor setup investigation found that its Armada kernel disables Landlock;
both verified AppImages failed before extraction. A kernel-only user/mount
namespace fallback is implemented in the native write policy. Native ARM64
confinement, lifecycle, lock, daemon-drain, cancellation and SDL/control fixtures
pass on the Thor. The actual melonDS and Azahar AppImages extract successfully
in 0.37 s and 1.58 s, and both CLI startup checks exit normally with private write
protection active. Four fixed native components are installed in its closed
Broomm copy, with the originals backed up and all user data preserved. Full UI
setup, gameplay and physical dual-screen/controller acceptance remain owner
verification; a new GitHub release has not been published. The ARM64 standalone expansion adds Dolphin, Eden, DuckStation, ARMSX2,
RPCS3 and PPSSPP with architecture-specific packages, hook maps and inventories.
ARMSX2 selects its 4K/16K package using the running kernel page size. All six
install and resolve private profiles on Thor. Native GC/Wii/PS1/PS2/PSP
controller/pause/reconnect lifecycle checks and RPCS3 PUP import pass. Analysis
and 64 related Flutter regressions pass; PS3/Switch game and physical acceptance
remain separate. See [the ARM64 evidence](docs/linux-arm64-standalone-audit.md).

Eden's Ally investigation found two defects: interleaved stdout/stderr could
prevent cold initialization from observing the loaded title, and signed 64-bit
UUID formatting restored cloud progress under an invalid native account folder.
The parser now separates pipes; desktop/Android Eden encode account IDs directly
from bytes. Thirty-five targeted tests and analysis pass. The actual copied
Ally BROOMM snapshot restores with matching hashes under the corrected account.
An isolated native Eden/Smash launch reaches Pause and exits normally. The current
macOS preview is packaged and signature/archive verified. After the owner closed
Broomm, the live Ally folders were repaired under session/writer locks with
verified save readback and all displaced directories retained for recovery.
Linux deployment and subsequent Gaming Mode gameplay remain pending. See
[evidence and save-preserving repair](docs/eden-save-account-repair.md).

Linux ARM64 has separate managed melonDS and Azahar cards for
the upstream DRM-leasing builds. AppImage provenance, ARM64 SDL interop and
physical acceptance gaps are recorded in [Linux standalone integration](docs/linux-standalone.md#ayn-thor-dual-screen-feasibility).

The Linux ARM64 setup recipe selects the published Broomm RetroArch 1.22.2
frontend and 15 Libretro AArch64 cores. Linux executable/core checks use the
selected architecture, and the normal platform card installs its one requested
core. Frontend inventory and package digests match the upstream release
manifest. The audited nightly core snapshots contain AArch64 ELF libraries. The real
setup workflow downloaded the frontend and NES/SNES cores into disposable
storage and verified one shared frontend and separate core installations.
Armada OS launch, controller input, saves and Gamescope handoff still need the
Thor test. The six additional standalone ARM64 integrations and their acceptance scope are
recorded in the ARM64 audit above.

In Steam Gaming Mode on the Ally, the RetroArch bridge recorded the menu
request and hid its window while Steam still tracked the launcher process.
Gamescope sessions now gate input immediately but wait for Broomm to map
before hiding the emulator. Resuming waits for emulator visibility before
hiding Broomm. Native Linux window-gate checks and 31 targeted Flutter tests
passed on Linux and macOS. The owner confirmed the installed preview fixed
the overlay handoff in Gaming Mode on the Ally.

Linux defaults to an owner-only local credential store for RomM and
SteamGridDB. The keyring is opt-in and selected at process startup. The
local store does not call Secret Service. Existing keyring entries remain
in that backend. Sign in once after switching to a store with no credential.
Native Linux checks verified restore from a separate process, profile isolation,
file permissions, and symlink rejection. Nineteen targeted Flutter tests passed
on Linux. The portable preview was installed on the Ally at its existing Steam
shortcut path, with the previous bundle retained beside it. Gaming Mode restore
was reported working during the owner's initial Gaming Mode testing.

The desktop settings overlay opens on the existing R3 + Select chord and uses
launcher controller events to navigate between Controller pairing and Close
game. Start resumes with a single press. The first action receives focus once
the pause settles. Closing uses session shutdown and progress finalization.
The pairing screen retains its separate hold-Start behavior. Analysis and 33
targeted tests on each of macOS and Linux passed. The macOS archive and its
signature were verified after extraction. The Linux preview was staged on the
Ally and its runner dependencies resolved. The owner later confirmed the overlay worked in Gaming Mode with the
window handoff fix above.

The owner confirmed Broomm's window stacking on an ASUS ROG Ally X in Steam
Gaming Mode on Bazzite. KDE also showed the application launcher icon after
refreshing its index. On Bazzite 44.20260921.0 (Kinoite), Broomm 0.1.10 reported
failed credential publication while keeping the authenticated session. The
user bus reached KDE's `ksecretd`, which returned zero collections and no
default alias. That build needed a default unlocked wallet for persistent sign-in.
The GNOME comparison host had an unlocked default `login` collection and two
Broomm credential items despite no manual keyring setup reported by the owner.
The owner later created a KDE wallet and reported that Broomm sign-in storage worked.
See [the KDE setup and verification steps](README.md#run-broomm).

Gaming Mode recheck on the same Bazzite build found a Gamescope Wayland session
started through SDDM autologin. Broomm used the normal user bus. The Secret
Service name was absent and not activatable directly. The installed KDE
compatibility alias tried to start `ksecretd` without a display and Qt aborted.
Starting the existing daemon with Broomm's Gamescope XWayland display context
registered Secret Service and found the user's default wallet in a locked
state. The owner did not see the first native unlock dialog despite its X11
window being mapped. A second probe verified that KDE can attach the native
modal dialog to Broomm's X11 window, and the owner confirmed that it was still
invisible. The diagnostic daemon was in a different process group from Broomm.
The temporary daemon and its hidden prompt were stopped. The follow-up used a
temporary Steam launch wrapper inside Steam's reaper chain. It started KDE
Secret Service with the Broomm display environment, confirmed both processes
shared the Steam cgroup, and requested the unlock dialog with Broomm as its
parent. The original Steam launch options were restored and verified after
startup. The prompt timed out and the wallet remained locked. The transient
provider was stopped after the test. A shared Steam cgroup by itself did not
produce a successful unlock in this run.
On the repeat launch, the owner confirmed the Steam-scoped dialog was visible.
Focusing KDE's password field did not open Steam's keyboard automatically.
The owner opened the keyboard from Steam's side menu and unlocked the wallet.
The user bus then reported it unlocked, and Broomm logged profile activation.
The diagnostic prompt wait expired before that manual unlock. The provider
still accepted the password afterward. A candidate for automatic keyboard
display is SDL's Steam keyboard URI. The Ally follow-up found KDE's mapped
modal and submitted its bounds relative to the Broomm window. Steam logged
execution of the URI, KDE reported prompt completion and an unlocked wallet,
and Broomm logged profile activation. The owner confirmed the initial keyboard
covered the password field. A follow-up reserved a narrow region at the
bottom of the game viewport. The owner confirmed that this worked, KDE reported
the wallet unlocked, and Broomm logged profile activation. The original
shortcut options were restored after each launch. The diagnostic provider
lives with the launch wrapper. A session-wide unlock lifetime and placement
on other display configurations remain unverified.

Steam Windows CI fixture correction (2026-11-03): run 41692492424 failed one
Windows test because its expected path mixed separators, while the resolver
correctly returned a native canonical path. Build and analysis succeeded.
Construct the expected file with a native file URI; keep exact path/directory
assertions and exercise both native/mixed inputs, literal metacharacters, Unicode
and actual file readback. No production behavior, skips or timeouts change.
The 17 related Steam tests pass on macOS and Linux, along with analysis; native
Windows verification belongs to the correction's GitHub run. See the
[failure evidence](docs/add-to-steam.md#windows-ci-fixture-correction).

Add to Steam (2026-11-03): Settings → Application has a desktop-only,
controller-navigable CEF action for the running Broomm copy and approved bundled
Steam artwork. SDK-only direct loopback transport rejects discovery/handshake
redirects and remote/ambiguous contexts. Current-account receipts, a stable OS
lock and retained native creation jobs support retry without duplicate creation.
Fresh native detail subscriptions avoid Steam's stale unsubscribed cache; bounded
publication/readback handles its asynchronous overview updates. Actual Linux
Steam created app ID 3861238242 and verified all four artwork hashes, with the
same ID on repeat. Per the owner's explicit permission, enabled this test
installation's CEF flag and reopened Steam; the product action does neither.
All 539 applicable macOS and 470 Linux Flutter tests pass, as does analysis and
the Linux release/dependency audit. Mac/Windows Steam, visual artwork, physical
input and Big Picture/gamescope remain separate acceptance. See
[workflow, API audit and limits](docs/add-to-steam.md).
The owner reported the feature working on 2026-11-03, without specifying further
device/compositor coverage. Re-running either shortcut action refreshes its
managed entry; replacing the executable at the same path preserves both shortcuts.

Eden Linux reconnect correction (2026-11-03): the owner's Smash disconnect and
re-pair reached native Resume, then Eden exited 255 with a fatal Wayland
duplicate commit-timer timestamp. An isolated same-game comparison reproduces
that error on the first reconnect with actual Qt Wayland; XWayland passes three
replacement-source cycles, live logical input, one/two/one players and normal
shutdown. Eden alone now selects child `xcb` when DISPLAY is available, through
the shared Play/Open emulator boundary. The unforced production-policy native
check passes the same sequence. All 453 Linux and 522 macOS Flutter tests,
analysis and Linux release/dependency checks pass; physical/Bazzite and
Wayland-only acceptance remain separate. A new Linux preview preserves the
running owner app and its data. See [diagnosis, evidence and retest](docs/linux-eden-reconnect.md).
An extra fresh-storage/immediate-close Broomm smoke exposed a separate
Mesa/Flutter raster-thread SIGSEGV; its cause remains unresolved and it is not
included in the passing Eden/native checks. The earlier preview passed that
same close check. The core trace and limitation are recorded with the evidence.

Linux launcher and reconnect follow-up (2026-11-03): first committed/pushed the
previous working tree as `7a1cade`; all jobs and publication in release run
41576682638 succeeded before new work began. Settings now has Application on
every host and Linux-only Install to Launcher, generating a current-user XDG
Desktop Entry and existing icon for the current executable. Optional async GIO
custom-icon metadata targets only that executable. Generic controller recovery
races no longer let late resume/hide completions overwrite disconnect pairing,
and a disconnect supersedes a pending menu. Three held-boundary regressions fail
before the fix and pass after it. Native follow-up after SSH returned passes
450 Linux tests (22 existing platform skips), 519 macOS tests (one Linux-only
skip), analysis, GTK host compilation/recovery, Linux app build/dependency audit,
and isolated real-app startup/graceful close. GIO's early executable lookup
rejects percent paths before expansion; installation now fails before publication
with move/retry guidance, alongside Desktop Entry's prohibited equals sign.
The verified Linux preview is deployed to Downloads without replacing/stopping
the owner's existing app. GNOME visual checks remain owner acceptance.
The owner reports most Linux systems validated and working; Bazzite/Big
Picture is planned for November 4 and remains unverified. See
[implementation, sources, walkthrough and limits](docs/linux-launcher-and-reconnect.md).

The two preview entries immediately below describe their original November 2
delivery state. Their code is now included in the successful `7a1cade` CI run.

Setup throughput follow-up (2026-11-02, uncommitted preview): downloaded emulator
packages retain one archive checksum and structural/ELF checks; verified packages
no longer receive repeated per-file hash scans. Linux metadata, copying and
payload downloads run outside the UI isolate. RetroArch card/Home setup selects
one platform core with a shared frontend. Default firmware, save/state, artwork,
setup, APK and application-package downloads now share the background I/O
approach; custom transports keep their existing behavior. Eden's native NCA
staging reports bytes, and immutable add-on content uses durable metadata-bound
receipts after its first verification, preserving ownership and interrupted
publication checks. Saves remain outside that cache. A real Linux Smash test also corrected Eden's
cwd/user precedence, blocking Wayland recommendation and disabled native console
identity output; real title load, virtual port assignment and pause/resume pass in nine seconds.
All 508 macOS and 438 Linux tests pass (22 existing Linux skips); current preview
archives/signatures are verified, without committing or pushing.
See the
[measurements, verification and test-build walkthrough](docs/setup-throughput.md).


Linux setup corrections (2026-11-02, uncommitted preview): official rolling
Libretro core downloads no longer require historical archive sizes/hashes.
Explicit setup records actual library identities and selects them durably;
restarts retain those selections and states remain build-specific, including
SNES. Linux updates preserve executable TAR modes, and native installation uses
a private executable helper even when an older updater lost its mode. All nine
standalone installations pass with that broken source mode; fresh upstream
RetroArch setup and native ABI loading pass for all fifteen cores. Reset all
emulators removes managed installations/settings while retaining local progress,
console identities, installed game content and pending sync, as clarified by the
owner. All 496 macOS and 427 Linux tests pass (22 Linux platform skips), with
independent kernel/sanitizer/bundle checks. Preview packaging and owner testing
are separate from commits/CI publication. See [reproduction and walkthrough](docs/linux-setup-repair.md).

macOS CI controller-test correction (2026-11-02): the hosted native test read
shortcut events after fixed 50 ms run-loop waits and missed the first Y event.
Controller tests now acknowledge each native press/release and its queued main
work before exact assertions. A held callback-queue regression also covers
release and re-press; the two-controller Shift case retains its semantics.
All eleven native macOS tests pass locally, with no skips. Application behavior
and workflow requirements are unchanged. See the
[diagnosis, reproduction and verification scope](docs/github-releases.md#controller-callback-synchronization--2026-11-02).

Windows CI artwork fixture follow-up (2026-11-02): the macOS native job now
passes on GitHub. The rerun exposed an asynchronous fixture-cleanup race on
Windows: disposal started closing the download lock without awaiting it before
storage deletion. Cleanup now drains downloads/cloud work, with two production
lock reacquisition cases for live and disposing models. All 19 targeted macOS
artwork/version/queue cases pass; Windows verification remains the hosted job.
See the [shutdown record](docs/github-releases.md#windows-artwork-fixture-shutdown--2026-11-02).

Linux standalone milestone (2026-11-02): Linux x64 adds bundled Dolphin, RPCS3, Azahar, Ryubing, melonDS, DuckStation, PCSX2, PPSSPP and Eden recipes. Managed installation, private profiles, native SDL/Qt/debugger pause/input, independent Open emulator, firmware/add-on staging and existing progress adapters are wired. Nine production installations and two profiles each pass. Native controller/lifecycle checks cover GameCube/Wii (all four Wii layouts), 3DS, DS, PS1, PS2, PSP and PS3 homebrew; PUP/CIA imports pass. Kernel/process/protocol/ABI regressions and independent sanitizers pass. Switch runtime requires owner-configured keys/firmware or explicit permission for key export; physical input/gyro, Steam/gamescope, new standalone native cloud round trips and managed ARM64 remain separate acceptance. See [versions, native evidence, walkthrough and limitations](docs/linux-standalone.md).

Linux download throughput correction (2026-11-02): native Flutter HTTPS file
transfers were limited to about 2.3 MB/s on the UI isolate while the same raw
consumer reached 38–57 MB/s on a background Dart isolate. Default RomM game and
add-on transfers now use independent worker I/O with bounded progress, drained
cancellation and confirmed writer closure/exit. Uncertain writers retain private
stages and stable game/session locks until restart. The compiled small-file
benchmark improves from 2.26 to 11.85 MB/s over HTTPS; curl confirms 51.84 MB/s
over Tailscale and 75.03 MB/s over LAN HTTP. All 478 macOS and 410 applicable
Linux tests pass (21 existing Linux skips), with clean analysis/formatting.
Fresh macOS signatures/archive and Linux dependency/archive checks pass. No
network settings or owner data changed; full-game post-fix speed remains owner
acceptance. See [measurements, scope and builds](docs/linux-download-throughput.md).

Linux RetroArch milestone (2026-11-02): Linux x64 now selects its own bundled
setup recipe and installs the released frontend and fifteen pinned cores. Dart
ZIP staging, metadata-bound launch verification, private profiles, public SDL3
input interposition, pause/menu/disconnect, Landlock writes, GTK close/recovery
and independent no-game configuration are implemented. The owner selected
RetroArch first, then standalone emulators. Native Wayland/Mesen execution proves
input/remap, pause, native SRAM/state capture/upload/restore against the test
server, repeated launch, independent configuration and graceful real-writer
recovery. Kernel/ASan/UBSan and production recovery checks pass, including a
Btrfs device-identity correction. All 474 macOS and 406 applicable Linux Flutter
tests pass; 21 existing Linux platform skips remain. Physical/Steam/gamescope,
other-core gameplay, standalone Linux and Linux ARM64 acceptance remain separate.
The owner's running app/download/data were preserved; only project-contained
SDK caches and disposable fixtures were created. See [walkthrough and evidence](docs/linux-retroarch.md).

All-emulator pause follow-up (2026-11-02): the remaining desktop adapters now
preserve emulator-native pause/resume instead of enforcing Running during play.
The shared native transition covers Qt, native-core, F5 and Astris routes;
RetroArch uses explicit, identity-checked network transitions. Eden preserves
an existing pause while changing controller sockets. Real macOS checks pass
for RetroArch's released frontend with an original synthetic core, Ryubing and
Astris with Super Smash Bros. Ultimate, and the DuckStation regression. Twenty
targeted Flutter cases, three C scenarios with independent ASan/UBSan, analysis
and workflow lint pass. Other native gameplay and physical/other-host checks
remain pending; implementation and verification are distinguished in
[the adapter record](docs/emulator-pause.md).

DuckStation native pause correction (2026-11-02): Broomm's Sony pause bridge
no longer interprets every native pause during gameplay as a request to Resume.
An explicit gate release owns one pending resume; ordinary polling observes
native pause/resume while pairing/disconnect gates continue enforcing Pause.
The old behavior is reproduced with real DuckStation/Mega Man X4; the fixed
native run passes polling, active-route publication, native resume, explicit
gate release (including a quick menu transition) and disconnect cases in a copied private profile. Three C cases
pass normally and under ASan/UBSan, ten existing Flutter cases pass, analysis
and workflow lint pass. Universal bridges and a fresh macOS application are
built; exact archive/signature evidence and remaining native-host limits are in
[the correction record](docs/duckstation-pause.md).

Argosy Android workflow research (2026-10-30): the owner rejects the mandatory
manual save-folder flow as the desired experience. A deeper audit of Argosy
2.27.3 at `68f1368b61707f8c4ad001b89eb095a705a46143` distinguishes its
embedded LibretroDroid frontend/core downloader from external RetroArch, traces
APK installation, automatic save-path discovery, session/cloud sync and RomM
BIOS distribution, and identifies vendor-specific storage access limits.
External-app discovery is proposed within the current design; an embedded
frontend is an unadopted architecture option. No app behavior, dependency,
emulator or production progress changed; native Android execution was not
performed. See [findings and tradeoffs](docs/argosy-android-workflow.md) and the
[pinned evidence inventory](docs/argosy-android-workflow.json).

MMJ shared-folder saves (2026-10-30): Android MMJ now connects the shared
`citra-emu` tree with persistent read/write access, explicit private-storage
warnings and per-profile private saves. SessionLease and a durable copy/restore
journal surround native title-data/extdata swaps; standalone saves and states
are restored after capture. The normal BROOMM history/import/backup/offline
contracts apply to ordinary saves. Denied grants, outside writes and interrupted
publication preserve copies; an explicit keep-folder resolution can finish an
uncertain session without further upload. MMJ states and CIA installation are
still missing. All 440 main Flutter tests and two separately scheduled full-size
save tests pass, including five new MMJ save/recovery cases. Static analysis and
Android Kotlin compilation pass. These remain distinct from unexecuted Android
device acceptance. See [setup and recovery](docs/mmj-shared-saves.md).

Measured Windows full-card test budget (2026-10-30): after the native updater
fixture passes independently, Windows reports a separate PS2 cloud round-trip
timeout. Its retained phase trace completes all five workflow phases in 51.182
seconds, exceeding the generic 30-second test limit. Only that full-card
integration case now has a 90-second budget; native card sizes, readbacks,
assertions and worker-drain teardown are retained. See
[timings and scope](docs/github-releases.md).

Windows updater test supervision (2026-10-30): the native PowerShell cancellation
fixture runs in its own mandatory Windows step, separate from parallel Flutter
tests, with unchanged eight-second deadlines. It reports early process exit,
bounded output and the installer log instead of only a missing checkpoint.
Portable regressions cover early exit and live-writer readiness. No application
updater behavior changes; native Windows execution is checked by CI. See
[reproduction and scope](docs/application-updates.md#windows-native-cancellation-fixture-2026-10-30).

Installed Switch launch correction (2026-10-30): the package-selection preflight
now reads the installed receipt and existing native package checkpoint instead
of requiring the lightweight saved game metadata to contain a downloadable RomM
manifest. Existing generations remain usable by both profiles without a remote
manifest request. A missing generation resolves real remote file identities
before its first import; failed, incomplete or mismatched responses retain the
installation. Legacy update/DLC folders are excluded from base-game selection
even without API category fields. See [reproduction and verification](docs/switch-installed-launch.md).

Astris/Citra MMJ follow-up (2026-10-29): Astris 1.0.32+2398e7c80 adds managed macOS 15+ ARM64 Switch launch, private preferences/accounts, native controller/pause interop, ordinary-save ZIPs and independent update/DLC ownership. Native checks cover live remap/menu/disconnect, shutdown, save export/import and package publication/reuse/removal. At that milestone Android Citra MMJ added package/activity discovery, installation and GamePath launch, with progress/CIA adapters missing. The 2026-10-30 shared-folder follow-up above implements ordinary saves without relying on MMJ's incomplete private-storage provider. Physical Astris input/gyro, Android runtime and other-host acceptance remain separate. Defaults are configured-only and successful setup selects the newly installed emulator. See [walkthrough and evidence](docs/astris-and-citra-mmj.md).

Updater preparation correction (2026-10-29): the production 0.1.2 → 0.1.3
failure is reproduced with a progress callback holding a native receive port.
Both worker closures unintentionally captured the UI callback. Dedicated
path-only worker scopes now keep UI/logging resources on their owning isolate;
checksums, extraction, locks, cancellation and publication checks remain intact.
Unexpected failures identify their phase and log an error type/OS code without
stringifying sensitive callback graphs or HTTP URLs. All **424 Flutter tests**
pass (422 ordinary plus two separately scheduled full-size save cases), including
three new regressions and native macOS replacement/rollback fixtures. Real public
0.1.3 preparation passes with the original failing callback and in compiled
ARM64 and Intel/Rosetta runtimes. The compiled probes stop before production
replacement. Existing broken updaters need one manual app replacement; the local
0.1.3 recovery build enables later GitHub updates. Other native hosts and the
owner's production upgrade remain separate acceptance. See
[recovery, evidence and commands](docs/application-updates.md#update-preparation-correction-2026-10-29).

Automatic core delivery and running macOS icon (2026-10-27): all twelve frontends and all fifteen RetroArch cores now have bundled HTTPS recipes; normal setup needs no companion pack or JSON import. Seven available official Libretro core builds replace the old offline dependencies, with retained legacy fingerprints and explicit-setup-only selection. Ordinary saves remain shared across core upgrades; incompatible states have physically separate frontend/core-hash folders and exact-build cloud identities. The 55-case targeted suite, native fresh setup/restart and ABI checks, thirteen game/state sessions, BIOS-core save checks and four additional cartridge/arcade native-data round trips pass. All ten macOS native app tests pass, including restoring the bundled infinity icon after a placeholder and retaining the current icon when its resource is absent. Startup assigns the icon directly; the owner's original Dock/cache trigger remains unproven and actual Dock appearance needs owner confirmation. See [walkthrough, versions and scoped evidence](docs/retroarch-public-cores.md).

RetroArch release adoption (2026-10-27): the bundled macOS ARM64 recipe now downloads Broomm/retroarch v0.1.0 with its exact ZIP, executable, SDL3 and complete 29-file inventory. All five published desktop artifacts/manifests were verified; this does not expand the existing managed core/bridge host boundary. Previous selected frontends and old setup packs retain their exact identities, profile paths and state naming until explicit setup. The release uses private native state paths after a real `-S` regression was diagnosed and corrected. The 52-case targeted suite, native public delivery/restart, thirteen supplied game/state checks, four BIOS-based platform routes (Lynx, Saturn, 3DO and Dreamcast) and SNES pairing/pause/remap pass, exercising all fifteen current cores. Seven remaining offline cores have an updated companion pack; eight retain direct tested downloads. The fresh macOS app/archive and extracted signatures pass. See [current distribution and host limits](docs/retroarch-distribution.md) and [exact fingerprints, retained failures and artifacts](docs/retroarch-release-adoption.json).

Launch/quit recovery (2026-10-27): repeated whole-ROM hashing has been removed from Ryubing/Eden save discovery and launch. Native title observations bind to the installed publication's server/ROM/file identity and file metadata; old checksum records and saves stay intact. The owner's 14.64 GB Smash installation now takes 11.113 ms for read-only receipt/identity lookup, with no ROM payload read. Explicit save actions cancel/drain idle sync instead of refusing it as a game. Launch cancellation includes cold-start children and retains the lease until writer exit. A pinned Ryubing early-quit race now waits for confirmed native pause before close. Quit acknowledges immediately, displays shutdown phases and offers an explicit exit if work stalls; macOS also has a no-Dart-response fallback and verified surviving-writer recovery. **405 Flutter tests**, **8 native macOS XCTest checks**, the real Ryubing initialize/reopen/cancel fixture and AppKit process-identity checks pass. The current macOS ZIP passes archive and extracted signature checks. Owner gameplay and Linux/Windows/Android native recovery acceptance remain separate. See [details and retained failures](docs/session-recovery.md) and [source/build evidence](docs/session-recovery.json).

Saturn verification (2026-10-23): both owner-provided regional BIOS files now pass checksum verification and real RomM automatic provisioning/reuse in a disposable profile. The Legend of Oasis boots through native pairing, pause/live remap and normal exit. Internal backup RAM, backup cartridge and console settings pass cloud-fixture export/upload-readback/restore; native state creation/loading and exact-build snapshot restore pass. The [Saturn record](docs/saturn-verification.md) separates this macOS automated evidence from physical gameplay, cross-device and other-host acceptance. No application or bridge change was needed. The current matrix now has 17 of 18 additional RetroArch routes natively checked, with 14 ordinary native-data round trips plus the separately seeded 32X case; Jaguar CD remains owner-deferred. Earlier dated counts below are historical.

Pairing-format correction (2026-10-23): the main RomM client now accepts the actual eight-character alphanumeric API key pairing code, including lowercase/hyphenated input, and the onboarding hint uses the correct terminology. The tagged 5.4.0 generator/exchange supersedes the prose documentation's numeric example. Three new HTTP regression cases cover accepted forms, malformed input without network effects and rejected/expired exchange without retry. The HTTP/onboarding suites pass 22 tests and targeted analysis passes; [exact evidence](docs/pairing-code-format.json) records the source hashes and remaining native acceptance. The matching Switch keyboard/build/deployment evidence stays in the sibling companion; its version 0.2.2 was transferred with hash readback. No main desktop release binary was rebuilt for this correction.


Current expansion (2026-10-23): the [colored platform matrix](docs/platform-support-matrix.md) records **25 launch/ordinary-save adapters**, including 18 new RetroArch routes/14 pinned cores, plus Wii and Switch native package workflows and missing Switch firmware provisioning. Thirteen new cartridge/arcade routes have native game/state checks and six have native ordinary-save export/import checks; five optical/BIOS routes still need native media validation. PS1/PS2/PSP remain pending; PS4 has no built-in emulator while retaining ordinary browsing/downloads. The runtime pack remains macOS arm64. Earlier dated milestone counts below are historical. See [the expansion record](docs/retroarch-wii-switch.md) for exact verification and remaining scope.

The native Nintendo Switch companion has its own [implementation record](../broomm-nsw/IMPLEMENTATION.md), source, evidence and Devbox environment in the sibling `broomm-nsw` project. This document tracks the main Broomm application and shared integrations, including Switch emulation; console-specific implementation status belongs to the companion.

Latest inventory: the authenticated [platform matrix](docs/platform-support-matrix.md) records 29 platforms / 7,660 ROM records, seven implemented macOS platform integrations, 22 missing/research integrations and the package/cloud-save/state gaps. It proposes candidates without installing them. The [RPCS3 installer exit correction](docs/rpcs3-installer-exit.md) prevents the known post-install SIGABRT notification through the child-only native guard while preserving strict completion/output verification and real failures. Both real ARM/Intel package imports, guarded firmware import/reuse, five native guard checks and all 257 Flutter tests pass; final build evidence is in its JSON.

Current follow-up: [automatic first sync and PS3 recovery](docs/cloud-initialization-and-ps3-recovery.md) initializes installed-game cloud history automatically, exposes a locked download checkpoint read-only with Refresh, and replaces PS3 whole-directory ownership with journaled package-file ownership. Existing game-created data and replaced originals survive installation/removal. All 257 Flutter tests and two copied-data/queue integration checks pass. Source/release fingerprints and remaining native/owner checks are recorded there and in its JSON. The preceding [downloads and status](docs/downloads-and-status.md) milestone retains its scoped 247-test/native-loading evidence. L2 Shift / R2 Enter and the cancellation of window capture remain unchanged. Earlier milestones below are historical.

Updated 2026-10-22. The application implements queued RomM downloads, persistent Home entries, managed setup for six emulator engines with seven pinned macOS choices (including melonDS and alternate Intel RPCS3 through Rosetta), and Home → loading → controller pairing → gameplay. The [library/progress follow-up](docs/library-and-progress-followup.md) adds early artwork selection, a Downloads screen, the docked keyboard, PS3 firmware acquisition and PS3 add-on reconciliation. The current [save-history/ISO correction](docs/slotted-saves-and-ps3-iso.md) appends native timestamped versions in `BROOMM`, preserves earlier saves, keeps explicit imports/backups and supports encrypted PS3 ISO/adjacent-key boot. Guarded restore, offline retries and conflicts remain. Ordinary progress adapters cover SNES, GameCube, Wii, 3DS, PS3, DS and Switch; individual format/native-host limits remain explicit. Authenticated DS save transfer/readback is verified; real PS3 PKG import, physical-controller and cross-device gameplay acceptance remain pending. See [README.md](README.md) for testing steps and the current Mac build.

Read [PROJECT.md](PROJECT.md) for requirements, the [decision record](docs/decisions.md) for settled choices, and [architecture](docs/architecture.md) for the proposed implementation. Remaining implementation details live in [open questions](docs/open-questions.md); the initial questionnaire has been answered.

## RomM application slice

The default entry point now opens server setup, server-scoped profiles, a three-app console Home, Broomm settings and the RomM Game Store. Settings persist reduced motion, artwork visibility and page size. RomM 5.4.0 integration includes server validation, password OAuth with read scopes and managed-save write access (read-only roles can still browse), client token/pair-code login, account identity, platforms, paginated/searchable ROMs, details and authenticated same-server artwork. Reusable refresh/client tokens are saved per server/account through direct native secure-store adapters; passwords and OAuth access tokens are never persisted. Explicit profile selection restores authentication, switching retains it, and device sign-out removes it. Native macOS evidence and the unverified other-host adapters are distinguished in [the follow-up record](docs/remembered-signins-and-platform-settings.md).

Server/profile metadata uses locked atomic publication and readback. Context/query generations reject stale requests after searching or signing out. The Store uses real server data and reports unavailable catalogues. Verified downloads and receipts publish together and appear on Home, shared per saved server across eligible profiles. Home plays the supported formats through managed emulator copies and profile-private data. Emulator Settings imports the tested local builds through setup JSON. Named collection filters remain pending; the managed-save slice is recorded below; no Go code was imported.

Controller navigation uses geometric Flutter focus, native macOS GameController events, Dart Linux evdev/Windows XInput adapters and Android gamepad interop. Pointer/touch activates inline editing; keyboard focus requires Enter to edit and Escape returns to navigation on the same field. Controller activation opens the virtual keyboard. Emulator Settings uses spatial arrows/controller directions and ordered Tab traversal through expanded confirmation controls. Scroll reveal includes full cards, labels and view edges, and newer focus stops obsolete scroll animations. Mouse hover does not take focus. Only macOS compilation/native tests and Flutter action-channel/layout tests are verified here; Linux input permissions, Steam/gamescope, Windows and Android behavior require native execution. The previous local-ROM controller lab remains reachable through Broomm settings, or the explicit prototype run command. See [the slice walkthrough and scoped evidence](docs/romm-application.md) and [download/input details](docs/romm-downloads-and-input.md).

## Current evidence

The Intel RPCS3 follow-up adds a separate macOS PS3 choice/default, shared profile-owned PS3 data, isolated Intel compilation caches and universal C bridges. **234 Flutter tests pass** and static analysis is clean. Two real Rosetta launches of the supplied encrypted PS3 ISO pass injected pairing, pause/resume, live remap and normal close (312.316 s fresh cache; 183.080 s repeated launch). This is not a compatibility/performance comparison. Firmware and ARM-regression checks and final release evidence are recorded in [the scoped follow-up](docs/rpcs3-intel.md). [Flutter capture-library research](docs/flutter-window-capture.md) identifies a common WebRTC API plus native runtime, process-identity and gamescope limitations; no capture dependency or preview is implemented. Physical gameplay and other native hosts remain separate acceptance.

Latest keyboard/cache follow-up: **231 Flutter tests pass**, plus **14 focused widget/render checks** for the final shortcut badges. Two native macOS GameController snapshot tests pass for shortcut button callbacks and multi-controller held Shift. A separate native two-boot RPCS3 check preserves 204 PPU objects and 155 shader files on each launch, while measuring about 187 seconds to readiness; a stack sample and pinned renderer source identify repeated MoltenVK pipeline conversion. No graphics/cache setting or emulator binary was changed. Live loading-window capture remains a researched proposal with platform-specific permission/compositor requirements. See [the follow-up](docs/loading-preview-and-keyboard.md) and its JSON for scoped evidence and release metadata. Physical controller and other native-host acceptance remain pending.

The preceding save-history/ISO milestone passed **228 Flutter tests** with clean static analysis. Native macOS checks validated encrypted RPCS3 ISO/key boot through pause/pair/resume/exit, copied native save exports including Pokémon Ranger, real RetroArch writer/finalization, and Switch committed save/ZIP round trips. Authenticated RomM 5.4 DS transfer created a timestamped raw 262,144-byte `.sav` in BROOMM and verified readback without changing previous assets. Its release evidence is recorded in [the correction record](docs/slotted-saves-and-ps3-iso.md) and its JSON. Real PS3 PKG import, physical-controller play, cross-device gameplay and other native hosts remain unverified.

The preceding library/progress milestone passed 217 Flutter tests, offscreen desktop/compact renders and native macOS checks for melonDS, the six existing emulator session flows, RPCS3 firmware import/reuse, installer/orphan writer exclusion and Switch restore/native consumption. Its release/signature evidence remains in [the scoped historical record](docs/library-and-progress-followup.md). Entries below describe their own milestones.

| Item | Status |
| --- | --- |
| Product specification and general engineering guidance | Updated with confirmed owner decisions |
| PGCS reference audit | Source inspection only; no PGCS application-code import or Go helper |
| Teddy server/profile flow | Source and test inspection documented; no Teddy runtime/visual check |
| Initial emulator inventory | Thirteen concrete executable adapters and the supplied RetroArch core set identified |
| RomM baseline | 5.4.0 selected and confirmed by the public instance schema retrieved through the supplied HTTP proxy; authenticated DS native save upload/readback is now verified separately |
| Controller injection / desktop overlays | C bridge built and exercised in five private macOS emulator copies with supplied ROMs; see the [measured findings](docs/research/injection-validation.md). Renderer/fullscreen/physical-controller and Linux/Steam acceptance remain separate |
| Flutter app / Devbox bootstrap | Flutter 3.47.0/Dart 3.13.0 and pub lockfile; onboarding, Home/Store downloads, preferences and explicit text editing. Current checks are recorded in the [sign-in/platform follow-up](docs/remembered-signins-and-platform-settings.md); the earlier managed milestone passed 94 tests and all six native ROM sessions. The local controller lab remains; other native hosts remain pending |
| Managed setup and Home launch | Twelve pinned macOS choices and all fifteen selected RetroArch cores download through bundled HTTPS recipes, including RetroArch from Broomm/retroarch v0.1.0 and seven refreshed official cores. Normal setup requires no external pack or import. Prior recognized frontend/core installations remain usable until explicit setup. Ordinary saves are retained and incompatible states are physically isolated. Private extraction, cancellation, verified publication/reuse and inline review work without a checkout root. Other native desktop core/bridge packages, arbitrary newer builds and system-executable selection remain pending; see [delivery evidence](docs/managed-setup-downloads.md) |
| Host coverage | macOS/Linux first; Windows later; Android uses simple external-app handoff |
| Remembered sign-ins and platform settings | Per-profile secure refresh/client credentials, Enter/Escape editing, all-server-platform sections, default routing, inline setup and shared managed uninstall with retained profile data; see [scoped evidence](docs/remembered-signins-and-platform-settings.md) |
| Keyboard/controller navigation and motion | Animated full-card/field reveal, first/last-row scroll edges, spatial emulator actions with ordered Tab traversal, Home/header return paths, indexed lazy catalogue traversal, retained modal focus, scrollable descriptions and compact session screens, reduced motion and held-key activation guards; see [current checks and owner walkthrough](docs/navigation-and-motion.md) |

The 2026-10-22 cloud-save slice passed 201 checks in the final complete Dart/Flutter plus two native-check run. Separate targeted checks cover save conflict ancestry, state provenance/core identity and controller routing during pre-launch/finalization. macOS native file round trips and a real RetroArch writer/finalization check use isolated data and a fixture server; owner-authenticated transfers and cross-device gameplay remain separate acceptance. See [the machine-readable source hashes, commands and release evidence](docs/cloud-saves.json).

## Owner-requested controller prototype

This bounded prototype deliberately precedes server/Home/Store implementation. Flutter provides a static ROM library, player cards, joining/leaving/reordering, both face-button swaps and the same pairing widget before and during play. C bridges expose four virtual logical ports inside the selected emulator's existing SDL runtime, sample mapped physical gamepads there, neutralize logical input during menus, and detect R3+Select and assigned-device removal. A released-button barrier avoids forwarding the confirmation press into gameplay. Reconnecting devices must join again with their new session identity.

Dart owns assignments, concrete emulator configuration, private process launch and native acknowledgements. A parent coordinator lock and a native emulator-owned writer lock enforce one game, including after launcher exit. Each emulator gets persistent prototype-owned data; the original emulator installations and ROMs are write-protected. The app bundles both native dylibs. The fixture provisioning step is explicit, not an automatic emulator updater or setup.json implementation. Android's external-app-only requirement is preserved: no native Android bridge is introduced.

The overlay is an external Flutter window aligned over the game, using macOS window presentation. The owner clarified that Steam → Broomm → emulator in gamescope-based Game Mode is a central acceptance path. The [preliminary window/compositor review](docs/research/controllers-and-overlays.md#steam-big-picture-and-gamescope-preliminary-window-review) finds ordinary window stacking insufficient as an assumption; a gamescope-aware surface or drawing inside the game presentation needs a native experiment. No Linux/Steam acceptance is claimed. It is not proof of GPU interception or acceptance in all fullscreen Spaces. Physical pads, Steam, handhelds, real port gameplay, rumble, motion feel/calibration, Linux and later hosts remain separate verification. The native smoke suite uses real supplied games with in-process synthetic SDL sources; see its machine-readable record and [walkthrough](README.md). Do not conflate that with owner-performed input/visual verification.

Initial prototype testing caught and corrected premature Azahar pause acknowledgement before EmuThread creation, Ryubing title readiness assumptions, virtual-trigger range conversion, stale asynchronous bridge reads after exit, card layout overflow, and shutdown of paused emulators. Failed synthetic fixture shutdowns were cleaned up separately; the interactive supervisor has no force-kill path. A supported native pause acknowledgement is required before play/overlay confirmation. The final macOS suite passes all six supplied ROMs, including held-confirmation neutrality, child lock ownership and clean exits; eight Dart/Flutter tests pass. Exact source/build fingerprints and scoped evidence are in [prototype validation](docs/research/prototype-validation.json).

The owner's subsequent physical/visual testing found missing decorations, resizing, one Broomm renderer crash, RetroArch relaunch input failure, Switch pause failure, and four phantom GameCube controllers. Those observations exposed gaps in the original synthetic suite. The [reliability follow-up](docs/research/prototype-reliability.md) records the fixes and [new regression evidence](docs/research/prototype-regressions.json) separately. Window presentation preserves decorations/user frame; macOS uses Skia Metal to avoid the observed pinned-SDK Impeller crash. Session lifetime checks protect return from normal/error exit and stale asynchronous work. Command publication is serialized and a lost bridge invalidates pause knowledge while retaining its writer. RetroArch logical player indices and Dolphin console socket counts are now verified at the emulator boundary. Ryubing foreground activation and a scoped SDL2 GCController backend workaround address resume and a diagnosed relaunch deadlock with the attached Switch Pro controllers. That reliability milestone passed 16 Dart/Flutter tests; two native window tests pass, including 30 hide/show cycles. All six ROMs pass the updated foreground-handoff suite, and the controlled bridge outage recovers while retaining the emulator-owned writer lock. This does not complete physical gameplay, fullscreen or Steam/Linux acceptance.

The subsequent pairing redesign adds large vector controller testers, six-axis snapshots, family-based initial face orientation, L1+R1 join/Wii type, independent L3+R1 face switching, one-second Start/Select holds, progressive player cards and controller-driven scrolling. Face changes now swap both pairs. Wii uses emulated Wii remotes rather than Brawl's GameCube compatibility: Dart publishes private mode configuration; the pinned C bridge reloads Dolphin while paused and verifies selected extension/orientation before releasing input. Native testing covers all eight variants and mixed Nunchuk/Classic players in one Brawl session. An intermittent Azahar startup lock inversion was sampled and corrected by deferring only its controller event watchers, with bounded continuous-input coalescing and a deterministic nested-callback check. Protocol 3 prevents an old bridge from being accepted by the new app. Current automated Flutter checks pass 42 tests; see [pairing behavior and measured evidence](docs/research/controller-pairing-testers.md). Physical gamepad feel, actual Classic game actions, Linux/Steam and later hosts remain acceptance work.

The [responsiveness/loading follow-up](docs/research/pairing-responsiveness.md) adds a distinct initial loading state, protocol 4 input-discovery readiness and an Azahar loading-screen boundary before pairing appears. Motion bars hide when gyro is inactive. Emulator output decoding/rotation moves to a bounded in-process logging isolate; mapped-value repaint checks and cached native executable symbols reduce measured work. The current analyzer and 49 Flutter tests pass. Controlled debug measurements reduce four-card build p95 from about 23 to 12 ms and a 2 MiB log-burst event-loop stall from about 362 to 24 ms; higher observed RSS and unverified owner responsiveness remain explicit. See that follow-up for exact native results and source fingerprints; earlier milestones above retain their historical counts.

## Stage 0 — Establish the Dart/Flutter environment

1. Create a pinned Devbox environment, Flutter project, package lockfile and platform-aware doctor/build/check scripts. Project dependencies are managed; pre-provisioned Xcode/Apple SDK and Windows SDK/C++ hosts are approved. No OS package installation.
2. Keep provisioning, profile/server management, session coordination and synchronization in Dart. PGCS supplies researched behavior and emulator knowledge only. Optional C injection bridges ship precompiled after validation; do not add Go code or a helper service.
3. Establish macOS/Linux native build/check jobs first. Keep later Windows/Android targets visible without treating their missing hands-on acceptance as an unresolved priority decision.
4. Use the [captured RomM 5.4.0 instance schema](docs/reference/README.md) and capture sanitized authenticated contract fixtures when implementing the client. Public schema retrieval is complete; HTTPS transport and authenticated runtime behavior remain to be verified.

Acceptance: a fresh project environment resolves reproducibly; format/analyze/tests and available native builds run through documented scripts; packaged native dependencies load. Record exact OS/CPU/SDK versions and unavailable checks. New package choices still require concrete tradeoff review; Flutter/Dart and the no-Go boundary are already selected.

## Stage 1 — Server-first profiles and the controller-first shell

Implement [server → known profiles → Home](docs/profiles-and-servers.md), following Teddy's explicit activation, filtered profile tiles and focus behavior. Store servers independently of profiles, keep one active server/account, and reset clients/navigation safely during switching. Build Home with Broomm settings, Game Store and Emulator Settings before game installation, following the owner's updated three-app requirement.

Acceptance: two saved servers with overlapping account IDs/names stay separate; servers with no profiles survive restart; startup does not authenticate before explicit profile choice; busy/error/modal focus paths work with controller, keyboard and pointer/touch. Switches preserve queued progress and reject stale results. Fixture catalogue data must be clearly identified.

## Stage 2 — RomM catalogue and shared game installation

Implemented first download slice: authenticated per-file streaming, portable path checks, size/raw CRC verification, private staging, OS-locked publication, Home records, permissions and cancellation. Archives remain raw; decompressed hashes are not container checksums. Retries restart transfers. Stage 3 now launches supported installed formats; [the artwork follow-up](docs/home-artwork-and-deletion.md) adds chosen local artwork and confirmed game deletion with retained progress. Owner-server transfers, native Linux/Windows/Android execution, full offline activation and repair remain pending; the managed-save slice below adds progress synchronization. See [download evidence](docs/romm-downloads-and-input.md).

The 3DS add-on follow-up implements repair for its own tracked native title content; general base-game repair remains pending. A failed add-on import leaves the completed base installation available, with a visible error and manual retry.

Implement the selected 5.4.0 auth/account/capability contract, catalogue pagination/search/details and content download. Install shared ROM/game payloads transactionally, with progress/cancel/retry/receipts and committed Home entries. Add a second account and server early to prove private progress and correct ownership.

Acceptance: browse a real authorized catalogue; install a complete game; cancel or interrupt without exposing a playable partial entry; reuse shared payload for another eligible profile without sharing its saves/states. Network failures retain the installed library. Cover traversal/collisions, partial HTTP responses, integrity and disk-full errors.

## Stage 3 — Managed setup and one complete desktop game session

**2026-10-27 delivery follow-up:** bundled schema-2 recipes no longer depend on
`BROOMM_PROJECT_ROOT`. All twelve pinned macOS choices download reviewed HTTPS
archives. Dolphin's official 2609 DMG now reproduces all 2,667 files and nine
links through a fixed Dart signing recipe. An archived Ryubing 1.3.3 ZIP matches
all 16 tested files; only its empty root Finder icon marker is ignored. RetroArch
uses the published Broomm SDL3 frontend and all fifteen cores now download;
seven have newly validated official builds and eight retain their library hashes.
Normal setup requires no companion pack or import. First installs,
private archive extraction, checksum/inventory checks, bounded cancellation,
receipt publication and verified reuse work through the existing inline cards.
Version-1 local imports remain supported; capture tools and native gameplay
fixtures now explicitly use `tool/setup-development.json`.

The earlier delivery milestone passed its analyzer and **392 Flutter tests**.
Two full fresh native installs passed for its **12 choices and 14 additional cores**
with `project: null`. Current core-refresh checks are recorded separately in
[the public-core evidence](docs/retroarch-public-cores.json).
A subsequent GitHub Azahar stream disconnect retained four completed choices and
discarded the partial transfer; safe diagnostic regressions were added, and the
same fixture explicitly resumed to all 12 choices/14 cores with default-manifest
reuse passing. The source-replacement check then freshly downloaded Dolphin,
Ryubing and eight unchanged cores, installed all 14 additional cores, accepted
the earlier complete pack and verified restart/reuse after removing its private
source directory. It passed in 47 seconds with exact full inventories. Logs
preserve the original redacted failure. These checks verify
delivery and existing binary identities, rather than new gameplay/input or other
host acceptance. See [recipes, source evidence and limitations](docs/managed-setup-downloads.md)
and [machine-readable results](docs/managed-setup-downloads.json).

The fresh [macOS build](build/releases/Broomm-macOS-setup-fixes.zip) is
**20,346,293 bytes**, SHA-256
`1233d40d8883bb5c39b1cdb29c9417eb53692ae40cb619908861322f0ca39934`.
The application and three existing bridges contain ARM64/x86-64; ZIP integrity,
the bundled manifest hash and strict/deep signatures pass before and after fresh
extraction. This ad-hoc local development build uses the normal
`~/Library/Application Support/Broomm` folder, with self-updates disabled. The
[companion setup pack](build/releases/Broomm-setup-macOS-arm64.zip) is
**148,651,975 bytes**, SHA-256
`80712dce859de91ea7bf7c05b22931e1d734c81502c3d4ff87116e8388737654`.
It contains no firmware, keys, games, profile settings or progress. README.md
documents first setup, explicit effects, output folders and cleanup. No owner
data migration, OS dependency installation or GitHub publication was performed.

Implement the [setup JSON workflow](docs/emulator-support.md#setup-json-contract) in Dart. Generate the install/update plan and execute only when the user starts it. All configuration is Broomm-local, even for a selected system executable. No automatic updates or mutation of external installations.

Take one macOS/Linux combination from the selected roster through provisioning/resources, private configuration, controller assignment, app-wide single-game locking, process supervision and save/state manifests. The first slice is a sequencing choice within the full initial roster, not a reduction of scope. Expand one verified integration at a time.

Acceptance:

- Owner launches a game using the expected player port; a second launch from the same or another Broomm process is refused while it runs.
- Two profiles use the same ROM bytes but separate saves/states. External/default-user emulator settings and files remain untouched.
- A new setup file updates only the requested managed artifacts after user initiation; failure retains the prior installation and settings. Manual executable changes are detected without silently reverting them.
- Confirmed game exit, failed launch and cancellation all preserve local progress and correct session ownership. A wrapper exiting is not mistaken for the real writer stopping.

## Stage 4 — Offline recovery and cross-device progress

The first [cloud-save slice](docs/cloud-saves.md) implements acknowledged baseline B, local snapshot L and current managed remote R under the originating server/account. Only the exact `broomm`/`Broomm` save without a slot is an automatic target. Offline progress is checkpointed locally; R = B permits upload of L, divergent changes require a choice, equal contents acknowledge without another upload, and a remote-only descendant is restored before play. Commit ancestry detects competing Broomm writers after a last-writer-wins server race. This does not make RomM 5.4's upload endpoint an atomic compare-and-swap. Explicit source imports and independent named backups are available from Home Options. Native gameplay/cross-host and authenticated server acceptance below remain outstanding; unit/HTTP and isolated file round trips do not establish them.

Acceptance: save round trip between macOS/Linux devices in both directions; matched-build state round trip; incompatible state retention; offline progress with unchanged remote uploads automatically; remote progress from another device creates an explicit conflict. Cover lost upload acknowledgement, a remote write after comparison, revoked login, disk-full, damaged local recovery and switching away with a queued upload. Inactive servers/accounts remain paused until selected and never borrow the active account's token.

## Stage 5 — Tight desktop input and settings integration

The owner prioritized RetroArch, Dolphin, RPCS3, Azahar and Ryubing. The [first native experiment](docs/research/injection-validation.md) hooks each tested macOS build's own SDL dispatch table, observes real emulator calls, and exercises live routing/remapping using two in-process virtual controllers. No PGCS bridge or Go application code is imported. Continue with physical devices, Steam/Linux, reversed order, duplicate models and topology changes before treating assignment as production support. PCSX2/ARMSX2 and the remaining roster follow their own verified adapters.

Acceptance: real gameplay verifies player assignment for direct and Steam/Linux handoff, handheld plus external devices, and relevant X11/Wayland cases. Missing/incompatible bridges cannot falsely confirm assignment. PGCS's existing two-player bridge does not establish four-player support.

For the in-game menu, prefer C injection/interposition and supported runtime control paths over emulator changes/forks. Prove one renderer/host tuple, capture/neutralize input, and apply/read back one actual setting. Broomm records per-setting live versus restart-required behavior and warns only for the latter. A native UI fallback is useful where necessary but does not replace the unified-menu goal.

Acceptance: menu input never also controls gameplay; focus/fullscreen/renderer recreation and Steam overlay coexistence are checked; IPC failure has a recoverable route and preserves saves. Expand Metal/gamescope/other renderers with separate evidence. Android input injection and overlays are explicitly excluded.

## Stage 6 — Remaining roster and later host delivery

Complete the [initial emulator roster](docs/emulator-support.md), recording configuration isolation, game-save/state compatibility, input ports and restart semantics per supported macOS/Linux build. Add Windows native delivery with its own evidence.

Android uses detected installed emulator apps, or user-approved installation when absent, then the supported ROM/save/state launch/import contract. Verify content access, profile progress handoff, post-game reconciliation and a single session. Do not implement pre-launch controller assignment, native injection, overlays or desktop-style sandboxing. An app without usable save/state access needs an explicit capability limitation; do not invent compatibility.

## Later work

Computer games add native/Proton runners, user-initiated runtime provisioning, profile-specific writable prefixes and title save adapters. RetroAchievements remains deferred. Neither stage justifies speculative framework code during the emulator work.

## Verification and delivery

Update source provenance, decisions, acceptance evidence and walkthroughs with each change. Distinguish static checks, native automated execution and owner-performed gameplay/visual verification. No application test is claimed for the documentation baseline. Document checks cover local links/anchors, Markdown structure, source fingerprints and consistency with the owner's answers; external-link uptime is not exhaustively tested.

The documentation baseline and its source-reference links pass target/anchor and Markdown structure checks. The captured public JSON schema is parsed and fingerprinted. The native experiment builds through Devbox, its Dart tools pass formatting/analysis, and its five-emulator ROM suite records live input changes, pause/resume readback and native panel draw callbacks. This does not establish visual/fullscreen, physical-controller or Linux/Steam acceptance. No OS dependencies were installed and neither reference project's source/settings were modified.

The motion follow-up routes base SDL accelerometer/gyro sensors through the existing per-player ports. Dolphin, RPCS3 and Ryubing poll the routed sensors; Azahar receives sensor events through its scoped deferred watcher. Pairing cards show sensor availability, failed observations and live axes. Remote gyro pointing has an R3 recenter binding; Classic has no duplicate Remote motion. Capability and successful sampling remain distinct, so transient read failures neutralize data without removing the configuration needed for recovery. Native synthetic-motion checks passed in all four supplied motion-capable ROM fixtures; Dolphin also consumed both sensor types from the two connected physical Switch Pro controllers. This does not establish owner movement/pointing acceptance or Azahar final game HID readback. See [motion evidence and remaining scope](docs/research/controller-motion.md).

The latest control change uses L3+R1 for faces and L3+R2 for per-player gyro. Pairing changes remain pending until Apply; the playing-game chord is gated natively, then Dart pauses/applies/resumes after release. A disconnect or failed command prevents an automatic resume and returns to recoverable pairing. Acceleration remains active when gyro is disabled. Upright/Nunchuk pointer bindings select gyro when enabled/supported and relative right stick otherwise. Native Brawl testing exercises the actual Dart model and reads Dolphin raw cursor input across live off/on changes and a no-gyro source in the same process; final game IR camera output/physical feel remain owner checks. See the [current gyro evidence](docs/research/gyro-toggle.json).

## Managed setup and Home play — 2026-10-17

The Emulator Settings screen reviews version-1 setup JSON and explicitly installs the pinned local RetroArch/Snes9x, Dolphin, RPCS3, Azahar and Ryubing bundles into shared Broomm storage. It validates complete bundle inventories, internal links and hashes, stages privately, publishes receipts/selections, supports cancellation/retry and refuses manual/unrecognized replacements. Firmware/keys use explicit local resource slots. No archive downloader, arbitrary-version bridge support, system-executable picker or automatic updater is claimed.

Home and completed Store downloads offer Play for SNES, GameCube, Wii, PS3, 3DS and Switch. Entry files come from the owned download receipt rather than fixture titles. The session freezes the selected profile, acquires the same coordinator/native writer locks as setup, creates private emulator data, waits for actual native readiness, then shows the redesigned console pairing UI. Existing join/test/layout/motion/overlay/disconnection behavior is retained. Normal exit and failures return to Home after writer observation; profile changes are unavailable while playing. Local progress persists; the subsequent managed-save slice adds scoped RomM synchronization and explicit import/backup actions.

The implemented tested package set is macOS arm64. Linux/Steam/gamescope, Windows, Android handoff, other roster members and physical gameplay acceptance remain open. The overlay remains the existing external macOS Flutter window. See [the detailed record](docs/managed-emulators-and-play.md) for exact builds, commands, failure investigations and verification scope. Earlier milestone counts above are historical.

## Remembered sign-ins and platform settings — 2026-10-17

The explicit focus order described in this historical milestone now applies to Tab. The owner's subsequent scrolling/navigation report led to spatial arrows/controller traversal, whole-card/field reveal, true scroll-edge selection and cancellation of obsolete scroll animations. See the [corrections and their separate verification](docs/navigation-and-motion.md#scroll-and-direction-corrections-after-owner-testing).

Public Argosy source confirms saved per-account bearer-token restoration. Broomm now stores reusable refresh/client credentials through direct OS secure-store adapters, verifies server/account correspondence and protects refresh/publication with a stable cross-process profile lock. Switch profile retains authentication; explicit device sign-out deletes and verifies the stored credential while keeping profile metadata and progress. A storage failure preserves the current successful session and produces a visible warning. Missing/rejected and unknown/locked/offline cases remain distinct. No password or OAuth access token is persisted, no new dependency was added and no reference-project code was copied. New device-approval/QR login remains unimplemented.

Text-field navigation requires Enter to edit; Escape ends editing while retaining field focus. Pointer/touch still edits immediately, and controller activation opens the virtual keyboard. Emulator Settings lists all server platforms, shows unsupported-system messages, resolves a per-server/platform default for Play, expands setup review within its card and follows explicit focus order through expanded actions. Configured emulators offer confirmed shared removal, with retained profile settings/saves/states and ROMs. Durable pending-removal checkpoints allow cleanup to finish after interruption; the same session lease excludes live games.

Analysis and 115 Flutter tests pass, including actual card-driven fixture install/remove, held cross-process locks and malformed-default preservation. The macOS app builds; three native Keychain/window tests, separate-process Keychain restore and real SNES Home Play pass. Phone/desktop widget PNGs were inspected. Linux/Windows/Android credential adapters have source inspection only; no native builds/runtime, live owner-server sign-in or physical Steam/controller acceptance is claimed. Linux needs an existing unlocked Secret Service provider; Windows enforces the native credential blob limit. See [tradeoffs, commands, exact evidence and remaining scope](docs/remembered-signins-and-platform-settings.md).

## Home artwork and local game deletion — 2026-10-19

Mapped RomM downloads now offer sequential square-PNG and hero pickers using the mapped SGDB ID and a separate secure per-profile API key. Galleries are paged and bounded; closing a page cancels only its requests. Selection verifies image dimensions/decoding and publishes immutable local files plus an atomic record. Home uses the square tile and a top-aligned, aspect-preserving hero over 75% of its height, fading into the unchanged atmosphere. Missing/failed/skipped art retains the existing fallback and completed game. Select Artwork refreshes the RomM mapping and repeats the same flow.

Home Select opens Select Artwork/Delete, with right-click, long-press, Options and keyboard equivalents. Modal return retains the hovered title. Confirmed deletion removes only shared local game/artwork, preserving all saves/states, other games, emulator data and remote content. An external durable deletion intent survives loss of the cleanup folder's inner receipt, supports pre-rename/partial/marker-only retry and blocks play/reinstall until finished. Session and library leases exclude active writers and concurrent mutations.

Analysis and 149 Flutter tests pass; four native macOS tests pass, including independent SGDB/RomM Keychain slots. Decoded artwork is checked in inspected desktop/compact widget PNGs; real RetroArch Home Play with the supplied SNES ROM passes. The release-mode app and extracted ZIP pass signature/integrity verification. No new dependency or emulator bridge change was introduced. Live authenticated SGDB, physical input, other-host native verification and standalone/notarized distribution remain separate. See [behavior, commands, tradeoffs and exact evidence](docs/home-artwork-and-deletion.md).

## Grouped catalogue and Home refresh — 2026-10-19

Store requests use RomM 5.4's metadata grouping and retain its server totals/offsets, filters and visibility. Sibling ROM identities and tagged filenames drive a refreshed version chooser before download; single-version downloads stay direct. Cancellation, permission failure, mismatched identity and a late result after profile switching cannot select another payload. SteamGridDB artwork adds an optional third logo picker, PNG/WebP validation and atomic logo persistence alongside retained icon/hero choices. Home displays the logo with a typed-title fallback, larger icons without captions, adjacent actions and bottom-right profile/tagline controls. Timed top-left cards replace persistent notice strips and the artwork Snackbar without shifting content or taking focus.

The resize regression exposed underlying details autofocus stealing the version modal's selection. Route-aware autofocus now preserves the chooser through desktop/compact resizing; footer navigation and gameplay-return feedback also have observable widget checks. Analysis and 155 tests pass, with twelve inspected offscreen PNGs and a real supplied-SNES Home Play check. Exact sources, final commands, macOS release/archive integrity and remaining native/live-service limits are recorded in [the follow-up](docs/catalogue-and-home-refresh.md). No dependency, native adapter, emulator bridge or save/sync workflow changed.

## 3DS updates and DLC — 2026-10-22

3DS downloads automatically discover and install decrypted CIA updates/DLC. Home Select adds **Download Updates and DLC**, which refreshes the authorized manifest, reuses verified existing CIA files, downloads changed packages without the base ROM and reconciles private Azahar content. Publication uses shared immutable sources/payloads and per-profile ownership/recovery journals. Repeated checks repair tracked deployed content from the verified cache; untracked files are preserved. Game deletion removes owned content/tickets across profiles and retains all progress and content still claimed by another installed ROM. Home blocks launch while that game is installing; artwork selection follows completion.

Analysis and **175 Flutter tests** pass. The supplied real Smash Bros. DLC passed import through managed **Azahar 2126.1.2**, repeat checking without transfer/import, second-profile application and all-profile uninstall with three retained progress sentinels, using isolated APFS copies. Final measured phases were 3.193 s initial import/deployment, 1.220 s repeat, 1.509 s second profile and 0.433 s removal. The macOS release app and extracted ZIP pass strict/deep signature and archive integrity verification. No new dependency or native bridge change was introduced. Live authenticated transfer, in-game DLC visibility, a real update CIA and non-macOS native verification remain separate checks. See [contracts, walkthrough and limitations](docs/3ds-updates-and-dlc.md) and [source/build evidence](docs/3ds-updates-and-dlc.json).


## RetroArch, Wii/Switch packages and firmware — 2026-10-23

The setup/resolver now installs and selects pinned core binaries for all 18 additional RA-based platforms in the server inventory. Profile/game/core-specific save directories, ZIP inner-member identities, native SRAM/RTC/VMU exports, exact core state groups and platform testers extend the existing session/cloud workflow. The SNES boundary remains separate. A native shutdown correction leaves RetroArch's save flush to its QUIT path, with sampling stopped first and quit confirmation disabled.

Wii and Switch now reconcile attached update/DLC sources, stage real native imports/scans, publish private owned content with recovery journals, and uninstall across profiles while retaining progress and shared references. WiiWare base WADs, tickets, shared NAND contents and DLC progress have explicit boundaries; system WADs are excluded. Switch missing resources use the owner's one-ZIP-plus-two-exact-key-filenames layout from the RomM firmware catalogue, with bounded extraction/checksums and no replacement of configured resources. Setup/launch and package phases remain visible. No arbitrary custom-emulator import or built-in PS4 emulator is claimed.

Native checks include all 14 core ABIs, 13 new game/pairing/pause/remap/state routes, six real ordinary-save export/import round trips, both real WiiWare/DLC fixtures, the real Pokémon Quest update and five DLC packages, fresh automatic Switch firmware/native game initialization, existing SNES launch and native writer/RPCS3 installer regressions. The supplied media and all fixture progress stay in isolated test roots; no remote save was changed. The final test/build/archive counts, hashes and artifacts are in [the machine-readable record](docs/retroarch-wii-switch.json). Five new optical/BIOS routes, in-game DLC recognition, full special peripherals, physical/cross-device and non-macOS acceptance remain outstanding.

## RetroArch save verification after owner testing — 2026-10-23

Owner reports now distinguish verified launch/state/cloud observations from failed ordinary progress. Opera's raw NVRAM export and upload readback now share a concrete native filename/version boundary. Flycast sessions force all VMUs into private per-game storage using the pinned build's real option name and override precedence; native disc-ID card names and observed state filenames are retained. Sole-game legacy cards migrate with a durable ownership record while originals remain intact; ambiguous histories and differing private data are preserved. Compressed cartridge saves now follow the frontend's observed outer-ZIP basename. Retained retries accept actual core IDs containing underscores and retain raw-save identity after a native installation is removed.

Save-capable native fixtures cover the ordinary file/sync boundaries; the 32X EEPROM sentinel is distinguished from game-created progress. NES 1943 correctly creates no ordinary save or empty upload. Stella and Beetle Lynx do not expose ordinary cartridge save RAM in the pinned builds; state transfer is checked instead. Saturn still lacks regional BIOS in RomM, and Jaguar CD native validation is deferred by the owner. The [updated matrix](docs/platform-support-matrix.md), [walkthrough](docs/retroarch-save-followup.md) and [evidence record](docs/retroarch-save-followup.json) report exact results, failures, counts and delivery. Native tests use disposable profiles and a fixture server; owner progress and remote saves are unchanged. Cross-device and other-host acceptance remains separate.

## PlayStation and PlayStation 2 — 2026-10-23

The managed pack adds DuckStation 0.1-12083-g00e299795 ARM64, ARMSX2 nightly-20261023 ARM64 and PCSX2 2.8.2 x86-64 through pre-existing Rosetta on the Apple Silicon host. Home resolves PS1/PS2 media into the same loading/pairing/session flow. New DualShock/DualShock 2 testers use the existing join, face-swap, paused menu and disconnect behavior. The independent C bridge uses each pinned emulator's own SDL3, queued native pause methods and real state acknowledgment. No emulator implementation is copied, no source patches or dependencies are added, and no system settings are changed.

Profile/game-private native whole cards participate in BROOMM timestamped save versions, explicit import/backup and existing recovery/conflict handling. Both PS2 choices share ordinary `.ps2` cards and BIOS, with separate native configuration and exact-build states. DuckStation uses `.mcd`. Multi-card native ZIPs preserve both slots; unsupported individual-game/container formats are rejected. Missing BIOS files come from the same RomM platform with checksum/format checks, visible phases and reuse. Native `-datapath` suffixes and DuckStation's private HOME are measured, rather than inferred from general Qt conventions. Rendering preferences remain intact.

Analysis and **299 Flutter tests** pass. The three-emulator native suite passes using Crash Bash and Harvest Moon: Save the Homeland: managed installation, real BIOS bytes, input readiness, joining, pause/live remap, same-process disconnect/reassignment, normal shutdown, native cards, cloud fixture upload/readback/export/restore and matching native states. Both PS2 builds also execute native state loads. DuckStation creates a native 128 KiB card; the tested PS2 cards are native blank 8 MiB cards with ECC. No completed in-game save-point or physical-controller acceptance is claimed. Both Sony console sockets currently retain their configured pad type, with unassigned input neutral; dynamic emulated unplugging remains a gap. The separate Flutter menu surface and missing non-macOS native packages remain explicit.

The existing six-game native regression also passes after the shared bridge changes. The macOS release and freshly extracted ZIP pass archive integrity and strict/deep signature checks. The [integration walkthrough](docs/playstation-support.md), [machine-readable evidence](docs/playstation-support.json) and [updated support matrix](docs/platform-support-matrix.md) retain exact builds, hashes, diagnostic failures, test scope and the new macOS release output. Saturn's earlier BIOS/native-progress prerequisite was subsequently verified in [its separate record](docs/saturn-verification.md). PS4 remains an ordinary downloadable platform without a built-in emulator. PSP was the remaining launch route at this milestone and is implemented in the following section.

## PSP and additional Switch emulator — 2026-10-23

The macOS ARM64 pack now includes official PPSSPP 1.20.4 and Eden 0.2.1. Eden is an independent Switch card/default choice after Ryubing; the upstream macOS distribution is experimental. Both use verified private configuration, the existing managed installer/no-game settings entry, native controller/pause/live-remap/disconnect interfaces and session supervision. PSP adds a single-controller handheld tester and verified ISO/CSO/PBP metadata; it needs no BIOS. Its native game-created savedata ZIPs and revision/build-compatible states participate in BROOMM history, explicit import/backup and existing conflict/recovery. Native destination/ZIP DLC installation tracks individual files and preserves new saves on uninstall; generic PSP patch execution is not claimed.

Eden uses independent console accounts, native save-directory boundaries, firmware/key paths and NAND add-on ownership. Logical ordinary Switch cloud exports remain compatible with Ryubing without copying identities or native indexes. The known installed update/DLC selection is prepared when the default changes. NSP title association and encrypted native content-ID readback are performed in Dart using the existing Apple AES primitive through FFI. Eden currently accepts one update NSP plus multiple DLC packages; ambiguous update versions are retained with an actionable error. No new runtime dependency, emulator implementation source or OS installation is introduced.

Analysis and **313 Flutter tests** pass. Native PPSSPP checks pass on N+ and Puzzle Bobble Pocket: actual core-button readback, paused live remap, disconnect/reassignment, game-created ordinary saves, state creation/loading and fixture cloud readback/export/restore. The frontend's final boot transition is verified before pairing to prevent an early native pause from being overwritten. Eden checks pass on Pokémon Quest: actual program/Npad/two-port state, paused remap, disconnect and a seeded native save-directory/cloud round trip. Six real update/DLC NSPs generate 14 validated NCAs, deploy across two profiles, repeat without transfers, uninstall with progress retained and load the update in native Eden. In-game DLC acceptance, game-created Eden saves, longer gameplay, physical input and non-macOS delivery remain separate.

The six existing native fixtures and the three-emulator Sony suite pass after the shared SDL additions. All twelve private no-game applications start and exclude competing sessions; five native writer/installer guard cases pass independently. Apple C static analysis reports no diagnostics, and the scoped PSP preference fixture passes AddressSanitizer/UndefinedBehaviorSanitizer. The final PSP fixture distinguishes actual ordinary saves from state-only BROOMM bundles; updated Quest closes normally, while an observed unpatched native guest/shutdown fault remains an experimental Eden limitation. No owner process was terminated or owner/remote progress changed.

The new macOS release ZIP is `build/releases/Broomm-macOS-arm64-psp-eden.zip` (20,001,329 bytes). Archive integrity, source/fresh-extraction strict/deep signatures and bundled setup/bridge fingerprints pass. Source/output hashes, retained failures, commands and limits are in [the evidence record](docs/psp-and-eden-support.json). The [walkthrough](docs/psp-and-eden-support.md) and [colored matrix](docs/platform-support-matrix.md) supersede older PSP-pending descriptions. The separate Flutter overlay surface and Linux/Steam/gamescope acceptance remain outstanding.

## Android external emulator audit — 2026-10-26

Android previously had sign-in and launcher input but reached desktop-only emulator setup/launch. It now has separate installed-package discovery, platform cards/defaults, official installation links, a checked APK/system-installer action and no-game app opening. Home uses concrete exported Android activities and confined read-only ROM URI grants, bypassing desktop controller pairing/injection/overlays. Discovery failures retain observations; opening an installer is followed by package readback rather than being called installation success.

PPSSPP, melonDS and Azahar have profile-specific Broomm DocumentsProvider roots and explicit in-emulator folder setup. Existing BROOMM workflows use those native files: PSP savedata/Android-build states, DS raw `.sav` and Azahar data/extdata/states. APK byte fingerprints prevent trusting a different emulator build's states. PSP native-folder/ZIP DLC and owned cleanup reuse the Dart installer. No existing external data is adopted or swept. Android sessions keep the production lease and a durable recovery marker until explicit emulator-closure confirmation; open writable descriptors block finalization. Return/resume alone is not writer-exit evidence. Interrupted/changed-build progress stays available for review.

**Android parity remains incomplete.** RetroArch, Dolphin, DuckStation, ARMSX2 and Eden still need Android save/storage adapters; DS states are missing. Android core/BIOS setup, CIA/WAD/NSP installation, Switch firmware/keys and associated external-content removal are not implemented. Their desktop installers are never called on Android. Store/download behavior remains ordinary, including PS4, but those native features are not advertised as working. Initial connected-folder sync runs before launch; background work only retries sealed progress while no Android session is pending.

Analysis is clean and **328 Flutter tests** pass, including 15 new Android boundary/workflow checks. All six Android Kotlin sources compile with the pinned Devbox Kotlin/JVM toolchain and hash-pinned Android/Flutter compile APIs. Compilation is not an APK build or runtime evidence: this host has no full Android SDK/device, and no Android emulator installation, SAF folder selection, gameplay, real save/state load or physical input was executed. No runtime plugin, emulator code or OS dependency was added. The main Flutter environment is unchanged; a separate development environment avoids the macOS license-name collision in Nix profiles. See [Android status, remaining work and sources](docs/android-emulators.md), [evidence](docs/android-emulators.json) and the README walkthrough. Native device acceptance and all red Android matrix cells remain open.

## GitHub release preparation — 2026-10-26

The owner selected Teddy's release workflow/version policy. `.github/workflows/release.yml` now defines PR checks and five package targets: macOS universal, Windows x64, Linux x64/ARM64 and Android universal. `version.txt` starts at `0.1`; the existing tag ledger automatically supplies stable patches on main and candidates on develop, without version-only source commits. Dart tooling implements planning/ownership validation, complete package/checksum/commit records and draft-first publication with upload readback. PRs do not publish or receive signing secrets; completed public releases are immutable on rerun. Both publishing branches share the queued release train.

CI uses the existing Flutter pin, locked project Linux/Android/lint Devbox environments and pre-provisioned native SDKs. Windows uses a workspace-local Flutter SDK matching the Devbox pin because Devbox has no native Windows backend. Linux uses Devbox headers/tools with the pre-provisioned Ubuntu compiler ABI, then rejects missing host dependencies and Nix runtime paths. Android uses copied private SDK components and a persistent four-secret release keystore; Gradle explicitly applies Kotlin with built-in Kotlin disabled, reads optional signing properties and pins the reviewed build tools/NDK. No OS package install, global SDK selection, new Flutter runtime plugin or emulator download is introduced. Developer Mac builds retain their old checkout behavior; `--portable` removes that checkout define from release builds.

Static analysis is clean and the complete suite passes **337 Flutter tests**, including nine release regressions. All **six macOS native host tests** pass with zero skips/failures; two existing XCTest deployment-target link warnings remain recorded. The release packaging path builds a universal app and all three universal C libraries, verifies architectures/deep signatures, then writes the ZIP/checksum/JSON. Fresh extraction also passes strict/deep signature verification and reports native version `0.1.0` / build `1001`. The local development artifact is `dist/Broomm-0.1.0-pr1.1-macos-universal.zip`, **20,010,754 bytes**, SHA-256 `ae66e5963a9856083732fa2f84b79b0916ef54f9ae362a47935f8faa2d72aa8a`. It was built from the cumulative uncommitted tree against base `4c28719`, not from a published revision.

Full Dart formatting now passes after correcting two existing test-file formatting differences. Workflow/ShellCheck validation uses a narrow, documented actionlint 1.7.12 workaround for GitHub's newer `concurrency.queue` field; the queue/cancellation values are checked independently. A real clean temporary Git checkout also exercises the version CLI without package caches. Diagnostic logs retain the sandbox socket/Nix-cache constraints and corrected validator/format findings. The root Devbox manifest/lock and pubspec lock remain unchanged.

Bash files retain LF on Windows checkouts. The tracked bootstrap Flutter crash report is removed from the current source tree after preserving an identical ignored copy; existing Git history is unchanged. New signing files, crash reports and release outputs are ignored.

**Initial local-only evidence:** the preparation above preceded the first GitHub run and did not establish hosted/native Linux, Windows or Android results. The [release walkthrough](docs/github-releases.md) explains exact branch/version behavior, prerequisites, outputs, external effects, cleanup and existing emulator acceptance limits. The platform matrix is unchanged by CI build coverage.

### First hosted CI corrections — 2026-10-26

The owner supplied six failing jobs at `b3fddece07a1198d44522c8841f5ed80482dd3b1` and confirmed a successful Android build/signing setup. Corrections address Windows native-path handling in add-on inventories and artwork cleanup, portable file copy/checksum operations, macOS-specific presentation fixtures, Windows PS2 fixture positioning and download teardown before releasing temporary storage. The native writer test builds its own private guard. The macOS frame test now chooses a screen-fitting frame with exact assertions and improved failure diagnostics; the supplied hosted log omitted its underlying assertion, so the runner-specific cause remains subject to rerun. Linux GTK/pkg-config use a coherent glibc 2.39 Nix snapshot and fail early with complete dependency/linker diagnostics.

Local validation passes **342 Flutter tests**, clean analysis, **216** formatted Dart files, workflow/ShellCheck and **six native macOS tests** after rebuilding the host and native libraries. Nix evaluation verifies distinct x64/ARM64 Linux target dependencies (GTK 3.24.43, GLib 2.80.4, glibc 2.39); it is not a Linux compile/run. Two existing XCTest SDK link warnings remain. No tests were skipped, assertion failures suppressed or timeouts increased. New Windows/Linux native verification and a complete hosted matrix remain pending. No commit, push, tag or release was made by this follow-up. See [failure details and reproduction](docs/github-releases.md#first-hosted-failures-and-corrections--2026-10-26) and [fingerprints](docs/github-ci-followup.json).

### Second hosted CI corrections — 2026-10-26

Four new logs at `208dda7dc6e3d80f697377cd01b069f48a6405b7` expose ten remaining Windows tests and a Linux Devbox bootstrap syntax error. The bare GTK flake plus output list generated an empty `gtk3.` selector; explicit `#gtk3^out,dev` now passes actual Devbox environment generation and pkg-config execution on macOS with GTK 3.24.43 and GLib/GIO 2.80.4. This corrects the previous validation gap: package metadata evaluation alone did not exercise Devbox's generated expression. No cache deletion is required by the reproduced cause.

Windows fixes compare RPCS3 profile directories as native URIs, retain Switch NSPs referenced from native metadata regardless of separators, and recognize firmware NCAs by leaf name. Ownership checks, foreign data preservation and incomplete-resource protection remain enforced. Six added regressions cover forged/wrong-account RPCS3 profiles, retained/extraneous Switch package references and both engines' incomplete firmware trees. All **348 Flutter tests**, static analysis, **216**-file format check and workflow/ShellCheck pass locally; the portable macOS debug app is rebuilt. Native Windows execution and Linux compilation still require a new hosted run. No tests are skipped and no timeouts are enlarged. This follow-up makes no commit, push, tag, release or signing change. See [details/reproduction](docs/github-releases.md#second-hosted-ci-corrections--2026-10-26) and [fingerprints](docs/github-ci-second-followup.json).

### Third hosted CI corrections — 2026-10-26

Three new logs at `cf27b39bef293bef31908e422280f1d9ad6d485c` show three remaining Windows Switch package failures and Linux x64/ARM64 linker failures. Native Switch indexes normalized path separators while publication still used raw string keys, leaving references to a renamed staging directory. Publication and retention now share file-URI identity and write native destination paths. Two additional regressions cover both indexes with mixed Windows separators, UNC paths/encoded characters and unrelated metadata; the existing package ownership/removal cases stay enabled.

The Linux link lines mix newer Pango 1.57.1 from Flutter's Nix wrapper with the selected Pango 1.52.2/GTK stack. CMake and compiler shims now restore the captured Devbox target pkg-config graph and clear competing flags/search paths after that wrapper runs. The manifest/lock expose the existing GTK graph's private development metadata from the same snapshot and preflight both dynamic/static queries. Both actual Linux target metadata graphs resolve on macOS using the host pkg-config tool; this is not Linux compilation. A native macOS GTK/GLib/GIO linkage probe exercises the production CMake boundary under poisoned inherited flags, literal paths/arguments and missing SDK selection.

All **350 Flutter tests**, clean analysis, **217**-file formatting, workflow/ShellCheck and the portable macOS debug rebuild pass. Windows execution, native Linux compiler-shim execution, full Linux builds/runtime auditing and a complete hosted matrix remain pending. The unchanged six native macOS app tests are not recounted as a new run. No test is skipped, assertion relaxed, timeout enlarged, signing secret changed or OS dependency installed. No Git commit/push/tag/release or owner-data mutation is performed. See [details/reproduction](docs/github-releases.md#third-hosted-ci-corrections--2026-10-26) and [fingerprints](docs/github-ci-third-followup.json).

### Fourth hosted CI follow-up — 2026-10-26

The logs at `988353f26a3e21f69f4ed73e66aa5987826f1cf9` have one Windows failure: the full-size PS2 engine-switching save test times out at 30 seconds, then fixture cleanup collides with a live save worker. The previous Switch failures are absent. Linux's static preflight now exposes a missing `xtst.pc` through AT-SPI. The previous closure-wide metadata query found directories Devbox did not propagate. Following only declared outputs and propagated build inputs reproduces the failure for both architectures; exposing the existing pinned XTest primary output makes both full dependency queries pass.

CI runs the two full-size card tests in a separate single-suite step on every checks host, including after an earlier check failure unless canceled. Test assertions, card sizes, checksum/readback behavior and 30-second limits stay intact. Failure-only phase timings identify the pending operation. Complete test workflows drain before temporary storage cleanup, and undrained workers retain their fixture directory. A deliberate 500 ms timeout in a private copy stays a failing test while its roughly eight-second workflow finishes before cleanup, without a secondary deletion failure. Windows resource contention remains a hypothesis; the scheduling change needs hosted verification.

Local **348 + 2 = 350 tests**, clean analysis, **217**-file formatting, workflow/ShellCheck and both restricted Linux metadata queries pass. Native Windows execution, Linux builds/runtime checks and the complete hosted matrix remain pending. Product/native sources are unchanged; no new app build or native app-test run is claimed. No test is skipped, assertion relaxed, timeout enlarged, OS dependency installed, signing changed or owner-data/Git publication effect performed. See [commands and limits](docs/github-releases.md#fourth-hosted-ci-follow-up--2026-10-26) and [fingerprints](docs/github-ci-fourth-followup.json).

### Fifth hosted Linux build correction — 2026-10-26

Both Linux logs at `4c366be55013f35dc243ddd6da9e8226ce8741be` pass dependency queries and Flutter assembly, then fail compiling `my_application.cc` because GTK's shared compiler flags omit X11's private headers. X11 is already in the SDK. The root CMake project now imports `x11`, the runner consumes `PkgConfig::X11`, and both preflight queries include it. No dependency manifest/lock change or window/backend behavior change is needed.

GTK-only flags reproduce the exact header failure against the real runner for both Linux architectures. A private object-only CMake harness uses the actual dependency/settings declarations and runner target; all three source objects compile for x64 and ARM64 with `-Wall -Werror`. ELF checks verify all six architectures, both X11 branches and the explicit libX11 link inputs. Full shared/static metadata queries and workflow/ShellCheck pass. The harness uses approved Apple Clang 21.0.0 with pinned Linux/Flutter/C++ headers and supplies compiler-work/ABI cache values only for the object-only cross check; production native compiler/link checks are unchanged.

This is cross-compilation on macOS, not Linux execution, final application linking, bundle auditing or gameplay. Those native checks and the complete hosted matrix remain pending; the new logs supply no Windows result. The unchanged Flutter suite and native macOS app tests are not recounted as new runs. No OS dependency installation, owner-data effect, test skip/timeout relaxation, signing change or Git publication is performed. See [reproduction and limits](docs/github-releases.md#fifth-hosted-linux-build-correction--2026-10-26) and [source/object evidence](docs/github-ci-fifth-followup.json).

### Sixth hosted CI follow-up — 2026-10-26

At `087aaa1889f1c9fb46e7a04fcaee070054aa8ccf`, the supplied macOS native test command succeeds; the job fails uploading its results because GitHub's artifact-storage hostname cannot resolve. This requires a job rerun, not a native test correction. The ARM64 log now confirms successful compilation/linking/bundle installation before the audit rejects Nix-resolved libepoxy. The script was checking the launcher before removing the engine's own SDK RUNPATH. Both exact locked Linux engines contain those paths.

Bundle preparation now finishes for every ELF before any dependency tree is checked. SDK paths/interpreters, missing libraries and loader errors remain failures, with per-binary diagnostics. Three native regression cases are added to both Linux build jobs: forced traversal orders with relocation/execution, missing transitive dependencies and an SDK interpreter. All fixtures stay private and clean up on exit.

Workflow/ShellCheck and shell syntax checks pass locally. Actual pinned x64/ARM64 ELF copies reproduce the old ordering failure and pass the corrected preparation/order checks through a modeled loader boundary on macOS; loader-error and SDK-interpreter failures remain visible. Source engine hashes remain unchanged. This is metadata/patch verification, not Linux execution: the new native tests, host `ldd` resolution and a complete hosted matrix await CI. Unchanged Flutter/native macOS application tests are not rerun or claimed anew. No tests are skipped, limits relaxed, OS dependencies installed, signing changed, owner data touched or Git publication performed. See [walkthrough and limits](docs/github-releases.md#sixth-hosted-ci-follow-up--2026-10-26) and [fingerprints](docs/github-ci-sixth-followup.json).

## Application updates from GitHub — 2026-10-26

The owner selected Teddy's updater as the reference. Official release builds check the public Broomm repository at startup and every six hours, with manual checks and stable/candidate channel selection in Settings. A newer complete release adds **Update Broomm** first on Home without changing the selected game's identity. Activating it starts a controller/keyboard-navigable download, checksum/build-record validation, private preparation and desktop replacement/restart. Development and PR builds stay manual. Release packaging embeds the full version/target and an installation inventory; emulator updates remain user-initiated setup imports.

The Dart workflows use existing HTTP, digest and confined archive mechanics without new runtime dependencies. OS adapters perform only exclusive directory moves/relaunch or Android package inspection/installer handoff. The updater finishes save work, checkpoints the game download queue and obtains the session lease before exit. Failed checkpointing retains the queue and its ownership for retry. Cancellation is fenced before OS handoff, a rejected exit disarms the helper, and replacement/launch failures preserve recovery evidence and attempt to restore the old bundle. Games, emulator configuration, accounts and progress remain outside the replaced installation. Android requires OS permission/confirmation and controls the final Open action; silent installation or guaranteed automatic Android relaunch is not claimed.

Local validation passes **371 ordinary + 2 full-size = 373 Flutter tests**, clean analysis, **228**-file formatting, workflow/ShellCheck and generated-helper shell checks. All **six native macOS host tests** pass with zero failures/skips; the two existing XCTest deployment-target link warnings remain. The portable macOS debug app builds, and all **seven Android Kotlin sources** compile with the pinned toolchain; the compatibility fallback emits two API deprecation warnings. Native macOS fixtures verify exclusive moves against occupied destinations and actual Launch Services replacement/relaunch, alongside independent-process locks, rollback, cancellation, queue persistence and controller navigation. A real public `v0.1.0` package (20,018,724 bytes) passes GitHub selection, checksum/build-record validation, private extraction and strict/deep signature checks without installing it or touching owner progress.

The first published release containing this code is needed before later releases can be discovered automatically; the existing public `v0.1.0` predates the updater. A real owner upgrade between two updater-enabled releases, Windows/Linux native replacement/relaunch (including gamescope), and Android device installation remain acceptance work. Native-host-specific regressions remain enabled on their corresponding CI runners. Test-fixture scheduling/teardown findings and the corrected intentional-future lint are retained in ignored diagnostics; no assertion or timeout was relaxed to obtain a pass. No OS dependency/global SDK change, signing change, commit, push, tag or release is performed. See the [walkthrough and recovery notes](docs/application-updates.md), [verification record](docs/application-updates.json) and README actions.

The requested current macOS delivery is [Broomm-macOS-application-updates.zip](build/releases/Broomm-macOS-application-updates.zip), **20,097,507 bytes**, SHA-256 `49908b5efa83ebc5499247338c78ac4763b66ded1b851a59f0b0804e69f31a05`. A fresh release-mode build and all three native bridges contain ARM64 and x86-64. ZIP integrity and source/fresh-extraction strict/deep code signatures pass. This ad-hoc-signed development package uses the checkout's existing data/setup paths, retains an explicit `0.1.0-dev` identity and contains no emulator, BIOS, ROM or progress payload. Automatic installation remains enabled only in official release builds. AGENTS.md now records the owner's standing requirement to include the current macOS build link in deliveries. Application sources are unchanged by this packaging follow-up; the preceding test results are retained rather than claimed as new runs.

## Infinity application icon — 2026-10-27

The owner selected the existing mint infinity mark for Broomm's application icon.
The pinned Flutter renderer now produces a 1024 px master, transparent mark,
seven macOS catalog sizes, nine Windows ICO sizes, a Linux window/theme PNG and
five Android legacy/foreground densities. Android 8+ adaptive and Android 13+
themed resources share the mark; generation checks every visible foreground
pixel against the 66 dp circular safe zone. These are checked-in native resources
used by every build mode, with no new renderer/plugin/runtime dependency. The
existing Material Icons glyph's license is retained and bundled on every target.

Linux loads the window icon relative to its executable rather than launch cwd.
Its bundle also carries standard hicolor/desktop-entry assets; no host desktop
registration or theme/cache changes are performed. Analysis is clean and all
229 Dart files pass formatting. The existing object-only cross-check compiles
all three actual Linux runner sources for x64 and ARM64 with `-Wall -Werror`.
This is not native Linux execution or linking. The renderer completes with the
expected PNG/ICO formats and density sizes; the first attempt retained the Nix
license copy's read-only mode, corrected only on the project-owned copy before
regeneration. No assertion, test or timeout is relaxed.

The fresh [macOS build](build/releases/Broomm-macOS-infinity-icon.zip) is
**20,306,518 bytes**, SHA-256
`ae598ba5e3fa67f96381a35ec5864a00a5e8c59031d45dd112e5af04b5d8c13b`.
The application and three bridges contain ARM64 and x86-64; ZIP integrity and
strict/deep signatures pass before and after fresh extraction. The packaged
ICNS and CoreUI catalog retain their hashes, both native icon metadata keys
name AppIcon, and the compiled catalog includes every source size. The extracted
256 px ICNS image was visually inspected through the image-view tool; no
computer-control tools or owner app/progress data were used. This remains an
ad-hoc-signed local development build using this checkout's existing data paths,
without emulator/BIOS/ROM payload or enabled development self-updates.

Native Windows resource compilation, Android APK/launcher rendering and Linux
desktop/Wayland icon lookup remain host acceptance checks. The earlier Flutter
and macOS host suites are not recounted as new runs for this artwork change.
The [artwork walkthrough](assets/branding/README.md) documents regeneration,
licensing, outputs and cleanup; [the verification record](docs/application-icons.json)
retains source/asset fingerprints, exact commands, diagnostics and platform limits.
No OS dependency, global SDK, emulator configuration, signing identity or Git
publication is changed.


## Standalone RetroArch desktop release pipeline — 2026-10-27

The owner-selected sibling `broomm-retroarch` now contains an independent native
GitHub Actions build/release workflow for macOS ARM64/Intel, Linux x64/ARM64 and
Windows x64. Android is explicitly excluded. Exact RetroArch 1.22.2/SDL 3.4.0
source pins, shared SDL3/OpenGL Core/Slang/network control configuration, private
toolchains, notices, native probes, per-file inventories/checksums and complete
corresponding sources are implemented. The queued release train uses
`version.txt` plus automatic stable/candidate tags; only a complete checked
artifact set can be published through a draft. Existing tags/releases are
preserved, and failed GitHub access is never treated as confirmed absence.

On macOS 27.0.1/Apple Silicon, 17 packaging/release regressions and workflow/
ShellCheck pass. A native frontend build passes SDL virtual-gamepad input,
feature/architecture/minimum-OS/relocation/signature checks, actual playing/
paused network command readback and clean QUIT. All 29 files, permissions,
signatures and standalone feature startup pass after fresh ZIP extraction.
Pinned Linux SDK metadata is verified for both architectures; native Windows,
Linux and macOS Intel execution, the first hosted release and Broomm physical
controller/gameplay adoption remain pending.

No project commit, push, GitHub release, Flutter change or trusted setup-hash
replacement was performed. The current Broomm macOS application stays unchanged;
a separate 8,119,704-byte ARM64 RetroArch ZIP is available. See
[distribution status, artifacts and adoption steps](docs/retroarch-distribution.md)
and the sibling project's README/IMPLEMENTATION for exact source/tool versions,
commands, failure corrections, local test effects, logs and cleanup.


### RetroArch first hosted SDK correction — 2026-10-27

The initial `Broomm/retroarch` version/source jobs fail before their logic runs
because pinned Linux libXScrnSaver has only `out`, while its Devbox selector
requested `out,dev`. The sibling recipe/lock now request `^out`; token
permissions and caches are unchanged. An independent lint-job SDK audit covers
all four Unix architectures with retained diagnostics. The original fails on
both Linux targets, the fixed 64 selectors pass, all 17 regressions and workflow
lint pass, and actual version/source commands plus readback pass locally. A
new hosted/native Linux run is still required. Existing macOS artifacts and
Flutter/native application sources are unchanged. See
[distribution follow-up](docs/retroarch-distribution.md) and sibling evidence.

### RetroArch Linux/Windows correction and macOS timeout — 2026-10-27

The next hosted run reaches Linux SDL configuration and fails on missing XTest;
the sibling SDK/lock now include the verified `libXtst^out` on both architectures.
Windows tool paths no longer replace Git Bash with BusyBox in the runner; child
processes resolve their private tools explicitly. All 25 regressions, lint, 66
Unix SDK selectors and repeated local native macOS probes pass. The hosted macOS
ARM64 build/SDL probe succeeds but its frontend GET_STATUS times out; the cause
is still unconfirmed. Flushed frontend logging, owned-child failure sampling
and retained failed runtimes now provide evidence for the next run. Checks and
timeouts remain strict. See [the distribution record](docs/retroarch-distribution.md).
Existing macOS artifacts, Flutter application sources and trusted hashes are
unchanged. No hosted pass, commit, push or publication is claimed.

The subsequent Windows run confirms shell isolation, then fails one regression
fixture with WinError 206: its large inline diagnostic exceeds the Windows
command-line limit. The fixture now reads the same payload from a temporary
file and enforces the UTF-16 command-line bound on every host. All 25 tests pass
locally with the original diagnostic assertions retained. No production/build
code or native artifact changed; hosted Windows acceptance and the separate
macOS timeout remain pending. See the distribution record and sibling evidence.

The latest Linux jobs compile both upstreams and pass SDL input, then fail on a
hard PulseAudio startup dependency. The sibling Linux recipe now disables the
standalone Pulse backend, retaining native ALSA and SDL3's dynamic PulseAudio
route; loader auditing precedes startup and retains all missing-library data.
The exact hosted macOS binary passes locally, while its VM timeout remains
unconfirmed. Explicit loopback client binding, reply identity/full bounded
traces and owned-child UDP inventory improve that transport boundary without
relaxing checks. All 31 regressions, lint and local/exact-CI macOS native probes
pass, including new SDL dummy audio. Build/native results now remain independent
of packaging-test failure, which still blocks release. Native Linux rerun and
hosted macOS acceptance remain pending. No Flutter change, new macOS binary,
OS dependency installation or Git publication occurred. See the distribution
record and sibling `docs/ci-followup-4.json` for exact evidence and limitations.

The next hosted run `40575998429` confirms native probes and packaging pass on
both macOS architectures. Windows reaches RetroArch configure after SDL builds;
the recipe now bypasses its Unix-style executable lookup with explicit private
compiler/resource/pkg-config `.exe` paths. Linux's only remaining loader failure
is headless-host EGL: the probe conditionally provisions the existing locked EGL
loader in a private test directory, strips its SDK RPATH and retains strict
host-dependency auditing. Native Wayland/EGL and shipped packages are unchanged.
All 37 regressions and lint pass locally; corrected native Linux/Windows checks
await a hosted rerun. No Flutter change, new binary or Git publication occurred.
See the distribution record and sibling `docs/ci-followup-5.json`.

Run `40579927392` confirms native checks and packaging pass on both Linux
architectures and macOS ARM64. Windows compiles and passes SDL/feature checks;
its first UDP query receives Winsock 10054 before the emulator binds its port.
The probe now handles only that Windows port-unreachable response within the
existing deadline, retaining actual acknowledgment and live-child requirements.
All 41 regressions, lint and the actual local macOS frontend check pass. Intel
macOS failed earlier during Nix package-cache DNS/downloads; its recipe is
unchanged and needs a hosted rerun. Windows native frontend acceptance also
remains pending. No Flutter change, new binary or Git publication occurred.
See the distribution record and sibling `docs/ci-followup-6.json`.

Run `40582896434` passes all Unix jobs and both Windows native probes. The
remaining Windows failure is package metadata using native backslashes against
a forward-slash ZIP inventory. The recipe now serializes portable references
and explicitly rejects unsafe or missing entries. Real nested target fixtures
and a Windows-path roundtrip cover the boundary on every host. All 44 regressions,
lint and existing real macOS package verification pass locally. Exact Windows
artifact readback confirms the corrected references. New native Windows packaging
and publication remain pending. No Flutter or binary change occurred. See the
distribution record and sibling `docs/ci-followup-7.json`.

## Owner-requested local development cleanup — 27 October 2026

Removed the obsolete checkout-local library, accounts/settings, profile progress,
managed emulator copies, prototype data, supplied test ROMs, research sessions,
download/tool caches and generated build state. Retained the source tree, locked
environment definitions, signing material and current
`build/releases/Broomm-macOS-automatic-cores.zip`. Historical committed native
evidence remains; its deleted ignored fixtures need reprovisioning for reruns.
No application behavior changed and no new binary was necessary.

Before removal, the process inventory showed no Broomm/emulator/build writers,
seven existing development runtime locks were acquired, and production
configuration/symlink inspection found no references into the deleted roots.
Production's 1,546-file path/type/size/modification-time inventory was identical
before and after (SHA-256
`21457af55770f1bc3790ab0553a620ab38fe3930020004b268701808b80d087c`).
No production files, installed Applications bundle, Keychain entries or remote
RomM data were modified. The retained macOS ZIP still hashes to
`39dffc43d3ac6aea38ab560a52a7c9cb73e9d8159de84f77f12b2d305c0e13f9`.
Available disk space increased by approximately 131 GB; nominal deleted directory
sizes were larger because of shared/cloned storage. These are filesystem checks,
not a new application or gameplay verification run.

## macOS emulator setup portability — 28 October 2026

The owner reported PCSX2, ARMSX2 and PPSSPP setup rejecting valid downloads on
another MacBook. Their local re-signing was followed by exact comparisons with
signature bytes captured on the development Mac. Fresh official downloads match
here; deliberately different valid code-signing output reproduces the rejection
class. The friend's exact signing difference remains uninspected.

Reviewed archives retain mandatory source size/SHA-256 validation. Privately
re-signed output now uses macOS deep/strict/all-architecture validation, expected
file/link structure and its locally recorded executable hash, instead of a
separate SHA-256 inventory comparison with another Mac's signatures. Receipts
bind the result to the specific build's reviewed source archive. Existing raw
imports and receipts remain compatible. Logical emulator/state/Switch progress
identities stay stable across signature variations; cancellation, writer locks,
private staging, copy/receipt/publication readbacks and progress retention remain.
The shared correction also covers Dolphin, DuckStation and Eden signing recipes.

Static analysis and all **415 Flutter tests** pass on macOS 27.0.1 / Xcode 27.1.
Three new signing regressions and an expanded state-compatibility case cover
different valid signatures, restart/source-free reuse, damaged resources,
unreviewed provenance, bad downloads and cancellation. Real pinned PCSX2 2.8.2,
ARMSX2 nightly-20261023 and PPSSPP 1.20.4 install with alternate valid signatures,
open private no-game configuration processes and exclude competing writers.
These are native setup/process checks, not fresh gameplay or friend-host
acceptance. No owner data or RomM progress is modified. Astris/Citra MMJ and
their default-selection work remain stashed. See the [walkthrough and evidence](docs/macos-emulator-signing.md).

The fresh [macOS package](build/releases/Broomm-macOS-portable-emulator-setup.zip)
is **20,477,225 bytes**, SHA-256
`c6732b81b0cf422756fe7b9f3b9f2221ecc93f2cdfaf12334f89c880cc4e28cc`.
The app and three bridges are universal; archive integrity, source and
fresh-extraction deep/strict/all-architecture signatures, and exact setup/bridge
readbacks pass. This portable local build uses production Application Support
storage and ad-hoc signing, with development self-installation disabled.
No emulator, game, firmware, credential or progress payload is bundled.

Before the requested Git publication, the updater was also corrected to use the
actual `Broomm/broomm` origin. Public API inspection showed distinct release IDs
and revisions in the old personal and organization repositories. Older installed
clients remain pointed at the personal repository and need one manual
organization-release installation before using this update stream. Two new
regressions verify organization API discovery/asset selection and rejection of
old or unrelated publishers. Analysis and all **417 tests** pass. The local
package was rebuilt; incremental compilation required refreshing the
project-owned App.framework and outer ad-hoc signatures before source and fresh
ZIP extraction signature checks passed. This does not change CI signing policy.

## Independent Open emulator and Azahar bundle launch — 28 October 2026

Open emulator now hands the no-game application to the OS and leaves Broomm
visible and navigable. It retains no emulator process, output subscription,
readiness/exit polling or game-active state, does not restore focus on exit,
and does not require that app to close before Broomm quits. Repeated activation
coalesces only a pending launch request; request failures are visible and allow
retry. Private profile settings and all gameplay supervision remain unchanged.

Complete macOS bundles use Launch Services with literal arguments and explicit
private environment values; the portable melonDS executable uses detached
startup. Azahar 2126.1.2 warns when its parent is not PID 1 and recommends opening
its app bundle. Its actual corrected launch has parent PID 1. Existing native
interop acquires both file locks inside the independent configuration process,
refuses conflicts nonblockingly and applies the existing private write policy
through the macOS sandbox API. No emulator monitoring or new dependency/service
is introduced. Installer-only lock and RPCS3 teardown behavior are preserved.

Analysis and all **421 Flutter tests** pass. Three UI/model regressions cover
window/session/shutdown behavior, retry and pending-request coalescing. Native
fixtures verify private writes and coordinator conflicts/linked paths; the latter
uses a held production lock plus a successful unlocked control. The four native
configuration tests also pass under UBSan trap instrumentation, and Clang static
analysis reports no findings. Five existing native installer regressions pass
independently. Real Azahar, PCSX2, ARMSX2 and PPSSPP apps open in disposable
profiles, with Launch Services parenting and actual native lock ownership
verified through read-only POSIX queries. Other emulators/hosts, camera behavior,
gameplay and owner visual/controller acceptance are not newly established.

The fresh universal macOS package is
[Broomm-macOS-independent-emulator-launch.zip](build/releases/Broomm-macOS-independent-emulator-launch.zip),
**20,480,144 bytes**, SHA-256
`efc4bef497e693c297e4d52efd7770af77473101ce809519905f6ed017c9b4c4`.
ZIP integrity, source/fresh-extraction deep/strict/all-architecture signatures and
exact guard readbacks pass. It uses production Application Support storage,
ad-hoc signing and disabled development self-installation; no owner or RomM
progress was modified. Paused Astris/Citra MMJ/default-selection work remains
excluded. See [walkthrough and evidence](docs/emulator-opening.md).

## Android parity investigation — 2026-10-30

The owner requested investigation before implementation after finding Android
cloud progress unavailable in practice. The [per-app audit](docs/android-parity-audit.md)
covers all nine Android adapters, source-level storage/provider access, save and
state formats, CIA/WAD/NSP installer boundaries, BIOS/firmware provisioning,
APK acquisition and ARMSX2 package variants. It distinguishes the four existing
unverified save routes from missing integrations and does not count downloads or
launch-only support as parity. Stable-folder profile swaps and device acceptance
are proposals; no behavior, dependency, emulator installation or user progress
was changed by this audit. Android runtime verification remains outstanding.

## Android APK installation and connected saves — 2026-10-30

The owner authorized APK acquisition/detection and reliable save folders, and
accepted explicit save/close confirmation on returning from an external app.
The [walkthrough](docs/android-installation-and-saves.md) documents the exact
one-time setup for all nine adapters and the remaining native prerequisites.
ARMSX2 detects `com.armsx2` and `com.armsx2.nightly`, preferring enabled stable;
recovery and folder identity retain the original package. Official APK downloads
have bounded redirects, progress, cancellation and partial-file cleanup before
Android's installer confirmation. DuckStation retains its official store flow;
PPSSPP Gold is detected without downloading a paid entitlement. Actual package
readback, rather than installer handoff, establishes success/default selection.

One stable folder per emulator/package serves every Broomm profile. Disposable
setup probes verify writable replacement. Private working/original snapshots,
durable journals and checked publication isolate each profile/game while
preserving standalone emulator data. All nine adapters now resolve ordinary
saves, with matching states for the eight apps that provide them. APK/ABI/core
identity separates both local and remote state groups; cached fingerprints avoid
rechecking unchanged APK/core bytes on every launch. Ambiguous console identities,
paths outside the grant and changed external data fail without adoption. Legacy
MMJ journals remain recoverable; unprovenanced legacy states stay local.

Returning offers **Finished? Sync progress**; explicit confirmation is enough
without emulator-process checks. Broomm still serializes its own transfers.
Offline capture uses existing sealed cloud pending data and BROOMM history.
Restart recovery can reconnect the original revoked folder or explicitly finish
without further native writes/upload, preserving recovery copies. New Play
requires a connected save folder instead of silently starting local-only.
BIOS/firmware provisioning and new content installers remain later work. No
additional Wii update integration is required; existing desktop WAD/DLC remains.

Analysis is clean; all **455 Flutter tests** pass, including **35 focused Android
cases**. All nine Kotlin files compile against the pinned Android/Flutter APIs;
only two existing `versionCode` deprecation warnings remain. These checks include
controlled real Dart files/cloud history and recovery, not native Android SAF or
emulator execution. No APK was built and no Android device was available. No new
runtime dependency or OS package was installed, and production/RomM progress was
not modified. See the [evidence record](docs/android-installation-and-saves.json).

The fresh universal [macOS build](build/releases/Broomm-macOS-android-saves.zip)
is **20,613,929 bytes**, SHA-256
`f17604056100722f17096b6e62d4f25d321cac19f5a76e2d16da44409954a3a6`.
Version **0.1.4 (1006)** uses production Application Support storage. Archive
integrity and source/fresh-extraction deep/strict/all-architecture signatures
pass; all seven Mach-O payloads contain ARM64 and x86_64. The build is ad-hoc
signed, not notarized, and does not establish Android device acceptance.

## Windows test fixture portability correction — 2026-10-30

The owner-supplied Windows log for `d870e0a` exposed four MMJ fixture failures
and one Astris assertion failure. Fake Android inventory keys used Windows
separators; a native package filename assertion assumed POSIX separators. Both
fake providers now use decoded URI segments, retained-file checks use URI leaves,
and the Astris check verifies the exact owned directory URI plus file existence.
No application behavior or production validation changed.

Three new portable cases exercise drive-letter and UNC Windows paths, encoded
names, POSIX names and rejection boundaries on every host. All **33 affected
tests** and **458 total Flutter tests** pass locally, with clean analysis and
formatting. Native Windows execution remains owned by its existing CI job; local
macOS success is not Windows acceptance. No retries, skips or timeout increases
mask the supplied failures. See the [diagnosis and reproduction](docs/github-releases.md#android-provider-fixture-corrections--2026-10-30)
and [evidence](docs/windows-test-paths.json). The runtime sources and verified
[macOS package](build/releases/Broomm-macOS-android-saves.zip) are unchanged.

The native `d314d27` follow-up still reports Windows failure, with full-size save
checks passing. Detailed log access is unavailable through the normal repository
credential helper. CI now retains Flutter JSON reports and emits bounded public
failure annotations with its built-in GitHub reporter plus a small SDK-only
reader. A deliberate failure preserves exit status 1; all **461 tests** pass
locally with the new reporting path. Three reader regressions, analysis,
formatting and workflow lint pass. No unidentified Windows failure is treated
as fixed by that local result; the next native run owns that evidence.

The `1d4b545` diagnostic run exposes two MMJ capture/recovery failures at Windows'
directory-enumeration path limit (276 characters), with the original separator
failures absent and full-size saves/native updater passing. The checks job now
uses the runner-owned short `TEMP`/`TMP`, with a shorter MMJ fixture prefix;
the observed deepest listing becomes 252 characters. This affects test scratch
storage only, without system changes, relaxed validation or larger timeouts.

Windows run `8b6ea59` has no remaining MMJ failures; full-size saves and the native
updater pass. It exposes one artwork-fixture cleanup failure from a live file
image. Teardown now finishes decoding, unmounts, clears cached/live streams and
pumps their disposal frame before deletion. Both new visible/cache-only file
regressions fail with the old cleanup and pass with the fix; all six artwork
cases pass locally. Production application sources remain unchanged.
