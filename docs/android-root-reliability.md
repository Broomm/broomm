# Rooted Android reliability checks — 2026-11-07

These checks use the installed PR #2 preview, Broomm **1054**, on the owner's
AYN Thor: Android 13, user 0, Magisk 31.1, official RetroArch 1.22.2 arm64 and
mGBA 0.11-212-7a12d6d. The owner authorized ADB input and device testing.
The application sources match merged revision `f4857e0`; this follow-up changes
verification records, not application behavior.

Before testing, stable, content-verified archives preserved Broomm's local data
and the relevant RetroArch files. Minish Cap, ROM 2338, had two occupied slots
and an empty third slot. Tests used that third slot. No existing RomM asset was
deleted or replaced.

| Boundary | Actual Thor result |
| --- | --- |
| Live emulator writer | Explicit recovery refused while RetroArch was running. Both journals and the native save stayed unchanged. |
| Offline play and capture | The installed game launched from an active profile without RomM. Creating slot C and quitting normally produced a durable pending snapshot. |
| Restart with pending progress | Force-stopping Broomm preserved the pending checkpoint. Reconnecting the original account uploaded version 212, verified its download and cleared pending. |
| Denied root | Magisk denial prevented launch before a game journal was created. Regrant and retry worked in the same Broomm process. |
| Interrupted emulator | Force-stopping RetroArch retained both journals and required review instead of automatic upload. |
| Revoked root during recovery | After restarting Broomm with root denied, recovery refused and preserved both journals and the save. Regrant allowed capture; unexpected exit still required an explicit cloud/device choice. |
| Real remote conflict | With slot D captured offline against version 212, a separate same-account API client appended version 213 containing the original save. Broomm retained both copies, recorded a conflict and displayed the choice. |
| Original-save restoration | Selecting cloud progress cleared the conflict and restored the exact pre-test bytes. Minish Cap displayed both original slots and an empty third slot. The unselected D snapshot remained in recovery. |
| Standalone preferences | All five pre-existing configuration/core-option files compared byte-identical with the backup. The isolated session save directory returned to its originally empty state. |
| Two authenticated accounts | User 3 started with empty slots and a separate native directory. Its E save stayed queued, with an unchanged checkpoint, while user 2 reconnected and played the original save. Selecting user 3 uploaded/read back version 214. Both manifests and native saves identify their own accounts. |

Version 213 is a new BROOMM history entry, with the same native bytes as original
version 211: SHA-256
`afcb8e484df0e03324223ec2b5010ad2279e744e039d9e287c3d8be526ec17b3`.
The competing offline D save has SHA-256
`0887bbcce3f812b79a3fbb43a7220fcd457b0d98e66fad6a0e25461cde5c7bad`.
Earlier history, including 211 and 212, remains available.
User 3's separate E save has SHA-256
`ad3196037df67b5848a7f76d3659aa3015fda45f5cb6ed6a250e270357f91dac`.
The Thor was returned to user 2 with both accounts synchronized and no active
emulator or session journals. The owner-added second profile remains available.

## Remaining product gap at build 1054

The [build 1057 follow-up](android-root-access.md#offline-profiles-rooted-states-and-snes--2026-11-07)
implements and verifies offline profile activation. The observations below
describe the earlier build rather than the current behavior.

A known profile cannot currently be activated after an offline application
restart. `ShellModel.activateProfile` requires `checkServer` and credential
restoration online before opening Home. Pending progress survives, and an
already active profile can play offline, but this does not satisfy PROJECT.md's
full offline-use requirement. Fix activation without treating an online
permission denial as an offline connection failure.

The saved Mac sign-in for the second account returned HTTP 401. The owner then
signed in normally to a different Thor account, user 3; no second account was
inferred from a duplicate local profile. A temporary API helper
also lost a renewed Thor sign-in after an ADB stdin transport failure; the
owner repaired it through normal login. The helper was corrected to use bounded
framing and duplex transport, verified secure readback, and then completed the
real conflict check. This was a test-tool failure, not an APK failure.
Some injected taps after an emulator return required refocusing Broomm's
existing Android task with `am task focus`. ADB input is distinct from the
owner's earlier physical-input acceptance.

## Native fault checks and reproduction

Compile the current production filesystem fixture with the pinned toolchain:

```sh
devbox run --config tool/android bash build_root_save_test.sh
```

Run its `Check_root_save_filesKt run` entry through `app_process` with Magisk,
using a fresh `/data/local/tmp/broomm-root-test-<32 hexadecimal digits>` root.
The fixture removes its disposable files in `finally`; remove the pushed DEX
after it exits. Never point it at an emulator or Broomm profile directory.

Seven native groups passed: atomic save replacement and UID/GID/mode/label
restoration; compare-before-write and linked/path refusal; interrupted staging
and exclusive publication; expired requests; verified ROM staging and cleanup;
core/controller/menu resource recovery; and a held production OS lock excluding
a separate Android process. These are real Android filesystem tests with
injected interruption points, distinct from killing the packaged application
during publication.

Receipts, screenshots, backup hashes and complete native output remain under
`.tool-cache/android-reliability/2026-11-07/`. The portable result summary is
[android-root-reliability.json](android-root-reliability.json). Temporary network
rules applied only to Broomm's UID and were removed; its original Magisk grant
was restored. Preserve normal profile, history, snapshot and stable lock files.
