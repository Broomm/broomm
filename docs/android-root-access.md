# Android root inspection and first save target

Current Broomm syncs only ordinary in-game saves. Save states remain local.
Earlier state-transfer observations describe their tested builds. See the
[current save contract](slotted-saves-and-ps3-iso.md#save-states-and-recovery).

## Rooted GBA route: implementation and validation status

Current source also adds rooted SNES/Snes9x and save states for both systems.
See the [new implementation and device checks](#offline-profiles-rooted-states-and-snes--2026-11-07).
The build-specific evidence below remains historical until the new APK is tested.

The owner approved libsu 6.0.0 core/service for the narrow privileged file
adapter. The first route now connects **GBA/mGBA ordinary saves on Android user
0**; other rooted emulator/user combinations remain unsupported. Read-only
inspection is independent. The actual mGBA core, external configuration and
owner-created Minish Cap save have been identified on the Thor. Native file
primitives pass isolated device tests. The owner confirmed the packaged Binder
connection in build 1038 after reopening Broomm, followed by gameplay and save
upload in builds 1042 and 1043. The owner confirmed loading an older Minish Cap
save before PR #1 merged. Automatic mGBA setup is the follow-up below.
Build 1054 subsequently passed the [root reliability checks](android-root-reliability.md)
for offline capture/reconnect, interrupted and revoked-root recovery, a real
remote conflict, and exact original-save restoration. That record retains the
remaining account/offline-activation limits separately.

1. Choose **Emulator Settings → Game Boy Advance → RetroArch → Set up**.
   Setup guides installation if the app is missing. Accept Android's installer
   confirmation.
2. Allow Magisk if asked. Broomm reuses or installs mGBA and connects GBA saves.
   If prompted, choose **Open emulator**, complete RetroArch's first open,
   wait for its main menu and quit it. Broomm checks closure and resource
   readiness on return before confirming setup. The existing shared-folder
   connection remains available to other systems. Root denial leaves a visible
   retry and **Use shared folder** option.
3. Install the selected GBA game from your RomM account. With RetroArch closed,
   choose the game on Home and press **Play**. Broomm checks closure and verifies
   package/user/signer/build identity, checks cloud progress and prepares a
   separate game/profile save directory plus session configuration under
   `/data/user/0/<retroarch-package>/files/Broomm/<profile>/<content>`.
4. Save in-game, choose **Quit RetroArch**, and return to Broomm. A verified
   normal exit starts sync automatically. If RetroArch is still running, choose
   **Return to emulator** and quit it there. For an uncertain or interrupted
   exit, use **Review and finish session** after quitting. The existing Dart
   workflow captures progress, synchronizes the selected
   account's BROOMM history and restores the session directory's pre-launch
   contents. The ordinary standalone `RetroArch/saves/mGBA` file is untouched.
5. For acceptance, retain the earlier history, create an independently changed
   save, use Broomm's existing history restore flow, relaunch and verify the
   earlier in-game position. Denial, lost connectivity and conflicts must retain
   progress and offer recovery.

Recovery copies/journals remain in Broomm's private
`files/broomm/android/shared-session` and `shared-swap.json`; the session marker
is `android/session.json`. Do not clear Broomm data, remove its root connection
or delete emulator session directories while recovery is pending. Generated
session configurations and interrupted private stages can remain as evidence;
cleanup is not part of a failed transaction. If an installed working save is
missing at capture, Broomm retains recovery and refuses to publish empty progress.
No standalone save is auto-imported.
The first rooted route handles ordinary saves.

### Automatic mGBA setup

The follow-up uses the existing Android APK install flow and root binding.
Broomm verifies that the selected RetroArch package is closed, reads the actual
frontend ELF ABI and reuses an existing compatible mGBA core. If absent, it
downloads one ZIP, validates the archive and extracted library against the
reviewed SHA-256 values, and asks the bound root service to publish it at
`cores/mgba_libretro_android.so`. The native service verifies package identity,
core ABI, staged checksum and owner, then publishes with exclusive file creation
and readback. A retry can recover an interrupted publication without replacing
an existing compatible core. **Cancel download** discards Broomm's staging.

The source is [Libretro's Android core Buildbot](https://docs.libretro.com/guides/download-cores/#installing-cores-manually)
and the [Libretro mGBA port](https://github.com/libretro/mgba) under MPL 2.0.
The reviewed archives were fetched on 2026-11-06 from
`nightly/android/latest/<abi>/mgba_libretro_android.so.zip`. Their embedded
version is `0.11-212-7a12d6d`, corresponding to source commit
`7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6`. The original unchanged ARM64,
ARMv7, x86 and x86-64 ZIPs now live in
[`vendor/android/mgba/0.11-212-7a12d6d`](../vendor/android/mgba/0.11-212-7a12d6d/README.md)
with the MPL license, exact source link and provenance. The downloader uses
Broomm Git commit `c6156ac820604feff1f5a51da1081e3dbce66e64` through
`raw.githubusercontent.com`, giving the recipe an immutable URL for each ABI.
These vendor files are downloaded during explicit setup and excluded from
Flutter's bundled assets. Both ZIP and core checksums remain pinned. An
existing compatible core is reused.


Broomm hands the official APK unchanged to Android's installer. The Thor's
installed 183,956,821-byte arm64 APK matched the official 1.22.2 Buildbot
download (SHA-256
`7bd5d208dfe93cc8e2ea6c04608948ce1a045980f160a58ca2d0993aa20ad213`).
It contains menu assets, Android controller profiles, databases, filters,
core information, overlays and shaders. Opening
[RetroArch's normal Android launcher](https://github.com/libretro/RetroArch/blob/v1.22.2/pkg/android/phoenix/src/com/retroarch/browser/mainmenu/MainMenuActivity.java#L188-L203)
triggers extraction under RetroArch's own UID. Direct gameplay with build
1052 had an empty standalone configuration and missing menu files. Its private
controller fallback worked on the Odin, but the owner reported missing menu
icons and a pixelated font.

During Setup and before direct play, Broomm checks for the default
Ozone menu fonts and settings icon. If the APK includes them and the stock
copies are missing, it offers the standard launcher. After first open and
quit, **Check and play** rechecks closure and the files. This check runs
before a game journal or save sync. Broomm preserves a configured custom
assets directory. The separate controller fallback still handles APK layouts
whose default profiles are unavailable, subject to the user's input
preferences. From a clean install, verify the settings icons and Back in
Minish Cap, then save and quit to verify sync. Repeat setup with mGBA already
present to verify the core is reused.

### Verified closure

The rooted route checks the selected Android user and package UID for live
processes before save preparation and launch. A bounded observation after
handoff records the launched process's PID, kernel start time, and monotonic
and wall-clock observation times for the current Broomm activity. On return,
the root service checks Android 11 or later's exit history for a single fresh
record matching that process. A normal self-exit with status zero plus a
fresh check for live writers enables automatic sync. An unavailable probe,
an app restart, an ambiguous record, or an abnormal exit leaves recovery
available. Manual recovery also refuses to proceed while a writer is detected.
No process is stopped by Broomm. The unrooted folder route still uses explicit
closure confirmation.

## Root connection reuse — 2026-11-06

The owner confirmed gameplay and sync on the Thor with build 1042. The
completed Minish Cap journal records an 8 KiB working save with SHA-256
`8aeee69c1208bee1dc705e799472f31f84ec80e6782b6f07e40c4d4baf70274b`
and a changed capture with SHA-256
`a779acffbbecf4015fbc7a2fd644ce9c9653662153561cae4e597ad2793b1b23`.
The RomM log records uploading and verifying save 199. Broomm restored the
original emulator file, removed the staged ROM and cleared the active journals.
The separate standalone save retains its original hash. A later in-game load
of save 199 remains unverified.

The owner saw a Magisk notification at each root call. Build 1042 opens a fresh
shell and binds for every file operation. The follow-up acquires root on the
first requested save action and keeps the normal libsu connection while
Broomm's activity remains alive. Switching to RetroArch and returning uses the
same binding. Root I/O still runs only on request with the existing package
checks, deadline and lock. Closing Broomm releases the binding. A lost binding
fails the in-flight operation, leaving a subsequent user retry to reacquire
root. The separate read-only **Inspect root access** button remains a diagnostic.

The owner confirmed that repeated notifications stopped on build 1043. After an
initial permission failure, one startup served 18 successful operations through
play and sync. Broomm uploaded and verified RomM save 203, removed the staged
ROM, cleared the active journals and preserved the standalone save hash.

To check the new behavior on the Thor, open Broomm and play Minish Cap, then
quit RetroArch and confirm sync. The `BroommRoot` log should show one Magisk
permission/startup pair and reuse on the remaining operations. Completely
close Broomm, reopen it and request a root save action to verify that a new
activity establishes its own connection. Magisk controls whether it shows a
dialog or a notification. Record the actual APK and device observations before
claiming this check has passed.

## Thor launch failure — 2026-11-06

Build 1040 reached the installed RetroArch 1.22.2 mGBA activity twice. The owner
saw a black screen and an Android not-responding dialog. The device ANR report
shows the native activity thread waiting and the startup log ends after the
environment banner. Both attempts supplied a Broomm `content://` URI in the
`ROM` extra. The
[upstream RetroArch changelog](https://github.com/libretro/RetroArch/blob/master/CHANGES.md)
lists external launcher URI support as a future change relative to 1.22.2.

Broomm downloaded save 180 for RomM ROM 2338 and verified its 8,192 bytes before
handoff. The captured managed save and Broomm's working copy both have SHA-256
`8aeee69c1208bee1dc705e799472f31f84ec80e6782b6f07e40c4d4baf70274b`.
The standalone 128 KiB save retains its original hash. The first swap finished,
and a second launch left session and swap markers. No new gameplay save was
observed. Device observations are in `.tool-cache/rooted-gba/roundtrip-black-screen.json`
and `.tool-cache/rooted-gba/retroarch-anr-1040.txt`.

For rooted GBA sessions Broomm now supplies a native path in `ROM`. The
selected raw `.gba` is copied from the verified library into a transaction-specific
directory beneath the same private profile/game root as the config. The root
service rejects linked, oversized or changed files and verifies the SHA-256
before publishing the copy with emulator ownership, its security label and
read-only mode. Broomm records the intended path before copying and cleans up
the owned copy after the existing closure and save-restoration flow. If
interrupted, finish the pending session in Broomm. Earlier session journals need
no migration.

The Thor native harness verifies normal staging, refusal of an existing target,
rejection of a changed digest, partial-copy cleanup and preservation of save
data. Full launch and the save round trip still require the packaged APK check.

Build 1041 was reinstalled from the verified PR artifact. All 64 Broomm data
files were restored and checked by hash. The user reported a worse experience.
Device logs show that ROM staging failed before handoff, then ROM cleanup failed
after the save swap reached `restored`. The standalone save retained its hash.

The installed 1041 root code was exercised in a disposable profile on the Thor.
It staged and removed the ROM using its own `/data/user/0` path and the
journaled checksum, but rejected the `/data/data` spelling. Both library names
refer to the same inode. The bridge now sends the verified relative library
path, and the service resolves and validates it under its own framework
directory. Cleanup now sends the recorded SHA-256. Regressions cover both
namespace names, traversal refusal and retry after interrupted cleanup.

A separate native-path control used the real Minish Cap ROM with a disposable
configuration and save directory. RetroArch 1.22.2 loaded mGBA and the content,
initialized video and audio, and logged the isolated SRAM path. This verifies
the native-path startup independently of the Broomm APK. The owner still needs
to verify the corrected packaged launch and a new gameplay save round trip.

Run local checks with the pinned environments:

```sh
devbox run -- flutter analyze --no-pub
devbox run -- flutter test --no-pub
devbox --config tool/android run check
devbox --config tool/android run check-shared-lock
devbox --config tool/android run check-root-inspection
devbox --config tool/android run build-root-save-test
```

The last command builds an Android `app_process` test archive, not a host test
pass. D8 **9.5.29** is a development-only official Google artifact cached under
`.tool-cache/research/android`, pinned to SHA-256
`f8c762ff84640b10083b934a47278758a7665977e618fab0c927fff00521dea3`.
It is not shipped in Broomm. CI independently compiles the device harness;
physical root execution requires the explicitly selected device.
The Thor run executes the production `RootSaveFiles` and `SharedDocumentLock`
inside an exclusively created `/data/local/tmp/broomm-root-test-<nonce>` root.
It passes replacement, native metadata restoration, changed/linked-path refusal,
interrupted partial staging and exclusive publication, expiry and cross-process
lock exclusion. The fixture removes only its own temporary files. No emulator
save was mutated. Local logs/receipts are under `.tool-cache/rooted-gba/`.

## Packaged GBA connection and follow-up — 2026-11-05

Actions run [42122253927](https://github.com/Broomm/broomm/actions/runs/42122253927)
passed all checks and packages for `2efaba2`. Verified APK build **1038** was
installed on the Thor using the existing reinstall approval. Before uninstall,
a recursive inventory found no Broomm saves, session or swap journals. The
standalone Minish Cap `.srm` still matched its original SHA-256.

The owner reported repeated root-connection timeouts. Read-only diagnostics
found no libsu bootstrap file or running root service, and Broomm's workers were
idle. After the owner completely closed/reopened Broomm, connection succeeded;
the application log confirms `GBA root save connection verified` at
`2026-11-05T22:55:16.821810Z`. This establishes packaged Binder/core/config access,
not game launch or progress synchronization.

The pinned [libsu binding implementation](https://github.com/topjohnwu/libsu/blob/6.0.0/service/src/main/java/com/topjohnwu/superuser/internal/RootServiceManager.java)
records a pending startup before the root shell runs and clears it only when a
service connects. This explains the observed retry behavior after an initial
startup failure; the initial failure itself was not captured. The follow-up
obtains Magisk permission before registering a binding, requests `su -M` without
an isolated-namespace fallback, retains the shell until connection, rejects late
replies and reports the failed phase. Failed registered startups explicitly ask
for an app restart instead of repeatedly timing out. This lifecycle correction
still requires the updated APK's device regression check.

Review also found that the root service's lock differed from the existing
shared-transfer status lock and was created as UID/GID 0 (confirmed read-only
on the Thor). Both now use the existing `files/android` lock inode, initialized
by the app before root access. The old unused root lock is not repurposed or
removed. Game grants and the launch boundary now resolve the trusted framework
alias into the actual `files/broomm/library`, refusing linked descendants,
foreign/old roots and traversal. Native regressions cover the actual library,
canonical/aliased readback and rejected paths, plus both processes' lock path.
The missing-working-save regression preserves recovery instead of publishing
empty progress. Local working files also use the game identity, so two
ROMs with the same filename cannot share a save. A regression writes distinct
saves for two content IDs and a second profile, then reads each back unchanged. None of these checks establishes emulator closure; the owner
must still save and quit explicitly.

The production file adapter additionally passed publication, replacement and
restoration in an exclusively named disposable profile beneath the actual
RetroArch private root. Readback preserved UID/GID 10118, mode 600 and label
`u:object_r:app_data_file:s0:c118,c256,c512,c768`. The disposable profile and
execution archive were removed. This test used generated 128 KiB payloads;
it did not access the standalone save/configuration or RomM, and does not prove
that mGBA loaded a restored game. Receipt: `.tool-cache/rooted-gba/package-device.json`.

Final application source `bcc0f07` passes every check/package job in
[Actions run 42127441352](https://github.com/Broomm/broomm/actions/runs/42127441352).
The current PR head/merge identity, archive digest and APK size/hash were verified
before installing **build 1040** on the Thor. APK SHA-256:
`3a1ec0a07caa222566fd264ab88d117b9e578e06f9ad7ae5da63d3a54560c6c8`.
The approved reinstall preserved RetroArch; a fresh recursive Broomm inventory
contained no gameplay saves or recovery journals. Launch/save/sync acceptance
of this APK remains pending owner interaction.

## Thor Magisk namespace failure — 2026-11-05

The owner confirmed RetroArch installed successfully through Broomm build 1035
and granted Broomm superuser access in Magisk. Inspection still failed because
Android's app-private mount namespace hid RetroArch's directory, even from UID
zero. On the Thor (Android 13/user 0, Magisk `31.1:MAGISKSU`), the exact fixed
inspection script was exercised under Broomm UID 10117 and its app namespace:
`su -c` failed at the directory check; `su -M -c` returned complete read-only
metadata. RetroArch `com.retroarch.aarch64` is `1.22.2_GIT`, version code
1763607214, UID/GID 10118, mode 700, label
`u:object_r:app_data_file:s0:c118,c256,c512,c768`.

The adapter now requests the global mount namespace for this one bounded
command using Magisk's documented `-M` option. It does not change Magisk policy,
Broomm's namespace, system security, emulator files or save connections. Root
managers lacking this option fail visibly; no compatibility beyond the observed
Magisk build is claimed. Directory, root identity and metadata failures have
distinct bounded codes, logged without arbitrary `su` output. The updated exact
script returns directory-unavailable (62) in the inherited namespace and a
complete report in the global namespace. Separately, the owner confirmed
**Read-only inspection completed** in the actual Broomm **build 1036** dialog
on 2026-11-05 after requesting inspection and allowing Magisk. This is
owner-performed in-app acceptance on this Thor/RetroArch/Magisk combination;
at that checkpoint, the mGBA core, active save paths and save synchronization
were not yet verified. The subsequent GBA evidence appears below.

Evidence is under `.tool-cache/android-root-failure/`. The Thor was held by an
existing ADB server on port 5038; use the project ADB with `-P 5038 -s 1b8e0a3e`
for that session. Neither ADB nor the diagnostic changed root grants.

## Initial inspection increment — 2026-11-05

The owner selected the **Thor running Android**, using **GBA**, as the first
rooted-device save target. Broomm's existing GBA adapter selects RetroArch/mGBA.
Initial inspection implementation preceded device availability. The subsequent
Thor check above establishes Android 13, Magisk 31.1 and the RetroArch frontend
build; the mGBA core build and active save paths still require inspection.

This increment implements **read-only capability/package-directory inspection**.
It does not read save payloads or preferences, inspect/stop emulator processes,
connect a root save location or perform a save swap. Root writes remain behind
the staged acceptance gate in [the Android plan](android-installation-and-saves.md#next-milestone-root-backed-storage-access).
The existing SAF/provider workflows, durable Dart journals, standalone save
restoration, RomM profile isolation and explicit save/close confirmation remain
the implemented gameplay contract.

## Owner walkthrough

Prerequisites: an already rooted Android device, this source revision built as
an Android APK, and an installed supported emulator. A root manager that provides
compatible `su -M -c` behavior and Android's `id`, `readlink` and `stat` utilities
is required for inspection. The fixed script has device evidence on the Thor's
Magisk 31.1, and the owner confirmed the complete inspection flow in build 1036.
For the selected first test, use the Thor's existing RetroArch installation and
its mGBA core. Do not uninstall an emulator or migrate existing saves to test.

1. Open **Emulator Settings → Inspect root access** and select RetroArch if asked.
   Opening the dialog does not request root.
2. Review the selected APK package/version and choose **Request root inspection**.
   If the device's root manager asks, grant or deny that explicit request. The
   manager may remember the permission according to its own settings.
3. Expect either a visible failure or **Read-only inspection completed**, with
   device/Android/API/ABI information, Android user, package UID/GID, canonical
   data-directory path, permissions, SELinux label and signer/build digests.
   These are observations, not proof of configured save locations or access to
   every file beneath the directory. The directory must belong to that package
   and the current Android user. Other users, adopted-storage layouts and
   shared-UID packages currently fail closed.
4. **Cancel inspection**, closing the dialog or Android activity teardown
   cancels/discards the request. A root prompt is bounded to 30 seconds by the
   native operation; Dart also bounds an unresponsive channel. Retry is explicit.
   Root managers can retain their own permission prompt/process after the client
   stops; Broomm neither changes their policy nor claims to control their lifetime.
5. The shared-folder route remains available inside **Set up**. Inspection never
   changes that connection, the default emulator, working progress or cloud status.

The report is kept only in the open dialog. Operational logs contain request,
completion/failure and cancellation phases with package context, not arbitrary
`su` output, configuration contents or credentials. Existing application log
rotation still applies. No emulator data files are created, modified or removed;
no Broomm storage migration or cleanup is needed. Root-manager permission history
is external state controlled by that manager. Uninstalling/clearing Broomm data
is not a cleanup step: it would remove existing private progress/recovery.

## Access mechanism and alternatives

Research consulted on 2026-11-05:
[Magisk's documented command interface](https://raw.githubusercontent.com/topjohnwu/Magisk/master/docs/tools.md),
[libsu](https://github.com/topjohnwu/libsu),
[Android ApplicationInfo](https://developer.android.com/reference/android/content/pm/ApplicationInfo),
and [Toybox stat source](https://raw.githubusercontent.com/landley/toybox/master/toys/other/stat.c).
These are interface evidence, not Thor compatibility results.

| Choice | Fit and concrete tradeoffs |
| --- | --- |
| Existing Android/JVM APIs plus one fixed inspection command (implemented) | Adds no shipped library or transitive dependencies and no ABI-specific binary. Uses the app's existing Kotlin/Android toolchain and the device's own `su`/system utilities. Broomm owns process/output/deadline/cancellation maintenance and tests. No third-party source is copied. The command is intentionally insufficient for transactional save writes. Root-manager/tool compatibility is a runtime prerequisite, verified only when the user asks. |
| libsu core / optional service modules (not adopted) | Apache-2.0 Android library with shell and root IPC support, published through JitPack. Could reduce future shell/service maintenance, but adds a versioned shipped dependency, its module/dependency graph and distribution/licensing review, and potentially a root-service lifecycle. Java core is not tied to a particular CPU ABI; native additions would require their own architecture audit. Cancellation, outstanding work, service death and file-publication behavior still need application tests. The transitive graph and current release have not been approved or pinned. |
| Existing SAF/provider access (retained) | Already integrated with the Dart save journals and avoids root permission. Its access is limited to the granted provider/shared locations. It cannot establish private-directory access for the selected rooted route. |

`RootInspection` owns the Android package observation and platform call.
`RootInspectionCommand` is a small read-only process adapter. Dart owns the
explicit request, cancellation of late replies, report validation and UI.
The native channel has only inspect/cancel operations and an exact supported
package/launcher allowlist, including the MMJ/AnTuTu launcher distinction.
It rechecks package metadata before and after inspection. The existing build
observation includes signing certificates, version, installation time and ABI;
the report separately includes the signing-certificate digest. This is not a
new APK payload hash or a save-state compatibility group.

The process receives literal arguments `su`, `-M`, `-c`, and a constant script.
The validated package data-directory path travels over stdin and is used only
as a quoted argument. No metadata becomes shell source. Only current-user
`/data/user/<user>/<package>` and the user-zero `/data/data/<package>` alias
are accepted; canonical resolution must stay within those boundaries. Root UID
zero, directory owner, permissions and a real security label are mandatory.
Missing data/tools/labels, unexpected diagnostics, nonzero exit, partial output,
excess output and changed identity are failures, never empty observations.
Both output streams share a 16 KiB limit. Available-byte reads avoid waiting
for EOF on a pipe retained by a root-manager descendant.

No arbitrary root shell, package uninstall, policy change, ownership repair,
`chmod`, `chown`, `restorecon`, force-stop or root installation is exposed.
Preserving per-file metadata during an eventual transaction remains future
work; inspecting the directory's metadata does not implement that guarantee.

## Verification and reproducibility

Run from the project using its pinned Devbox environments:

```sh
devbox run -- flutter analyze --no-pub
devbox run -- flutter test --no-pub test/android_root_inspection_test.dart test/android_emulators_test.dart test/android_folder_sync_test.dart test/mmj_shared_saves_test.dart
devbox --config tool/android run check
devbox --config tool/android run check-root-inspection
devbox run -- flutter test --no-pub
```

The Kotlin check compiles the complete Android bridge against pinned APIs.
The separate JVM process tests execute disposable child processes on the host:
success, partial output, denial/nonzero status, secret/escape-bearing diagnostics,
bounded stdout/stderr flooding, timeout, explicitly coordinated cancellation,
missing executable and path/user/UID/label rejection. They do not invoke host
`su`, execute Android utilities or modify emulator files. Children are reclaimed
in fixture cleanup. CI schedules this check independently of other native tests
and retains its log; a hosted run is still required.

Six Flutter regressions cover explicit opt-in, complete/mismatched report
validation, late replies after cancellation, retry after denial, dialog disposal
and an unresponsive native channel. Existing Android save/recovery regressions
run alongside them. These are simulated Android boundaries, not device tests.
Local evidence and the macOS archive digest are recorded in
[`android-root-access.json`](android-root-access.json).

Build/test logs remain in `.tool-cache/rooted-android/` and
`build/android-checks/`; Kotlin scratch JARs are under
`.tool-cache/research/android/`. They can be removed after checks finish.
Keep normal profile/cloud/journal directories. Initial sandbox attempts could
not open Flutter's loopback sockets or access the Devbox Nix daemon; their logs
are retained separately. Authorized reruns used the same pinned tools outside
that restriction. An initial lint invocation used the config directory as its
working directory; the corrected invocation explicitly enters this project.

## Next acceptance gate: Thor GBA

### mGBA initialization and Minish Cap fixture — 2026-11-05

The owner downloaded mGBA through RetroArch and saved its configuration. Read-only
ADB inspection found `cores/mgba_libretro_android.so` beneath the verified
RetroArch private root: 2,472,240 bytes, SHA-256
`b5a6ed40ede735ea7f1d56916f4ceed8c2aabe4d481fe3383ae2b5e5485b6545`,
UID/GID 10118, mode 600, with the package's existing SELinux label. This is the
installed payload identity; no upstream revision is inferred from its filename.

The active configuration is actually
`/storage/emulated/0/Android/data/com.retroarch.aarch64/files/retroarch.cfg`,
outside the two private-root configuration candidates in the existing SAF
adapter. It selects `/storage/emulated/0/RetroArch/saves`, core sorting enabled,
content-directory sorting disabled, uncompressed saves, and automatic overrides
enabled. The shared save and override inventories were empty before this test.
A root adapter must inspect the real configuration and explicitly isolate its
session paths; a root grant alone cannot resolve this existing configuration gap.

The owner selected **The Legend of Zelda: The Minish Cap**, RomM ROM 2338. A copy
of the already-installed 16,777,216-byte USA ROM was staged in a new timestamped
Thor Download subdirectory, with SHA-256 readback
`bedc74df62755f705398273de8ed3bc59be610cf55760d0b9aa277f1f5035e73`.
The existing macOS save and remote RomM progress were not modified or imported.
The first launch reached an existing RetroArch menu and exited without showing
the game. The v1.22.2
[activity implementation](https://github.com/libretro/RetroArch/blob/v1.22.2/pkg/android/phoenix/src/com/retroarch/browser/retroactivity/RetroActivityFuture.java)
exits on different content delivered through `onNewIntent`; device activity logs
match that sequence. An explicit subsequent cold launch using the
[frontend startup parameters](https://github.com/libretro/RetroArch/blob/v1.22.2/pkg/android/phoenix/src/com/retroarch/browser/mainmenu/MainMenuActivity.java)
logs the correct ROM and mGBA paths. The owner then reported the test save was
created after being asked to save in-game and quit. Read-only inspection found
`/storage/emulated/0/RetroArch/saves/mGBA/Legend of Zelda, The - The Minish Cap (USA).srm`,
131,072 bytes, SHA-256
`db607737305566abae63754664bcbad987e2b002edc25f336bd93e3fe2bb7924`.
Its shared-storage view reports UID 10109, GID 1023, mode 660 and
`u:object_r:fuse:s0`; these differ from private package metadata and must not be
treated as interchangeable. No override files were present. This establishes
the first ordinary-save correspondence on the Thor. It is a CLI validation
fixture with owner gameplay, not a Broomm launch or synchronization acceptance
result. No save payload was imported, uploaded, replaced or deleted.

The owner's automatic Android core-download requirement is now explicit in
PROJECT.md. Manual core setup is temporary. No dependency or core-distribution
mechanism has been newly selected, and unattended updates remain excluded.
Local fixture metadata is in `.tool-cache/rooted-gba/device-session.json`.
Retain the test save until synchronization/restoration verification is complete;
cleanup must target only the recorded staged ROM directory and explicitly
identified disposable test data.

### Privileged file operations: approved dependency and implementation

The read-only process runner cannot safely become a write runner merely by
adding shell commands. On the Thor, Toybox 0.8.6 provides `flock` on an open file
descriptor and `dd conv=fsync`, but its `sync` has no per-file/per-directory
option. A shell implementation would need its own durable operation receipts,
permission-prompt expiry, descendant-held locks, metadata restoration and
interrupted staging recovery. Killing the Java `su` client does not establish
that a privileged writer has stopped. A local shell draft was investigated but
is excluded from application sources; no device save writes were attempted.

The owner approved **libsu 6.0.0 `service` and its `core` dependency**, using an
application-bound, non-daemon root service exclusively for narrow Android file
primitives. Dart continues to own game/profile resolution, transactions,
durable journals, cloud synchronization and recovery decisions. Do not expose
an arbitrary shell or remote filesystem API. The `nio` and legacy `io` modules
are excluded. Gradle now strictly pins the two approved modules and verifies their
reviewed POM/AAR hashes. The published Gradle module metadata has mismatched
component coordinates, so this scoped repository uses the verified Maven POMs
and explicitly ignores module-metadata redirection. License/source notices are
bundled in Android assets. This does not change desktop dependencies.

| Option | Concrete tradeoffs |
| --- | --- |
| libsu core + service 6.0.0 (approved and integrated) | Android-only Java/Binder library; the inspected AARs contain no ABI-specific native payloads. Upstream minimum API is 19, below Broomm's current Android floor. Published service POM depends only on core; core POM declares no runtime dependencies. AndroidX annotations 1.6.0 are compile-only upstream. Apache-2.0 license requires retained license/notices. Uses JitPack, adding a build-distribution endpoint that must be scoped to this group and pinned with artifact verification. Normal root services are tied to bound clients; daemon mode is unnecessary and excluded. We still implement deadlines, cancellation acknowledgments, writer locks, metadata/path validation, atomic publication and recovery, and test binder/process death. Desktop builds and their dependencies remain unchanged. |
| Own Kotlin root-process bootstrap | Avoids a shipped root library but makes Broomm maintain privileged `app_process` startup, class loading, Binder authentication, namespace selection, process/client death and Android-version compatibility. It still needs the same file-operation and recovery tests. No reduction in root authority or save-correctness obligations. |
| Own small native executable | Provides direct descriptor-relative access, atomic publication and directory flushing, with a smaller file-primitive API. Adds an owned executable distribution/build surface for each Android ABI, source/license/hash receipts, root process protocol and cancellation/lifetime handling. Broomm must maintain and natively validate that machinery. No third-party runtime library is required, but current APK packaging does not ship such a helper. |
| Extend shell commands | No new binary/library, but stronger dependence on device utility semantics and substantially more interruption/metadata/publication protocol work. Retain the current fixed shell for read-only capability checks; it is not yet a verified write mechanism. |

The latest published GitHub release observed on 2026-11-05 is 6.0.0, published
2024-06-28; this is an old release, not evidence of recent release cadence or
Thor compatibility. Tag 6.0.0 resolves to commit
`8c3e80ffe466b89ff875471e542d77e6a1b480c5`. Research downloaded and inspected
the published POMs/AAR inventories before approval:

- core AAR: 40,221 bytes, SHA-256
  `a1ca5a8adb9ab11c42b71fc2d2a61b5a95cb4cdd06df0eb8c204c06813c2bb5b`.
- service AAR: 41,331 bytes, SHA-256
  `528bbcc3f057e8b5ea6f69a2deea1e0ff536880602e99e98763d7b74cf1d0659`.

Sources: [release](https://github.com/topjohnwu/libsu/releases/tag/6.0.0),
[pinned build definition](https://github.com/topjohnwu/libsu/blob/6.0.0/build.gradle.kts),
[service build](https://github.com/topjohnwu/libsu/blob/6.0.0/service/build.gradle.kts),
[core build](https://github.com/topjohnwu/libsu/blob/6.0.0/core/build.gradle.kts),
[license](https://github.com/topjohnwu/libsu/blob/6.0.0/LICENSE),
[service lifecycle contract](https://github.com/topjohnwu/libsu/blob/6.0.0/service/src/main/java/com/topjohnwu/superuser/ipc/RootService.java),
[published service POM](https://jitpack.io/com/github/topjohnwu/libsu/service/6.0.0/service-6.0.0.pom),
[published core POM](https://jitpack.io/com/github/topjohnwu/libsu/core/6.0.0/core-6.0.0.pom).
The complete local fetch/hash receipt is
`.tool-cache/rooted-gba/libsu-research/receipt.json`.

The implementation adds a GBA-only root binding and separate session
configuration in `files/Broomm/<profile>/<content>` beneath the verified emulator
root, leaving the observed standalone shared-storage save intact. The first route
selects the exact `.srm` and reuses the existing Android session lease/Dart swap
journal. Native file primitives preserve data and metadata through failures.
Before deployment, exercise deterministic denied/delayed permission, changed
identity, interrupted publication, surviving worker and retry cases. Then build
the PR APK and perform the actual RomM upload/changed-save/restore/in-game-load
sequence. Automatic core provisioning remains the subsequent setup requirement.

Connect the Thor booted into Android over authorized USB/Wi-Fi ADB, and record
its Android user/version, root manager and RetroArch package/core builds.
ADB shell root permission is not evidence that Broomm's APK has permission.
Run the in-app inspection, then inspect the selected RetroArch configuration,
overrides and actual mGBA save-file correspondence read-only. Use a disposable
game/profile session while preserving standalone data. Only then implement the
narrow ordinary-save transfer adapter with metadata-preserving publication and
durable Dart recovery.

Before roster expansion, verify in-game save → correct account's BROOMM history
→ independently changed save → restore → in-game load. Include two profiles,
offline progress, conflicts, denied/revoked root permission, interrupted
publication and standalone restoration with matching UID/GID/mode/label. Keep
explicit save/close confirmation; directory access does not establish writer
exit. Matching state support and firmware/add-on installation are separate work.


## Offline profiles, rooted states and SNES — 2026-11-07

Implementation extends the existing user-0 libsu connection; no new runtime
library or root-manager policy is added. GBA and SNES retain separate setup
bindings alongside the existing shared-folder connection. **Set up** selects
mGBA for GBA or Snes9x for SNES, verifies the installed ABI, preserves a compatible
existing core and otherwise installs a pinned reviewed archive. Snes9x artifacts
are [versioned with provenance and license](../vendor/android/snes9x/1.63-fae2fea/README.md)
at commit `e95826b793c5f1ff07c87adef4fd4fbe2f76880f`, retained by
`android-snes9x-1.63-fae2fea`. Upstream binaries identify source
`fae2fea08f74180759ef540ee94259213f503480`; exact source and build-recipe links
are retained. All four ELF builds require only Android libc, libm and libdl; no extra runtime
C++ library is required. These are not a claim of a reproduced NDK build.

The root file boundary now includes the selected game's SRAM, states and PNG
thumbnails inside `states/states-<fingerprint>-android`. The fingerprint includes
the APK/ABI identity and exact core SHA-256. State files are bounded at 16 MiB,
128 selected files and 64 MiB per native inventory. File descriptors carry
state bytes across Binder, with app-owned regular-file checks, SHA-256/readback
and durable private capture. Configuration remains bounded at 256 KiB. Native
publication retains compare-before-write, metadata restoration and the shared
OS lock. A missing installed working save/state refuses capture and keeps
recovery instead of publishing deletion. Legacy untracked native states remain
untouched. Core changes during recovery retain the old group's native capture
without publishing it as compatible with the new core.

Saved-profile activation can fall back only on a classified transport failure
after reading a valid bound credential. Per-profile access receipts retain
online allow/deny decisions and rejected authentication. Reconnection restores
and checks the same account under the credential lock, immediately persisting
rotated refresh tokens before the identity response, then resumes pending sync.
Online rejection, TLS problems and invalid responses do not become offline
permission. While an offline game is active, reconnection waits for closure.

Walkthrough: choose the saved profile while disconnected, play and quit normally,
then reconnect using the offline icon beside the Home profile. For each rooted platform choose
**Emulator Settings → platform → RetroArch → Set up**, then **Play**. Use
RetroArch's Quick Menu to save a manual state; quit RetroArch and wait for Broomm's
confirmed sync. Launch again and load the same slot. Test restoration through
**Options → Cloud saves** while the emulator is closed. SNES accepts a single
`.sfc`/`.smc`, GBA a `.gba`; compressed/multi-file root launches are not claimed.

Private backups and verification logs for this increment live under the ignored
`.tool-cache/android-offline-states-snes/2026-11-07`. Do not remove a pending
session, clear app data or replace cores while recovering progress. Normal
successful completion restores original managed native bytes and removes its
staged ROM/configuration; Broomm's per-profile progress remains available.

Cloud regressions also cover raw SRAM plus an Android state companion, pending
retry after deleting a disposable native fixture, and retention across different
Android/frontend builds. The shared bundle/retry readers now recognize the
existing Android state-group form as well as desktop host/architecture groups.

Clean Dart analysis and all **619 Flutter tests** pass, with one existing native
host skip. The Android bridge compiles, and eight native fault groups passed on
the Thor, including a 2 MiB descriptor round trip and interrupted state publication.
CI for runtime `c614999` passed Windows, Linux and macOS checks and built all five
packages. Native behavior on other Android devices remains unverified.

Build **1057**, runtime `7908a10`, passed real ADB-controlled checks on the owner's
Thor (Android 13, user 0, Magisk 31.1, RetroArch 1.22.2_GIT arm64, RomM 5.4.0):

| Boundary | Observed result |
| --- | --- |
| Saved profile after offline restart | A UID-scoped network rejection blocked only Broomm's RomM connection. Restart and explicit saved-profile selection opened the local library and Minish Cap. |
| Offline GBA state and account switching | A real manual state survived Quit and application restart as pending. Selecting user 3 left user 2's checkpoint byte-identical. Only reselecting user 2 uploaded/read back its version 216. |
| GBA states and history | Both accounts uploaded different slot-0 states. User 2 replaced its state (217), explicitly imported the older version 216 as 218, then RetroArch loaded the earlier file-selection position. Original SRAM hashes stayed unchanged. |
| Snes9x setup | Normal Set up installed the pinned arm64 core, SHA-256 `dfd51707769000b08551e61eee4fe1a68d9e6188d62bf849c762339fa6bebcd3`, retaining mGBA and its separate binding. |
| Super Mario World | User 2's original Mario A and user 3's empty files remained separate. Both accounts uploaded/read back SRAM and distinct manual states (versions 220 and 221), then loaded their own states in RetroArch. User 2 returned to Yoshi's House; user 3 returned to the new-game introduction. |
| Preservation | The original two GBA SRAM files and user 2's SNES SRAM stayed byte-identical. All 13 pre-existing native files, including standalone configuration/core options and retained historical configurations, compared unchanged with backup. No active writer, session journal or pending upload remained. The temporary network rule was removed. |

Current RetroArch preferences did not create PNG thumbnails during these sessions;
their transfer/restore boundary is covered by automated/native fixtures. This
is single-device account isolation and actual RomM readback, not a second-device
gameplay claim or coverage of other cores.

The one-time build 1057 reinstall was explicitly approved after the preview
signing keys differed. A verified backup preserved every local file, both native
Keystore sign-ins were re-encrypted/read back, and all 160 non-signature APK
entries matched CI. Its local retained preview signing identity permits future
Thor upgrades without that migration. No credential or signing key is in the
repository or evidence record.

Final inspection found eight temporary session configurations left by 1057.
The correction records each generated configuration's path/hash durably before
native publication, then uses compare-before-delete after save restoration and
ROM cleanup. A changed configuration preserves recovery; a lost deletion reply
can retry idempotently. Unrecorded legacy configurations are retained.

Build **1058**, runtime `c614999`, upgraded normally with the retained preview
key and unchanged app UID. Both saved accounts opened without another sign-in.
GBA/user 2 and SNES/user 3 loaded their earlier states, quit normally and synced;
both journal-owned configurations were gone afterward. All 19 existing managed
native files stayed byte-identical. The Thor returned to the original account
with no live emulator or session journal. The current universal macOS archive,
**24,349,989 bytes**, SHA-256
`09129651e6ea162379b99b1620373af9f42bfc6929a6926a2b73c27466a4fe41`,
passed ZIP and source/extracted deep strict signature checks. It is ad-hoc
signed, not notarized. See [the portable evidence](android-offline-states-snes.json)
for exact artifacts, hashes and the distinction between device and fixture checks.
