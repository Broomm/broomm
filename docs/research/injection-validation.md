# Native controller injection: executed validation

Date: **2026-10-16**. Host: **macOS 27.0.1, Apple M1 Pro, ARM64**. This report supersedes the earlier source-only feasibility assessment for the five builds below. The [probe source and walkthrough](../../experiments/injection/README.md), [source provenance](../../experiments/injection/SOURCES.md) and [machine-readable evidence](injection-validation-evidence.json) accompany it.

**The approach works on the tested macOS builds:** an injected C library can intercept the emulator's actual SDL calls, return the original results, and change button mappings/controller routing during a running session. All five also have a measured semantic pause/resume route. An injected native panel was attached and received draw callbacks in each emulator. **Visual confirmation above the game in every renderer/fullscreen mode and Linux with Steam Input remain unverified.**

These are real game/process tests with the supplied ROMs and synthetic controllers inside each emulator. They are not physical-controller gameplay acceptance or a completed Flutter feature. No Go or PGCS application/bridge code was reused.

## Answers to the four questions

| Emulator / tested build | 1. Hook the same API? | 2. Same query results? | 3. Live selection / mappings? | 4. Pause and simple UI? |
| --- | --- | --- | --- | --- |
| RetroArch 1.22.2, build 20261001; Snes9x 1.63 `fae2fea` | **Yes:** actual SDL3 gamepad calls | **Yes:** original runtime results in the intercepted calls | **Yes:** button swap and A/B source routing reached the native caller | **Pause yes:** command API reports PLAYING → PAUSED → PLAYING. Native panel draw calls observed |
| Dolphin 2609 | **Yes:** embedded SDL3 dispatch table | **Yes:** actual `ciface::SDL::Gamepad::Button::GetState` calls | **Yes:** live button and source changes in Melee | **Pause yes:** `Core::State` Running → Paused → Running. Native panel draw calls observed; game title identifies Metal |
| RPCS3 0.0.42-20031, `d08d568d` | **Yes:** actual SDL3 pad-handler calls | **Yes:** original button/axis results in that runtime | **Yes:** pad-handler button/axis results changed live | **Pause yes:** native state 3 → 4 → 3, meaning running → paused → running. Native panel draw calls observed with the Vulkan game window |
| Azahar 2126.1.2 | **Yes:** embedded SDL2 getters **and** real event watcher | **Yes:** actual game-bound polling plus callback delivery | **Yes:** controller-button results and delivered event IDs/mappings change live | **Pause yes:** native frame-advance/pause flag 0 → 1 → 0. Native panel draw calls observed |
| Ryubing, runtime **Ryujinx 1.3.3** | **Yes:** lazily loaded SDL2, called from managed code | **Yes:** managed calls reach the intercepted native getters | **Yes:** live button/axis results change for its configured Player 1 | **Pause yes:** its configured F5 action adds then removes `(Paused)` from the game window title. Panel continues receiving draw callbacks |

In column 3, “selection” means changing **which device supplies input to an already bound logical controller**, inside the process. The emulator's own device dropdown/configuration is not rewritten. The experiment's mappings live in the bridge. Native settings persistence, reconnect recovery and Broomm profile persistence are later work.

Column 4 deliberately distinguishes a working native draw path from visually accepted compositing. The panel is a child `NSView` in the emulator's own content view, drawn with CoreGraphics/CoreText from C through the Objective-C runtime. It is **not a Metal/Vulkan present hook**, an interactive settings menu, or proof that a Flutter surface can be shared with the emulator. No screen-control or screen-capture tools were used.

## What was actually tested

| Emulator | Supplied game | Actual SDL runtime |
| --- | --- | --- |
| RetroArch | Super Mario World `.sfc` | SDL **3.4.0**, dynamic library |
| Dolphin | Super Smash Bros. Melee `.rvz` | SDL **3.4.0**, statically embedded |
| RPCS3 | Rayman Legends BLUS31183 `EBOOT.BIN` | SDL **3.4.16**, dynamic library |
| Azahar | Mario Kart 7 `.cci` | SDL **2.32.10**, statically embedded |
| Ryubing | Super Mario 3D World + Bowser's Fury `.nsp` | SDL **2.30.0**, dynamic library loaded after startup |

The supplied Brawl ROM was not needed for the GameCube Dolphin proof; Wii-specific bindings are not established by the Melee run. The RPCS3 game required the supplied PS3 firmware, installed in a private portable root. Ryubing used the supplied keys/firmware in its private `-r` root. Source ROMs, firmware, keys, original emulator bundles and original settings were read-only. Disk hashes compare the private and original executable bytes; hooks change memory rather than those files.

The Devbox lock pins Flutter 3.47.0-sdk-links / Dart 3.13.0. The C libraries build with the already provisioned Apple clang 21 / Apple SDK. No OS packages, controller drivers, Go helpers, emulator source changes or renderer libraries were installed.

Each session attaches two virtual controllers to **the existing SDL runtime inside that process**. It alternates known button edges and axis values, checks passthrough, swaps buttons 0/1, then swaps sources A/B while the emulator remains open. The bridge logs original/effective values, actual native call sites, runtime IDs, callback delivery, pause readback and draw counts. Fixture-generated queries are excluded from native query counters. The evidence checker requires native calls in all three policies, changed native results in both mapping policies, no sampled passthrough mismatch, passing fixture checks, a pause/resume round trip and draw callbacks.

Final periodic snapshots, recorded in the accompanying JSON (counts are observations, not performance benchmarks):

| Emulator | Native queries | Changed native results | Panel draw callbacks | Failed fixture checks |
| --- | ---: | ---: | ---: | ---: |
| RetroArch | 55,446 | 10,962 | 14 | 0 |
| Dolphin | 24,577 | 3,916 | 11 | 0 |
| RPCS3 | 810,270 | 29,588 | 14 | 0 |
| Azahar | 14,290 | 4,834 | 13 | 0 |
| Ryubing | 636,093 | 22,726 | 11 | 0 |

Azahar additionally recorded 637 real watcher callbacks and 608 matching input-event observations. All five recorded changed native results in both remapping modes and passed pause/resume readback.

A second SDL runtime or a launcher-side device list would not prove these results. SDL2 instance ID **0 is valid**; an early fixture incorrectly treated it as missing, which was corrected. The final evidence comes from clean logs with a single emulator PID, not mixed startup/error-child output.

## Why this is stronger than player-index overrides

The useful interception point is SDL's **live DynAPI function table**. The inspected ARM64 entry points use dispatch stubs; the bridge validates their instructions and derives the same table base independently from three getters. It then replaces selected data pointers, retaining the original function targets. SDL2 and SDL3 get separate ABI-correct bridge builds. This also reaches embedded SDL without loading another SDL implementation. [SDL DynAPI ABI](https://github.com/libsdl-org/SDL/blob/release-3.4.0/docs/README-dynapi.md).

In passthrough, a getter returns its original native result directly. Remapping changes the requested control; routing chooses a different existing source handle. This controls the data the emulator actually consumes, independent of whether its UI calls a device “SDL/0/name”, “name 1”, a normalized GUID/ordinal, or something else. It goes beyond changing `SDL_GetGamepadPlayerIndex` and hoping an emulator uses that value.

Emulator bindings still require tight integration. Dolphin's configured qualifier was verified through actual gamepad getter calls. RPCS3's SDL device name was confirmed in its own pad log. Ryubing rejected the first two candidate IDs; the accepted fixture ID was `0-000000ff-6956-7472-7561-6c2043007601`, followed by native getters and its own Player 1 connection log. That normalization is a measured adapter detail, not a universal GUID conversion guarantee. [RPCS3 SDL naming](https://github.com/RPCS3/rpcs3/blob/d08d568d/rpcs3/Input/sdl_pad_handler.cpp), [official Ryubing identifier report](https://github.com/Ryubing/Issues/issues/10).

Azahar is **not solely event-driven**: its selected buttons and axes poll SDL, while its event watcher also handles lifecycle and event-derived input. Both were observed. Replacing only `SDL_PollEvent` would miss its watcher; replacing only a player-index getter would miss its actual button/axis contract. [Azahar getters](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/input_common/sdl/sdl_joystick.cpp), [event watcher](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/input_common/sdl/sdl_impl.cpp).

## Pause and rendering are separate integrations

Pausing uses the emulator's semantic controls, while its UI/event loop remains alive. No process suspension or blocked rendering thread stands in for pause.

- RetroArch: its existing command protocol, with `GET_STATUS` readback.
- Dolphin: version-specific native `Core::System` / `GetState` / `SetState` calls, resolved from this executable's symbols and scheduled on the main thread. [State contract](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Core/Core/Core.h).
- Azahar: its native pause/resume methods on the actual Qt main-window object. Readback checks the compiled method's instruction layout before inspecting the corresponding frame-limiter flag. This is a pinned-build experiment, not a stable public C ABI. [Methods](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/citra_qt/citra_qt.cpp).
- RPCS3: its existing `OnPlayOrPause` action, with its native status read before/after. Startup state 7 is **Starting**, not paused or running, and is rejected. First-use PPU compilation took several minutes; a subsequent warm run reached running state and verified 3 → 4 → 3, with Rayman reporting about 60 FPS. [States](https://github.com/RPCS3/rpcs3/blob/d08d568d/rpcs3/Emu/System.h), [action](https://github.com/RPCS3/rpcs3/blob/d08d568d/rpcs3/rpcs3qt/main_window.cpp).
- Ryubing: the actual private config specifies F5 for pause. The injected C code delivers it through the emulator's own AppKit game window, with title readback. It does not assume SDL keyboard state is the Avalonia keyboard backend.

The C panel demonstrates a small, dependency-free macOS native presentation option. It does not decide the final shared Flutter menu architecture. Renderer-specific hooks remain a separate experiment if the native child view cannot satisfy visibility/fullscreen requirements. Resolution setters, restart warnings and broad settings control have not been implemented by this proof.

## Failures and boundaries retained in the evidence

Several failures changed the probe rather than being counted as successes: Apple platform launch tools stripped the original DYLD environment placement; embedded SDL had stripped public entry points; injected libraries changed dyld image ordering; SDL2 ID 0 was mishandled; a direct Qt dialog close caused a native crash and was replaced by a queued Qt close event; and a private RPCS3 error child initially contaminated a later log. The final runner locks sessions, stops its private error children, archives prior logs and records PIDs.

RPCS3 portable mode still uses a hardcoded macOS cache/log directory. An exact-prefix filesystem interposition confines those accesses to the private experiment cache while a seatbelt continues denying original-path writes. This is additional research plumbing, not a verified general-purpose filesystem sandbox or production save-isolation adapter. Headless firmware installation also succeeded then hit an RPCS3 teardown crash; that command's exit is not marked successful merely because the installed firmware was usable afterward.

Qt object/method access is intentionally narrow. The C-only ABI prototype retains temporary Qt container/string references for the short test; production code needs ownership-safe interop. Internal symbols, private layouts and dispatch patterns can change between builds. The successful injection of these local distributions does not establish that a stock hardened/notarized distribution permits identical loading or that a system-selected executable can always be integrated without preparing a managed copy.

## What this does and does not settle for Broomm

The evidence supports proceeding with **per-emulator C bridges against the emulator's own input runtime**, with Dart owning setup, sessions and policy persistence. It removes the need to guess controller ordering from the GUI toolkit for these selected SDL paths. A setup/join UI should obtain input from the same process/context that will consume it, then acknowledge an applied logical-player route.

It does **not** recover a physical identity that Steam has discarded or merged into a virtual device. Linux/Steam remains a required native test with the actual launch route, physical/virtual duplicates, reversed identical controllers, disconnect/reconnect, held-button policy changes and X11/XWayland versus Wayland where applicable. No Linux binary or Steam-input session was executed here.

Before production acceptance, also verify physical rumble/motion/touch, more than two players, input neutralization while a menu is open, visible panel ordering/fullscreen/renderer recreation, focus and other overlays, safe shutdown/save preservation, profile policy persistence and update/signing compatibility. Held-input state reconciliation is not solved merely by swapping event IDs; these fixture transitions use repeated edges and are not a sticky-button recovery guarantee. Android remains outside this injection work.

The remaining access question is practical: **which Linux machine/launch environment should be used for the Steam Input reproduction?** No further product-policy decision is needed to continue the already authorized investigation.
