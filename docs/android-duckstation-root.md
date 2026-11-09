# Android DuckStation root integration

2026-11-08. PSP acceptance is complete and PR #5 merged as `d30d5dd`.
DuckStation is the next standalone increment. This document separates the
implemented read-only diagnostic from the save-writing work still required.
The existing connected-folder adapter remains separate.

The subsequent [transaction implementation](android-duckstation-transactions.md)
now adds private cards/states/preferences, durable recovery, BIOS provisioning
and removal backups. Native mechanism tests pass; packaged two-account game
acceptance remains pending. The earlier sections below retain their original
research/acceptance scope and do not establish that later integration.

## Implemented: initialized app-files inspection

The global **Emulator Settings → Inspect root access** diagnostic inspects
DuckStation's app-private external files for Android user 0. It verifies the
exact `/storage/emulated/0/Android/data/com.github.stenzek.duckstation/files`
path against its `/data/media/0/Android/data/…/files` mirror, including device,
inode, UID, GID, permissions and SELinux categories. It also requires a regular,
singly linked, bounded `settings.ini` with the corresponding ownership/label
and stable metadata. It never reads settings contents. Unavailable, changed,
foreign, permissive or incomplete observations fail visibly, without treating
them as an empty directory or creating a save connection.

The fixed command keeps the existing 30-second deadline, 16-KiB output bound,
cancellation and before/after package-identity checks. Paths are stdin data,
not interpolated shell source. Dart validates the native response against the
selected app/user and presents an immutable snapshot. The diagnostic explicitly
says selected save folders and their contents were not inspected. No native
settings, folder choices, saves or Broomm bindings are changed.

On the Thor (Android 13/user 0/Magisk 31.1), direct execution of the production
script and parser passed: UID 10137, external GID 1078/mode 2770, matching media
mount device 65038/inode 27858, initialized settings 9,913 bytes. Native settings
SHA-256 remained `7f554e69e299de15d9339aacd4e635675f30f14c36673f61dac5ca993e3edab7`
with identical metadata before/after. These values are evidence, not constants
for other installations. The first CLI fixture timed out because `adb exec-out`
does not forward host stdin; piping the same request on-device corrected the
test transport. Production Android stdin handling was unchanged.

Eleven focused Flutter cases pass, including DuckStation response immutability,
foreign package/user refusal and the visible save-folder boundary. Kotlin/JVM
subprocess regressions pass for initialized metadata, unavailable/truncated
observations and ownership/path/mount/file refusal boundaries. Full Android
bridge compilation and targeted Dart analysis pass. Full CI for `7fc0e8f` passed
all platform checks and five packages. Its retained-key build **1118** passed
the complete in-app diagnostic on the Thor, including app-files metadata and the
explicit save-folder limit. Native BIOS/settings bytes and metadata were identical
before/after inspection. Both saved accounts restored normally without passwords
or credential export. The repeated audits preserve both PSP private inventories,
backups and primaries 255/257/260/259, all 49 earlier RetroArch progress files,
nineteen managed native files, thirteen original files, four retained VMUs,
fifteen cores and eighteen bindings. The data-preserving upgrade retained Broomm
UID 10134 and its exact emulator-settings hash. This does not establish
DuckStation save synchronization.

## Native build and first-run research

The official [Android beta page](https://downloads.duckstation.org/android-testing/)
describes the Compose rewrite and warns that it is beta software. Its versioned
2026-11-08 APK is `downloads/duckstation-12126.apk`, version
`0.1-12693-gcc4a0d678`/12126, 112,478,343 bytes, SHA-256
`3e944243fa6d201d2c2c935f1a1b104fe7e2696c6f2a6b3d719fa212660d73f7`.
Package: `com.github.stenzek.duckstation`; signer SHA-256:
`a6357957d296b3b03edeb62da317cb347ecde63b6577977ffcbfe0d9a6975450`.
Its native emulator libraries contain ARM64, ARMv7 and x86-64 ELFs; an unrelated
x86 AndroidX library does not establish x86 emulator support. Archive inspection
confirms exported MainActivity/EmulationActivity. DEX strings alone do not prove
that the existing `bootPath`/`resumeState` handoff is consumed.

The beta was downloaded locally for authorized device research, installed fresh
and initialized through its normal UI. No APK is committed or bundled; upstream
prohibits redistribution and asks that download links target its page. Broomm's
existing store/manual-APK route is unchanged. The native UI detected **Odin
Controller** and completed automatic mapping. BIOS import and game folders were
skipped; optional RetroAchievements was left disabled without an account.

The native Folders page shows default app-private `memcards`/`savestates` paths;
the initialized INI has no Folders override and Card1Type is PerGameTitle.
Folder relocation was not used. Its experimental move/copy feature is not a
proven account-isolation mechanism.

Native research subsequently copied the existing Mac RomM Mega Man X4 CHD
(6583, 380,622,493 bytes, SHA-256
`eed3c1dd60fe4959f61c428870b4ae6cbeb22f16a2e5f7ea902ca0c6334f5ba1`)
and BIOS into a new disposable Thor Download folder, without copying progress or
credentials. Broomm also downloaded that game through its normal Store.
DuckStation's own importer recognized the BIOS as `ps-22a.bin`; SHA-256:
`71af94d1e47a68c11e8fdb9f8368040601514a42a5a399cda48c7d3bff1e99d3`.
Android's Downloads provider stalled listing the test folder; external storage's
provider worked. Native document-picker boot rendered the intro/title and
automatic demo for `SLUS-00561`. Native Slot 1 produced
`savestates/SLUS-00561_1.sav` (1,339,224 bytes,
`d5a177e7edfbd629f1b9f75141b6c132bedb2c87d98c02be45bd1a81959e5578`).
Normal Close Game retained a distinct `_resume.sav` and removed the emulation
activity while core/video/CDROM threads remained alive. Ordinary saving,
interactive gameplay and physical input are not yet accepted. All native test
states remain unassigned; no Broomm PS1 session or cloud publication occurred.
Injected ADB observations do not establish owner visual verification.

## Fresh-boot handoff correction — real-provider failure and correction

The exact APK was inspected privately with Android 13's preinstalled `dexdump`;
no decompiler dependency, APK redistribution or copied upstream implementation
was introduced. The activity reads `bootPath` and `saveStatePath`. The old
`resumeState` extra is absent from its reader. Its document picker translates
URIs into native `/android_content/` or `/android_content_id/` paths.

A valid state reached the title through an external intent, but the missing-state
control exposed a different failure: fresh ROM access rejected the raw content
URI. A state can restore its own media path and mask this broken handoff. The
translated external-storage path boots without a state and avoids that error.
These are native external-provider observations, not Broomm provider acceptance.

The adapter now selects the translated contract only for the inspected version
12126/name/signer. It gives the game's existing read-only capability a document
alias, with the same token, file allowlist and owned-library checks. Exact file
metadata reports no write/delete/rename/folder capability. Related known files
receive individual grants; release revokes document aliases and legacy paths.
Other builds/emulators retain their existing handoff. A mismatched 12126 identity
refuses before granting access. No save-folder connection is added. Kotlin/JVM
regressions cover corresponding aliases, Unicode/space names, malformed paths,
boundary refusals and version/signer selection; bridge compilation passes.
Full CI for `457c8e1` passed all checks and five packages. Its retained-key
build 1119 upgraded with the same app UID and emulator-settings hash. An isolated
ARM64 development fixture replaced only the Dart entry point, retaining all
native/manifest payloads from that package. It used the real installed-game
receipt, session lease, emulator adapter and read-only provider, without reading
credentials, starting a profile/cloud session or capturing saves.

That real-provider test failed fresh boot. The regular translated path calls
`DocumentsContract.isDocumentUri`, which requires a registered document provider;
the generic content provider's document-shaped alias is insufficient. Native
APK inspection confirmed this branch, consistent with the
[Android document contract](https://developer.android.com/reference/android/provider/DocumentsContract#isDocumentUri(android.content.Context,%20android.net.Uri)).
An opaque-ID path opened the CHD but then treated it as the optional `.sbi`
sidecar: changing only the display-name suffix left the underlying document ID
unchanged. That route was rejected. Neither failure is accepted gameplay or
state compatibility.

The correction adds a separate `DocumentsProvider` at `.games.documents`,
protected by `MANAGE_DOCUMENTS` and exact temporary read grants. It advertises
no roots, directory access, writing or mutation. Both providers consume the same
token/manifest and owned-library resolver. Native related-file resolution can
now change the actual document-relative name; missing or ungranted files fail
instead of substituting the ROM. Existing emulator URIs keep their original
provider. See the [provider API contract](https://developer.android.com/reference/android/provider/DocumentsProvider).
JVM regressions cover exact ROM/sidecar correspondence, ungranted and missing
sidecars, and refusal of the generic authority for this launch contract.
Full CI for `1aa3fe1` subsequently passed all checks/five packages. Retained-key
build **1120** and its isolated ARM64 fixture preserved UID 10134 and exact
Broomm emulator-settings bytes. The real provider booted the installed CHD
without a state and rendered the opening sequence. Exact document metadata
reported 380,622,493 bytes, octet-stream MIME and flags 0. Native Save State
created the previously empty Slot 2; Slot 1 stayed identical. Normal Close Game
returned to Broomm. Production grant release emptied its records and revoked
all game URI permissions; the next fresh boot received a different token.

Loading Slot 2 then warned that its saved CD-image path could not be opened and
that using the current disc might be unstable. Its header contained the first,
revoked token. This is a failed state-portability check, despite successful
fresh boot. It must not be accepted as reliable state replay.

Build 1121 derived a stable, versioned document-set identity in Dart
from sorted relative resource names, sizes and actual SHA-256 digests. Absolute
device paths, local server/game/profile IDs and enumeration order are excluded.
The native reviewed-version adapter requires that identity before creating any
grant. Access is still temporary: release revokes permissions and clears records;
only a newly authorized matching content set restores the same resource names.
The read-only worker has cancellation, a five-minute operation deadline,
file/count/byte bounds, progress feedback and before/after filesystem checks.
There is no new dependency, persistent URI-access registry or credential read.
Host regressions covered release/relaunch, different device/library IDs, content
replacement with preserved size/modified time, foreign/missing/linked resources
and cancellation before native handoff. All CI checks and five packages passed
for `88830f3`. Its isolated ARM64 fixture passed fresh boot and saved previously
empty Slot 3. Normal Close Game returned to Broomm; production release cleared
all manifest records and game URI permissions. After a Broomm restart and fresh
launch, loading Slot 3 replayed the opening sequence without the earlier expired
media warning. The same stable token appeared in its native state header.
Slot 3 was 848,090 bytes, SHA-256
`c1e05fed4dc07e49adc1e3edb70706feb6bdfc8aad0215a767edf0d023816b60`.
Slots 1 and 2, native settings and BIOS stayed unchanged; native Close Game
naturally replaced its resume state and updated playtime. All temporary grants
were cleared again. This accepts the native document/state-reference handoff,
not Broomm cloud synchronization, ordinary saving, scored gameplay or physical
input. All three native slots remain unassigned.

The ordinary retained-key build **1121** was restored. Its UID and Broomm
emulator settings stayed unchanged. Both saved accounts restored normally
without passwords/credential export, and the Thor returned to its owner profile.
Repeated PSP/RetroArch audits preserved both private PSP inventories/archives
and checkpoints, 49 earlier progress files, nineteen managed native files,
thirteen original files, four retained VMUs, fifteen cores and eighteen bindings.

### Current correction: use the installed publication identity

The digest implementation read the 380,622,493-byte ROM on every launch, taking
4,875 and 4,871 ms on the Thor. Although the state-reference check passed, this
violated PROJECT.md's prohibition on launch-time ROM checksums. It is replaced
with a versioned identity from the existing installed publication record:
RomM ROM ID, platform, release filename/revision, sorted relative filenames and
published sizes. Absolute device paths, local server/profile IDs, publication
time, display titles, optional download-checksum preferences and enumeration
order are excluded. The receipt must belong to the exact owned game and agree
with every granted regular file and observed size. Missing, linked, duplicate,
foreign, changed or incomplete observations refuse before native launch.

Only the bounded receipt is read; payload access is metadata-only. This is the
identity of Broomm's immutable managed publication, not fresh proof of ROM bytes.
Download verification remains a separate operation. A same-size out-of-band
edit of a private managed payload is not detected by this check. No checksum
cache or new persistent access registry is introduced. Cancellation, a 30-second
deadline and file/count/byte/path bounds remain. Forty-two focused Flutter cases
and analysis pass, including a file boundary that rejects all ROM reads,
release/relaunch and another device's local IDs, changed release identity,
publication mismatches and cancellation. The initial test command mistyped a
nonexistent session test path; correcting it to the existing emulator/session
file passed without changing assertions. The full source suite passes 750 tests
with one existing host skip. All CI checks and five packages passed for `fef7564` (run 42528636639). The retained-key
normal build **1122** and isolated ARM64 fixture preserve all 160 normal app
payloads and 159 unchanged fixture payloads respectively; the fixture replaces
only its Dart entry point and never starts a profile/cloud session.

The actual provider booted the installed CHD, created previously empty Slot 4,
and closed normally. After complete grant-record/URI-permission revocation and
a Broomm restart, fresh launch and native Slot 4 replay succeeded without the
expired-media warning. The stable publication token matched its saved header.
The metadata-only preparation took **4 ms**, then **3 ms** (receipt phase 1 ms
in each), rather than the earlier whole-ROM scan's roughly 4.9 seconds.
Slot 4 was 926,103 bytes, SHA-256
`aae6e442fd44092ea067feed099c0b3025745aef547c70522a534412b646c27e`.
Slots 1–4 remained byte-identical across replay. The resume state/playtime
naturally changed during normal native closure. All temporary access was revoked
again; no PS1 cloud publication occurred.

The separate injected Start/touch-input observation did not conclusively reach
interactive gameplay. A touch-layout toggle added only
`TouchscreenController/AnalogControllerLayout=Digital`. That known research
change was detected by the preservation check, then the normally closed
research cache was stopped after a fresh exact-build status observation and the
original INI bytes/ownership/label were restored and verified. All four native
slots stayed identical. A temporary ADB transfer initially succeeded with empty
stdout; replacing the incorrect output-string assumption with checksum readback
completed cleanup. No unrelated preference, save or credential was changed.
This manual research cleanup is not production settings-loan acceptance.
The normal build 1122 was restored. Both saved accounts restored through the
ordinary chooser without passwords or credential export, then the owner account
was restored. Final audits match the accepted PSP inventories/checkpoints and
all 49 earlier RetroArch progress files, nineteen managed files, thirteen
original files, four retained VMUs, fifteen cores and eighteen bindings.
See [the scoped device acceptance](android-duckstation-thor-handoff.json).

Both fixture sessions ended through native Close Game; all temporary game grants
were cleared and the regular build 1120 was restored. Native settings and BIOS
hashes and both Slot 1/2 files remain unchanged. Advanced-settings visibility
was restored after UI research; native settings bytes stayed identical, although
the app atomically replaced its settings inode. At that checkpoint no logging preference had changed.
The Compose advanced screen did not expose the logging controls investigated.

The APK also shows that base settings load once into a retained interface and
save when MainActivity pauses. Replacing `settings.ini` beneath a cached process
cannot be assumed to redirect the next game and risks a later rewrite. Do not
copy PPSSPP's settings-loan design without verifying this app's actual reload
and shutdown contract. Threads alone cannot establish live gameplay or complete
writer shutdown here.


## Native shutdown research — not a production proof

With its game normally closed and all slot hashes verified, the already closed
research process was stopped and confirmed absent. A retained owner-only backup
protected the original INI. Only `Logging/LogToFile` and `LogFileTimestamps` were
temporarily enabled. A native-picker boot then closed through normal Close Game.
The diagnostic showed resume-state compression and `Host::OnSystemDestroyed()`,
followed by surface/activity destruction. It also confirmed the selected
per-title card name `memcards/Mega Man X4 (USA)_1.mcd`, although no ordinary card
file had been created. This is a selected path, not accepted ordinary saving.

After normal closure the research process was stopped, the original INI bytes,
UID/group/mode/label were restored and verified, and only the newly created
research log was removed from the native app folder. The complete diagnostic
remains private. Slots 1/2 stayed identical. Subsequent provider tests ran with
the original logging preferences; no research logging remains enabled.

The [public core implementation](https://github.com/stenzek/duckstation/blob/master/src/core/system.cpp)
queues asynchronous state writes. Its ordinary destroy path does not alone
establish that the write queue has joined. Exact correspondence between that
public revision and the inspected Android beta has not been established.
The observed system-destroyed callback, cached PID, retained Core/Video/CDROM
threads or disappearing activity must therefore not authorize save capture or
settings replacement. Verify the exact native/frontend flush and settings
reload contract first. No root save-writing adapter is enabled by this evidence.

## Exact-build writer observations — research only

The exact APK registers a native `flushSaveStates()` method. Its Android
application lifecycle observer saves base settings then calls that operation;
MainActivity also saves base settings synchronously when pausing. Inspection of
the ARM64 JNI registration table and implementation identifies two fixed status
fields: the session-state byte consumed by `isSessionValid`/`isSessionPaused`,
and the outstanding-state-write counter waited on by `flushSaveStates`.
The native ARM64 ELF SHA-256 is
`46435267ea46ae686561dcb4f03e6063d58debe135174056d3dc408896156d73`.
The exact public core commit named by this beta was unavailable (HTTP 404), so
public-master behavior remains a separate comparison.

A bounded on-device prototype verified the installed APK hash, exact mapped ELF,
UID, command name and process start ticks before/after reading only those five
non-secret bytes. It did not scan a heap, read settings/saves/credentials, inject
code or write process memory. Actual observations were running=2, paused=3 and
normally closed=0, with zero outstanding state writes at each observation.
The closed cached process survived until explicit research cleanup. These
observations do not test a held nonzero writer, process-replacement races, all
memory-card writer paths, other ABIs or a production settings-reload workflow.
No such memory probe is shipped or used to authorize Broomm save changes.

A concrete next design can bind narrow status reads to this exact APK/ELF/ABI,
while refusing unknown layouts and retaining normal recovery. This avoids
log-level changes but requires a new reviewed layout for every native build/ABI.
A logging-only alternative needs verified completion events and changes to
native logging preferences; the system-destroyed line alone is insufficient.
An emulator fork/injection would add a different maintenance/licensing burden
and does not fit the current external-app scope. These are investigated
tradeoffs, not implemented save writing or acceptance of a new dependency.
Before cache disposal, prove current preferences have been saved as well as
all game writers having finished; never replace the retained INI under a live
cached settings interface.

## Required before root save sessions

Real document boot and native state-reference replay are established above.
Verify production native shutdown/writer evidence on this exact APK with the
retained RomM-sourced BIOS/game. Determine how settings overrides,
whole cards, per-game preferences, resume/global undo and state filenames are
actually consumed. Design a concrete Dart-owned private profile/game workflow
with durable settings loans and original-data restoration; do not infer these
contracts from PPSSPP's memory-stick selector. Keep achievements/credentials
and unrelated native content out of game exports. Bind states to actual native
APK/ABI/game revision. Finish two-account ordinary/state, offline, recovery,
removal/reinstall and earlier-emulator preservation checks before claiming
DuckStation root sync or proceeding to another save-writing adapter.

## Diagnostic walkthrough

Install/open DuckStation, complete first run and wait for its main menu. In
Broomm choose **Emulator Settings → Inspect root access → DuckStation → Request
root inspection**, allowing the root manager if prompted. Expect **Read-only
inspection completed**, app-files metadata and the explicit save-folder limit,
or an actionable initialization/identity error. Close the dialog to discard the
snapshot; no file cleanup is needed. A cached native process is not closure
proof for future save operations.

```sh
devbox run -- flutter --suppress-analytics test --no-pub test/android_root_inspection_test.dart test/android_duckstation_documents_test.dart test/android_emulators_test.dart
devbox --config tool/android run check-root-inspection
devbox --config tool/android run check
```

The JVM checks emit disposable test JARs under `.tool-cache/research/android`.
They are development artifacts, not shipped runtime dependencies. Removing that
cache cleans them without changing emulator or game data.
