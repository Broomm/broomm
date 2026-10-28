# macOS emulator setup portability

Updated 2026-10-28. The owner reported failed PCSX2, ARMSX2 and PPSSPP setup
on another MacBook; Azahar succeeded. The failing installers re-sign the
downloaded application for Broomm's existing controller bridge. Azahar retains
its upstream signature.

## Cause and correction

The old installer compared every prepared file with signatures captured on the
development Mac. This conflated an exact emulator build with the output of
the local signing tools. Signature formats and entitlement encoding vary with
the signing system; Apple documents this in [Using the latest code signature
format](https://developer.apple.com/documentation/Xcode/using-the-latest-code-signature-format).
Different valid signature bytes therefore caused the same rejection as altered
program code.

Fresh official archives reproduced the old inventories on this development Mac.
The exact difference on the friend's machine was not inspected. To exercise the
failure deterministically here, the checks re-sign with both SHA-1 and SHA-256
code directories. All three resulting executable hashes differ from the old
captured hashes while native signature validation succeeds. The old comparison
would reject them; the corrected installer accepts them.

Setup now uses the following chain:

1. Match the source to a reviewed recipe for that specific build and verify the
   complete archive's pinned size and SHA-256 before extraction/signing.
2. Extract into confined private staging and run the existing macOS signing
   recipe. No arbitrary commands, executable builds or hook addresses can be
   supplied through a setup import.
3. Validate the expected file/link structure and macOS's deep, strict,
   all-architecture signature seal. Record the locally prepared executable
   SHA-256 in the installation receipt, and verify copied output against it.
4. Publish using the existing writer lease, staging, receipt and selection
   readbacks. On later inspection, validate that local executable identity and
   its signature; do not compare signatures with those from the capture host.

There is no additional per-file SHA-256 inventory comparison for re-signed
archives. Signature validation itself still checks the code/resource seal.
Unmodified archives and legacy extracted-folder imports retain their existing
inventory checks. This introduces no library, dependency, emulator update or
change to system-wide configurations.

The reviewed logical build identity remains unchanged for native symbols,
installed paths, save-state compatibility and Switch progress bindings. The
local executable hash is used for executable integrity. Signing differences
must not split otherwise compatible save states across devices. Existing
receipts without preparation metadata continue using the old verified bytes;
they are not rewritten or re-signed automatically.

The same archive-preparation correction applies to Dolphin, DuckStation and
Eden. This follow-up runs real installations for the three reported failures;
it does not claim new native gameplay acceptance for those other emulators.

## Owner retry and effects

Replace the Broomm application with the current macOS package. Open **Emulator
Settings → PlayStation 2 → PCSX2 / ARMSX2**, or **PlayStation Portable → PPSSPP**.
Choose **Set up**, then **Start setup** in that card. Existing Rosetta is required
for PCSX2 on Apple Silicon; Broomm does not install it.

Expected result: setup completes, **Open emulator** opens the private
configuration, and the emulator can be selected for Play. Failed attempts
before publication need no reset; completed archive caches can be reused.
Keep all profile progress and settings. Do not delete locks or the data root.
If a damaged installed application is explicitly reported, remove its managed
executable through Emulator Settings, then set it up again; removal preserves
profile progress.

## Verification and reproduction

On macOS 27.0.1 Apple Silicon / Xcode 27.1 (27A9275):

- Static analysis and all **415 Flutter tests** pass.
- Three new native signing regressions cover different valid signature bytes
  across installation/restart/source-free reuse, damaged signed resources and
  unknown archive provenance, plus invalid downloads/cancellation with progress
  retained. An existing state-compatibility regression now checks that signing
  variation preserves the state group while a changed emulator build splits it.
- Fresh pinned PCSX2 2.8.2, ARMSX2 nightly-20261023 and PPSSPP 1.20.4 archives
  install with different valid signatures and each opens a live private
  no-game configuration process. Competing writers are excluded. Fixture-only
  processes are stopped and writer release is checked. No owner data or remote
  progress is modified.

Run from the pinned Devbox environment:

```sh
devbox run -- flutter analyze
devbox run -- flutter test
devbox run -- flutter test tool/check_setup_portability_test.dart --reporter expanded
devbox run -- bash tool/build_bridges.sh
devbox run -- bash tool/build_app.sh --release --portable
```

The integration command expects the exact pinned official archives named
`pcsx2.tar.xz`, `armsx2.tar.xz` and `ppsspp.zip` under
`.tool-cache/research/setup-portability/`. Their URLs/hashes are in the bundled
setup. It creates disposable data there, including private profile/configuration
files; it never opens owner games. Logs and detailed local hashes are retained
there. Remove those fixture directories only after their test processes exit.

The friend's actual macOS retry and gameplay remain owner acceptance. Linux,
Windows and Android behavior is not established by this macOS setup check.
Astris/Citra MMJ/default-selection work remains in the named Git stash and is
excluded from this hotfix.

The current [macOS package](../build/releases/Broomm-macOS-portable-emulator-setup.zip)
is 20,477,225 bytes, SHA-256
`c6732b81b0cf422756fe7b9f3b9f2221ecc93f2cdfaf12334f89c880cc4e28cc`.
The app and all three bridges include ARM64 and x86-64. ZIP integrity, source
and fresh-extraction deep/strict/all-architecture signatures, and packaged
setup/bridge readbacks pass. It uses normal production Application Support
storage, retains ad-hoc development signing and has automatic application
installation disabled. No ROM, firmware, emulator payload, login or progress
is bundled. The [machine-readable record](macos-emulator-signing.json) retains
the tested base revision, exact archive/local executable hashes and remaining
acceptance limits.

The publication follow-up corrects updater discovery to `Broomm/broomm`, adds
two repository-selection regressions and passes analysis plus all **417 tests**.
The package above includes that correction. Existing clients using the old
personal repository need one manual official release installation; see
[update migration](application-updates.md). Incremental local Flutter output
required refreshing the App.framework and outer ad-hoc signatures before the
source and fresh-extraction signature checks passed.
