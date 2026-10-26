# RomM, computer games, and RetroAchievements

Implementation follow-up: the [initial RomM application slice](../romm-application.md) now implements session-only login, server-scoped profile metadata and catalogue browsing against the captured 5.4.0 contract. Direct HTTPS public heartbeat verification succeeds; authenticated owner-server acceptance and the save/install work discussed below remain separate.

Research date: 2026-10-16, updated with the owner's decisions. The selected initial target is **RomM 5.4.0**, with the owner's instance at `https://romm.docubi.casa`. Its public schema was retrieved through `192.168.1.2:1080` as an HTTP forward proxy and reports version 5.4.0, OpenAPI 3.1.0 and 226 paths. See the [instance snapshot and transport limits](../reference/README.md). No credentials, authenticated catalogue/game downloads, synchronization or server changes were involved.

## RomM is an API integration, not a shared filesystem

RomM documents catalogue/content access, user-scoped saves/states, client tokens, and a device synchronization protocol. That makes the requested launcher feasible at the service boundary. It does not establish compatibility between every emulator's local save tree and RomM's asset representation. [RomM introduction](https://docs.romm.app/4.9.0/), [saves and states](https://docs.romm.app/4.9.0/using/saves-and-states/).

Implement against the selected **5.4.0** release and the [captured instance contract](../reference/romm-5.4.0-openapi.json). RomM serves `/openapi.json`; rendered documentation may lag a running instance. The 4.9.0 documentation linked here is historical background only, not Broomm's compatibility target or authority for exact 5.4.0 request fields/scopes. [Consuming OpenAPI](https://docs.romm.app/4.9.0/developers/openapi/), [RomM 5.4.0 release](https://github.com/rommapp/romm/releases/tag/5.4.0).

In the inspected tagged 5.4.0 save handler, `content_hash` participates in device baseline tracking, and a downloaded acknowledgement tracks the served version. It must not be assumed to provide compare-and-swap protection for an arbitrary update. The 5.4.0 release also identifies `StateSchema.core` for RetroArch core identity, sync deletion operations, and changes to negotiation/baseline fields. These are concrete contract items to test; core identity is not a complete emulator-build compatibility guarantee. [Tagged save handler](https://github.com/rommapp/romm/blob/5.4.0/backend/endpoints/saves.py), [5.4.0 API changes](https://github.com/rommapp/romm/releases/tag/5.4.0).

## Authentication and profiles

RomM's documented client tokens are per-user and scope-limited, with a pairing/exchange flow suitable for handheld onboarding. Verify that flow and available scopes against the chosen server release. Store one credential reference per Broomm profile using OS credential facilities, and handle revocation/permission loss without discarding local progress. [Client API tokens and pairing](https://docs.romm.app/4.9.0/developers/client-api-tokens/).

Required profile behavior, with exact RomM authentication mechanics to verify:

- Save multiple servers independently of profiles. Select server, then one of its known accounts or Add profile, following the [Teddy-derived flow](../profiles-and-servers.md). Use a controller-accessible RomM pairing/login flow; never copy Teddy's TED authentication protocol. Preserve explicit trust configuration for self-hosted TLS.
- Resolve stable user identity before binding downloads or progress to a profile. Never use the display username alone.
- Request only catalogue/download/save/device permissions that the verified flow needs. Do not require administrative credentials.
- Bind every queued upload, remote device record and baseline to the originating server/account. Only one server/account context is active. Pause inactive queues and resume them when that owner is selected and connected; never reuse the replacement profile's token.
- Separate catalogue permissions from shared installed bytes, with an explicit offline/permission-change policy.
- Support servers behind path prefixes and redirects without forwarding credentials to an unrelated origin. Validate download URLs returned by the API before using authentication headers.

Older-server compatibility is outside the initial 5.4.0 target; do not add speculative fallback authentication. Unsupported required capabilities produce a precise compatibility message.

## Catalogue and installation contract

The Store needs paginated/searchable catalogue metadata, canonical platform identity, content/file manifests, artwork and authenticated download. Read endpoint pagination/filter behavior from the selected schema instead of assuming a single response is the complete library. A missing page or 403 response cannot authorize local game deletion.

Use remote ROM identity plus verified content revision to resolve a shared install. Multi-file games, disc sets, archives and emulator-installed titles require explicit preparation rules. Downloaded content is data until the selected adapter validates it. A ROM filename is not automatically an executable command or a stable save basename.

Map RomM's canonical platform identifiers explicitly to supported adapters; preserve remote IDs and display labels separately. Unknown/custom platforms should remain visible with a setup explanation, rather than being guessed from a display name. Pin the mapping contract with the chosen server's catalogue. [RomM supported platforms](https://docs.romm.app/4.9.0/platforms/supported-platforms/).

## Save and state transport

RomM documents device registration, synchronization negotiation, transfer operations, conflict resolution, and session completion. Prefer that protocol when available in the supported release, while retaining Broomm's durable local snapshots and recovery. Do not assume that one negotiation call locks another device out for an entire game session. [Device sync protocol](https://docs.romm.app/4.9.0/developers/device-sync-protocol/).

The concrete contract investigation must answer:

| Concern | Required evidence before implementation |
| --- | --- |
| Save versus state | Separate upload/list/download semantics, ownership, slot identity and state/core metadata |
| Directory saves | Supported multi-file/bundle representation; manifest, deletion and atomicity rules |
| Conflict safety | Negotiation/baseline fields, conditional-update behavior and stale-operation handling |
| Idempotency | How to reconcile an upload accepted remotely when the response was lost |
| Integrity | Remote hashes/receipts, downloaded bytes and acknowledgement semantics |
| Device/account scope | Token/device binding and permission behavior for each request |
| Remote deletion | Explicit tombstones/authoritative operations, distinguished from unreadable/incomplete responses |
| Resource limits | Server/proxy upload limits and resumability for memory cards, NAND/disks and large states |

Do not prescribe request payloads from mixed documentation releases. Capture successful and failing responses from the selected version into sanitized integration fixtures, including two-client conflicts and profile separation.

Use the [three-view reconciliation and safe session lifecycle](../architecture.md#synchronization-invariants) as the client safety model. Reconcile before play and after confirmed flush/exit. Persist offline changes for later upload. Stable file size and filesystem notifications are not sufficient proof of a consistent live snapshot. Conflict UI should identify device, profile, emulator, time and content version, while preserving both candidates until a choice is committed.

The owner's offline policy is settled: compare the current remote hash R with the last acknowledged common hash B. If R = B, automatically upload the new local snapshot L. If L and R both changed from B and differ, notify and offer keep-local/keep-RomM. If L = R, acknowledge matching content without prompting; if only R changed, stage a safe download. Missing baselines, failed reads or incomparable hash schemes do not authorize replacement. Hash both sides using the same content definition/algorithm, with adapter-defined manifests for multi-file saves.

Preserve the remote revision across the check/upload race. Verify the 5.4.0 conditional-update or negotiation behavior before relying on it; a `content_hash` parameter alone is not proof of an atomic condition. If the server does not enforce that condition, preserve/version the competing bytes and reconcile rather than silently overwrite a later device's progress. This is implementation work needed to honor the hash rule, not a different conflict policy.

## Save compatibility is an adapter responsibility

An ordinary save may be a raw battery-save file, a memory-card image, a directory card, a console user-data tree, a NAND, or an emulator-specific container. These representations must be deliberately mapped; matching file extensions is insufficient. PGCS's emulator-specific private-profile and save-root work is useful here.

States are more restrictive. Record emulator ID/version/build, core ID/version where applicable, game/content/disc revision, relevant format metadata and host architecture. Preserve available metadata even when RomM lacks a dedicated field; decide whether a supported sidecar/manifest is possible rather than silently inventing API fields. Never promise automatic state conversion.

Cross-device acceptance requires a real save transfer A → RomM → B, loading it on B, making new progress, and transferring it back. Run the same round trip for supported states with matched builds, and an intentional incompatible-build test that retains the state and explains the problem. File upload success alone is not cross-device resume acceptance.

## Android uses ordinary emulator-app handoff

An ordinary Android app cannot read another app's private save directory. Storage Access Framework selection also cannot grant arbitrary access to `Android/data` or `Android/obb` on current target policies. Each emulator must expose an accessible shared save location, a content/provider API, or a cooperative integration for automatic synchronization. [Android storage restrictions](https://developer.android.com/about/versions/11/privacy/storage).

The desktop pattern of downloading an executable into writable configuration and spawning it does not transfer directly either. Android restricts executing files from an app's writable home for apps targeting API 29+, and emulator apps ordinarily run through package/Activity boundaries. The owner selected separately installed emulator apps: detect compatible existing apps, offer ordinary user-approved installation if absent, and pass ROM/save/state inputs through their supported contracts. A bundled emulator engine is not the chosen route. [Android executable-code behavior](https://developer.android.com/about/versions/10/behavior-changes-10).

For each Android candidate, prove content URI/path handling, durable grants, save/state import/export or redirection, external-app return behavior, safe progress reconciliation and recovery after Broomm is killed. Returning to Broomm does not prove the emulator flushed. Accept the emulator app's ordinary Android configuration/isolation limits; no controller assignment, injection or overlay integration is required or planned. If a required save/state handoff cannot work for a package/version, show that specific gap and preserve the profile's progress.

## Computer games and compatibility tools: later stage

The future requirement is broader than wrapping a Windows `.exe`. Model game content, installation recipe, launch entry, native OS/architecture, mutable data roots and compatibility runner independently. A title may contain an archive, installer, dependencies, launchers or multiple executables; a RomM entry alone does not define a safe installation recipe.

| Host / game | Proposed routing | Coverage boundary |
| --- | --- | --- |
| Matching native desktop OS/architecture | Native game runner | Packaging, dependencies, permissions and save discovery still need per-title handling |
| Linux / Windows game | Compatible Proton-based runner, selected automatically with override | Tested per title, runner build, architecture and host; not universal compatibility |
| macOS / Windows game | Separately researched compatibility route | Proton-on-Linux evidence does not establish a macOS solution |
| Android / Windows or desktop Linux game | Separate future feasibility study | CPU translation, graphics, sandbox and runtime delivery; no inherited desktop guarantee |

Valve describes Proton as a Steam-client compatibility tool based on Wine and additional components. Outside Steam, evaluate a maintained runner/runtime arrangement rather than assuming a bare Proton script supplies Steam's environment. [Valve Proton](https://github.com/ValveSoftware/Proton).

**umu-launcher is a concrete candidate** because it explicitly provides a Proton/Steam Runtime execution path outside Steam. Compare its process supervision, runtime download/update behavior, compatibility database IDs, packaging, permissions and license against alternatives before selection. This is research, not an approved dependency. [umu-launcher](https://github.com/Open-Wine-Components/umu-launcher).

Use immutable shared game payloads where the title permits them, and profile/game-specific writable prefixes and user-data roots. A globally shared Wine prefix would leak profile data and serialize unrelated games. Prefixes contain machine/runtime state as well as saves; syncing a whole prefix between devices is not the default progress model. Save extraction/restore requires a title-specific location contract and process-tree supervision, including launchers and lingering helper processes.

Automatic compatibility selection should expose the selected tool/build, retain a per-game override, avoid changing a prefix underneath a running game, and preserve retry/rollback after runner updates. Test 32/64-bit requirements and architecture explicitly. Runtime dependencies belong to managed game/runtime delivery rather than ad hoc system package installs; required kernel/driver capabilities need honest host requirements.

Do not enable emulator injection indiscriminately for future PC games. Anti-cheat/protected titles and unsupported hook combinations need an injection-disabled launch path; supporting compatibility tools is not a requirement to bypass protection. Store purchases, DRM account automation and universal installer execution are not established by this specification.

## RetroAchievements: feasible, deferred

Keep two future integrations separate:

- **Account/library presentation:** link a RetroAchievements identity and display game/achievement/progress data through an appropriate authorized API.
- **In-game unlocking:** use a supported emulator's existing integration, or a separately approved emulator integration with the necessary memory access, game identification, lifecycle and hardcore rules.

The `rcheevos` project supplies emulator integration and game-hashing/client functionality. It is useful evidence, not a drop-in launcher feature: an overlay that draws achievement badges does not evaluate achievements correctly. [rcheevos](https://github.com/RetroAchievements/rcheevos), [client integration guide](https://github.com/RetroAchievements/rcheevos/wiki/rc_client-integration).

Before that later stage, verify supported games/emulators, authentication/token handling, who owns event submission, double-login behavior, emulator-native notices and hardcore/save-state rules. RomM account linkage or metadata must not be presented as proof that a locally launched emulator can unlock achievements. Preserve state compatibility metadata now; implement no achievement engine or RA dependency in the initial stages.
