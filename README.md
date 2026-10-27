# Broomm

Broomm is a native Flutter game launcher in early development for Windows, macOS, Linux, and Android, initially targeting RomM 5.4.0 with macOS/Linux validation first. Its controller-first Home and Store take inspiration from the PS5 interface. Users select a saved server, then a known profile; ROMs are shared while saves/states stay private. Only one game runs at a time.

The default Flutter application connects to RomM 5.4.0, signs in, and opens a console-style Home with **Broomm settings**, **Game Store**, and **Emulator Settings**. The Store downloads games to Home. On **macOS Apple Silicon**, the managed setup pack configures RetroArch, Dolphin, RPCS3, Azahar, Ryubing, melonDS, DuckStation, PCSX2, ARMSX2, PPSSPP and Eden; supported Home games open controller pairing before play. PCSX2 runs through existing Rosetta. Timestamped BROOMM saves, explicit imports and named backups are available for the documented native formats; see [save history and PS3 ISO support](docs/slotted-saves-and-ps3-iso.md). The earlier six-ROM controller lab is preserved separately.

For PSP, set up **PPSSPP** under its platform card and Play a downloaded ISO, CSO v1 or PBP; no BIOS is required. For the additional Switch choice, set up **Eden**, then select **Set as default**. Both use the normal controller-pairing flow and profile-private cloud saves. The [PPSSPP/Eden walkthrough](docs/psp-and-eden-support.md) covers native DLC directories, firmware/keys, cleanup, test commands and the experimental Eden macOS limits. The current [colored support matrix](docs/platform-support-matrix.md) includes both.

The latest local macOS test build is [Broomm with the infinity app icon](build/releases/Broomm-macOS-infinity-icon.zip). It includes the current application changes and precompiled bridges, uses this checkout's existing data/setup paths, and contains no emulator, BIOS or game payload. The local emulator pack targets Apple Silicon. This development build keeps automatic app installation disabled; official GitHub release builds enable it.

![Broomm application icon](macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png)

The mint infinity icon is included in macOS, Windows, Linux and Android debug,
profile and release builds. See the [artwork source, native resources and rendering command](assets/branding/README.md).

## Run Broomm

Official release builds now check GitHub for Broomm updates. An available release
adds **Update Broomm** as the first Home tile. Activate it with A/Enter or a click
to download, verify, install and restart. **Broomm settings → Application updates**
contains the channel and manual check. Development/PR builds stay manual; the
first packaged release containing this updater can update to subsequent releases.
See the [application update walkthrough and recovery notes](docs/application-updates.md).

The native Nintendo Switch homebrew app lives in the sibling [broomm-nsw project](../broomm-nsw/README.md), with its own requirements, implementation status and build environment. General Broomm decisions, the Flutter application and Switch emulator integration remain here.

Android has an initial external-app route, **not complete emulator parity**; see the [Android status](docs/android-emulators.md). On an Android build, open **Emulator Settings → Refresh installed apps**, choose an installed default or use **Install** / **Install APK…**. Android confirms installation and Broomm reads back package status. Play opens the external app directly without controller pairing.

For PPSSPP, melonDS or Azahar, use **Configure saves**, then select **Broomm · profile · emulator** in the emulator's folder picker. Use it as PPSSPP's Memory Stick root, melonDS's custom save directory or Azahar's user directory. Save/exit the emulator and confirm the selection. Choose the matching root after changing profiles. Play checks BROOMM history before handoff; save and exit the emulator before choosing **Finish and sync progress**. After interruption use **Emulator Settings → Finish previous game session**. Existing external saves are not moved or erased. PSP native-folder/ZIP content can use the connected root. Other Android save/package adapters and DS states remain incomplete, and no native Android acceptance is claimed.

Verify the Android workflow and compile its native sources:

```sh
devbox run -- flutter --suppress-analytics test --no-pub test/android_emulators_test.dart
devbox --config tool/android run check
```

The second command uses a pinned, separate Devbox Kotlin/JVM environment and hash-pinned API artifacts in `.tool-cache/research/android`. Its `bridge.jar` output is **not an APK**. This host lacks a full Android SDK/device; APK/device verification remains required. Remove that cache and `tool/android/.devbox` to clean the compile-only tooling. Android game deletion keeps Broomm save roots/recovery. Uninstalling Broomm or clearing its Android app data also removes those private roots: sync/export progress first.

From this checkout, with Devbox and the already provisioned Xcode host:

```sh
devbox run app-run
# Or build the native bundle:
devbox run app-build
# build/macos/Build/Products/Debug/broomm.app
devbox run app-check
```

1. Select **Server address**, enter your RomM URL (for the supplied instance, `https://romm.docubi.casa`), then **Continue**. Click/touch a field to type directly. Tab/arrows focus a read-only field; **Enter** starts typing and **Escape** stops editing while keeping that field focused for navigation. Controller A opens the virtual keyboard; its Done/Cancel restores navigation focus. You can switch input devices at any time. HTTPS certificates are verified. HTTP requires an explicit choice on the server form; credentials are unencrypted on HTTP.
2. Choose **Add profile**, enter the account's username/password and **Sign in**. A client token or eight-character RomM API key pairing code (letters and numbers) is also supported; lowercase and hyphen-separated codes are accepted. Token permissions need `me.read`, `roms.read`, `platforms.read` and `assets.read`, plus `assets.write` for cloud saves and `firmware.read` for automatic PS3 firmware retrieval. Broomm remembers a refresh/client token in the system secure store, separately for each server/account. On later starts, select the saved server and profile to continue without another password while the credential is accepted. Passwords are never saved. Accounts must already exist in RomM.
3. Move left/right between Home tiles and press A to open one. D-pad/left stick moves focus; B/Esc goes back; controller X opens Store search with the virtual keyboard. The controller keyboard supports letters, Shift, symbols, spaces, backspace and Done. Physical arrows move the caret only while editing; Escape returns them to navigation. Tab moves between controls.
4. Open **Game Store**, search/filter and choose **Download game** (choose a release if grouped). Downloads queue one at a time. Mapped artwork pickers appear immediately while transfer continues, with image dimensions. **Downloads**, beside Store on Home, shows active, queued and failed entries, with cancel/retry/remove. Completed games appear on Home. Closing Broomm cancels the active transfer and preserves unfinished queue records for explicit retry. Base-game downloading changes no remote ROM/save content; gameplay and explicit save actions use the cloud-save contract below.
5. Open **Broomm settings** to change reduced motion, artwork display or games per page. Settings save immediately. **Switch profile** or the footer profile button retains remembered sign-ins. **Sign out on this device** removes the current profile's local credential; its server, profile, ROMs and progress remain. This does not revoke the token in RomM. An unavailable/locked secure store produces a visible error; successful login can continue for that session without saving a plaintext fallback.
6. Open **Emulator Settings**. Every RomM platform has a section, including unsupported platforms. Select a card's **Set up**/**Verify setup**, review the expansion in that card, then **Start setup**. Arrow/controller down visits card actions and the expanded confirmation before the next card. A supported platform always has an effective default for Home Play; **Set as default** selects another configured choice when available, including the two PS2 and PS3 choices. **Import setup JSON** selects a local file and opens a matching review. The first pack copies the exact tested app bundles already in this checkout's `prototype-data/`; it imports binaries/core and selected supplied firmware/keys, with fresh profile settings, preserving prototype saves. Remote archives, arbitrary newer versions and a system-executable picker remain pending; see [schema and limits](docs/managed-emulators-and-play.md).
7. Select a supported downloaded game on Home and choose **Play**. Missing emulator/resources lead to setup. Choose an entry file if the download has several. An explicit loading screen stays visible until native input/pause is ready. **L1+R1** joins; test buttons in the live diagram. **L3+R1** swaps both face pairs, **L1+R1** cycles Wii types after joining, **L3+R2** toggles gyro, hold **Select** removes a player, hold **Start** starts/resumes. Pointer/keyboard can use the visible controls. **R3+Select** opens the paused menu; its Controller pairing screen applies changes live. Disconnecting an assigned controller opens pairing. Close the emulator normally to return Home. A shutdown error retains the writer lock and progress; close the native window normally before another launch. PS3's first shader/PPU compilation can take several minutes.
8. The local fixtures remain in **Broomm settings → Open local controller test games**. Press B/Esc from that lab's game list to return. Its original prototype progress stays separate from the new server/account profiles. Server/profile changes are blocked while a Home game is active.
9. To uninstall a configured emulator, open its card and choose **Remove → Remove emulator**. Confirmation explains the shared effect (Dolphin serves both GameCube and Wii). Broomm removes only its managed app/core/installation resources; all profile settings, saves/states, source bundles and downloaded ROMs remain. Removal is unavailable during gameplay. If interrupted after withdrawal, **Finish removal** resumes cleanup; set up the emulator again to play. No remote file is deleted.

Development builds store metadata/preferences in `broomm-data/accounts.json`, under `settings.lock`; logs rotate at 1 MiB with ten retained segments. ROMs/receipts are in `broomm-data/library/<server-id>/<rom-id>/`, protected by `library/downloads.lock`; folder structure stays under `content/`. Managed releases are in `broomm-data/emulators/`; profile-private configuration, saves, states and console data are in `broomm-data/profiles/<profile-id>/emulators/`. Shared `session.lock` and emulator-owned `writer.lock` enforce one game across app instances and exclude setup. These files are ignored. Save sync appends timestamped versions to the current account/game's `BROOMM` slot, with local recovery in `cloud-saves/`; see the walkthrough below. `prototype-data/` remains independent. Never delete live lock files. Removing `broomm-data/` after all writers close deletes downloaded ROMs, managed copies, account metadata and every profile's local progress; keep the whole directory to preserve them.

Packaged builds without the development root use macOS Application Support, Linux XDG config, Windows APPDATA, or Android app-private files. `BROOMM_DATA_ROOT` can select a root at build time. Linux launcher navigation requires access to gamepad evdev devices; Steam key mapping remains an alternative. Native Linux/Steam, Windows and Android checks are pending. See [implementation, sources and verified limits](docs/romm-application.md).

Remembered sign-ins use macOS Keychain, Windows Credential Manager, Linux Secret Service, or Android Keystore-encrypted private files. Linux requires an available unlocked Secret Service provider in the session, including Steam Gaming Mode. Windows currently enforces Credential Manager's native blob limit; oversized credentials stay session-only with a warning. `authentication-locks/` contains only nonsecret coordination files. Use device sign-out before intentionally discarding account metadata; deleting a data directory does not clear OS credential-store entries. See [Argosy research, storage choices and verification](docs/remembered-signins-and-platform-settings.md).

## PlayStation / PlayStation 2

Set up **DuckStation** under PlayStation, or **ARMSX2 / PCSX2** under PlayStation 2. For automatic BIOS installation, add `bios.bin` to the matching RomM platform's BIOS/firmware catalogue: a raw 512 KiB PS1 BIOS or 4 MiB PS2 BIOS, then rescan. The supplied account already has both. Broomm verifies and copies the missing BIOS into this profile on first Play. Existing firmware and rendering preferences are retained. PCSX2 on Apple Silicon needs Rosetta already installed.

Launch, join with **L1+R1**, hold **Start**, and use **R3+Select** for paused pairing/remapping. Both systems expose two controller ports. Quit normally to flush native memory cards and synchronize the `BROOMM` slot. PS1 uses `.mcd`; PS2 uses `.ps2`; multi-card exports use ZIP. The PS2 alternatives share this profile/game's ordinary cards, while settings and exact-build states remain separate. Use **Set as default** to switch engines and **Open emulator** for private native settings. Individual-game exports such as `.psv`/`.psu` and headered cards need conversion before import.

See [formats, pinned builds, test commands, paths and cleanup](docs/playstation-support.md) and the [current support matrix](docs/platform-support-matrix.md). The new release is `build/releases/Broomm-macOS-arm64-playstation.zip`; it contains Broomm and its precompiled bridges, with no emulator/BIOS/ROM payload. Keep `broomm-data/` to preserve progress. Disposable native test installations live in `.tool-cache/research/playstation/native-*` and may be removed only after their processes exit.

## Run the controller prototype

From this checkout, with Devbox and the already provisioned Xcode host:

```sh
devbox run prototype-prepare
devbox run prototype-run
```

Preparation is explicit and local. It clones the five already prepared emulator fixtures under `experiments/injection/sessions/` into `prototype-data/`, copies the existing Snes9x core, and builds two C bridges. It reuses the firmware/keys already supplied for the research; it downloads no games, emulators, firmware or OS dependencies. Existing prototype data is retained on subsequent preparation. The running app does not need compilers. Run preparation with all prototype games closed.

1. Choose a ROM using D-pad up/down or keyboard up/down and A/Enter, or click a game. The list stops at its ends and scrolls the selected game into view. All six provided games are listed, including Wii Brawl. An explicit **Loading <emulator>…** screen stays visible until the game, controller discovery and native pause are ready. No player slots or device chips appear during loading. **Cancel launch** (or Esc) requests normal shutdown after the process starts; Azahar finishes startup before safely closing.
2. Connect controllers over USB or pair them with macOS Bluetooth first. Press **L1 + R1** (Xbox LB + RB / Nintendo L + R) to join, or click its detected-controller chip. Initially only a centered Player 1 card appears. Each join reveals that player's live tester and one next join card, up to the fixture's limit: 3DS one, SNES two, others four.
3. Press buttons and move sticks/triggers to illuminate the **target console's controller**, including PS3 symbols, the GameCube layout, SNES, 3DS and Switch Pro. Broomm guesses face orientation from SDL controller family, with a name fallback. Press **L3 + R1** to swap **both A/B and X/Y**, independently of controller type. Release both chord buttons between changes. **L3 + R2** toggles that player's gyro in pairing or during gameplay; accelerometer input stays enabled. The gyro icon shows the selected state. Short Start/Select presses and the D-pad only test input: **hold Select/Back for one second** to remove that controller, or **hold Start for one second** to apply and play, then release all controller buttons. The progress bars show the holds. Mouse controls still allow reordering, changing layout and removal. Keyboard arrows/Tab select a visible control and **Enter activates that control**; select **Apply & play** to start and **Cancel game** to stop.
4. While playing, press **R3 + Select/Back** together on a paired controller. Input is blocked, the game pauses, and the Flutter window opens over the emulator with one menu item: **Controller pairing**. The bottom face button opens it; hold Start or press Esc to resume. The same pairing screen applies changes without restarting. For Wii, the four illustrated choices are **Upright Remote, Classic Controller, Remote + Nunchuk, and Horizontal Remote**. One large tester shows the active type, with all four small illustrated choices below. **L1 + R1 after joining cycles Wii types**; clicking a type also keeps the current face orientation. With gyro pointing off or unavailable, the right stick supplies relative IR pointing for upright Remote and Remote + Nunchuk (horizontal Remote also has stick pointing). R3 recenters the pointer. R1 supplies shake for Remote modes; Nunchuk uses the left stick, L1 for C and left trigger for Z. Classic uses both sticks and its own buttons, without duplicate Remote bindings. Source accelerometer input drives the Remote, and enabled gyro plus accelerometer enable Dolphin gyro pointing instead of the vertical modes' stick pointer; **R3 alone recenters the pointer**. The controller card shows motion bars only while gyro is active and readable, plus missing/failed sensor status. Classic does not consume Remote motion. A separate Nunchuk motion source and the MotionPlus extension remain unimplemented.
5. Disconnect a paired controller. The game pauses and pairing opens automatically. Reconnect and explicitly join again, or continue with another joined controller. Unpaired-device removal does not interrupt play.
6. Use **Cancel game** in pairing or close the emulator normally to return to the list. An emulator failure also returns to the list with its exit status. Closing/quitting Broomm requests normal emulator shutdown first; if it remains open, the app retains ownership and explains how to close it. It never forcibly terminates owner gameplay.

Broomm keeps its normal macOS title bar and your chosen window size throughout this flow. It no longer resizes itself to match emulator windows. Dolphin's emulated GameCube sockets now follow the applied pairing: two paired players connect two pads, and changes apply during the session. If bridge snapshots stop after discovery, Broomm returns to pairing after five seconds, marks pause as unconfirmed and retains the live writer's ownership/data. Close the emulator normally if it cannot recover.

The emulator starts behind the loading screen to inspect its own SDL runtime. Pairing appears only after controller discovery and native pause are confirmed; gameplay input stays gated. The overlay is a separate Broomm Flutter window placed over the game, rather than GPU present-hook rendering. Physical pads, actual player behavior, fullscreen Spaces and focus still require owner acceptance. Steam/gamescope compatibility is also unverified; the [preliminary compositor review](docs/research/controllers-and-overlays.md#steam-big-picture-and-gamescope-preliminary-window-review) explains why ordinary separate-window stacking needs its own native test. Mouse/keyboard fallback remains available. SDL devices without a gamepad mapping, rumble and Steam/Linux handling remain outside this first prototype. Motion uses the emulator runtime's SDL accelerometer/gyro support: Dolphin Remote, RPCS3 Sixaxis, Azahar 3DS motion and Ryubing gamepad motion. No extra service or dependency is required. A controller/driver that exposes no sensors keeps ordinary button/stick support. Steam Input may hide the underlying sensors; this build does not bypass it. Other hosts, split Joy-Con sensor variants and motion feel/calibration need native/owner verification.

Each emulator has persistent settings, saves/states, firmware and caches under `prototype-data/<emulator>/`; there is one local prototype profile. ROMs stay in `roms/` and are write-protected in child sessions, as are original PGCS/Teddy resources and normal user configuration roots. No RomM synchronization runs. Do not delete `prototype-data/` if you want to retain progress; removing a build or rebuilding the app does not remove it. Never remove `session.lock` or `writer.lock` while any Broomm/emulator process is alive: they are stable lock inodes, not stale-marker files. After all games exit, transient `bridge-status.json`, `bridge-command.txt` and logs may be removed; retain save/user/portable directories. Failed provisioning staging directories are retained for inspection.

```sh
devbox run prototype-check       # static analysis and Flutter tests
devbox run prototype-check-macos # native window/foreground regressions (Xcode)
devbox run prototype-build       # build/macos/Build/Products/Debug/broomm.app
devbox run prototype-smoke       # six real ROMs, synthetic SDL test sources
devbox run -- dart tool/smoke_wii.dart # eight Wii variants + mixed Nunchuk/Classic players
devbox run -- dart tool/smoke_motion.dart # four real ROMs, synthetic motion routing/failure checks
devbox run -- dart tool/check_motion_hardware.dart # Brawl, connected motion pads, five-second observation
devbox run -- flutter test tool/smoke_gyro_live_test.dart # real Brawl + Dart model, live gyro hotkey/pointer fallback
devbox run -- flutter test tool/smoke_startup_test.dart # six-ROM startup gate, immediate close and early cancellation
```

The smoke suite is separate from interactive play, holds the same session locks, and never enables test sources in the Flutter app. It checks native pause/resume, live routing and both face-button swaps, R3+Select, held-confirmation input neutrality, paired-device detach, the emulator-owned writer lock and graceful exit. Evidence is written to `prototype-data/smoke-results.json`, `prototype-data/wii-results.json`, `prototype-data/motion-results.json` and `prototype-data/motion-hardware.json` and `prototype-data/gyro-live-results.json`; per-emulator `broomm.log` and `bridge.log` provide details. The [original prototype snapshot](docs/research/prototype-validation.json) preserves the first six-ROM run; the [reliability follow-up](docs/research/prototype-reliability.md) records the owner's failures, fixes and current regression results separately. The [tester/Wii follow-up](docs/research/controller-pairing-testers.md) records the new controls, native reload/readback and the Azahar callback correction. The [motion follow-up](docs/research/controller-motion.md) distinguishes real getter consumption, Azahar event delivery and the two physical Switch Pro sensor observations. The hardware check requires connected, SDL-visible motion controllers and briefly resumes Brawl with those sources; it closes normally and retains private game data. The live gyro check exercises the real Dart model and reads Dolphin's raw pointer controls in the same Brawl process for both vertical modes and a source without gyro. In-game gyro changes briefly pause, apply and resume after the chord is released. Neither native raw input readback nor the hardware observation establishes owner pointing feel or visual acceptance. Source/build details are in [native/README.md](native/README.md). The development build is tied to this checkout's local fixture manifest; it is not a standalone installer.

Targeted regressions use the same prepared games and one reused session supervisor:

```sh
devbox run -- dart tool/smoke_prototype.dart smw --preconnected --repeat=3
devbox run -- dart tool/smoke_prototype.dart 3dworld --focus-broomm --repeat=3
devbox run -- dart tool/smoke_prototype.dart 3dworld --close-game-window --repeat=2
devbox run -- dart tool/smoke_prototype.dart melee --bridge-outage
```

The focus check opens the built Broomm app and verifies the emulator actually lost focus before allowing resume. Run these commands with interactive games closed. The outage fixture suppresses status publication, then restores it; it never kills or suspends an emulator. The pinned Ryubing/macOS SDL2.30 workaround disables that child process's GCController backend while retaining HIDAPI/IOKit. Two connected Switch Pro controllers remain discoverable; MFi-only controllers need separate acceptance with this workaround. macOS Broomm uses the existing Skia Metal renderer to avoid the observed Flutter 3.47 Impeller foreground/resize crash. No SDK or emulator update is performed.

The [earlier injection validation](docs/research/injection-validation.md) preserves the original five-emulator findings separately.

The [responsiveness/loading follow-up](docs/research/pairing-responsiveness.md) records the measured UI/logging work and readiness boundary. Motion bars appear only with active, readable gyro on a target that uses motion; gyro-off still routes acceleration and shows applicable stick-pointer guidance. Session output is decoded/written on an in-process Dart worker with bounded batching/backlog and rotating logs, so emulator output does not perform synchronous file writes on the Flutter UI isolate. Logging errors remain visible and do not release a game's writer lock. Startup test results are in `prototype-data/startup-results.json` and `prototype-data/azahar-startup-close-results.json`. These checks suppress host presentation and use synthetic sources; physical responsiveness and Steam/gamescope remain owner/native acceptance.

## Read the documentation

For CI failures and local reproduction, see the [latest hosted-run follow-up](docs/github-releases.md#sixth-hosted-ci-follow-up--2026-10-26). Linux ARM64 now compiles and links; the remaining packaging failure came from checking the launcher before preparing its engine's SDK search paths. The correction prepares all binaries before auditing dependencies, with native regressions scheduled on both Linux architectures. Local checks inspect actual x64/ARM64 engines on macOS; native Linux loader checks still require CI. The supplied macOS native test command succeeds; its result upload fails on GitHub artifact-storage DNS and needs a rerun. Android signing already built successfully according to the owner; device acceptance remains separate.

| Document | Purpose |
| --- | --- |
| [Application updates](docs/application-updates.md) | GitHub checks, first Home tile, verified installation, restart, recovery and platform validation |
| [PROJECT.md](PROJECT.md) | Product requirements, user journeys, and deferred scope |
| [AGENTS.md](AGENTS.md) | Engineering practices adapted from PGCS |
| [IMPLEMENTATION.md](IMPLEMENTATION.md) | Staged work, acceptance gates, and current status |
| [Architecture](docs/architecture.md) | Proposed boundaries, profile isolation, installation, and save lifecycle |
| [Confirmed decisions](docs/decisions.md) | Owner-approved scope and constraints |
| [Server/profile flow](docs/profiles-and-servers.md) | Teddy audit, server-first selection, activation and focus behavior |
| [Emulator support](docs/emulator-support.md) | Initial PGCS-derived roster and user-initiated setup JSON installs/updates |
| [PGCS reference audit](docs/pgcs-reuse.md) | Inspected behavior and emulator knowledge; no PGCS application-code reuse |
| [Controllers and overlays](docs/research/controllers-and-overlays.md) | In-process input routing, Steam Input, injection, and overlay feasibility |
| [Injection validation](docs/research/injection-validation.md) | Executed controller, pause and native UI experiments in five macOS emulators |
| [Controller motion](docs/research/controller-motion.md) | Motion routing, physical sensor evidence, independent pairing controls and verification limits |
| [Prototype reliability](docs/research/prototype-reliability.md) | Owner-reported failures, targeted fixes, regression evidence and remaining verification |
| [Probe walkthrough](experiments/injection/README.md) | Build, isolated ROM tests, policy controls, logs and cleanup |
| [RomM and future integrations](docs/research/romm-and-future-integrations.md) | API compatibility, save sync, PC games/Proton, and deferred RetroAchievements |
| [RomM API snapshot](docs/reference/README.md) | Live 5.4.0 schema and read-only proxy verification |
| [Development environment](docs/development.md) | Devbox policy, native SDK constraints, and verification strategy |
| [Remembered sign-ins and platform settings](docs/remembered-signins-and-platform-settings.md) | Argosy research, secure-store tradeoffs, Enter/Escape editing, platform defaults, inline setup and managed removal |
| [Home artwork and deletion](docs/home-artwork-and-deletion.md) | Sequential SteamGridDB pickers, layered backgrounds, title options, safe local deletion and macOS build evidence |
| [Catalogue and Home refresh](docs/catalogue-and-home-refresh.md) | Grouped ROM versions, logo selection, larger Home icons, footer controls and timed notification cards |
| [3DS updates and DLC](docs/3ds-updates-and-dlc.md) | Automatic CIA import, existing-game checks, private deployment, repair and progress-preserving removal |
| [Navigation and motion](docs/navigation-and-motion.md) | Shared focus reveal, Home/header chains, lazy catalogue navigation, modal/text reading, screen motion and verification limits |
| [Remaining details](docs/open-questions.md) | Specific implementation details left after the initial answers |

Start with PROJECT.md and the profile flow, then the research documents. The initial questionnaire is resolved in the decision record. Designs marked **proposed** remain implementation proposals; the documents do not claim working platform support.

## Development

GitHub builds follow Teddy's **`version.txt` + automatic tags** policy. PRs against
`main`/`develop` build macOS universal, Windows x64, Linux x64/ARM64 and Android
universal packages; successful branch pushes publish stable/candidate releases
only after checks and every build pass. Configure the four Android signing
secrets before publishing. See [workflow setup, version examples, commands and
current native limits](docs/github-releases.md). Hosted failures have been corrected
locally; a complete successful hosted matrix remains required.

Project workflows are Dart within Flutter; no PGCS code or Go helpers. Optional C injection bridges may ship precompiled on desktop. Android uses ordinary external emulator app handoff without input injection or overlays. Desktop configuration always stays Broomm-local, even for system-selected executables, and emulator updates are manual/setup-file initiated.

All project dependencies must be managed through Devbox/project tooling. Pre-provisioned Xcode/Apple SDK and Windows native toolchain hosts are approved; no new OS dependencies are installed by bootstrap. See [development constraints](docs/development.md).

Research and owner decisions recorded on **2026-10-16**. PGCS and Teddy source trees remain read-only; no application code is imported. Emulator bundles and supplied firmware were copied into ignored, private experiment directories for the authorized ROM tests. The owner's RomM public schema was retrieved through the supplied HTTP proxy and reports 5.4.0; authenticated integration checks remain unexecuted.

## Verify managed setup and Home play

For Home artwork, configure **Broomm settings → SteamGridDB API key** with a key from [SteamGridDB API preferences](https://www.steamgriddb.com/profile/preferences/api). It is stored securely per RomM profile, independently of the RomM sign-in. Broomm does not retrieve your server's private SteamGridDB key. A missing key can also be configured from the first artwork popup; artwork remains optional.

The Store groups related releases using RomM's metadata, including search, platform filters and recent picks. Open a game and choose **Download game**; if it has several versions, select a filename-tagged release in **Choose a version** using D-pad/arrows and A/Enter or a pointer. Only that ROM is downloaded. Already downloaded versions are marked; **Download another version** remains available in their details. Identical display names alone do not merge unrelated games, and no RomM metadata is changed.

Downloading a game with an `sgdb_id` mapping opens **Choose a square icon**, **Choose a background**, then **Choose a logo**. These galleries contain square PNG grids, heroes, and static PNG/WebP logos respectively. Use arrows/D-pad and A/Enter or click an image. Previous/Next page keeps each gallery bounded. **Keep current…** advances without replacing that asset. Cancelling the first popup ends selection; cancelling a later step retains earlier choices and the other saved images. Missing images and failed requests keep the game and its fallback artwork. Chosen art is stored locally and shared with that downloaded game across profiles on the same server. The hero covers the top 75% of Home, preserves its aspect ratio and fades into Broomm's existing background. The selected logo replaces the large title; absent, unreadable or disabled artwork uses the typed title. Existing games can add a logo through Select Artwork without redownloading.

Home uses larger icons without captions, with Play and Options side by side. The top branding is removed; the profile and tagline sit at the bottom right, over the base background. Home navigation is at the bottom left. D-pad/arrow Down reaches the actions; Left/Right moves between Play and Options, and Up returns to the selected game. From the footer, Up restores the remembered content selection. Transient notification cards appear at the top left for seven seconds (problems for twelve); new events restart the timer. They take no focus or page space. Ongoing download progress and Cancel stay available until the operation finishes; operation-specific errors remain in details/status.

On Home, select/hover a title and press **Select / View / Back** on the controller to open **Select Artwork**, **Download Updates and DLC** (3DS and PS3) and **Delete**. Keyboard uses the context-menu key or Shift+F10; pointer uses right-click or **Options**, and touch can long-press. Select Artwork refreshes the RomM mapping and repeats the artwork pickers. **Delete → Delete game** removes the shared downloaded files, artwork and its owned installed updates/DLC from this device, **keeping saves and save states**. Add-ons still used by another installed version are retained. No RomM file or emulator application is deleted. A live Broomm game blocks deletion, including from another process. A pending deletion shows **Finish deleting**; choose Delete again to complete it before redownloading.

New artwork lives under `home-artwork/<server-id>/<rom-id>/artwork/choice-*/` (older artwork in library entries remains readable), with `artwork.json` selecting the immutable files and retaining artist credits. Durable `.deleting-<rom-id>.json` checkpoints stay outside the cleanup folder so partial deletion remains recoverable after its inner receipt is gone. Do not remove active lock files or use emulator/profile folders as game-uninstall cleanup. Source bundles and all profile progress remain outside this operation. See [artwork/deletion evidence and limits](docs/home-artwork-and-deletion.md).

For the macOS release-mode build, use:

```sh
devbox run -- bash tool/build_app.sh --release
# build/macos/Build/Products/Release/broomm.app
```

For the current ad hoc development archive, refresh the outer app seal after an incremental build copies native resources, then verify the complete bundle:

```sh
codesign --force --sign - --preserve-metadata=identifier,entitlements,flags,runtime build/macos/Build/Products/Release/broomm.app
codesign --verify --deep --strict build/macos/Build/Products/Release/broomm.app
```

The latest archive is [Broomm with the infinity app icon](build/releases/Broomm-macOS-infinity-icon.zip). Unzip it and open `broomm.app` after closing every previous Broomm game/app normally. A running older copy can still own the download queue. This is a development build tied to this checkout's data/setup paths, with the existing local emulator pack; it is not a notarized standalone emulator installer. The default `devbox run app-build` remains a debug build. See the [application updater](docs/application-updates.md), [RPCS3 installer notification fix](docs/rpcs3-installer-exit.md), [live platform/coverage matrix](docs/platform-support-matrix.md), [automatic first-sync/GT6 recovery checks](docs/cloud-initialization-and-ps3-recovery.md) and [download/status checks](docs/downloads-and-status.md).

For the Intel PS3 option, open Emulator Settings → PlayStation 3 → RPCS3 Intel → Set up, confirm the reviewed source, then choose Set as default. The verified source is available in this checkout; Rosetta must already be installed. Both RPCS3 builds keep this profile’s existing PS3 saves, firmware and add-ons, with separate compilation caches. See [the Intel walkthrough and checks](docs/rpcs3-intel.md). The [Flutter capture-library comparison](docs/flutter-window-capture.md) is historical research; window capture has been canceled in favor of native loading counters.

Close interactive games first. Prerequisites are the existing tested `prototype-data/` bundles/core/resources and provided `roms/`, prepared through the earlier controller milestone; these tests do not download emulator binaries or install OS packages.

```sh
devbox run app-check
devbox run -- flutter test tool/smoke_managed_test.dart
devbox run -- flutter test tool/smoke_home_test.dart
devbox run -- flutter test tool/render_managed_test.dart
devbox run app-build
```

Run Flutter tests and the macOS build serially. Native tests use isolated copied binaries/profile data in `.tool-cache/research/managed-play/`, real ROMs and explicit synthetic controllers; expect six pairing/play/remap/normal-close results, and Home Play returning to Home. Repeated runs retain fixture progress/caches. PNGs are in its `previews/` folder. After every fixture process has exited, that research directory can be removed to reclaim test copies without deleting normal app/prototype data. The normal app never enables these synthetic sources. See [scoped evidence, provenance and remaining work](docs/managed-emulators-and-play.md).

## Verify keyboard/controller navigation and motion

Use `devbox run app-run` with the existing development prerequisites above. A known RomM account with a multi-page catalogue is needed for Store checks; supported local emulator fixtures are needed only for game/pairing checks.

1. On Home, move along the tile row, then Down to **Open/Play** and Up again. The selected tile returns. At a row edge, another left/right press stays there. Up reaches the header; Down returns to the content selection.
2. In the Store, move through the recent rail and several grid rows, including a held direction. The row/column is retained and the focused card stays visible. Return Up to the search field: the view reaches its top and **Game Store** and **Search games** are visible. **Load more games** selects the first newly loaded game; the final row reveals **You're all caught up** when there is no next page. Reverse direction during a scroll: the previous animation must not carry the new selection away. Open details and go Back: the invoking card remains selected.
3. In details, move Up from **Download game/Play** to the outlined description. Up/down scrolls long text; Down at its end reaches the actions. In the platform picker, the current platform is initially selected and revealed. B/Esc cancels without changing the filter.
4. Open a controller keyboard from a password field. Navigate to its visibility button and activate it, then cancel and resume inline editing with Enter. Native controller Back ends inline editing before leaving the form. Keyboard arrows keep moving the caret while editing.
5. In Emulator Settings at desktop width, Right from **Refresh status** reaches **Import setup JSON**; Down reaches the next card's action. Right from **Verify setup** reaches **Remove**, while Down goes to the row below. Move down through several cards, then back up: the entire selected card, including its name, status and bottom padding, stays visible. Tab still visits actions in order. At narrow widths, buttons that wrap onto separate rows use Up/Down. At the first/last row, scrolling includes the view's heading/footer where these fit with the selection. An expanded card taller than the viewport keeps its active action visible. Down at the bottom stays there. Do not start setup/removal unless you intend those existing installation effects. In pairing, keyboard Enter activates the selected button; physical controller buttons/D-pad remain live test inputs with the existing join/hold chords.
6. Enable **Reduce motion** and repeat navigation. Focus scrolling, descriptions, setup expansion, background color, dialogs and screen transitions become immediate. The operating system's disabled-animation accessibility setting also takes precedence.

Verification commands (run serially):

```sh
devbox run app-check
BROOMM_RENDER_ROOT="$PWD/.tool-cache/research/navigation-followup/previews" devbox run -- flutter test tool/render_navigation_test.dart tool/render_shell_test.dart tool/render_managed_test.dart --concurrency=1
devbox run app-build
devbox run prototype-check-macos
```

The build is `build/macos/Build/Products/Debug/broomm.app`. Current widget PNGs and check logs are under `.tool-cache/research/navigation-followup/`; the earlier navigation record remains under `.tool-cache/research/navigation/`. Fixture data is isolated from normal accounts. These artifacts can be removed after checks finish. Native Home smoke retains its existing `.tool-cache/research/managed-play/home-data/` fixture progress; remove it only after all fixture writers exit. Ordinary navigation changes no game/save files; activation retains each action's existing effects. Physical input feel, Steam/gamescope and other native hosts still need owner verification. See [the evidence record](docs/navigation-and-motion.md).

## Verify 3DS updates and DLC

Use the macOS Apple Silicon build above, a signed-in RomM 5.4 account and the configured tested Azahar installation. Put decrypted, unpacked CIA packages in a game's `updates/` (or `update/`) and `dlc/` subfolders and rescan that game in RomM. The game detail API must list those files; merely copying files to the server before a scan is insufficient. Each package must match the base game's title and region.

1. For the already installed **Super Smash Bros. for Nintendo 3DS**, select its Home tile and press **Select/Back**, click **Options**, right-click or long-press. Choose **Download Updates and DLC** with D-pad/arrows and A/Enter or click. Broomm checks RomM, reuses the already downloaded verified DLC when possible, imports it through Azahar and applies it to your profile. It does not download the base game again.
2. Wait for the completion card, then **Play** and check the game's DLC. Repeating the menu action should report **Updates and DLC are up to date** without another transfer/native import. Missing or changed Broomm-owned deployed content is repaired from the verified cache. Extra untracked files cause a visible preservation error.
3. For a fresh 3DS game, choose **Download game** in the Store. Its normal download is followed automatically by update/DLC verification and native installation. Home shows **Installing…** until that game is ready. Optional artwork selection follows installation. If Azahar is not configured, or a CIA is unsupported/corrupt, the completed base game remains on Home with an error; configure Azahar/fix the source and use **Download Updates and DLC** to retry.
4. When another authorized profile plays, its private emulator data receives the shared add-ons while its progress remains separate. For a disposable test installation, choose **Delete** and confirm: ROM/artwork/packages and its owned native content are removed across profiles; saves/states are retained. Add-ons still used by another installed version stay installed. Redownload to check progress retention. Nothing is deleted from RomM.

Transfers/imports show phases and a cancellation action. Close gameplay before changing/removing add-ons. Interrupted publication or cleanup retains a checkpoint; retry the menu action or Delete to finish. Do not delete lock files, private emulator roots or progress as a recovery shortcut. Shared sources/manifests live under `<data>/addons/<server>/<rom>/`; native content is copied into `<data>/profiles/<profile>/emulators/azahar/`. Existing private configuration and all progress stay there. This milestone supports macOS ARM64 Azahar; other emulator/host import adapters remain pending.

Automated checks, run serially:

```sh
devbox run -- flutter --suppress-analytics analyze
devbox run -- flutter --suppress-analytics test
devbox run -- flutter --suppress-analytics test tool/check_3ds_addons_test.dart --reporter expanded
```

The last command needs the supplied Smash Bros. CCI/DLC already downloaded in `broomm-data` and its configured managed Azahar; `BROOMM_ADDON_SOURCE` can select another prepared data root. It uses isolated APFS copies, performs real native import/repeat/profile deployment/removal, preserves test progress sentinels and writes `.tool-cache/research/3ds-addons/native-workflow.json`. It does not change the normal installed game or profiles. Once its processes exit, `native-workflow-*` fixture directories in that research folder can be removed to reclaim space. Live authenticated transfers, actual update-CIA gameplay, in-game DLC visibility and other native hosts remain owner/platform checks. See [implementation, source contracts and evidence](docs/3ds-updates-and-dlc.md).

## Verify downloads, DS and PS3 resources

Use the current Apple Silicon build with this checkout's `prototype-data` pack and a RomM 5.4.0 account. In Emulator Settings, expand Nintendo DS, review melonDS and confirm Setup. Its official 1.1 source is `prototype-data/melonds/melonDS.app`; the pinned inventory is in setup assets. System emulator configuration is untouched. Linux/Windows/Android native verification of these additions remains pending.

1. Queue two Store games. Choose mapped SteamGridDB icon/background/logo immediately, then open Downloads beside Store. Observe up to the configured number of transfers followed by the waiting queue, without a progress overlay. Cancel, then Retry or Remove downloaded data. Removal clears partial files and that transfer's artwork, retaining saved progress and any base game verified before an add-on failure.
2. Traverse a long Home rail with left/right: selection stays nearer the middle, bounded by either end. Store Search matches adjacent button heights. Pointer selection edits the original input; keyboard Enter enables typing and Escape restores navigation. Controller X/search or A on a field opens the docked keyboard in the same window. A selects keys, X deletes backward, Shift/Caps changes case/symbols, Enter/Done submits and B dismisses without submission. Password visibility stays beside the original field.
3. Download a DS `.nds` game and Play from Home. Wait for loading, join with L1+R1, test mappings and hold Start to play. The established R3+Select menu pauses/remaps. Save in-game and close normally. **Use existing save file** accepts an ordinary raw `.sav` or ZIP containing one, copies it into private melonDS storage and appends a native `.sav` version to this profile/game's `BROOMM` slot. DSV containers require external conversion. States retain their verified build/host group.
4. Put one PS3 PUP in that platform's RomM BIOS/firmware catalogue and rescan. Grants/client tokens need `firmware.read`; old remembered grants may need one new sign-in. Play a PS3 game without configured firmware: expect checking/downloading/verifying/installing before pairing. A second launch reuses firmware. Existing configured firmware is retained. Missing/ambiguous PUPs or bad checksums produce errors without selecting arbitrary resources.
5. Put unpacked title/region-matching `.pkg` files in the PS3 game's `updates/` and `dlc/`, with any required exact-content-ID `.rap` files in its manifest; rescan. A new download imports them automatically. Select/Options → **Download Updates and DLC** checks an existing game's differences/repair without downloading the base. Repeated checks report up to date. Delete removes owned native content across profiles while retaining savedata, unrelated files and content claimed by another installed ROM version. Real PKG/gameplay acceptance still needs owner testing.
6. For an encrypted PS3 disc, keep `Game.iso` and `Game.dkey` together in RomM and include both in its scanned file manifest. Download the game: Broomm retains both beside each other, inspects the ISO's title metadata without extraction and passes the ISO path to RPCS3. RPCS3 reads the adjacent key natively; no key text enters command arguments or logs. Already installed ISO/key pairs can be launched directly. A first boot can spend several minutes compiling before controller pairing appears. Decrypted ISOs and extracted `PS3_GAME/USRDIR/EBOOT.BIN` remain supported.

Data effects: game files remain in `library/`; new artwork is in `home-artwork/<server>/<rom>/`; queues are in `downloads/<server>/<profile>/`. Legacy artwork remains readable. Firmware is a shared managed resource plus a private profile copy; PS3 generations live in `addons-ps3/`. Progress remains in `cloud-saves/` and private emulator trees. Installer logs are bounded in `diagnostics/`. Delete through the UI; keep locks/checkpoints in place.

Run serially with interactive games closed:

```sh
devbox run -- flutter analyze
devbox run -- flutter test
devbox run -- flutter test tool/check_installer_guard_test.dart tool/check_ps3_firmware_test.dart --concurrency=1
devbox run -- flutter test tool/check_melonds_test.dart tool/check_switch_progress_test.dart --concurrency=1
devbox run -- flutter test tool/render_library_followup_test.dart
```

Native checks require the existing supplied firmware/ROMs and pinned pack. Isolated copies and rendered PNGs are under `.tool-cache/research/library-followup/`. Remove fixture directories only after their native children exit; retain normal profile storage. See [the follow-up](docs/library-and-progress-followup.md) for exact evidence and limits.

## Verify managed cloud saves

Use RomM **5.4.0**, the configured macOS native pack and an account/token with `assets.read` and `assets.write`. Old remembered read-only grants need one new sign-in, available after a permission failure in the save dialog. No password is retained. Close other Broomm game/setup operations before testing.

1. Launch an installed SNES, 3DS, DS, GameCube, Wii, PS3 or Switch game from Home. Broomm checks only this account/game's latest `BROOMM` slot version in the **Broomm** emulator namespace before pairing. Existing local and remote progress require a choice when there is no common baseline. First play without progress creates no empty remote save. The first Switch launch initializes/binds native save storage, closes its writer, then restores cloud progress before the gameplay launch. With no BROOMM history, a legacy unslotted `broomm` bundle can migrate once; its source stays unchanged.
2. Save inside the game, then close the emulator normally. Broomm returns with a sync screen. Wait for completion or choose **Keep local save and finish later**. RomM should show a new `Broomm [yyyy-mm-dd_hh-mm-ss]` version in slot `BROOMM`, retaining earlier versions. DS uses raw `.sav`, SNES raw `.srm`, and native directory/multifile saves use `.zip`. The smaller old DS `broomm` file was a compressed bundle; its replacement exposes the original native bytes. Compatible states are kept in a matching timestamped state archive, without wrapping the ordinary `.sav`. Routine sync leaves unrelated named saves and slots unchanged.
3. From that game's Select/Options menu, choose **Use existing save file**, select an available source (20 entries per page), and confirm. The selected source remains unchanged; local progress adopts its contents and Broomm appends a new BROOMM version. Supported sources are Broomm backups or the documented native exports; for Azahar, ZIP the complete `data` directory including `00000001.metadata` and `00000001/`. Raw console `.sav` conversions are not guessed.
4. Choose **Backup savefile**, enter a name such as `Before the final boss`, then **Create backup in RomM**. It creates a separate backup with the appropriate extension; backups containing states use `.zip`. An existing filename is refused. An interrupted retry resumes its original recovery snapshot; the dialog explains this. Later automatic sync still uses only BROOMM history.
5. **Cloud saves → Sync / resolve conflict** retries explicitly or offers device/cloud progress when both changed. Both copies are retained locally until a choice succeeds. On a second device with the same account, the same-ROM/native-format save should pull before play; this gameplay check still needs owner verification. State loading requires a compatible emulator/core build and host. Create a fresh state during a Broomm session to establish its build provenance; unverified existing states stay local and are never relabelled during an emulator/core update. Automatic pulls preserve an unverified local state even when a cloud state occupies the same slot; **Use existing save file** can explicitly apply the cloud copy.
6. Play offline, save and close normally. Keep the local-pending notice. When the same account/server is active again, idle retry runs one pending game every 45 seconds. If the managed remote is unchanged from its baseline, pending progress uploads; otherwise choose a version through Cloud saves. Changing profile/server cancels and drains the prior operation. Deleting the game preserves progress and pending snapshots; retry does not need the ROM installed.

Ryubing synchronizes only the verified current program/account's committed save directory and matching device save, excluding account/index/system metadata. RPCS3 has a title-prefixed savedata adapter but no real gameplay-progress fixture; PS3/Switch states are unsupported here. Raw Dolphin memory cards, unsupported imports and other native hosts remain gated or unverified in [the current version-history record](docs/slotted-saves-and-ps3-iso.md). Appending versions preserves concurrent uploads; main-save/state publication is not a server-side atomic transaction and conflicts still require review.

Run checks serially:

```sh
devbox run -- flutter analyze
devbox run -- flutter test --concurrency=1
devbox run -- flutter test tool/check_cloud_progress_test.dart --concurrency=1
devbox run -- flutter test tool/check_cloud_session_test.dart --concurrency=1
devbox run -- flutter test tool/check_ps3_iso_test.dart --concurrency=1
devbox run -- bash tool/build_app.sh --release
```

Native checks use isolated APFS copies and the supplied ROMs. They do not upload normal progress to the owner's server or print credentials. The file check restores copied saves and round-trips native exports, including Pokémon Ranger's `.sav`. The session check starts/closes real RetroArch and checks writer shutdown, lock ownership and fixture-server readback. The PS3 check needs the existing downloaded 3D Dot Game Heroes ISO/`.dkey` and configured RPCS3; it boots in isolated storage, pauses/resumes and closes normally. Logs/evidence are in `.tool-cache/research/cloud-saves/` and `.tool-cache/research/slotted-saves/`. After fixture children exit, their `native-progress-*`, `native-session-*`, `native-ps3-iso-*` and `live-native-*` directories can be removed. Keep normal `broomm-data/profiles/` and `broomm-data/cloud-saves/`; never delete stable locks while Broomm or an emulator might be alive. The separately recorded live DS check appended valid BROOMM versions using isolated local progress; all earlier remote saves were retained. No remote saves are automatically deleted by Broomm.

## Verify controller keyboard shortcuts and RPCS3 cache reuse

1. Open a text field using controller A. The keyboard stays docked under the original field. Use **Y** for Space, **X** for Backspace, **hold L2** for Shift across several characters, **L3** for Caps Lock, **L1/R1** for caret movement, **R2** to submit (Start also works) and **B** to dismiss. The matching badges appear on the keys. Caps Lock and held Shift invert letter case together. Ordinary key selection with A remains available.
2. Check an existing selection and an emoji: replacement/deletion and caret movement preserve Unicode boundaries. Switch away from Broomm while holding L2, release it and return; Shift should be clear. A dialog above the dock must not let shortcuts edit its covered field. Close/reopen the keyboard and confirm ordinary typing still works. Pointer input remains inline without the dock.
3. For the PS3 check, use the existing managed RPCS3 and downloaded encrypted 3D Dot Game Heroes ISO/key. With interactive games closed, run the native cache check below. It copies configuration, firmware and caches into isolated storage, launches twice and reports cached PPU objects reused/changed plus time to pairing readiness. The measured macOS runs each took about 187 seconds while preserving all 204 PPU objects and 155 shader files. The remaining work sampled inside Vulkan/MoltenVK shader conversion; the current pinned pipeline compiler does not persist its driver cache. This build leaves graphics/cache settings unchanged. See [the investigation](docs/loading-preview-and-keyboard.md).

```sh
devbox run -- flutter test test/console_keyboard_shortcuts_test.dart test/console_field_navigation_test.dart --concurrency=1
devbox run -- bash tool/test_macos.sh -only-testing:RunnerTests/RunnerTests/testGameControllerKeyboardShortcutEvents -only-testing:RunnerTests/RunnerTests/testHeldShiftWaitsForEveryControllerRelease
devbox run -- flutter test tool/check_rpcs3_cache_test.dart --concurrency=1 --reporter=expanded
```

The native keyboard tests use synthetic GameController snapshots; verify physical buttons on your controller separately. Other native hosts remain pending. Cache checks change only disposable profile/emulator copies and their local logs, without remote RomM writes. After their children stop, `native-cache-*` under `.tool-cache/research/loading-keyboard/` can be removed. Do not remove normal profile caches or alter unreadable RPCS3 log permissions.

The owner canceled window capture. RPCS3 now uses native loading counters instead; see the current walkthrough below. Earlier capture-library documents remain historical research, with no capture dependency or permission added.


## Verify download limits, cloud badges and emulator configuration

Use the current macOS build, your RomM 5.4.0 account and the configured tested emulator pack. Existing sign-ins, games and private progress are retained. Quit interactive emulator sessions before native checks.

1. Open **Broomm settings → Downloads**. **Maximum simultaneous downloads** cycles from 1 to 6 (default 3). Queue several different games in Store, select their artwork and open Downloads. Each active game has its own progress and Cancel action. Changing the limit starts waiting work when capacity allows; lowering it lets active transfers finish. Add-on installation waits its turn and waits for gameplay to stop.
2. Leave **Verify game checksums** off for normal downloads: HTTP/manifest sizes and completed file lengths are still checked, with no second full-file CRC scan. Turn it on to request that scan. Firmware, executable, add-on and save verification retain their separate checks.
3. Inspect the top-right corner of Home game icons. Green cloud/check means the last sync was confirmed; amber cloud/sync means waiting to sync; red cloud/off means attention is needed. After downloading a supported game with a configured emulator, leave Broomm idle: its first sync runs automatically. A game without local or managed remote progress becomes green without an empty upload. Existing BROOMM progress is restored safely; unrelated slots are left alone. Signing in also initializes legacy installations. Missing emulator setup or Switch's first native save-identity initialization can defer this until ready. Play/quit still synchronizes progress, and **Options → Cloud saves** handles conflicts. Badges do not continuously poll all remote saves.
4. In **Emulator Settings**, the effective default has a green outline. **Open emulator** starts a configured emulator without a ROM using this profile's private settings. Change preferences and **quit the emulator from its own UI**; Broomm returns when its process exits. A configuration process excludes games, setup/removal and profile changes until then. Input routing required by Broomm gameplay is still managed when playing; unrelated RetroArch/Dolphin graphics preferences are now retained rather than replacing their whole configuration files.
5. Open a PS3 game through either RPCS3 choice. During startup, expect native file/module counts and a phase progress bar. Between phases it becomes indeterminate; the counter may reset. Pairing still waits for native input/pause readiness. No window capture or graphics/cache setting change is involved.
6. For Gran Turismo 6, use **Options → Download Updates and DLC**, or Retry its failed download in Downloads. The installed base game is reused. Package files now coexist with game-created title data; replaced metadata is retained for restoration on uninstall. A copied-data integration check installs/reuses/removes the cached native DLC and restores all 579 original files exactly. Actual in-game DLC visibility remains an owner gameplay check.
7. On the virtual keyboard, hold **L2** for Shift and press **R2** for Enter. Y/Space, X/Backspace, L3/Caps, L1/R1/caret and B/dismiss remain available. The gameplay gyro chord L3+R2 is unchanged.
8. If another Broomm copy owns Downloads, the saved queue stays visible with a read-only notice. Quit that copy normally, then select **Refresh downloads**; interrupted jobs offer Retry/Remove. Never delete `queue.lock` to bypass its owner. An already running older app should be closed before using the new PS3 file-ownership format.
9. With the installer-fix build, installing a newly available PS3 package through either RPCS3 choice should complete without macOS's “RPCS3 quit unexpectedly” alert. An unchanged add-on check reuses installed content and does not exercise the native installer. Genuine package failures remain visible in Broomm; the [scoped fix/checks](docs/rpcs3-installer-exit.md) describe the strict success criteria. See the [platform matrix](docs/platform-support-matrix.md) for all 29 server platforms, candidate choices and remaining integration gaps.

```sh
devbox run -- flutter analyze
devbox run -- flutter test
devbox run -- flutter test tool/check_emulator_configuration_test.dart tool/check_installer_guard_test.dart --reporter expanded
devbox run -- flutter test tool/check_rpcs3_loading_test.dart --reporter expanded
devbox run -- flutter test tool/measure_download_verification_test.dart --reporter expanded
devbox run -- flutter test tool/check_gt6_addon_recovery_test.dart --reporter expanded
devbox run -- bash tool/build_app.sh --release
```

The native startup checks use disposable profiles in `.tool-cache/research/downloads-status/`, read the supplied PS3 ISOs/keys and do not upload progress. No-game startup tests terminate only their disposable processes for cleanup; native user-driven preference changes/normal quit remain owner acceptance. The loading test waits through real cold compilation (about twelve minutes for both builds here), then closes through the ordinary session supervisor. Exact results, failed experiments and host scope are in [the evidence](docs/downloads-and-status.md). After every fixture child exits, `native-loading-*`, `native-configuration-*` and remaining `verification-*` folders there may be removed. Preserve normal `broomm-data/profiles/`, cloud recovery and stable lock files. The release ZIP remains a checkout-bound development build; Linux/Windows/Android native verification and notarized distribution are not established by these macOS checks.

The GT6 file check requires the existing BCUS98296 installation and cached native package output. It copies them into `.tool-cache/research/cloud-queue-gt6/gt6-files-*`, exercises production file ownership, then verifies the original profile/registry are unchanged. It does not launch RPCS3, redownload packages or upload saves. Those isolated `gt6-files-*` folders can be removed after the check; keep normal profile data, cloud snapshots and `.ps3-addon-originals` recovery files.

## RetroArch, Wii and Switch follow-up

The [colored platform matrix](docs/platform-support-matrix.md) now records 25 launch/save adapters, with 18 additional RetroArch platforms and separate native acceptance markers. PS4 remains normally browsable/downloadable, with no built-in emulator. Generic custom-emulator JSON import is not implemented yet.

1. In Emulator Settings, select a server platform → its RetroArch core → **Set up / Verify setup**, review the local sources and confirm. This installs the shared frontend plus pinned core pack. Development core inputs are prepared explicitly with `devbox run -- dart tool/prepare_retroarch_cores.dart`; no core is automatically updated. Required BIOS files must be in that platform's RomM firmware catalogue or an explicitly imported local `bios` resource.
2. Download a game, or select an installed Wii/Switch game → **Options → Download Updates and DLC**. Keep Wii packages as WADs and Switch updates/DLC as NSPs under `updates/`, `update/` or `dlc/`. Wii game-channel WAD bases are supported; system/IOS WADs are excluded. Expect native validation/import before completion, with repeat checks avoiding unchanged transfers.
3. For automatic Switch resources, configure **exactly one firmware ZIP, `prod.keys` and `title.keys`** in the Switch platform's **RomM BIOS/firmware catalogue**, then rescan RomM. Start the game or check its packages. Broomm installs missing private resources before pairing and retains existing configured resources. These are the exact filenames; there is no typo alias or automatic firmware update.
4. Play from Home, pair with L1+R1, then hold Start. R3+Select opens the paused pairing menu; L3+R1 swaps face orientation. New RetroArch routes use per-game/private save storage and the existing BROOMM cloud history. Single SRAM files use `.srm`; RTC/VMU/NVRAM companions remain together in a ZIP. State groups require the same frontend/core build. Some older games only create states, with no battery save.
5. Delete removes owned installed packages and shared ROM/artwork while preserving all progress. Content still used by another installed release is retained; after its last reference is removed the package cache is collected. Interrupted cleanup is retryable.

Native game tests now cover 17 of the 18 additional RetroArch routes; Jaguar CD is deferred at the owner's request. Fourteen have ordinary native-data round trips, with a separate seeded 32X EEPROM check. In-game DLC visibility, full special-peripheral/keypad mappings, physical controllers, cross-device saves and Linux/Steam/Windows/Android delivery need their separate acceptance. The [expansion record](docs/retroarch-wii-switch.md), [save follow-up](docs/retroarch-save-followup.md) and [Saturn verification](docs/saturn-verification.md) distinguish their dated results. No owner progress or remote saves are changed by those isolated checks.

## Verify RetroArch save corrections

The later [save follow-up](docs/retroarch-save-followup.md) supersedes the earlier five-route pending count and generic save labels. The [support matrix](docs/platform-support-matrix.md) distinguishes native saves, state-only cores, owner reports and remaining BIOS/media prerequisites.

1. Quit the earlier Broomm build and open the updated macOS build with the existing data directory and profile. No emulator update or reinstallation is needed.
2. On Crash n Burn/3DO, open **Options → Cloud saves → Sync / resolve conflict**. The retained raw BROOMM version should verify without the ZIP/conversion error. Normal play/quit should append a `.srm` version; older versions remain untouched.
3. On Crazy Taxi, sync from that menu or launch and quit normally. The single-game legacy shared VMUs are copied into private storage; the core uses its native disc-ID filenames. A nonempty VMU ZIP and matching states should synchronize after normal close. Keep the original `system/dc` cards until gameplay confirms the migrated progress. An ambiguous multi-game legacy history or conflicting private card stops migration and preserves both copies.
4. Play a compressed save-capable cartridge, such as Sonic 3, Shining Force: The Sword of Hajya or Phantasy Star, then quit normally. Existing native saves named after the outer ZIP are discovered and uploaded as `.srm`.
5. NES 1943 does not produce an ordinary save; no empty upload is expected. Atari 2600 and the pinned Lynx core retain cloud state support, without claiming ordinary cartridge EEPROM. Saturn's BIOS and native progress route are now verified; Jaguar CD validation is deferred.

Run `devbox run -- flutter test tool/check_retroarch_saves_test.dart --reporter expanded` with the documented local cached fixtures to repeat native capture/readback/restore checks. The test copies owner inputs under a writer lease, uses a fixture server and changes no owner progress or remote save. After all test children exit, its `.tool-cache/research/ra-save-followup/native-*` roots may be removed; retain normal profiles, cloud recovery and stable locks.

## Verify Saturn

Add **`mpr-17933.bin`** (USA/Europe) and **`sega_101.bin`** (Japan) to Saturn's BIOS/firmware in RomM and rescan. Both are 524,288 bytes. Configure Saturn's RetroArch card, download a game and select **Play**: Broomm should install missing BIOS files into the private profile before pairing. Join with **L1 + R1**, hold **Start**, then quit the emulator normally. Backup RAM (`.srm`), backup cartridge (`.bcr`) and console settings (`.smpc`) synchronize together in a native ZIP in **BROOMM**; state groups require the same frontend/core build.

The Legend of Oasis has passed native boot, pairing, pause/live remap, backup-memory round trip, state creation/loading and matched snapshot restore on macOS ARM64. These automated checks used disposable profiles and a fixture cloud endpoint, preserving all real progress. Repeat with `BROOMM_SAVE_PLATFORMS=saturn devbox run -- flutter test tool/check_retroarch_saves_test.dart --reporter expanded` after provisioning the local cached fixture. See [exact prerequisites, evidence and cleanup](docs/saturn-verification.md). No emulator reinstall or new Broomm build is needed for this BIOS verification.
