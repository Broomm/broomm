# Installed Switch launch correction

2026-10-30. The owner's installed Super Smash Bros. Ultimate failed with “RomM
did not provide a complete downloadable file manifest” for both profiles.
Read-only inspection found all 101 receipt-listed files present at their
recorded sizes: one base NSP, one update and 99 DLC NSPs. The Ryubing generation
also had its matching checkpoint/manifest. This is metadata/size evidence, not
a checksum or gameplay check.

`RommGame.toJson()` deliberately stores lightweight game metadata without the
remote `files` array. `GameLibrary.load()` restores that metadata alongside its
separate local file receipt. `GamePackages.needsSwitchSelection()` incorrectly
passed that restored metadata to the download manifest validator before
checking the existing content generation. Every restart could therefore fail
before the emulator opened. Profiles share this installation, explaining the
same failure on both accounts; their save data was not implicated.

The preflight now reuses a valid content checkpoint. Without one, it inspects
the installed file receipt to distinguish a base-only game from one needing
its first native update/DLC import. API roles identify root-level attachments;
`update`, `updates` and `dlc` folders also identify older categorized/missing-role
receipts. Base selection excludes these attachments. If first import needs
remote file identities absent from the saved metadata, it requests the same
game's detail manifest and checks game/platform identity before using it.
Missing, denied, incomplete and mismatched responses remain failures rather
than an empty add-on inventory. Normal launches with a generation do not make
this request. This fixes a shared Switch boundary for Ryubing and Eden;
it adds no runtime dependency or automatic emulator update.

## Owner verification

Quit Broomm, replace the application with the supplied fixed macOS build, then
select either existing profile and **Home → Super Smash Bros. Ultimate → Play**.
The expected result is progress to emulator loading and controller pairing
without this manifest error. Repeat with the other profile. No redownload,
manual receipt edit or deletion is needed. Existing profile saves and content
remain in normal Application Support storage. Switching to a backend that has
not imported its content yet can require a RomM connection for that first import.

The fix does not bypass firmware, content integrity, cloud conflict or native
launch failures. End-to-end owner gameplay remains an acceptance check.

## Developer reproduction

```sh
devbox run -- flutter test --no-pub test/native_packages_test.dart test/library_download_test.dart test/addon_shell_test.dart test/eden_test.dart --reporter expanded
BROOMM_SWITCH_RECEIPT='/absolute/path/to/library/server/game/receipt.json' devbox run -- flutter test --no-pub tool/check_switch_installation_test.dart --reporter expanded
```

The targeted suite covers restart, base-only games, two private profiles sharing
a generation, folder/root-role attachments, first-import reuse and failed or
mismatched manifest recovery. It retains progress and rejects damaged content
checkpoints. The manual inspection tool reads only the provided installation's
metadata/file sizes, copies checkpoint metadata into disposable storage, checks
both checkpoint-present and checkpoint-absent paths, and removes its own scratch
directory. It starts no emulator, reads no ROM payload and contacts no server.
Do not remove production profile, game or save folders for this diagnostic.

The isolated commit source passes analysis and **428 Flutter tests** (426 ordinary
and two separately scheduled full-size save checks), plus the read-only installed
receipt check. [Verification evidence](switch-installed-launch.json) records the
source scope and log fingerprints; the local archive/signature record is
`build/releases/Broomm-macOS-switch-launch-fix-ci.json`. Other native hosts and
physical gameplay are not established by this macOS metadata check.
