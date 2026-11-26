# Remote screen implementation

24 November 2026. The first preview adds macOS hosting and shared client code
inside the Flutter application. The [product contract](../PROJECT.md#remote-screen)
and [walkthrough](../README.md#remote-screen-preview) define the visible flow.

## Android receive crash — 26 November 2026

The owner's Galaxy records three identical build-1210 crashes as a video session
starts. Each has `SecurityException: ... android.permission.ACCESS_NETWORK_STATE`
in `NetworkMonitorAutoDetect`, followed by WebRTC's JNI fatal check and SIGABRT
on `network_thread`. The missing Android network-state declarations are now
included in the application manifest. These are install-time normal permissions
([Android reference](https://developer.android.com/reference/android/Manifest.permission#ACCESS_NETWORK_STATE));
camera/microphone capture is outside this receiver change.

The Android release recipe checks permissions in the actual merged APK with
the existing SDK's [AAPT2](https://developer.android.com/tools/aapt2#dump).
Missing or API-capped network permissions fail packaging. Three regressions
exercise those conditions; 24 focused cases and static analysis pass. Device
media verification must follow a freshly installed update; prior compilation,
startup and macOS loopback results did not prove Android video reception.

## Approved WebRTC prototype — 25 November 2026

The owner selected `flutter_webrtc` after reviewing native adapters and shared
media engines. Broomm pins version 1.6.3 and keeps the existing application,
discovery, connection/history UI, authentication and controller/touch transport.
Peers advertise `webrtc-1`; otherwise the existing version-1 JPEG path remains.
WebRTC descriptions/candidates use a separately bounded 64 KiB message kind on
the authenticated control socket. Normal control messages remain limited to
2 KiB. SDP and ICE credentials are never logged. Media uses direct ICE with no
configured external STUN/TURN server and a video-only peer; forwarded audio is
still deferred. WebRTC secures its media transport; the preview's control
connection/code remains unencrypted and retains its trusted-LAN notice.

The current macOS source keeps Broomm's supervised process/window validation,
game-area crop, window restoration and cancellation generations. It registers
one source through the plugin's engine-scoped `instanceForMessenger` and public
local-stream/track hooks. ScreenCaptureKit forwards cropped pixel buffers to
`RTCVideoSource` at a 1440×1080 / 60 fps target, avoiding the JPEG encode path.
The shared receiver uses the plugin's native renderer/texture. H.264 is preferred
when offered, while other supported codecs remain negotiable. The first real
macOS loopback check identifies VideoToolbox on both sides; hardware use on
Android, Windows and Linux must be established separately.

Media startup, pending signaling, ICE candidates, socket writes, diagnostic
operations and resource teardown have explicit limits. Local descriptions are
sent before their candidates. Old session IDs are ignored. Cancellation closes
an eventual late peer acquisition; capture stops before local stream teardown.
Video failures retain controller/touch connectivity and expose Retry screen.
That action starts a new capture generation/peer. A remote texture is displayed
only after its first rendered frame, with an actionable startup deadline.
Every five seconds, validated structured reports identify dimensions, codec
implementation, encoded/decoded fps and cumulative loss/drop counts. They do not
establish perceptual image quality, distinct game-image FPS or input/video latency.

`tool/webrtc_native.json` records the reviewed desktop runtime hashes. Before
packaging, `dart tool/prepare_webrtc.dart` verifies the pinned upstream recipe
and applies bounded, serialized downloads plus archive/binary verification in
the project-managed package cache. It refuses unreviewed recipes and damaged
cache contents. `tool/check_webrtc_native_cache.dart` exercises corrupt archives
and binaries on native Windows/Linux runners after building the actual plugin.
Apple's Swift package pins the XCFramework checksum; Android verifies the new
WebRTC/AudioSwitch Maven artifacts in `android/gradle/verification-metadata.xml`.
Upstream-provided license/notice texts ship under `assets/licenses/`. Build tools
remain development-only; applications ship the plugin runtimes, not compilers.

Native runtime versions and source/build references:

- Flutter plugin: [1.6.3](https://pub.dev/packages/flutter_webrtc/versions/1.6.3),
  MIT wrapper plus its upstream NOTICE; Dart transitive dependencies are locked.
- Apple/Android SDK: **150.7871.04**, [SDK source](https://github.com/webrtc-sdk/webrtc),
  [build recipes](https://github.com/webrtc-sdk/webrtc-build),
  [Apple release](https://github.com/webrtc-sdk/Specs/releases/tag/150.7871.04),
  Android `io.github.webrtc-sdk:android:150.7871.04`.
- Windows x64/Linux x64/ARM64 wrapper: **libwebrtc.m150.7871.07**,
  [source and release](https://github.com/webrtc-sdk/libwebrtc-wrapper/releases/tag/libwebrtc.m150.7871.07).
  Archive structure, embedded runtime architecture/hash and supplied notices were
  inspected before pinning. Native architecture compilation remains a separate check.
- AudioSwitch: pinned commit **039a35aefab7747c557242fa216c9ea11743b604**, a native
  Android transitive dependency. Its upstream Apache license ships with the notices.
- Android path-provider implementation: **2.2.23**, explicitly constrained within
  path_provider's supported range. The 2.3 JNI rewrite adds a desktop native
  asset requiring `libjvm.so`; Linux package verification caught that unwanted
  runtime dependency. The channel-based implementation keeps Java a development
  tool rather than an application requirement. Desktop bundles still undergo
  their complete native dependency checks.

The standalone native check is a separate development entry point, never the
packaged app's entry point. Use a previously prepared private melonDS fixture:

```sh
devbox run -- bash tool/build_app.sh --release --portable \
  --target=tool/check_remote_rtc.dart \
  --dart-define=BROOMM_RTC_PROJECT=/absolute/path/to/broomm \
  --dart-define=BROOMM_RTC_FIXTURE_ROOT=/absolute/path/to/broomm/.tool-cache/research/remote-followup/native-EXAMPLE
```

Run that fixture bundle's executable and inspect
`.tool-cache/research/remote-webrtc/native-loopback.json`. It launches a fresh
private profile, verifies high-resolution native H.264 reception, closes capture
and both peers, then closes the private game normally. Rebuild the ordinary app
without `--target` before packaging. The executed first check reports success,
1440×1080 VideoToolbox encoding/decoding, 54.8–56.8 fps measured windows and no
reported drops/loss. The final fixture measures 57.0–57.4 fps. It preserves the
owner's installation, profile and progress. CI run 45550187927 packages all five
targets and passes native macOS XCTest plus Windows/Linux package and corrupt-cache
checks. Run 45552737250 also packages all five targets after the discovery fix,
passes native macOS XCTest and passes macOS/Linux checks.
This establishes native compilation/packaging, not Windows/Linux client media
playback. Tablet Wi-Fi/visual acceptance is still pending.

Static analysis, all 865 local Flutter tests (one existing Linux-only skip)
and 21 focused remote tests pass. Three discovery regressions
cover asynchronous no-route errors, preserving TCP control when advertisement
fails, and stale socket errors after a new search. These address the real macOS
CI discovery failure without disabling broadcast or changing network settings.
Full-suite and package checks track that correction separately from the
unchanged Windows file-in-use fixture cleanup failures. The current Mac preview
is build 1221. Matching Android build 1210 is installed on the Galaxy with the
retained signing identity, an unchanged UID and matching installed APK readback.
The app launches without an observed fatal startup error. This verifies package
installation/startup, not tablet hardware decode or visual acceptance. Exact
package hashes and revision identities are in IMPLEMENTATION.md.

## Connection and input

The application owns a TCP listener on port 43187 for its lifetime. UDP discovery
replies advertise the listener port and expose no connection code. A client
must supply the host's installation code before sending navigation or input.
Failed authentication is bounded, and one authenticated remote screen is allowed.
The listener and sockets close during normal application shutdown.

The versioned TCP protocol uses a five-byte header with a message kind and
big-endian payload length. Control messages are limited to 2 KiB and JPEG frames
to 1 MiB before payload allocation. Both endpoints bound pending writes and use
write deadlines. Client heartbeats detect a silent host. Sender-relative monotonic timestamps
reject input delayed in transit before it can trigger launcher actions. The native encoder gets its next credit when the bounded socket write finishes,
not when the client paints and acknowledges a frame. One encoded frame is in
flight. The client decodes one JPEG at a time with one replaceable pending frame;
older pending images are dropped and video never fills Flutter's ImageCache.
Codecs/source images are disposed on completion, replacement, pause and teardown.
The client decodes at 640 by 480 and expands the image to its available viewport,
with only a compact connection strip below it. The ordinary shell footer is
hidden while connected. It remembers successful hosts in most recent
order, capped at twelve, under an OS file lock and atomic publication.

The initial transport uses the existing Dart SDK and an unencrypted connection
with an installation code. The connection screen explains its trusted-LAN scope.
An encrypted transport can replace this boundary in a later milestone. No new
Dart package or shipped media runtime is added. This selects the native capture
option from the [dependency comparison](research/lan-controller-and-second-screen.md#transport-and-dependency-choices).

Android reads full foreground controller state through its existing Activity.
macOS uses GameController, Windows uses the existing XInput reader, and Linux
extends the existing evdev reader. The client sends positional buttons, both
sticks and triggers. Device changes and focus loss produce disconnected neutral
input. Launcher actions use Broomm's normal navigation boundary.

For supported macOS games, a private Unix datagram socket carries input to the
emulator's own SDL2 runtime. Each game session gets a fresh endpoint so a
crashed emulator's leftover socket cannot block the next launch. Its virtual source participates in the existing
pairing and logical-port routing. It expires after 350 ms without fresh input.
This is process-local input and requires no host OS controller driver.
The native socket's packet count, size and numeric values are bounded.

melonDS additionally accepts single-touch press, drag and release in DS pixels
(0–255, 0–191). The shared client maps the exact fitted image rectangle, rejects
letterbox presses, clamps an active drag, and ignores extra fingers. Touch uses
the authenticated, timestamp-checked connection. A bounded native queue coalesces
moves while preserving edges; quick taps remain pressed for at least 20 ms so
one DS input frame can observe them. Native expiry is independent of controller
heartbeats. Pause, client focus loss and disconnect release touch. The main-queue
adapter writes the same frontend touch state as the pinned 1.1 ScreenPanel mouse
handlers, guarded by executable identity and matching ARM64 instructions.
It neither moves the system pointer nor creates an OS input device.
Azahar touch remains deferred.

## Emulator layout and video

A connected client at launch enables two windows for melonDS 1.1 or Azahar
2126.1.2. A durable journal records only the layout keys temporarily controlled
by the feature. Broomm restores them after writer exit and before the next
session, preserving unrelated settings changed during play. The normal session
lease protects this work.

ScreenCaptureKit captures one secondary window owned by the supervised child.
The host verifies its PID, process birth, executable and writer-lock ownership
through the existing macOS session adapter. The selector requires a unique
melonDS `[w2]` title or Azahar `Secondary Window` suffix. A missing or ambiguous
source is visible and retryable. Capture requires macOS 12.3 and Screen Recording
permission. The existing app remains deployed for macOS 12.0.

Remote melonDS starts with unrotated, native-aspect, non-integer-scaled top-only
and bottom-only windows. Both maximize once to their display's visible work area;
this does not enter fullscreen or repeatedly override a user resize. Play orders
the primary above the secondary without activating another application. The
bridge publishes the secondary window number and a crop in logical window points,
excluding chrome and letterboxing. Identity-checked capture uses that crop and
updates when geometry changes. Temporary geometry, size and screen preferences
are included in the durable restoration journal.

The [1.1 frontend](https://github.com/melonDS-emu/melonDS/blob/1.1/src/frontend/qt_sdl/Screen.cpp)
uses Qt painting or its OpenGL path, rather than SDL_Renderer. A generic SDL
present hook cannot extract these frames. Direct capture remains feasible with
an emulator-specific bridge covering software and accelerated renderers and their
buffer ownership; that bridge is not implemented here. This follow-up selects
the owner's authorized maximize fallback, retaining ScreenCaptureKit permission
and window-lifecycle requirements.

The observed close failure used a missing QCoreApplication::quit export as a
prerequisite to the Qt close path, then fell back to searching visible AppKit
windows. Hidden windows therefore received no close request; the observed process
exited normally about 36 seconds later, beyond Broomm's 20-second deadline.
The adapter now identifies root window ID 0 and calls melonDS's own onQuit action.
Its normal closeEvent closes child windows and flushes configuration/progress.
The deadline and normal writer/save supervision remain unchanged.

Native capture targets up to 60 frames per second at 640 by 480 and encodes JPEGs
through system frameworks. Five-second diagnostics report capture fps/encoding time, socket fps/bytes/write
time, and client receive/decode fps/time/failures to the host log. Idle, blank and
suspended capture samples are counted separately. Actual Wi-Fi frame rate,
bandwidth and input/video delay still need measurement on the host/client pair. Renderer, window covering,
minimization, fullscreen and Spaces behavior need native acceptance. The client
shows capture problems while preserving its controller connection.

## Stream reliability and frame pacing follow-up

The owner's latest run mostly worked, then displayed the active melonDS caption
without video and consistently raised the secondary. Existing host logs record
stream starts and normal-gameplay/exit transitions but no per-frame progress.
The logged ScreenCaptureKit failures coincide with emulator shutdown; they do
not establish the cause of the earlier blank view.

A real-TCP regression reproduces a deterministic race: the first JPEG arrives,
then the stream-start status clears that image before its widget paints. The
old host then waits forever for the discarded frame's paint acknowledgement.
A second lifecycle race let an older asynchronous capture stop clear a newer
capture handle. Stream generations now reject obsolete native callbacks and
credits. Native ownership detaches the previous handle before awaiting stop;
older work never clears a replacement. Starting status precedes frames, active
status requires a real frame, and active-status updates preserve that frame.
A successfully started stream without a frame gets an actionable four-second
watchdog message while controller input continues. The version-1 JPEG wire
format is retained; old paint acknowledgements are accepted but ignored by the
new host, and a new client can still acknowledge an old host.

A generated 640×480 native encoding benchmark measured **1.61 ms mean / 2.09 ms
p95** for the existing CGImage/NSBitmap encoder, versus **2.07 / 2.30 ms** for
direct CoreImage JPEG. The existing encoder remains. A real loopback comparison
using the original/revised production services and a controlled 40 ms paint-ACK
delay measured **14.98 fps → 29.97 fps** at the same 33 ms source interval.
The revised path achieved **62.28 fps** at a 16 ms source interval. These are
controlled transport measurements with a pre-encoded frame, not tablet Wi-Fi
measurements or end-to-end hardware latency.

Primary ordering now reconciles later activation and secondary raises instead
of remembering only the first order operation. The bridge selects the pinned
Qt root window, uses its raise/activate methods, and keeps Cocoa's primary key
window consistent. Native primary/secondary IDs and order diagnostics are logged.
The integration check uses `optionOnScreenOnly`, which Apple's CGWindow.h
explicitly defines as front-to-back. The earlier `optionAll` test used an
all-window inventory without an ordering guarantee; its failed comparisons were
not accepted as visual evidence. No private WindowServer API is used.

Real focus/close testing also exposed a **SIGBUS in pcre2_jit_match_16 through
QCocoaMenuItem::sync**. The remote melonDS child receives
`QT_ENABLE_REGEXP_JIT=0`, Qt's documented switch for its regex matcher
([Qt documentation](https://doc.qt.io/qt-6/qregularexpression.html#debugging-code-that-uses-qregularexpression)).
This is scoped to that child and concerns Qt menu matching; it does not select
a different DS CPU renderer/recompiler or change any global environment.

Benchmark data, the failing race, complete fixture logs and native crash evidence
are retained under `.tool-cache/research/remote-stream/` and the private
`.tool-cache/research/remote-followup/native-*` roots. The final implementation
record distinguishes compilation, native execution and owner acceptance.

## Live image quality and frame rate — 25 November 2026

This records the JPEG baseline before the approved WebRTC prototype above.

The owner started a real melonDS session after upgrading the Galaxy. The running
host is macOS build **1218**, the client is SM-X800 / Android 16 / build **1202**,
and the game is *Pokemon Ranger: Shadows of Almia*. The TCP connection uses
the local network, through host `en0` and tablet `wlan0`; USB is only the ADB
diagnostic connection. The owner reports general low resolution/softness and
insufficient frame rate, with a much sharper image in the Mac emulator window.
They did not report compression artifacts and have not tested input/video latency.

Forty-five capture/send intervals and forty-six client intervals between
**03:51:00 and 03:54:46 UTC** give the following five-second-window statistics.
The later encoder benchmark was not running during these intervals.

| Phase | Mean fps | Lowest interval | Highest interval |
| --- | ---: | ---: | ---: |
| Capture/encode | 54.02 | 36.4 | 57.9 |
| Socket send | 53.82 | 41.0 | 57.8 |
| Tablet receive | 53.35 | 24.1 | 57.8 |
| Tablet decode | 50.78 | 23.3 | 57.0 |

There are zero reported decode failures. The latest twelve client intervals in
that window average **54.25 decoded fps**. These phases use independent report
boundaries, so their minima are not a same-frame attribution. Capture averages
**2.43 ms** encoding; client decode completion averages **12.20 ms**. Send rate
averages **1,758 KiB/s**, peaks at **4,053 KiB/s**, and socket writes average
**0.28 ms**. The tablet reports a 5 GHz link at 1,441 Mbps PHY rate and -48 dBm;
this is advertised link speed, not a measured capacity test. Thermal status is
zero. This run does not show sustained socket backpressure explaining the drops.

Android SurfaceFlinger presentation timestamps separately establish actual
SurfaceView updates: an initial 126-timestamp sample gives **57.08 fps**, with
six intervals at least 25 ms. Three later samples after the encoding benchmark
give **55.02, 55.39 and 55.39 fps**, with 10–11 doubled intervals per 125–126
intervals and a maximum interval of **33.44 ms**. This establishes uneven
presentation cadence; it does not count distinct emulated-game images or measure
input/video latency. Android `gfxinfo` only tracked 24 native view frames and
is not used as Flutter video FPS evidence.

The sharpness limitation is concrete: capture is fixed at **640×480**, and the
Dart decoder independently caps every incoming image to that same size. The
tablet's Flutter surface is **2800×1752**. Fitting the image across its available
viewport enlarges an already downsampled picture. JPEG quality is 0.75; increasing
that value alone cannot recover detail removed by the resolution caps.

A separate generated-image benchmark of the existing native JPEG path finds
**1.73 ms / 65,573 bytes** at 640×480 versus **5.27 ms / 261,711 bytes** at
1280×960, both quality 0.75. At quality 0.90 the 1280×960 result is
**6.04 ms / 365,149 bytes**. These are encode-only means from 80 warmed frames
per case, not real-game bandwidth or tablet decoding measurements. Merely
raising both caps therefore needs new native client checks before shipping.

The proposed next milestone is higher-resolution hardware video, with a
client-sized 4:3 target (initial experiment: **1440×1080 at 60 fps**) bounded by
the captured source. The existing native-adapter design can use Apple's
[VideoToolbox streaming encoder](https://developer.apple.com/documentation/videotoolbox/encoding-video-for-live-streaming),
Android's [hardware codec capability checks](https://developer.android.com/media/optimize/performance/codec)
and a Flutter [external texture](https://api.flutter.dev/flutter/widgets/Texture-class.html).
This would avoid decoding each JPEG into a new Dart-managed image. It is a
proposal, not implemented or verified support, and is not a new dependency decision.

| Approach | Benefit | Work and remaining risk |
| --- | --- | --- |
| Higher-resolution JPEG | Reuses the current wire format and all four client implementations; no new runtime | Encoding, bandwidth and client image decode/upload rise together. Needs explicit quality limits and native frame-rate checks. |
| System H.264 codecs and external textures | Candidate for higher detail with hardware decode and temporal compression; no bundled media runtime on macOS/Android | Requires capability negotiation, bounded codec queues, keyframe/config recovery and cancellation checks. macOS/Android, Windows [Media Foundation](https://learn.microsoft.com/en-us/windows/win32/medfound/h-264-video-decoder) and Linux codec availability need separate native adapters and verification. JPEG can remain the supported fallback. |
| Bundled cross-platform media runtime | Could share more codec/transport behavior | Reopens the dependency comparison: distribution, licenses, runtime assets and hardware backends on every target. No such dependency is selected here. |

Live reports, timestamps, source/build identity, thermal/memory checks and the
encoding benchmark remain under `.tool-cache/research/remote-stream/live-20261125/`.
No emulator settings, live progress, network settings or running application
were changed. Sharpness and frame-rate acceptance remain open.

## Verification

The remote tests exercise real loopback authentication and control delivery,
UDP discovery, persisted recent hosts, rejected oversized transport headers,
invalid controller ranges, interrupted layout recovery and the role-selection UI.
The C receiver fixture exercises real Unix datagrams with controlled SDL calls,
including malformed packets, expiry and reconnect. Address and undefined-behavior
sanitizer execution is independent of the ordinary fixture.

Commands run from the checkout use its Devbox environments.

```sh
devbox run -- bash tool/ci/in_env.sh flutter --suppress-analytics analyze --no-pub
devbox run -- bash tool/ci/in_env.sh flutter --suppress-analytics test --no-pub
devbox run --config tool/android check
devbox run -- bash tool/build_bridges.sh
devbox run -- bash tool/check_remote_input.sh
devbox run -- bash tool/check_remote_input.sh --sanitize
```

The child environment selects the pre-provisioned Apple compiler and SDK on
macOS for native Dart assets and native test fixtures. `devbox run app-check`
and `prototype-check` use that same environment. It does not change the global
Xcode selection or install machine-wide dependencies.

The owner verified macOS-to-Galaxy-tablet video and forwarded controller input
on the original PR preview, reporting image sizing, missing touch and close
problems. That is scoped owner-performed melonDS acceptance, not Azahar or
all-platform acceptance.

The latest follow-up passes static analysis, 859 macOS-hosted Flutter tests (one existing
Linux-only skip), real loopback touch/authentication/focus-loss checks, and
ordinary plus independent ASan/UBSan native receiver/window fixtures. The latter
check tap edges, minimum duration, invalid packets, expiry, pause, windowed
maximize, cropping, resize behavior, unrelated windows and primary stacking.
An actual melonDS 1.1 ARM64 fixture copies an existing verified installation and
local ROM under its source session lease, then runs with fresh private saves.
Three runs (normal, remote and remote relaunch) verify visible primary ordering
and recovery after a controlled secondary raise, then confirm all AppKit windows
are invisible before normal close. They exit in 532, 611 and 567 ms. Both remote
runs read back press coordinates and release/pause state in the native frontend
and publish a 1228×921 game crop. These checks establish native frontend delivery;
they do not replace owner gameplay acceptance of touch or the revised stream.
No production profile/save is used by that fixture.

To repeat that explicit integration check, supply a managed Broomm data root and
a local DS ROM, then run:

```sh
BROOMM_REMOTE_FIXTURE_INSTALL=/path/to/Broomm-data \
BROOMM_REMOTE_FIXTURE_ROM=/path/to/game.nds \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
devbox run -- flutter --suppress-analytics test --no-pub tool/check_remote_melonds_test.dart
```

Its private copies, fresh saves and diagnostics remain under
`.tool-cache/research/remote-followup/native-*`; after the fixture has exited,
those fixture directories may be removed. The source lock is released after
copying. Final package fingerprints are in IMPLEMENTATION.md. Owner verification
of revised tablet sizing, touch gameplay, cropped capture, permissions and
renderer behavior remains pending, along with Azahar gameplay and native
Windows/Linux client execution. The live measurements above establish current
LAN throughput and presentation cadence; input/video latency remains unmeasured.
