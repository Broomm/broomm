# Native injection experiment

This is a **macOS ARM64 research fixture**, separate from the future Flutter application. Read the [results and limitations](../../docs/research/injection-validation.md). It tests the supplied games in private emulator copies; it is not a production launcher or a complete settings overlay.

## Build and inputs

Use the repository's pinned Devbox environment and the already installed Apple command-line SDK:

```sh
devbox run probe-build
devbox run -- dart analyze experiments/injection/tools
```

No OS dependencies are installed. Builds produce `build/probe-sdl2.dylib` and `build/probe-sdl3.dylib`; only the host ARM64 ABI is supported. The generated slot metadata is committed, so fetching SDL headers is not needed to build. To regenerate it, fetch the exact two headers in [SOURCES.md](SOURCES.md) into `reference/SDL2_dynapi_procs.h` and `reference/SDL3_dynapi_procs.h`, verify their hashes, then run `tools/derive-slots.dart` through Devbox.

`artifacts/local-installations.json` is a **local, ignored input** identifying the five existing emulator bundles. Its shape is:

```json
{
  "RetroArch": {
    "bundle": "/absolute/path/RetroArch.app",
    "executable": "/absolute/path/RetroArch.app/Contents/MacOS/RetroArch",
    "sdl_major": 3,
    "sdl_library": "/absolute/path/RetroArch.app/Contents/Frameworks/libSDL3.0.dylib"
  }
}
```

The other keys are `Dolphin`, `RPCS3`, `Azahar`, and `Ryubing`. Omit `sdl_library` for the embedded SDL builds, Dolphin and Azahar. RPCS3 uses SDL3 and Ryubing uses SDL2. The existing local inventory records the tested paths. A different build requires renewed validation; this example does not certify an arbitrary replacement.

## Run a private session

Run from the repository root. First prepare the named copy:

```sh
devbox run -- dart experiments/injection/tools/run.dart prepare Dolphin
devbox run -- dart experiments/injection/tools/dolphin-config.dart
devbox run -- dart experiments/injection/tools/run.dart run Dolphin --exec "$PWD/roms/ngc/Super Smash Bros. Melee (USA) (En,Ja).rvz"
```

Other supplied game targets are:

- RetroArch: run `retroarch-config.dart`, then pass `-v -c <private retroarch.cfg> -L <existing snes9x_libretro.dylib> <roms/snes/Super Mario World (USA).sfc>`.
- Azahar: first run once to generate its private INI, then run `azahar-config.dart`, then pass the supplied Mario Kart 7 `.cci` path. The bridge queues a normal Qt close event only for Azahar's exact direct-executable startup warning. Other load errors are logged and left visible.
- RPCS3: use `--installfw=<supplied PUP path> --headless` to populate private firmware, then run `rpcs3-config.dart` and pass Rayman's `PS3_GAME/USRDIR/EBOOT.BIN` **without** `--input-config`. That flag requires `--no-gui` in this build. The tested headless firmware installation succeeded and then RPCS3 crashed during teardown; inspect the installation log before proceeding. It is not reported as a clean command success.
- Ryubing: run `ryubing-resources.dart <supplied firmware ZIP> <supplied key directory>` once. Run once to migrate defaults, then run `ryubing-config.dart` and pass the supplied Mario 3D World `.nsp`. Resource preparation uses a new, empty private target and logs no key contents. The emulator's own firmware/game loading supplies the decryption compatibility check; the fixture is not a general firmware validator.

The runner serializes sessions with an OS file lock. It copies bundles with APFS copy-on-write, selects private portable/explicit data roots, and applies a child seatbelt denying writes to original Library/settings, reference projects and ROMs. RPCS3's hardcoded macOS cache prefix is redirected into its private cache by the C bridge. Original executables, settings, ROM bytes and firmware sources are not written. App bundles, keys, firmware, ROMs, saves and generated logs are ignored by version control.

## Policies and observations

By default a run lasts 36 seconds. Set `BROOMM_PROBE_SECONDS` for first-use compilation. The sequence is passthrough → button 0/1 swap at 12s → pause request at 16s → resume at 20s → source A/B swap at 22s. The injected fixture creates two virtual gamepads **inside the emulator's own SDL runtime** and exercises button/axis values with repeated edges. It does not install an OS virtual-controller driver.

To set a policy during a longer run:

```sh
devbox run -- dart experiments/injection/tools/control.dart rpcs3 2 1 1
```

The final three numbers are input mode (0 passthrough, 1 swap buttons, 2 swap controller sources), show panel (0/1), and desired pause (0/1). These are native actions for Dolphin/Azahar/RPCS3; Ryubing uses its configured F5 hotkey through its own AppKit window. For RetroArch use `retroarch-command.dart GET_STATUS PAUSE_TOGGLE GET_STATUS` against the private command port; the control file does not pause RetroArch.

Inspect `sessions/<name>/probe.log`, `process.log`, and the emulator's private logs. `QUERY` records actual emulator call sites, `SELF_CHECK` checks the injected fixture, `EVENT path=watch` traces callback delivery, and native state/title readback establishes pause. A standalone fixture self-check is insufficient without real emulator queries/events. Logs include PIDs; archived logs preserve earlier failures. The overlay is an AppKit child view, with `OVERLAY_ATTACHED` and `OVERLAY_DRAW` evidence. It has no production navigation, input capture or settings controls.

After preparing all five fixtures, `check-games.dart <existing Snes9x core path>` runs their supplied ROMs sequentially. `capture-evidence.dart` checks each latest log and writes the sanitized JSON evidence beside the findings. It returns a failure status for missing native calls, missing changed results in either mapping mode, failed fixture checks, missing pause/resume readback, missing draws, mixed PIDs or differing private/original executable hashes. Native probe segments rotate at 1 MiB and retain the current segment plus nine older segments.

The runner terminates test copies after the observation window, escalating if necessary, and closes private RPCS3 error children. These forced stops concern disposable fixture saves; this is **not** the final game's save-safe shutdown implementation. Stop a queued runner before deleting fixtures. Cleanup is deletion of `sessions/`, `build/`, `artifacts/` and `reference/` under this experiment directory, after its processes have ended. Keep the small source files and committed ABI metadata.

Physical-controller gameplay, menu visibility above every renderer/fullscreen mode, controller-only navigation, hotplug during held buttons, Steam Input/Linux, macOS hardened stock distributions, Windows and Android are not acceptance claims of this fixture.
