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

Primary references: [GitHub workflow concurrency and queue semantics](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency),
[release API and draft behavior](https://docs.github.com/en/rest/releases/releases),
[Devbox install action](https://github.com/jetify-com/devbox-install-action),
[Flutter action inputs](https://github.com/subosito/flutter-action),
[Ubuntu 24.04 runner inventory](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md).
