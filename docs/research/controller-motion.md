# Controller motion and independent pairing controls

Updated 2026-10-16. Implemented and checked on the existing **macOS arm64 prototype**. This follows the owner's request for physical-controller motion and the clarified pairing gestures. It does not establish Linux/Steam, Windows or Android behavior.

The later [responsiveness/loading follow-up](pairing-responsiveness.md) records protocol 4, the loading gate and current verification. The telemetry block is now hidden when gyro is disabled, unavailable, unreadable or unused by the target type; acceleration still routes independently. Earlier motion/gyro snapshots remain historical evidence for their recorded revisions.

## Behavior

L1+R1 joins; for an already joined Wii controller it cycles Upright Remote → Classic → Remote + Nunchuk → Horizontal Remote. Other current systems have one type. L3+R1 swaps both face pairs, independently of type. Both chord buttons must be released to rearm. L3+R2 toggles the joined player's gyro, independently of type/faces, without disabling acceleration. The chord works in pairing, the paused menu and gameplay. Analog trigger hysteresis and a fresh release prevent repeated toggles. The Wii card shows one large active tester and all four small illustrated choices below. Start/Select holds, progressive player cards and the in-game R3+Select menu remain unchanged.

The existing C bridge samples the physical gamepad's base SDL accelerometer and gyro in the same runtime that supplies its buttons. The selected player receives that source's sensor data. Reordering follows source identity; face swaps do not rotate motion axes. No sensor capability is guessed from a controller name. The card distinguishes unknown capability, confirmed absence, available sensors and failed samples, and shows live signed axes. Accelerometer bars use gravity units; gyro bars use radians/second.

Logical sensor ports remain available before pairing so emulators can initialize their motion paths once. That interface is a stable routing capability, distinct from the physical device's capabilities reported in the UI. A missing source or failed sensor supplies stationary +Y gravity (`[0,9.80665,0]` m/s²) and zero angular velocity. Pause/disconnect gates also neutralize motion; cached consumers receive neutral events. Getter snapshots older than 100 ms are neutralized. Sampling success does not prove a controller's hardware calibration or that it is producing fresh hardware reports; SDL remains the device boundary.

| Target | Integration | Remaining scope |
| --- | --- | --- |
| Dolphin Wii Remote modes | Six accelerometer directions, six gyro directions, gyro IR when both sensor capabilities exist; R3 without Select recenters. Upright/Nunchuk select relative right-stick IR when gyro is off or the source lacks the required sensors; R1 shake remains available | MotionPlus extension and an independent Nunchuk motion source are pending; one whole gamepad cannot independently represent Remote and Nunchuk movement |
| Dolphin Classic / GameCube, RetroArch SNES | Ordinary controls continue; those target types consume no motion | No invented motion actions |
| RPCS3 | Its SDL Sixaxis path reads routed acceleration and yaw; RPCS3 owns DS3 unit conversion | Supplied Rayman fixture establishes native getter consumption, not a motion game action |
| Azahar | Private profile selects SDL motion on logical port 1; routed sensor events feed its existing input watcher | Final game HID readback and MK7 motion steering need owner verification |
| Ryubing | Private player configurations enable GamepadDriver motion; its SDL2 getters consume routed sensors | Supplied game native getter consumption is verified; motion gameplay needs owner verification |

Dolphin pointer selection depends on the per-player gyro preference and reported capability, not a single successful sample. A temporary read failure therefore becomes neutral input and can recover without a restart or another configuration change. Classic mode removes Remote IMU bindings. In-game toggles gate input before forwarding the chord; Dart publishes the new per-player flags and Dolphin configuration, waits for pause/reload, then resumes after L3 and R2 release. Disconnect/menu/exit events supersede the pending resume. Failures reopen pairing with actionable feedback. Changes stay in Broomm-owned data; no system emulator settings, driver installation, OS settings or emulator source patches are involved.

## Implementation choice and sources

This extends the already selected SDL injection bridge; no new library or runtime dependency was introduced. Direct SDL sensor interception keeps the same runtime/device identity as button pairing, supports getter consumers and event consumers, and uses existing zlib-licensed ABI metadata. Alternatives were a DSU/Cemuhook UDP server (another transport/configuration and inconsistent emulator coverage), per-host native HID paths (more coordinate/identity/backend work), and emulator source changes (the owner prefers unmodified emulators). Those alternatives remain research, not dependency decisions.

SDL2 and SDL3 have different sensor function returns and event layouts. The bridge hooks capability, enable/state, data/rate and SDL2 timestamped data APIs. It emits bounded sensor events every second 8 ms worker tick for cached consumers. A small snapshot lock never surrounds SDL calls or callbacks. Source reads reject nonfinite data and clear validity on failure; disconnect never replays the removed source. The bridge disables only sensors it enabled itself when closing a source. Data remains in SDL's standard controller coordinates and SI units; emulators perform their own platform conversions.

Primary evidence:

- [SDL3 gamepad sensor API and units](https://github.com/libsdl-org/SDL/blob/release-3.4.0/include/SDL3/SDL_gamepad.h), [SDL2 sensor getter](https://wiki.libsdl.org/SDL2/SDL_GameControllerGetSensorData), [SDL2 events](https://github.com/libsdl-org/SDL/blob/release-2.32.10/include/SDL_events.h), [SDL3 events](https://github.com/libsdl-org/SDL/blob/release-3.4.0/include/SDL3/SDL_events.h).
- [Dolphin 2609 sensor initialization/polling](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Core/InputCommon/ControllerInterface/SDL/SDLGamepad.cpp), [input direction names/signs](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Core/InputCommon/ControllerInterface/SDL/SDLGamepad.h), [IMU cursor/recenter](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Core/InputCommon/ControllerEmu/ControlGroup/IMUCursor.cpp).
- [RPCS3 d08d568d sensor polling/Sixaxis conversion](https://github.com/RPCS3/rpcs3/blob/d08d568d/rpcs3/Input/sdl_pad_handler.cpp).
- [Azahar 2126.1.2 SDL motion factory/event conversion](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/input_common/sdl/sdl_impl.cpp), [sensor enable/cache](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/input_common/sdl/sdl_joystick.cpp).
- Ryubing's pinned runtime reports 1.3.3. The measured in-process SDL2 calls establish its getter path. Exact source-host access remains unresolved; third-party mirrors were not adopted as proof of its implementation.

Build provenance, ABI-header hashes, license notices and recipes remain in [SOURCES.md](../../experiments/injection/SOURCES.md). Existing Apple frameworks and the emulator's own SDL are the only native runtime requirements. The C bridge remains a precompiled native adapter; configuration/session workflows remain Dart.

## Measured checks

The [current snapshot](gyro-toggle.json) contains source/bridge/emulator hashes, host, commands and results. The [initial motion snapshot](controller-motion.json) and earlier records remain historical. Native checks run serially with the real coordinator/writer locks, actual supplied ROMs and normal shutdown.

- Flutter analyzer and 42 tests pass, including independent gestures, hold exclusion, Wii type/face preservation, capability uncertainty, partial/failed motion, per-source configuration, local SDL motion settings and UI states.
- Both bridge variants compile with warnings as errors; independent Clang analysis reports zero diagnostics. No race sanitizer execution is claimed.
- All six ROM regressions pass launch, routes, both face pairs, pause/resume, menu/disconnect, writer ownership and graceful exit after sensor sampling was added.
- All eight Wii variants plus mixed Nunchuk/Classic players pass native extension/orientation readback with independent type/face selection.
- Four motion fixtures also verify per-player gyro disable/reenable while acceleration and other players continue, plus synthetic source routing, reassignment, unchanged motion axes after a face flip, failed gyro with working accelerometer, no-sensor source, recovery, menu neutrality, detach gate and graceful exit. Dolphin/RPCS3/Ryubing measurements come from real emulator getter calls and returned values, excluding diagnostic reads. Azahar measurements record routed events after its watcher callback returns; they do not inspect final game HID state.
- In the earlier [motion revision](controller-motion.json), with synthetic inputs disabled, **two connected Nintendo Switch Pro controllers** reported both sensors and live finite data. In Brawl, Dolphin consumes both sensor types on both assigned ports. The five-second observation records source and consumed vectors; nobody was asked to move a controller, and pointing direction/feel was not accepted by the owner.
- A separate live Brawl check drives the actual Dart app model with L3+R2 in upright and Nunchuk modes. The held chord is consumed once, its buttons are gated, and no emulator restart occurs. Dolphin `Cursor::GetState(false)` confirms raw right-stick pointer bindings when gyro is off and zero stick pointer input when gyro is on. A source exposing only acceleration also supplies stick pointing. This getter does not advance relative pointer state or inspect final game IR camera coordinates.
- Rendered Flutter pairing artifacts were inspected without computer-control tools. Native window behavior is unchanged by this work; the previous window regression results remain historical evidence.

Run commands, required local fixtures, output locations and cleanup are in [README.md](../../README.md). Hardware observations require connected motion controllers; the synthetic smoke never enables test sources in interactive Broomm.

## Limits and next verification

Steam Input can expose a virtual pad with no sensors even when the physical controller has them. This prototype reports what the owning SDL runtime exposes; it does not bypass Steam or guarantee motion in gamescope. The existing Ryubing/macOS GCController workaround remains child-scoped, so MFi-only controllers still need separate investigation. Base SDL accel/gyro types are implemented; independently addressed left/right Joy-Con sensors, arbitrary raw joysticks, rumble, MotionPlus and calibration UX are pending. Other native hosts and Android's intentionally simpler external-app handoff remain outside this implemented bridge stage.

For owner testing: join a motion controller, move it and confirm both rows react. Use L3+R1 to flip faces and L3+R2 to disable/enable gyro. With gyro disabled, confirm the gyro row is inactive while acceleration still reacts. In a Wii Remote mode, resume, move/tilt it, press R3 alone to recenter, then reopen pairing with R3+Select. Switch type and face orientation independently and verify motion follows the assigned player. While playing in upright or Nunchuk mode, toggle gyro off and verify right-stick relative pointing; release the chord fully before toggling on again. Test a game that actually consumes motion for each target; sensor polling by a game without motion mechanics does not establish a motion game action.
