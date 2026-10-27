# Automatic RetroArch core setup — 2026-10-27

Normal setup now needs only Broomm and an internet connection. The bundled
recipes download all twelve managed emulator frontends and all fifteen selected
RetroArch cores. Users do not need a companion pack, developer checkout, local
archive or setup JSON import. Optional custom/offline imports remain available.
The existing managed-emulator host boundary is macOS Apple Silicon; this change
does not claim native Linux/Windows core/bridge acceptance or Android parity.

The seven previous offline dependencies have available official
[Libretro macOS ARM64 downloads](https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/).
Their archive/library SHA-256, transfer size, embedded native version, architecture
and system-only runtime dependencies were inspected before adoption:

| Core | Downloaded native version | Affected routes |
| --- | --- | --- |
| FinalBurn Neo | v1.0.0.03 / GIT32958a8 | Arcade |
| Flycast | 1b63c8a | Dreamcast |
| Gambatte | v0.5.0-netlink / 7809bb6 | Game Boy / Game Boy Color |
| Genesis Plus GX | v1.7.4 / 60bee4c | Mega Drive, Master System, Game Gear |
| Beetle Saturn | v1.32.1 | Saturn |
| Opera | 1.0.0 / 370d9a2 | 3DO |
| Virtual Jaguar | v3.10.0 / ffea7893 | Jaguar / Jaguar CD (game verification deferred) |

The other eight core libraries keep their existing hashes. Original source
repositories, licenses and firmware requirements remain in
[the core inventory](../assets/setup/retroarch-cores.json). Broomm downloads core
libraries during setup; they are not embedded in its app ZIP. The custom
RetroArch frontend still downloads from Broomm/retroarch v0.1.0.

Libretro's `latest` URLs can change. Each accepted version has a pinned archive
and library fingerprint; unexpected provider bytes fail without replacing an
installed core. An updated Broomm/setup recipe is needed when those URLs change.
This limitation no longer sends users to a manual companion pack. The validated
download cache can be reused. No OS package, runtime service or new Dart dependency
was introduced.

## Installation and upgrades

1. Open **Emulator Settings**, select **RetroArch → Set up/Verify setup**.
2. Review that card, then **Start setup**. The frontend, Snes9x and fourteen
   additional cores download, verify, extract and publish automatically.
3. Existing installations still launch with their previous recognized core bytes
   until explicit setup publishes a current version. Cancellation or a rejected
   binary retains the previous usable core. Publication is private and OS-locked.
4. Settings and ordinary native saves stay in the same profile/game/core folders.
   The seven changed builds use state directories containing the actual frontend
   and core hashes. Their cloud state identities use those same build inputs.
   Existing old states are retained and cannot be captured as new-build states.
5. **Remove emulator** removes the owned frontend and recognized core versions;
   profile saves, state folders, settings and downloaded games remain. Original
   reviewed local packs remain optional legacy inputs, not installation prerequisites.

Development/native checks use private directories under `.tool-cache/` and leave
`prototype-data/` and owner progress unchanged. Remove disposable test directories
only after their writers exit. Keep normal Broomm data to preserve installed games,
credentials and progress; do not delete live lock files.

## macOS running icon

The owner saw the infinity icon in Finder but a missing/wrong running Dock icon.
The previous package has the correct `AppIcon.icns` and generated icon metadata;
there is no explicit icon override in the previous startup code. The exact
Launch Services/cache trigger was not reproduced, so a cache cause is not claimed
as proven. Source icon keys are now explicit, and native startup reads its own
bundled ICNS and assigns `NSApplication.applicationIconImage` directly.

Native tests replace the running image with a placeholder and verify the restored
infinity artwork, and verify that a missing resource preserves the existing icon.
AppKit converts the source 8-bit ICNS to a color-managed 16-bit representation.
Diagnostic native images show the same artwork with about 0.6% mean channel error;
the comparison bounds rendered error to 1%, instead of requiring TIFF or pixel
byte equality through that conversion. The original strict-comparison failures
and images are retained. Actual Dock appearance still needs owner confirmation;
no UI automation or system icon-cache changes were performed.

## Verification and delivery

The targeted 55-case suite covers core upgrade/restart, failed publication,
cancellation/retry, retained ordinary data, physically separate state builds,
removal, archive validation and download boundaries. Live setup/ABI checks use
only the bundled HTTPS recipes with no local source files. Native gameplay checks
exercise thirteen supplied games, then Lynx/Saturn/3DO/Dreamcast save/state paths.
Separate Genesis/Master System/Game Gear/Arcade native save fixtures check the
changed save-capable cores against a local RomM fixture server. These are native
automated checks, not physical-controller, every-game or cross-device acceptance.

```sh
devbox run -- flutter test --no-pub test/retroarch_core_upgrade_test.dart test/setup_delivery_test.dart
devbox run -- flutter test --no-pub tool/check_setup_source_replacements_test.dart tool/check_retroarch_cores_test.dart
devbox run -- flutter test --no-pub tool/check_retroarch_play_test.dart
BROOMM_SAVE_PLATFORMS=3do,dc,saturn,lynx devbox run -- flutter test --no-pub tool/check_retroarch_saves_test.dart
BROOMM_SAVE_PLATFORMS=genesis,gamegear,sms,arcade devbox run -- flutter test --no-pub tool/check_retroarch_saves_test.dart
# Native app/icon checks, using a private data root:
devbox run -- bash tool/build_app.sh --portable --dart-define=BROOMM_DATA_ROOT="$PWD/.tool-cache/retroarch-public-cores/native-app-data" --no-pub
devbox run -- bash tool/test_macos.sh
```

See the [exact hashes, commands, retained failures and native results](retroarch-public-cores.json).
The [current macOS ZIP](../build/releases/Broomm-macOS-automatic-cores.zip) uses normal
Application Support storage. Install/open this app and confirm the running Dock
icon, then set up RetroArch directly from its card. Local development self-update
remains disabled. No ROMs, BIOS, keys, progress or emulator payload are embedded.
