# Development environment and verification

Status: the root Devbox environment pins Flutter 3.47.0-sdk-links with Dart 3.13.0. The [GitHub workflow and version policy](github-releases.md) now define the five native package targets, independent checks and publication gates, with project-scoped Linux/Android/lint Devbox environments. Native hosted matrix execution remains pending; prepared workflows do not establish runtime support. The earlier [injection experiment](research/injection-validation.md) and [walkthrough](../experiments/injection/README.md) retain their own evidence.

## Environment policy

The owner requires Devbox-managed development and no new dependencies installed into the operating system. Pre-provisioned Xcode/Apple SDK and Windows C++/Windows SDK hosts are approved. Do not use Homebrew, apt, global Dart packages, global SDK managers or machine-wide compiler installation as a setup shortcut. The native experiment resolved its project Devbox environment and installed no OS dependencies.

Devbox provides project-scoped packages and scripts using Nix. Pin supported tool versions and retain its lockfile, with explicit platform-specific packages where needed. It manages the environment, rather than turning one host into all native build targets. Its documented package-platform list covers Darwin/Linux, so a native Windows environment cannot be assumed. [Devbox](https://www.jetify.com/devbox), [version pinning](https://www.jetify.com/docs/devbox/guides/pinning-packages), [platform-specific packages](https://www.jetify.com/docs/devbox/guides/platform-specific-packages).

Proposed bootstrap inventory, subject to the owner dependency review:

- Pinned Flutter SDK with its compatible bundled Dart SDK; app package lockfile.
- C bridge compiler/build system where the selected desktop integration needs it; bundle precompiled libraries for users. Application workflows remain Dart, with no Go code/helpers or PGCS application-code import.
- Linux Flutter build libraries and tooling from Devbox, with explicit runtime/driver access verification.
- Android JDK, SDK/NDK/build tools/Gradle inputs and project-local caches at exact compatible versions. SDK license acceptance is explicit; do not silently accept new licenses in an init hook.
- Test/format/lint utilities supplied by the project environment. Native build recipes must identify dependencies unavailable from it.

Keep download caches, `PUB_CACHE`, Gradle user data and Android SDK paths explicit and project-managed where supported. Do not repurpose `HOME` or change user shell profiles to influence tool discovery. Some Nix-supplied SDKs are immutable; use a writable, versioned project-managed SDK/cache arrangement when Flutter requires writes, rather than global installs or permissions changes.

The research bootstrap pins and locks the Flutter/Dart toolchain and demonstrates the native probe scripts on macOS. The prototype adds app build/check scripts; the [release follow-up](github-releases.md) adds CI and Linux build inputs with explicit remaining native verification. A comprehensive local doctor command remains pending. Do not copy PGCS's Go-focused Devbox manifest or its `@latest` selections.

## Native toolchain constraint

Flutter supports native desktop builds, but each host requires its own native tooling. Its setup documentation requires Xcode for macOS and Visual Studio's C++ tooling for Windows. Devbox is not evidence that these proprietary host SDKs are available as ordinary Nix packages. [Flutter desktop support](https://docs.flutter.dev/platform-integration/desktop), [macOS setup](https://docs.flutter.dev/platform-integration/macos/setup), [Windows setup](https://docs.flutter.dev/platform-integration/windows/setup).

The policy is settled: use **pre-provisioned native SDK hosts plus Devbox-managed project dependencies**, without new OS dependency installation. Do not ask again whether those existing SDKs are permitted. Do not execute system-wide `xcode-select` or install Xcode/MSVC as a bootstrap shortcut; report an unavailable build host if its required SDK is missing.

| Target | Proposed build/verification arrangement | Unresolved evidence |
| --- | --- | --- |
| Linux | Native Linux Devbox environment; real host graphics/input smoke tests | Pin package set and baseline distro/runtime; verify Steam Runtime/gamescope separately |
| macOS | Native Mac with pre-existing approved Xcode/SDK; Devbox for project tools | Verify SDK versions, signing and packaged app; first hands-on target alongside Linux |
| Windows | Native Windows runner with pre-provisioned approved C++/Windows SDK; reproducible project bootstrap | Devbox/native-Windows strategy is open. WSL checks are Linux checks and do not verify the native Windows app |
| Android | Managed SDK/JDK/build environment; Android emulator plus physical handheld tests later | Choose OS/API/architecture baseline; verify installed-app ROM/save/state handoff. No native injection/overlay integration |

macOS and Linux are the agreed first development/verification hosts. Windows and Android follow with explicit native coverage. CPU architectures and minimum OS/API versions still need exact build-matrix selection; they do not reopen the SDK approval or host priority. See [confirmed decisions](decisions.md).

## Intended commands after bootstrap

The bootstrap milestone should provide these scripts, document prerequisites, and update this section with their actual behavior and output paths:

```sh
devbox run doctor
devbox run format-check
devbox run analyze
devbox run test
devbox run build-linux
devbox run build-macos
devbox run build-windows
devbox run build-android
```

Only run a native build script on a compatible configured host. No script may install an OS dependency to make itself pass. A doctor report should distinguish a missing optional target toolchain from a failure of the currently requested build. Until these scripts exist, use the documentation index in [README.md](../README.md) to review this planning repository.

## Verification layers

| Layer | Useful evidence | What it does not establish |
| --- | --- | --- |
| Pure Dart/domain tests | Profile identity, installation state transitions, reconciliation, queue/retry and failure behavior | Real server/emulator behavior |
| Flutter widget/focus tests | Focus graph, controller actions, modals, virtual keyboard and conflict decisions | Physical controllers or gameplay handoff |
| Native ABI/contract tests | Bridge forwarding, wrong versions, input neutrality, process/IPC errors and locks | Port assignment in an actual emulator |
| RomM integration fixtures/server tests | Authentication, pagination, ownership, conflicts, transfers and interrupted responses | Emulator save-format compatibility |
| Native packaged smoke checks | App starts, bundled libraries load, private storage and process lifecycle work | All devices/graphics/session combinations |
| Owner-performed gameplay/visual checks | Real player ports, Steam handoff, render overlays and cross-device resume | Untested hosts/builds or other adapter combinations |

CI should run format/analyze/domain/widget checks and native host jobs independently, with full logs and revision identity. Build bridge artifacts from audited source and verify packaged architecture/dependencies. Add native sanitizer/race checks appropriate to the chosen languages without blocking unrelated host results behind a single job.

The first hosted run exposed native-path assumptions and macOS-only filesystem tools in shared workflows. Native enumeration now yields portable add-on identities; Windows/Linux use existing Dart digest and file-copy code while macOS retains its native optimizations. Presentation tests inject their recipe host rather than enabling production native packages. The macOS writer fixture builds its own native guard, and widget tests drain download work before removing temporary storage. Keep these tests enabled on their native CI hosts. Linux GTK/pkg-config are pinned to the existing glibc 2.39 snapshot; metadata evaluation is distinct from compilation. See the [hosted failure follow-up](github-releases.md#first-hosted-failures-and-corrections--2026-10-26).

Prioritize failure tests that protect progress: interruption before/after publication, upload accepted with lost response, profile switch while work is queued, stale baseline, two-device conflict, corrupt/missing working tree, live writer after launcher wrapper exit, disk-full, revoked token and incomplete remote listing. Use controlled clocks, locks and fail points rather than timing luck.

## Manual acceptance record

For every integration, retain the exact Broomm revision; OS/architecture; emulator/core/runtime/bridge version and hashes; renderer/window/input backend; Steam mode; device models/transports; profile/server identities with secrets redacted; steps; expected and observed result; and verifier.

Native UI/input verification is owner-performed unless the owner explicitly authorizes computer-use tools. Provide concrete controller/game actions and expected port/sync outcomes. Never claim to have visually inspected a display based only on logs or API success.

## macOS prototype build details

`PUB_CACHE` is project-local under `.tool-cache/pub`. No application packages beyond Flutter are added; `flutter_test` uses the pinned SDK's test dependencies. Xcode 27.0 (27A266a) is pre-provisioned. The scripts select its `DEVELOPER_DIR` only for child commands, clear conflicting Nix compiler/linker overrides for Xcode, and leave the machine's active developer directory unchanged.

The pinned Nix SDK stores framework/template files read-only. Generated host files are writable project copies. Project-local `tool/apple_tools/rsync` repairs writable modes only in generated `build/` destinations without following nested links. The `lipo` wrapper thins into a private temporary output and publishes atomically because the provisioned Xcode 27 tool rejects existing outputs. Xcode build phases prepend those wrappers. Neither wrapper changes the Nix store or machine settings. The built app includes the compiled SDL2/SDL3 bridges under `Contents/Resources/native/`; executable ABI hashes are checked against the explicit local preparation manifest.

The macOS prototype intentionally disables App Sandbox in its own development entitlements to supervise external emulator processes. Each child is instead launched with a write-denial profile protecting ROMs, original resources and the user's normal settings. This is not a distributable security boundary or production signing/notarization design. Firmware and save resources remain private in `prototype-data/`; runtime helpers are built-in macOS tools, not compilers or a Go service.

The managed setup slice keeps these same tools and native bridges. `tool/capture_tested_setup.dart` creates trusted whole-bundle inventories for the exact reviewed test builds, never as a runtime trust bypass. Setup and Home Play run in Dart; local import uses existing macOS copy/hash tools and precomputed symbol assets, with no user compiler requirement. Shared releases and private server/account profiles are separate from `prototype-data/`. See [build provenance, paths and current limits](managed-emulators-and-play.md). Run Flutter tests/renderers and native macOS builds serially to avoid races in generated ephemeral files.
