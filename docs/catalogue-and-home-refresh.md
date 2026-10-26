# Grouped catalogue, logos and Home refresh

Updated 2026-10-19 in response to the owner's two screenshots. This follow-up changes catalogue presentation and Home feedback; [artwork ownership and game deletion](home-artwork-and-deletion.md), managed-emulator configuration and profile-private progress retain their existing boundaries. [Exact fingerprints, logs and build details](catalogue-and-home-refresh.json) identify this uncommitted workspace independently of earlier milestones.

## Catalogue and version choice

Every catalogue request now sends `group_by_meta_id=true`, including Discover/recent picks, search, platform filters and subsequent pages. This is the parameter exposed by the captured [RomM 5.4.0 schema](reference/romm-5.4.0-openapi.json). The [tagged ROM endpoint](https://github.com/rommapp/romm/blob/5.4.0/backend/endpoints/roms/__init__.py) supplies permission-filtered `sibling_roms`; the [response schema](https://github.com/rommapp/romm/blob/5.4.0/backend/endpoints/responses/rom.py) supplies each sibling's ROM ID and filename with tags. Raw public source snapshots are retained in `.tool-cache/research/home-refresh/`.

RomM chooses the catalogue representative and owns metadata grouping, totals and offsets. Broomm does not merge by display name, invent a group ID or fetch the whole library to deduplicate one page. Different games sharing a title remain distinct unless RomM links them. Unidentified/misidentified metadata may therefore need correction in RomM. Sibling identities and tags round-trip through the existing receipts; older receipts without them remain readable.

Open a grouped entry and choose **Download game**. **Choose a version** lists the representative plus each distinct sibling, with filename tags and an already-downloaded indicator. Arrows/D-pad navigate the list and A/Enter selects; pointer/touch works too. Already downloaded versions cannot be downloaded again from that list. **Download another version** is available when viewing a downloaded entry with siblings. A single-version entry retains the direct download flow.

The group is refreshed before showing its choices. The chosen ROM is refreshed and checked for exact identity and current profile context before the existing download boundary refreshes and verifies its manifest. Only that version's files/receipt are installed. Cancellation, failed/revoked detail requests, identity mismatch and a profile change during selection cannot start a different download. No remote metadata, preferred version or source file is modified. Shared game files and profile-private writable data retain their existing ownership.

## Artwork and Home

The existing two artwork steps now lead to **Choose a logo**. The [official SteamGridDB API](https://www.steamgriddb.com/api/v2) exposes `/logos/game/{gameId}` and static PNG/WebP logos. The same mapped ID, separate secure profile key, credential-free CDN transport, paging, cancellation, image verification and request/response bounds are reused. No package, native component, OS dependency or additional service was added.

Logo images can be wide, square or tall. They use aspect-preserving contain rendering, retaining transparency, rather than imposing the heroes' landscape rule or stretching them. A selected logo replaces the large Home game name and supplies its accessible name. Missing, unreadable or disabled artwork retains the typed title. It remains possible to add logos to existing installations through **Select Artwork** without redownloading ROMs. Keeping/skipping/cancelling a step preserves the other existing images and any earlier new choices; the first-step cancellation still ends selection.

The optional logo is published with the icon/hero in the same immutable choice directory and atomic version-1 record. Replacing one image copies the other selected images, including the logo. Only recognized previous image files are cleaned after publication. Old icon/hero-only records load without migration. The existing confirmed deletion removes the logo with the local game/artwork and preserves every profile's saves and states.

Home icons are larger and have no visible captions. Accessible labels remain, and the prominent selected title/logo identifies the game. Play and Options share a responsive row, including the checked 320-pixel layout. Left/Right traverses those actions and Up returns to the selected tile. The top branding/header is removed. A bottom-left Home action and bottom-right profile retain shell navigation, with the tagline beside the profile when space permits. Up from the footer restores the remembered content selection. The original top-aligned hero/fade and underlying atmosphere are retained.

## Notifications and focus

Transient notifications use opaque, readable cards at the top left, with an icon and message. Completion cards expire after seven seconds; problem cards after twelve. Each new event has its own timer, unchanged polling does not repeat it, and an older timer cannot dismiss a newer event. Cards use the saved/platform reduced-motion policy and announce their text as a live region. They occupy no page space and do not request focus.

Active download progress/cancellation remains available in a card until completion; its phase/byte updates keep the existing rate limit. The operation's error state remains available to its details/status rather than being erased by the visual timer. Signing out/switching profiles removes previous feedback. Gameplay hides launcher cards, and the game-active transition explicitly refreshes the shell so a launch/return problem becomes visible after gameplay ends. Artwork completion uses the same card path; the bottom Snackbar was removed.

Visual inspection found a related focus bug: resizing the window could rebuild the underlying details layout and autofocus its Download/Play button underneath the version modal. Those buttons and Back now request autofocus only on their current route. The chooser keeps its first available selection across desktop/compact resize, and still returns focus normally after closing. Both initial and resized controller focus are asserted at the actual widget boundary.

## Verification and delivery

Analysis and **155 Flutter tests pass**. New and extended cases cover the actual grouped HTTP query (including pagination/recent requests), sibling parsing/identity, a single Store card with filename-tagged choices, native controller-channel selection of the second version, cancellation, permission failure, a different returned ROM identity, and a held request after profile switching. Logo checks cover the distinct endpoint and PNG/WebP formats, bounds, persistence across reload/partial replacement, decoded Home rendering, text fallback and existing safe deletion. Timed-card checks prove position, expiry, newer-event lifetime, unchanged page geometry/focus, retained active progress, account changes and visible feedback after gameplay.

Two offscreen renderer tests pass, producing twelve inspected PNGs for grouped Store, desktop/compact version choices, Home/logo, notification card, all three artwork steps, key settings and title options. Images and catalogue data are isolated fixtures, including a generated transparent logo; these are not owner-server or physical-controller observations. The existing supplied-SNES Home Play smoke test also passes through real managed RetroArch loading/pairing/play and normal return. No emulator bridge or save workflow changed, and a new six-emulator run is not claimed.

The macOS release is built through the approved Devbox/Apple toolchain and packaged at `build/releases/Broomm-macOS-arm64-home-refresh.zip`. Built/extracted bundle signature integrity and ZIP CRC checks accompany the evidence record. The launcher includes x86_64/arm64 slices; the verified managed emulator/bridge pack remains Apple Silicon. This is an ad-hoc-signed, checkout-aware development build, with the same data/setup prerequisites as before. It is not standalone/notarized distribution or native acceptance on Linux/Steam, Windows or Android. The prior native credential/window checks remain historical evidence; no native adapter changed here.

The first package verification reported a modified nested `App.framework` while both frameworks validated independently. The generated development bundle's outer seal was refreshed using the existing Release entitlements, then repackaged and verified both before and after extraction. The precise Xcode incremental-build cause is not established; signing changed no framework/application code. The full diagnostic and signing commands are retained in `signature-repair.json` alongside the final package checks.

Run serially:

```sh
devbox run app-check
devbox run -- flutter test --concurrency=1 tool/render_home_artwork_test.dart tool/render_versions_test.dart
devbox run -- flutter test tool/smoke_home_test.dart
devbox run -- bash tool/build_app.sh --release
```

Follow the [README walkthrough](../README.md#verify-managed-setup-and-home-play): filter/search the Store, choose a release, optionally select its icon/hero/logo, then verify Home actions, footer and disappearing cards. Existing games use Select Artwork for a logo. No owner credentials were read to run these checks; authenticated retrieval from the owner's RomM/SteamGridDB and physical controller/visual acceptance remain pending. Research logs/previews and isolated fixture data can be removed after their processes close; keep normal `broomm-data/`, all profile progress and stable lock/checkpoint files. The build replaces no running owner application.
