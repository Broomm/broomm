# Loading previews, RPCS3 caching and controller typing

Superseded direction: window capture was canceled by the owner. The current dock uses **L2 Shift / R2 Enter**, and RPCS3 exposes native loading counters. This page preserves the earlier investigation; see [current implementation and evidence](downloads-and-status.md).

Investigation and keyboard implementation, 2026-10-22. The preview below is a concrete design proposal; this build implements the keyboard shortcuts and investigates cache behavior, without adding a capture backend or changing emulator graphics settings. Current requirements remain in [PROJECT.md](../PROJECT.md); exact checks and release metadata are in [the evidence record](loading-preview-and-keyboard.json).

## Live emulator preview: feasible, with platform capture adapters

A small live viewport at the top of Broomm's loading screen is feasible. Capture the supervised emulator's window into a Flutter texture inside the existing Broomm window. Rendering another top-level preview window would not solve the Steam/gamescope requirement. A proposed starting budget is 640×360 at 5–10 fps with aspect-preserving letterboxing, a queue of at most two frames and frame processing outside Flutter's UI isolate. Intermediate screenshots written to files or PNG/base64 frames sent through method channels would add avoidable CPU, allocation and disk work.

| Host | Concrete capture route | Permissions, runtime and uncertainty |
| --- | --- | --- |
| macOS | ScreenCaptureKit window filter → SCStream → CVPixelBuffer → FlutterTexture | Native Apple framework, available since macOS 12.3. Requires Screen Recording permission; the OS may require restarting the app after granting it. No new Dart package. Capture of an obscured/minimized window and dialog switching still need native acceptance. |
| Windows | Windows.Graphics.Capture → D3D11 frame pool → Flutter texture | Native Windows API, support must be queried. System consent/window-selection behavior and capture borders need an intentional UX; direct HWND targeting has its own native contract. Requires a tested Windows adapter. |
| Linux, Wayland and gamescope | ScreenCast portal → PipeWire stream → Flutter texture | Available source types are compositor-dependent; window selection normally involves a system picker. Portal/PipeWire support and Gaming Mode must be checked on the actual distribution. Restore tokens can reduce repeated selection but do not establish silent PID capture. |
| Linux, X11 | X11 window capture as a separate backend/experiment | An XWayland/X11 window ID is not interchangeable with a Wayland surface. Need native scaling, ownership and same-game/compositor tests; it is not a general gamescope solution. |
| Android | Preserve the existing external-app handoff | No desktop injection/overlay/capture machinery is proposed for this staged Android flow. |

Capture only windows verified against the current supervised process, executable and launch generation. Never substitute a desktop capture or another app when the emulator window is absent. The emulator may open a compiler/progress dialog separately from its game window; select the appropriate owned window and follow its replacement rather than keeping a blank game surface. Stop capture on input readiness, cancellation, child exit and route disposal; ignore late results from an earlier session. Denial, revoked access, an unavailable portal or a stalled capture must leave loading, cancellation and controller pairing usable.

Compared with this OS route, renderer injection avoids some capture permissions and could later share the in-game overlay bridge, but requires separate Metal/Vulkan/OpenGL/D3D hooks, synchronization and frame-copy checks. It also cannot show a Qt compiler dialog before the emulator creates its game renderer. Text-only phase feedback is cheaper and needs no capture permission, but does not provide the requested live view. The OS route is the recommended first experiment. Linux DBus/PipeWire dependencies and packaging still require a concrete dependency decision; no package was added for this investigation.

Primary references: Apple's [capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) and [window filter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)), Microsoft's [screen capture guide](https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/screen-capture), and the [ScreenCast portal contract](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.ScreenCast.html). This is researched API feasibility, not a claim that a live preview has been executed or shipped.

## RPCS3: persistent emulator caches, repeated MoltenVK work

The owner's private profile has `Disable On-Disk Shader Cache: false`, `SPU Cache: true` and LLVM precompilation enabled. Broomm does not clear these caches when launching or closing a game. Its private cache is currently under `profiles/<profile>/emulators/rpcs3/home/Library/Caches/rpcs3/cache/`, with additional child-scoped cache routing retained from the controller prototype. Preparation preserves existing profile files. System emulator configuration was not changed for this investigation.

A controlled native test copied the owner's RPCS3 build, firmware, private configuration and cached files to disposable storage while holding the production session lease. It launched the same encrypted **3D Dot Game Heroes** ISO/adjacent key twice with the ordinary Broomm supervisor, paused/paired/resumed and closed normally. Ordinary profile progress and caches were never passed as writable child data. The results were:

| Launch | Time to input/pause readiness | Existing PPU objects unchanged | PPU objects rewritten / added | Shader-cache files retained |
| --- | ---: | ---: | ---: | ---: |
| First cached launch | 187.220 s | 204 | 0 / 0 | 155 |
| Second cached launch | 187.395 s | 204 | 0 / 0 | 155 |

The repeated delay is real, while PPU compilation reuse is working. During the second launch, a native stack sample caught the RSX worker in `vkCreateGraphicsPipelines`, MoltenVK's pipeline/shader library creation and SPIR-V-to-MSL conversion. That is graphics pipeline work, rather than recompiling the 204 saved PPU objects.

The exact pinned [RPCS3 pipeline compiler](https://github.com/RPCS3/rpcs3/blob/d08d568d/rpcs3/Emu/RSX/VK/VKPipelineCompiler.cpp) creates its shared Vulkan driver cache with empty initial data, then destroys it without a `vkGetPipelineCacheData` serialization step. The saved RPCS3 shader/pipeline descriptions do not establish persisted MoltenVK-converted shader libraries. [MoltenVK's own guide](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md#shader-loading-time) explains that Vulkan cache export/import can preserve converted MSL and avoid repeating conversion. The observed sample agrees with that limitation. This does not establish that every Metal driver cache or every possible sandbox interaction has been audited; it does establish retained emulator files and repeated conversion in this exact macOS build.

No shader setting, cache path, driver configuration, update policy or executable was changed to hide the delay. Disabling preload can move compilation into gameplay rather than remove it. A possible future intervention is a tightly scoped Vulkan cache serialization bridge, or an explicitly selected upstream build that persists it. That experiment would need device/driver/cache-UUID and binary-build keys, size/integrity bounds, safe invalid-cache rejection, interruption-safe publication, device recreation and repeated native render/exit checks. It is not implemented here, and this research does not authorize an automatic emulator update or a new renderer library.

The test recipe is `tool/check_rpcs3_cache_test.dart`; the detailed local result is `.tool-cache/research/loading-keyboard/native-cache.json`. It excludes unreadable rotated RPCS3 diagnostic logs from its disposable copy without changing their permissions. No owner save, remote RomM asset or system cache was deleted. Cache inventories compare relative paths, byte lengths and modification times; no gameplay save-load or cross-host shader reuse is claimed.

## Controller keyboard shortcuts: implemented

The dock now displays shortcut badges alongside its ordinary keys:

| Control | Action while the keyboard is active |
| --- | --- |
| A | Activate the selected key |
| B | Dismiss, keeping typed text |
| Y | Insert space at the current selection |
| X | Backspace, deleting a whole Unicode grapheme or selection |
| Hold R2 | Shift letters and symbols for as long as held; stays active across multiple characters |
| L3 | Toggle Caps Lock; held Shift inverts the letter case of Caps Lock |
| L1 / R1 | Move the caret left/right by a grapheme |
| Start | Submit the original field and close the dock |

Native channel actions and Flutter game-key events use the same dock command handling. macOS GameController, Windows XInput, Linux evdev and Android gamepad input emit the additional actions. Held Shift is aggregated across connected controllers and released on disconnection; the Flutter dock also clears it on app focus loss and closure. Covered fields ignore typing/deletion shortcuts, but still accept the modifier's release. Physical keyboard letters retain their ordinary meaning and pointer activation still edits inline. Key accessible names remain stable while visible badges explain their controller shortcuts.

Widget regressions exercise actual field selection, length limits, multi-character held Shift, case/Shift combinations, Unicode caret/delete, submit/dismiss and modal/lifecycle behavior. Two native macOS tests use GameController snapshot devices to verify button callbacks and overlapping held triggers. Those are native API checks with synthetic devices, not physical controller acceptance. Linux/Windows/Android source paths remain unverified on native hosts. The full-suite/build evidence and retained failed experiments are in the companion JSON; [README.md](../README.md) contains the owner walkthrough and cleanup.

The complete Flutter suite passes **231 tests**. After the final presentation-only badge styling, **14 focused widget/render checks** pass, with the desktop and compact PNGs inspected. Static analysis is clean; the two native GameController tests and the two-launch cache test pass separately. The macOS release, ZIP integrity and extracted app's deep strict signature pass without a signing repair. Artifact: `build/releases/Broomm-macOS-arm64-keyboard-shortcuts.zip`, 19,342,470 bytes, SHA-256 `89332ff7d99227e1923666957f33e9dfd0c551f52f9c66594e84fd19e36b52e9`. This is the existing Apple Silicon checkout-bound development distribution, without notarization.
