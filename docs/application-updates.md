# Application updates

The owner selected Teddy's application updater as the behavior reference. This
implementation follows its stable/RC release ordering, checksum verification,
private staging, detached desktop replacement/restart, previous-bundle retention
and Android installer handoff. The inspected Teddy revision is
`989b212336743965e4e77ff8f744d6ad87c20b67`; the relevant files are
`lib/ted/teddy_updates.dart`, `teddy_update_installer.dart`,
`teddy_update_settings.dart` and `teddy_update_cleanup.dart`.

Broomm's public source is `Broomm/broomm`, with the existing five release
targets and `version.txt`/tag-ledger policy. It has no Teddy/TED server version
family constraint. A newer major/minor application release can be offered.
RomM authentication and emulator setup/update policy are unchanged.

The updater was corrected to this organization repository on 2026-10-28. Older
builds still check the separate `pedrotrschneider/broomm` repository, so they may
need one manual installation of an organization release before the normal
in-app update flow can discover later builds. Keep existing Application Support
data; this change requires no account, library or progress reset.

## Use it

1. Install an official packaged Broomm release containing this updater. Keep the
   complete Windows/Linux portable folder together, or use the macOS `.app`.
   The installation's parent must be writable. Keep personal data outside the
   application bundle/folder. Android requires the same package/signing identity
   and a newer numeric build code.
2. Broomm checks GitHub at startup and every six hours. Open **Broomm settings →
   Application updates → Check for updates** to check sooner. The default channel
   follows the installed release: stable builds get stable releases; candidate
   builds also get newer candidates. Stable and Release candidates can be chosen
   explicitly. Settings retains the selection across profiles and restarts.
3. When a newer complete release exists, **Update Broomm** appears first on Home.
   The selected app/game retains its identity when that tile or Downloads appears.
   Navigate to the tile and press A/Enter or click it. Download starts immediately;
   the update screen shows phases and percentage. B/Escape or **Cancel update**
   cancels preparation. The existing app stays usable after cancellation/failure.
4. Before installation Broomm finishes save work, stops emulator setup, checkpoints
   the download queue and obtains the session/writer lease. A game, configuration
   session or unfinished external Android session must be finished first. A failed
   queue checkpoint aborts the update with the in-memory queue and its lock kept
   for retry. Queued games, partial payloads and selected artwork are retained.
5. On desktop the verified installer acknowledges readiness, Broomm commits the
   handoff and exits, then the helper replaces and relaunches it. On Android,
   authorize installation from Broomm if requested, then choose **Continue
   installation** and confirm the Android installer. Android controls replacement
   and the final Open/relaunch UI; silent APK installation or a guaranteed
   automatic Android relaunch is not promised.
6. Sign back into a remembered profile after restart. Games and progress remain in
   their existing storage. Use Downloads to retry interrupted game transfers. A
   completed or failed desktop installer receipt produces one notification.

No offered release, offline/error, checking and preparing are distinct states.
Failed checks show a retry message in Settings and retain an already known offer.
Background checks do not generate repetitive notification popups. Development and
PR builds have no automatic installation path; Settings explains this. The current
public `v0.1.0` predates the updater, so it cannot discover this feature itself.

## Integrity, ownership and recovery

Release selection requires a numeric stable/RC version, a non-draft uploaded
platform payload, its exact `payload.ext.sha256` sidecar and its build JSON record.
Duplicates, incomplete releases, other repositories/versions and downgrades are
rejected. Both the recent-release list and latest-stable endpoint are checked so
many candidates cannot hide the stable release.

Requests are independent of RomM clients and carry no account credentials.
Only GitHub HTTPS API/download addresses and GitHub's HTTPS asset redirects are
accepted. Response sizes, redirect count, connection/idle/operation durations,
archive entries and expanded sizes are bounded. The full executable download is
always hashed on a Dart worker; this is independent of the optional game-checksum
setting. The checksum, payload size, target/version and build commit must agree
with release records. These checks trust the configured GitHub publisher; they
are not an independent publisher signature. macOS additionally verifies the
downloaded app's deep code signature. Android verifies its retained signing key
through the OS installer.

Windows ZIP and Linux TAR extraction use private staging with path, collision,
type and size checks. Linux publication now uses USTAR packages. macOS inspects
ZIP headers and framework links before `ditto`, then checks resolved links and
code signatures. Save ZIP extraction still rejects all links; the new link
inspection option is read-only for application bundles.

Staging lives in `.broomm-update-*` beside a desktop installation, or Android's
private `application-updates` cache. A stable OS lock and an in-process guard
fence preparation; the detached helper's exclusive claim spans process exit.
The helper waits for the original process identity, requires the commit marker,
checks cancellation, and preserves the prior bundle as `previous/`. Native macOS
uses the built-in JavaScript/Objective-C bridge solely for
`renamex_np(RENAME_EXCL)`. Windows uses exclusive directory moves; Linux uses
same-device, non-clobber, non-nesting moves with readback. Existing destinations
are never force-replaced. No third-party runtime library, service or OS package
installation is added.

On a replacement or immediate launch failure the helper attempts to restore and
relaunch the prior bundle. An application crash after a successful OS launch is
not health-checked automatically. Recovery bundles and `install.log` remain for
inspection; do not delete uncertain stages or backups while their writer/helper
is alive. A stale `.broomm-update-active` claim requires inspection rather than
being guessed away from a PID. If necessary, quit Broomm, verify no installer is
still working, preserve `previous/` and the log, then restore the previous bundle
to its original location without replacing unrelated files.

Startup cleanup uses the same lock, validates the full ownership manifest and
only removes recognized stages older than 24 hours without desktop handoff or
recovery evidence. It preserves unknown/incomplete state, active leases,
native-writer uncertainty, logs and backups. Android handoff renews the APK/manifest
timestamps; its cached APK becomes eligible after that 24-hour grace period, even
after handoff. A delayed permission prompt cannot shorten that grace. Discarding a failed update
does not delete application data, games, emulator installations or saves.

## Implementation and checks

`lib/src/updates/` separates release selection, HTTP transfer, archive validation,
installation/OS handoff and presentation state. Shell/session supervision owns
shutdown and save/queue leases. The Home row, background artwork lookup and game
options share its app count; adding an update or download tile cannot address the
wrong game. All new actions use the existing controller/keyboard focus system.

The release recipe embeds the full stable/RC version and target in Dart and writes
a top-level bundle inventory into `broomm-release.json`. Platform native versions
retain their numeric core/build code. The same checksum/build records produced by
the existing publication tooling are consumed by the updater.

| Boundary | Local evidence | Remaining native acceptance |
| --- | --- | --- |
| GitHub/macOS package | Real public `v0.1.0` download, checksum/build record, private extraction and deep signature verification | Real owner upgrade between two updater-enabled Broomm releases |
| macOS replacement | Native exclusive rename with existing destinations; actual Launch Services relaunch of a private native fixture; previous bundle retained | Owner gameplay/progress continuity after a production upgrade |
| Linux x64/ARM64 | TAR confinement, shared workflow tests; ordinary Unix helper lifecycle exercised on macOS | Native Linux updater/relaunch and gamescope checks |
| Windows x64 | ZIP preparation, inventory, ownership and failure checks | Native PowerShell cancellation test is enabled on Windows CI; full replacement/relaunch still needs that host |
| Android | Seven Kotlin sources compile; Dart permission/retry, handoff, retention and rejection contracts pass | Device installer/signature/permission/return behavior |

Run the owning regressions and project checks from the repository root:

```sh
devbox run -- flutter --suppress-analytics test --no-pub test/application_updates_test.dart test/application_update_archives_test.dart test/application_update_widget_test.dart test/application_update_android_test.dart test/release_workflow_test.dart
devbox run -- flutter --suppress-analytics test --no-pub --exclude-tags full-size-save
devbox run -- flutter --suppress-analytics test --no-pub test/playstation_test.dart --tags full-size-save --concurrency=1
devbox run -- flutter --suppress-analytics analyze --no-pub
devbox --config tool/android run check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer devbox run -- bash tool/build_app.sh --portable --debug --no-pub
devbox run -- bash tool/test_macos.sh
```

Tests use isolated files/processes, including a headless private macOS native app;
they do not install a release over the user's app, change RomM content or use
emulator/game progress. Temporary test fixtures clean up after workers finish.
Ignored `.tool-cache/application-update*` retains diagnostic logs and the real
download probe; the probe discards its downloaded package after verification.
The compiled developer app is under `build/macos/Build/Products/Debug/broomm.app`.
Its default development version deliberately disables automatic installation.

The updater milestone's [macOS delivery ZIP](../build/releases/Broomm-macOS-application-updates.zip)
is a fresh release-mode build of the same application sources. Its application
and three native bridges contain both ARM64 and x86-64. Archive integrity and
strict/deep signatures pass, including after fresh extraction. It uses this
checkout's existing `broomm-data/` and setup paths, includes no emulator/BIOS/game
payload, and keeps the `0.1.0-dev` updater-disabled identity. Close older copies,
unzip, then open `broomm.app`. The adjacent `.sha256` and JSON retain the checksum,
base revision and uncommitted-build identity. This is an ad-hoc-signed local test
build rather than a notarized/public GitHub release. Keep the ZIP or remove it
when no longer needed; deleting it does not delete progress.
The README links the latest macOS build when subsequent features supersede it.

The [verification record](application-updates.json) distinguishes analysis,
compilation, native fixtures, live release verification and outstanding platform
acceptance. No commit, push, tag or release is performed by this implementation.

Primary references: [Teddy updater](https://github.com/pedrotrschneider/teddy/blob/989b212336743965e4e77ff8f744d6ad87c20b67/lib/ted/teddy_update_installer.dart),
[GitHub releases API](https://docs.github.com/en/rest/releases/releases),
[release asset fields](https://docs.github.com/en/rest/releases/assets), and
[Android package installation](https://developer.android.com/reference/android/content/pm/PackageManager#canRequestPackageInstalls()).
