# Cemu and desktop Remote screen

## Setup and use

This branch implements Cemu 2.6 for macOS Intel (including already installed
Rosetta on Apple Silicon), Linux x64 and Windows x64. Cemu has no reviewed
Linux ARM64 package. Android is a client; Android hosting remains deferred.
Use matching current Broomm builds on both devices for Wii U geometry.

1. In Emulator Settings, select Wii U → Cemu → Setup and confirm the reviewed
   download. No emulator update happens automatically. On Apple Silicon, Rosetta
   must already be installed. Linux needs the desktop libraries required by the
   official Ubuntu 22.04 ZIP, including GTK3, OpenGL/GLU, X11/Wayland and Bluetooth
   libraries; Broomm does not install OS packages. Windows uses the normal x64
   desktop host without a controller driver or administrator installation.
2. Install a WUA game or a decrypted game containing code/*.rpx and code/app.xml
   through the normal RomM library flow. An RPX's app.xml and optional meta.xml
   must identify the same base title. On first WUA launch, Broomm briefly opens
   a separate no-game Cemu profile to scan native archive metadata, then closes
   it normally. Only a unique base title for that exact file can select saves.
   Cloud-save actions require that initial inspection; metadata failure never
   becomes an empty save. WUD/WUX keys and Wii U add-on installers are outside
   this milestone. Keep the code/content/meta tree together for decrypted games.
3. Keep host Broomm open. Its server runs from startup, including onboarding;
   the Host button only shows addresses, port 43187 and the connection code.
   On Linux, start the packaged application with `GDK_BACKEND=x11 ./broomm` in
   an X11/XWayland desktop. Native Wayland capture reports an explicit error.
   Allow LAN TCP/UDP discovery and WebRTC media through the local firewall.
4. Connect the client before launching the game, using discovery, a recent host
   or a manual IP:port. The controller navigates host Broomm immediately. Launch
   Wii U, join with L1+R1 and hold Start. The primary Cemu window remains on the
   host; its GamePad View goes to the client. On macOS, grant Broomm Screen
   Recording permission. Use Retry screen after correcting a capture problem.
5. Touch the image to use the GamePad screen. The client fits a 16:9 image above
   its controls and maps it to 854×480, rejecting letterbox touches. Buttons,
   sticks, analog triggers and touch use Cemu's loopback DSU client; no virtual
   OS device is created. One GamePad is supported; gyro, rumble, other controller
   types and multiplayer need later work. R3+Select opens Broomm's game menu.
6. Disconnecting an assigned controller pauses and requires rejoining. Close the
   game normally to finalize cloud progress and restore temporary window settings.
   If a native writer survives, Broomm keeps its lock and progress for recovery;
   it never treats a timeout as confirmation that the writer exited.

Linux also implements best-effort secondary-window WebRTC capture and process-
local forwarded controller input for the existing melonDS/Azahar runtimes.
Windows currently launches/hosts Cemu only; adding Windows melonDS/Azahar
requires their managed runtime adapters. Touch forwarding on Linux/Windows is
currently Cemu only. macOS melonDS touch remains supported. Audio and Azahar
touch remain deferred. No Linux/Windows gameplay acceptance is claimed.

## Storage, ownership and cleanup

Cemu uses Broomm-owned versioned launch copies under
`profiles/<profile>/emulators/cemu/launcher/<executable hash>/`. macOS portable
settings sit next to Cemu.app; Linux/Windows settings are in Cemu/portable.
Settings changes never target the original installation. The stable
`user/mlc01/` lies outside those versioned copies. Ordinary cloud bundles contain
only this base title's account 80000001 and common save directories in
`mlc01/usr/save/00050000/<title low>/user/`; other accounts, title IDs, console
keys and installed content are excluded. There are no supported Cemu save states.
Native title identity is independent of RomM names and file basenames.

`cemu-remote-layout.json` records owned window preferences and their exact old
anchor before modification; restoration preserves unrelated native preferences.
Keep it until the emulator has exited and restoration completes. Reset emulator
settings removes known settings, controller profiles and shader/catalogue caches,
while retaining the MLC, console identity and unrelated files. Managed removal
preserves profiles and progress, as for the other adapters. Normal setup uses the
reviewed package recipe; arbitrary or differently signed Cemu installations are
not accepted as equivalent reviewed builds.

Logs use the existing Broomm log and session diagnostics. Native receipts contain
process birth, writer admission and sequence information; a stale receipt cannot
stand in for current kernel pause state. Never remove session/writer lock files
or manually delete launcher directories while an emulator might still be open.
Recent hosts remain in remote-screen.json, shared with the earlier feature.

## Native implementation and provenance

Dart owns configuration, DSU, title inspection, save handling and lifecycle.
Original Broomm C/Objective-C/C++ interop only admits an actual native writer,
observes process state, changes kernel pause and operates owned windows. No Cemu implementation code is copied into these sources. Build recipes are
`tool/build_bridges.sh`, `tool/build_linux_bridges.sh`, and Windows runner CMake;
no compiler or test runtime is needed by packaged users. Windows packages ship
broomm-cemu-guard.dll and broomm-cemu-run.exe with a static C++ runtime.

Reviewed upstream: [Cemu v2.6](https://github.com/cemu-project/Cemu/releases/tag/v2.6),
source tree a6fb0a48eb437a8a41c13b782ac8ae0433bf8f98, MPL-2.0.
Cemu is downloaded after explicit setup, not bundled into Broomm. Preserve its
upstream license/notices in the private copy. Package URLs, sizes and SHA-256
are pinned in each host's tested-builds.json; inventories include package files.
macOS uses the reviewed exported CafeSystem globals; Linux uses reviewed ELF
writable-data offsets and verifies mapping bounds; Windows uses the exported
gameMeta_getTitleId. These are build-specific capabilities, never addresses from
an imported setup JSON. The native main-window FPS title additionally confirms
renderer startup before offering the pairing gate.

The XML package decision and upstream protocol evidence are in
[the research record](research/cemu-remote-screen.md). Approved xml 7.1.0 is pure
Dart/MIT; pubspec.lock pins its dependencies. XML input is size/depth bounded,
DTD/entity declarations are rejected and malformed settings preserve prior data.

## Verification boundary

Local macOS automated checks exercised real official Cemu 2.6 (Intel under
Rosetta) in an isolated no-game profile: private portable creation, kernel writer
lock/birth inspection, kernel pause/resume, rejection of changed birth identity
and normal exit. Controlled tests exercise DSU's actual UDP wire format and
expiry, pairing cancellation, exact window capture identity, native save/account
boundaries, reset preservation and interrupted layout restoration. These checks
are not Wii U gameplay, GamePad rendering, physical input, cloud round-trip or
owner visual acceptance. A suitable local Wii U game has been requested for
those checks. Linux/Windows native CI results and remaining limitations must be
recorded in IMPLEMENTATION.md; application compilation alone is not acceptance.
