# Bundled emulator delivery recipes

Updated 2026-10-27. The application already bundled a setup JSON, but its
`tested:` paths required this development checkout. The bundled
[version-2 recipes](../assets/setup/setup.json) now work without
`BROOMM_PROJECT_ROOT`. Normal supported setup now downloads every frontend and
core through the bundled recipes, with no external pack/import requirement. The
seven new official core versions and native checks are documented in
[the public-core follow-up](retroarch-public-cores.md). No host adapter is added.

## Current distribution

| Delivery | Choices | Status |
| --- | --- | --- |
| Pinned HTTPS archive from upstream | RPCS3 ARM and Intel, Azahar, melonDS, DuckStation, PCSX2, ARMSX2, PPSSPP, Eden | ✅ Fresh download, extraction and full application verification passed on macOS Apple Silicon |
| Official Dolphin DMG | Dolphin 2609 universal | ✅ Fixed signing recipe reproduces all 2,667 tested files and nine links; no companion pack required |
| Archived HTTPS release | Ryubing 1.3.3 universal | ✅ All 16 application files match the tested build; no companion pack required |
| Broomm RetroArch release | RetroArch 1.22.2 / Broomm v0.1.0, macOS ARM64 | ✅ Pinned GitHub ZIP, new executable/SDL3 hashes and complete 29-file inventory |
| Official RetroArch core ZIPs | All fifteen selected cores, including the seven previously offline inputs | ✅ Fresh HTTPS-only setup, native ABI, gameplay and scoped save/state round trips; no companion pack |
| Other desktop hosts | Existing Linux/Windows emulator adapters | ⏳ Their native packages and bridge acceptance remain pending |
| Android | External installed applications | Existing handoff is unchanged; see [Android status](android-emulators.md) |

Dolphin now uses the [official 2609 DMG](https://dl.dolphin-emu.org/releases/2609/dolphin-2609-universal.dmg),
41,965,559 bytes, SHA-256
`b8910a6f8710cbe93b916f5b3867a46e67e49aa8272657d282d4accae359cd6b`.
Its original code needs the signing preparation already applied to the tested
copy. A concrete Dart recipe signs eight fixed Mach-O files, four nested bundles
and the outer app, preserving the reviewed main entitlements and enabling the
existing bridge. This reproduces the complete original inventory, including
executable `cfbfb74e5a1c3191fb33a135ee5e258b33bff1b7a02e7d3e6d4710c0fcd8286e`.
No Go code, arbitrary imported commands, new native bridge or emulator update is
introduced. Native deep/strict/all-architecture signature verification also passes.

Ryubing's original host remains unreachable. The
[archived 1.3.3 ZIP](https://archive.org/download/ryujinx-1.3.3-stable/Ryujinx%201.3.3%20%28stable%29.zip),
70,570,489 bytes, SHA-256
`f258953e0380a9d1b332607673e413215af9683966225f8cca7f8facb4e445d4`,
contains the identical tested executable and all 16 application files. This is a
third-party archive, not an official mirror; trust comes from the full existing
inventory comparison. Extraction ignores only the exact empty regular root
`Icon\r` Finder marker. Nonempty markers, links and traversal/control names still
fail. Its signatures and original bundled notices are retained.

RetroArch now downloads the [Broomm v0.1.0 frontend](https://github.com/Broomm/retroarch/releases/tag/v0.1.0).
Its reviewed macOS ARM64 ZIP is 8,128,584 bytes, SHA-256
`a09b7284cad1672010f9baa50a05d100c3c7102889b984d6f8315fc1798d449e`.
It retains upstream revision `1b8917df23625bcf40b67ba6476d9bfb0d30dc65`
and SDL 3.4.0, with newly verified executable/runtime inventories. The recipe uses
the versioned GitHub URL and mandatory checksums. Emulator updates remain an
explicit setup action; startup does not fetch a newer frontend.

The previous custom SDL3 build (`1.22.2 / 20261001`) remains a recognized
installed build with its original inventory. It differs from the official Metal build.
The [current official nightly](https://buildbot.libretro.com/nightly/apple/osx/universal/RetroArch_Metal.dmg)
was downloaded and run with `--features` on 2026-10-27: it still reports SDL2,
and cannot replace our controller-compatible build. That inspected DMG is
247,192,157 bytes, SHA-256
`23a193be336d32b2162fa26aebd5ae1fcfd29baf5691935d18cca4141ba72944`.
PGCS's packaging audit confirmed that the earlier exact SDL3 frontend was locally
built and never published. The new release comes from the separate Broomm recipe;
its new fingerprints do not impersonate that older executable.

The seven previously offline cores now use available official Libretro builds,
with new archive/library fingerprints, embedded versions and native validation.
The other eight core libraries retain their existing hashes. Libretro's `latest`
URLs are mutable: changed bytes are rejected, with existing installations kept.
A reviewed recipe refresh or Broomm update is required if the provider replaces
an archive; the application does not accept an untested core silently. Completed
verified downloads are cached. The custom frontend release still contains no
cores, but Broomm now obtains all cores itself during setup.

The earlier private companion pack is retained under
`build/setup-packages/macos-arm64/`. It contains only the three application
archives, pinned core archives, this setup JSON and instructions. It includes no
console firmware, keys, ROMs, profile settings or progress. Existing application
notices stay inside their bundles. Its files and hashes are pinned in the bundled
manifest or the trusted build's slot-specific compatibility list, rather than
accepted from an arbitrary import. Its old Dolphin/Ryubing sources and all old
core archives still import without changing the new default downloads. A stable public mirror
and complete redistribution/source provenance need to be settled before publishing
these old snapshots. Importing its RetroArch source explicitly selects the old
frontend, with its old inventory and launch behavior.

Those earlier packs are optional legacy inputs, with their original hashes;
they are no longer part of normal installation. Use **Emulator Settings →
RetroArch → Set up/Verify setup → Start setup**. Existing old cores resolve to
their original files until explicit setup publishes a current version. Upgrades
preserve ordinary saves, settings, prior apps and old state files. New core
versions use physical state folders containing the frontend/core fingerprints,
so an old state cannot be mislabeled as compatible during cloud capture.

The explicit `devbox run -- dart tool/export_setup_packages.dart --output build/setup-packages/current-macos-arm64` recipe exports
only these allowlisted application/core inputs from the existing `prototype-data/`
cache, using macOS bsdtar's USTAR/gzip format without extended attributes, ACLs or
file flags. It requires the exact pinned archive size/hash before publication,
verifies retained archives and copies the release JSON. It never rewrites trusted
fingerprints. Archive owner/timestamp metadata can prevent reproduction on a
different source host: preserve the reviewed archives until an immutable mirror
exists. The native integration check additionally validates every extracted file
and link against the trusted inventories. No capture tool can turn an arbitrary
new build into an accepted delivery package.

## Setup contract and effects

Opening Emulator Settings or reviewing a recipe performs no download or
installation. **Start setup** takes the existing cross-process session/writer
lease, resolves the requested archives, and installs only into Broomm's managed
storage. Controller navigation and the inline review/confirmation stay intact.
The active card shows transfer progress and a reachable **Cancel setup** action.

HTTPS downloads have bounded redirects, response sizes, idle/deadline timeouts
and cancellation. They carry no RomM credentials. Archive SHA-256 and exact size
are mandatory even when the optional full game-file checksum preference is off.
Completed original downloads live in `setup-downloads/` and are freshly hashed
before reuse. Changed cache entries are preserved and cannot become installations.
Incomplete HTTP stages are removed after their writer closes. Cancellation or a
failed archive never publishes a partial emulator, changes a system installation
or deletes previous installations/profile progress.

macOS's existing libarchive CLI normalizes ZIP, 7z and compressed TAR archives
into a bounded private USTAR stream. DMGs attach read-only at a unique private
mount, acknowledge that path and detach before publication or cleanup. Dart
preflights names, collisions, sizes, entry types and confined internal links
before extracting the selected application. Files cannot be written through
archive links. If a native tool cannot be stopped, or a mount cannot be detached,
its private stage is retained rather than recursively deleted. Stale stages are
not automatically recovered or treated as evidence that a writer exited.

Reviewed DuckStation, PCSX2, ARMSX2, PPSSPP and Eden archives require local ad-hoc
signing in private staging. Dolphin uses the fixed signing recipe above. RPCS3,
Azahar, Ryubing and melonDS retain their downloaded signatures. After the
[2026-10-28 portability correction](macos-emulator-signing.md), re-signed archives
retain their pinned source identity, expected file/link structure and macOS
deep/strict/all-architecture signature validation. Their receipt records the
locally generated executable hash. They no longer require another Mac's exact
signature bytes or a separate SHA-256 comparison for every re-signed file.
Unmodified downloads and legacy extracted imports retain their existing full
inventory checks. Copied-bundle, receipt and selection readbacks remain.
Symbols, controller hooks, firmware handling, profile configuration and saves
retain their previous logical build identities. Recognized installed
applications/cores are verified and reused without source archives.

Emulator updates remain explicit. The JSON cannot introduce commands, bridge
libraries, environments, hook addresses or arbitrary executable versions.
Version-1 extracted local folders and development `tested:` aliases still work.
Version-2 `source`, `core` and `cores` accept a reviewed archive object:

```json
{
  "url": "https://provider.example/releases/pinned/application.zip",
  "sha256": "<64 lowercase hexadecimal characters>",
  "bytes": 123456,
  "format": "zip",
  "entry": "Application.app",
  "prepare": "none"
}
```

An offline archive uses `"file": "application.tar.gz"` instead of `url`.
Its path is relative to the imported JSON; default recipes look in Broomm's
`setup-packages/`. It must have the same pinned size, checksum, archive layout
and preparation as that slot in the bundled manifest or an explicitly reviewed
older delivery for that same slot in `tested-builds.json`. Imports cannot add
compatibility authority themselves or move a trusted archive into another slot. Mirrors may change the
HTTPS URL, and offline imports may select the same payload from disk. Unknown
payloads or preparation steps are rejected before effects. Resource paths remain
explicit local imports; firmware and key retrieval from RomM still occurs in the
existing per-platform launch workflow.

## Verification and reproduction

New regressions exercise real socket streaming, restart/cache reuse, same-size
cache alteration, short responses, wrong hashes, held-stream cancellation,
unsafe redirects, imported-recipe authority, a held production session lease,
local archive publication/retry, framework links, traversal, case collisions,
linked ancestors and truncated directories. Existing local imports, removal and
inline card navigation remain covered.

```sh
devbox run -- flutter test --no-pub test/setup_downloads_test.dart test/setup_archives_test.dart test/setup_delivery_test.dart test/managed_emulators_test.dart test/emulator_setup_flow_macos_test.dart
# Explicit external integration check, requires the companion archives:
devbox run -- flutter test --no-pub tool/check_setup_delivery_test.dart
```

Two complete fresh checks passed, and final interrupted-fixture recovery/reuse
passed in 1m18s on macOS 27.0.1 / Apple Silicon using Flutter
3.47.0 / Dart 3.13.0. It actually downloaded all nine upstream applications,
installed all 12 choices and all 14 additional cores from scratch with
`project: null`, then read the unmodified bundled manifest and verified/reused
every installation. It checks exact inventories and existing core fingerprints;
it does not establish new gameplay, physical-controller or cross-platform
acceptance. All effects used isolated fixture storage. Native logs and copies are
retained in `.tool-cache/setup-downloads/`; the machine-readable summary is
[managed-setup-downloads.json](managed-setup-downloads.json).

The final full Flutter suite passes **392 tests**, including the native-helper
termination/output bounds, retained signing-failure stages and cancellation
before signing begins. Signing is a bounded, non-interruptible file operation
because its allocator can also write the application; Cancel takes effect
immediately after it finishes. Abnormal signing teardown retains private staging.
Reuse also verifies the required base Snes9x core and preserves changed/missing
core data instead of treating re-setup as a silent repair.

A later repeat encountered GitHub closing the Azahar response mid-transfer.
The incomplete archive was discarded and the four completed installations were
retained. The diagnostic initially exposed a signed redirect URL; transport and
malformed-redirect errors now use safe contextual messages. Regressions cover
an abruptly closed real stream and signed-URL/TLS/timeout redaction. The retained
private fixture was resumed explicitly with
`BROOMM_SETUP_REUSE_FIXTURE=.tool-cache/setup-downloads/native-install-nJFKNB`
and the same native command; this is an observed recovery check, not an automatic
test retry. All 12 choices and 14 additional cores passed after that recovery,
including a second verification from the unmodified bundled manifest. The
redacted original failure log is retained beside the final log.

The original native gameplay/save checks now explicitly import
`tool/setup-development.json`, preserving their existing fixture inputs and avoiding
accidental network dependence. Development inventory-capture tools update that
file instead of replacing the release manifest with checkout aliases.

The source-replacement native check passes in **47 seconds** with a fresh private
data root: real HTTPS downloads of Dolphin, Ryubing and eight unchanged cores;
all 14 additional cores installed; complete inventories verified; every older
companion recipe accepted; then restart/reuse from the default manifest after
deleting the fixture's input directory. The separate Ryubing-only check also
passes without any companion input. Reproduce with:

```sh
devbox run -- flutter test --no-pub tool/check_setup_source_replacements_test.dart
devbox run -- flutter test --no-pub tool/check_ryubing_delivery_test.dart
```

The first command needs the remaining reviewed RetroArch archives under
`build/setup-packages/macos-arm64/`; it copies eight allowlisted inputs into its
own private fixture. Neither command reads or writes owner emulator preferences,
games or progress. Their logs/results live in
`.tool-cache/setup-source-replacements/` and `.tool-cache/setup-ryubing-fix/`.
The current export additionally verified all eight retained snapshot archives
with `--output build/setup-packages/current-macos-arm64`. Attempted regeneration
from the extracted app did not reproduce its archive metadata and was correctly
refused; the original reviewed bytes were explicitly copied and reverified.
No trusted fingerprint was recaptured. Preserve those original archives until
immutable distribution/reproducible packaging is available.

The fresh macOS ZIP is `build/releases/Broomm-macOS-setup-fixes.zip`,
20,346,293 bytes, SHA-256
`1233d40d8883bb5c39b1cdb29c9417eb53692ae40cb619908861322f0ca39934`.
The application and three bridges contain both ARM64/x86-64; the two bundled setup
JSON assets match the source, ZIP integrity passes, and deep/strict signatures
pass before and after fresh extraction. It uses the normal Application Support
folder with no checkout/data-root override. This is an ad-hoc local development
build with self-updates disabled; other native host verification is unchanged.

No new package dependency, compiler prerequisite, OS installation, user-data
migration or Git publication was introduced. Dart HTTP and existing macOS archive
primitives implement the workflow inside the application. The existing staged
host limitations remain explicit.


## Standalone RetroArch release adoption — 2026-10-27

The first five-target release is published. All five ZIPs, checksum files and
full manifests were retrieved and verified against the GitHub asset digests and
the packaging verifier. Broomm adopts the Apple Silicon frontend through its
existing managed-host path. Other desktop cores/bridges and native Broomm
acceptance remain separate; Android's external-app route is unchanged.
See [distribution evidence](retroarch-distribution.md) and the
[exact adoption record](retroarch-release-adoption.json).
