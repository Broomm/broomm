# Eden single-core hang: debugger proposal

Status: the owner approved the project-local debugger on November 4, 2026.
GDB **15.1** is provisioned in the isolated Thor project's Devbox. Its pinned
recipe and resolved lock are retained in `tool/native-linux-debug/`. No
production bridge change from this investigation is deployed.

The owner stopped this investigation on November 5 and explicitly declined a
custom Eden build. No Qt SDK or modified Eden is to be provisioned or deployed.
The proposed patch below is retained only as an uncompiled research artifact.
The subsequent Azahar investigation is also deferred. The owner's next
milestone is [root-backed Android access](android-installation-and-saves.md#next-milestone-root-backed-storage-access);
the November 5 release checkpoint does not resume native emulator debugging.

The owner's retry confirms `Core.use_multi_core: false` with NCE. The inspected
game was Captain Toad 1.4.2. Its native pause is acknowledged, followed by a
stalled first-launch/shutdown sequence. This differs from Smash's earlier
multicore CPU spin. Closing also stalled; the owner ended the session by
switching to Desktop Mode.

Private Desktop Mode comparisons reproduce a paused-exit hang with Broomm's
reviewed SDL table/version binding. Requesting Eden's native Stop action before
window close also stalls. Skipping controller reconfiguration does not resolve
it. A Qt-only diagnostic without SDL hooks/sampling exits in one comparison;
another Qt-only variant still hangs. Those observations narrow the controls but
do not establish the lock owner or a reliable correction. Early Qt-only probes
had an invalid diagnostic status writer and are excluded from the conclusions.
The original 22-second single-core survival checks establish neither gameplay
nor a successful launch/shutdown round trip.

## Approved tool

Use GNU GDB only inside the isolated Thor development environment. Pin its
recipe to the project's existing immutable Nixpkgs revision:

```json
{
  "packages": {
    "github:NixOS/nixpkgs/5ed627539ac84809c78b2dd6d26a5cebeb5ae269#gdb": {
      "platforms": ["aarch64-linux", "x86_64-linux"]
    }
  }
}
```

The resolved version and package-fetch log are retained with the investigation;
the reproducible Devbox recipe and lock are retained with the project source. GDB uses
GPL-3.0-or-later; it is a development tool and is not linked into or distributed
with Broomm. This Linux diagnostic creates no macOS, Windows or Android runtime
requirement. Nix downloads the pinned debugger and its dependency closure into
the existing project-managed environment; no OS package manager, global tool
installation, sysctl, service or global permission change is proposed.

The comparison process uses a copied emulator profile under a private directory
on the Thor. The debugger may temporarily stop that process to capture every
thread's stack. It will not attach to a live owner session, evaluate expressions
that call native functions, edit process memory or upload/restore saves. Disable
frame-argument/local-variable printing and core dumps; retain only stack/symbol
and operation-phase evidence. Keep keys on the Thor. Bound each capture and
ensure the test process has actually exited before removing its copied data.

GDB's [thread-stop documentation](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Thread-Stops.html)
explains that the default mode stops all inferior threads together. This can
perturb timing, so compare the captured wait with an undebugged reproduction
before accepting a fix. A failed attach or missing symbols remains an incomplete
observation, not proof that there is no deadlock.

The alternative is additional phase logging using the already approved Clang
environment. It adds no package and remains available, but the existing probes
cannot identify the complete blocked call chain or its lock owner. GDB is the
recommended next diagnostic; it is not itself a game compatibility fix.

## Capture status

The debugger resolves 116 mapped ELF modules when the packaged loader does not
publish them normally to GDB. Its initial normal CPU interrupt (`SIGUSR2`) must
pass through to NCE; stopping on that signal prevents normal pause progress and
does not reproduce the owner's hang. A subsequent signal-aware run closes its
private native session, and later undebugged Desktop Mode runs also close.
These successes are not accepted as a fix: no production change caused them,
and the original failure is intermittent or depends on the original session.
There is not yet a usable post-hang stack establishing the lock owner.

The owner subsequently returned to Gaming Mode and left Broomm on Home.
The November 5 capture below supersedes the earlier absence of a usable
post-hang stack. No production shutdown correction is deployed.

Twelve completed diagnostic roots were removed after confirming no process had
a working directory in them. Selected logs and hashes were retained, while
their copied keys/saves stayed on the Thor and were removed with those roots.
No speculative prototype was installed into the owner's application or live
emulator profile. The live and copied baseline native runtime hashes were also
compared to rule out an unintended runtime replacement.

Automatic approval review initially rejected provisioning the debugger because
the dependency alternatives/tradeoff review and owner approval had not occurred.
The owner then explicitly approved the documented plan, and provisioning
completed under that authorization.

## Gaming Mode capture — November 5

SSH access was restored using the unchanged public Armada defaults after the
owner confirmed that configuration. No password was written to a script or log.
The live Broomm process was the emulator-preferences preview running through
Steam in Gamescope. Graphics/loader settings were inherited through a whitelist
in memory; no RomM client or credentials participated.

A private Flutter target exercises the production `GameSession` cold
initialization → confirmed native pause → close → normal launch → close flow.
The ordinary Dart SDK could not start under Steam's inherited loader context,
so those earlier SDK failures are excluded from emulator findings. The Flutter
probe used the production bridge, verified against the running application.

The full workflow reproduces a paused-close timeout. One run closes its cold
child at **5.996 s**, reaches the next acknowledged pause at **10.097 s**, then
fails the normal **20 s** shutdown deadline. Single-core Dynarmic also times
out in cold initialization; changing from NCE does not resolve this path.
Resuming before window close, and resuming followed by native Stop and an idle
check, both still time out. These were private comparisons, not product fixes.

Attaching GDB after confinement returns `ptrace: Operation not permitted`.
Launching private Eden processes under GDB instead captures the failure twice.
Normal NCE signals continue to pass through. GDB explicitly loads 118 mapped
ELF modules. A further capture records relevant stack/module offsets and
mutex-owner metadata, without arguments, local variables or game payloads:

- The window thread waits in `QThread::wait` during native close.
- The emulation-control thread waits during shutdown.
- `CPUThread` waits in `pthread_mutex_lock`; that mutex's owner is the
  emulation-control thread.

The installed ELF's disassembly and data layout match
[`KernelCore::RemoveProcess`](https://github.com/eden-emulator/mirror/blob/58c1e20ee58efa3900ba616207d460886214480b/src/core/hle/kernel/kernel.cpp#L879).
Its process-list mutex is at implementation offset `0x80` and its vector at
`0xb0`, matching the captured code. The CPU stack reaches that operation from
[`Service::OS::Process::Finalize`](https://github.com/eden-emulator/mirror/blob/58c1e20ee58efa3900ba616207d460886214480b/src/core/hle/service/os/process.cpp#L61).
Meanwhile,
[`TerminateAllProcesses`](https://github.com/eden-emulator/mirror/blob/58c1e20ee58efa3900ba616207d460886214480b/src/core/hle/kernel/kernel.cpp#L121)
holds the process-list mutex while waiting for termination. This identifies a
native cleanup lock cycle. A corrective build has **not** yet verified the
proposed change.

The unmodified official GCC package was also compared privately. Its AppImage
is 63,596,174 bytes, SHA-256
`494014f67401bbbe7d48da7128d769734cf97863bfb2349d48cd2a118173e769`;
its download matches the official zsync length/SHA-1. Smash with multicore NCE
still exits with SIGSEGV in **4.877 s**. Captain Toad with single-core NCE
survives 30 seconds and closes normally by its native SIGTERM handler. That
unpaused comparison establishes neither a working paused workflow nor gameplay.
The currently listed stable upstream release remains
[0.2.1](https://git.eden-emu.dev/eden-emu/eden/releases/tag/v0.2.1).

Evidence is retained under
`.tool-cache/research/eden-gaming-session-20261105T024355Z/`, including
`native-lock-observation.json`, `retained-evidence-manifest.json` and
`cleanup-result.json`. Nine completed private profile roots were removed after
confirming no test process remained. Their copied keys/saves were not exported.
The private probe's bridge was reset, and the production Linux build output was
restored from its matching saved build. The live runtime and application bridge
still hash to
`3e7fde960bf638f48c8f7454185a9375757ad6074e00313b93bd6c4d7f07dd87`.

## Archived proposal: private Eden rebuild declined

**Declined by the owner on November 5; no new SDK is provisioned.** This was a development
experiment on Linux ARM64, not a change to Broomm's shipped runtime or its other
platforms.

The uncompiled patch is archived locally as `eden-process-list-unlock.patch`
under the ignored investigation directory, outside committed product/tool
sources. It targets Eden commit `58c1e20ee58efa3900ba616207d460886214480b` (0.2.1). It detaches
each pending process list under the mutex, then terminates/releases those
existing references after unlocking. A further pass handles processes appended
during cleanup. It preserves each list-owned reference's release and allows
concurrent finalizers to take the mutex. `git apply --check` passes against the
exact source. Compilation, cancellation/race checks and native behavior remain
unverified. The patch addresses shutdown; it does not claim to repair Smash's
separate multicore startup failure.

The smallest additional SDK proposal is **QtBase and QtCharts 6.7.2** from the
project's existing immutable Nixpkgs revision
`5ed627539ac84809c78b2dd6d26a5cebeb5ae269`, through an isolated Devbox:
`qt6.qtbase^out,dev` and `qt6.qtcharts^out,dev`. The
[pinned source manifest](https://github.com/NixOS/nixpkgs/blob/5ed627539ac84809c78b2dd6d26a5cebeb5ae269/pkgs/development/libraries/qt-6/srcs.nix)
provides fixed source hashes. Native ARM64 resolution/build availability still
needs checking; no successful SDK or emulator build is claimed.

Eden requires Qt Widgets, Charts, Concurrent, DBus and Gui. QtBase supplies
those except Charts. This SDK brings its Nix-resolved GUI/tool dependencies,
including X11/XCB, graphics, font, ICU and DBus components. Exact closure and a
resolved lock would be recorded before use. QtBase offers LGPLv3/GPL options;
[QtCharts offers GPLv3](https://doc.qt.io/qt-6/qtcharts-index.html#licenses).
The private emulator build remains GPLv3 software. This proposal distributes
neither those SDKs nor a modified emulator, and adds no Flutter dependency or
user runtime requirement.

The existing compiler, CMake/Ninja and approved debugger would be reused.
Eden's other existing build components would use its immutable source and
dependency manifests, with project-managed caches and recorded hashes.
Additional tools/libraries outside that reviewed scope need their own decision.
No system package manager, machine SDK selection or global service changes.

| Approach | Concrete tradeoff |
| --- | --- |
| Existing bridge/stock packages | No SDK additions, but the tested close-order changes fail and GCC still crashes Smash. They do not exercise a source correction. |
| Isolated Devbox Qt SDK plus paired source builds — proposed | Reuses the project's native toolchain and source pin. Adds development downloads and a separately maintained Eden patch; the older Qt SDK must pass configure/compile before testing. |
| Upstream prebuilt Qt SDK | Eden's optional bundled-Qt branch requests 6.9.3, but its published SDK assets contain no Linux ARM64 package. It cannot supply this host's native SDK directly. |

First build unchanged source as a control, then patched source with the same
SDK, flags and dependencies. The control must reproduce the relevant failure
before attributing improvement to the patch. Test cold initialization, paused
close/reopen, and close after resumed execution with copied profiles; confirm
actual writer exit and retained ownership on failure. Recheck the new
executable/SDL/Qt bindings before a Broomm integration test.

Fetch/configure/build operations must remain cancellable and bounded, with
private staging and complete failure logs. Do not replace an installed emulator,
change owner preferences or synchronize real saves during this experiment.
Any eventual managed-emulator update remains user-initiated and requires a
verified package, notices/source provenance and separate gameplay acceptance.
