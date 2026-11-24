# Remote screen implementation

24 November 2026. The first preview adds macOS hosting and shared client code
inside the Flutter application. The [product contract](../PROJECT.md#remote-screen)
and [walkthrough](../README.md#remote-screen-preview) define the visible flow.

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
reject input delayed in transit before it can trigger launcher actions. Video waits for a client
render acknowledgement before the native encoder produces the next frame.
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

Native capture targets 30 frames per second at 640 by 480 and encodes JPEGs
through system frameworks. Actual frame rate, bandwidth and input/video delay
need measurement on the host and client pair. Renderer, window covering,
minimization, fullscreen and Spaces behavior need native acceptance. The client
shows capture problems while preserving its controller connection.

## Verification

The remote tests exercise real loopback authentication and control delivery,
UDP discovery, persisted recent hosts, rejected oversized transport headers,
invalid controller ranges, interrupted layout recovery and the role-selection UI.
The C receiver fixture exercises real Unix datagrams with controlled SDL calls,
including malformed packets, expiry and reconnect. Address and undefined-behavior
sanitizer execution is independent of the ordinary fixture.

Commands run from the checkout use its Devbox environments.

```sh
devbox run -- flutter --suppress-analytics analyze --no-pub
devbox run -- flutter --suppress-analytics test --no-pub
devbox run --config tool/android check
devbox run -- bash tool/build_bridges.sh
devbox run -- bash tool/check_remote_input.sh
devbox run -- bash tool/check_remote_input.sh --sanitize
```

The owner verified macOS-to-Galaxy-tablet video and forwarded controller input
on the original PR preview, reporting image sizing, missing touch and close
problems. That is scoped owner-performed melonDS acceptance, not Azahar or
all-platform acceptance.

The follow-up passes static analysis, 854 macOS-hosted Flutter tests (one existing
Linux-only skip), real loopback touch/authentication/focus-loss checks, and
ordinary plus independent ASan/UBSan native receiver/window fixtures. The latter
check tap edges, minimum duration, invalid packets, expiry, pause, windowed
maximize, cropping, resize behavior, unrelated windows and primary stacking.
An actual melonDS 1.1 ARM64 fixture copies an existing verified installation and
local ROM under its source session lease, then runs with fresh private saves.
Three runs (normal, remote and remote relaunch) confirm all AppKit windows are
invisible before normal close. They exit in 503, 639 and 500 ms. Both remote
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
renderer behavior remains pending, along with Azahar gameplay, latency/bandwidth
measurements and native Windows/Linux client execution.
