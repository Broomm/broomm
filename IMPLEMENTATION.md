# Implementation plan

Windows updater test supervision (2026-10-30): the native PowerShell cancellation
fixture runs in its own mandatory Windows step, separate from parallel Flutter
tests, with unchanged eight-second deadlines. It reports early process exit,
bounded output and the installer log instead of only a missing checkpoint.
Portable regressions cover early exit and live-writer readiness. No application
updater behavior changes; native Windows execution is checked by CI. See
[reproduction and scope](docs/application-updates.md#windows-native-cancellation-fixture-2026-10-30).

Installed Switch launch correction (2026-10-30): the package-selection preflight
now reads the installed receipt and existing native package checkpoint instead
of requiring the lightweight saved game metadata to contain a downloadable RomM
manifest. Existing generations remain usable by both profiles without a remote
manifest request. A missing generation resolves real remote file identities
before its first import; failed, incomplete or mismatched responses retain the
installation. Legacy update/DLC folders are excluded from base-game selection
even without API category fields. See [reproduction and verification](docs/switch-installed-launch.md).

Updater preparation correction (2026-10-29): the production 0.1.2 → 0.1.3
failure is reproduced with a progress callback holding a native receive port.
Both worker closures unintentionally captured the UI callback. Dedicated
path-only worker scopes now keep UI/logging resources on their owning isolate;
checksums, extraction, locks, cancellation and publication checks remain intact.
Unexpected failures identify their phase and log an error type/OS code without
stringifying sensitive callback graphs or HTTP URLs. All **424 Flutter tests**
pass (422 ordinary plus two separately scheduled full-size save cases), including
three new regressions and native macOS replacement/rollback fixtures. Real public
0.1.3 preparation passes with the original failing callback and in compiled
ARM64 and Intel/Rosetta runtimes. The compiled probes stop before production
replacement. Existing broken updaters need one manual app replacement; the local
0.1.3 recovery build enables later GitHub updates. Other native hosts and the
owner's production upgrade remain separate acceptance. See
[recovery, evidence and commands](docs/application-updates.md#update-preparation-correction-2026-10-29).

Automatic core delivery and running macOS icon (2026-10-27): all twelve frontends and all fifteen RetroArch cores now have bundled HTTPS recipes; normal setup needs no companion pack or JSON import. Seven available official Libretro core builds replace the old offline dependencies, with retained legacy fingerprints and explicit-setup-only selection. Ordinary saves remain shared across core upgrades; incompatible states have physically separate frontend/core-hash folders and exact-build cloud identities. The 55-case targeted suite, native fresh setup/restart and ABI checks, thirteen game/state sessions, BIOS-core save checks and four additional cartridge/arcade native-data round trips pass. All ten macOS native app tests pass, including restoring the bundled infinity icon after a placeholder and retaining the current icon when its resource is absent. Startup assigns the icon directly; the owner's original Dock/cache trigger remains unproven and actual Dock appearance needs owner confirmation. See [walkthrough, versions and scoped evidence](docs/retroarch-public-cores.md).

RetroArch release adoption (2026-10-27): the bundled macOS ARM64 recipe now downloads Broomm/retroarch v0.1.0 with its exact ZIP, executable, SDL3 and complete 29-file inventory. All five published desktop artifacts/manifests were verified; this does not expand the existing managed core/bridge host boundary. Previous selected frontends and old setup packs retain their exact identities, profile paths and state naming until explicit setup. The release uses private native state paths after a real `-S` regression was diagnosed and corrected. The 52-case targeted suite, native public delivery/restart, thirteen supplied game/state checks, four BIOS-based platform routes (Lynx, Saturn, 3DO and Dreamcast) and SNES pairing/pause/remap pass, exercising all fifteen current cores. Seven remaining offline cores have an updated companion pack; eight retain direct tested downloads. The fresh macOS app/archive and extracted signatures pass. See [current distribution and host limits](docs/retroarch-distribution.md) and [exact fingerprints, retained failures and artifacts](docs/retroarch-release-adoption.json).

Launch/quit recovery (2026-10-27): repeated whole-ROM hashing has been removed from Ryubing/Eden save discovery and launch. Native title observations bind to the installed publication's server/ROM/file identity and file metadata; old checksum records and saves stay intact. The owner's 14.64 GB Smash installation now takes 11.113 ms for read-only receipt/identity lookup, with no ROM payload read. Explicit save actions cancel/drain idle sync instead of refusing it as a game. Launch cancellation includes cold-start children and retains the lease until writer exit. A pinned Ryubing early-quit race now waits for confirmed native pause before close. Quit acknowledges immediately, displays shutdown phases and offers an explicit exit if work stalls; macOS also has a no-Dart-response fallback and verified surviving-writer recovery. **405 Flutter tests**, **8 native macOS XCTest checks**, the real Ryubing initialize/reopen/cancel fixture and AppKit process-identity checks pass. The current macOS ZIP passes archive and extracted signature checks. Owner gameplay and Linux/Windows/Android native recovery acceptance remain separate. See [details and retained failures](docs/session-recovery.md) and [source/build evidence](docs/session-recovery.json).

Saturn verification (2026-10-23): both owner-provided regional BIOS files now pass checksum verification and real RomM automatic provisioning/reuse in a disposable profile. The Legend of Oasis boots through native pairing, pause/live remap and normal exit. Internal backup RAM, backup cartridge and console settings pass cloud-fixture export/upload-readback/restore; native state creation/loading and exact-build snapshot restore pass. The [Saturn record](docs/saturn-verification.md) separates this macOS automated evidence from physical gameplay, cross-device and other-host acceptance. No application or bridge change was needed. The current matrix now has 17 of 18 additional RetroArch routes natively checked, with 14 ordinary native-data round trips plus the separately seeded 32X case; Jaguar CD remains owner-deferred. Earlier dated counts below are historical.

Pairing-format correction (2026-10-23): the main RomM client now accepts the actual eight-character alphanumeric API key pairing code, including lowercase/hyphenated input, and the onboarding hint uses the correct terminology. The tagged 5.4.0 generator/exchange supersedes the prose documentation's numeric example. Three new HTTP regression cases cover accepted forms, malformed input without network effects and rejected/expired exchange without retry. The HTTP/onboarding suites pass 22 tests and targeted analysis passes; [exact evidence](docs/pairing-code-format.json) records the source hashes and remaining native acceptance. The matching Switch keyboard/build/deployment evidence stays in the sibling companion; its version 0.2.2 was transferred with hash readback. No main desktop release binary was rebuilt for this correction.


Current expansion (2026-10-23): the [colored platform matrix](docs/platform-support-matrix.md) records **25 launch/ordinary-save adapters**, including 18 new RetroArch routes/14 pinned cores, plus Wii and Switch native package workflows and missing Switch firmware provisioning. Thirteen new cartridge/arcade routes have native game/state checks and six have native ordinary-save export/import checks; five optical/BIOS routes still need native media validation. PS1/PS2/PSP remain pending; PS4 has no built-in emulator while retaining ordinary browsing/downloads. The runtime pack remains macOS arm64. Earlier dated milestone counts below are historical. See [the expansion record](docs/retroarch-wii-switch.md) for exact verification and remaining scope.

The native Nintendo Switch companion has its own [implementation record](../broomm-nsw/IMPLEMENTATION.md), source, evidence and Devbox environment in the sibling `broomm-nsw` project. This document tracks the main Broomm application and shared integrations, including Switch emulation; console-specific implementation status belongs to the companion.

Latest inventory: the authenticated [platform matrix](docs/platform-support-matrix.md) records 29 platforms / 7,660 ROM records, seven implemented macOS platform integrations, 22 missing/research integrations and the package/cloud-save/state gaps. It proposes candidates without installing them. The [RPCS3 installer exit correction](docs/rpcs3-installer-exit.md) prevents the known post-install SIGABRT notification through the child-only native guard while preserving strict completion/output verification and real failures. Both real ARM/Intel package imports, guarded firmware import/reuse, five native guard checks and all 257 Flutter tests pass; final build evidence is in its JSON.

Current follow-up: [automatic first sync and PS3 recovery](docs/cloud-initialization-and-ps3-recovery.md) initializes installed-game cloud history automatically, exposes a locked download checkpoint read-only with Refresh, and replaces PS3 whole-directory ownership with journaled package-file ownership. Existing game-created data and replaced originals survive installation/removal. All 257 Flutter tests and two copied-data/queue integration checks pass. Source/release fingerprints and remaining native/owner checks are recorded there and in its JSON. The preceding [downloads and status](docs/downloads-and-status.md) milestone retains its scoped 247-test/native-loading evidence. L2 Shift / R2 Enter and the cancellation of window capture remain unchanged. Earlier milestones below are historical.

Updated 2026-10-22. The application implements queued RomM downloads, persistent Home entries, managed setup for six emulator engines with seven pinned macOS choices (including melonDS and alternate Intel RPCS3 through Rosetta), and Home → loading → controller pairing → gameplay. The [library/progress follow-up](docs/library-and-progress-followup.md) adds early artwork selection, a Downloads screen, the docked keyboard, PS3 firmware acquisition and PS3 add-on reconciliation. The current [save-history/ISO correction](docs/slotted-saves-and-ps3-iso.md) appends native timestamped versions in `BROOMM`, preserves earlier saves, keeps explicit imports/backups and supports encrypted PS3 ISO/adjacent-key boot. Guarded restore, offline retries and conflicts remain. Ordinary progress adapters cover SNES, GameCube, Wii, 3DS, PS3, DS and Switch; individual format/native-host limits remain explicit. Authenticated DS save transfer/readback is verified; real PS3 PKG import, physical-controller and cross-device gameplay acceptance remain pending. See [README.md](README.md) for testing steps and the current Mac build.

Read [PROJECT.md](PROJECT.md) for requirements, the [decision record](docs/decisions.md) for settled choices, and [architecture](docs/architecture.md) for the proposed implementation. Remaining implementation details live in [open questions](docs/open-questions.md); the initial questionnaire has been answered.

## RomM application slice

The default entry point now opens server setup, server-scoped profiles, a three-app console Home, Broomm settings and the RomM Game Store. Settings persist reduced motion, artwork visibility and page size. RomM 5.4.0 integration includes server validation, password OAuth with read scopes and managed-save write access (read-only roles can still browse), client token/pair-code login, account identity, platforms, paginated/searchable ROMs, details and authenticated same-server artwork. Reusable refresh/client tokens are saved per server/account through direct native secure-store adapters; passwords and OAuth access tokens are never persisted. Explicit profile selection restores authentication, switching retains it, and device sign-out removes it. Native macOS evidence and the unverified other-host adapters are distinguished in [the follow-up record](docs/remembered-signins-and-platform-settings.md).

Server/profile metadata uses locked atomic publication and readback. Context/query generations reject stale requests after searching or signing out. The Store uses real server data and reports unavailable catalogues. Verified downloads and receipts publish together and appear on Home, shared per saved server across eligible profiles. Home plays the supported formats through managed emulator copies and profile-private data. Emulator Settings imports the tested local builds through setup JSON. Named collection filters remain pending; the managed-save slice is recorded below; no Go code was imported.

Controller navigation uses geometric Flutter focus, native macOS GameController events, Dart Linux evdev/Windows XInput adapters and Android gamepad interop. Pointer/touch activates inline editing; keyboard focus requires Enter to edit and Escape returns to navigation on the same field. Controller activation opens the virtual keyboard. Emulator Settings uses spatial arrows/controller directions and ordered Tab traversal through expanded confirmation controls. Scroll reveal includes full cards, labels and view edges, and newer focus stops obsolete scroll animations. Mouse hover does not take focus. Only macOS compilation/native tests and Flutter action-channel/layout tests are verified here; Linux input permissions, Steam/gamescope, Windows and Android behavior require native execution. The previous local-ROM controller lab remains reachable through Broomm settings, or the explicit prototype run command. See [the slice walkthrough and scoped evidence](docs/romm-application.md) and [download/input details](docs/romm-downloads-and-input.md).

## Current evidence

The Intel RPCS3 follow-up adds a separate macOS PS3 choice/default, shared profile-owned PS3 data, isolated Intel compilation caches and universal C bridges. **234 Flutter tests pass** and static analysis is clean. Two real Rosetta launches of the supplied encrypted PS3 ISO pass injected pairing, pause/resume, live remap and normal close (312.316 s fresh cache; 183.080 s repeated launch). This is not a compatibility/performance comparison. Firmware and ARM-regression checks and final release evidence are recorded in [the scoped follow-up](docs/rpcs3-intel.md). [Flutter capture-library research](docs/flutter-window-capture.md) identifies a common WebRTC API plus native runtime, process-identity and gamescope limitations; no capture dependency or preview is implemented. Physical gameplay and other native hosts remain separate acceptance.

Latest keyboard/cache follow-up: **231 Flutter tests pass**, plus **14 focused widget/render checks** for the final shortcut badges. Two native macOS GameController snapshot tests pass for shortcut button callbacks and multi-controller held Shift. A separate native two-boot RPCS3 check preserves 204 PPU objects and 155 shader files on each launch, while measuring about 187 seconds to readiness; a stack sample and pinned renderer source identify repeated MoltenVK pipeline conversion. No graphics/cache setting or emulator binary was changed. Live loading-window capture remains a researched proposal with platform-specific permission/compositor requirements. See [the follow-up](docs/loading-preview-and-keyboard.md) and its JSON for scoped evidence and release metadata. Physical controller and other native-host acceptance remain pending.

The preceding save-history/ISO milestone passed **228 Flutter tests** with clean static analysis. Native macOS checks validated encrypted RPCS3 ISO/key boot through pause/pair/resume/exit, copied native save exports including Pokémon Ranger, real RetroArch writer/finalization, and Switch committed save/ZIP round trips. Authenticated RomM 5.4 DS transfer created a timestamped raw 262,144-byte `.sav` in BROOMM and verified readback without changing previous assets. Its release evidence is recorded in [the correction record](docs/slotted-saves-and-ps3-iso.md) and its JSON. Real PS3 PKG import, physical-controller play, cross-device gameplay and other native hosts remain unverified.

The preceding library/progress milestone passed 217 Flutter tests, offscreen desktop/compact renders and native macOS checks for melonDS, the six existing emulator session flows, RPCS3 firmware import/reuse, installer/orphan writer exclusion and Switch restore/native consumption. Its release/signature evidence remains in [the scoped historical record](docs/library-and-progress-followup.md). Entries below describe their own milestones.

| Item | Status |
| --- | --- |
| Product specification and general engineering guidance | Updated with confirmed owner decisions |
| PGCS reference audit | Source inspection only; no PGCS application-code import or Go helper |
| Teddy server/profile flow | Source and test inspection documented; no Teddy runtime/visual check |
| Initial emulator inventory | Thirteen concrete executable adapters and the supplied RetroArch core set identified |
| RomM baseline | 5.4.0 selected and confirmed by the public instance schema retrieved through the supplied HTTP proxy; authenticated DS native save upload/readback is now verified separately |
| Controller injection / desktop overlays | C bridge built and exercised in five private macOS emulator copies with supplied ROMs; see the [measured findings](docs/research/injection-validation.md). Renderer/fullscreen/physical-controller and Linux/Steam acceptance remain separate |
| Flutter app / Devbox bootstrap | Flutter 3.47.0/Dart 3.13.0 and pub lockfile; onboarding, Home/Store downloads, preferences and explicit text editing. Current checks are recorded in the [sign-in/platform follow-up](docs/remembered-signins-and-platform-settings.md); the earlier managed milestone passed 94 tests and all six native ROM sessions. The local controller lab remains; other native hosts remain pending |
| Managed setup and Home launch | Twelve pinned macOS choices and all fifteen selected RetroArch cores download through bundled HTTPS recipes, including RetroArch from Broomm/retroarch v0.1.0 and seven refreshed official cores. Normal setup requires no external pack or import. Prior recognized frontend/core installations remain usable until explicit setup. Ordinary saves are retained and incompatible states are physically isolated. Private extraction, cancellation, verified publication/reuse and inline review work without a checkout root. Other native desktop core/bridge packages, arbitrary newer builds and system-executable selection remain pending; see [delivery evidence](docs/managed-setup-downloads.md) |
| Host coverage | macOS/Linux first; Windows later; Android uses simple external-app handoff |
| Remembered sign-ins and platform settings | Per-profile secure refresh/client credentials, Enter/Escape editing, all-server-platform sections, default routing, inline setup and shared managed uninstall with retained profile data; see [scoped evidence](docs/remembered-signins-and-platform-settings.md) |
| Keyboard/controller navigation and motion | Animated full-card/field reveal, first/last-row scroll edges, spatial emulator actions with ordered Tab traversal, Home/header return paths, indexed lazy catalogue traversal, retained modal focus, scrollable descriptions and compact session screens, reduced motion and held-key activation guards; see [current checks and owner walkthrough](docs/navigation-and-motion.md) |

The 2026-10-22 cloud-save slice passed 201 checks in the final complete Dart/Flutter plus two native-check run. Separate targeted checks cover save conflict ancestry, state provenance/core identity and controller routing during pre-launch/finalization. macOS native file round trips and a real RetroArch writer/finalization check use isolated data and a fixture server; owner-authenticated transfers and cross-device gameplay remain separate acceptance. See [the machine-readable source hashes, commands and release evidence](docs/cloud-saves.json).

## Owner-requested controller prototype

This bounded prototype deliberately precedes server/Home/Store implementation. Flutter provides a static ROM library, player cards, joining/leaving/reordering, both face-button swaps and the same pairing widget before and during play. C bridges expose four virtual logical ports inside the selected emulator's existing SDL runtime, sample mapped physical gamepads there, neutralize logical input during menus, and detect R3+Select and assigned-device removal. A released-button barrier avoids forwarding the confirmation press into gameplay. Reconnecting devices must join again with their new session identity.

Dart owns assignments, concrete emulator configuration, private process launch and native acknowledgements. A parent coordinator lock and a native emulator-owned writer lock enforce one game, including after launcher exit. Each emulator gets persistent prototype-owned data; the original emulator installations and ROMs are write-protected. The app bundles both native dylibs. The fixture provisioning step is explicit, not an automatic emulator updater or setup.json implementation. Android's external-app-only requirement is preserved: no native Android bridge is introduced.

The overlay is an external Flutter window aligned over the game, using macOS window presentation. The owner clarified that Steam → Broomm → emulator in gamescope-based Game Mode is a central acceptance path. The [preliminary window/compositor review](docs/research/controllers-and-overlays.md#steam-big-picture-and-gamescope-preliminary-window-review) finds ordinary window stacking insufficient as an assumption; a gamescope-aware surface or drawing inside the game presentation needs a native experiment. No Linux/Steam acceptance is claimed. It is not proof of GPU interception or acceptance in all fullscreen Spaces. Physical pads, Steam, handhelds, real port gameplay, rumble, motion feel/calibration, Linux and later hosts remain separate verification. The native smoke suite uses real supplied games with in-process synthetic SDL sources; see its machine-readable record and [walkthrough](README.md). Do not conflate that with owner-performed input/visual verification.

Initial prototype testing caught and corrected premature Azahar pause acknowledgement before EmuThread creation, Ryubing title readiness assumptions, virtual-trigger range conversion, stale asynchronous bridge reads after exit, card layout overflow, and shutdown of paused emulators. Failed synthetic fixture shutdowns were cleaned up separately; the interactive supervisor has no force-kill path. A supported native pause acknowledgement is required before play/overlay confirmation. The final macOS suite passes all six supplied ROMs, including held-confirmation neutrality, child lock ownership and clean exits; eight Dart/Flutter tests pass. Exact source/build fingerprints and scoped evidence are in [prototype validation](docs/research/prototype-validation.json).

The owner's subsequent physical/visual testing found missing decorations, resizing, one Broomm renderer crash, RetroArch relaunch input failure, Switch pause failure, and four phantom GameCube controllers. Those observations exposed gaps in the original synthetic suite. The [reliability follow-up](docs/research/prototype-reliability.md) records the fixes and [new regression evidence](docs/research/prototype-regressions.json) separately. Window presentation preserves decorations/user frame; macOS uses Skia Metal to avoid the observed pinned-SDK Impeller crash. Session lifetime checks protect return from normal/error exit and stale asynchronous work. Command publication is serialized and a lost bridge invalidates pause knowledge while retaining its writer. RetroArch logical player indices and Dolphin console socket counts are now verified at the emulator boundary. Ryubing foreground activation and a scoped SDL2 GCController backend workaround address resume and a diagnosed relaunch deadlock with the attached Switch Pro controllers. That reliability milestone passed 16 Dart/Flutter tests; two native window tests pass, including 30 hide/show cycles. All six ROMs pass the updated foreground-handoff suite, and the controlled bridge outage recovers while retaining the emulator-owned writer lock. This does not complete physical gameplay, fullscreen or Steam/Linux acceptance.

The subsequent pairing redesign adds large vector controller testers, six-axis snapshots, family-based initial face orientation, L1+R1 join/Wii type, independent L3+R1 face switching, one-second Start/Select holds, progressive player cards and controller-driven scrolling. Face changes now swap both pairs. Wii uses emulated Wii remotes rather than Brawl's GameCube compatibility: Dart publishes private mode configuration; the pinned C bridge reloads Dolphin while paused and verifies selected extension/orientation before releasing input. Native testing covers all eight variants and mixed Nunchuk/Classic players in one Brawl session. An intermittent Azahar startup lock inversion was sampled and corrected by deferring only its controller event watchers, with bounded continuous-input coalescing and a deterministic nested-callback check. Protocol 3 prevents an old bridge from being accepted by the new app. Current automated Flutter checks pass 42 tests; see [pairing behavior and measured evidence](docs/research/controller-pairing-testers.md). Physical gamepad feel, actual Classic game actions, Linux/Steam and later hosts remain acceptance work.

The [responsiveness/loading follow-up](docs/research/pairing-responsiveness.md) adds a distinct initial loading state, protocol 4 input-discovery readiness and an Azahar loading-screen boundary before pairing appears. Motion bars hide when gyro is inactive. Emulator output decoding/rotation moves to a bounded in-process logging isolate; mapped-value repaint checks and cached native executable symbols reduce measured work. The current analyzer and 49 Flutter tests pass. Controlled debug measurements reduce four-card build p95 from about 23 to 12 ms and a 2 MiB log-burst event-loop stall from about 362 to 24 ms; higher observed RSS and unverified owner responsiveness remain explicit. See that follow-up for exact native results and source fingerprints; earlier milestones above retain their historical counts.

## Stage 0 — Establish the Dart/Flutter environment

1. Create a pinned Devbox environment, Flutter project, package lockfile and platform-aware doctor/build/check scripts. Project dependencies are managed; pre-provisioned Xcode/Apple SDK and Windows SDK/C++ hosts are approved. No OS package installation.
2. Keep provisioning, profile/server management, session coordination and synchronization in Dart. PGCS supplies researched behavior and emulator knowledge only. Optional C injection bridges ship precompiled after validation; do not add Go code or a helper service.
3. Establish macOS/Linux native build/check jobs first. Keep later Windows/Android targets visible without treating their missing hands-on acceptance as an unresolved priority decision.
4. Use the [captured RomM 5.4.0 instance schema](docs/reference/README.md) and capture sanitized authenticated contract fixtures when implementing the client. Public schema retrieval is complete; HTTPS transport and authenticated runtime behavior remain to be verified.

Acceptance: a fresh project environment resolves reproducibly; format/analyze/tests and available native builds run through documented scripts; packaged native dependencies load. Record exact OS/CPU/SDK versions and unavailable checks. New package choices still require concrete tradeoff review; Flutter/Dart and the no-Go boundary are already selected.

## Stage 1 — Server-first profiles and the controller-first shell

Implement [server → known profiles → Home](docs/profiles-and-servers.md), following Teddy's explicit activation, filtered profile tiles and focus behavior. Store servers independently of profiles, keep one active server/account, and reset clients/navigation safely during switching. Build Home with Broomm settings, Game Store and Emulator Settings before game installation, following the owner's updated three-app requirement.

Acceptance: two saved servers with overlapping account IDs/names stay separate; servers with no profiles survive restart; startup does not authenticate before explicit profile choice; busy/error/modal focus paths work with controller, keyboard and pointer/touch. Switches preserve queued progress and reject stale results. Fixture catalogue data must be clearly identified.

## Stage 2 — RomM catalogue and shared game installation

Implemented first download slice: authenticated per-file streaming, portable path checks, size/raw CRC verification, private staging, OS-locked publication, Home records, permissions and cancellation. Archives remain raw; decompressed hashes are not container checksums. Retries restart transfers. Stage 3 now launches supported installed formats; [the artwork follow-up](docs/home-artwork-and-deletion.md) adds chosen local artwork and confirmed game deletion with retained progress. Owner-server transfers, native Linux/Windows/Android execution, full offline activation and repair remain pending; the managed-save slice below adds progress synchronization. See [download evidence](docs/romm-downloads-and-input.md).

The 3DS add-on follow-up implements repair for its own tracked native title content; general base-game repair remains pending. A failed add-on import leaves the completed base installation available, with a visible error and manual retry.

Implement the selected 5.4.0 auth/account/capability contract, catalogue pagination/search/details and content download. Install shared ROM/game payloads transactionally, with progress/cancel/retry/receipts and committed Home entries. Add a second account and server early to prove private progress and correct ownership.

Acceptance: browse a real authorized catalogue; install a complete game; cancel or interrupt without exposing a playable partial entry; reuse shared payload for another eligible profile without sharing its saves/states. Network failures retain the installed library. Cover traversal/collisions, partial HTTP responses, integrity and disk-full errors.

## Stage 3 — Managed setup and one complete desktop game session

**2026-10-27 delivery follow-up:** bundled schema-2 recipes no longer depend on
`BROOMM_PROJECT_ROOT`. All twelve pinned macOS choices download reviewed HTTPS
archives. Dolphin's official 2609 DMG now reproduces all 2,667 files and nine
links through a fixed Dart signing recipe. An archived Ryubing 1.3.3 ZIP matches
all 16 tested files; only its empty root Finder icon marker is ignored. RetroArch
uses the published Broomm SDL3 frontend and all fifteen cores now download;
seven have newly validated official builds and eight retain their library hashes.
Normal setup requires no companion pack or import. First installs,
private archive extraction, checksum/inventory checks, bounded cancellation,
receipt publication and verified reuse work through the existing inline cards.
Version-1 local imports remain supported; capture tools and native gameplay
fixtures now explicitly use `tool/setup-development.json`.

The earlier delivery milestone passed its analyzer and **392 Flutter tests**.
Two full fresh native installs passed for its **12 choices and 14 additional cores**
with `project: null`. Current core-refresh checks are recorded separately in
[the public-core evidence](docs/retroarch-public-cores.json).
A subsequent GitHub Azahar stream disconnect retained four completed choices and
discarded the partial transfer; safe diagnostic regressions were added, and the
same fixture explicitly resumed to all 12 choices/14 cores with default-manifest
reuse passing. The source-replacement check then freshly downloaded Dolphin,
Ryubing and eight unchanged cores, installed all 14 additional cores, accepted
the earlier complete pack and verified restart/reuse after removing its private
source directory. It passed in 47 seconds with exact full inventories. Logs
preserve the original redacted failure. These checks verify
delivery and existing binary identities, rather than new gameplay/input or other
host acceptance. See [recipes, source evidence and limitations](docs/managed-setup-downloads.md)
and [machine-readable results](docs/managed-setup-downloads.json).

The fresh [macOS build](build/releases/Broomm-macOS-setup-fixes.zip) is
**20,346,293 bytes**, SHA-256
`1233d40d8883bb5c39b1cdb29c9417eb53692ae40cb619908861322f0ca39934`.
The application and three existing bridges contain ARM64/x86-64; ZIP integrity,
the bundled manifest hash and strict/deep signatures pass before and after fresh
extraction. This ad-hoc local development build uses the normal
`~/Library/Application Support/Broomm` folder, with self-updates disabled. The
[companion setup pack](build/releases/Broomm-setup-macOS-arm64.zip) is
**148,651,975 bytes**, SHA-256
`80712dce859de91ea7bf7c05b22931e1d734c81502c3d4ff87116e8388737654`.
It contains no firmware, keys, games, profile settings or progress. README.md
documents first setup, explicit effects, output folders and cleanup. No owner
data migration, OS dependency installation or GitHub publication was performed.

Implement the [setup JSON workflow](docs/emulator-support.md#setup-json-contract) in Dart. Generate the install/update plan and execute only when the user starts it. All configuration is Broomm-local, even for a selected system executable. No automatic updates or mutation of external installations.

Take one macOS/Linux combination from the selected roster through provisioning/resources, private configuration, controller assignment, app-wide single-game locking, process supervision and save/state manifests. The first slice is a sequencing choice within the full initial roster, not a reduction of scope. Expand one verified integration at a time.

Acceptance:

- Owner launches a game using the expected player port; a second launch from the same or another Broomm process is refused while it runs.
- Two profiles use the same ROM bytes but separate saves/states. External/default-user emulator settings and files remain untouched.
- A new setup file updates only the requested managed artifacts after user initiation; failure retains the prior installation and settings. Manual executable changes are detected without silently reverting them.
- Confirmed game exit, failed launch and cancellation all preserve local progress and correct session ownership. A wrapper exiting is not mistaken for the real writer stopping.

## Stage 4 — Offline recovery and cross-device progress

The first [cloud-save slice](docs/cloud-saves.md) implements acknowledged baseline B, local snapshot L and current managed remote R under the originating server/account. Only the exact `broomm`/`Broomm` save without a slot is an automatic target. Offline progress is checkpointed locally; R = B permits upload of L, divergent changes require a choice, equal contents acknowledge without another upload, and a remote-only descendant is restored before play. Commit ancestry detects competing Broomm writers after a last-writer-wins server race. This does not make RomM 5.4's upload endpoint an atomic compare-and-swap. Explicit source imports and independent named backups are available from Home Options. Native gameplay/cross-host and authenticated server acceptance below remain outstanding; unit/HTTP and isolated file round trips do not establish them.

Acceptance: save round trip between macOS/Linux devices in both directions; matched-build state round trip; incompatible state retention; offline progress with unchanged remote uploads automatically; remote progress from another device creates an explicit conflict. Cover lost upload acknowledgement, a remote write after comparison, revoked login, disk-full, damaged local recovery and switching away with a queued upload. Inactive servers/accounts remain paused until selected and never borrow the active account's token.

## Stage 5 — Tight desktop input and settings integration

The owner prioritized RetroArch, Dolphin, RPCS3, Azahar and Ryubing. The [first native experiment](docs/research/injection-validation.md) hooks each tested macOS build's own SDL dispatch table, observes real emulator calls, and exercises live routing/remapping using two in-process virtual controllers. No PGCS bridge or Go application code is imported. Continue with physical devices, Steam/Linux, reversed order, duplicate models and topology changes before treating assignment as production support. PCSX2/ARMSX2 and the remaining roster follow their own verified adapters.

Acceptance: real gameplay verifies player assignment for direct and Steam/Linux handoff, handheld plus external devices, and relevant X11/Wayland cases. Missing/incompatible bridges cannot falsely confirm assignment. PGCS's existing two-player bridge does not establish four-player support.

For the in-game menu, prefer C injection/interposition and supported runtime control paths over emulator changes/forks. Prove one renderer/host tuple, capture/neutralize input, and apply/read back one actual setting. Broomm records per-setting live versus restart-required behavior and warns only for the latter. A native UI fallback is useful where necessary but does not replace the unified-menu goal.

Acceptance: menu input never also controls gameplay; focus/fullscreen/renderer recreation and Steam overlay coexistence are checked; IPC failure has a recoverable route and preserves saves. Expand Metal/gamescope/other renderers with separate evidence. Android input injection and overlays are explicitly excluded.

## Stage 6 — Remaining roster and later host delivery

Complete the [initial emulator roster](docs/emulator-support.md), recording configuration isolation, game-save/state compatibility, input ports and restart semantics per supported macOS/Linux build. Add Windows native delivery with its own evidence.

Android uses detected installed emulator apps, or user-approved installation when absent, then the supported ROM/save/state launch/import contract. Verify content access, profile progress handoff, post-game reconciliation and a single session. Do not implement pre-launch controller assignment, native injection, overlays or desktop-style sandboxing. An app without usable save/state access needs an explicit capability limitation; do not invent compatibility.

## Later work

Computer games add native/Proton runners, user-initiated runtime provisioning, profile-specific writable prefixes and title save adapters. RetroAchievements remains deferred. Neither stage justifies speculative framework code during the emulator work.

## Verification and delivery

Update source provenance, decisions, acceptance evidence and walkthroughs with each change. Distinguish static checks, native automated execution and owner-performed gameplay/visual verification. No application test is claimed for the documentation baseline. Document checks cover local links/anchors, Markdown structure, source fingerprints and consistency with the owner's answers; external-link uptime is not exhaustively tested.

The documentation baseline and its source-reference links pass target/anchor and Markdown structure checks. The captured public JSON schema is parsed and fingerprinted. The native experiment builds through Devbox, its Dart tools pass formatting/analysis, and its five-emulator ROM suite records live input changes, pause/resume readback and native panel draw callbacks. This does not establish visual/fullscreen, physical-controller or Linux/Steam acceptance. No OS dependencies were installed and neither reference project's source/settings were modified.

The motion follow-up routes base SDL accelerometer/gyro sensors through the existing per-player ports. Dolphin, RPCS3 and Ryubing poll the routed sensors; Azahar receives sensor events through its scoped deferred watcher. Pairing cards show sensor availability, failed observations and live axes. Remote gyro pointing has an R3 recenter binding; Classic has no duplicate Remote motion. Capability and successful sampling remain distinct, so transient read failures neutralize data without removing the configuration needed for recovery. Native synthetic-motion checks passed in all four supplied motion-capable ROM fixtures; Dolphin also consumed both sensor types from the two connected physical Switch Pro controllers. This does not establish owner movement/pointing acceptance or Azahar final game HID readback. See [motion evidence and remaining scope](docs/research/controller-motion.md).

The latest control change uses L3+R1 for faces and L3+R2 for per-player gyro. Pairing changes remain pending until Apply; the playing-game chord is gated natively, then Dart pauses/applies/resumes after release. A disconnect or failed command prevents an automatic resume and returns to recoverable pairing. Acceleration remains active when gyro is disabled. Upright/Nunchuk pointer bindings select gyro when enabled/supported and relative right stick otherwise. Native Brawl testing exercises the actual Dart model and reads Dolphin raw cursor input across live off/on changes and a no-gyro source in the same process; final game IR camera output/physical feel remain owner checks. See the [current gyro evidence](docs/research/gyro-toggle.json).

## Managed setup and Home play — 2026-10-17

The Emulator Settings screen reviews version-1 setup JSON and explicitly installs the pinned local RetroArch/Snes9x, Dolphin, RPCS3, Azahar and Ryubing bundles into shared Broomm storage. It validates complete bundle inventories, internal links and hashes, stages privately, publishes receipts/selections, supports cancellation/retry and refuses manual/unrecognized replacements. Firmware/keys use explicit local resource slots. No archive downloader, arbitrary-version bridge support, system-executable picker or automatic updater is claimed.

Home and completed Store downloads offer Play for SNES, GameCube, Wii, PS3, 3DS and Switch. Entry files come from the owned download receipt rather than fixture titles. The session freezes the selected profile, acquires the same coordinator/native writer locks as setup, creates private emulator data, waits for actual native readiness, then shows the redesigned console pairing UI. Existing join/test/layout/motion/overlay/disconnection behavior is retained. Normal exit and failures return to Home after writer observation; profile changes are unavailable while playing. Local progress persists; the subsequent managed-save slice adds scoped RomM synchronization and explicit import/backup actions.

The implemented tested package set is macOS arm64. Linux/Steam/gamescope, Windows, Android handoff, other roster members and physical gameplay acceptance remain open. The overlay remains the existing external macOS Flutter window. See [the detailed record](docs/managed-emulators-and-play.md) for exact builds, commands, failure investigations and verification scope. Earlier milestone counts above are historical.

## Remembered sign-ins and platform settings — 2026-10-17

The explicit focus order described in this historical milestone now applies to Tab. The owner's subsequent scrolling/navigation report led to spatial arrows/controller traversal, whole-card/field reveal, true scroll-edge selection and cancellation of obsolete scroll animations. See the [corrections and their separate verification](docs/navigation-and-motion.md#scroll-and-direction-corrections-after-owner-testing).

Public Argosy source confirms saved per-account bearer-token restoration. Broomm now stores reusable refresh/client credentials through direct OS secure-store adapters, verifies server/account correspondence and protects refresh/publication with a stable cross-process profile lock. Switch profile retains authentication; explicit device sign-out deletes and verifies the stored credential while keeping profile metadata and progress. A storage failure preserves the current successful session and produces a visible warning. Missing/rejected and unknown/locked/offline cases remain distinct. No password or OAuth access token is persisted, no new dependency was added and no reference-project code was copied. New device-approval/QR login remains unimplemented.

Text-field navigation requires Enter to edit; Escape ends editing while retaining field focus. Pointer/touch still edits immediately, and controller activation opens the virtual keyboard. Emulator Settings lists all server platforms, shows unsupported-system messages, resolves a per-server/platform default for Play, expands setup review within its card and follows explicit focus order through expanded actions. Configured emulators offer confirmed shared removal, with retained profile settings/saves/states and ROMs. Durable pending-removal checkpoints allow cleanup to finish after interruption; the same session lease excludes live games.

Analysis and 115 Flutter tests pass, including actual card-driven fixture install/remove, held cross-process locks and malformed-default preservation. The macOS app builds; three native Keychain/window tests, separate-process Keychain restore and real SNES Home Play pass. Phone/desktop widget PNGs were inspected. Linux/Windows/Android credential adapters have source inspection only; no native builds/runtime, live owner-server sign-in or physical Steam/controller acceptance is claimed. Linux needs an existing unlocked Secret Service provider; Windows enforces the native credential blob limit. See [tradeoffs, commands, exact evidence and remaining scope](docs/remembered-signins-and-platform-settings.md).

## Home artwork and local game deletion — 2026-10-19

Mapped RomM downloads now offer sequential square-PNG and hero pickers using the mapped SGDB ID and a separate secure per-profile API key. Galleries are paged and bounded; closing a page cancels only its requests. Selection verifies image dimensions/decoding and publishes immutable local files plus an atomic record. Home uses the square tile and a top-aligned, aspect-preserving hero over 75% of its height, fading into the unchanged atmosphere. Missing/failed/skipped art retains the existing fallback and completed game. Select Artwork refreshes the RomM mapping and repeats the same flow.

Home Select opens Select Artwork/Delete, with right-click, long-press, Options and keyboard equivalents. Modal return retains the hovered title. Confirmed deletion removes only shared local game/artwork, preserving all saves/states, other games, emulator data and remote content. An external durable deletion intent survives loss of the cleanup folder's inner receipt, supports pre-rename/partial/marker-only retry and blocks play/reinstall until finished. Session and library leases exclude active writers and concurrent mutations.

Analysis and 149 Flutter tests pass; four native macOS tests pass, including independent SGDB/RomM Keychain slots. Decoded artwork is checked in inspected desktop/compact widget PNGs; real RetroArch Home Play with the supplied SNES ROM passes. The release-mode app and extracted ZIP pass signature/integrity verification. No new dependency or emulator bridge change was introduced. Live authenticated SGDB, physical input, other-host native verification and standalone/notarized distribution remain separate. See [behavior, commands, tradeoffs and exact evidence](docs/home-artwork-and-deletion.md).

## Grouped catalogue and Home refresh — 2026-10-19

Store requests use RomM 5.4's metadata grouping and retain its server totals/offsets, filters and visibility. Sibling ROM identities and tagged filenames drive a refreshed version chooser before download; single-version downloads stay direct. Cancellation, permission failure, mismatched identity and a late result after profile switching cannot select another payload. SteamGridDB artwork adds an optional third logo picker, PNG/WebP validation and atomic logo persistence alongside retained icon/hero choices. Home displays the logo with a typed-title fallback, larger icons without captions, adjacent actions and bottom-right profile/tagline controls. Timed top-left cards replace persistent notice strips and the artwork Snackbar without shifting content or taking focus.

The resize regression exposed underlying details autofocus stealing the version modal's selection. Route-aware autofocus now preserves the chooser through desktop/compact resizing; footer navigation and gameplay-return feedback also have observable widget checks. Analysis and 155 tests pass, with twelve inspected offscreen PNGs and a real supplied-SNES Home Play check. Exact sources, final commands, macOS release/archive integrity and remaining native/live-service limits are recorded in [the follow-up](docs/catalogue-and-home-refresh.md). No dependency, native adapter, emulator bridge or save/sync workflow changed.

## 3DS updates and DLC — 2026-10-22

3DS downloads automatically discover and install decrypted CIA updates/DLC. Home Select adds **Download Updates and DLC**, which refreshes the authorized manifest, reuses verified existing CIA files, downloads changed packages without the base ROM and reconciles private Azahar content. Publication uses shared immutable sources/payloads and per-profile ownership/recovery journals. Repeated checks repair tracked deployed content from the verified cache; untracked files are preserved. Game deletion removes owned content/tickets across profiles and retains all progress and content still claimed by another installed ROM. Home blocks launch while that game is installing; artwork selection follows completion.

Analysis and **175 Flutter tests** pass. The supplied real Smash Bros. DLC passed import through managed **Azahar 2126.1.2**, repeat checking without transfer/import, second-profile application and all-profile uninstall with three retained progress sentinels, using isolated APFS copies. Final measured phases were 3.193 s initial import/deployment, 1.220 s repeat, 1.509 s second profile and 0.433 s removal. The macOS release app and extracted ZIP pass strict/deep signature and archive integrity verification. No new dependency or native bridge change was introduced. Live authenticated transfer, in-game DLC visibility, a real update CIA and non-macOS native verification remain separate checks. See [contracts, walkthrough and limitations](docs/3ds-updates-and-dlc.md) and [source/build evidence](docs/3ds-updates-and-dlc.json).


## RetroArch, Wii/Switch packages and firmware — 2026-10-23

The setup/resolver now installs and selects pinned core binaries for all 18 additional RA-based platforms in the server inventory. Profile/game/core-specific save directories, ZIP inner-member identities, native SRAM/RTC/VMU exports, exact core state groups and platform testers extend the existing session/cloud workflow. The SNES boundary remains separate. A native shutdown correction leaves RetroArch's save flush to its QUIT path, with sampling stopped first and quit confirmation disabled.

Wii and Switch now reconcile attached update/DLC sources, stage real native imports/scans, publish private owned content with recovery journals, and uninstall across profiles while retaining progress and shared references. WiiWare base WADs, tickets, shared NAND contents and DLC progress have explicit boundaries; system WADs are excluded. Switch missing resources use the owner's one-ZIP-plus-two-exact-key-filenames layout from the RomM firmware catalogue, with bounded extraction/checksums and no replacement of configured resources. Setup/launch and package phases remain visible. No arbitrary custom-emulator import or built-in PS4 emulator is claimed.

Native checks include all 14 core ABIs, 13 new game/pairing/pause/remap/state routes, six real ordinary-save export/import round trips, both real WiiWare/DLC fixtures, the real Pokémon Quest update and five DLC packages, fresh automatic Switch firmware/native game initialization, existing SNES launch and native writer/RPCS3 installer regressions. The supplied media and all fixture progress stay in isolated test roots; no remote save was changed. The final test/build/archive counts, hashes and artifacts are in [the machine-readable record](docs/retroarch-wii-switch.json). Five new optical/BIOS routes, in-game DLC recognition, full special peripherals, physical/cross-device and non-macOS acceptance remain outstanding.

## RetroArch save verification after owner testing — 2026-10-23

Owner reports now distinguish verified launch/state/cloud observations from failed ordinary progress. Opera's raw NVRAM export and upload readback now share a concrete native filename/version boundary. Flycast sessions force all VMUs into private per-game storage using the pinned build's real option name and override precedence; native disc-ID card names and observed state filenames are retained. Sole-game legacy cards migrate with a durable ownership record while originals remain intact; ambiguous histories and differing private data are preserved. Compressed cartridge saves now follow the frontend's observed outer-ZIP basename. Retained retries accept actual core IDs containing underscores and retain raw-save identity after a native installation is removed.

Save-capable native fixtures cover the ordinary file/sync boundaries; the 32X EEPROM sentinel is distinguished from game-created progress. NES 1943 correctly creates no ordinary save or empty upload. Stella and Beetle Lynx do not expose ordinary cartridge save RAM in the pinned builds; state transfer is checked instead. Saturn still lacks regional BIOS in RomM, and Jaguar CD native validation is deferred by the owner. The [updated matrix](docs/platform-support-matrix.md), [walkthrough](docs/retroarch-save-followup.md) and [evidence record](docs/retroarch-save-followup.json) report exact results, failures, counts and delivery. Native tests use disposable profiles and a fixture server; owner progress and remote saves are unchanged. Cross-device and other-host acceptance remains separate.

## PlayStation and PlayStation 2 — 2026-10-23

The managed pack adds DuckStation 0.1-12083-g00e299795 ARM64, ARMSX2 nightly-20261023 ARM64 and PCSX2 2.8.2 x86-64 through pre-existing Rosetta on the Apple Silicon host. Home resolves PS1/PS2 media into the same loading/pairing/session flow. New DualShock/DualShock 2 testers use the existing join, face-swap, paused menu and disconnect behavior. The independent C bridge uses each pinned emulator's own SDL3, queued native pause methods and real state acknowledgment. No emulator implementation is copied, no source patches or dependencies are added, and no system settings are changed.

Profile/game-private native whole cards participate in BROOMM timestamped save versions, explicit import/backup and existing recovery/conflict handling. Both PS2 choices share ordinary `.ps2` cards and BIOS, with separate native configuration and exact-build states. DuckStation uses `.mcd`. Multi-card native ZIPs preserve both slots; unsupported individual-game/container formats are rejected. Missing BIOS files come from the same RomM platform with checksum/format checks, visible phases and reuse. Native `-datapath` suffixes and DuckStation's private HOME are measured, rather than inferred from general Qt conventions. Rendering preferences remain intact.

Analysis and **299 Flutter tests** pass. The three-emulator native suite passes using Crash Bash and Harvest Moon: Save the Homeland: managed installation, real BIOS bytes, input readiness, joining, pause/live remap, same-process disconnect/reassignment, normal shutdown, native cards, cloud fixture upload/readback/export/restore and matching native states. Both PS2 builds also execute native state loads. DuckStation creates a native 128 KiB card; the tested PS2 cards are native blank 8 MiB cards with ECC. No completed in-game save-point or physical-controller acceptance is claimed. Both Sony console sockets currently retain their configured pad type, with unassigned input neutral; dynamic emulated unplugging remains a gap. The separate Flutter menu surface and missing non-macOS native packages remain explicit.

The existing six-game native regression also passes after the shared bridge changes. The macOS release and freshly extracted ZIP pass archive integrity and strict/deep signature checks. The [integration walkthrough](docs/playstation-support.md), [machine-readable evidence](docs/playstation-support.json) and [updated support matrix](docs/platform-support-matrix.md) retain exact builds, hashes, diagnostic failures, test scope and the new macOS release output. Saturn's earlier BIOS/native-progress prerequisite was subsequently verified in [its separate record](docs/saturn-verification.md). PS4 remains an ordinary downloadable platform without a built-in emulator. PSP was the remaining launch route at this milestone and is implemented in the following section.

## PSP and additional Switch emulator — 2026-10-23

The macOS ARM64 pack now includes official PPSSPP 1.20.4 and Eden 0.2.1. Eden is an independent Switch card/default choice after Ryubing; the upstream macOS distribution is experimental. Both use verified private configuration, the existing managed installer/no-game settings entry, native controller/pause/live-remap/disconnect interfaces and session supervision. PSP adds a single-controller handheld tester and verified ISO/CSO/PBP metadata; it needs no BIOS. Its native game-created savedata ZIPs and revision/build-compatible states participate in BROOMM history, explicit import/backup and existing conflict/recovery. Native destination/ZIP DLC installation tracks individual files and preserves new saves on uninstall; generic PSP patch execution is not claimed.

Eden uses independent console accounts, native save-directory boundaries, firmware/key paths and NAND add-on ownership. Logical ordinary Switch cloud exports remain compatible with Ryubing without copying identities or native indexes. The known installed update/DLC selection is prepared when the default changes. NSP title association and encrypted native content-ID readback are performed in Dart using the existing Apple AES primitive through FFI. Eden currently accepts one update NSP plus multiple DLC packages; ambiguous update versions are retained with an actionable error. No new runtime dependency, emulator implementation source or OS installation is introduced.

Analysis and **313 Flutter tests** pass. Native PPSSPP checks pass on N+ and Puzzle Bobble Pocket: actual core-button readback, paused live remap, disconnect/reassignment, game-created ordinary saves, state creation/loading and fixture cloud readback/export/restore. The frontend's final boot transition is verified before pairing to prevent an early native pause from being overwritten. Eden checks pass on Pokémon Quest: actual program/Npad/two-port state, paused remap, disconnect and a seeded native save-directory/cloud round trip. Six real update/DLC NSPs generate 14 validated NCAs, deploy across two profiles, repeat without transfers, uninstall with progress retained and load the update in native Eden. In-game DLC acceptance, game-created Eden saves, longer gameplay, physical input and non-macOS delivery remain separate.

The six existing native fixtures and the three-emulator Sony suite pass after the shared SDL additions. All twelve private no-game applications start and exclude competing sessions; five native writer/installer guard cases pass independently. Apple C static analysis reports no diagnostics, and the scoped PSP preference fixture passes AddressSanitizer/UndefinedBehaviorSanitizer. The final PSP fixture distinguishes actual ordinary saves from state-only BROOMM bundles; updated Quest closes normally, while an observed unpatched native guest/shutdown fault remains an experimental Eden limitation. No owner process was terminated or owner/remote progress changed.

The new macOS release ZIP is `build/releases/Broomm-macOS-arm64-psp-eden.zip` (20,001,329 bytes). Archive integrity, source/fresh-extraction strict/deep signatures and bundled setup/bridge fingerprints pass. Source/output hashes, retained failures, commands and limits are in [the evidence record](docs/psp-and-eden-support.json). The [walkthrough](docs/psp-and-eden-support.md) and [colored matrix](docs/platform-support-matrix.md) supersede older PSP-pending descriptions. The separate Flutter overlay surface and Linux/Steam/gamescope acceptance remain outstanding.

## Android external emulator audit — 2026-10-26

Android previously had sign-in and launcher input but reached desktop-only emulator setup/launch. It now has separate installed-package discovery, platform cards/defaults, official installation links, a checked APK/system-installer action and no-game app opening. Home uses concrete exported Android activities and confined read-only ROM URI grants, bypassing desktop controller pairing/injection/overlays. Discovery failures retain observations; opening an installer is followed by package readback rather than being called installation success.

PPSSPP, melonDS and Azahar have profile-specific Broomm DocumentsProvider roots and explicit in-emulator folder setup. Existing BROOMM workflows use those native files: PSP savedata/Android-build states, DS raw `.sav` and Azahar data/extdata/states. APK byte fingerprints prevent trusting a different emulator build's states. PSP native-folder/ZIP DLC and owned cleanup reuse the Dart installer. No existing external data is adopted or swept. Android sessions keep the production lease and a durable recovery marker until explicit emulator-closure confirmation; open writable descriptors block finalization. Return/resume alone is not writer-exit evidence. Interrupted/changed-build progress stays available for review.

**Android parity remains incomplete.** RetroArch, Dolphin, DuckStation, ARMSX2 and Eden still need Android save/storage adapters; DS states are missing. Android core/BIOS setup, CIA/WAD/NSP installation, Switch firmware/keys and associated external-content removal are not implemented. Their desktop installers are never called on Android. Store/download behavior remains ordinary, including PS4, but those native features are not advertised as working. Initial connected-folder sync runs before launch; background work only retries sealed progress while no Android session is pending.

Analysis is clean and **328 Flutter tests** pass, including 15 new Android boundary/workflow checks. All six Android Kotlin sources compile with the pinned Devbox Kotlin/JVM toolchain and hash-pinned Android/Flutter compile APIs. Compilation is not an APK build or runtime evidence: this host has no full Android SDK/device, and no Android emulator installation, SAF folder selection, gameplay, real save/state load or physical input was executed. No runtime plugin, emulator code or OS dependency was added. The main Flutter environment is unchanged; a separate development environment avoids the macOS license-name collision in Nix profiles. See [Android status, remaining work and sources](docs/android-emulators.md), [evidence](docs/android-emulators.json) and the README walkthrough. Native device acceptance and all red Android matrix cells remain open.

## GitHub release preparation — 2026-10-26

The owner selected Teddy's release workflow/version policy. `.github/workflows/release.yml` now defines PR checks and five package targets: macOS universal, Windows x64, Linux x64/ARM64 and Android universal. `version.txt` starts at `0.1`; the existing tag ledger automatically supplies stable patches on main and candidates on develop, without version-only source commits. Dart tooling implements planning/ownership validation, complete package/checksum/commit records and draft-first publication with upload readback. PRs do not publish or receive signing secrets; completed public releases are immutable on rerun. Both publishing branches share the queued release train.

CI uses the existing Flutter pin, locked project Linux/Android/lint Devbox environments and pre-provisioned native SDKs. Windows uses a workspace-local Flutter SDK matching the Devbox pin because Devbox has no native Windows backend. Linux uses Devbox headers/tools with the pre-provisioned Ubuntu compiler ABI, then rejects missing host dependencies and Nix runtime paths. Android uses copied private SDK components and a persistent four-secret release keystore; Gradle explicitly applies Kotlin with built-in Kotlin disabled, reads optional signing properties and pins the reviewed build tools/NDK. No OS package install, global SDK selection, new Flutter runtime plugin or emulator download is introduced. Developer Mac builds retain their old checkout behavior; `--portable` removes that checkout define from release builds.

Static analysis is clean and the complete suite passes **337 Flutter tests**, including nine release regressions. All **six macOS native host tests** pass with zero skips/failures; two existing XCTest deployment-target link warnings remain recorded. The release packaging path builds a universal app and all three universal C libraries, verifies architectures/deep signatures, then writes the ZIP/checksum/JSON. Fresh extraction also passes strict/deep signature verification and reports native version `0.1.0` / build `1001`. The local development artifact is `dist/Broomm-0.1.0-pr1.1-macos-universal.zip`, **20,010,754 bytes**, SHA-256 `ae66e5963a9856083732fa2f84b79b0916ef54f9ae362a47935f8faa2d72aa8a`. It was built from the cumulative uncommitted tree against base `4c28719`, not from a published revision.

Full Dart formatting now passes after correcting two existing test-file formatting differences. Workflow/ShellCheck validation uses a narrow, documented actionlint 1.7.12 workaround for GitHub's newer `concurrency.queue` field; the queue/cancellation values are checked independently. A real clean temporary Git checkout also exercises the version CLI without package caches. Diagnostic logs retain the sandbox socket/Nix-cache constraints and corrected validator/format findings. The root Devbox manifest/lock and pubspec lock remain unchanged.

Bash files retain LF on Windows checkouts. The tracked bootstrap Flutter crash report is removed from the current source tree after preserving an identical ignored copy; existing Git history is unchanged. New signing files, crash reports and release outputs are ignored.

**Initial local-only evidence:** the preparation above preceded the first GitHub run and did not establish hosted/native Linux, Windows or Android results. The [release walkthrough](docs/github-releases.md) explains exact branch/version behavior, prerequisites, outputs, external effects, cleanup and existing emulator acceptance limits. The platform matrix is unchanged by CI build coverage.

### First hosted CI corrections — 2026-10-26

The owner supplied six failing jobs at `b3fddece07a1198d44522c8841f5ed80482dd3b1` and confirmed a successful Android build/signing setup. Corrections address Windows native-path handling in add-on inventories and artwork cleanup, portable file copy/checksum operations, macOS-specific presentation fixtures, Windows PS2 fixture positioning and download teardown before releasing temporary storage. The native writer test builds its own private guard. The macOS frame test now chooses a screen-fitting frame with exact assertions and improved failure diagnostics; the supplied hosted log omitted its underlying assertion, so the runner-specific cause remains subject to rerun. Linux GTK/pkg-config use a coherent glibc 2.39 Nix snapshot and fail early with complete dependency/linker diagnostics.

Local validation passes **342 Flutter tests**, clean analysis, **216** formatted Dart files, workflow/ShellCheck and **six native macOS tests** after rebuilding the host and native libraries. Nix evaluation verifies distinct x64/ARM64 Linux target dependencies (GTK 3.24.43, GLib 2.80.4, glibc 2.39); it is not a Linux compile/run. Two existing XCTest SDK link warnings remain. No tests were skipped, assertion failures suppressed or timeouts increased. New Windows/Linux native verification and a complete hosted matrix remain pending. No commit, push, tag or release was made by this follow-up. See [failure details and reproduction](docs/github-releases.md#first-hosted-failures-and-corrections--2026-10-26) and [fingerprints](docs/github-ci-followup.json).

### Second hosted CI corrections — 2026-10-26

Four new logs at `208dda7dc6e3d80f697377cd01b069f48a6405b7` expose ten remaining Windows tests and a Linux Devbox bootstrap syntax error. The bare GTK flake plus output list generated an empty `gtk3.` selector; explicit `#gtk3^out,dev` now passes actual Devbox environment generation and pkg-config execution on macOS with GTK 3.24.43 and GLib/GIO 2.80.4. This corrects the previous validation gap: package metadata evaluation alone did not exercise Devbox's generated expression. No cache deletion is required by the reproduced cause.

Windows fixes compare RPCS3 profile directories as native URIs, retain Switch NSPs referenced from native metadata regardless of separators, and recognize firmware NCAs by leaf name. Ownership checks, foreign data preservation and incomplete-resource protection remain enforced. Six added regressions cover forged/wrong-account RPCS3 profiles, retained/extraneous Switch package references and both engines' incomplete firmware trees. All **348 Flutter tests**, static analysis, **216**-file format check and workflow/ShellCheck pass locally; the portable macOS debug app is rebuilt. Native Windows execution and Linux compilation still require a new hosted run. No tests are skipped and no timeouts are enlarged. This follow-up makes no commit, push, tag, release or signing change. See [details/reproduction](docs/github-releases.md#second-hosted-ci-corrections--2026-10-26) and [fingerprints](docs/github-ci-second-followup.json).

### Third hosted CI corrections — 2026-10-26

Three new logs at `cf27b39bef293bef31908e422280f1d9ad6d485c` show three remaining Windows Switch package failures and Linux x64/ARM64 linker failures. Native Switch indexes normalized path separators while publication still used raw string keys, leaving references to a renamed staging directory. Publication and retention now share file-URI identity and write native destination paths. Two additional regressions cover both indexes with mixed Windows separators, UNC paths/encoded characters and unrelated metadata; the existing package ownership/removal cases stay enabled.

The Linux link lines mix newer Pango 1.57.1 from Flutter's Nix wrapper with the selected Pango 1.52.2/GTK stack. CMake and compiler shims now restore the captured Devbox target pkg-config graph and clear competing flags/search paths after that wrapper runs. The manifest/lock expose the existing GTK graph's private development metadata from the same snapshot and preflight both dynamic/static queries. Both actual Linux target metadata graphs resolve on macOS using the host pkg-config tool; this is not Linux compilation. A native macOS GTK/GLib/GIO linkage probe exercises the production CMake boundary under poisoned inherited flags, literal paths/arguments and missing SDK selection.

All **350 Flutter tests**, clean analysis, **217**-file formatting, workflow/ShellCheck and the portable macOS debug rebuild pass. Windows execution, native Linux compiler-shim execution, full Linux builds/runtime auditing and a complete hosted matrix remain pending. The unchanged six native macOS app tests are not recounted as a new run. No test is skipped, assertion relaxed, timeout enlarged, signing secret changed or OS dependency installed. No Git commit/push/tag/release or owner-data mutation is performed. See [details/reproduction](docs/github-releases.md#third-hosted-ci-corrections--2026-10-26) and [fingerprints](docs/github-ci-third-followup.json).

### Fourth hosted CI follow-up — 2026-10-26

The logs at `988353f26a3e21f69f4ed73e66aa5987826f1cf9` have one Windows failure: the full-size PS2 engine-switching save test times out at 30 seconds, then fixture cleanup collides with a live save worker. The previous Switch failures are absent. Linux's static preflight now exposes a missing `xtst.pc` through AT-SPI. The previous closure-wide metadata query found directories Devbox did not propagate. Following only declared outputs and propagated build inputs reproduces the failure for both architectures; exposing the existing pinned XTest primary output makes both full dependency queries pass.

CI runs the two full-size card tests in a separate single-suite step on every checks host, including after an earlier check failure unless canceled. Test assertions, card sizes, checksum/readback behavior and 30-second limits stay intact. Failure-only phase timings identify the pending operation. Complete test workflows drain before temporary storage cleanup, and undrained workers retain their fixture directory. A deliberate 500 ms timeout in a private copy stays a failing test while its roughly eight-second workflow finishes before cleanup, without a secondary deletion failure. Windows resource contention remains a hypothesis; the scheduling change needs hosted verification.

Local **348 + 2 = 350 tests**, clean analysis, **217**-file formatting, workflow/ShellCheck and both restricted Linux metadata queries pass. Native Windows execution, Linux builds/runtime checks and the complete hosted matrix remain pending. Product/native sources are unchanged; no new app build or native app-test run is claimed. No test is skipped, assertion relaxed, timeout enlarged, OS dependency installed, signing changed or owner-data/Git publication effect performed. See [commands and limits](docs/github-releases.md#fourth-hosted-ci-follow-up--2026-10-26) and [fingerprints](docs/github-ci-fourth-followup.json).

### Fifth hosted Linux build correction — 2026-10-26

Both Linux logs at `4c366be55013f35dc243ddd6da9e8226ce8741be` pass dependency queries and Flutter assembly, then fail compiling `my_application.cc` because GTK's shared compiler flags omit X11's private headers. X11 is already in the SDK. The root CMake project now imports `x11`, the runner consumes `PkgConfig::X11`, and both preflight queries include it. No dependency manifest/lock change or window/backend behavior change is needed.

GTK-only flags reproduce the exact header failure against the real runner for both Linux architectures. A private object-only CMake harness uses the actual dependency/settings declarations and runner target; all three source objects compile for x64 and ARM64 with `-Wall -Werror`. ELF checks verify all six architectures, both X11 branches and the explicit libX11 link inputs. Full shared/static metadata queries and workflow/ShellCheck pass. The harness uses approved Apple Clang 21.0.0 with pinned Linux/Flutter/C++ headers and supplies compiler-work/ABI cache values only for the object-only cross check; production native compiler/link checks are unchanged.

This is cross-compilation on macOS, not Linux execution, final application linking, bundle auditing or gameplay. Those native checks and the complete hosted matrix remain pending; the new logs supply no Windows result. The unchanged Flutter suite and native macOS app tests are not recounted as new runs. No OS dependency installation, owner-data effect, test skip/timeout relaxation, signing change or Git publication is performed. See [reproduction and limits](docs/github-releases.md#fifth-hosted-linux-build-correction--2026-10-26) and [source/object evidence](docs/github-ci-fifth-followup.json).

### Sixth hosted CI follow-up — 2026-10-26

At `087aaa1889f1c9fb46e7a04fcaee070054aa8ccf`, the supplied macOS native test command succeeds; the job fails uploading its results because GitHub's artifact-storage hostname cannot resolve. This requires a job rerun, not a native test correction. The ARM64 log now confirms successful compilation/linking/bundle installation before the audit rejects Nix-resolved libepoxy. The script was checking the launcher before removing the engine's own SDK RUNPATH. Both exact locked Linux engines contain those paths.

Bundle preparation now finishes for every ELF before any dependency tree is checked. SDK paths/interpreters, missing libraries and loader errors remain failures, with per-binary diagnostics. Three native regression cases are added to both Linux build jobs: forced traversal orders with relocation/execution, missing transitive dependencies and an SDK interpreter. All fixtures stay private and clean up on exit.

Workflow/ShellCheck and shell syntax checks pass locally. Actual pinned x64/ARM64 ELF copies reproduce the old ordering failure and pass the corrected preparation/order checks through a modeled loader boundary on macOS; loader-error and SDK-interpreter failures remain visible. Source engine hashes remain unchanged. This is metadata/patch verification, not Linux execution: the new native tests, host `ldd` resolution and a complete hosted matrix await CI. Unchanged Flutter/native macOS application tests are not rerun or claimed anew. No tests are skipped, limits relaxed, OS dependencies installed, signing changed, owner data touched or Git publication performed. See [walkthrough and limits](docs/github-releases.md#sixth-hosted-ci-follow-up--2026-10-26) and [fingerprints](docs/github-ci-sixth-followup.json).

## Application updates from GitHub — 2026-10-26

The owner selected Teddy's updater as the reference. Official release builds check the public Broomm repository at startup and every six hours, with manual checks and stable/candidate channel selection in Settings. A newer complete release adds **Update Broomm** first on Home without changing the selected game's identity. Activating it starts a controller/keyboard-navigable download, checksum/build-record validation, private preparation and desktop replacement/restart. Development and PR builds stay manual. Release packaging embeds the full version/target and an installation inventory; emulator updates remain user-initiated setup imports.

The Dart workflows use existing HTTP, digest and confined archive mechanics without new runtime dependencies. OS adapters perform only exclusive directory moves/relaunch or Android package inspection/installer handoff. The updater finishes save work, checkpoints the game download queue and obtains the session lease before exit. Failed checkpointing retains the queue and its ownership for retry. Cancellation is fenced before OS handoff, a rejected exit disarms the helper, and replacement/launch failures preserve recovery evidence and attempt to restore the old bundle. Games, emulator configuration, accounts and progress remain outside the replaced installation. Android requires OS permission/confirmation and controls the final Open action; silent installation or guaranteed automatic Android relaunch is not claimed.

Local validation passes **371 ordinary + 2 full-size = 373 Flutter tests**, clean analysis, **228**-file formatting, workflow/ShellCheck and generated-helper shell checks. All **six native macOS host tests** pass with zero failures/skips; the two existing XCTest deployment-target link warnings remain. The portable macOS debug app builds, and all **seven Android Kotlin sources** compile with the pinned toolchain; the compatibility fallback emits two API deprecation warnings. Native macOS fixtures verify exclusive moves against occupied destinations and actual Launch Services replacement/relaunch, alongside independent-process locks, rollback, cancellation, queue persistence and controller navigation. A real public `v0.1.0` package (20,018,724 bytes) passes GitHub selection, checksum/build-record validation, private extraction and strict/deep signature checks without installing it or touching owner progress.

The first published release containing this code is needed before later releases can be discovered automatically; the existing public `v0.1.0` predates the updater. A real owner upgrade between two updater-enabled releases, Windows/Linux native replacement/relaunch (including gamescope), and Android device installation remain acceptance work. Native-host-specific regressions remain enabled on their corresponding CI runners. Test-fixture scheduling/teardown findings and the corrected intentional-future lint are retained in ignored diagnostics; no assertion or timeout was relaxed to obtain a pass. No OS dependency/global SDK change, signing change, commit, push, tag or release is performed. See the [walkthrough and recovery notes](docs/application-updates.md), [verification record](docs/application-updates.json) and README actions.

The requested current macOS delivery is [Broomm-macOS-application-updates.zip](build/releases/Broomm-macOS-application-updates.zip), **20,097,507 bytes**, SHA-256 `49908b5efa83ebc5499247338c78ac4763b66ded1b851a59f0b0804e69f31a05`. A fresh release-mode build and all three native bridges contain ARM64 and x86-64. ZIP integrity and source/fresh-extraction strict/deep code signatures pass. This ad-hoc-signed development package uses the checkout's existing data/setup paths, retains an explicit `0.1.0-dev` identity and contains no emulator, BIOS, ROM or progress payload. Automatic installation remains enabled only in official release builds. AGENTS.md now records the owner's standing requirement to include the current macOS build link in deliveries. Application sources are unchanged by this packaging follow-up; the preceding test results are retained rather than claimed as new runs.

## Infinity application icon — 2026-10-27

The owner selected the existing mint infinity mark for Broomm's application icon.
The pinned Flutter renderer now produces a 1024 px master, transparent mark,
seven macOS catalog sizes, nine Windows ICO sizes, a Linux window/theme PNG and
five Android legacy/foreground densities. Android 8+ adaptive and Android 13+
themed resources share the mark; generation checks every visible foreground
pixel against the 66 dp circular safe zone. These are checked-in native resources
used by every build mode, with no new renderer/plugin/runtime dependency. The
existing Material Icons glyph's license is retained and bundled on every target.

Linux loads the window icon relative to its executable rather than launch cwd.
Its bundle also carries standard hicolor/desktop-entry assets; no host desktop
registration or theme/cache changes are performed. Analysis is clean and all
229 Dart files pass formatting. The existing object-only cross-check compiles
all three actual Linux runner sources for x64 and ARM64 with `-Wall -Werror`.
This is not native Linux execution or linking. The renderer completes with the
expected PNG/ICO formats and density sizes; the first attempt retained the Nix
license copy's read-only mode, corrected only on the project-owned copy before
regeneration. No assertion, test or timeout is relaxed.

The fresh [macOS build](build/releases/Broomm-macOS-infinity-icon.zip) is
**20,306,518 bytes**, SHA-256
`ae598ba5e3fa67f96381a35ec5864a00a5e8c59031d45dd112e5af04b5d8c13b`.
The application and three bridges contain ARM64 and x86-64; ZIP integrity and
strict/deep signatures pass before and after fresh extraction. The packaged
ICNS and CoreUI catalog retain their hashes, both native icon metadata keys
name AppIcon, and the compiled catalog includes every source size. The extracted
256 px ICNS image was visually inspected through the image-view tool; no
computer-control tools or owner app/progress data were used. This remains an
ad-hoc-signed local development build using this checkout's existing data paths,
without emulator/BIOS/ROM payload or enabled development self-updates.

Native Windows resource compilation, Android APK/launcher rendering and Linux
desktop/Wayland icon lookup remain host acceptance checks. The earlier Flutter
and macOS host suites are not recounted as new runs for this artwork change.
The [artwork walkthrough](assets/branding/README.md) documents regeneration,
licensing, outputs and cleanup; [the verification record](docs/application-icons.json)
retains source/asset fingerprints, exact commands, diagnostics and platform limits.
No OS dependency, global SDK, emulator configuration, signing identity or Git
publication is changed.


## Standalone RetroArch desktop release pipeline — 2026-10-27

The owner-selected sibling `broomm-retroarch` now contains an independent native
GitHub Actions build/release workflow for macOS ARM64/Intel, Linux x64/ARM64 and
Windows x64. Android is explicitly excluded. Exact RetroArch 1.22.2/SDL 3.4.0
source pins, shared SDL3/OpenGL Core/Slang/network control configuration, private
toolchains, notices, native probes, per-file inventories/checksums and complete
corresponding sources are implemented. The queued release train uses
`version.txt` plus automatic stable/candidate tags; only a complete checked
artifact set can be published through a draft. Existing tags/releases are
preserved, and failed GitHub access is never treated as confirmed absence.

On macOS 27.0.1/Apple Silicon, 17 packaging/release regressions and workflow/
ShellCheck pass. A native frontend build passes SDL virtual-gamepad input,
feature/architecture/minimum-OS/relocation/signature checks, actual playing/
paused network command readback and clean QUIT. All 29 files, permissions,
signatures and standalone feature startup pass after fresh ZIP extraction.
Pinned Linux SDK metadata is verified for both architectures; native Windows,
Linux and macOS Intel execution, the first hosted release and Broomm physical
controller/gameplay adoption remain pending.

No project commit, push, GitHub release, Flutter change or trusted setup-hash
replacement was performed. The current Broomm macOS application stays unchanged;
a separate 8,119,704-byte ARM64 RetroArch ZIP is available. See
[distribution status, artifacts and adoption steps](docs/retroarch-distribution.md)
and the sibling project's README/IMPLEMENTATION for exact source/tool versions,
commands, failure corrections, local test effects, logs and cleanup.


### RetroArch first hosted SDK correction — 2026-10-27

The initial `Broomm/retroarch` version/source jobs fail before their logic runs
because pinned Linux libXScrnSaver has only `out`, while its Devbox selector
requested `out,dev`. The sibling recipe/lock now request `^out`; token
permissions and caches are unchanged. An independent lint-job SDK audit covers
all four Unix architectures with retained diagnostics. The original fails on
both Linux targets, the fixed 64 selectors pass, all 17 regressions and workflow
lint pass, and actual version/source commands plus readback pass locally. A
new hosted/native Linux run is still required. Existing macOS artifacts and
Flutter/native application sources are unchanged. See
[distribution follow-up](docs/retroarch-distribution.md) and sibling evidence.

### RetroArch Linux/Windows correction and macOS timeout — 2026-10-27

The next hosted run reaches Linux SDL configuration and fails on missing XTest;
the sibling SDK/lock now include the verified `libXtst^out` on both architectures.
Windows tool paths no longer replace Git Bash with BusyBox in the runner; child
processes resolve their private tools explicitly. All 25 regressions, lint, 66
Unix SDK selectors and repeated local native macOS probes pass. The hosted macOS
ARM64 build/SDL probe succeeds but its frontend GET_STATUS times out; the cause
is still unconfirmed. Flushed frontend logging, owned-child failure sampling
and retained failed runtimes now provide evidence for the next run. Checks and
timeouts remain strict. See [the distribution record](docs/retroarch-distribution.md).
Existing macOS artifacts, Flutter application sources and trusted hashes are
unchanged. No hosted pass, commit, push or publication is claimed.

The subsequent Windows run confirms shell isolation, then fails one regression
fixture with WinError 206: its large inline diagnostic exceeds the Windows
command-line limit. The fixture now reads the same payload from a temporary
file and enforces the UTF-16 command-line bound on every host. All 25 tests pass
locally with the original diagnostic assertions retained. No production/build
code or native artifact changed; hosted Windows acceptance and the separate
macOS timeout remain pending. See the distribution record and sibling evidence.

The latest Linux jobs compile both upstreams and pass SDL input, then fail on a
hard PulseAudio startup dependency. The sibling Linux recipe now disables the
standalone Pulse backend, retaining native ALSA and SDL3's dynamic PulseAudio
route; loader auditing precedes startup and retains all missing-library data.
The exact hosted macOS binary passes locally, while its VM timeout remains
unconfirmed. Explicit loopback client binding, reply identity/full bounded
traces and owned-child UDP inventory improve that transport boundary without
relaxing checks. All 31 regressions, lint and local/exact-CI macOS native probes
pass, including new SDL dummy audio. Build/native results now remain independent
of packaging-test failure, which still blocks release. Native Linux rerun and
hosted macOS acceptance remain pending. No Flutter change, new macOS binary,
OS dependency installation or Git publication occurred. See the distribution
record and sibling `docs/ci-followup-4.json` for exact evidence and limitations.

The next hosted run `40575998429` confirms native probes and packaging pass on
both macOS architectures. Windows reaches RetroArch configure after SDL builds;
the recipe now bypasses its Unix-style executable lookup with explicit private
compiler/resource/pkg-config `.exe` paths. Linux's only remaining loader failure
is headless-host EGL: the probe conditionally provisions the existing locked EGL
loader in a private test directory, strips its SDK RPATH and retains strict
host-dependency auditing. Native Wayland/EGL and shipped packages are unchanged.
All 37 regressions and lint pass locally; corrected native Linux/Windows checks
await a hosted rerun. No Flutter change, new binary or Git publication occurred.
See the distribution record and sibling `docs/ci-followup-5.json`.

Run `40579927392` confirms native checks and packaging pass on both Linux
architectures and macOS ARM64. Windows compiles and passes SDL/feature checks;
its first UDP query receives Winsock 10054 before the emulator binds its port.
The probe now handles only that Windows port-unreachable response within the
existing deadline, retaining actual acknowledgment and live-child requirements.
All 41 regressions, lint and the actual local macOS frontend check pass. Intel
macOS failed earlier during Nix package-cache DNS/downloads; its recipe is
unchanged and needs a hosted rerun. Windows native frontend acceptance also
remains pending. No Flutter change, new binary or Git publication occurred.
See the distribution record and sibling `docs/ci-followup-6.json`.

Run `40582896434` passes all Unix jobs and both Windows native probes. The
remaining Windows failure is package metadata using native backslashes against
a forward-slash ZIP inventory. The recipe now serializes portable references
and explicitly rejects unsafe or missing entries. Real nested target fixtures
and a Windows-path roundtrip cover the boundary on every host. All 44 regressions,
lint and existing real macOS package verification pass locally. Exact Windows
artifact readback confirms the corrected references. New native Windows packaging
and publication remain pending. No Flutter or binary change occurred. See the
distribution record and sibling `docs/ci-followup-7.json`.

## Owner-requested local development cleanup — 27 October 2026

Removed the obsolete checkout-local library, accounts/settings, profile progress,
managed emulator copies, prototype data, supplied test ROMs, research sessions,
download/tool caches and generated build state. Retained the source tree, locked
environment definitions, signing material and current
`build/releases/Broomm-macOS-automatic-cores.zip`. Historical committed native
evidence remains; its deleted ignored fixtures need reprovisioning for reruns.
No application behavior changed and no new binary was necessary.

Before removal, the process inventory showed no Broomm/emulator/build writers,
seven existing development runtime locks were acquired, and production
configuration/symlink inspection found no references into the deleted roots.
Production's 1,546-file path/type/size/modification-time inventory was identical
before and after (SHA-256
`21457af55770f1bc3790ab0553a620ab38fe3930020004b268701808b80d087c`).
No production files, installed Applications bundle, Keychain entries or remote
RomM data were modified. The retained macOS ZIP still hashes to
`39dffc43d3ac6aea38ab560a52a7c9cb73e9d8159de84f77f12b2d305c0e13f9`.
Available disk space increased by approximately 131 GB; nominal deleted directory
sizes were larger because of shared/cloned storage. These are filesystem checks,
not a new application or gameplay verification run.

## macOS emulator setup portability — 28 October 2026

The owner reported PCSX2, ARMSX2 and PPSSPP setup rejecting valid downloads on
another MacBook. Their local re-signing was followed by exact comparisons with
signature bytes captured on the development Mac. Fresh official downloads match
here; deliberately different valid code-signing output reproduces the rejection
class. The friend's exact signing difference remains uninspected.

Reviewed archives retain mandatory source size/SHA-256 validation. Privately
re-signed output now uses macOS deep/strict/all-architecture validation, expected
file/link structure and its locally recorded executable hash, instead of a
separate SHA-256 inventory comparison with another Mac's signatures. Receipts
bind the result to the specific build's reviewed source archive. Existing raw
imports and receipts remain compatible. Logical emulator/state/Switch progress
identities stay stable across signature variations; cancellation, writer locks,
private staging, copy/receipt/publication readbacks and progress retention remain.
The shared correction also covers Dolphin, DuckStation and Eden signing recipes.

Static analysis and all **415 Flutter tests** pass on macOS 27.0.1 / Xcode 27.1.
Three new signing regressions and an expanded state-compatibility case cover
different valid signatures, restart/source-free reuse, damaged resources,
unreviewed provenance, bad downloads and cancellation. Real pinned PCSX2 2.8.2,
ARMSX2 nightly-20261023 and PPSSPP 1.20.4 install with alternate valid signatures,
open private no-game configuration processes and exclude competing writers.
These are native setup/process checks, not fresh gameplay or friend-host
acceptance. No owner data or RomM progress is modified. Astris/Citra MMJ and
their default-selection work remain stashed. See the [walkthrough and evidence](docs/macos-emulator-signing.md).

The fresh [macOS package](build/releases/Broomm-macOS-portable-emulator-setup.zip)
is **20,477,225 bytes**, SHA-256
`c6732b81b0cf422756fe7b9f3b9f2221ecc93f2cdfaf12334f89c880cc4e28cc`.
The app and three bridges are universal; archive integrity, source and
fresh-extraction deep/strict/all-architecture signatures, and exact setup/bridge
readbacks pass. This portable local build uses production Application Support
storage and ad-hoc signing, with development self-installation disabled.
No emulator, game, firmware, credential or progress payload is bundled.

Before the requested Git publication, the updater was also corrected to use the
actual `Broomm/broomm` origin. Public API inspection showed distinct release IDs
and revisions in the old personal and organization repositories. Older installed
clients remain pointed at the personal repository and need one manual
organization-release installation before using this update stream. Two new
regressions verify organization API discovery/asset selection and rejection of
old or unrelated publishers. Analysis and all **417 tests** pass. The local
package was rebuilt; incremental compilation required refreshing the
project-owned App.framework and outer ad-hoc signatures before source and fresh
ZIP extraction signature checks passed. This does not change CI signing policy.

## Independent Open emulator and Azahar bundle launch — 28 October 2026

Open emulator now hands the no-game application to the OS and leaves Broomm
visible and navigable. It retains no emulator process, output subscription,
readiness/exit polling or game-active state, does not restore focus on exit,
and does not require that app to close before Broomm quits. Repeated activation
coalesces only a pending launch request; request failures are visible and allow
retry. Private profile settings and all gameplay supervision remain unchanged.

Complete macOS bundles use Launch Services with literal arguments and explicit
private environment values; the portable melonDS executable uses detached
startup. Azahar 2126.1.2 warns when its parent is not PID 1 and recommends opening
its app bundle. Its actual corrected launch has parent PID 1. Existing native
interop acquires both file locks inside the independent configuration process,
refuses conflicts nonblockingly and applies the existing private write policy
through the macOS sandbox API. No emulator monitoring or new dependency/service
is introduced. Installer-only lock and RPCS3 teardown behavior are preserved.

Analysis and all **421 Flutter tests** pass. Three UI/model regressions cover
window/session/shutdown behavior, retry and pending-request coalescing. Native
fixtures verify private writes and coordinator conflicts/linked paths; the latter
uses a held production lock plus a successful unlocked control. The four native
configuration tests also pass under UBSan trap instrumentation, and Clang static
analysis reports no findings. Five existing native installer regressions pass
independently. Real Azahar, PCSX2, ARMSX2 and PPSSPP apps open in disposable
profiles, with Launch Services parenting and actual native lock ownership
verified through read-only POSIX queries. Other emulators/hosts, camera behavior,
gameplay and owner visual/controller acceptance are not newly established.

The fresh universal macOS package is
[Broomm-macOS-independent-emulator-launch.zip](build/releases/Broomm-macOS-independent-emulator-launch.zip),
**20,480,144 bytes**, SHA-256
`efc4bef497e693c297e4d52efd7770af77473101ce809519905f6ed017c9b4c4`.
ZIP integrity, source/fresh-extraction deep/strict/all-architecture signatures and
exact guard readbacks pass. It uses production Application Support storage,
ad-hoc signing and disabled development self-installation; no owner or RomM
progress was modified. Paused Astris/Citra MMJ/default-selection work remains
excluded. See [walkthrough and evidence](docs/emulator-opening.md).
