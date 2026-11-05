# Android root inspection and first save target

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
the mGBA core, active save paths and save synchronization are not yet verified.

Evidence is under `.tool-cache/android-root-failure/`. The Thor was held by an
existing ADB server on port 5038; use the project ADB with `-P 5038 -s 1b8e0a3e`
for that session. Neither ADB nor the diagnostic changed root grants.

## Current scope — 2026-11-05

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

1. Open **Emulator Settings → Game Boy Advance → RetroArch → Inspect root access**.
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
5. **Configure saves** remains the existing folder route. Inspection never
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
