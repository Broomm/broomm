# Argosy's Android setup and save workflow

Research date: **2026-10-30**. Source audit of Argosy **2.27.3**, commit
[`68f1368b61707f8c4ad001b89eb095a705a46143`](https://github.com/rommapp/argosy-launcher/tree/68f1368b61707f8c4ad001b89eb095a705a46143),
committed 2026-10-29. The live wiki is supplementary and can change independently
of that commit. [Source inventory and hashes](argosy-android-workflow.json).

This is research and a proposal, **not implemented Android behavior or device
acceptance**. No APK, core, BIOS or save was installed, no RomM account was
accessed, and no external emulator's files were changed. Reference source was
downloaded into an ignored research cache; none was imported into the app.

## Main finding

Broomm's mandatory **Configure saves** step for every Android emulator is an
implementation choice, not a universal Android requirement. Argosy discovers
accessible save locations first and asks for an override when needed. More
significantly, its seamless core installation belongs to a **built-in Libretro
frontend**, distinct from the external RetroArch app. The earlier
[Android audit](android-parity-audit.md) concentrated on external apps and did
not evaluate that frontend as an architectural alternative. Its private-storage
limits remain relevant, but it was insufficient as a guide to Argosy's overall
experience.

| Concern | What Argosy actually does | Consequence for Broomm |
| --- | --- | --- |
| Standalone emulator installation | Finds an APK release/variant, downloads it in-app, checks its package, opens Android's installer, and observes package-added/replaced events. Unknown-source permission and install confirmation still belong to Android. | The recent Broomm APK pipeline follows this broad model already. Setup and save discovery after installation need improvement. |
| Core installation | Downloads missing cores into **Argosy's own private storage** and loads them through its LibretroDroid fork. First launch downloads the selected/default core with progress; onboarding can prefetch cores. | This does not depend on writing into another app's private core directory. Broomm has no equivalent built-in frontend today. |
| External RetroArch | Constructs a launch intent naming a core in RetroArch's own `cores` directory and its configuration. Reads `retroarch.cfg` to locate saves/states. | Do not confuse automatic built-in downloads with an external RetroArch core installer. The inspected external launch path expects the selected core to exist. |
| Save setup | Uses emulator/package/platform-specific paths, configuration discovery and remembered overrides. | Try discovery and verify access before asking the player to configure a folder. |
| RomM synchronization | Resolves the native save unit, restores/checks before play, captures on session end, and queues offline work. | Keep Broomm's existing BROOMM history/profile rules; improve how its external save connection is established. |
| BIOS | Retrieves RomM firmware metadata, downloads on demand, verifies hashes and distributes to known destinations. Built-in launch automatically places downloaded BIOS. | BIOS provisioning is feasible. Downloading, placing and emulator-specific import are different operations. |

## Installation and cores

[`EmulatorDownloadManager.kt`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/emulator/EmulatorDownloadManager.kt)
stages APKs through `.part` files, reports byte-based progress, checks the archive
package against the selected emulator/family, and waits for installation events.
[`AppInstaller.kt`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/update/AppInstaller.kt)
uses a read-only FileProvider URI and prefers a system APK installer. This is
user-confirmed installation, not silent installation. Registry/family detection
also accommodates package variants. Argosy's supported roster and naming are
reference evidence, not replacements for Broomm's verified stable/nightly rules.

For built-in play,
[`GameLauncher.buildBuiltInIntent`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/emulator/GameLauncher.kt#L712)
resolves a core and downloads it if missing before starting `LibretroActivity`.
[`LibretroBuildbot`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/libretro/LibretroBuildbot.kt)
selects an ABI matching the **running process**, using
`https://buildbot.libretro.com/nightly/android/latest/<abi>/`.
[`LibretroCoreManager`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/libretro/LibretroCoreManager.kt)
writes a named ELF library under `filesDir/libretro/cores`, stages publication,
records its version/hash, and retains older builds for rollback. It separately
fetches supporting system assets for some cores. Its core catalogue includes
classic systems and melonDS, Azahar, Dolphin, PPSSPP and ARMSX2; catalogue
membership is not proof of performance, compatibility, or availability for
every ABI. Switch remains an external emulator route.

The external
[`commandForRetroArch`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/emulator/GameLauncher.kt#L1265)
instead supplies `ROM`, `LIBRETRO`, `CONFIGFILE` and Android directory extras.
Its `LIBRETRO` points into `/data/data/<retroarch-package>/cores`. The built-in
downloader does not put that library there. Automatic installation into external
RetroArch through its cooperating provider is a separate integration to prove;
this audit does not establish it by analogy.

## Save discovery and permissions

Argosy's manifest requests broad shared-storage access. Its first-run flow
checks storage permission once rather than requiring an emulator-root grant
before every adapter becomes usable. Its
[`SavePathAuthority`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/emulator/savepath/SavePathAuthority.kt)
distinguishes explicit per-game/platform paths, evaluated defaults, registry
defaults and RetroArch configuration. A known path is not automatically usable:
discovery also tests whether directories can be listed/read.

| Broomm adapter | Relevant Argosy behavior | Remaining condition |
| --- | --- | --- |
| RetroArch | Searches package-specific, public and Android/media configurations; honors save/state sorting and beside-content settings. | Config/core must exist and the actual files must be accessible. |
| PPSSPP / Gold | Recognizes candidate Memory Sticks by `PSP/SYSTEM/ppsspp.ini` or `ppssppvr.ini`; follows usual locations when they move; explicit override wins. | This is a candidate/config heuristic, not a universal API to read arbitrary private preferences. Ambiguity must not choose another profile's progress. |
| melonDS | Knows app-specific and shared `melonDS/saves` candidates and native `.sav` files. | Custom paths and private storage can still need setup. |
| Azahar / MMJ | Knows shared `Azahar`/`citra-emu` and package-specific SDMC layouts, including title identity. | Private variants do not become publicly writable just because their path is known. |
| Dolphin | Knows native GameCube region/card and Wii title directories; has separate built-in and standalone handling. | Correct card mode/save unit and access still matter. Broomm can also use Dolphin's cooperating provider. |
| ARMSX2 | Handles folder cards and game-specific extraction/merge from shared `.ps2` cards; supports custom roots. | Its wiki explicitly asks users with a custom system folder to point Save Path at that folder's `memcards`; multiple folder cards can require a choice. |
| DuckStation | Supports its memory-card layout with device-specific access. | Wiki limits private-card sync to supported AYN/Retroid/Ayaneo access; this is not a general Android guarantee. |
| Eden | Resolves native console-account/title save folders. | Requires actual NAND access; no save-state capability is created. Existing console identity must be preserved. |

Sources:
[`SavePathRegistry`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/emulator/SavePathRegistry.kt),
[`RetroArchConfigParser`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/emulator/RetroArchConfigParser.kt),
[`PpssppMemoryStick`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/emulator/savepath/PpssppMemoryStick.kt),
and the live [Save Sync guide](https://github.com/rommapp/argosy-launcher/wiki/Save-Sync).

There are several storage mechanisms, not one portable permission bypass:

- Ordinary shared files and accessible configuration paths.
- DocumentsContract calls, including an attempted `manage=true` query route.
- An optional build-configured alternate path/symlink route, tested at runtime.
- Vendor root daemons on supported handhelds. `RootShell` selects AYN/Retroid's
  PServer or Ayaneo's Xsu executor. `RootFileAccessor` can adjust group access;
  `AndroidDataMirror` can synchronize copies through that daemon.

See
[`FileAccessLayerImpl`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/storage/FileAccessLayerImpl.kt),
[`AndroidDataAccessor`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/storage/AndroidDataAccessor.kt),
and [`RootShell`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/util/RootShell.kt).
Do not treat upstream comments describing an access technique as evidence it
works on every device. Android's
[documented all-files permission](https://developer.android.com/training/data-storage/manage-all-files)
still excludes other apps' app-specific directories. Broomm's own providers and
emulator-owned DocumentsProviders remain useful routes without vendor root.
No vendor permission changes or alternate-path tricks are adopted here.

## Synchronization lifecycle

The built-in frontend owns its live save/system/state directories and supplies
those paths directly to the core. External apps use discovered locations.
Synchronization therefore works on the emulator's **native save unit**:
cartridge files, per-title folders, companion files, or one game's entries in a
shared card. It is not just a generic copy of an arbitrary `.sav`.

[`SaveSyncRepository.preLaunchSyncForGame`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/repository/SaveSyncRepository.kt#L363)
checks disk against the active cached save and consults RomM. It supports
hash/device-currentness and capability-dependent negotiation, with explicit
local/server conflict results. A user-selected older restore point is respected.
Session-end processing captures progress into a local cache, uploads changes or
queues them offline, and retains conflict information. A network-constrained
WorkManager job drains work periodically (six hours, one-hour flex).

[`PlaySessionTracker`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/emulator/PlaySessionTracker.kt)
also caches built-in saves/states before slow core teardown, so network upload
need not finish before the emulator closes. For external apps,
[`GameSessionService`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/emulator/GameSessionService.kt#L256)
can watch usage/lifecycle events when usage access is granted. That is an
inference about session presence, not proof a process has exited. **Broomm keeps
the owner's accepted “Finished? Sync progress” confirmation**; adopting a presence
watch is unnecessary for this UX improvement.

File uploads retain a file's native extension; directories use ZIP. Slots,
save states, device registration and account ownership are separate concerns.
Argosy uses its own autosave/channel policies and supports newer server snapshot
APIs conditionally. Broomm's target **RomM 5.4**, profile isolation, timestamped
**BROOMM** slot, explicit import/backup and conflict rules remain authoritative.
Do not copy Argosy's slot selection, cleanup or restore semantics wholesale.
Its internal design documents contain audits/proposals as well as descriptions;
they are not evidence that every listed defect or proposed fix is current.

## BIOS and firmware

**Argosy does support BIOS provisioning.**
[`BiosRepository`](https://github.com/rommapp/argosy-launcher/blob/68f1368b61707f8c4ad001b89eb095a705a46143/app/src/main/kotlin/com/nendo/argosy/data/repository/BiosRepository.kt)
reconciles firmware metadata from RomM, downloads selected/missing files with
progress and validates RomM's MD5 when supplied. Its Settings UI exposes Download
Missing and Distribute; this is not a blanket automatic download of every BIOS
at every launch. Built-in launch distributes already downloaded BIOS into its
private Libretro system directory. Filename/hash mappings and subdirectories
(for example `pcsx2/bios`) are concrete per-core knowledge.

External distribution copies to a writable known destination. An emulator that
imports firmware into a private database/root may still need its own import UI;
the [BIOS guide](https://github.com/rommapp/argosy-launcher/wiki/BIOS) explicitly
documents this for standalone PS2 variants and aPS3e. Broomm should distinguish
downloaded, placed, imported and verified-ready states.

The source also contains an Eden firmware installer: it validates a firmware ZIP
against `prod.keys`, copies keys, extracts NCAs into the native registered
contents directory, and creates a default account only when absent. Its direct
filesystem destination must actually be writable. This is useful format evidence,
**not native acceptance or permission to reproduce its account/publication policy**.
Broomm's agreed one ZIP plus `prod.keys` and `title.keys`, existing console
identity, staged ownership and readback rules remain in force.

## Proposed Broomm direction

Two independent changes should be evaluated separately:

1. **Improve external-app setup within the current design.** Detect an installed
   package, inspect known accessible locations and live configuration, bind one
   verified save connection across profiles, and ask only for the specific
   missing permission/location/settings. Replace the unconditional manual gate
   with discovery, visible readiness and a targeted repair action. A one-time
   shared-storage permission can help discovery; a provider grant is still needed
   where appropriate. Preserve standalone progress and Broomm's journaled swaps.
2. **Decide whether to add a built-in core frontend.** This is how Argosy avoids
   external core installation and save-path problems for its core-based systems.
   Start any approved prototype with one simple cartridge core and real save
   round trips before expanding to hardware-rendered cores.

| Option | Benefit | Cost / unresolved work |
| --- | --- | --- |
| Keep external apps, add discovery/config inspection | Fits the agreed Android app model; reuses current Dart progress adapters; smaller runtime change. | Cannot promise universal access or silent private configuration. External RetroArch core installation still needs a proven cooperating route. |
| Add a LibretroDroid-based frontend | Owns core/save/system paths; on-demand cores; direct exit/save hooks; closest to Argosy's built-in experience. | New native rendering/audio/input/lifecycle surface, ABI delivery and crash containment. Flutter needs a native view/activity/bridge; it is not a Dart package swap. Argosy's repository declares GPLv3; fork, native dependencies and each core need provenance/license review before reuse/distribution. |
| Implement a new Libretro frontend around Flutter/FFI | Own the integration and retain Dart domain workflows. | Reimplements substantial renderer/audio/input/core-environment work already present upstream; significantly higher integration and maintenance burden. |

The second option should be treated as an explicit architecture decision: the
current product specifies external Android emulator apps. No engine, library,
root mechanism or runtime dependency is selected by this research. Keep ordinary
sync/setup decisions in Dart whichever rendering adapter is eventually chosen.
Core install/update choices must preserve Broomm's user-initiated emulator-update
policy, platform/ABI compatibility and exact-build state boundaries; do not adopt
uncontrolled nightly upgrades simply because Argosy uses a nightly endpoint.

For either route, readiness needs native Android tests: a clean installation,
pre-existing emulator, denied/revoked grants, offline launch, restart after
interruption, two Broomm accounts, actual in-game save/load and RomM round trips.
Core acquisition must also test ABI mismatch, failure/cancellation and no-network
first launch. No such native execution was performed for this audit.

The current [macOS package](../build/releases/Broomm-macOS-android-saves.zip) is
unchanged; this research introduces no application build or new APK. Research
source can be removed from `.tool-cache/research/argosy-android-flow/` without
affecting application or user data.

Documentation checks: pinned-source inventory generated with the project's
SDK-only digest code; relative file targets and whitespace checked. The unchanged
20,613,929-byte macOS archive retains SHA-256
`f17604056100722f17096b6e62d4f25d321cac19f5a76e2d16da44409954a3a6`;
`unzip -t` and the existing source app's deep/strict/all-architecture signature
verification pass. Application tests were not rerun for this documentation-only
change.
