# RomM downloads and mixed-input text entry

Implemented 2026-10-17. This extends the [initial application slice](romm-application.md). The Store downloads ROM files and publishes Home entries; playing those downloads, save synchronization and managed emulator setup remain separate milestones.

This record describes that first slice. Subsequent milestones add [managed setup and Home Play](managed-emulators-and-play.md), [explicit Enter/Escape text editing](remembered-signins-and-platform-settings.md), and [selected artwork and local game deletion](home-artwork-and-deletion.md); their current behavior and verification supersede the corresponding limits below. Save synchronization remains pending.

## Text entry

Server address, username, password/token and Store search are real inline Flutter text fields. Pointer/touch selection and physical keyboard traversal allow ordinary typing, selection, caret movement and platform text submission. They never open Broomm's virtual keyboard. Password/token fields remain obscured.

Controller A and the native controller channel use a separate activation intent, which opens the virtual keyboard with the current value. Done applies the value and restores focus; Cancel preserves the original. Controller directions move focus between fields/buttons; physical editing keys keep their normal text-field behavior. Controller X still opens Store search directly. No sticky last-input flag is involved, so a pointer click after controller use still edits inline. Store search applies on text submission, Search, or controller-keyboard Done.

## Download contract and ownership

The captured [RomM 5.4.0 schema](reference/romm-5.4.0-openapi.json) and official tagged handlers were inspected: [file downloads](https://github.com/rommapp/romm/blob/5.4.0/backend/endpoints/roms/files.py), [file paths](https://github.com/rommapp/romm/blob/5.4.0/backend/models/rom.py), [hash definitions](https://github.com/rommapp/romm/blob/5.4.0/backend/handler/filesystem/roms_handler.py). The detail response's `files` array supplies stable file/parent identities, full paths, names, sizes and hashes. Individual requests use `GET /api/roms/{file-id}/files/content/{encoded-file-name}` with `roms.read`; the path ID is the file's ID. Files remain under the configured server path prefix. Redirects are rejected without forwarding credentials.

The app refreshes the game detail before starting a transfer. It streams each file directly to private staging with asynchronous disk backpressure, a 20-second header/idle deadline, a 24-hour file-transfer ceiling and cancellation. It bounds the manifest to 10,000 files and each file to 1 TiB. Download progress is limited to roughly eight updates per second, with phase and bounded byte logging. No ROM payload is buffered in full on the UI isolate.

The local structure is:

```text
broomm-data/library/
  downloads.lock
  <saved-server-id>/
    .partial-<unique>/          # never a completed Home entry
    <rom-id>/
      receipt.json
      content/<relative game files>
```

Single-file games keep their original filename. Multi-file games keep paths relative to the game's RomM folder. File IDs must belong to the requested game. Portable path validation rejects traversal, absolute/drive paths, NUL/control characters, reserved names, case collisions, file/folder collisions and excessive path lengths/depth. Exclusive file creation additionally catches aliases according to the actual filesystem. Linked roots, directories, locks and receipt files are rejected. Archives remain raw files; no extraction or execution occurs.

After streaming, a cancellable worker reads each file back and calculates its raw IEEE CRC-32. Its size must match the manifest, and a supplied raw-file RomM CRC must match. RomM can hash decompressed archive members instead of the downloaded container; archive metadata, extensions and container signatures prevent comparing those hashes with raw container CRCs, including containers with an unusual suffix. Every receipt records local raw CRCs, including for containers and files with no remote checksum. CRC is accidental-corruption detection, not cryptographic authenticity; transport retains the existing TLS verification/explicit HTTP policy.

A stable OS lock and an in-process lease cover staging and publication. After all files verify, Broomm flushes and reads back the receipt, then publishes the directory with one rename. It refuses to overwrite an existing installation. An interruption before publication leaves staging, which is ignored by Home and removed on a later installation only while holding the writer lock. Normal failure/cancellation removes its own stage. No byte-range resume is implemented; retry starts from the beginning. File/receipt flush and rename do not claim directory-fsync durability across power loss.

Receipts preserve game metadata and the originating account ID; they contain no credentials. Storage is shared by saved server and ROM ID, independent of profile names. On login/reload, the app checks payload presence/size and verifies each game's catalogue visibility using the active account. Another authorized profile reuses the same directory. Explicit 401/403/404 results exclude inaccessible games from that profile's Home while keeping files. A failed network check retains an originating account's local entry with a visible warning; it does not grant a new account access. Catalogue refresh failures do not clear installed games. Different servers retain separate directories even when ROM/account IDs overlap. Saves and save states are untouched.

## UI and limitations

Store details offer Download game. The progress panel and Cancel download remain reachable when returning to Home/other screens. The details action can retry after a failure. Only one download runs at a time; sign-out cancels it, invalidates the account context and closes its client. Graceful window close waits for cancellation/cleanup. Completion adds a Home tile; its details say Downloaded and explain that playing is coming later. There is no Play action. A missing/size-changed payload remains an entry needing attention; unreadable receipts produce a library warning while preserving the affected directory and other readable games.

The first slice does not implement repair/uninstall, a download queue, cached artwork for offline use, a full offline login flow, archive extraction, generated playlists or byte-range resume. Receipt loading checks existence/size, rather than rehashing gigabytes at every login. Owner-authenticated downloads from `romm.docubi.casa`, physical mixed-input use, and native Linux/Steam, Windows and Android checks remain pending. No credentials were available for a live authenticated test. The running owner's app/session is not closed for this delivery.

## Verification

`devbox run app-check`: analysis plus **82 passing tests**, including the previous controller/session regressions. New tests exercise real loopback HTTP with the actual client/filesystem, nested files, cancellation/retry, stalled headers/bodies, truncated/oversized/corrupt responses, redirect/authentication failures, traversal/collisions, archive hash distinctions, damaged receipts/files, shared profile reuse and restart. A separate Dart process holds the production OS lock to prove exclusion and safe stale-stage cleanup. Account-change tests reject late download completion after sign-out. Widget tests cover direct pointer/keyboard entry, masking/caret keys, controller origin/channel switching, Store submission, download-to-Home navigation and absence of a premature Play action. This evidence does not establish owner-server authenticated acceptance or cross-host native behavior.

The [README walkthrough](../README.md#run-broomm) describes prerequisites, controller/keyboard actions, storage, effects and cleanup. Isolated fixture previews are generated using `BROOMM_RENDER_ROOT="$PWD/.tool-cache/research/download-input/previews" devbox run -- flutter test tool/render_shell_test.dart`; downloaded Home, progress, Store and phone layouts are inspected as artifacts, without computer-control tools. Machine-readable final counts, source/build fingerprints and logs are retained in [romm-downloads-and-input.json](romm-downloads-and-input.json).
