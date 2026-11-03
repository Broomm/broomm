# Linux launcher and controller reconnection — 2026-11-03

## Release gate

Before new behavior was changed, the owner requested the entire existing tree
be committed and pushed. Commit `7a1caded9ec9361c68f2c444b885829088d93d43`
contains the prior Linux setup/download fixes and pending research documents.
[Release run 41576682638](https://github.com/Broomm/broomm/actions/runs/41576682638)
completed successfully: workflow lint, version, Linux/macOS/Windows checks,
native macOS checks, Linux x64/ARM64, Windows, universal macOS and Android builds,
and release publication. Launcher/reconnection work began after that success;
that run does not verify these subsequent changes.

## Application launcher

**Broomm settings → Application** exists on all hosts; Linux alone exposes
**Install to Launcher**. The action resolves the current executable, checks its
bundled `data/broomm.png`, and publishes these current-user files:

- `<data-home>/applications/app.broomm.broomm.desktop`
- `<data-home>/icons/hicolor/512x512/apps/app.broomm.broomm.png`

`<data-home>` is absolute nonempty `XDG_DATA_HOME`, otherwise
`$HOME/.local/share`. Relative XDG values are ignored. Installation holds a
stable OS file lock, writes through private stages with readback/atomic rename,
and refreshes only its owned launcher. Existing unrelated launchers, icons and
linked destinations are preserved with a visible error. It uses no shell,
`sudo`, new library or global desktop configuration. Exec quoting preserves
spaces and reserved characters. Desktop Entry's prohibited `=` and GIO's
unsupported `%` in an executable path receive an actionable move/retry message
before any launcher is published. No emulator, game or saved progress is affected.

The native follow-up found that GIO 2.90.1 performs an executable lookup before
expanding escaped percent signs. A spec-escaped percent path was therefore
rejected while loading application information. The original failed test is
retained in `remote-evidence/flutter-tests-first.log`; the corrected regression
checks refusal before effects, rather than claiming an invalid launcher works.
The real GIO launch case still tests spaces, quotes, backticks, dollar and
backslash characters without shell expansion or added arguments.

The launcher uses the existing application ID/icon name and current absolute
bundle path. It does not copy the bundle. Close Broomm and reopen from
Applications after installation; run the action again after moving the bundle.
An in-place application update retains that path.

Linux ELF executables do not provide a portable counterpart to the Windows PE
icon resource that ordinary file managers use. For GNOME Files, the existing
GTK/GIO bridge attempts `metadata::custom-icon` on **its own executable only**,
pointing to its own bundled icon. This is asynchronous with cancellation and
readback. It neither rewrites the executable nor changes every ELF file's icon.
GVFS/file-manager support is optional; failure is explained in Settings and
does not undo the correctly installed launcher/icon. The per-file icon is
attempted when **Install to Launcher** is activated; it is not embedded metadata
that travels in a downloaded archive.

## Reconnection investigation

The friend's DualSense battery report did not name an emulator or provide a
reproduction. Inspection found two generic asynchronous presentation bugs:

1. A delayed resume acknowledgement or window-hide completion could overwrite a
   newer disconnect screen, hiding pairing and restoring Playing.
2. A disconnect received while the menu was still waiting for pause/presentation
   was ignored by the already-opening guard, leaving Menu instead of Pairing.

Resume completion now verifies session/request identity, the current screen,
connected assignments and mappings before publishing Playing. A hide already in
flight restores the newer pairing/menu. A disconnect supersedes a pending menu.
Reconnecting controllers still need explicit pairing with their current SDL
instance ID; neither names nor old instance IDs authorize assignment.

Three controlled tests hold the resume/pause/hide boundaries, including a
DualSense-labelled device returning under a new instance ID. All three fail
against the previous committed model and pass after the fix; explicit re-pairing
then resumes normally. This establishes those races, not a confirmed physical
DualSense diagnosis. Native bridge behavior is unchanged.

## Verification and owner walkthrough

- **519 macOS Flutter tests pass**, with one Linux-only GIO test correctly
  excluded. **450 Linux Flutter tests pass**, with 22 existing platform skips.
  Static analysis and formatting pass.
- Launcher cases cover custom/default/invalid XDG paths, regular branding,
  repeated installation, foreign/symlink preservation, an independent process
  holding the production lock, and retry after failure. Widget tests cover
  keyboard/controller reachability and activation, busy/completion/error/retry
  feedback and the Linux-only action.
- A Linux-only test uses the existing GIO Desktop Entry parser to launch a
  disposable executable whose path contains spaces, quotes, backticks, dollar,
  and backslash characters, checking exact cwd and zero added arguments. A
  separate case verifies rejection of equals/percent executable paths.
- After SSH returned, production GTK host/header compilation and writer recovery
  pass. The release app builds and passes its full ELF dependency audit. The
  deployed binary reaches server selection with isolated HOME/XDG storage and
  exits 0 on SIGTERM. The owner's old app remains running and unchanged.
- **GNOME file-manager visual acceptance and physical controller testing remain
  pending.** The green CI run above predates the new native method; this later
  Linux evidence comes from the owner's CachyOS x86_64 host.

After building on Linux, run these tests from the repository root inside its
Linux Devbox environment:

```sh
flutter test --no-pub test/linux_launcher_test.dart \
  test/launcher_settings_test.dart test/controller_reconnection_test.dart
```

`tool/check_linux_host.sh` independently compiles the production GTK host/header
and exercises existing writer recovery; `tool/ci/build_linux.sh` builds the app.
These checks use private fixtures, not real launcher paths.

For visual acceptance:

1. Keep `bundle/broomm`, `bundle/lib/` and `bundle/data/` together in the desired
   final application folder. Open Broomm normally.
2. Navigate using arrows/controller to **Broomm settings → Application → Install
   to Launcher**. Expect confirmed completion and close/reopen guidance.
3. Close normally and launch **Broomm** from the desktop Applications menu. Check
   the regular infinity icon and correct data/profile reuse. In GNOME Files,
   refresh the bundle directory and inspect the executable's icon; record the
   file-manager/metadata result separately from launcher success.
4. During a disposable game session, disconnect a paired controller while
   resuming or opening the menu. Reconnect, pair with L1+R1, test its buttons and
   hold Start. Pairing should remain visible until an explicit successful resume.
   Repeat with the friend's real DualSense/emulator when available.

Optional cleanup removes only the two installed files above, retaining the
stable lock file. GNOME custom metadata can separately be cleared with
`gio set -t unset /absolute/path/to/bundle/broomm metadata::custom-icon`.
Deleting a preview archive/app is independent of accounts, games and progress;
do not remove Broomm's data directory.

## Delivered previews

The Linux build is available at:

```sh
~/Downloads/Broomm-Linux-launcher-reconnect-preview/bundle/broomm
```

Close the older app normally before opening this copy. The bundle uses normal
production storage; accounts, games and progress need no migration or reset.
The [Linux archive](../build/releases/Broomm-Linux-x64-launcher-reconnect-preview.tar.gz)
is also retained in Downloads on the Linux machine: **11,988,376 bytes**, SHA-256
`d8709d39adb17af6f437af94526b63fc7c54cc48786f0a3c8a0e1b463bc0d52b`.
The archive payload/mode checks and freshly extracted readback pass. Deployment
uses an exclusive directory rename and preserves existing destinations.

Ignored logs, the before-fix regression fixture and package evidence are under
`.tool-cache/research/linux-launcher/`. The launcher-milestone macOS preview is
[Broomm-macOS-linux-launcher-preview.zip](../build/releases/Broomm-macOS-linux-launcher-preview.zip),
using normal production storage and a development identity with updates disabled.
Its macOS bundle is ad-hoc signed, not notarized. Linux launcher visibility and
Steam/gamescope behavior are not established by a successful macOS build.

macOS package verification: **21,299,157 bytes**, SHA-256
`4565f9fc45c90405a8487905b614a5cb6546b39607c1b4d3aba76c8d6b77dcf0`.
The source bundle and a freshly extracted archive pass deep, strict,
all-architecture signature checks, ZIP integrity and native/asset readback.
The macOS and Linux artifacts record the same current source-tree fingerprint.

## Primary sources

- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/): user data locations and absolute-value rules.
- [Desktop Entry Exec rules](https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html) and [recognized keys](https://specifications.freedesktop.org/desktop-entry/latest/recognized-keys.html): executable quoting, literal percent, icon and startup identity.
- [GIO async file attributes](https://docs.gtk.org/gio/method.File.set_attributes_async.html): existing GTK runtime interop with cancellation/completion.
- [GNOME Files metadata definitions](https://github.com/GNOME/nautilus/blob/main/src/nautilus-metadata.h): the per-file `custom-icon` key. No GNOME code is copied.
- [GIO Desktop Entry loading](https://github.com/GNOME/glib/blob/main/gio/gdesktopappinfo.c): initial executable lookup before launch-time percent expansion; native rejection confirmed separately above.
