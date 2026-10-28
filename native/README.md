# Prototype native bridges

The [PlayStation integration](../docs/playstation-support.md) adds pinned DuckStation ARM64, ARMSX2 ARM64 and PCSX2 x86-64/Rosetta adapters in `playstation.inc`. They call native Qt pause methods that marshal to the emulator thread, then acknowledge actual UI notification flags (DuckStation) or atomic VM state (PS2). SDL3 logical enumeration/player indices exclude physical source devices from numbered emulator routes while retaining direct Broomm discovery. These paths use the emulator's bundled SDL3; no additional runtime or emulator implementation source is shipped. Test-only state save/load actions require the existing session-test opt-in. Source/output fingerprints, ABI evidence and native test limits are in the integration record.

The [library/progress follow-up](../docs/library-and-progress-followup.md) adds
the pinned melonDS 1.1 SDL2/Qt pause path and
`broomm-installer-guard.dylib`. The latter is Broomm-owned POSIX interop holding
`writer.lock` inside an RPCS3 installation process through native teardown and
parent death. Dart owns installation policy, validation and publication.
The same guard protects no-game configuration processes until native exit;
their normal emulator UI owns shutdown. Independent configuration launches now
take the coordinator and writer locks inside the child, with nonblocking refusal
of conflicts, and apply the existing Dart-supplied private write policy through
macOS's sandbox API. This lets Launch Services own the process without Broomm
polling its readiness/lifetime or retaining a lease. Installer-only invocations
retain their original writer-lock behavior. No new helper service or runtime is
shipped. See [Open emulator behavior](../docs/emulator-opening.md).
The session bridge additionally exposes
optional hash-pinned RPCS3 file/module loading counters in protocol 4, with
bounded atomic snapshots. See [current evidence](../docs/downloads-and-status.md).
The guard also translates `abort()` to non-success status 86 only for the
explicit `rpcs3-cli-v1` unattended-installer opt-in, emitting a protocol marker
instead of SIGABRT. Dart still requires a native completion checkpoint, the
known teardown diagnostic and independent output validation. Gameplay and
no-game configuration do not opt in. See [the installer correction and native
checks](../docs/rpcs3-installer-exit.md); there is no global crash-report setting.
It uses only the Apple SDK C runtime, adds no third-party source/runtime, and
ships precompiled in `Resources/native/`. Build with the script below;
`build/native/SHA256SUMS` records all three output libraries. Release source
and output fingerprints are in the follow-up JSON.

melonDS validates its existing SDL2 DynAPI table through exported stubs that
survive LTO (`SDL_JoystickGetButton`, `SDL_JoystickGetAxis`,
`SDL_GameControllerOpen`). Missing real functions fail before sampling. Its
selected logical joystick is resolved from a source instance ID in that
runtime. Pause reads the pinned EmuThread state and active flag after arm64
instruction checks. This is a build-specific macOS bridge, not an ABI promise
for arbitrary versions/hosts. No SDL runtime is loaded by Broomm and no
emulator source is patched.

`session.inc` extends Broomm's own earlier `probe.c`; no PGCS source is used.
Build with `devbox run -- bash tool/build_bridges.sh` using the approved Xcode
host. This emits universal arm64/x86_64 SDL2/SDL3 and installer-guard dylibs, plus
`build/native/SHA256SUMS`. The x86_64 emulator integration is the pinned Intel
RPCS3 and PCSX2 builds; universal bridge compilation does not validate other Intel
emulators. The SDL3 dispatch guard checks RIP-relative Intel stubs before
publishing hooks, and AppKit rectangle returns use the Intel `objc_msgSend_stret`
ABI. ARM keeps its existing instruction guards and calling convention. See
[Intel RPCS3 integration](../docs/rpcs3-intel.md) and
[upstream provenance and licenses](../experiments/injection/SOURCES.md) for the
reviewed SDL ABI lists and emulator symbol provenance. No SDL runtime is bundled
or loaded into an emulator by Broomm: the bridge uses its existing runtime.

The C bridge exposes four stable logical ports, samples physical SDL gamepads,
feeds assigned sources to those ports, gates input during menus, detects the
R3 + Back/Select chord and disconnects, and calls reviewed native pause paths.
Dart owns assignments, configuration, launch supervision, UI and command policy.
The bridge holds a whole-file fcntl writer lock until the emulator process exits,
so an orphan still prevents another game or preparation run from using its data.
The parent also holds a separate coordinator lock. Keep both lock files in place;
file existence is not the ownership check.
Hotplug identity is scoped to the current emulator process. Duplicate names do
not merge devices. Reconnection requires explicit rejoining.

RetroArch sees the logical routes' explicit SDL player indices as well as their
filtered enumeration; pre-existing physical devices must not shift its numbered
driver slots. Dolphin's host routes are distinct from its emulated console
sockets: native current-run SI configuration connects only paired, present
players. The console device readback is sampled only while the CPU is paused.

Private, atomic snapshots use protocol 4. Commands contain a monotonic revision,
active/pause flags, four source instance IDs (`UINT32_MAX` means vacant), four
face-pair swap flags, a quit flag, four Wii mode indices and four gyro-enable flags. The bridge applies each revision once; a stale command
cannot release a disconnect/hotkey gate. Status includes its process PID, sample
number, acknowledged revision, native pause readback and controller inputs.
`inputReady` confirms successful discovery in this process; failed discovery
preserves the preceding observation and reports an input error. Dart stays on
the loading screen until this flag, a blocked input gate and a native pause
are all confirmed. Stable logical ports are established before discovery.
Resuming from a menu waits for all paired controller buttons to be released.
Native pause runs on the emulator's main queue. RetroArch pause is acknowledged
through its private loopback network command port, supervised by Dart.
Ryubing's configured pause action requires the owning AppKit application to be
active before delivery. Its pinned macOS SDL2.30 child disables the GCController
backend after a sampled reentrant GCController/HID/Avalonia deadlock; HIDAPI and
IOKit remain enabled. MFi-only devices need separate verification. This setting
does not affect Broomm's library navigation or other emulator processes.
Pause pulses also wait for key-window focus and the previous key release. Normal
Avalonia shutdown resolves a current visible window when the close is delivered;
a retained native window can outlive its managed delegate, so it is not a safe
delayed close target. Direct NSApplication termination bypasses the managed
window teardown and can strand .NET workers. Closed
windows do not receive delayed key releases. A game-ended observation requests
normal application shutdown without releasing ownership before process exit.

Source snapshots include all six axes and SDL controller family. SDL2 children set `SDL_GAMECONTROLLER_USE_BUTTON_LABELS=0` so their getters use the same physical south/east/west/north positions as SDL3; this changes no global SDL configuration. A swap routes 0↔1 and 2↔3 together.

For Wii only, `wii.inc` calls the exact Dolphin 2609 InputConfig reload and native current-run Wiimote source APIs, while the CPU is paused. Dart owns the generated `WiimoteNew.ini` and its revision marker. The native bridge rejects a mismatched file revision, reads selected attachment and upright/sideways settings back, and holds input/pause until the revision matches. Source masks are published before their configuration revision. Wii sessions keep all GameCube SI sockets empty. Status exposes `wiiApplied`, configured `wiiSources`, selected extensions, paused active-extension readback and orientation; the real extension-port change proceeds on resumed CPU ticks. Test-only Remote button readback uses Dolphin's own locked getter. The Classic extension's actual game actions still require owner acceptance.

Azahar's native SDL callback can take its controller-map mutex and re-enter SDL while SDL holds the joystick lock. Its pinned child alone sets `BROOMM_DEFER_SDL_WATCHES`: fixed-size input-event copies are delivered on the main queue, outside the originating callback/SDL lock. Button/hotplug ordering is retained; pending continuous axis/sensor samples coalesce by device/control in a bounded queue. Overflow requests a closed input/pause gate. Non-controller events keep their original synchronous delivery. Unregistered callbacks are ignored. The opt-in native fixture pushes an event recursively under the SDL lock and verifies deferred, ordered delivery on the main thread, then exercises real hotplug and relaunch. No watcher queue runs in a separate helper service.

`test_sources.inc` creates two additional virtual *physical-source substitutes*
only when the test launcher explicitly sets `BROOMM_SESSION_TEST`. The interactive
Flutter application never enables that flag. It permits reproducible live routing,
both face-pair swaps, hotkey and disconnect checks against real supplied games, without
pretending this establishes physical-controller or gameplay acceptance.
Optional test controls put sources before the logical ports and suppress status
publication for a bounded outage check. The Dart supervisor discards stale pause
knowledge, retains writer ownership, and can consume fresh snapshots again.
Additional status fields include connected host-route mask, paused Dolphin
console-socket mask and actual AppKit application activity. Test-only fields
identify the synthetic sources and RetroArch's own numbered driver input.

For pinned Azahar 2126.1.2, readiness also requires the loading-screen widget to
hide relative to its main window, with instruction guards on the inspected ABI.
An early cancellation stays pending until loading completes: closing during its
constructor's terminal warning occurs before `app.exec` and can otherwise leave
the later game running behind a closed window. Normal close still stops SDL
sampling first. Fixed executable class methods and unhooked sensor event APIs
resolve once; mutable interception slots remain dynamic. See the
[responsiveness follow-up](../docs/research/pairing-responsiveness.md).

See the [reliability follow-up](../docs/research/prototype-reliability.md) for the
owner-reported failures, corrective experiments and current regression evidence.

These are development prototypes tied to the prepared emulator executables.
Apple Silicon/macOS is implemented; Linux/Steam, Windows injection and native
Android handoff are still pending. The Flutter overlay is a separate Broomm
window positioned over the emulator, not a hooked GPU presentation surface.
Full-screen Spaces, focus, physical pad models, Steam interaction, rumble and
motion feel/calibration need separate owner/native acceptance. Non-gamepad SDL joysticks are
not supported by this first pairing prototype.

Additional configuration facts were checked against RPCS3 revision `d08d568d`:
[SDL pad names/default directions](https://github.com/RPCS3/rpcs3/blob/d08d568d/rpcs3/Input/sdl_pad_handler.cpp)
and [private exit-confirmation key](https://github.com/RPCS3/rpcs3/blob/d08d568d/rpcs3/rpcs3qt/gui_settings.h).
Normal native shutdown is deferred until sampling has stopped and queued resume
notifications have had an event-loop turn; no synthetic test process is left
running by the successful suite. Failure diagnosis used native process samples
and crash reports, without desktop computer-control tools.

`motion.inc` extends the existing SDL bridge with sensor discovery/enable/read/rate APIs (SDL2 and SDL3 returns differ), SDL2 timestamped reads, and sensor events for cached consumers. Four logical ports expose a stable accel/gyro interface before pairing; physical snapshots report actual capability separately (`sensors`: -1 unknown, 0 absent, bit 0 accel, bit 1 gyro) from successful reads (`sensorReady`). Source samples use m/s² and rad/s in the SDL controller frame. Face swaps do not rotate sensor axes. Logical getters and events route the paired source, with zero angular velocity and stationary +Y gravity during a gate, vacancy, failed reading or stale bridge sample (>100 ms). The worker samples every 8 ms; logical sensor events are bounded to every second tick. A dedicated snapshot mutex never encloses SDL calls or event delivery. Only sensors enabled by this bridge are disabled on source close.

Protocol 4 retains the four per-player gyro-enable flags introduced in protocol 3 and rejects earlier snapshots/commands. `gyroEnabled` reports the applied flags; disabling gyro neutralizes only angular velocity in getters and events. Native L3+R2 detection uses trigger hysteresis and gates input before forwarding the chord, publishing a `gyro` request with the source instance ID. Dart owns the toggle and pause/reload/resume workflow; release of L3 and R2 is required before activation. Dart owns per-emulator configuration: Dolphin IMU inputs/IR and recenter, Azahar SDL motion device, Ryubing GamepadDriver motion. The C code contains no domain configuration workflow. `motionReads`/`consumedMotion` exclude bridge diagnostics and record real emulator getter consumption. `motionDelivered`/`deliveredMotion` record values after SDL watcher callbacks return; they do not inspect Azahar game HID state. `BROOMM_TEST_MOTION` is accepted only with opt-in session test sources; its file controls per-source capability, read failure and finite sensor vectors. It is never enabled by the Flutter application. See [sensor evidence/provenance and acceptance limits](../docs/research/controller-motion.md).

Opt-in native Brawl tests additionally read `Cursor::GetState(false)` for Point group 3 while the configuration is stable on Dolphin's main queue. Its two-double return ABI is checked against the pinned header; the false argument reads raw control references without advancing relative pointer state. Diagnostic reads are excluded from ordinary query-consumption counters. `wiiPointer` is test-only evidence of resolved native pointer bindings, not the game's final IR camera coordinates. `test-input.txt` optionally appends RX/RY/R2 values for each synthetic source to exercise actual stick/trigger paths.

The Wii/Switch/RetroArch expansion adds original `dolphin_installer.inc` to the existing universal installer guard. Its child-only opt-in calls the hash/instruction-pinned Dolphin 2609 WAD importer on the main queue after native initialization, in disposable sandboxed storage, holding the native writer lock. It links only the approved Apple AppKit/libSystem SDK. Dart owns all validation, package selection, publication, ownership and recovery. Intel WAD import is not implemented. The regular controller bridges now leave RetroArch shutdown to its verified QUIT channel so normal core teardown flushes save RAM, after the sampling worker stops. See [source/output fingerprints, native checks and limits](../docs/retroarch-wii-switch.json).

`ppsspp.inc` adds PPSSPP 1.20.4 ARM64 core pause/readback, frontend readiness and test-only native PSP button/state-key checks. Native `Core_Break(UIPause)` is acknowledged only after stepping and pending-work inactivity; frontend boot flags and screen identity are independently instruction-guarded under a nonblocking input lock. SDL2 discovery is scoped to one logical pad, using the emulator's own instance IDs and runtime. `ppsspp_storage.inc` supplies the child-only `NSUserDefaults` memory-stick path because this frontend consults that preference before HOME. The two native folder/bookmark setters stay in the volatile domain; original methods for unrelated keys are preserved. The same storage adapter applies to no-game configuration, without controller hooks.

`eden.inc` adds the hash-pinned experimental Eden 0.2.1 ARM64 interface. It observes actual loader completion, powered/paused state and console ports, and calls native `EmuThread::SetRunning` plus HID connect/disconnect on the owning Qt queue. Existing activation/release gating remains required. All unpaired native sockets are disconnected, with four logical Pro Controller slots. Eden's static SDL build uses three surviving DynAPI anchor stubs; its cached device-added watch events are translated only after virtual instance IDs are published. The tiny `eden_probe.inc` bypass applies only to Eden's exact self-exec Vulkan probe, while the real writer remains locked. Test-only status adds `switchButtons` and `nativeProgram`; PSP adds `pspButtons`.

PPSSPP SDL2 also uses the independently checked ARM64 relaxed dispatch-stub pattern (NOP plus literal load/branch). None of these additions enables arbitrary builds or Intel/Linux/Windows/Android runtime integration. `tool/build_bridges.sh` selects the approved Apple compiler explicitly inside Devbox and still emits universal C bridge libraries; verified emulator entry points remain host/build-specific. Dart owns all configuration, package, progress and publication decisions. No emulator/Qt/SDL implementation is copied, and no new framework or runtime is bundled. See [provenance, native evidence and delivery](../docs/psp-and-eden-support.md).
