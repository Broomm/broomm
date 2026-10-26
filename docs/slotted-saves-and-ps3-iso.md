# BROOMM save history and encrypted PS3 discs

Implemented 2026-10-22. This supersedes the public single-file contract in [the original cloud-save milestone](cloud-saves.md). Product requirements are in [PROJECT.md](../PROJECT.md); UI actions, prerequisites and cleanup are in [README.md](../README.md#verify-managed-cloud-saves). Machine-readable verification is in [the companion record](slotted-saves-and-ps3-iso.json).

## Public saves

Automatic synchronization appends versions in the current account/game's exact `BROOMM` slot, under emulator `Broomm`. Names are `Broomm [yyyy-mm-dd_hh-mm-ss].ext`. Broomm sends `Broomm.ext` and lets RomM reserve the timestamped filename. The latest creation timestamp wins, with numeric ID as a deterministic tie break; listing order does not establish recency. Duplicate version filenames block sync. Other slots, names and accounts are excluded from automatic content access.

| Native adapter | Public ordinary save | Contents |
| --- | --- | --- |
| melonDS | `.sav` | Original raw DS save bytes, without compression or Broomm metadata |
| RetroArch/Snes9x | `.srm` | Original SRAM bytes |
| Dolphin/GameCube | `.zip` | Matching title's GCI files; preserve A/B area names when needed |
| Dolphin/Wii | `.zip` | Current disc title's native data directory |
| Azahar | `.zip` | Native title data/metadata and verified extdata areas |
| RPCS3 | `.zip` | Current title-ID-prefixed savedata directories |
| Ryubing | `.zip` | Verified committed account save and matching device save areas |

These directory ZIPs contain native files, not the internal `broomm.json` manifest. Logical area prefixes are retained for multifolder exports so import can distinguish cards, extdata and device data. Local immutable recovery bundles retain inventories, identities, ancestry and state compatibility data. Unknown native formats still fail rather than guessing conversions.

The reported Pokémon Ranger discrepancy was the old compressed wrapper: its remote `broomm` asset was 46,523 bytes, while the contained native save was 262,144 bytes. The new public `.sav` is exactly 262,144 bytes. The old asset is retained read-only. When no BROOMM history exists, a verified legacy asset can supply progress and migrate into a new native version; new writes never replace it.

**Use existing save file** still requires explicit source selection and appends a fresh BROOMM version without modifying the source. **Backup savefile** creates an independent unslotted asset, adding the native extension; a full backup containing states uses `.zip`. Name collisions are refused and interrupted backups retain their original checkpoint. Automatic synchronization never adopts a named backup on its own.

## States, retries and conflicts

Supported states retain the existing verified emulator/core/build/host groups. With an ordinary native save, the full recovery/provenance bundle is published as a separate RomM **state** asset named with that version's same stem and timestamp and `.zip`. The ordinary `.sav`/`.srm` remains usable by native consumers. A state-only snapshot before the first ordinary save uses a correctly named `.zip` primary version. RPCS3 and Ryubing states remain unsupported.

Durable upload checkpoints resume a missing or unacknowledged state companion for the same primary version. Its contents, snapshot identity and ordinary save digest must match before acknowledgment. A lost companion response is reconciled without uploading either asset twice. A changed local snapshot is pinned before pruning for a subsequent version; completing an older upload preserves a newer crashed session's review flag. A newer remote head observed during finalization prevents acknowledgment of a stale head. Archive-only retry can export and verify retained progress after ROM/emulator uninstall without accessing native save paths.

Publication of a primary and its companion is not an atomic server transaction. Another device can observe the primary while the companion is pending; local recovery and incomplete-transfer errors remain important. A lost primary response with states, an intervening writer or an incompatible companion can require explicit conflict review. Do not claim that arbitrary simultaneous external writers or state loading on another device have been verified. Ordinary native files do not carry the old bundle's causal ancestry; conflict decisions use the acknowledged content baseline and retained append-only versions. Existing unknown local states remain protected by the preceding provenance rules.

New sync never sends a PUT to an old save ID or automatically deletes remote saves. For a **slot POST**, `overwrite=true` disables RomM's content-hash deduplication after the server reserves a fresh timestamped filename. Without it, changing only a save state could reuse an older primary version with identical ordinary save bytes and collide with that version's state companion. This flag is confined to BROOMM slot creation; unslotted backups use `overwrite=false`. `autocleanup=false` prevents client-requested pruning; server administrator retention limits still apply.

The live RomM 5.4 instance exposed a separate precision issue: fresh POST returned `updated_at=...28.412392+00:00`, while GET returned `...28+00:00` for the same record. The transport now obtains the persisted record after upload and accepts only whole-second truncation of that timestamp with all identity, filename, size, checksum, location and missing-file fields unchanged. Actual timestamp/content/identity changes still fail. Subsequent transfer revision checks remain exact.

## PS3 ISO and adjacent keys

The pinned RPCS3 already supports ISO boot and native adjacent-key lookup. The launcher previously filtered out `.iso` candidates and assumed metadata existed as an extracted PARAM.SFO. It now selects ISO images, inspects their ISO9660 directory metadata read-only and resolves `PS3_GAME/PARAM.SFO` plus `PS3_GAME/USRDIR/EBOOT.BIN` without extracting or mounting the disc. Bounds, dual-endian fields, duplicate paths and truncation are validated. The same title reader supplies savedata and add-on matching.

Game downloads already consume every file in a verified manifest. The ISO and its adjacent `.dkey` therefore retain their names and directory together; a regression now verifies this complete download path. Preparation validates the native sidecar format: 16 binary bytes or 32 hexadecimal characters with optional CR/LF. RPCS3 also supports the matching `.key` fallback. Broomm passes the original ISO path; RPCS3 finds the adjacent key internally. Key contents never enter argv, environment, diagnostics or error messages. A decrypted ISO can boot without a sidecar. Missing manifest entries require rescanning/fixing the owner's RomM catalogue, rather than fetching keys from another source.

## Evidence and sources

Native macOS arm64 RPCS3 validation booted the owner's encrypted **3D Dot Game Heroes** ISO (BLUS30490) with its already downloaded `.dkey`, reached paused input readiness, applied a synthetic joined controller, resumed, paused again and exited normally. The first boot compiled for approximately four minutes. This proves native ISO/key consumption and the pause/pair lifecycle for that exact build; physical input, gameplay savedata, DLC/PKG and other native hosts are separate checks.

The native file check uses isolated copies of existing progress and the supplied ROM identities. Native exports round-trip byte-for-byte for SNES, GameCube, Wii, 3DS and Pokémon Ranger DS; the PS3 fixture validates identity but has no gameplay save. A real RetroArch session checks writer shutdown and session lock ownership through fixture-server finalization. Switch's separate native check covers its committed/working save boundary and ZIP import. No fixture restores into the owner's normal native profile.

The authenticated live check used the production explicit-copy and sync workflows with an isolated copy of Pokémon Ranger's native progress. It appended `Broomm [2026-10-22_21-02-02].sav` (ID 61), slot `BROOMM`, 262,144 bytes, and verified downloaded SHA-256 equality. All nine preceding assets remained unchanged, including the six existing `autosave` files, legacy `broomm` and two native versions retained from diagnosing the POST precision issue. A repeated identical upload also established the server's deduplication behavior. No previous asset was deleted. The final ordinary sync acknowledged equality without appending another version. Source credentials were handled through the existing native secure-store adapter and never logged; normal OAuth refresh can rotate the remembered token.

Primary references:

- [Argosy native filename selection](https://github.com/rommapp/argosy-launcher/blob/98562a1e7c6679eaa1edf91ce440655479520eaa/app/src/main/kotlin/com/nendo/argosy/data/repository/SaveSyncApiClient.kt) and [slot upload](https://github.com/rommapp/argosy-launcher/blob/98562a1e7c6679eaa1edf91ce440655479520eaa/app/src/main/kotlin/com/nendo/argosy/data/repository/SaveUploader.kt). Its raw-extension/directory-ZIP convention informed the public format; no Kotlin code or new dependency was imported.
- RomM 5.4.0 [save endpoints](https://github.com/rommapp/romm/blob/5.4.0/backend/endpoints/saves.py), [version-name reservation](https://github.com/rommapp/romm/blob/5.4.0/backend/handler/asset_store.py), and [state endpoints](https://github.com/rommapp/romm/blob/5.4.0/backend/endpoints/states.py).
- Pinned [RPCS3 ISO/key reader](https://github.com/RPCS3/rpcs3/blob/d08d568d/rpcs3/Loader/ISO.cpp). Only the existing RPCS3 binary performs decryption; this change adds no AES implementation, native component or dependency.

Executed logs, exact sources/build hashes, release verification and retained failed experiments are listed in the companion JSON. Linux, Windows, Android, cross-device gameplay and physical controller acceptance are not established by these macOS checks.

The final complete Flutter suite passes **228 tests** and static analysis reports no issues. Four separately named native checks cover encrypted PS3 boot, copied file/export restoration, RetroArch finalization and Switch save consumption/export; the authenticated DS server check is a fifth integration check. These are scoped checks, not 233 gameplay validations.

Release: `build/releases/Broomm-macOS-arm64-save-history.zip`, 19,318,164 bytes, SHA-256 `fb093a5374b6d57fc06d7a225988c99bdbaec5552a89b6177fc991a5c6ad67c1`. The release build, ZIP integrity and extracted app's deep strict signature pass. As in the prior incremental build, the generated outer seal referenced the earlier App.framework; the inner framework verified, and refreshing the outer ad-hoc signature with existing Release.entitlements corrected it before packaging. This is the existing Apple Silicon checkout-bound development distribution, without notarization or new emulator installations.
