# Controller routing and in-game overlays

Research date: 2026-10-16. This document contains the initial design investigation using the [PGCS source audit](../pgcs-reuse.md) and primary sources. Subsequent C/Dart experiments have now run the owner's ROMs in RetroArch, Dolphin, RPCS3, Azahar and Ryubing on macOS ARM64. Read the [executed validation report](injection-validation.md) for measured answers, exact builds and remaining gaps. Designs below remain proposals unless that report explicitly verifies them; rolling upstream source alone is not native acceptance.

Scope updated from the owner's decisions: **desktop integrations only**, with macOS/Linux first. Keep application/supervisor workflows in Dart, with optional precompiled C bridges. Do not import PGCS application code or add Go. Prefer injection/interposition and supported runtime paths over emulator modification/forks. Android uses ordinary ROM/save/state handoff with none of this controller/overlay machinery.

## Findings

**In-process controller assignment is feasible for selected emulator/input backends. PGCS already implements a narrow version. It is not a general solution to Steam Input identity, emulator configuration, or overlay rendering.**

Treat the work as three independently negotiated capabilities:

1. **Input:** identify what the emulator sees and bind that route to an emulated player port.
2. **Presentation and capture:** render a menu over the game and prevent its navigation from also controlling gameplay.
3. **Control:** ask a particular emulator to apply settings safely and confirm the resulting effective values.

Sharing a loaded native module and local IPC is plausible. Sharing the same injection entry point for all three is not guaranteed.

## Why launcher-side controller ordering breaks

A model GUID identifies a class of device, rather than a unique physical controller. Serials may be absent. Paths are backend-dependent and may change across reconnects or transport changes. SDL instance IDs are local to a runtime's device lifetime. A launcher's enumeration ordinal is not an emulator's ordinal. SDL exposes an implementation-dependent device path, but that API is not a universal persistent identity contract. [SDL device-path API](https://wiki.libsdl.org/SDL3/SDL_GetGamepadPath).

Steam can change what the game observes: physical devices, virtual gamepads, remapped controls, or keyboard/mouse events. Its configuration also follows application/foreground context. Valve documents both emulated-input and native-action approaches; SDL integration helps avoid physical plus emulated double input. These facts support testing the final child route, not assuming launcher visibility survives handoff. [Steam Input concepts](https://partner.steamgames.com/doc/features/steam_controller/concepts), [developer guidance](https://partner.steamgames.com/doc/features/steam_controller/getting_started_for_devs).

Injecting into the child can observe and control the child's runtime. It cannot reconstruct physical provenance that Steam has removed or distinguish identical virtual routes using a name that carries no unique information. A native Steam Input integration is a possible separate experiment, subject to SDK/distribution requirements and non-Steam launch behavior; it is not a generic API for overriding arbitrary emulators.

## Preferred order of integration

| Approach | Benefit | Limitation / decision |
| --- | --- | --- |
| Emulator-supported persistent device bindings | Lowest ongoing interception burden; can preserve upstream UI | Must verify exact build, backend, identity and duplicate-device behavior |
| SDL dynamic API bridge | Uses an SDL-supported loading path; observes the real runtime; PGCS has code | Only works for compatible SDL use and selectors the bridge actually intercepts |
| Native API interception / app-local proxy | Can address a non-SDL input backend or render API | Per-OS/ABI/API maintenance; duplicate paths and hook chaining need proof |
| Existing cooperative API/plugin | Can expose real ports, settings and safe thread scheduling | Use where already supported; changing upstream emulators is not the preferred route |
| Virtual-controller broker | Broomm could own virtual routes and player assignment | Drivers/permissions/device hiding, latency and motion/rumble fidelity; adds significant deployment cost |
| Emulator changes/fork | Full access to ports, render loop and settings | Owner prefers avoiding these; only a last-resort proposal if external integration cannot meet a concrete requirement |

The owner's preferred route is external integration against the small selected emulator set. This table does not approve a dependency or emulator fork.

## SDL dynamic API: the strongest starting point

SDL's dynamic API routes calls through a function table and allows an alternative library selected through `SDL3_DYNAMIC_API`. This mechanism can remain usable with statically linked SDL if enabled and appropriately accessible. SDL also allows builds to disable it. ABI/table negotiation and access to the original implementation still matter. The prose documentation contains historical ABI-version examples; use the selected build's headers/table and runtime negotiation instead of copying that example version number. [SDL dynamic API design](https://github.com/libsdl-org/SDL/blob/main/docs/README-dynapi.md).

PGCS's C bridge demonstrates the practical pattern: forward the original SDL implementation, validate selected identities inside the child, supply player indices, and hold game startup until the supervisor acknowledges. Its current implementation supports two joined players and rejects ambiguous identity or reconnection. See the [source audit](../pgcs-reuse.md) for exact code and evidence.

**Important:** overriding `SDL_GetGamepadPlayerIndex` helps only when the selected emulator uses that result for its binding identity. Other software may assign its own indices, use names, process `SDL_EVENT_*` device IDs, or bypass SDL for native APIs. An emulator built with Qt may use SDL for input and a separate render stack; its GUI toolkit name is not its controller contract.

Source checks relevant to an adapter-specific plan:

| Integration | Inspected evidence | Consequence |
| --- | --- | --- |
| PCSX2/ARMSX2 | Local PGCS PS2 adapter and bridge explicitly map player-index-based SDL bindings | First bridge reproduction candidate; verify current upstream build and original SDL entry access |
| DuckStation | Upstream `GetPersistentIdentifier` uses GUID/serial and a Windows GameInput identity path; PGCS also has a serial-free bridge fallback | Prefer verified persistent binding; use the bridge only for the explicit fallback scope |
| Dolphin | Upstream SDL backend enumerates joystick IDs and adds devices to Dolphin's own ControllerInterface | PGCS's player-index override cannot be assumed to define Dolphin port IDs; inspect its qualifier/registry and prove routing separately |
| RPCS3 | Upstream SDL handler records name/path/serial and builds its own device names/lookup | Changing SDL player index alone is not established as a solution; test the actual handler and configured ports |
| RetroArch / SDL2-based integrations | PGCS has distinct core/backend mapping code and SDL2 model probes | No inherited SDL3 guarantee; actual joypad driver, event paths and core port behavior matter |

Sources: [DuckStation SDL source](https://github.com/stenzek/duckstation/blob/master/src/util/sdl_input_source.cpp), [Dolphin SDL backend](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/InputCommon/ControllerInterface/SDL/SDL.cpp), [Dolphin SDL gamepad](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/InputCommon/ControllerInterface/SDL/SDLGamepad.cpp), [RPCS3 SDL handler](https://github.com/RPCS3/rpcs3/blob/master/rpcs3/Input/sdl_pad_handler.cpp). These are source-level observations, not native gameplay acceptance.

## A better controller setup workflow

Keep the visible setup experience in Flutter. Native integrations supply evidence, rather than owning a competing UI.

1. Show player slots supported by the selected integration, plus controller test, layout/preset, Join, Leave and Reorder actions. Use physical button positions internally; choose glyphs separately. Do not reproduce PGCS's fixed 20-device/four-card prototype as a requirement.
2. Record a provisional join roster with observed identity, backend, physical/virtual evidence and current device generation. Do not label it confirmed merely because Broomm received a button press.
3. Prepare and start the emulator in a supported idle/gated state before game execution. If it cannot initialize input before loading a game, expose that as an adapter limitation; do not invent a universal pre-game pause.
4. Receive the child's inventory. Match a unique identity when possible. For indistinguishable devices, ask each player to perform a short child-observed button challenge so assignment uses the actual current runtime handle. This is a proposed protocol requiring an input-reading hook; the existing PGCS bridge does not implement it.
5. Bind each selected route through the emulator's real selector, then read back or test the effective port. A challenge identifies a route for this session, not a persistent physical serial.
6. Reject or re-run the setup on topology changes before release. Preserve the roster for clear rejoin guidance. Do not silently swap player 1 when another controller reconnects.

Make controller eligibility errors actionable within the setup screen. Display whether Broomm is routing direct physical input or Steam-translated input. Avoid permanently blocking all virtual devices or all identical models: distinguishability in the final backend is what matters. Conversely, do not promise that two identical serial-free devices can always be matched between processes.

The macOS Flutter prototype now exercises live assignment changes and reconnect/rejoin behavior with synthetic SDL sources; physical-controller and Steam/Linux acceptance are pending. Relaunch is not the intended response to routine pairing changes or controller disconnects. Any inherited bridge fatal-error path must be reviewed before adding runtime hotplug or overlay use.

## Steam Input on Linux

Proposed diagnostic matrix: Broomm launched directly with Steam closed; directly with Steam running; via a Steam shortcut with Steam Input enabled/disabled where supported; then the real game child in the same cases. Compare physical and virtual inventories, focus transitions, permissions and effective mappings at each handoff.

PGCS's Linux code classifies kernel input origin through sysfs and has a physical-first route policy, with a distinguishable virtual-only fallback. It also reports successful targeted Qt X11/xcb tests on Ally/Bazzite. Those are relevant observations, not authorization to import its routing policy or to force X11 globally. Test child-only backend selection, confirm the loaded backend, and compare the same devices/game under X11/XWayland and Wayland.

Do not infer virtual status from missing serial alone. Do not broadly clear Steam injection environment variables: input/overlay integration may depend on them. Compose child-specific hints and preserve unrelated state. Direct physical routing can bypass Steam remapping/gyro features; using Steam's translated route can lose physical features. This is a user-visible choice and a validation issue, not just deduplication.

## Platform feasibility

| Host | Candidate route | Constraints to prove |
| --- | --- | --- |
| Windows | Compatible SDL dynamic API DLL; otherwise selected native input API hooks and render hooks | Match process architecture and DLL dependencies; verify code-signing/package policies and hook order. XInput slots are 0–3, not universal physical identities; GameInput/RawInput/HID require their own mapping evidence |
| Linux | Compatible SDL dynamic API `.so`; selected `LD_PRELOAD` interposition or Vulkan layer | ELF linkage/export visibility, runtime/container namespaces, Steam Runtime, device access, hook chaining, Wayland/X11 and graphics backend all matter |
| macOS | Compatible SDL dynamic API `.dylib`; cooperative integration or approved render interposition | Match architecture, signatures and hardened-runtime policy; injected libraries can be rejected by library validation |
| Android | Normal installed emulator app launch with ROM/save/state handoff | Input assignment, injection, desktop sandboxing and overlays are explicitly out of scope |

Windows slot semantics: [XInputGetState](https://learn.microsoft.com/en-us/windows/win32/api/xinput/nf-xinput-xinputgetstate). Apple restrictions: [library validation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation), [hardened runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime). Android boundary: [application sandbox](https://source.android.com/docs/security/app-sandbox).

On macOS, a managed-copy signing experiment may be possible for a selected emulator, but requires an explicit packaging decision and verification of entitlements, functionality and update identity. Do not modify the user's existing emulator or treat disabling system security as a launch requirement. `SDL3_DYNAMIC_API` does not bypass loader policy. Windows remote-process attachment is not the first experiment when an explicit supported load path exists.

Android needs only its external-app ROM/save/state access and completion contract. Use detected compatible apps or guide installation; do not implement a controller-routing/bridge capability for Android. A Flutter frontend does not make another app's private saves accessible, so state any precise handoff limitation. See the [Android requirements](../../PROJECT.md#android-handoff).

## Overlay rendering is a separate workstream

A graphics hook can draw a menu even if input uses an unrelated API. An input hook can identify controllers even if the emulator never uses SDL for graphics. Packaging both into one module is an implementation option, not proof that one hook provides both capabilities.

| Rendering route | Suitable investigation | Important boundary |
| --- | --- | --- |
| Cooperative emulator render callback | First choice where available | Requires an actual upstream extension/control point |
| Vulkan layer | Desktop Vulkan renderers; initial overlay prototype candidate | Register a Broomm-owned layer for the launched child; handle queue synchronization, multiple swapchains and recreation |
| OpenGL interception | Linux/Windows GL renderers | Correct current context, GL state restoration, symbol resolution and window-system paths |
| D3D11/D3D12 interception | Windows renderers | API-specific present/resource/device-loss handling and overlay coexistence |
| Metal integration | macOS native rendering | Separate native render work and signing constraints; Vulkan/MoltenVK evidence does not establish native Metal support |
| Separate Flutter window / compositor surface | Fallback settings panel where verified | Stacking, exclusive fullscreen, focus and gamepad capture vary; not a portable in-game overlay |

Khronos documents environment-selected layer discovery, which supports investigating app-owned layer manifests without a system install. Use child-scoped paths and preserve existing layer discovery; discovery alone does not enable the layer or validate synchronization. [Vulkan loader layer interface](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderLayerInterface.md).

MangoHud demonstrates working Vulkan/OpenGL overlay mechanisms and preload integration. Its documentation also specifies a different `mangoapp` route for gamescope, so ordinary desktop injection cannot be assumed to cover Steam Deck/Game Mode. It is evidence and a code/design reference, not a selected Broomm menu library. [MangoHud documentation](https://github.com/flightlessmango/MangoHud).

Dear ImGui is a rendering reference: it separates input/platform backends from Vulkan, GL, DirectX and Metal backends, which do not inject themselves into an arbitrary emulator. It is C++, so adopting it as-is would not match the current Dart/C implementation boundary. Rendering Flutter output to a shared texture could retain menu code in Dart but adds texture transport, synchronization and lifecycle work in the C bridge. No renderer dependency is selected. [Dear ImGui backends](https://github.com/ocornut/imgui/blob/master/docs/BACKENDS.md).

An external window also needs compositor cooperation. Wayland's compositor owns composition and input routing, so a transparent topmost-window strategy needs host-specific proof. [Wayland architecture](https://wayland.freedesktop.org/docs/book/Architecture.html). Android overlay permission is not part of the product plan; Android overlays are excluded.

## Steam Big Picture and gamescope: preliminary window review

Reviewed 2026-10-16 against upstream gamescope tag **3.16.31**, commit `6867f509874f9bc52e12d6f4c4596cdf0d5be6b4`, and master `2b5cf191d1047d6895516a834de8a72ac1c342f3` (2026-10-14). This is documentation/source inspection on macOS. No Linux/Bazzite machine, compositor session, Steam controller handoff or native Linux overlay was tested. Neither source revision identifies the gamescope build on a future test device. These findings do not approve a rendering library or replace the existing prototype.

**Assessment:** the owner's Steam → Broomm → emulator + in-game settings flow is feasible to investigate, but the current ordinary Flutter window is not a validated Game Mode overlay. Multiple windows are supported; reliable simultaneous composition, focus and controller ownership require explicit integration. An ordinary “always above” window is a high-risk default for this target. That is an engineering assessment, not a reproduced Broomm failure.

### The three environments differ

| Environment | Relevant behavior | Consequence for Broomm |
| --- | --- | --- |
| Big Picture on a normal desktop | The Steam interface runs with the desktop's window manager. Steam Input follows application/foreground context. | Test OS focus/fullscreen and input changes; a macOS panel does not establish Linux Game Mode behavior. |
| Bazzite-Deck / SteamOS Gaming Mode | Bazzite documents Big Picture UI in a minimal gamescope session. | Validate under the session compositor itself, with Broomm as the Steam shortcut. |
| Desktop Steam with nested gamescope | The game lives inside a nested compositor. Bazzite's ScopeBuddy documents separate overlay/input fixes and avoids another nested gamescope in Gaming Mode. | A Broomm window outside the child's compositor is not automatically part of its composition. Do not add nested gamescope as a presumed universal fix. |

Sources: [Bazzite Gaming Mode overview](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Steam_Gaming_Mode/), [ScopeBuddy behavior](https://docs.bazzite.gg/Advanced/scopebuddy/), [gamescope nested model](https://github.com/ValveSoftware/gamescope/blob/6867f509874f9bc52e12d6f4c4596cdf0d5be6b4/README.md), [Steam Input foreground mapping](https://partner.steamgames.com/doc/features/steam_controller/getting_started_for_devs?l=english#3).

### What upstream actually implements

Gamescope selects a base game window and handles transient/popup and overlay surfaces separately. XWayland focusable entries include window/app/PID identities for Steam. Current same-app cross-process popups can qualify, so different PIDs alone do not rule out Broomm UI. Application grouping still matters. App identity can derive from Steam scope/ancestry and X11 `STEAM_GAME`; environment variables alone are not proof of grouping. [Window selection and overlay code](https://github.com/ValveSoftware/gamescope/blob/6867f509874f9bc52e12d6f4c4596cdf0d5be6b4/src/steamcompmgr.cpp#L4197), [process identity lookup](https://github.com/ValveSoftware/gamescope/blob/2b5cf191d1047d6895516a834de8a72ac1c342f3/src/Utils/Process.cpp#L782).

The tagged Wayland implementation marks layer-shell surfaces as external overlays. X11 also has a `GAMESCOPE_EXTERNAL_OVERLAY` path. External overlays are excluded from normal game-focus candidates; Steam's interactive overlay has separate focus handling. There is a selected external-overlay slot, so coexistence with MangoApp needs proof. Displaying a layer is therefore not evidence of keyboard, pointer, touch or Steam Input ownership. The general `gamescope_control` protocol labels itself private. These details support a compositor-aware experiment, not a portable topmost-window promise. [Layer-shell handling](https://github.com/ValveSoftware/gamescope/blob/6867f509874f9bc52e12d6f4c4596cdf0d5be6b4/src/wlserver.cpp#L2072), [private control protocol](https://github.com/ValveSoftware/gamescope/blob/2b5cf191d1047d6895516a834de8a72ac1c342f3/protocol/gamescope-control.xml).

A working precedent for compositor composition exists: MangoHud directs gamescope users to **MangoApp** and says its ordinary integration is unsupported there. This proves a specialized overlay route exists, not that its performance HUD is an interactive Broomm menu. [MangoHud gamescope instructions](https://github.com/flightlessmango/MangoHud#gamescope).

### Reports that constrain confidence

SteamTinkerLaunch's own documentation records Game Mode window-switching difficulty, occasional jitter and subwindows opening behind another window. Upstream gamescope issue **#1885** reports a launcher plus game rendering failure on 3.16.12. These are relevant failure examples with their own builds and conditions, not proof all multi-window applications fail or that a newer Bazzite build still has those defects. [Maintainer documentation](https://github.com/sonic2kk/steamtinkerlaunch/wiki/Steam-Deck#known-issues), [gamescope report #1885](https://github.com/ValveSoftware/gamescope/issues/1885).

Issue **#1341** records launcher/container cases where the child ran but was not made visible, with app-ID/layer-order investigation. Packaging and process ancestry deserve separate checks; do not copy its historical root-property rewrites into Broomm as a supported interface. A 2026 RPCS3/RetroArch report concerns SteamOS **desktop Wayland** input, and explicitly says Game Mode works; it must not be cited as a Game Mode failure. [Visibility report #1341](https://github.com/ValveSoftware/gamescope/issues/1341), [desktop input report #13223](https://github.com/ValveSoftware/steam-for-linux/issues/13223).

### Options for the requested flow

The following are proposals, not selected implementations:

| Option | Fit and tradeoff |
| --- | --- |
| Current ordinary Flutter panel | Retains all Dart UI; depends on automatic focus, app grouping and stacking. It might replace the game visually or remain behind it. Keep as a macOS prototype/fallback until tested. |
| Explicit full-screen settings/game switch | Could provide both functions through one Steam entry, but temporarily replaces game presentation. It does not deliver the requested menu over the game. |
| Gamescope-aware compositor overlay | Could retain Flutter UI and keep the emulator as the base game/input context. Prototype a distinct surface role, child-to-Dart controller events, input suppression and Steam menu priority. Input support, surface conflicts, packaging and version compatibility remain open. |
| Draw in the emulator's game presentation surface | Best matches the original aim and avoids a settings-window focus handoff. Requires real render integration per backend, Flutter-output transport or another reviewed renderer, and repainting while emulation is paused. The existing SDL input hooks do not provide this renderer. |

For a gamescope-aware layer, keeping the emulator focused while its bridge sends navigation to Dart is a plausible controller-only design. It could avoid switching Steam's input context when opening Broomm's menu. This is an inference to test; keyboard/mouse/touch capture and coexistence with Steam's own menus remain independent requirements. Do not impersonate Steam's overlay or continuously rewrite its global focus order.

The current code supports only the macOS panel presentation path (`MainFlutterWindow.swift`). Linux's GTK runner is scaffold code and has no corresponding host-channel integration. The launch path also assigns `DYLD_INSERT_LIBRARIES` to Broomm's bridge; preserving/chaining Steam's injected components needs an explicit audit before claiming the macOS Steam path works. A future Linux preload/layer must preserve Steam's existing child environment and namespaces too. No application behavior was changed by this review. The [source audit](gamescope-source-audit.json) records pinned inputs and SHA-256 fingerprints.

### Smallest native acceptance experiment

Once a Linux host is available, begin with one Steam shortcut for Broomm and one emulator/ROM, without RomM or extra settings work. Pin the OS image, Steam channel/build, gamescope package/fork, GPU/driver, XWayland/Wayland backend, emulator and bridge hashes. Test the ordinary-panel candidate first, then a gamescope-aware layer or in-game rendering if it fails the required flow.

1. Launch Broomm from Steam, pair two controllers and start the child. Inspect actual process scope, compositor connection, window grouping and focus. Hide launcher windows during gameplay while retaining their processes.
2. Repeat R3+Select → pairing → player reorder/mapping → resume using only controllers, with no Steam window picker or desktop focus workaround. The paused game must remain visible beneath the menu, and the menu must continue repainting when the emulator stops presenting new frames.
3. Disconnect a paired controller, reconnect and rejoin. Confirm that pausing/menu input never also controls the game and that released controls resume cleanly.
4. Open and close Steam Home/QAM while Broomm's menu is open. Steam must receive its navigation, closing it must restore the correct Broomm/game state, and no second Steam Input layout or duplicate route may appear.
5. Repeat with MangoApp enabled/disabled, window recreation/fullscreen/resolution changes, and relevant HDR/VRR settings. Inspect conflicts rather than assuming multiple external layers work.
6. Test direct desktop Big Picture and native Gaming Mode separately. Compare child-only X11/XWayland early if input/focus fails, verify the backend loaded, then test intended native Wayland/packaged paths separately.

A pass establishes only that exact host/backend route. Until then, the separate-window prototype remains unverified for the owner's central Steam/Game Mode use case. Prefer in-game rendering for the general architecture unless the smaller compositor experiment demonstrates an equally seamless flow with acceptable host-specific maintenance.

## Input ownership while a menu is open

Opening the menu must transfer navigation ownership: consume the opening chord, deliver neutral buttons/axes to the game through every active intercepted path, avoid stuck buttons, and wait for released controls before returning input. Intercepting only SDL events is insufficient if the emulator polls state. Intercepting gamepad input is insufficient when Steam maps that controller to keyboard/mouse input.

Define menu ownership separately from game pause. Pause/resume requires a verified emulator action. If pause is unavailable, say the game continues; do not simulate pause by blocking its rendering thread or suspending an arbitrary process. Restore the previous input state on close, focus loss, disconnection and IPC failure, with a recoverable escape route.

Test the chord against Steam's overlay and emulator hotkeys. Do not assume the Guide button reaches Broomm. Provide a configurable alternative and avoid treating a PGCS-reserved chord as a Broomm product decision.

## A consistent menu needs emulator-specific control

The proposed control interface exposes actions with `supported`, `effectiveValue`, and application mode (`live`, `restartRequired`, `openNativeUI`, `unsupported`). Commands include a session ID and request ID and return confirmed outcomes, rather than optimistic UI-only success.

- Broomm-owned preferences, such as its UI settings and sync status, can be handled by Broomm independently.
- Controller port changes need the selected emulator's binding/reload mechanism and safe thread/lifecycle point.
- Render resolution must use a verified runtime API, supported hotkey or narrowly reviewed emulator integration. Writing an INI while the emulator runs may do nothing or be overwritten at exit.
- Save/load state, pause and orderly quit need adapter support and confirmation. A drawn menu does not add missing emulator features.

Dolphin and RPCS3 are useful targets for this ambition, but their exact current UI and control surfaces must be audited for the chosen releases. An OSD, achievement notification or hotkey is not evidence of a complete controller-operated settings menu. Prefer supported runtime actions and narrowly versioned injection/interposition in the selected builds. Emulator modifications or forks are a last resort, not the next assumed milestone.

Per-setting restart behavior is a required part of each adapter's knowledge. Show a restart notice only when the changed setting is known to require it; verified live settings apply without that warning. Record uncertain behavior as an integration gap to investigate rather than marking every setting restart-required. A return to ordinary settings/native UI can cover an unavailable action but is not the goal of the unified desktop menu.

There is a concrete smaller path for Dolphin: its inspected hotkey scheduler already handles increase/decrease internal resolution by changing `GFX_EFB_SCALE`, as well as pause and per-player Wii profile cycling. A first menu could invoke a narrowly configured native hotkey action, with verified input delivery and acknowledgement, before adding a general settings API. Its OSD feedback is useful evidence but not structured readback. RPCS3's inspected game-window shortcut handler likewise exposes pause/resume and graceful shutdown, providing candidates for a limited action set; this inspection does not establish a live resolution setter. These are source-level starting points, not tested external command interfaces. [Dolphin hotkey scheduler](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DolphinQt/HotkeyScheduler.cpp), [RPCS3 game-window shortcuts](https://github.com/RPCS3/rpcs3/blob/master/rpcs3/rpcs3qt/gs_frame.cpp).

## Proposed bridge/control protocol

Use a versioned local channel scoped to the launched session, with a private endpoint, fresh session nonce and OS access controls. Bind it to the expected child identity; do not trust a stale `ready` file from a previous launch. Suggested messages: `hello(build, abi, capabilities)`, `inventory(generation)`, `assign(roster, generation)`, `assignmentVerified`, `releaseGame`, `menuState`, and typed setting request/result messages.

The bridge must not receive account credentials or a generic shell-execution command. Keep network/sync operations in Broomm. Version mismatch or a missing assignment acknowledgement blocks verified startup; an optional unavailable overlay can fall back to Broomm Settings with an honest capability message.

Do not wait for IPC while holding SDL/device locks or a graphics queue required to complete the request. PGCS's blocking initialization/release handshake must be redesigned if a child-observed interactive challenge or render-thread callback participates. Bound all waits and test parent death, stale endpoints, cancelled startup and child exit.

## Experiments and acceptance gates

1. **Prove one C input bridge:** choose a pinned PCSX2/ARMSX2 build and available macOS/Linux host. Use the PGCS prototype as evidence, with a Dart supervisor and bundled precompiled C library. Verify direct launch, reversed player join order, an unjoined pad enumerating first, duplicate models, missing serial, wrong ABI and cancellation. Use owner-observed per-player game actions, not just a `ready` response.
2. **Steam/Linux routing:** repeat with Steam Input and real handoff, built-in handheld plus external pads, two/four controllers where the adapter supports them, permissions failures, X11/XWayland versus Wayland, and reconnects. The bridge's two-player limit must be resolved before claiming four-player support.
3. **One different selector:** investigate Dolphin or RPCS3's actual device registry. Prove how child-observed handles become configured emulator ports; record an explicit no-go if a maintained hook/cooperative API is required.
4. **One rendering backend:** after owner review of renderer/dependencies, draw a controller-navigable overlay in a pinned emulator/backend. Test fullscreen transitions, resize, swapchain recreation, device loss, Steam overlay and gamescope where relevant.
5. **Input capture and one real setting:** demonstrate that menu navigation cannot move the game, release controls cleanly, and apply/read back one supported setting. Record whether restart is required. Verify that overlay failure preserves saves and recoverable gameplay.
6. **Expand desktop coverage:** establish both macOS and Linux evidence, then Windows with its own builds/tests. Android remains a normal external-app handoff and is excluded from bridge/overlay expansion. Do not convert one successful Linux hook into an all-platform injection promise.

Record executable/core/bridge hashes, host OS/architecture, renderer, SDL/input backend, Steam state, window backend, devices/transport, exact steps, expected versus observed behavior, and who verified gameplay. No experiment above is marked complete for Broomm.
