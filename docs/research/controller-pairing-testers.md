# Controller testers and Wii pairing

Updated 2026-10-16. These are implemented **macOS arm64 prototype** behaviors and scoped verification results, separate from production support or Steam/gamescope acceptance. The owner's subsequent feedback says the previous reliability changes are substantially better; it does not establish acceptance of this new pairing UI.

The later [responsiveness/loading follow-up](pairing-responsiveness.md) supersedes the startup presentation and current protocol/test count below. Pairing now appears only after usable input discovery and native pause; inactive gyro bars are hidden. Earlier evidence snapshots retain their original source hashes.

## Requested and implemented behavior

- Both face pairs change together: physical south/east and west/north are exchanged. Y alone no longer performs any pairing action.
- L1+R1 joins the next player, then cycles Wii controller types. L3+R1 independently swaps both face pairs. A held chord fires once; release both chord buttons before pressing again. Start held after a face chord cannot trigger Play. SDL family is the initial guess, with a name fallback for unknown families. The diagram makes that guess visible and reversible.
- Short Start/Select presses, individual shoulder buttons, face buttons, sticks, triggers and D-pad remain test inputs. Hold Start or Select for one second to apply/play or remove, respectively. Holds reset on release, disconnect, screen/readiness changes and lost pause knowledge. Select+R3 remains reserved for the playing-game menu; Select+Start can send Wii Home in gameplay without triggering a pairing hold.
- Initially one centered Player 1 join card appears. Joined players get a large target-controller tester, followed by only one empty next-player card. Slots stop at the fixture's real limit. Pressing another player's controller scrolls that tester into view if it is in another row. Pointer controls preserve player reordering.
- Original vector diagrams represent SNES, GameCube, DualShock 3, 3DS, Switch Pro and four Wii setups. Face/shoulder/D-pad buttons illuminate; both sticks move and triggers light. PS symbols are vector strokes, independent of symbol-font availability. The tester projects the adapter's configured target controls from the emulator's own SDL samples while game input stays gated. It is not a readback of every game's internal input state. Controls a target does not bind have no invented target action.

Nintendo diamond adapters use A=east, B=south, X=north, Y=west. PS3 uses Cross=south, Circle=east, Square=west, Triangle=north; GameCube retains its asymmetric A/B/X/Y adapter layout. SDL2 children use the positional-label hint to match SDL3. For Nintendo diamond targets, Xbox/PlayStation/unknown sources initially flip both pairs to match familiar face labels; recognized Nintendo sources initially retain their positions. For PS3/GameCube, Nintendo sources initially flip. Unknown family/name is a guess, never device identity. Both SDL type lookups use regenerated metadata from the already reviewed pinned ABI declarations.

The Wii card keeps one large active tester and the four small type choices along the bottom. Face switching preserves the chosen type, and type switching preserves face orientation.

## Wii modes and native application

The behavior audit used PGCS's four general Wii setups as reference, without copying its code. Its game-specific Monkey Ball preset and its profile-hotkey implementation were excluded. Broomm's default is Remote + Nunchuk. L1+R1 cycles the four types without changing face orientation. L3+R1 flips faces without changing type, allowing all eight combinations independently. Clicking one of the four illustrated types preserves the current face orientation.

| Type | Implemented bindings |
| --- | --- |
| Upright Remote | No extension, upright orientation; face buttons → A/B/1/2, D-pad or left stick → Remote D-pad, right stick → relative IR, R1 → shake |
| Classic Controller | Classic extension; Nintendo diamond, D-pad, two sticks, shoulder L/R, trigger ZL/ZR; separate Remote buttons/IR/shake are unbound to avoid duplicate game actions |
| Remote + Nunchuk | Nunchuk extension, left stick → Nunchuk stick, L1 → C, left trigger → Z; Remote face/D-pad/IR/shake as above |
| Horizontal Remote | No extension, sideways orientation; D-pad or left stick → Remote D-pad, face buttons → A/B/1/2, right stick → relative IR, R1 → shake |

Start/Select map to Wii +/− individually; together they map to Home. The in-game Select+R3 chord takes precedence through the input gate. The subsequent [motion follow-up](controller-motion.md) adds source accelerometer/gyro routing and gyro pointing. Right-stick pointing and shake remain fallbacks; MotionPlus and separate Nunchuk motion remain pending.

Dart writes only the session's Broomm-owned `WiimoteNew.ini`, with a revision marker and stable logical devices. The pinned Dolphin 2609 C bridge pauses, checks the marker, calls `InputConfig::LoadConfig`, reads selected extension and upright/sideways values back, and updates native current-run Wiimote source settings for paired, present routes. GameCube SI sockets stay empty during Wii sessions. Input remains gated until native configuration matches and all controller buttons are released. The active emulated extension changes on resumed CPU ticks, which the native test subsequently inspects while paused. No emulator restart, emulator source patch, Go helper, extra SDL runtime or new library is involved.

Protocol 3 carries revision, active/pause, four source IDs, four face-swap flags, quit, four gyro-enable flags and four mode indices (0 upright, 1 Classic, 2 Nunchuk, 3 sideways). Unsupported snapshot protocols fail visibly. Source IDs remain scoped to this emulator process, including valid SDL2 ID zero. Native implementation details are in [native/README.md](../../native/README.md).

## Verification and limits

The [original machine-readable snapshot](controller-pairing-testers.json) records the earlier combined-chord implementation and its hashes/native results. The [motion/independent-control snapshot](controller-motion.json) records the prior motion revision. The [gyro toggle snapshot](gyro-toggle.json) records the current revision and checks. Earlier [prototype](prototype-validation.json) and [reliability](prototype-regressions.json) snapshots remain historical evidence.

- Flutter analysis and **42 tests** pass: pair identity/capacity, both face pairs and target bindings, native six-axis/family snapshots, protocol mismatch, hold/chord timing and readiness, progressive slots, reordering/scrolling, all target painters, and existing exit/recovery boundaries.
- All six supplied ROMs pass real emulator launch, both face-pair routing checks, native pause/resume, R3+Select, held-confirmation neutrality, assigned-device removal and graceful exit. The sources are opt-in in-process SDL substitutes, never enabled by the interactive app. RetroArch's numbered driver slot is also checked.
- In a single Brawl process, all **eight Wii variants** pass configuration acknowledgement, selected and active extension readback, orientation checks, one configured Wii source and zero GameCube sockets. Dolphin's locked Remote button getter confirms both face pairs in the three Remote modes. Mixed Nunchuk/Classic players subsequently show two configured sources and active extensions `[1,2]`. This does not inspect Classic game-action consumption or establish physical-pad/motion acceptance.
- Flutter-rendered PNGs under `.tool-cache/research/pairing-*.png` were inspected for the centered join screen and controller silhouettes/labels. This is artifact inspection, not computer control or owner-performed visual acceptance. Native window regression status is recorded in the snapshot.

One regression run exposed an intermittent Azahar startup deadlock before ROM boot. A native sample showed the hotplug callback holding its map mutex, re-entering SDL, then synchronously receiving another callback while SDL's joystick lock was held. The private pinned Azahar child now defers controller watch callbacks to the main queue. Continuous axis/sensor samples coalesce in a bounded queue; button/hotplug order is preserved, and overflow gates input. The deterministic native fixture pushes another event recursively under the SDL lock and checks deferred, ordered main-thread delivery. Three subsequent launches and two preconnected-source launches passed; the final six-ROM run includes this fixture. The original stalled test ignored normal termination and was cleaned up explicitly before boot; the interactive application has no forced-kill path. An intermediate protocol-version mismatch was also corrected before final checks. Failed diagnostics remain under `.tool-cache/research/`; they are not claimed as passing checks.

Physical controller feel, individual models, real Classic gameplay actions, fullscreen/focus acceptance and Steam/gamescope remain owner/native checks. Linux/Windows injection and Android's simpler external-app handoff remain unimplemented; Flutter scaffolding is not evidence for those capabilities.

## Primary references

- [Dolphin 2609 Wii controller configuration and source changes](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Core/Core/HW/Wiimote.cpp), [InputConfig reload](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Core/InputCommon/InputConfig.cpp), [Wii buttons/orientation and extension updates](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Core/Core/HW/WiimoteEmu/WiimoteEmu.cpp), [attachment selection](https://github.com/dolphin-emu/dolphin/blob/2609/Source/Core/InputCommon/ControllerEmu/ControlGroup/Attachments.cpp).
- [SDL3 3.4 gamepad types and positional buttons](https://github.com/libsdl-org/SDL/blob/release-3.4.0/include/SDL3/SDL_gamepad.h), [SDL2 positional/label hint](https://wiki.libsdl.org/SDL2/SDL_HINT_GAMECONTROLLER_USE_BUTTON_LABELS).
- [Azahar 2126.1.2 input implementation and watcher/map locks](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/input_common/sdl/sdl_impl.cpp), [RPCS3 pad schema](https://github.com/RPCS3/rpcs3/blob/d08d568d/rpcs3/Emu/Io/pad_config.h).

Build recipes, reviewed upstream versions/licenses and ABI-header hashes remain in [probe provenance](../../experiments/injection/SOURCES.md). These links support source interpretation; the recorded native results establish the narrower tested behavior.
