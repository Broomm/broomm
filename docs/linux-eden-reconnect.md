# Eden Linux disconnect/resume exit — 2026-11-03

## Observed failure

The owner's Smash session disconnected an 8BitDo controller at
15:57:36.252 UTC. Broomm requested pause, removed the native console port and
presented pairing. The same controller returned with a new SDL instance ID.
At 15:57:48.313 Eden acknowledged the new native port and resumed; 54 ms later
its Wayland connection reported:

```text
wp_commit_timer_v1: Commit already has timestamp
The Wayland connection experienced a fatal error: Protocol error
Emulator exited with status 255
```

The launcher then returned Home and retained progress for cloud-save review.
The trace establishes native emulator exit after resume, rather than a missing
controller-pairing acknowledgement. No crash stack or defective controller
hardware is inferred from these logs.

## Native comparison and correction

An explicit test uses the same supplied Smash base NSP on the owner's CachyOS
x86_64 host, reviewed Eden **0.2.1**, and two opt-in SDL virtual sources. It
creates a new isolated profile for each comparison in an existing disposable
managed installation. Only firmware and keys already on that Linux host are
provisioned locally into that profile; owner progress and console/account
identities are not copied. No RomM calls occur. The original physical 8BitDo
remains enumerated but is not assigned by the test.

| Case | Actual Qt backend | Result |
| --- | --- | --- |
| Before correction, child Wayland | `wayland`, read back from Qt | Initial play succeeds; first replacement-source resume reproduces the same commit-timer error and exit 255 |
| Before correction, child XWayland | `xcb`, read back from Qt | Three detach/reconnect/new-ID cycles, live logical buttons, one → two → one native players and normal exit 0 |
| Corrected production policy, no test backend override | `xcb`, read back from Qt | The same complete sequence passes, normal exit 0, no session problems |

`linuxLaunchEnvironment` now selects `QT_QPA_PLATFORM=xcb` **for Eden only** when
the parent provides a nonempty `DISPLAY`. This overrides the inherited Qt
backend only in that emulator child. It retains the reviewed Sharun loader,
private HOME/cwd, input bridge and XDG isolation. Both Play and Open emulator use
this shared boundary. Broomm's own backend, desktop configuration, other
emulators and non-Linux paths are unaffected. Existing configured Eden copies
are reused; setup is not required again.

This is a scoped workaround for the demonstrated Eden/Wayland reconnect failure,
not proof that Wayland is generally defective. The protocol message alone does
not identify the responsible component in Eden's Qt/Vulkan/compositor stack.
Wayland-only environments without `DISPLAY` retain their existing backend; this
workaround does not establish a fix there. Bazzite/Steam Big Picture and the
owner's real physical reconnect remain separate acceptance.

## Verification

- Three regressions cover child-only selection with an inherited Wayland
  preference, absence of an X11 display, and unchanged other-emulator policies.
- **453 Linux Flutter tests pass**, with 22 existing platform skips.
- **522 macOS Flutter tests pass**, with one Linux-only GIO skip.
- Static analysis and formatting pass. The Linux release build and full ELF
  dependency audit pass. The native comparison uses real Eden, firmware, ROM,
  main-loop pause and controller configuration, not generated configuration
  alone. It does not establish physical input or completed gameplay.
- `tool/check_linux_eden_reconnect_test.dart` is an explicit native check outside
  the ordinary suite. Prerequisites are a disposable `BROOMM_EDEN_TEST_DATA`,
  local emulator data in `BROOMM_EDEN_TEST_REFERENCE`, the existing game file in
  `BROOMM_EDEN_TEST_ROM`, and `BROOMM_EDEN_TEST_EVIDENCE`. Use the approved desktop
  connection in memory and the Linux Devbox environment. For the corrected
  default, leave `QT_QPA_PLATFORM` unset, set `BROOMM_EDEN_EXPECT_BACKEND=xcb`
  and `BROOMM_EDEN_TEST_CASE=default`, then run:

```sh
flutter test --no-pub tool/check_linux_eden_reconnect_test.dart
```

An additional packaged-app check reached server selection with fresh isolated
storage but returned SIGSEGV on immediate SIGTERM close. The faulting thread is
`io.flutter.rast`, with its top frames inside Mesa's
`libgallium-26.2.5-arch3.1.so`, not Eden. The earlier preview passed the same
immediate-close check. This does not establish the cause or a regression in the
Eden policy; the failure is retained separately in `shutdown-evidence.txt` and
is **not** counted as a passing packaged-app shutdown check. It remains a
separate application/renderer follow-up. The owner's real process was untouched.

Before-fix Wayland/XWayland comparisons and after-fix default evidence are
retained in `.tool-cache/research/eden-disconnect/`, including exact native
backend/exit logs and disposable profile paths. Private keys remain on Linux
and are not included in logs, downloaded evidence or application archives.
Fixture profiles may be removed after their writers have exited; preserve the
owner's application data and any real unsynchronized progress.

## Owner retest

Close the previous Broomm normally and run:

```sh
~/Downloads/Broomm-Linux-eden-reconnect-preview/bundle/broomm
```

Choose the existing profile and launch Smash with the existing Eden setup. Pair,
play, disconnect the controller, then reconnect and join with L1+R1. Hold Start
to resume; Eden should remain open and accept controls. Repeat through the
R3+Select menu and, if available, with a second player. Keep the existing games,
firmware, settings and progress. Use **Settings → Application → Install to
Launcher** to repoint the launcher to this new application folder.

[Linux archive](../build/releases/Broomm-Linux-x64-eden-reconnect-preview.tar.gz)
and [matching macOS preview](../build/releases/Broomm-macOS-eden-reconnect-preview.zip)
use normal application storage and the development identity with updates
disabled. The owner’s running application is not stopped or replaced during
deployment. Preview cleanup removes only its archive/extracted bundle.

Package readback:

- Linux: **11,988,495 bytes**, SHA-256 `d5d574640d4ac266b98bc0c1fba38fd6f0d0828ccbf9fb5596bdc3c01fe79711`; full archive payload/mode readback and exclusive deployment pass.
- macOS: **21,299,153 bytes**, SHA-256 `6a64d6fee384eed07b165b1b9450f0ce8bf76606d5de9592fc8a687bda7ef769`; source and freshly extracted deep/strict/all-architecture signatures, archive and asset readback pass. Ad-hoc signed, not notarized.

Both packages record the same current runtime source fingerprint.

Qt documents `xcb`/`wayland` platform names and process-specific backend
selection in [QGuiApplication](https://doc.qt.io/qt-6/qguiapplication.html#platformName-prop).
The failure and workaround claims above come from the local native traces.
