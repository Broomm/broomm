# RomM application slice

The default entry point is now the Broomm application. It implements server/account onboarding, Home, Broomm settings and catalogue browsing. Subsequent slices add [downloads and input](romm-downloads-and-input.md), [managed setup and Home Play](managed-emulators-and-play.md), and [remembered sign-ins and platform settings](remembered-signins-and-platform-settings.md). The earlier native controller lab remains separate. Synchronization and native acceptance on untested hosts remain pending. The evidence at the end of this document preserves the original application milestone.

## Flow and ownership

First use: server address → compatibility check → Add profile → login → Home. Subsequent starts show saved servers, then only the profiles belonging to the selected server. Choosing a known profile restores its saved credential; missing/rejected credentials require login. Storage/network failures remain errors, rather than prompting for a password as though the sign-in were missing. Stable local server/profile IDs are independent of names and remote numeric IDs; the same account ID on two servers remains separate.

An empty Home has exactly Broomm settings, Game Store and Emulator Settings; completed downloads add game tiles to that row. The horizontal app row, prominent focused title/action, restrained atmospheric background and Store hero/cover rows take inspiration from console interfaces using original Flutter/vector UI. All data shown in interactive Store screens comes from the active RomM connection. Placeholder artwork represents missing/loading covers; it is not a fake game catalogue.

Broomm settings persists reduced motion, artwork visibility and page size (24/48), and provides device sign-out, profile/server switching and access to the explicitly labelled local controller lab. Emulator Settings groups managed installation/configuration under each server platform, with inline review, defaults and removal. Supported downloaded games play from Home. Named collections and progress synchronization remain pending. Local-ROM lab sessions retain their existing single prototype profile; selecting a RomM profile does not reassign that data.

The metadata store uses a stable OS lock, serialized read/modify/write, private staging, flushed file writes, atomic replacement and readback. Corrupt, inaccessible or linked files are errors; they are not treated as an empty account list. Servers survive cancelling login. Preferences and account metadata share one transactional document. The initial schema contains no password/token/credential reference. It does not implement crash recovery for a directory-level power-loss scenario or claim that pending game progress is in this metadata file.

Only the active account owns an authenticated client. Profile switching closes it and clears transient views while retaining secure credentials. Device sign-out also removes and verifies absence of the current profile's stored credential. Both invalidate context/query generations. Late searches cannot replace a newer query or populate another profile. Device sign-out does not revoke the credential in RomM. Catalogue listing/authentication cannot delete game files or progress.

## Verified API contract

The [captured 5.4.0 OpenAPI schema](reference/romm-5.4.0-openapi.json) is the wire-contract baseline. The official [tagged auth implementation](https://github.com/rommapp/romm/blob/5.4.0/backend/endpoints/auth.py) was inspected for password grants, read-only scopes, refresh rotation and expiry units. Historical 4.9 documentation is not used as authority for 5.4 request fields.

| Purpose | Contract implemented |
| --- | --- |
| Compatibility | `GET /api/heartbeat`, `SYSTEM.VERSION == 5.4.0` |
| Password login | `POST /api/token`, URL-encoded password grant; `me.read roms.read platforms.read assets.read` |
| Refresh | Same endpoint, refresh grant, one in-flight refresh per active client; rotated refresh credentials published under a per-profile cross-process lock, access token memory-only |
| Client-token login | Bearer client token, or `POST /api/client-tokens/exchange` with RomM's eight-character alphanumeric API key pairing code and `raw_token` response; normalize hyphens/case as the server does |
| Account identity | `GET /api/users/me`; stable numeric account ID and enabled state |
| Platforms | `GET /api/platforms`; remote IDs remain distinct from display names |
| Store | `GET /api/roms` with limit/offset, search term, platform IDs and total; full-library indices/filter metadata disabled |
| Picks | Most recently added IDs descending, first result featured; this is a collection pick, not a personalization engine |
| Detail | `GET /api/roms/{id}`; summary, platform, genres, year, rating and size when available |
| Artwork | Returned server-local cover/screenshot paths, resolved under the configured base prefix |
| Downloads | Detail `files` manifest plus `GET /api/roms/{file-id}/files/content/{encoded-file-name}`; the path ID is a file ID, not the parent ROM ID |

The client rejects redirects instead of forwarding authentication, confines authenticated artwork to the selected origin/base path, validates URL structure before normalization, keeps TLS certificate verification, requires an explicit opt-in for HTTP, bounds responses (12 MiB JSON / 8 MiB artwork) and uses a 20-second operation deadline. Four connections per host and a client-scoped bounded artwork cache limit work. HTTP errors expose fixed actionable messages; server bodies, passwords, tokens and authorization headers are never printed. Expired/forbidden sessions remain distinct from a confirmed-empty catalogue. Retry is user initiated; the client does not retry a consumed refresh token automatically.

Direct validated HTTPS access to the owner's public heartbeat now works with the implemented Dart client and confirms 5.4.0. No proxy was needed for that check. No owner credentials were available, so live authenticated catalogue/artwork and token/pairing acceptance remain owner checks. Local real-HTTP tests verify forms, refresh, headers, filters, pagination, redirect confinement and errors without inventing live acceptance.

## Dependency and input choices

No application package was added. Dart `HttpClient` supplies transport rather than `http`/Dio: fewer transitive/runtime dependencies and no new license/distribution asset, at the cost of explicitly owning deadlines, response limits, cancellation, token refresh and URI policy. A generated client would add a build/dependency pipeline and a much larger surface than this slice. Flutter's existing ChangeNotifier, focus/actions, widgets and SDK test tools cover current state/navigation; a routing/state-management framework was not introduced.

The later [credential follow-up](remembered-signins-and-platform-settings.md) selects direct OS adapters after comparing `flutter_secure_storage` and packaging/maintenance tradeoffs. No new dependency is added. OS storage calls are native interop; RomM refresh, identity, locking and publication decisions remain Dart. There is no plaintext credential fallback. Only native macOS secure-store behavior is currently verified.

Launcher input is separate from emulator input routing. macOS uses the existing GameController bridge extended with Back, Search, Menu, left stick and bounded held-direction repeat. Linux uses Dart FFI with existing libc/evdev, read-only nonblocking gamepad descriptors and capability-based discovery; it requires the user's normal device permissions. Windows uses OS XInput; Android forwards gamepad keys/axes through Flutter interop and provides the app-private storage path. No SDL runtime, driver, privileged input helper or OS package is installed for launcher navigation. Flutter/Steam key events remain another navigation path. Native runtime availability and permission failures on Linux, XInput coverage and Steam duplicate-input behavior need target-native tests; a macOS build is not proof of them.

Input references: [Linux event protocol and codes](https://www.kernel.org/doc/html/latest/input/event-codes.html), [XInput gamepad layout](https://learn.microsoft.com/en-us/windows/win32/api/xinput/ns-xinput-xinput_gamepad), [Android controller input](https://developer.android.com/games/sdk/game-controller/controller-input). Native navigation uses public OS APIs; no implementation is copied from these sources.

Flutter geometric focus, visible focus rings and scroll-to-focus support home apps/games, Store cards/filters/details, settings, profiles and modals. Pointer/touch starts inline editing; keyboard navigation requires Enter to edit and Escape returns to navigation on the same field. Controller activation opens the on-screen keyboard. Explicit ordered traversal in Emulator Settings includes dynamically expanded review controls. Pointer hover does not take navigation focus. Artwork decode sizes, repaint boundaries in the retained controller lab and worker-based rotating logs avoid unnecessary UI-isolate work. The shared session logger gained optional source/severity metadata with its existing session defaults preserved.

## PGCS reference and remaining work

The PGCS manifest/setup implementation was re-inspected read-only for this slice: `internal/setup/manifest.go` validates named launchers, host-specific source/format/executable/version/core artifacts; `setup.go` uses an install lock, staging and explicit execution. The future Broomm flow will be import → validate → show plan → user starts installation → private prepare/verify → publish. No Go source, setup operation, emulator download or automatic update was introduced. Existing [roster/setup requirements](emulator-support.md) still apply, including configuration isolation for system-selected executables.

## Verification and owner walkthrough

Use the [README walkthrough](../README.md#run-broomm). Required checks run through Devbox; Flutter tests and native builds run serially because they share generated Swift-package state. The original application verification passed `devbox run app-check` with 67 tests plus analysis, including the 49 previous controller/session regressions. Those checks cover real HTTP auth/refresh/filtering/redirect/timeout behavior, profile separation and restart, serialized metadata/preferences, corrupt/link preservation, stale searches/profile contexts, controller action/channel navigation, virtual-keyboard input and 390×844 / 860×620 / 1600×900 layouts. No sanitizer execution or cross-host native acceptance is claimed.

`tool/render_shell_test.dart` renders actual Flutter widgets with explicitly isolated fixture data to `.tool-cache/research/romm-shell/previews/`. Home, server setup, settings, Store and phone Home images were inspected; this is artifact inspection, not computer-control or physical controller acceptance. Fixture credentials/data never enter the interactive app.

Exact source/build fingerprints, command logs and final native results are recorded in [romm-application.json](romm-application.json). The direct public heartbeat result is retained under `.tool-cache/research/romm-shell/live-result.json`. Interactive user data is in `broomm-data/` for this development build; no account catalogue or credentials are checked into the repository. Existing ROMs/emulator user data and both reference source checkouts remain unchanged by this application slice.

The 67-test result and machine-readable snapshot above record the original application slice. Current download/input verification is recorded separately in [the extension evidence](romm-downloads-and-input.md).

Owner checks still needed: log in to the actual server; confirm covers, details, search, platforms and downloads under the account's permissions; use a physical controller through onboarding/settings/Store and mixed-device text entry; verify remembered sign-in across restart and explicit sign-out; repeat under native Linux/Steam and later Windows/Android. Supported Home Play is now implemented; synchronization remains a subsequent milestone.

## Pairing-format correction — 2026-10-23

The owner reported that the API key pairing code contains letters. The exact [RomM 5.4.0 generator/exchange](https://github.com/rommapp/romm/blob/5.4.0/backend/utils/client_tokens.py) generates eight characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, normalizes hyphens/case and sets a 60-second lifetime. The prose documentation's numeric example led to an incorrect numeric-only classifier in the main client and keyboard/validator in the Switch companion. Both clients now use the tagged format. No package or authentication mechanism was added.

The main HTTP suite now checks generated-alphabet forms, lowercase/hyphens, malformed input before network effects and expired exchange without retry/session creation. Those tests plus the existing shell/onboarding regressions pass 22 cases; analysis passes for the three modified Dart source/test files. [The correction evidence](pairing-code-format.json) identifies tested source/log hashes. These are macOS-host tests of portable Dart/Flutter behavior, without owner credentials or changes to remote keys. No new desktop binary or Linux/Windows/Android native verification is claimed. The companion keeps its own native build/deployment/keyboard acceptance records in `broomm-nsw`.
