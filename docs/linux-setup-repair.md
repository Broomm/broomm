# Linux setup corrections — 2026-11-02

The owner reported that every setup failed in the installed Linux release.
Investigation used the existing SSH connection to CachyOS x64. The running
application and its production storage were left intact; installations and reset
checks used a separate source snapshot and disposable data folders.

## Causes and corrections

- RetroArch's Linux recipes used official Libretro `latest` URLs alongside fixed
  archive sizes and hashes. The provider rebuilt those mutable artifacts, so a
  valid current download failed before extraction. Linux core setup now accepts
  current official archives, checks transfer completion and archive structure,
  and records the installed library's actual identity. That identity selects
  installed versions and isolates save states. Existing selections survive a
  restart without network access; a failed explicit update retains the old core.
  Executable releases with native bridge addresses retain their reviewed builds.
- The installed `lib/broomm-native-run` had mode `0644`, while the development
  helper had mode `0755`. The updater's TAR extractor discarded executable
  modes and repaired only the main application. It now restores executable bits
  from the archive. Installation also publishes an executable private copy of
  its small helper, allowing bundles affected by an older updater to work without
  changing their permissions. Bundle checks actually execute the shipped helper
  and reject a non-executable one.

No library, OS package, system permission or service was installed or changed.
The owner explicitly requested that this preview be tested before any commit.

## Reset boundary

**Emulator Settings → Reset all emulators → Reset installations and settings**
removes managed frontend/core installations and setup downloads, clears native
settings/caches across profiles and clears emulator defaults. It regenerates
Broomm's initial settings for the supported emulators.

Local saves, states, console accounts, NAND content, game installations, artwork,
RomM credentials and pending synchronization are retained. The owner's later
clarification supersedes the initial proposal to wipe profile data. Reset uses
known native configuration paths; it never searches save/NAND trees for files
that happen to end in `.ini` or `.json`. It does not remove system emulators or
remote RomM assets. Native writer exclusion and a durable reset intent prevent
deletion during a game and make interrupted settings resets repeatable.

## Preview walkthrough

1. Close the old Broomm window and any emulator opened through it. Extract
   `Broomm-Linux-x64-setup-fix-preview.tar.gz` and launch `bundle/broomm`, keeping
   its `lib/` and `data/` directories beside it. A ready copy is placed under
   `~/Downloads/Broomm-Linux-setup-fix-preview/` on the test machine.
2. The preview uses normal `~/.config/broomm` storage. Select the existing server
   and profile. Reset is optional; it is not needed to repair the download or
   permission failures.
3. In Emulator Settings, review and start RetroArch setup, then a standalone.
   Expect current core downloads to complete and the installed/default status
   to appear. Open emulator should still leave Broomm usable.
4. If testing reset, confirm its stated boundary, verify games/progress remain,
   then set up the desired emulators again. Play uses retained local progress
   and the usual controller flow. States still need their matching core build.
5. This is a local `0.1.7-dev` preview. Automatic application updates are disabled
   for this development identity so an official release cannot replace the test
   build unexpectedly. CI/commit/publication await owner testing. To discard the
   preview, remove only its extracted application folder and downloaded archive;
   keep `~/.config/broomm`.

The local CachyOS build targets that machine's installed runtime; official Ubuntu
and ARM64 release runners are separate checks. Windows/Android native execution
was not performed. macOS also receives a fresh universal preview archive with
code signatures and extraction integrity verified before delivery.

## Verification

- 496 macOS Flutter tests and 427 Linux Flutter tests pass; 22 existing Linux
  platform/native comparison skips remain. Analysis, formatting and workflow
  lint pass.
- All nine standalone packages install and resolve two private profiles with
  `build/native/broomm-native-run` deliberately changed to `0644`. Source archives
  are the existing reviewed fixtures; extraction/publication use production code.
- Fresh network setup installs all fifteen Linux cores from the official provider.
  A native probe loads each library and reads Libretro API/system information.
  The disposable RetroArch reset retains a native save and pending sync record.
- Unit cases cover rolling size/content changes, truncated transfers, selected
  identities across restart, failed updates, state directory separation, helper
  permission repair, updater TAR modes, reset cancellation, held session locks,
  interrupted resets and progress/config separation across several emulators.
- Linux kernel ownership/process, ASan/UBSan and package dependency/permission
  checks run independently. These checks establish setup and ABI loading, not
  new commercial gameplay or physical controller acceptance.

Ignored evidence is in `.tool-cache/research/linux-setup-fix/` on both hosts;
Linux checks use the nested `work/` snapshot. `source-files.json` compares 454
runtime/test/tool files with no differences. Disposable integration data may be
removed after its processes exit; normal Broomm data must be retained.
