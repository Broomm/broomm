# GitHub builds, versions and releases

The owner selected the workflow and version policy from the sibling Teddy
project. Broomm adapts its `.github/workflows/release.yml`,
`scripts/release_version.py`, `scripts/publish_release.py` and packaging/signing
behavior. Teddy is reference material, not a source of Broomm instructions. No
Teddy application code, media dependencies, server compatibility policy, Go,
updater or OS package installation is imported. Release decisions and packaging
are implemented in Dart under `tool/release/` using the SDK and existing digest
code; no Flutter runtime dependency is added.

## Version policy

`version.txt` contains **MAJOR.MINOR**, initially `0.1`. Keep `pubspec.yaml` as the
local development default; CI supplies Flutter's `--build-name` and
`--build-number` without creating version-only source commits.

| Event | Version/tag | Effects |
| --- | --- | --- |
| First successful push to `develop` | `0.1.0-rc1`, tag `v0.1.0-rc1` | GitHub prerelease |
| Next successful `develop` push | `0.1.0-rc2` | Increment candidate; retain patch |
| Successful push to `main` | `0.1.0`, tag `v0.1.0` | Stable release |
| Next development/stable cycle | `0.1.1-rc1` / `0.1.1` | Advance from highest stable patch |
| PR targeting either branch | e.g. `0.1.1-pr7.12345` | Build artifacts only; no tag or release |
| Change `version.txt` to `0.2` | `0.2.0-rc1` / `0.2.0` | New owner-selected major/minor line |

The Android/Flutter numeric build number is `1000 + GITHUB_RUN_NUMBER`, stable on
a rerun and increasing across major/minor changes. `version.txt` does not change
automatically. The **tag ledger** supplies automatic patch/candidate bumps, as in
Teddy. Completed tags on the same commit/channel are reused on rerun; an old
release cannot become the channel's latest over a newer version. Unrelated tags
and other major/minor lines do not consume this line's numbers.

Main/develop share one queued workflow concurrency group. PRs have independent
groups. Versions are calculated without Git mutation. All analysis/tests, native
Mac tests and all five builds must succeed before publishing. A second ownership
check rejects a stale number or a tag owned by another commit. Publication stages
a draft, uploads the complete payload/checksum/metadata set, checks the draft's
asset names/sizes, then makes it public. Failed builds/uploads do not create a
public release; a failed draft may remain for inspection/retry. An already public
release is never overwritten on rerun.

## Build matrix and current capability

| Build | Hosted runner | Package |
| --- | --- | --- |
| macOS universal app and C bridges | `macos-26` | `Broomm-VERSION-macos-universal.zip` |
| Windows x64 | `windows-2025` | `Broomm-VERSION-windows-x64.zip` |
| Linux x64 | `ubuntu-24.04` | `Broomm-VERSION-linux-x64.tar.gz` |
| Linux ARM64 | `ubuntu-24.04-arm` | `Broomm-VERSION-linux-arm64.tar.gz` |
| Android universal ARMv7/ARM64/x64 | `ubuntu-24.04` | `Broomm-VERSION-android-universal.apk` |

Each payload has an adjacent `.sha256` and a JSON record of the product, version,
workflow commit, build number, target, size and digest. Exact expected filenames
and all five hashes are checked before uploading; native test results and other
files cannot enter a release. Build artifacts are retained for 14 days. macOS
native test results are uploaded separately, including after test failures.

These are **early application builds**, not proof of emulator parity. The
[support matrix](platform-support-matrix.md) remains authoritative: the desktop
bridge/managed emulator pack is verified on macOS Apple Silicon, with the Intel
RPCS3 alternative separately tested. A universal Broomm binary does not add an
Intel-host emulator pack. Linux/Windows emulator bridges and Steam/gamescope
acceptance remain pending. Android's external-app/save/package support is partial
and still needs a device run. CI requires no private RomM service, credentials,
ROMs, firmware, keys or locally prepared emulator executables. Those native
integration suites remain explicit owner/developer checks, not fake CI passes.

macOS packages build all three universal libraries, verify architectures and deep
signatures and use ad-hoc signing; they are **not notarized**. Windows packages
retain DLLs and `data/` beside `broomm.exe` and are unsigned. Linux tarballs retain
the complete Flutter bundle and require a host with GTK 3, Secret Service,
a compatible glibc (Ubuntu 24.04 baseline) and graphics drivers. CI checks
linked libraries against the host loader with Nix overrides removed and rejects
remaining Nix RPATH/interpreter/dependency references. It does not bundle the Nix
store, install packages on the user's OS, or establish graphical/native gameplay
acceptance. Keep the Linux bundle's `lib/` and `data/` beside `broomm`.

Release macOS builds use `tool/build_app.sh --release --portable`: they do not
embed this checkout as `BROOMM_PROJECT_ROOT`. Ordinary developer builds retain
their prior checkout-based workflow. Release setup still imports the reviewed
local emulator bundles using explicit source paths; remote emulator provisioning
and Linux/Windows emulator packs are not added by the release workflow. Neither
the app archives nor this repository should contain emulator, ROM, firmware, key
or account payloads. The current built-in `tested:` setup aliases require the
developer fixtures; use the documented explicit setup JSON sources elsewhere.

## Toolchains and dependency choices

macOS uses the root pinned Flutter/Dart Devbox environment and the pre-provisioned
Apple SDK, with child-only `DEVELOPER_DIR`. Linux uses the locked
`tool/ci/linux` Devbox environment for Flutter, CMake, Ninja, pkg-config, GTK
development inputs and ELF tools. Broomm's credential adapter uses GTK's existing
GIO/D-Bus interface to Secret Service and requires no additional libsecret package.
Its already provisioned Ubuntu Clang
18/compiler sysroot supplies the native ABI, so Nix's newer glibc is not a shipped
dependency. No `apt`, Homebrew, global SDK selection or OS package bootstrap is
run. Linux compilation/runtime dependency checks still require native CI evidence.
GTK and pkg-config now resolve from Nixpkgs
`5ed627539ac84809c78b2dd6d26a5cebeb5ae269`, matching the existing binutils snapshot:
GTK 3.24.43, GLib 2.80.4, pkg-config 0.29.2 and glibc 2.39. The first hosted build
exposed an incomplete newer GLib/sysprof development graph. The build now checks
the complete GTK/GLib/GIO compiler and linker flags before CMake and retains
verbose compiler/linker output. Nix evaluation confirms both Linux architectures;
it does not establish a successful Linux build.
GTK selects its outputs with `#gtk3^out,dev`. With Devbox 0.18.4, combining a bare
flake package with an `outputs` field generated an empty output selector
(`gtk3.`), which is invalid Nix. The explicit selector has been checked through
Devbox environment generation and actual pkg-config execution, not just package
metadata evaluation.

Flutter's Nix wrapper also injects its own newer GTK/Pango search paths after the
build script starts. Linux CI captures the Devbox target pkg-config graph and real
CMake path before invoking Flutter. The CMake and Clang shims restore that graph
and clear injected compiler/linker/library flags at the native tool boundary.
The development manifest explicitly exposes the existing GTK stack's private
pkg-config inputs, all from the same snapshot: PCRE2, libthai/libdatrie, Xdmcp,
Lerc, epoxy, xkbcommon and GLib's mount/SELinux inputs. These are build inputs for
the existing GTK dependency, with Linux-only inputs scoped to both Linux targets.
The primary `xorg.libXtst` output must also be exposed explicitly for AT-SPI's
private `xtst.pc` requirement; its presence in the runtime closure alone does not
place its metadata on Devbox's pkg-config search path.
Dynamic and static dependency queries run before compilation. No new Flutter
runtime dependency or operating-system installation is introduced.
The application target also imports `x11` explicitly: `my_application.cc`
includes GDK's X11 public headers for window-manager detection, and GTK's shared
compiler flags omit those private include paths. This consumes the X11 development
inputs already supplied by GTK; adding more installed packages alone cannot fix
a target which does not request their compiler flags.

Android uses `tool/ci/android` for the same Flutter pin plus JDK 21. The workflow
copies the runner's **already provisioned/licensed** API 36, build tools 36.1.0,
NDK 29.0.14206865 and platform tools into `.tool-cache/android/sdk`. Gradle's
wrapper/cache and memory limits stay in `.tool-cache/android/gradle`. Missing
components fail with their names. The workflow neither invokes `sdkmanager` into
the global SDK nor silently accepts new SDK licenses. Its pinned NDK/build tools
also appear in `android/app/build.gradle.kts`.

Devbox has no native Windows backend. As in Teddy, the Windows jobs use
`subosito/flutter-action`, reading the exact Flutter version from Broomm's root
Devbox configuration and caching SDK/pub files under `.tool-cache/`. The runner's
existing MSVC/Windows SDK is used. This explicit native Windows tooling exception
is confined to CI; WSL would build Linux rather than validate Windows. The
packager checks the running Flutter version against the root Devbox pin on every
target. Introducing a separate Windows SDK/version manager would duplicate that
pin and add a dependency without improving native validation.

Top-level Actions are pinned to verified upstream commits. The Devbox installer
uses CLI 0.18.4. Workflow lint uses project-scoped actionlint 1.7.12 and ShellCheck
0.10.0. That actionlint version still rejects GitHub's documented
`concurrency.queue`; `tool/ci/lint_workflow.sh` asserts this exact `queue: max` /
`cancel-in-progress: false` policy and filters only the obsolete schema error.
All other diagnostics remain fatal. This workaround records validator lag,
rather than removing the release queue or claiming an unfiltered schema pass.

## Repository configuration before the first push

1. Create/select the destination GitHub repository and configure its Git remote.
   No remote, commit, tag, release, branch rule or repository setting is changed
   by this implementation.
2. Enable Actions and the matrix's hosted runners. The workflow grants read-only
   repository access by default and `contents: write` only to the publish job.
   Ensure organization policies/tag protection allow that job's releases.
   Land workflow definitions on the default branch before publishing a develop
   commit that introduces/changes them: GitHub's release API can reject a
   `GITHUB_TOKEN` release targeting workflow changes outside the default branch.
   This workflow does not add a personal access token to bypass that restriction.
3. Configure these **Actions repository secrets**, using a persistent owner-held
   Android signing keystore:

   | Secret | Contents |
   | --- | --- |
   | `ANDROID_KEYSTORE_BASE64` | Base64 of the JKS/PKCS12 keystore |
   | `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
   | `ANDROID_KEY_ALIAS` | Signing key alias |
   | `ANDROID_KEY_PASSWORD` | Signing key password |

   Publishing fails if any is missing; it never falls back to the debug key.
   PR builds use debug signing and do not receive these secrets. Signing files
   are private, ignored, and removed by an `always()` cleanup step. No Apple or
   Windows signing secret is needed for the initial unsigned/ad-hoc builds.
4. Review the source snapshot before staging. ROMs, firmware, keys, application
   data, tool caches, build outputs, signing files and future Flutter crash logs
   are ignored. The tracked bootstrap `flutter_01.log` was removed from the
   current tree after preserving an identical ignored copy at
   `.tool-cache/github-ci-bootstrap-flutter.log`. Existing local Git history was
   not rewritten. Project licensing and public/private visibility remain the
   owner's repository decisions.
5. Push a feature branch and open a PR against `develop` to exercise the matrix
   without publication. Confirm all required jobs and inspect the five packages.
   A push/merge to `develop` then publishes the next candidate; `main` publishes
   the next stable. Each release includes the current capability limitations.

No personal access token, private RomM test account or application password is
needed. `GITHUB_TOKEN` is supplied by GitHub only to the publisher. PR checkout
credentials are not persisted, and `pull_request_target` is not used.

## Local checks, outputs and cleanup

From the repository root:

```sh
devbox --config tool/ci/lint run check
devbox run -- flutter --suppress-analytics pub get --enforce-lockfile
devbox run -- dart format --output=none --set-exit-if-changed lib test tool
devbox run -- flutter --suppress-analytics analyze --no-pub
devbox run -- flutter --suppress-analytics test --no-pub
```

The release regressions use temporary local Git repositories and fake GitHub
responses. They exercise tag/channel arithmetic, reruns, PR isolation, stale
ownership, invalid/missing/mixed artifacts, upload/readback failure, immutable
public releases and signing-property escaping. They publish nothing.

On the pre-provisioned Mac, the same package path can be exercised without GitHub:

```sh
RELEASE_VERSION=0.1.0-pr1.1 BUILD_CORE=0.1.0 BUILD_NUMBER=1001 \
TARGET_PLATFORM=macos TARGET_ARCH=universal GITHUB_SHA="$(git rev-parse HEAD)" \
bash tool/ci/run.sh dart tool/release/package.dart
```

`dist/` must be empty before packaging. The command builds in `build/` and writes
the ZIP/checksum/JSON into ignored `dist/`; it does not launch an emulator or
publish anything. Preserve a wanted previous `dist/` before rerunning. To clean
these outputs remove `dist/`, `build/`, the relevant project `.tool-cache/android`
directory and `tool/ci/*/.devbox` as appropriate. Do not remove `broomm-data` or
other progress data. A release publication check/command requires GitHub event
identity and should run only in the authorized workflow.

## Verification record

Workflow implementation and locked tool resolution were prepared on macOS,
2026-10-26, against the existing local base `4c28719` plus the cumulative working
tree. The root Flutter Devbox pin/lock are unchanged. Local validation results and
remaining hosted/native checks are recorded in IMPLEMENTATION.md. No GitHub
workflow execution, remote push, real release publication, Linux/Windows package
execution or Android APK/device execution is claimed by local Dart tests.

Local analysis, all 337 Flutter tests and six native Mac tests pass; the latter
retain two existing SDK deployment-target link warnings. The locally built
universal package passes source/fresh-extraction signatures and native version
readback. The clean version CLI, formatter and workflow/ShellCheck checks pass,
with the documented queue-schema exception. Exact hashes, retained diagnostics
and commands are in the [machine-readable record](github-releases.json).

### First hosted failures and corrections — 2026-10-26

The owner supplied six failing job logs from the first hosted run at
`b3fddece07a1198d44522c8841f5ed80482dd3b1` and confirmed that the Android package
built successfully with the configured signing secrets. That is owner-reported
build evidence; Android device/emulator integration is still a separate check.

| Failing boundary | Correction |
| --- | --- |
| macOS Flutter test: missing native writer guard | Compile the actual guard in the test's temporary project; no previous `build/native` is required. |
| Linux/Windows setup navigation tests | Inject a macOS recipe manager for presentation-only tests. Production still reports missing native emulator packs on unsupported hosts. |
| Windows add-on inventories and artwork cleanup | Derive portable relative paths and filenames from native file URIs. Unknown files and symlinks beside an old artwork choice remain protected. |
| Windows checksum and Linux/Windows firmware copies | Reuse streaming Dart hashing outside the UI isolate and regular Dart filesystem copies on those hosts; retain macOS batched hashes/APFS clones. |
| Windows PS2 fixtures | Explicitly seek to the start after extending a memory card. Windows `truncate` moves the file position; these fixtures previously wrote their header at EOF. |
| Windows download test cleanup | Finish queue/cloud work while driving the widget clock and real I/O, then remove temporary storage after the native queue handle closes. Compare native file identities as URIs. |
| macOS native window test | Fit the chosen frame to the actual visible screen, retain exact frame/style/level assertions, and include screen details on failure. Emit xcresult failure summaries into CI logs. |
| Linux x64/ARM64 builds | Pin the coherent native dependency snapshot described above and expose full linker diagnostics. |

The supplied native log identifies the failing window test but omits its assertion
details. Its fixed 1100×760 frame was unsuitable for smaller runner displays;
the corrected fixture passes locally. A hosted rerun is still needed to confirm
that this explains that runner's failure. No test is skipped and no timeout is
increased by these corrections.

Local follow-up verification on macOS ARM64: **342 Flutter tests**, clean analysis,
216 formatted Dart files, workflow/ShellCheck validation and **six native macOS
tests**. The host application and all three native libraries were rebuilt. The
two existing XCTest deployment-target link warnings remain. There is no new
Windows or Linux native execution result yet, and no release was published by
this follow-up. Exact source/log fingerprints and limits are in the
[follow-up record](github-ci-followup.json).

To reproduce locally, use the checks above; the Flutter suite now builds its own
small native writer-test dependency on macOS. For the native host tests, run
serially with interactive sessions closed:

```sh
devbox run -- bash tool/build_bridges.sh
devbox run -- bash tool/build_app.sh --portable --no-pub
devbox run -- bash tool/test_macos.sh
```

The debug application is in `build/macos/Build/Products/Debug/broomm.app` and native
results are in `build/macos/Logs/Test/Native-*.xcresult`. The tests use temporary
storage and disposable test credentials; they do not open a ROM or contact RomM.
Remove only the generated `build/` and ignored test logs when no test/native
child is running. Keep normal game and progress storage. After committing and
pushing the corrections, inspect the complete hosted matrix before publication;
rerunning the old commit alone does not include these fixes.

### Second hosted CI corrections — 2026-10-26

The next four supplied logs check out
`208dda7dc6e3d80f697377cd01b069f48a6405b7`. Windows now reaches ten failing tests,
down from 28. Linux checks and both Linux package jobs stop during Devbox
bootstrap, before tests or compilation. Their cache-cleanup suggestion is generic;
the reproduced failure is invalid generated Nix, not evidence of corrupt caches.

| Failure | Correction and boundary checks |
| --- | --- |
| Generated `gtk3.` output in Devbox's Nix flake | Use `#gtk3^out,dev`; regenerate the lock. Reproduce the old syntax error, then generate the real environment and run GTK/GLib/GIO pkg-config queries successfully. |
| RPCS3 uninstall rejects its own profile after Windows enumeration | Compare absolute directory URIs while retaining account/emulator ownership validation. Existing multi-profile deletion tests stay enabled; new cases reject a copied owner record outside managed storage and another account's record inside the expected directory. |
| Switch uninstall deletes package bytes still referenced by another owner | Recognize metadata by native leaf name, normalize file references to URIs and compare against the package directory including its trailing separator. Test shared owners, an external native reference, later cleanup after removing that reference, and a sibling directory that cannot retain a generation. |
| Repeat Switch firmware preparation thinks existing NCAs are absent | Match the enumerated NCA leaf name instead of a slash-prefixed native path. Keep repeat/no-download checks for both Eden and Ryubing and confirm an incomplete existing tree is preserved for explicit repair. |

Local verification: **348 Flutter tests**, clean analysis, **216** formatted Dart
files, workflow/ShellCheck validation and a rebuilt portable macOS debug app.
The new Devbox check runs on macOS using the actual Linux CI manifest: the
generated shell loads, GTK reports **3.24.43**, GLib/GIO **2.80.4**, and full
compiler/linker flag queries succeed. This establishes Devbox's generation/output
selection and the selected SDK graph on this host; it is not Linux compilation
or native Windows execution. No tests are disabled or timeouts enlarged.

To check environment generation from the root without printing the environment
(whose output may contain private local values), run:

```sh
devbox --config tool/ci/linux run -- pkg-config --modversion gtk+-3.0 glib-2.0 gio-2.0
devbox --config tool/ci/linux run -- pkg-config --print-errors --cflags --libs gtk+-3.0 glib-2.0 gio-2.0
devbox run -- flutter --suppress-analytics test --no-pub test/ps3_addons_test.dart test/native_packages_test.dart test/switch_firmware_test.dart
```

Expect the versions above and successful ownership, retention, deletion/retry and
firmware tests. The commands use project-managed dependencies and temporary test
data, with no RomM account, real ROM or system emulator configuration. Devbox
generates ignored files under `tool/ci/linux/.devbox`; normal game/progress storage
is outside this test data. The full suite and macOS build commands remain above.
A new hosted run must contain these corrections; Windows execution and native
Linux compilation remain pending. No commit/push/release or cache deletion is
performed by this follow-up. See [the second follow-up fingerprints](github-ci-second-followup.json).

### Third hosted CI corrections — 2026-10-26

The next three supplied logs are from
`cf27b39bef293bef31908e422280f1d9ad6d485c`. Windows is down to three failing
Switch package tests. Both Linux builds pass environment generation and reach the
linker, where newer Pango 1.57.1 is mixed with the pinned Pango 1.52.2/GTK stack.
The verbose link commands reveal Flutter's wrapper adding newer runtime search
paths after the earlier environment cleanup. Clearing flags only before invoking
Flutter did not exercise or protect this boundary.

| Failure | Correction and regression boundary |
| --- | --- |
| Switch indexes retain a renamed temporary package directory on Windows | Relocate paths by normalized file URI before publishing updates/DLC JSON, then write native destination paths. Reuse that identity for retained references. Cases cover mixed separators in both indexes, UNC paths, encoded filename characters and unrelated metadata. The existing shared-owner/deletion tests remain enabled. |
| Linux linker mixes two GTK/Pango graphs | Capture Devbox's target pkg-config path; restore it in CMake and both compiler shims after Flutter's wrapper. Clear competing flags and search paths there, retaining the pre-provisioned Ubuntu Clang/linker. |
| FindPkgConfig's private queries lack development metadata | Expose the existing pinned GTK graph's private development outputs and check full dynamic/static flags up front. Actual Linux x64 and ARM64 `.pc` graphs now resolve using the pinned host pkg-config tool without running target binaries. |

Local verification passes **350 Flutter tests**, clean analysis, **217** formatted
Dart files, workflow/ShellCheck and a portable macOS debug app rebuild. The
completed Devbox environment loads on macOS and full static GTK/GLib/GIO queries
succeed. A small native GTK/GLib/GIO program compiles, links and runs through the
production CMake shim despite deliberately invalid inherited compiler/linker/SDK
flags; literal paths/arguments with spaces survive and missing SDK selection
fails before configuration. That probe uses the Devbox macOS Clang 21.1.8 and
does not execute the Linux compiler shims. Its intermediate missing-metadata
diagnostics and final clean result remain in the fingerprinted logs.

For the actual Linux build, use a provisioned Ubuntu 24.04 host with Clang 18:

```sh
devbox run -- flutter --suppress-analytics test --no-pub test/native_packages_test.dart test/switch_package_paths_test.dart
TARGET_PLATFORM=linux bash tool/ci/run.sh bash tool/ci/build_linux.sh --release
```

The second command selects `tool/ci/linux`, checks both dependency queries and
builds the application with the sanitized native tools. Expect no missing private
pkg-config modules and no newer Pango/GTK search paths in the native link command.
Use the workflow for separate x64/ARM64 packaging and runtime dependency auditing.
Local native Windows tests, Linux compilation and a complete hosted matrix remain
pending; metadata inspection and a macOS linkage probe do not establish them.
These checks use temporary fixtures, ignored `.tool-cache`/Devbox/build outputs
and Nix-managed dependencies. They do not access RomM, modify emulator/profile
data or require cache deletion. Remove diagnostic fixture files only after their
processes exit. No tests are disabled, assertions relaxed or timeouts enlarged.
No commit, push, tag, release or signing change was made. See [the third follow-up
fingerprints and exact verification commands](github-ci-third-followup.json).

### Fourth hosted CI follow-up — 2026-10-26

The three supplied logs now test
`988353f26a3e21f69f4ed73e66aa5987826f1cf9`. Windows reports one failure: the PS2
engine-switching cloud-save round trip reaches its 30-second timeout. Teardown
then tries to remove files still owned by an asynchronous save worker. The prior
Switch package failures are absent. Both Linux builds stop earlier, at the new
static pkg-config preflight: `xtst`, required by `atspi-2`, is not exposed.

The previous Linux check collected pkg-config directories from the entire Nix
runtime closure. That included XTest metadata which Devbox did not propagate
into the build environment. The corrected diagnostic starts at the declared
SDK outputs and follows only `nix-support/propagated-build-inputs`; default host
pkg-config directories are disabled. It reproduces the supplied `xtst` failure
for both Linux architectures before the change. Adding the existing pinned
`xorg.libXtst` primary output to the manifest/lock makes both full dynamic/static
queries pass. No development output selector is needed for this package.
This is target metadata inspection on macOS, not native Linux execution.

The PS2 test uses a full 8,650,752-byte card with repeated durable snapshots,
upload readbacks and two build-specific state groups. Its isolated local round
trip completes in about eight seconds. The Windows log does not identify its
pending phase, so contention is a hypothesis, not an established Windows cause.
CI now runs the two `full-size-save` tests in a separate, single-suite step on
every checks host; the main step runs the remaining tests. The save step still
runs after an earlier check failure unless the job is canceled. All assertions,
native card sizes and the default 30-second limits remain. `dart_test.yaml`
declares the tag without changing default local test selection or timeouts.

Follow-up on 2026-10-30: the isolated Windows trace for `df00f8e` establishes
the cumulative deadline problem. The two-emulator cloud round trip reaches
every phase's end at **51,182 ms**, after the default 30-second test timeout.
PCSX2 after-play ends at 13,131 ms, ARMSX2 before-play at 20,959 ms, ARMSX2
after-play at 43,171 ms, and the final PCSX2 sync at 51,182 ms. This is a
completing series of real-card captures/restores/readbacks, rather than a stalled
individual operation. That single end-to-end test now has an explicit bounded
**90-second** budget. The other card test, data sizes, integrity/state assertions,
worker-drain teardown, application deadlines and native updater's eight-second
checks remain unchanged. The Windows updater fixture independently passes in
its dedicated step. Raw phase evidence is retained in
`.tool-cache/research/windows-updater-test/windows-job-native.log`.

The round trip retains phase timings for failure output. Both full-size cases
drain their complete asynchronous workflow before fixture cleanup; if a worker
cannot drain, teardown reports and retains its directory. An isolated copy with
a deliberately forced **500 ms** timeout fails as expected, then finishes its
approximately eight-second save workflow before cleanup, without a secondary
file-deletion failure. The passing cases still exercise actual native card
payloads, exports/imports, retained states and cloud readbacks against fake RomM.

Reproduce the CI partitions from the project root:

```sh
devbox run -- flutter --suppress-analytics test --no-pub --reporter expanded --exclude-tags full-size-save
devbox run -- flutter --suppress-analytics test --no-pub --reporter expanded test/playstation_test.dart --tags full-size-save --concurrency=1
```

Both commands must pass; expect **348 + 2 = 350 tests** on this macOS host.
The ordinary `flutter test` command still includes all tests. The existing
workflow lint, analysis and formatting commands remain applicable. The Linux
build command above exercises the actual corrected preflight on Ubuntu.

Local analysis, **217**-file formatting, workflow/ShellCheck, both test partitions
and both restricted Linux metadata queries pass. Windows timeout resolution,
native Linux compilation/bundle audit and a complete successful hosted matrix
remain pending. No product code or native sources changed, so no new application
build or native app-test result is claimed here. Diagnostics are retained under
ignored `.tool-cache`; normal fixtures clean up after their workers finish.
There are no test skips, assertion/timeout relaxations, OS installs, signing
changes, owner-data effects, Git commits, pushes, tags or releases. See [exact
commands, retained diagnostics and fingerprints](github-ci-fourth-followup.json).

### Fifth hosted Linux build correction — 2026-10-26

Both supplied logs at `4c366be55013f35dc243ddd6da9e8226ce8741be` pass the
dependency preflight and Flutter/Dart assembly, then fail compiling
`linux/runner/my_application.cc`: GDK's `gdkx.h` cannot find `X11/Xlib.h`.
The compile command includes GTK's public include paths but lacks the SDK's
libX11/xorgproto paths. These development files are already present; the runner
was missing a declared build dependency, rather than another Devbox package.

The root Linux CMake project now imports `x11` through pkg-config and the runner
links `PkgConfig::X11`, which supplies its include paths and link input. The
Linux preflight includes `x11` in both shared/static queries. Window-manager
detection and backend selection are unchanged. No dependency manifest or lock
needs updating for this correction.

Verification now exercises the failing source, beyond metadata queries:

- GTK-only flags reproduce the exact missing-Xlib error in the actual runner
  for both x64 and ARM64 Linux targets.
- An object-only CMake harness consumes the real project's dependency/settings
  declarations and the real runner CMake target. All three source objects
  (`main.cc`, `my_application.cc`, generated plugin registrant) compile for each
  Linux architecture with the production `-Wall -Werror` settings.
- ELF inspection confirms six relocatable objects with the expected x64/ARM64
  machine IDs. Both application objects reference the X11 window-manager branch,
  and both generated link specifications contain the pinned libX11 input.
- Both complete shared/static preflight queries and workflow/ShellCheck pass.

These are cross-compilation checks on macOS using approved Xcode Clang 21.0.0,
the pinned SDK's GTK/GLib/X11 headers, GCC 13.3 C++ headers and glibc 2.39 Linux
headers. They use the pinned Flutter 3.47 SDK's Linux public headers. The private
object-only harness supplies CMake's compiler-work/ABI cache values because it
has no Linux linker/loader; it does not link or execute a Linux application.
Production CMake and native CI keep their ordinary compiler, ABI and link checks.
This establishes actual source/object compilation and target flag wiring, not a
successful native Linux build, final linking, bundle audit or runtime acceptance.

On a provisioned Ubuntu 24.04 host with Clang 18, from the project root:

```sh
TARGET_PLATFORM=linux bash tool/ci/run.sh bash tool/ci/build_linux.sh --release
```

Expect all runner source files to compile with the X11 include paths present.
Use the workflow for architecture-specific packaging and host dependency audits.
The ignored `.tool-cache/ci-fifth-*` directories retain the exact compiler commands,
objects and diagnostics; they may be removed once those check processes exit.
The additional validation headers are fetched through the existing pinned Nix
snapshot into its managed cache, without OS package installation. No real game,
emulator configuration or progress is used. Dart/application behavior is unchanged;
the Flutter suite and native macOS tests were not rerun or claimed anew. No tests
are disabled or limits relaxed, and no Git commit/push/tag/release or signing
change is made. The supplied logs contain no new Windows result. See [revision,
source/header/object fingerprints and exact commands](github-ci-fifth-followup.json).

### Sixth hosted CI follow-up — 2026-10-26

The two supplied logs test `087aaa1889f1c9fb46e7a04fcaee070054aa8ccf`.
The macOS app and native test command finish successfully. That job fails in
`actions/upload-artifact`, with `getaddrinfo ENOTFOUND
productionresultssa16.blob.core.windows.net`. This is a result-upload DNS failure,
not an XCTest failure. No native test, assertion or upload requirement is changed;
rerun the failed job in GitHub Actions. The existing XCTest SDK link warnings are
warnings, not the reported failure. The log does not include individual test counts.

Linux ARM64 completes compilation, linking and Flutter bundle installation. Its
dependency audit then finds `libepoxy.so.0` in the Nix store. The old script patches
and audits one ELF at a time, so auditing the launcher can load an engine that has
not been prepared yet. Inspection of the exact locked Flutter 3.47 engines confirms
both architectures have SDK RUNPATHs; ARM64's includes the precise libepoxy path
printed by the hosted loader. Checking binaries in another traversal order must
not determine whether a portable bundle is accepted.

`check_linux_bundle.sh` now collects the ELF files, prepares every bundle-local
RPATH/NEEDED entry, then audits every file. The host loader still runs without
`LD_LIBRARY_PATH`, and unresolved libraries, SDK paths/interpreters and nonzero
loader results remain fatal. Failures name the affected binary and preserve the
loader's diagnostic. Only produced bundle files are patched; the SDK is unchanged.

`test_linux_bundle.sh` adds three native regression cases to each Linux build job:
both forced discovery orders must produce relocatable working executables; a
missing transitive library must fail; and an SDK interpreter must fail. Tiny C
fixtures use the runner's existing Clang 18 and host libraries in temporary storage.
An isolated fake SDK directory reproduces the engine RUNPATH condition without
writing to the real SDK or `/nix/store`.

On a provisioned Ubuntu 24.04 host of either target architecture, from this root:

```sh
TARGET_PLATFORM=linux bash tool/ci/run.sh bash tool/ci/test_linux_bundle.sh
TARGET_PLATFORM=linux bash tool/ci/run.sh bash tool/ci/build_linux.sh --release
TARGET_PLATFORM=linux bash tool/ci/run.sh bash tool/ci/check_linux_bundle.sh build/linux/arm64/release/bundle
```

Use `x64` instead of `arm64` in the final path on x64. Expect three regression
PASS lines, then an app bundle whose dependencies resolve outside the SDK. The
regression fixtures clean up automatically; the app build remains under `build/`.
The full packaging job archives only a bundle that passes this audit.

Local workflow/ShellCheck and shell syntax checks pass. A private probe uses the
actual pinned engine/executable ELF files and native macOS `patchelf`/`readelf`:
the previous script fails for launcher-first discovery, the correction passes
metadata/order checks in both orders on both architectures, and loader-error/SDK
interpreter rejection remains enforced. **The probe models the loader boundary;
it does not execute Linux binaries, the native regression suite or real `ldd`.**
New native loader/relocation tests and the complete hosted matrix therefore still
need a run containing these changes. No new Flutter or macOS app-test run is
claimed for unchanged application code. See [input hashes, exact commands,
artifact fingerprints and limits](github-ci-sixth-followup.json).

Ignored `.tool-cache/ci-sixth-*` holds the probe, private copies and diagnostics;
those fixtures may be deleted after its process exits. Engine artifacts were
fetched from the existing lock through the managed Nix cache; no OS dependency,
global SDK change or shipped runtime dependency is introduced. No owner games,
saves, emulator settings, signing secrets or Git publication are changed.

Primary references: [GitHub workflow concurrency and queue semantics](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency),
[release API and draft behavior](https://docs.github.com/en/rest/releases/releases),
[Devbox install action](https://github.com/jetify-com/devbox-install-action),
[Flutter action inputs](https://github.com/subosito/flutter-action),
[Ubuntu 24.04 runner inventory](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md),
[pinned GTK recipe](https://github.com/NixOS/nixpkgs/blob/5ed627539ac84809c78b2dd6d26a5cebeb5ae269/pkgs/development/libraries/gtk/3.x.nix),
[pinned GLib recipe](https://github.com/NixOS/nixpkgs/blob/5ed627539ac84809c78b2dd6d26a5cebeb5ae269/pkgs/development/libraries/glib/default.nix),
[Dart Windows truncate implementation](https://github.com/dart-lang/sdk/blob/3.13.0/runtime/bin/file_win.cc#L236).

### Android provider fixture corrections — 2026-10-30

The supplied Windows Server 2025 log for `d870e0a` contains five failures:
four MMJ shared-save tests and the Astris content-isolation test. MMJ's fake
DocumentsProvider enumerated native host paths by substring, leaking Windows
backslashes into its Android document keys. Production correctly rejected these
unsafe keys. Astris's assertion compared a native Windows filename against the
literal `/switch-astris/` substring. Neither failure requires a runtime change.

Both Android folder fixtures now derive relative document names from decoded URI
segments. They emit the same slash-separated transport as the actual provider,
while preserving names containing spaces, Unicode, percent and hash characters.
The retained-MMJ-file check uses its URI leaf. Switch checks compare native file
leaves and the exact owned Astris package-directory URI, and verify the selected
file exists. Production path validation, assertions about ownership/restoration,
timeouts and native-runner coverage remain intact.

Three new host-independent cases explicitly construct Windows drive and UNC
URIs, preserve POSIX names and verify outside-root/unsafe-path rejection. These
run on every checks host, so the Windows separator contract is exercised on the
development host as well. The affected suites pass **33 tests**; all **458 Flutter
tests** pass on macOS ARM64, analysis is clean and formatting leaves all 270
source files unchanged. The first sandboxed attempt failed before loading tests
because Flutter could not bind loopback; the authorized network-enabled run
passes. [Evidence and retained log hashes](windows-test-paths.json) distinguish
these checks from actual Windows execution.

Reproduce locally:

```sh
devbox run -- flutter --suppress-analytics test --no-pub --reporter expanded \
  test/android_document_paths_test.dart test/mmj_shared_saves_test.dart \
  test/android_folder_sync_test.dart test/native_packages_test.dart
devbox run -- flutter --suppress-analytics test --no-pub --reporter expanded
devbox run -- flutter --suppress-analytics analyze --no-pub
devbox run -- dart format --output=none --set-exit-if-changed lib test tool
```

Actual Windows acceptance remains the existing `checks (windows-2025, windows)`
job, including its separately scheduled full-size-save and native-updater steps.
No tests are disabled and no workflow test timeout is increased. Application
code is unchanged, so the verified [current macOS package](../build/releases/Broomm-macOS-android-saves.zip)
still contains the current runtime. Ignored `.tool-cache/research/windows-document-paths/`
contains logs and may be removed after testing; no owner data was touched.

The native follow-up run for `d314d27` still reports a Windows failure; its
full-size save step passes. The public job API exposes incomplete step details,
and downloading detailed logs requires repository authorization unavailable to
the normal credential helper. No Windows pass is inferred from the local result.

CI now uses Flutter's built-in GitHub reporter together with its JSON file
reporter for the main, full-size and updater suites. A small SDK-only reader
publishes bounded failure names, error details and stacks as check annotations;
JSON reports are retained as failure artifacts. It escapes workflow commands,
retains late errors and missing-detail failures, and leaves the original test
commands' exit statuses intact. A disposable deliberate failure verifies exit
status 1 and a detailed annotation; a complete passing run verifies no failure
annotations. All **461 tests** pass locally with this reporting path, including
three annotation regressions. Analysis, formatting and workflow lint pass. This
reporting change provides diagnostics for the next native run; it does not claim
to fix an unidentified failure or establish Windows acceptance.

The diagnostic run `1d4b545` identifies the remaining two failures precisely:
Windows directory enumeration rejects the MMJ capture directory's **276-character**
wildcard path under `C:\Users\RUNNER~1\AppData\Local\Temp`. The formerly failing
separator cases are no longer present; full-size saves and the native updater
both pass. The checks job now sets child-scoped `TEMP`/`TMP` to GitHub's
runner-owned short temporary root, and the MMJ fixture uses a shorter prefix.
For the reported hierarchy this reduces the wildcard path to **243 characters**
and its nested child listing to **252**, below the Windows enumeration limit.
No registry, system temp setting, runtime save layout, test timeout or assertion
is changed. The two existing MMJ capture/recovery cases remain the native
regressions; the subsequent Windows job establishes the final result.
