# Android DuckStation root integration

2026-11-08. PSP acceptance is complete and PR #5 merged as `d30d5dd`.
DuckStation is the next standalone increment. This document separates the
implemented read-only diagnostic from the save-writing work still required.
The existing connected-folder adapter remains separate.

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

## Fresh-boot handoff correction — native acceptance pending

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
Actual Broomm provider and repeated-session/state acceptance remain pending.

The APK also shows that base settings load once into a retained interface and
save when MainActivity pauses. Replacing `settings.ini` beneath a cached process
cannot be assumed to redirect the next game and risks a later rewrite. Do not
copy PPSSPP's settings-loan design without verifying this app's actual reload
and shutdown contract. Threads alone cannot establish live gameplay or complete
writer shutdown here.

## Required before root save sessions

Verify real content-URI boot, a RomM-sourced BIOS/game and normal native
shutdown/writer evidence on this exact APK. Determine how settings overrides,
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
devbox run -- flutter --suppress-analytics test --no-pub test/android_root_inspection_test.dart
devbox --config tool/android run check-root-inspection
devbox --config tool/android run check
```

The JVM checks emit disposable test JARs under `.tool-cache/research/android`.
They are development artifacts, not shipped runtime dependencies. Removing that
cache cleans them without changing emulator or game data.
