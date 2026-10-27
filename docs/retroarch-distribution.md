# RetroArch desktop distribution — 2026-10-27

## Current adoption

Broomm now uses the published [Broomm/retroarch v0.1.0 release](https://github.com/Broomm/retroarch/releases/tag/v0.1.0)
for its existing macOS ARM64 managed setup. The versioned ZIP URL, archive
size/SHA-256, executable/SDL3 hashes and all 29 bundle files are pinned. The
release uses recipe commit `21155499eb04bc5c47645d497dd11cd3300c4d3d`,
RetroArch revision `1b8917df23625bcf40b67ba6476d9bfb0d30dc65` and SDL 3.4.0.
All five published target ZIPs, manifests and checksum files passed download
digest and complete packaging-manifest verification. Their manifests report
successful native SDL/frontend probes; foreign binaries were not executed here.

| Published target | Artifact verification | Broomm integration verified in this task |
| --- | --- | --- |
| macOS ARM64 | ✅ Full manifest, inventory and checksum | ✅ All 15 current cores exercised: 17 additional platform routes plus SNES; native input/pause, state and scoped save round trips |
| macOS Intel | ✅ Full manifest, inventory and checksum | ⏳ Native core/bridge package acceptance |
| Linux x64 | ✅ Full manifest, inventory and checksum | ⏳ Native core/bridge and Steam/gamescope acceptance |
| Linux ARM64 | ✅ Full manifest, inventory and checksum | ⏳ Native core/bridge acceptance |
| Windows x64 | ✅ Full manifest, inventory and checksum | ⏳ Native core/bridge package acceptance |

The released frontend initially exposed a real integration bug: deprecated
`-S <file>` bypassed `savestate_directory` and selected the macOS Documents
default. Broomm's filesystem protection rejected that write. The new build now
uses the configured private directory and native content basename; cloud capture
uses the same name, including multi-chip arcade ZIPs. The previous frontend keeps
its tested `game.state` contract. Exact executable/core fingerprints continue to
separate states, so old files are retained rather than labeled compatible.

Setup remains explicit. Existing previous-build selections load, resolve and
remain usable; failed verification keeps them selected. The bundled recipe selects
v0.1.0 only after successful setup. Importing the old reviewed pack explicitly
selects its old frontend and integrity inventory. Profile paths/settings, ordinary
saves, state files and previous app directories are preserved. Three upgrade
regressions cover restart, successful/failed setup and unknown selected identities;
additional state-boundary cases cover native names and old/new fingerprints.

The frontend release contains no cores. Broomm now downloads all fifteen cores
itself: eight retain their tested library hashes and seven use newly verified
official Libretro builds. No companion pack is required. See the
[public-core follow-up and running Dock icon fix](retroarch-public-cores.md).
See [setup actions and cleanup](managed-setup-downloads.md), the
[fresh macOS app](../build/releases/Broomm-macOS-automatic-cores.zip)
and [exact release fingerprints, commands and results](retroarch-release-adoption.json).
The final targeted suite passes 52 cases; native delivery/restart and gameplay
checks pass. The BIOS-core follow-up also verifies Lynx states, 3DO native saves,
both migrated/fresh Dreamcast VMUs and Saturn save/state loading and restoration.
The Saturn test's old hard-coded filename was corrected to use the resolved
native boundary; that initial failure and its passing rerun are retained.
Physical controllers and other hosts' Broomm gameplay are separate
acceptance; there was no owner-data migration or emulator auto-update.

## Earlier packaging and workflow corrections

The owner requested a standalone workflow in the sibling [`broomm-retroarch`](../../broomm-retroarch/README.md) project. That initially empty directory received its own source/toolchain locks, Devbox configuration, native build/probe scripts, archive/release regression tests, notices and [GitHub workflow](../../broomm-retroarch/.github/workflows/release.yml). That initial local preparation did not create a Git commit or GitHub publication; subsequent owner-triggered workflows produced the release adopted above.

The workflow builds RetroArch 1.22.2 at `1b8917df23625bcf40b67ba6476d9bfb0d30dc65` with shared SDL 3.4.0. Required SDL3, OpenGL Core, Slang and networking/command features are checked. Qt, FFmpeg, MCP and SDL1/2 are disabled; macOS uses OpenGL instead of Metal. These are frontend packages; cores and menu assets remain separately versioned/distributed. No PGCS code, game, firmware, BIOS, key or user progress is included.

| Target | Native runner | Status here |
| --- | --- | --- |
| macOS ARM64 | macos-26 | Exact CI binary passes locally; hosted `GET_STATUS` timeout remains unconfirmed after client-binding correction |
| macOS Intel | macos-15-intel | Hosted build still running in the inspected run snapshot |
| Linux x64 | ubuntu-24.04 | Hosted compilation/SDL pass; mandatory PulseAudio dependency corrected; runtime rerun pending |
| Linux ARM64 | ubuntu-24.04-arm | Hosted compilation/SDL pass; mandatory PulseAudio dependency corrected; runtime rerun pending |
| Windows x64 | windows-2025 | Shell isolation confirmed; test fixture command-length error corrected; native build pending |

Android is intentionally excluded: its emulator installations are external. Linux's immutable Devbox compiler/SDK baseline uses GCC 13.2.0/glibc 2.39. macOS uses the approved Apple toolchain with a declared minimum of macOS 13. Windows bootstraps checksum-pinned embedded Python, w64devkit 2.4.0 and CMake 3.31.7 into its workspace. No OS dependency installation or global SDK change is part of these recipes.

The separate project follows `version.txt` major/minor with tag-derived stable patches on `main`, candidates on `develop`, and build-only PR versions. Version selection through publication is queued. Every native target must pass packaging regressions, SDL virtual-controller input and actual frontend pause/quit checks. Binary ZIPs, per-file manifests and checksums are published with exact upstream source archives and packaging recipes. Only the final publish job receives write permission. It validates a complete same-version/same-commit artifact set, preserves existing releases/tags and uploads through a draft. See the sibling README for commands, Actions setup, output layout, interruption recovery and cleanup.

Local macOS 27.0.1/Apple M1 Pro verification passes **17 regression cases**, actionlint/ShellCheck, a complete native build, virtual gamepad press/release, SDL3 feature readback, Mach-O architecture/minimum-OS/relocation checks, deep/strict signatures, playing/paused status readback and clean QUIT. All **29 files** retain their hashes and permissions through ZIP extraction; the extracted executable starts independently. This is headless control/input-library verification, not rendered gameplay or physical-controller/injection acceptance. The sibling [implementation record](../../broomm-retroarch/IMPLEMENTATION.md) records initial failures and the corrected explicit private test paths, including the preliminary probe's cleaned-up history entry.

The local [RetroArch macOS ARM64 ZIP](../../broomm-retroarch/dist/RetroArch-1.22.2-broomm-0.1.0-local-macos-arm64.zip) is **8,119,704 bytes**, SHA-256 `15f9ced835ca428255952dac32fcc5d5e3d6664dabcaf64ed670f88382099f7c`. Its matching manifest/checksum and full local logs remain in that project's ignored output directories. No new Flutter build is required: the current [Broomm macOS application](../build/releases/Broomm-macOS-session-recovery.zip) is unchanged.

Before adopting these releases into Broomm, obtain a complete hosted release and validate each frontend/core/bridge combination on its native host. Then review immutable versioned asset URLs, archive hashes and new executable/runtime inventories in Broomm's setup/build records. These rebuilt binaries differ from the old companion package; changing a version string is insufficient acceptance. Do not silently recapture trusted hashes or claim remaining offline core archives have been replaced. Broomm's current setup JSON, managed installations, application binary and progress are unchanged by this packaging task.


## First hosted SDK correction

The owner pushed `0411d59b8ef956752cbcd98f49e10202ec997235` to `Broomm/retroarch`. Both supplied version/source job logs stop during Devbox installation: pinned Linux `libXScrnSaver` has only an `out` output, while the recipe requested `out,dev`. The selector and lock entry now request `^out`. The later HTTP 403 is the install action's failure-only cache diagnostic, not a release permission problem; no cache deletion or expanded token permission is needed.

A new independent lint-job preflight evaluates every requested SDK output on all four Unix architectures and retains JSON plus full diagnostics. The exact original configuration is rejected on both Linux targets; the fixed configuration passes 25 selectors on each Linux architecture and seven on each macOS architecture. Both corrected Nix installables resolve, all 17 regressions and workflow/ShellCheck pass, and the actual version/source commands succeed locally with source/recipe readback. The recipe check targets committed HEAD and does not claim uncommitted fixes were archived.

See the sibling [implementation follow-up](../../broomm-retroarch/IMPLEMENTATION.md) and [machine-readable evidence](../../broomm-retroarch/docs/ci-followup-1.json). Native Linux SDK installation/builds and the hosted rerun remain pending. The macOS frontend ZIP and current Flutter app remain unchanged; no new native gameplay/build or Flutter-suite result is claimed. No commit, push, tag or release was performed in this correction.

## Second hosted correction and macOS timeout

Run `40565107398` at `c9c8e49ada1640f6e639132a9b91f3144c96ed64` reaches SDL configuration on both Linux architectures, where the complete artifacts report missing XTest. The pinned SDK now includes `xorg.libXtst^out` on both architectures. Its actual substituted outputs contain the required header and correctly identified ELF/SONAME. All 66 Unix package/output selectors pass metadata validation. Windows fails before compilation because exporting the private toolchain shadows the runner's Git Bash with BusyBox. Build/probe tools now receive a child-only PATH and explicit executable lookup, preserving the runner shell.

The later macOS ARM64 log shows a successful build and SDL probe, followed by a `GET_STATUS` timeout in the actual frontend probe. The empty redirected log does not identify the cause: the pinned macOS console branch buffers its output. This hosted failure remains unresolved. An explicit flushed emulator log, child status and bounded failure stack sample now preserve the missing evidence without relaxing checks or changing global settings. Failed runtimes are diagnostic artifacts, excluded from publication. Both probes still run independently after a successful build.

All **25 regressions**, workflow/ShellCheck and local native SDL/frontend probes pass; a disposable native child confirms stack sampling works. No native Linux/Windows pass or hosted macOS fix is claimed. Binary/runtime fingerprints and both existing macOS ZIPs remain unchanged. See the sibling [current implementation record](../../broomm-retroarch/IMPLEMENTATION.md) and [second correction evidence](../../broomm-retroarch/docs/ci-followup-2.json). The next hosted run must validate the Linux/Windows corrections and supply the macOS timeout diagnostics if it recurs. No commit, push, tag, release, Flutter change or new OS dependency was performed.

The subsequent Windows log at `24cfe6ecba83d6d1955bd6ee2acc9853a554620c` confirms Git Bash and both tool-path checks now work. One large-log regression fixture then hits WinError 206 before compilation: it puts the entire diagnostic payload on the command line. That fixture now reads the same 40,054-byte payload from a temporary file, preserving every diagnostic assertion and checking Windows' serialized UTF-16 command-line limit on all hosts. All 25 tests pass locally. Production/build code and existing macOS artifacts are unchanged; Windows native build acceptance and the hosted macOS timeout remain pending. See [the third correction evidence](../../broomm-retroarch/docs/ci-followup-3.json).

## Linux runtime and macOS transport follow-up

The Linux jobs in run `40571405429` compile both upstreams and pass the native SDL input check, then fail on a mandatory `libpulse.so.0` dependency during frontend startup. Exact artifact inspection confirms that link in both frontend architectures; both bundled SDL libraries already support PulseAudio dynamically without that hard dependency. The Linux frontend recipe now disables its standalone PulseAudio backend, retaining ALSA and SDL3 audio. Select SDL3 audio for the host's PulseAudio/PipeWire-Pulse service. Full Linux loader auditing runs before startup and records every missing library, rejects build-SDK runtime leakage and prevents direct PulseAudio linkage from returning. No runtime library or OS dependency is added. Rebuilt native Linux/physical audio acceptance remains pending.

The macOS sample shows core execution, SDL input polling and command-socket polling. The exact CI binary passes the original and revised strict checks locally on macOS 27.0.1; the failing VM runs 26.6.2. The hosted timeout remains unconfirmed. The probe now binds its client explicitly to loopback before reserving a separate emulator port, verifies reply identity and preserves unexpected replies/attempts/endpoints on failure. Owned-child UDP socket inventory joins the existing stack sample. No emulator patch, global permission change, increased timeout or relaxed expected state is used.

All **31 regressions** and lint pass. Both the local and exact hosted macOS runtime pass SDL dummy-audio/controller and strict frontend feature/dependency/signature/playing/pause/QUIT checks locally. An original temporary child verifies native socket inventory, stack sampling and protocol persistence. Compilation/native checks now continue after an executed packaging-test failure so one run can expose independent problems; that failure still blocks publication. The earlier Windows fix remains included. Both existing macOS ZIPs and Flutter code remain unchanged. See the sibling [implementation record](../../broomm-retroarch/IMPLEMENTATION.md) and [fourth follow-up evidence](../../broomm-retroarch/docs/ci-followup-4.json).

## Windows compiler lookup and headless Linux EGL

Run `40575998429` at `76d7b2cda179a8b2b314e62fbb434e7ca6dd05f1` confirms **both macOS jobs now pass their native probes and packaging**. Windows passes all 31 then-current regressions and builds SDL, then RetroArch's Unix-style PATH/filename helper fails to find the real private `gcc.exe`. CC, CXX, WINDRES and PKG_CONF_PATH now carry explicit private forward-slash `.exe` paths; missing tools are refused. The unchanged upstream helper reproduces the original failure and passes with explicit compiler paths in a local Unix-host model, which does not establish native Windows execution. Separate configure details are also preserved.

Both Linux jobs now pass compilation and native SDL checks, with no mandatory PulseAudio link. Their sole unresolved library is `libEGL.so.1`, absent on the headless runners. The frontend probe supplies only the existing locked libglvnd EGL loader from an isolated test directory, strips its SDK RPATH and audits its host dependencies. It does not install OS packages, disable Wayland/EGL or ship the fixture. Whole-SDK runtime access, other missing dependencies and SDK leakage remain failures. Exact x64/ARM64 cached ELF inspection confirms matching architectures, SONAMEs, available host dependencies and GLIBC requirements below the 2.39 baseline.

All **37 regressions**, workflow/ShellCheck and diff checks pass locally. Corrected native Linux frontend/Windows runs remain pending. Existing macOS packages and Broomm Flutter code remain unchanged; no Git publication occurred. The sibling [implementation record](../../broomm-retroarch/IMPLEMENTATION.md), [walkthrough](../../broomm-retroarch/README.md) and [fifth follow-up evidence](../../broomm-retroarch/docs/ci-followup-5.json) contain reproduction commands, artifact fingerprints and verification limits.

## Windows UDP startup and Intel package-cache network failure

Run `40579927392` at `c118770fe80286964fcc42d32977130e67e09eb9` confirms both Linux architectures and macOS ARM64 pass native probes and packaging. Windows passes full compilation, SDL audio/controller checks and PE/feature inspection, then its first query receives UDP error 10054 before the still-running emulator opens its control port. The probe now records this Windows-specific port-unreachable response and continues the existing 20-second readiness wait at 250 ms intervals. Actual state/source acknowledgment and child liveness remain required; other errors, persistent unreachability and exit still fail.

Intel macOS fails during Devbox SDK downloads with `cache.nixos.org` DNS/connection timeouts, before compilation. Its compiler recipe previously passed and is unchanged. Rerun that job after network recovery; no cache clearing, new permissions, global network changes or blanket retries were added. All **41 regressions**, lint and the actual local macOS frontend check pass. Native Windows frontend acceptance and the Intel bootstrap rerun remain pending. Existing macOS downloads and Flutter code remain unchanged. See [sixth follow-up evidence](../../broomm-retroarch/docs/ci-followup-6.json) and the sibling implementation record for exact logs and limits.

## Windows package metadata

Run `40582896434` at `a1c3961f3636ef93672f6d3fa8366f464f1e61d7` passes both macOS and both Linux jobs. Windows now passes compilation and both native probes, then package verification fails because the build record stores `RetroArch\\SDL3.dll` while ZIP inventory keys use `/`. The writer now stores portable bundle-relative paths, with explicit syntax/inventory validation. Tests use real nested target layouts and a Windows-path roundtrip on every host. All **44 regressions**, lint and verification of the existing real macOS package pass locally. Exact Windows artifact readback confirms both corrected references match their files. Native Windows packaging and publication still await a fresh CI run; existing binaries, macOS downloads and Flutter code remain unchanged. See [seventh follow-up evidence](../../broomm-retroarch/docs/ci-followup-7.json).
