# Pairing responsiveness and emulator loading

Updated 2026-10-16. This follow-up addresses the owner-reported pairing stalls, inactive motion bars and misleading startup controls. Implementation and measurements are scoped to the macOS arm64 prototype. Other native hosts and Steam/gamescope acceptance remain pending.

## Implemented behavior

Launching a game shows an explicit loading screen with the game/emulator, current startup phase and cancellation once the process has started. Controller cards, join icons and device chips are absent. The first pairing screen requires fresh same-process input discovery, stable logical ports and an acknowledged native pause. Host presentation must finish before that screen becomes usable; the initial button state must be released before a join chord can fire. Lost or failed startup observations retain loading/recovery feedback rather than pretending the device list is empty.

Azahar creates its emulation thread and frame-limiter flag before its loading UI has finished. The pinned bridge now checks its loading-screen visibility relative to its owning main window before pausing or reporting ready. A minimized parent is not load completion. The field offset is guarded by instructions in the hashed `OnLoadComplete` function; unsupported layouts fail closed. Dolphin core state, RPCS3 running/paused state, Ryubing game title/pause state and RetroArch's game-specific network acknowledgement keep their existing boundaries. Protocol 4 adds explicit `inputReady`; an earlier bridge is rejected.

Inactive gyro telemetry is hidden, including the accelerometer/gyro bar block when gyro is disabled, unavailable, unreadable or unused by the target controller type. Accelerometer routing remains active independently; hiding telemetry does not disable input. Right-stick pointer status remains visible for Wii fallback modes.

## Measured performance work

The old logger opened/statted/appended files synchronously on Flutter's UI isolate. A controlled 4,000-chunk, 2 MiB burst blocked the event loop for about 362 ms. The replacement uses one in-process Dart isolate, an 8 MiB bounded backlog, batched messages, a persistent file handle, 1 MiB segments and ten-segment retention. Output decoding/escape removal and file rotation run in that worker. Failures surface and retry at a bounded cadence; overflow is reported once per backlog episode. Exit drains output pipes with a bound and closes logging with a bound; neither logging failure nor backlog authorizes discarding game progress. The same burst's UI enqueue/event-loop stall measured about 22/24 ms. This is a controlled stress case, not proof of the exact source of every owner-observed stall.

Controller diagrams previously repainted unconditionally, including static Wii thumbnails, and temporary TextPainters were not explicitly disposed. Diagrams now have repaint boundaries, compare actual mapped control values before repainting, skip building bindings for static thumbnails and dispose temporary text layouts. A native macOS debug UI-only benchmark with four Wii player cards and a 32 ms status cadence measured:

| Metric | Before | After |
| --- | --- | --- |
| Build p50 | 12.87 ms | 7.95 ms |
| Build p95 | 22.87 ms | 11.88 ms |
| Build p99 | 28.15 ms | 14.10 ms |
| Raster p95 | 1.52 ms | 1.01 ms |
| Maximum event-loop gap | 78.11 ms | 60.86 ms |
| Observed RSS | 191.3 MB | 236.8 MB |

Each run lasts 22 seconds with a two-second warmup. These are single controlled debug runs on the owner's M1 Pro host, not production FPS guarantees or long-session memory acceptance. Repaint caching can trade memory for less redraw work; the observed RSS did not decrease. The large log-burst stall and the ordinary UI benchmark measure separate paths.

A two-second sample of paused Dolphin also identified repeated class/ABI symbol lookup in the main-thread bridge. Concrete methods in the pinned executable and the unhooked SDL sensor event/timestamp APIs now resolve once. Mutable SDL interception slots are not globally cached. The final sample removes the repeated main-thread lookup stack and substantially reduces worker lookup samples. Native behavior checks remain necessary because a sampled hot path alone does not establish correct input or pause.

## Verification and limits

The current machine-readable evidence is [pairing-responsiveness.json](pairing-responsiveness.json). Historical controller/motion/gyro snapshots retain their earlier source hashes. Logs and timing artifacts stay under `.tool-cache/research/`; native test results stay under `prototype-data/`.

The 49 Flutter tests cover startup readiness ordering, held join input across loading, startup failure/exit recovery, absence of join widgets while loading, hidden inactive bars, log rotation/retention, retry/recovery and bounded overflow, alongside existing controls/session tests. Real startup checks exercise all six ROMs through the actual Dart model, with presentation suppressed, and require pairing to be usable on its first appearance. Separate native checks cover the prior routing, face swaps, gyro, pointer, disconnect and normal-exit behavior. These do not establish owner physical/visual acceptance.

Initial early-close checks exposed two Azahar shutdown failures. Readiness now waits for its loading screen. An early Cancel also stays pending until startup completes: its constructor displays a modal terminal warning before BootGame and `app.exec`, so closing during that warning can succeed before the game starts and before Qt can process a quit request. The final native suite passes repeated immediate paused closes and cancellation with startup observations suppressed, using the original shutdown timeout. Failed logs/sample are retained; one isolated failed synthetic Azahar process required SIGTERM cleanup after its parent had exited. The interactive app still has no force-kill path and private progress was retained. See [inspected startup and Qt sources](../../experiments/injection/SOURCES.md).

One Debug rebuild failed because a simultaneous Flutter native test regenerated the shared ephemeral Swift-package directory and removed the framework input during compilation. Tests and the final rebuild are serialized; the failed build log is retained separately. No SDK dependency, generated source or global SDK selection was changed to work around it.

## Reproduce

Use the README's normal preparation and verification prerequisites. Diagnostic commands:

```sh
devbox run -- dart tool/profile_session_log.dart improved
devbox run -- dart tool/profile_native_pairing.dart improved
devbox run -- bash tool/build_app.sh --target tool/profile_pairing.dart --dart-define=PROFILE_LABEL=improved
build/macos/Build/Products/Debug/broomm.app/Contents/MacOS/broomm
devbox run prototype-build
devbox run -- flutter test tool/smoke_startup_test.dart
```

The UI profiler is an explicit diagnostic entry point with four synthetic display-only cards; it never starts a game or enables native test sources in interactive Broomm. It exits after its measurement. It temporarily replaces the Debug app entry point: rebuild normally before interactive use, as shown above. The native profiler uses the supplied Brawl fixture and Broomm-owned session data, captures a process sample, and closes normally. ROMs/system emulator settings remain unchanged. Benchmark runs are separate from gameplay acceptance.
