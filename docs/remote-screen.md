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
The client decodes at 640 by 480. It remembers successful hosts in most recent
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

Native macOS packaging, full test counts and artifact fingerprints are recorded
in IMPLEMENTATION.md after final verification. The implementation still needs
a two-device LAN run with real melonDS and Azahar gameplay, physical controller
acceptance, macOS capture-permission and renderer checks, and Android/Windows/Linux
client execution. No DS or 3DS game fixture is installed on this development host.
The current native C fixture establishes receiver behavior with controlled SDL
calls. Its results do not establish real emulator input consumption or video.
