# Eden Linux launch and save-account investigation — 2026-11-04

The owner's Ally (Bazzite, x86_64) used managed Eden 0.2.1, reviewed build identity
`f9ff8a8991ae33b4f96469a6df2b7ac59220dca9c3e075750ea6f406dde0c734`,
and Smash Ultimate, program `01006a800016e000`. The report was in Gaming Mode;
the subsequent diagnostic used the existing Desktop Mode session. These are
two Broomm defects, separate from DLC installation.

## Evidence and corrections

At 03:06:46 UTC the first native loader record was split after `Loading Super`.
Mesa diagnostics arrived before its remaining game name/title ID at 03:06:46.591.
The bridge acknowledged Pause at 03:06:53.327. Broomm nevertheless stopped cold
initialization at 03:08:44, its two-minute deadline: the shared stdout/stderr
identity buffer could no longer match the interrupted loader record. The later
attempt received an intact record and completed initialization. The new bounded
parser retains independent pipe buffers and consumes all bytes of large bursts.
It preserves the existing Eden/Ryubing/Astris native-loader patterns; no launch
deadline or shader/cache setting was relaxed.

The native `profiles.dat` has UUID bytes
`cde3270c6ca84eec4b59b7456231292f`. Eden's legacy save directory is those bytes
reversed and encoded as 32 uppercase hex digits:
`2F29316245B7594BEC4EA86C0C27E3CD`. Broomm instead formatted two unsigned 64-bit
reads through signed native Dart integers. The low half's high bit produced
`-13B15793F3D81C33`, yielding the exact invalid directory in the screenshot:
`2F29316245B7594B-13B15793F3D81C33`.

The downloaded BROOMM snapshot was restored there, while Eden created fresh
progress under its real account. Both directories remained present. All five
files in the malformed directory matched the retained downloaded snapshot;
the active cloud baseline remained unchanged. A third orphan directory contained
only a 16-byte `.yuzu_save_size` marker. This inspection does not authorize
deleting any of those copies or choosing a conflicting save by timestamp.

Desktop and Android Eden now format the UUID byte-by-byte, preserving all 128
bits. The future `account/<raw-byte-UUID>/<title>/0` convention is unchanged.
Native console/account changes and storage migrations still invalidate an
already resolved boundary. No console account, firmware or DLC is replaced.
Eden's own [orphan-profile check](https://github.com/eden-emulator/mirror/blob/master/src/qt_common/util/content.cpp)
compares native save directory names with known accounts before boot, explaining
why the bad destination triggers a blocking dialog even though DLC remains usable.

## Verification and remaining work

- `flutter analyze --no-pub` passes. Thirty-five targeted tests pass, including
  account IDs with either/both high halves set, exact restore/readback in the
  native directory, Android placement, account migration/change rejection,
  interleaved pipes, large bursts, and the cloud recovery regressions.
- A copied Ally account and actual retained BROOMM snapshot were exercised
  through the production `ProgressStore.restore`. All five restored file hashes
  matched the selected cloud snapshot in the corrected native account directory.
  The overwritten fresh device snapshot was retained by the normal restore
  journal. This was an isolated local copy, with no RomM writes.
- An isolated reflink clone on the Ally launched the real installed Eden/Smash
  through its existing injected bridge and xcb backend, reached acknowledged
  Pause with no connected console ports, and exited normally. A second launch
  with the reported Mesa option overrides confirmed that Eden's loader record
  uses stdout and all 24 driver warnings use stderr, directly validating the
  independent-pipe parser boundary. Both runs exited with status zero. This
  checks native readiness, not controller/gameplay acceptance of the corrected
  application.
- The current portable macOS preview was rebuilt and its archive and extracted
  deep/strict code signature verified. It is `0.1.13-dev`, ad-hoc signed and uses
  the normal production data directory. Its development identity disables
  automatic application updates.

Diagnostic copies, native fixture results and regression logs are retained under
ignored `.tool-cache/research/eden-save-account/`. Native fixture directories
are under the Ally's `~/.cache/eden-account-*`; remove those diagnostic copies
only after their child emulator has exited. They do not contain live progress.

**Live repair completed at 03:40:21 UTC after the owner closed Broomm.** Both
session/writer locks were held, and process inspection confirmed no Broomm/Eden
writer. The malformed, correct and marker-only directories were renamed intact
under `~/.config/broomm/recovery/eden-account-20261104T034021Z`. A staged copy of
the acknowledged downloaded BROOMM snapshot was published at the real account
path. All five files (8,262,840 bytes) matched the snapshot after publication.
The durable repair journal reached `verified`; the cloud state and native
account bytes remained unchanged. The fresh device save and malformed restored
copy remain separately recoverable there. No files were merged, settings cleared,
console account recreated, or RomM data changed.

**Linux deployment remains pending.** Use a build containing this correction
before launching again; the currently installed old binary can recreate the
malformed path. The folder repair alone cannot correct its code.

After repair, launch Smash from the corrected Linux build. Expect no orphan
warning, the existing DLC, and the selected save progress. Close normally and
launch again. Controller operation and this end-to-end Gaming Mode check remain
owner verification; a matching hash or successful build does not establish them.
