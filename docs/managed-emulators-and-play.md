# Managed emulators and Home play

The following records the original managed-play milestone. The current pack also includes [melonDS/cloud progress](library-and-progress-followup.md), [RetroArch/Wii/Switch expansion](retroarch-wii-switch.md), [DuckStation/PCSX2/ARMSX2](playstation-support.md) and [PPSSPP/Eden](psp-and-eden-support.md). Consult the [current matrix](platform-support-matrix.md) for implemented routes and remaining limits.

Updated 2026-10-17. This slice connects the existing RomM download library to the five tested native emulator integrations. It does not implement save sync or change the wider product roster. Automated native checks use the supplied ROMs and explicit synthetic SDL sources. Physical gameplay, owner-authenticated RomM transfers and Steam/gamescope acceptance remain separate.

## Implemented behavior

Home → Emulator Settings lists all server platforms with supported emulator cards and an empty-state message for unsupported systems. **Set up** or **Verify setup** expands review inside that card; **Start setup** performs the installation. **Import setup JSON** selects sources and opens a matching card's review. Merely opening the screen or reading JSON changes no installation. The first pack imports extracted local copies of the builds previously tested in this checkout. It copies only the app bundles, Snes9x core and selected firmware/keys. Prototype preferences, saves and console accounts are not imported. The [follow-up](remembered-signins-and-platform-settings.md) records default routing, navigation and managed removal; the 94-test/six-ROM results below remain the earlier milestone's evidence.

Setup verifies every bundled file and internal link against trusted application inventories, checks the core hash, stages privately, verifies the copied bundle, writes/readbacks a receipt and atomically publishes the release and selection. Existing unrecognized folders or modified binaries are preserved and reported. Completed earlier items survive cancellation or a later batch failure. Retry reuses a recognized release; missing resource slots can be added without overwriting existing slots. Cancel takes effect at bounded file-operation boundaries, so a current copy/hash may finish first. The same coordinator/native writer leases exclude setup during gameplay, including a surviving emulator after its launcher exits. No lock files are deleted to bypass ownership.

Home tiles and completed Store downloads offer **Play** for SNES, GameCube, Wii, PS3, 3DS and Switch. Broomm validates the owned receipt and regular content files, resolves the server's platform slug, then chooses an entry file. Multiple supported files show a controller-navigable chooser. Unknown platforms remain browsable. PS3 requires an extracted `PS3_GAME/USRDIR/EBOOT.BIN`; packed folders are not extracted by this slice. SNES ZIP uses RetroArch's existing reader; other adapters require their listed native formats.

The selected server/profile stays fixed for the session. Broomm verifies the managed binary/core before preparing private configuration. The new route explicitly displays loading until the child confirms game/input readiness and pause, then presents large live controller testers in the console shell's colors, typography and cards. It preserves progressive slots, Wii type thumbnails, motion, join/hold gestures, both face-pair swaps, R3+Select menu and disconnection handling. Closing or failing a game returns to Home after its process exits. A still-live writer retains the lock and shows an actionable error.

## Build pack and ownership

| Integration | Pinned build | Playable formats in this slice |
| --- | --- | --- |
| RetroArch / Snes9x | 1.22.2 / 20261001, core 1.63 | SNES: sfc, smc, zip |
| Dolphin | 2609 | GameCube: rvz, iso, gcm, ciso; Wii: rvz, iso, wbfs, wia |
| RPCS3 | 0.0.42-20031 d08d568d | Extracted PS3 boot executable |
| Azahar | 2126.1.2 | 3DS: cci, 3ds, cxi, app |
| Ryubing | runtime 1.3.3 | Switch: nsp, xci, nro |

This pack is **macOS arm64 only**, matching the tested bridge/symbol/runtime assets. Linux, Windows and Android display their missing-package limitation. Android's eventual external-app handoff retains its simpler scope. Other RetroArch cores and the remaining roster need their own configuration and native evidence.

Development root is `broomm-data/`; packaged builds use the existing platform-specific application root. Shared releases are `emulators/<emulator-id>/<executable-sha256>/`; selections are `emulators/selected.json`. Private data is `profiles/<profile-id>/emulators/<emulator-id>/`. Profile IDs already incorporate server/account identity. The existing lab continues to use `prototype-data/`, independently.

RetroArch writes saves/states to the private profile's `saves/` and `states/`. Dolphin uses its private `user/`. RPCS3 uses `portable/`, reached through a Broomm-created link in that profile's private HOME; icons and supplied firmware are copied there. Azahar consumes `home/Library/Application Support/Azahar/`, including its actual config, NAND, SDMC and states. Ryubing uses private `user/`, with a new profile-derived console account, copied firmware/keys and generated controller config. Desktop children have a scoped write-denial policy allowing their private runtime, system temporary storage and the native writer lock. No system/default-user emulator configuration is used or edited. This development sandbox policy is not a production security/signing claim.

Firmware/key slots are user-provided: RPCS3's extracted `dev_flash`, Ryubing's installed `registered` firmware folder, `prod.keys` and optional `title.keys`. Their structure is checked; they are not downloaded, shipped or treated as vendor-authenticated firmware. Required missing resources are visible before play. These integrations retain each emulator's native save/state limitations; no cross-device state compatibility or state support in RPCS3 is implied.

## Version-1 local setup JSON

See [the bundled default](../assets/setup/setup.json). For an independent local source, import a JSON file containing, for example:

```json
{
  "schema_version": 1,
  "host": "macos-arm64",
  "launchers": {
    "dolphin": { "source": "/path/to/Dolphin.app" },
    "rpcs3": {
      "source": "/path/to/RPCS3.app",
      "resources": { "ps3_firmware": "/path/to/dev_flash" }
    }
  }
}
```

Paths may be absolute or relative to that JSON file. `tested:` aliases resolve the existing checkout's prepared copies. Sources must match the trusted build inventories. Setup files cannot supply commands, environments, bridges or hook addresses. The UI supports inline typing or controller keyboard entry of the JSON path.

Remote URLs/archives, an in-app manifest downloader, arbitrary newer builds and system-executable selection are **not implemented**. A newer setup file can only select compatible trusted assets; new binary versions require reviewed inventories, symbols and native bridge evidence. A manually replaced binary is detected and retained, with play blocked until that integration is validated. This is an initial local provisioning slice, not the complete future update/distribution pipeline.

The [capture tool](../tool/capture_tested_setup.dart) is development-only: it derives inventories/hashes/symbol metadata from the exact reviewed copies. It must never be run automatically to trust a user's replacement binary. `assets/setup/` contains metadata only; no emulator, ROM, firmware or key payload is shipped there. Existing source/license references are in [the injection source record](../experiments/injection/SOURCES.md), [native bridge documentation](../native/README.md) and the retained notices inside imported app bundles. No new Dart package or Go helper was added. Runtime copy/hash operations use existing macOS tools; compilers and `nm` are development tools, not setup prerequisites for packaged users.

## Verification and corrections

The machine-readable [evidence record](managed-emulators-and-play.json) identifies commands, host, source fingerprints and limitations. The analyzer and 94 regular Flutter tests cover managed publication/restart/reuse, modified binaries and escaping links, cancellation/retry, lock exclusion, corrupt selections, private profiles, missing/redirected progress roots, platform/entry identity, measured RetroArch status variants, readiness gating, failure return and narrow/desktop pairing layouts. Native checks additionally run all six supplied ROMs through actual managed binaries, same-runtime synthetic pads, pairing, pause/play, live remap and normal shutdown; new 3DS/Switch profiles also pass. A fixture RomM account downloads the provided SNES bytes under a different filename, then exercises Home Play and pairing through the real app route and returns to Home. This is real native execution with a fixture catalogue, not an authenticated test of the owner's server.

Initial failures were retained and investigated:

- RetroArch's measured `GET_STATUS` reply omitted the optional CRC field. Readiness now accepts both measured formats and requires the exact launched ROM stem, removing the old fixture-title assumption.
- Fresh RPCS3 profiles needed first-run UI defaults, its actual private HOME lookup and UI icons. The adapter disables the native update check. Cold shader/PPU initialization exceeded six minutes; the native harness bound was increased to ten minutes only after logs/sampling established continued compilation. Loading remains explicit. The final retained-profile six-ROM suite took about 3m32s; this does not establish fast cold PS3 startup.
- Azahar on macOS ignored the initially seeded `user/config/` and read private HOME instead. A process sample showed its close-confirmation dialog, and actual writable files identified the effective path. Configuration/mappings now target that path and preserve its progress. The isolated failed fixture resisted normal close and SIGTERM; only that test child was forcibly cleaned up after its data/logs were retained. Interactive Broomm has no force-kill recovery path. Subsequent native checks close normally.
- Ryubing's generated DRAM enum representation was corrected before native validation. New profiles receive no copied prototype account or saves.
- Widget harnesses must advance frames/session polling alongside real I/O; indeterminate loading cannot use `pumpAndSettle`. Narrow-window card/button rows now wrap. Test-only session injection enables synthetic sources explicitly; production `main` does not enable them.

Rendered setup and pairing artifacts are under `.tool-cache/research/managed-play/previews/`. They were inspected as widget PNGs, not through computer-control tools. Native input reads do not prove physical game actions, motion feel, focus/fullscreen or Steam/Gaming Mode behavior. The overlay is still the existing external macOS Flutter surface, not a newly implemented in-renderer/gamescope overlay.

## Walkthrough and cleanup

Use [README.md](../README.md) for the normal setup/play actions, prerequisites and commands. Builds produce `build/macos/Build/Products/Debug/broomm.app`. Native smoke artifacts and isolated private profiles are in `.tool-cache/research/managed-play/`; the app's ordinary data stays separate. After all fixture emulator processes have exited and released their locks, deleting that research directory removes only its copied binaries/fixture saves/logs. Keep it to retain test progress/caches. Never remove the app's `profiles/` to uninstall a managed executable, or delete a lock while a writer is alive.

Still pending: remote provisioning recipes, the rest of the emulator roster, system-executable selection, full offline profile activation, save-unit manifests/recovery journals, RomM save/state sync, renderer overlays and native Linux/Steam/Windows/Android validation. Secure credential persistence is now implemented separately in the [follow-up](remembered-signins-and-platform-settings.md). No automatic update, OS dependency installation, source-emulator mutation or remote progress write was introduced.
