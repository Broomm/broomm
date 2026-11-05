# Thor launcher input stalls — 2026-11-04

**Checkpoint — 2026-11-05:** the input correction and its measured evidence
remain part of the release checkpoint. Further Linux ARM64 investigation is
deferred while [root-backed Android access](android-installation-and-saves.md#next-milestone-root-backed-storage-access)
becomes the next milestone. The [separate emulator failures](thor-gameplay-investigation.md)
remain unresolved; they do not invalidate or broaden the input measurements.

The owner reported severe launcher performance in Gaming Mode on the AYN Thor
running Armada. The running process was the ARM64 standalone preview, with no
emulator active during inspection. Broomm does not configure VRR, a launcher
frame-rate limit, the system GPU governor or a power-saving display mode.

## Measured cause

The app's platform/UI thread repeatedly entered `synchronize_rcu_normal` from
AArch64 syscall 57 (`close`). Linux controller discovery ran on that same Dart
isolate every two seconds. It opened all `/dev/input/event*` nodes, checked the
button capabilities, then synchronously closed every non-gamepad descriptor.
`O_NONBLOCK` does not make descriptor teardown nonblocking. The kernel's
[evdev client detachment](https://github.com/torvalds/linux/blob/master/drivers/input/evdev.c)
calls `synchronize_rcu()` when releasing the descriptor.

The Thor exposed twelve evdev nodes. A single non-exclusive capability scan,
without reading input events, took **315.61 ms**. Individual closes took
**10.90–55.43 ms**, including keyboard, sensor and touch nodes that were not
controllers. Sampling the running app caught its UI thread in this close/RCU
wait 21 times over 160 observations. The controller itself remained open.

The app was also downloading two large games at roughly 50 MB/s combined. Those
transfers explained its I/O totals; CPU, memory and I/O-pressure observations did
not establish system saturation. They were left running during diagnosis and
were not throttled or used as a substitute explanation for the measured UI wait.

## Correction

Linux discovery, input polling and descriptor teardown now belong to a dedicated
Dart isolate. Only the existing navigation action strings cross to the UI.
Polling remains at 16 ms and discovery at two seconds. Windows XInput and the
macOS/Android native navigation paths retain their existing behavior. Gameplay
pairing continues to use the emulator's own API and native bridge.

Before opening a new evdev descriptor, discovery reads the kernel's sysfs key
capabilities. The kernel prints native unsigned-long bitmap words in descending
order; see [input bitmap formatting](https://code.googlesource.com/linux/torvalds/linux/+/4bf54e47525dcacd4c6cdd97fb5902592414dd7a/drivers/input/input.c).
Confirmed non-gamepads need no evdev open/close. A candidate is still validated
by ioctl on the actual opened descriptor. Missing, unreadable or malformed
metadata means unknown and retains the descriptor-based fallback. Metadata is
re-read, so a reused event path is not permanently classified by an older device.

Shutdown stops the worker timers, drains discovery, closes its owned descriptors
and frees its native buffer. Disposal before the worker handshake still requests
cleanup when the handshake arrives. Late actions cannot reach a disposed UI.
There is no worker termination that abandons its native descriptors.

## Verification

An actual Thor comparison used the old and corrected input implementations with
an 8 ms Dart event-loop probe, 0.5 s warmup and nine seconds per case. The same
physical devices and ongoing app/downloads were retained; no UI automation or
synthetic controller actions were sent to the open app.

| Input implementation | Samples | p95 gap | p99 gap | Maximum gap | Gaps above 33 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Previous | 936 | 8.156 ms | 8.727 ms | **285.915 ms** | 4 |
| Worker plus metadata filter | 1065 | 8.149 ms | 8.604 ms | **9.212 ms** | 0 |

These are main-isolate scheduling gaps, **not measured rendered-frame rates**.
The comparison demonstrates removal of the recurring input-induced freezes;
owner visual/input acceptance in the packaged Gaming Mode app remains separate.

Four regression cases pass on native macOS and ARM64 Linux: capability word
classification, unknown/malformed observations and path reuse, a held blocking
kernel read without UI starvation, and disposal before startup. The last two
use a real pipe read that the UI side must release; wall-clock sleeps do not
coordinate the race. Seventeen related input/navigation/widget regressions and
Flutter analysis pass on macOS. Linux ARM64 and macOS release builds succeed.

Diagnostic captures, benchmark sources and logs remain under ignored local
`.tool-cache/research/thor-ui-performance/` and the isolated Thor project
`~/Projects/broomm-thor-fix/.tool-cache/`. No live sign-in, game or progress data
was replaced. The corrected preview is staged alongside the running app at
`~/Downloads/Broomm-Linux-arm64-input-latency-preview/broomm`; close the existing
Broomm first, then launch that binary and test Home/Store/controller navigation,
including during downloads and controller reconnects.
