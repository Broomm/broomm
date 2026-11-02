# Linux managed setup: original gap

The owner adopted RetroArch first. The [implemented Linux x64 milestone](linux-retroarch.md)
and [nine standalone integrations](linux-standalone.md) now supersede this original gap assessment; the inspection below remains dated
evidence rather than the current runtime status.

2026-11-02. Read-only inspection of the owner's CachyOS x86_64 computer over
the SSH connection explicitly supplied for Broomm testing. The running bundle
is Broomm 0.1.6 (1013), `linux-x64`, revision
`82c953d4858f5229f6fa996e2b852417144a45b0`. Its packaged setup assets match this
checkout's macOS-only recipes. Home/Store/download operation is distinct from
emulator support; no game-launch or controller acceptance was performed.

There is no Linux setup JSON hidden behind a disabled default. Simply enabling
the existing setup controls would expose macOS application bundles and native
addresses to a Linux host, while later setup/launch guards would still reject
the operation.

| Boundary | Observed implementation | Required Linux work |
| --- | --- | --- |
| Bundled recipe | `assets/setup/setup.json` declares `macos-arm64`; all `tested-builds.json` records use that host | Select a host-specific reviewed Linux manifest/build/core inventory automatically |
| Setup availability | `ManagedEmulators.supported` accepts only `macos-arm64`; `readPlan` rejects other hosts before parsing imports | Separate real setup/runtime capabilities and advertise only implemented host/build combinations |
| Package extraction | `extractSetupArchive` rejects non-macOS, then invokes Apple's libarchive/DMG tools | Native Linux archive adapter with the existing confined staging, limits, cancellation and publication contracts |
| Build verification | Existing inventories describe `.app` bundles, macOS signatures and pinned macOS symbols | Reviewed Linux executable/runtime identities and platform verification; macOS addresses are not portable |
| Private configuration | Concrete profiles include macOS HOME/portable locations; no-game launch uses Launch Services and the macOS writer guard | Verified Linux-private paths, arguments, child environment and independently retained writer protection |
| Game sessions | `GameSession._launch` rejects non-macOS; active launch uses `sandbox-exec`, DYLD libraries and macOS process/window behavior | Linux process/input/pause/window integration with real acknowledgement, locking, recovery and profile isolation |
| Progress | Ordinary-save formats and RomM workflows exist, but resolution depends on a supported managed session | Verify native Linux filenames, writable boundaries and state compatibility per adapter rather than claiming parity from shared formats |
| Distribution | GitHub builds the Linux Flutter application and packages its runtime libraries | Add the Linux native runtime assets required by the implemented emulator integration; application compilation alone is not emulator support |

The owner's running Linux data directory has accounts, downloads, artwork and
library data; it has no managed emulator selection. No supported emulator was
found on the normal command path. Flatpak lists Discord only. This does not
prove that no emulator executable exists elsewhere. Existing system compiler,
tar, bsdtar, bwrap and unshare tools are present, but Devbox/Nix/Flutter/Dart were
not found on the inspected command path or normal user/tool locations. No tool
was installed, no system configuration changed, and no existing app/process,
account, game, lock or save was modified.

## Proposed first milestone

Bring up **RetroArch on Linux x64** as the first native integration, using the
already selected Broomm frontend release and reviewed Linux core packages.
Complete automatic host selection, managed installation/private configuration,
controller pairing/menu/disconnect, pause ownership, native progress boundaries
and normal/recovery shutdown together before marking it playable. Verify it on
this host over SSH using private fixtures and separately record owner physical
controller/Steam/gamescope acceptance. Keep unsupported standalone adapters
unavailable until their actual Linux packages and native integration are ready.

Then repeat native acceptance for the selected standalone roster. Setup JSON
does not authorize emulator updates, arbitrary native addresses or commands;
retain the existing explicitly initiated setup/update policy. Development must
use a project-contained Devbox environment, without installing OS packages or
changing global SDK selections on the owner's computer.

This document is an audit and proposal, not an implemented Linux setup feature.
