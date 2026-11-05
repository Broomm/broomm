# Thor gameplay investigation — 2026-11-04

**Deferred — 2026-11-05:** the owner stopped further Linux ARM64 work and
requested committing/pushing the current implementation for a release build.
The next milestone is [root-backed Android access](android-installation-and-saves.md#next-milestone-root-backed-storage-access).
The input/display-preference corrections remain implemented; Eden and Azahar
failures and melonDS physical window-width acceptance remain open. The owner
declined a custom Eden build. Diagnostic evidence below is not gameplay acceptance.

The owner reported three issues on the AYN Thor running Armada Linux: Smash
exits during startup in Eden, Azahar exits with code -6, and the whole melonDS
top window, including its menus, appears too narrow. The bottom melonDS display
was reported to work. This document separates those reports, native comparisons,
and the application changes made during investigation.

## Tested host and builds

The host runs Armada `20261010.c3d178c`, Linux `7.2.6`, AArch64 with 4 KiB pages,
and Adreno 740 in Steam Gaming Mode. The running Broomm was the
`0.1.14-dev` input-latency preview. These are Linux desktop integrations, not
Android emulator handoffs.

| Emulator | Installed package identity | Test content |
| --- | --- | --- |
| Eden 0.2.1, Linux AArch64 Clang PGO | `03ba7d98e46e13f46f8aac66774ea71e36c676082d61b5f618e4ed78dd2b0263` | Smash, `01006A800016E000`, update 13.0.5; separate base-only 1.0.0 comparison |
| Azahar Armada, source `d162991403ff3a77ed623b6dd29b5074c4f45819` | `feb29b220975b7e454369a63bdd6a1eeadb384f43ac324a9e2ddbe516f5d6971` | Mario Kart 7, USA Rev 1 CCI |
| melonDS Armada 1.1, source `12891b6d064171e8a70c7ef146b9ba068d702b26` | `e6401d369badcb4fe92696dd327073a1891d4f5f835d6123925ec3121d99105b` | New Super Mario Bros., USA/Australia NDS |

The Eden package reports Turnip Mesa 26.1.1; Azahar reports bundled Turnip
26.2.1. melonDS uses OpenGL and reports Mesa 26.2.4. Different bundled graphics
stacks are an investigation variable, not proof of a driver defect.

## Method and data boundaries

Native comparison launches use disposable profile copies in the existing Thor
development project, under its private `.tool-cache/gameplay-compare-*`
directories. They acquire Broomm's live session/writer locks before copying,
refuse an existing emulator process, and redirect HOME, XDG, temporary files,
configuration aliases and writable data into the copy. Native keys remain on
the Thor. No RomM credential is read, no cloud synchronization runs, and no
live save or emulator preference is replaced.

The comparisons remove Broomm's injected input bridge; selected cases also
remove its native process supervisor. The reviewed emulator launchers and
their bundled loaders remain in use. Tests are bounded, terminate their own
child process group, and disable core dumps. A child still alive at the
deadline is recorded as **bounded startup survival**, not successful gameplay.
Some children require SIGKILL after the graceful termination interval; those
recorded `-9` results are diagnostic cleanup, not spontaneous startup crashes.

## Eden / Smash

The real Broomm session decrypts and loads Smash 13.0.5, initializes Vulkan,
then reports guest unmapped writes, scheduler dispatch-count assertions and an
emulated break. It exits with signal 5. No missing-key error explains that run.

| Private comparison | Result |
| --- | --- |
| NCE, no input bridge and no supervisor | SIGSEGV after 5.527 s |
| Dynarmic/JIT, no input bridge and no supervisor | SIGSEGV after 11.116 s |
| Fresh save area in the copied profile | SIGSEGV after 5.407 s |
| Minimal settings, copied per-game settings removed, 13.0.5 | SIGSEGV after 5.431 s |
| Minimal settings, installed add-ons removed from the copy; log confirms 1.0.0 | SIGSEGV after 4.477 s |
| Multicore NCE with fastmem and fastmem exclusives disabled | SIGABRT after 5.681 s, guest break `0xE401` |
| Multicore JIT with both fastmem options disabled | SIGTRAP after 9.634 s, Dynarmic `!is_executing` assertion |
| Single-core NCE or JIT with both fastmem options disabled | Both survive the 22 s startup deadline |
| Single-core NCE or JIT with default fastmem options | Both survive the 22 s startup deadline; runtime logs confirm the selected settings |

Thus Broomm's bridge and supervisor are not required to reproduce the crash.
Removing just the update, existing save, or custom configuration is insufficient
in these tests. Single-core execution only survives bounded startup checks;
the owner's next retry still hangs. It is not a verified workaround and is not
imposed by Broomm.

### Follow-up: owner-reported loading hang

On the owner's next launch, the emulator-preferences preview was running.
Eden loaded Smash 13.0.5, then logged dispatch-count assertions and unmapped
writes at emulated-startup time **4.549 s**. Its native log stopped advancing.
The process remained alive: a three-second read-only sample measured 908 CPU
ticks at 100 ticks/s, approximately three occupied CPU cores. Two guest CPU
threads and the emulation-control thread accounted for almost all of that
activity. This is consistent with an emulation failure/spin, not evidence of
continued useful loading.

The actual runtime log still reported `Core.use_multi_core: true` and
`Cpu.cpu_backend: Nce`; the proposed manual single-core workaround had not
been active in this run. The controller bridge continued publishing status
and acknowledging commands, while native pause remained unknown (`-1`).
Bridge liveness and an alive process therefore did not establish a working
game or a completed startup. Failure feedback for this case remains an
application gap; this follow-up did not change application behavior.

The inspection sent no controller/pause/termination commands and changed no
live preference or progress. Its redacted capture and thread-state sample are
under `.tool-cache/research/eden-loading-20261105T001634Z/` (UTC capture name;
the owner's local date was November 4). End the current session before opening
the profile's native Eden settings and testing single-core mode. A successful
gameplay result is still needed; the earlier 22 s startup survival alone does
not establish that workaround as playable.

### Confirmed single-core retry

The owner disabled multicore and retried. The actual next log is **Captain
Toad: Treasure Tracker 1.4.2**, title `01009BF0072D4000`; both the runtime log and
stored setting confirm single-core NCE. Unlike the previous Smash CPU spin,
native pause is acknowledged and a three-second sample consumes no CPU ticks.
Broomm's first-launch preparation then waits for the temporary native session
to exit before any cloud restore can proceed. That shutdown does not finish.
Closing also stalls; the owner switches to Desktop Mode to end the session.

Private Desktop Mode comparisons reproduce the paused-exit failure with the
reviewed SDL table/version metadata. A private prototype requesting Eden's
asynchronous native Stop action still hangs; removing native controller
reconfiguration also fails to resolve it. Neither change is deployed. One
corrected Qt-only diagnostic without SDL hooks/sampling exits normally, while
another control still hangs. Early invalid Qt-only probes are excluded from
conclusions. The controls have not yet identified the lock owner or a fix.

The new capture and comparison evidence is under
`.tool-cache/research/eden-singlecore-hang-20261105T003608Z/`. The owner approved
[pinned project-local GDB](eden-native-debugging.md) to inspect the blocked
threads. Debugger runs with an invalid ROM argument, missing library symbols
or an intercepted normal NCE signal are incomplete diagnostics, not new game
compatibility evidence.

### Gaming Mode lock capture — November 5

The actual `GameSession` diagnostic now reproduces the paused-close failure in
the owner's Steam/Gamescope context. Private GDB-started captures identify the
CPU thread waiting for Eden's process-list mutex, owned by the emulation-control
thread during shutdown. Source/disassembly inspection connects that wait to
`Service::OS::Process::Finalize` calling `KernelCore::RemoveProcess` while
`TerminateAllProcesses` waits with the same list mutex held.

Single-core JIT and two further close-order controls still fail. The unmodified
official GCC build also crashes Smash with multicore NCE in 4.877 seconds.
Captain Toad's separate unpaused GCC comparison survives 30 seconds and closes
normally; that is not gameplay or paused-workflow acceptance. A process-list
source patch applies cleanly to the immutable Eden 0.2.1 source but has not been
compiled or tested natively. The owner declined the additional Qt SDK/private
rebuild on November 5; it is not an implemented correction. See
[the exact capture, patch and SDK proposal](eden-native-debugging.md).

Nine completed profile copies were removed after preserving 46 redacted
diagnostic logs and confirming no private test process remained. Copied keys and
saves stayed on the Thor. Live bridges and all 291 production application inputs
remain unchanged. The current macOS archive passes a fresh integrity check and
deep/strict signature verification after extraction.

Upstream describes Linux ARM64 support as experimental in its
[architecture notes](https://github.com/eden-emulator/mirror/blob/master/docs/user/Architectures.md).
An [upstream report on Snapdragon 8 Gen 2 / Adreno 740](https://github.com/eden-emulator/Issue-Reports/issues/287)
discusses earlier ARM64/fastmem crashes; its author later reported improvement.
That report is supporting research, not proof that the Thor has the identical
historical defect. A separate
[ARM64 Dynarmic report on macOS](https://github.com/eden-emulator/Issue-Reports/issues/636)
contains the same `!is_executing` assertion and a single-core workaround; the
different host also prevents treating it as an exact root-cause match.

## Azahar / Mario Kart 7

The native lease is granted for the bottom DSI panel, and Vulkan initialization
reaches an assertion indexing `std::vector<vk::SurfaceFormatKHR>`. Signal 6 is
SIGABRT, matching the owner's code -6.

The abort reproduces without Broomm's input bridge or process supervisor in
0.917 s. Disabling only Gamescope's implicit Vulkan layer still aborts.
Setting `AZAHAR_DRM_LEASE=0` in the private comparison avoids that startup abort
for 22 s. This disables the dual-screen lease and is not deployed as a fix.
An attempted child-only Qt Wayland comparison aborts before game startup and
does not establish a usable Wayland renderer/backend.

The pinned fork's
[swapchain code](https://github.com/virtudude/azahar/blob/d162991403ff3a77ed623b6dd29b5074c4f45819/src/video_core/renderer_vulkan/vk_swapchain.cpp#L147)
accesses `formats[0]` without checking an empty list. Its
[display-surface path](https://github.com/virtudude/azahar/blob/d162991403ff3a77ed623b6dd29b5074c4f45819/src/video_core/renderer_vulkan/vk_platform.cpp#L133)
can return a null surface, while the presentation constructor proceeds to
swapchain creation. This is a source-level explanation consistent with the
observed assertion. There is no symbolized native stack trace identifying the
precise failing driver call.

The remaining work is in the lease-capable emulator/graphics path: diagnose
why it provides no usable surface format, handle that failure safely, and
verify both physical screens. A different provider build, driver experiment or
patched emulator needs a separately reviewed identity and input-hook map;
none is silently substituted by this Broomm change.

### Azahar follow-up — November 5

The currently published Armada release still points to the same pinned source
and package. Four private comparisons reproduce SIGABRT in 1.040–1.452 seconds:
bundled Turnip 26.2.1 versus system Turnip 26.2.4, each with default Vulkan
layers and with all loader layers disabled. Renderer logs and mapped modules
confirm the selected driver and absence of layers in the disabled cases. No
driver substitution or layer override is deployed to the live emulator.

A development-only, passthrough loader-audit observer follows Vulkan dispatch
through the renderer's real instance. It records successful Xlib surface
creation and two primary-surface formats. DRM display lookup, lease acquisition,
mode/plane enumeration and display-surface creation all return `VK_SUCCESS`.
The secondary display surface is valid, but its surface-format query returns
`VK_SUCCESS` with **count zero** immediately before the vector-index assertion.
This narrows the failure beyond the earlier possible null-surface explanation;
it does not establish why the driver offers no formats or provide a fix.

The initial preload/dlsym observer interfered before renderer creation and is
excluded from that conclusion. The first audit observer saw only a temporary
headless instance; the refined observer handles loader reload and records the
actual renderer. No observer is a product runtime component or emulator rebuild.

The local ignored capture is
`.tool-cache/research/azahar-lease-20261105T140435Z/`. After confirming the private
writers had exited, cleanup retained thirteen redacted diagnostic files and
removed all four temporary outer profile roots. Copied keys/save payloads were
not exported; live settings, saves and emulator files were unchanged. Further
diagnosis and physical dual-screen acceptance are deferred at the owner's request.

## melonDS / top window

The owner clarified that the entire top emulator window and menu bar were
narrow, rather than only the DS image. The bottom panel worked. Its native
log confirms lease acquisition, the rotated 1080×1240 secondary output and
bottom touch routing.

A direct private launch without Broomm's bridge/supervisor reports a 1920×1080
top-level X11 window and a 1920×1058 render area, checked at 4 and 11 s. A
diagnostic fullscreen launch reports 1920×1080 for both. These read-only
geometry queries concern only the test child's windows. They do not measure
the owner's physical image or reproduce the exact Steam/Broomm launch chain.
Both processes survive the 18 s comparison. The width problem remains
unconfirmed by this comparison; fullscreen is not claimed as a verified fix.

The pinned fork already switches its layout to top-only when a lease is active;
hardcoding top-only would damage its fallback when a lease is unavailable.
The owner will configure fullscreen inside the emulator. The proposed
`--fullscreen` application change was removed before delivery. Broomm passes
only the literal NDS path, preserving native window geometry and layout.

## Implemented display-preference correction

The owner explicitly permits required game/profile/input arguments and rejects
unnecessary presentation arguments. Accordingly:

- DuckStation, PCSX2 and ARMSX2 no longer receive `-nofullscreen`.
- Eden no longer rewrites `UI.fullscreen` and its default-selection marker.
- Dolphin no longer rewrites `Display.Fullscreen`.
- RPCS3 no longer rewrites its fullscreen setting or republishes `config.yml`
  for that purpose.
- Required private storage, game, account, input and supervision controls remain.
  Existing RetroArch display preferences already survive preparation; its
  first-profile defaults are separate from per-launch overrides.

This corrects preference ownership. It does not repair Eden's multicore
execution or Azahar's lease renderer and does not automatically alter any
existing saved preference. Configure the desired mode once in **Emulator
Settings → Open emulator** for the active Broomm profile.

## Verification and evidence

Forty affected Flutter tests pass on macOS, and forty pass on native Thor ARM64
Linux. Linux retains the existing skip of the macOS-only AES adapter test; it
does not claim that adapter works on Linux. Four new boundary regressions cover
fullscreen/windowed/unspecified preferences across the affected adapters and
melonDS's literal game argument plus preserved geometry. The existing input,
private-profile, progress and setup checks also pass. Flutter analysis is clean.
Windows and Android native checks were not run in this investigation.

The local capture directory is
`.tool-cache/research/thor-gameplay-20261104T231240Z/`. It retains original
reported-session logs, bounded-comparison results, source URLs/hashes, regression
logs and build/package verification. Earlier denied Flutter test sockets and
the corrected new test-fixture mistake remain in the diagnostic logs; the
final test logs record successful execution. The isolated Thor project is
`~/Projects/broomm-thor-fix`. Its application/native/asset build inputs were
compared to the current workspace: all 291 source inputs matched.

Both current release builds succeed. The macOS ZIP passes archive integrity and
deep/strict code-signature verification before and after fresh extraction; its
signature is ad-hoc, not notarized. The ARM64 Linux bundle passes native loader
dependency and bundled-asset checks. Its retrieved archive checksum matches the
Thor's archive and all 107 files were read successfully. The separately staged
Thor preview matches all 107 build files. The previously running application is
not replaced, and no Steam shortcut or live emulator setting is changed.

After capturing selected native diagnostic logs and their hashes, all six
private comparison roots were removed, including their copied keys/saves. The
cleanup first confirmed no process had a working directory in those roots.
The original profiles, progress, installed games and emulator binaries remain.

See the current packages and owner verification steps in [README](../README.md).
