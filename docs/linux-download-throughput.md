# Linux RomM download throughput — 2026-11-02

The slow download was receiving payload, rather than verifying a checksum.
Broomm sustained about 2 MB/s while its TCP receive queue held roughly
650–760 KiB. The CachyOS machine had a 1 Gbit wired link, no measured I/O
pressure, and a direct Tailscale peer endpoint on the server's LAN. There was
no relay detour. The owner authorized raw log inspection and comparison with
`http://192.168.1.2:1080`.

The native Flutter UI isolate was the measured bottleneck. The same HTTPS
consumer, without file writes, reached 2.38 MB/s on that isolate and 57.39 MB/s
on an independent Dart isolate. This establishes the scheduling boundary;
it does not identify a specific GTK/Flutter engine defect. Disk batching,
synchronous stream listeners and removing per-chunk timeout churn each failed
to improve it materially. Those experiments were removed from product code.

## Measurements

These use eight copies of the same public RomM font asset, 1,307,660 bytes each,
on the owner's Linux host. MB/s means decimal megabytes per second. No real
account credentials were used and the tests made no RomM writes.

| Native Linux measurement | HTTPS over Tailscale | Direct LAN HTTP |
| --- | ---: | ---: |
| curl to `/dev/null` | 51.84 MB/s | 75.03 MB/s |
| Flutter, original production file loop | 2.26 MB/s | 27.72 MB/s |
| Flutter, production background file worker | **11.85 MB/s** | **23.11 MB/s** |

The full worker measurement includes a fresh isolate, HTTP connection, disk
flush, confirmed close and exit for each small file. Its HTTPS result is
5.24 times the original; small-file startup overhead explains why it is below
the raw background stream's 38–57 MB/s. Direct HTTP was already fast and gains
no benefit in this small-file test. A full authenticated large-game download
with the fix remains owner acceptance. These are not a controlled VPN-only
comparison: the LAN URL also changes HTTP/TLS and routing.

## Implemented correction and recovery

The default `RommClient` moves game-content HTTP reads and private-file writes
to one Dart isolate per file. This also covers updates/DLC downloaded through
that API. Authentication refresh and account association stay in the calling
workflow; only the current access-token snapshot enters worker memory. No
password, refresh token, account file or GUI connection setting is exported.
Progress reaches the UI at most once per 120 ms plus final byte count.

Manifest size enforcement, redirect refusal, HTTP failures, stall/total limits,
flush and close remain in the shared transfer routine. Completion requires a
closed-writer result **and** worker exit. Cancellation closes only that worker's
HTTP client and drains it before returning. Closing the owning RomM client
cancels its workers without affecting another client's transfers.

If the worker exits without confirming file closure, Broomm reports the problem,
keeps its private stage and holds the stable game/session OS lock until process
exit. It does not publish the game, delete the uncertain stage or permit another
instance to reuse it. Restart Broomm before retrying; ordinary owned-stage recovery
then applies. Do not delete lock files. The 3DS, PS3 and Switch/Wii/PSP content
workflows retain their stages/session leases for the same failure.

Explicitly injected HTTP clients preserve their existing transport behavior.
Firmware, saves, emulator packages and application updates keep their existing
download routes; this milestone does not claim a speed change there. The fix
uses the Dart SDK and adds no dependency or OS/network configuration.

## Verification and delivery

All **478 macOS Flutter tests** and **410 applicable Linux Flutter tests** pass;
Linux retains 21 existing platform skips. Four new regressions exercise actual
worker HTTP/file I/O: fragmented bytes/final tails and size mismatches; stalled
cancellation alongside another transfer; owner-client shutdown; and retained
cross-process stage/session locks followed by successful restart recovery.
Analysis, repository formatting and diff checks pass. The compiled native Linux
benchmark uses the real production worker. Windows/Android native execution was
not performed this turn.

- [Linux x64 test build](../build/releases/Broomm-Linux-x64-download-speed-CachyOS.tar.gz):
  normal application entry point, all four ELF dependency trees resolve, every
  archived file read back. Local CachyOS/glibc 2.44 baseline; official Ubuntu CI
  remains separate.
- [Current macOS build](../build/releases/Broomm-macOS-download-speed.zip): universal,
  ad-hoc signed, not notarized. Source and fresh extraction pass deep, strict,
  all-architecture signature verification and bundled native/asset readback.
- [Exact timings, source hashes, package hashes and host limits](linux-download-throughput.json).

On Linux, close the old Broomm normally, extract the new archive and run
`bundle/broomm` from the desktop session. On macOS, replace only the application
bundle with the extracted app. Both use the existing production accounts,
library and progress. Queue a game in Store, open Downloads and compare sustained
speed after startup; cancellation must finish before a retry/removal is allowed.
Keep the data directory intact. Delete only the downloaded app archive/extracted
app when finished with a test build; that does not remove game data.

Reproduce the regressions from the project Devbox environment:

```sh
devbox run -- flutter --suppress-analytics test --no-pub test/romm_download_worker_test.dart test/library_download_test.dart test/download_queue_test.dart
devbox run -- flutter --suppress-analytics analyze --no-pub
```

The owner's original app was never restarted or stopped. Its active download
completed naturally at 16:28:48 UTC and published the base game; the old Linux
release reported incomplete add-on integration afterward. Tests used only
project-contained temporary files and disposable diagnostic windows, with the
explicitly authorized desktop connection settings held in memory. No saves or
owner configuration were modified by the tests.
