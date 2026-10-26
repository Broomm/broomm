# Home artwork and local game deletion

Updated 2026-10-19. This implements the owner's sequential SteamGridDB artwork pickers, layered Home backgrounds and title options. The owner explicitly selected **remove downloaded files/artwork while keeping saves and save states**. Earlier navigation, managed-emulator and authentication evidence remains separate. Exact tested source/build fingerprints and command outcomes are in [the evidence record](home-artwork-and-deletion.json).

The subsequent [catalogue/Home follow-up](catalogue-and-home-refresh.md) adds the optional third logo step, larger uncaptioned Home icons, footer profile controls and timed top-left notification cards. It supersedes the corresponding two-step layout descriptions in this historical record; deletion and credential ownership are unchanged.

## User flow and ownership

Configure **Broomm settings → SteamGridDB API key** using a key from [SteamGridDB API preferences](https://www.steamgriddb.com/profile/preferences/api). A mapped download also offers configuration inside its first picker when no usable key is available. The key is profile scoped and stored in an independent `sgdb-<profile-id>` native secure-store entry, bound to server URL and remote user ID. It cannot replace the RomM refresh/client token. It is never saved in account settings, artwork records or logs. Removing the SGDB key leaves the RomM sign-in and existing local artwork intact.

After a verified mapped game finishes downloading, the app opens two sequential dialogs: **Choose a square icon**, then **Choose a background**. Square icons come from PNG grids, backgrounds from heroes. Choose by pointer or controller/keyboard activation. Galleries page through at most 50 results at a time and replace previous previews. Artist names are displayed. Full-size images are downloaded and decoded/checked before accepting the selection. Games stay installed if artwork is skipped, cancelled, unavailable or invalid.

Keep current icon advances to the hero step. Cancelling the first dialog ends the workflow. Cancelling the hero step keeps any newly selected icon and the prior hero. Each asset falls back independently: no custom icon uses the existing cropped RomM poster; no hero leaves the existing Broomm atmosphere. Explicitly disabling artwork hides the selected images without deleting them. No mapping means no automatic picker; manual Select Artwork explains the missing mapping. It refreshes game details, so a new mapping added in RomM works without redownloading.

The hero fills the top 75% of the application screen, with `BoxFit.cover` and top-center alignment. It scales/crops rather than stretching. A bottom alpha fade exposes the original atmosphere, which is still painted beneath the image and across the rest of the screen. The chosen square image is the **Home game tile** icon; the operating system's Broomm application icon is unchanged.

Hover or focus a Home game and press **Select / View / Back** for exactly two menu actions: **Select Artwork** and **Delete**. Pointer uses right-click or Options; touch can long-press. Keyboard uses the context-menu key or Shift+F10. The menu focuses the selected title before opening and restores selection afterward, including mouse-hover activation. Deleting the selected item returns focus to a valid remaining Home item. Windows XInput Back, Linux BTN_SELECT, Android BUTTON_SELECT and macOS GameController buttonOptions route to the shared intent. Physical-controller behavior on these hosts remains a separate acceptance check.

Downloads and artwork are shared per server/game; another eligible profile sees the chosen local images without needing an SGDB key just to display them. Each profile's SGDB credential remains separate. No remote RomM metadata/artwork is edited and no RomM token is sent to SteamGridDB or its CDN.

## API and dependency decision

The captured RomM 5.4.0 schema exposes nullable integer `sgdb_id` on ROM details/list entries. Its [tagged search endpoint](https://github.com/rommapp/romm/blob/5.4.0/backend/endpoints/search.py) covers metadata/cover search, not a hero-list proxy. Broomm therefore uses the existing mapped ID with a separately authenticated SGDB client. It does not search by title, infer another game identity or extract the server's private provider key.

The [official SGDB contract](https://www.steamgriddb.com/api/v2) specifies bearer authentication and separate grids/heroes endpoints. Broomm requests square `512x512,1024x1024` PNG grids and static heroes, with explicit page/limit parameters and the provider's default content exclusions. Response entries are checked for kind, dimensions, image type and allowed CDN address. The downloaded public OpenAPI file and tagged RomM source are retained with fingerprints in `.tool-cache/research/home-artwork/`.

No package or OS dependency was added. The existing Dart `HttpClient`, Flutter image codecs and native credential adapters remain the runtime dependencies across desktop and Android. There are no additional native architectures, helper services, license notices or build tools to ship for this feature.

| Alternative | Tradeoff considered | Outcome |
| --- | --- | --- |
| Existing SDK transport | No new transitive/runtime assets; works with the current four target hosts/architectures. Broomm owns two endpoints, cancellation, bounds, redirects, validation and tests. | Used, extending the existing transport choice. |
| [`http`](https://pub.dev/packages/http) | Maintained Dart-team BSD-3-Clause package with composable clients and abortable requests on the IO implementation. Adds a package/transitive dependency graph but would still need Broomm's image, identity, storage and failure policy. No native helper is required by its ordinary IO client. | Reviewed; not introduced for two GET endpoints. |
| [`dio`](https://pub.dev/packages/dio) | MIT package with cancellation/interceptors/progress and broader facilities. Larger dependency/API surface and maintenance/distribution audit; its general facilities do not supply safe image publication or game ownership. | Reviewed; not introduced. |
| RomM server proxy | Would keep SGDB authentication on the server, but the selected 5.4.0 wire contract does not expose the required hero catalogue. | No unverified proxy endpoint invented. |

The SGDB HTTP owner is separate from RomM. Only SGDB API requests receive the SGDB key; CDN requests receive no credential. Production media addresses are HTTPS on the known SGDB CDN hosts; redirects, unsupported response types and oversized data fail explicitly. JSON is bounded to 2 MiB, previews to 1 MiB and full images to 24 MiB. Pixel/dimension checks bound decoder work; the selected image must match the returned dimensions, and icons must actually be square PNGs. Requests have twenty-second deadlines and four connections per host. Closing a page/popup cancels its request group without cancelling the next dialog. A timed-out connection cannot later start its request. No automatic retry or fallback to plaintext keys is added.

API errors, key failures, malformed responses and confirmed-empty galleries remain distinct. Retry, key configuration, keeping the current image and cancellation stay reachable. Artwork errors do not undo the completed download or delete prior choices.

## Local publication and deletion recovery

Artwork lives with the shared game under `library/<server-id>/<rom-id>/artwork/choice-*/`. An atomic `artwork.json` record selects immutable icon/hero files and stores SGDB IDs, authors, source URLs and format/dimensions. New files are staged privately, flushed and published under the library OS lock. Updating only one image retains the other; prior recognized files are cleaned after publication, while unrelated additions are preserved. Broken optional art leaves a usable ROM with fallback and a visible library warning. No save root is read or modified by artwork selection.

Delete is explicit and confirmed. It holds the session/writer exclusion lease and the library OS lock, verifies server/game identity and rejects unrelated top-level files or conflicting public/cleanup folders. A durable `.deleting-<rom-id>.json` intent is published and read back **outside** the game tree before withdrawal. The game moves into `.deleting-<rom-id>/`, its content/artwork is removed, then the external checkpoint is removed. Recursive cleanup does not follow links and never receives a profile or emulator path.

The external checkpoint survives partial cleanup even if the inner receipt is gone. The loader exposes pre-rename intent, partial cleanup and marker-only final cleanup as a pending deletion. The same Delete action finishes it; play, new artwork and redownload are blocked until cleanup completes. Invalid/foreign checkpoints and identity conflicts preserve files with an error. A lost successful-deletion acknowledgement is idempotent. Process-interruption states are tested; full directory-fsync/power-loss durability is not claimed.

Deletion removes the shared local game and chosen artwork for all profiles on that server. Saves, states, emulator configuration, original source bundles, other games/servers and all remote RomM files remain. Reinstalling can reuse the retained profile data. This is independent of managed-emulator uninstall and does not implement progress synchronization.

## Verification and build

Analysis and **149 Flutter tests pass** on the final source. New checks cover real loopback HTTP filters/authentication isolation, response bounds, scoped cancellation, malformed catalogues, secure-key isolation, artwork persistence/replacement, corrupt optional metadata, active and independent-process writer locks, conflicting identities, interrupted deletion phases, invalid checkpoints, all progress preservation and both real widget picker/menu flows. The gallery-page test selects via controller after paging; pointer hover and Select, cancellation, confirmed deletion and retained title focus use the actual app shell.

The renderer uses generated PNG fixtures, real Flutter widgets and local file decoding. It drives real I/O and frames together, asserts a decoded hero is painted, and captures both pickers, desktop/compact Home, the key setting and title options. All seven PNGs under `.tool-cache/research/home-artwork/previews/` were inspected. These are offscreen artifacts, not computer-control or owner-performed observations. A fixture RomM download of the supplied SNES ROM also passes actual managed RetroArch loading, pairing, gameplay and normal return to Home. Existing bridges/emulator settings were not changed; no new six-emulator run is claimed.

Four native macOS tests pass, including an SGDB Keychain slot that can be written/read/removed without changing the paired RomM slot. The release app builds and both the built and ZIP-extracted bundles pass `codesign --verify --deep --strict`; ZIP integrity also passes. The launcher binary is universal x86_64/arm64, but the tested emulator/bridge pack remains **Apple Silicon only**. This is an ad-hoc-signed, checkout-aware development release, not notarized standalone distribution or Intel-emulator acceptance. Other-host native credential/input verification, physical controllers and authenticated live SGDB/RomM artwork retrieval remain pending; no owner API key was available for this run. Existing native SDK linker warnings in XCTest are retained in the log, not hidden.

Run these serially through Devbox:

```sh
devbox run app-check
devbox run -- flutter test tool/render_home_artwork_test.dart
devbox run prototype-check-macos
devbox run -- flutter test tool/smoke_home_test.dart
devbox run -- bash tool/build_app.sh --release
```

The explicit shell command forwards `--release`; the default app-build command remains debug. The supplied archive is `build/releases/Broomm-macOS-arm64-artwork.zip`, containing `broomm.app`. Close any existing game/app normally, unzip and open it. No SDK/compiler is needed at runtime; the existing workspace-managed emulator installations/setup sources remain prerequisites for play. See the [README walkthrough](../README.md#verify-managed-setup-and-home-play).

Logs, public contract snapshots, generated previews and isolated extraction live under `.tool-cache/research/home-artwork/`; smoke data stays in its earlier `.tool-cache/research/managed-play/home-data/`. After fixture processes close, those research copies may be removed. Keep normal `broomm-data/` and every profile's private progress. Do not delete stable lock files or pending-deletion checkpoints to bypass a live writer. The Keychain tests use disposable identities with cleanup; owner sign-ins/keys were not read or replaced.
