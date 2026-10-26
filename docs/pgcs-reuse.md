# PGCS reference audit

Inspected on 2026-10-16 at `/Users/ptrschneider/Projects/pgcs`. This is an audit of the supplied local project, not just its README or a claim that its behavior has been reproduced in Broomm.

**Owner decision after this audit:** do not reuse PGCS application code and do not introduce Go. Reimplement Broomm workflows in Dart. The values carried forward are engineering practices, emulator knowledge, manifest concepts and observed behavior. Optional injection bridges may be written in C and bundled precompiled. The original filename is retained for existing documentation links; it does not imply permission to import code. The owner also selected PGCS's concrete emulator roster; see [emulator support](emulator-support.md).

## Evidence and limits

The checkout reports HEAD `0e7cba7f27d84d3875fcaa6a171fea5862e7c181`, with substantial staged, unstaged, and untracked controller/documentation changes. The inspected working tree is newer than that commit. In particular, `internal/controller/routing.go`, `virtual_linux.go`, and the controller mapping database are untracked in the source checkout. Checking out HEAD alone would omit part of this audit's evidence; record the exact reference when reproducing an observation.

Read the complete AGENTS.md; the native bridge README and implementation; controller routing/classification, launch/session recovery, process identity, provisioning/extraction, and representative emulator adapters. PROJECT.md, SETUP.md and the launcher/implementation inventories were used for context, without importing their unrelated product scope. Source and historical validation records were inspected read-only. No PGCS tests, controllers, emulators, Steam sessions or CI jobs were executed for this task.

Useful local source entry points:

| Area | Source in the inspected PGCS tree | Research value for a Dart implementation |
| --- | --- | --- |
| Engineering practices | [AGENTS.md](../../pgcs/AGENTS.md) | Adapt general practices; omit product rules and historic owner approvals |
| Managed provisioning | [setup.go](../../pgcs/internal/setup/setup.go), [manifest.go](../../pgcs/internal/setup/manifest.go), [reuse.go](../../pgcs/internal/setup/reuse.go) | Study staging, receipts and retry behavior; implement Broomm's manifest/update flow in Dart |
| Downloads and extraction | [download.go](../../pgcs/internal/setup/download.go), [extract.go](../../pgcs/internal/setup/extract.go), [appimage.go](../../pgcs/internal/setup/appimage.go) | Useful bounded transfer, path validation, private staging and archive tests; revisit limits for large games |
| Session/recovery | [session.go](../../pgcs/internal/launch/session.go), [process_identity.go](../../pgcs/internal/launch/process_identity.go) | Study invariants and failure cases; write Dart recovery and profile-bound RomM transfers independently |
| Emulator boundary | [launcher.go](../../pgcs/internal/launcher/launcher.go) | Small preparation/mapping boundary is useful; do not transplant Go types or registry verbatim |
| Private profiles | [dolphin.go](../../pgcs/internal/launcher/dolphin.go), [rpcs3.go](../../pgcs/internal/launcher/rpcs3.go), [pcsx2.go](../../pgcs/internal/launcher/pcsx2.go), [duckstation.go](../../pgcs/internal/launcher/duckstation.go) | Recheck config/save locations for selected builds and implement Broomm-local configuration without importing adapters/tests |
| Join and discovery | [join.go](../../pgcs/internal/controller/join.go), [SDL worker](../../pgcs/internal/controller/sdlprobe/join.go), [identity checks](../../pgcs/internal/controller/sdlprobe/join_identity.go) | Keep ordered roster/device concepts and relevant fixtures; replace prototype presentation in Flutter |
| Steam/Linux routing | [routing.go](../../pgcs/internal/controller/routing.go), [virtual_linux.go](../../pgcs/internal/controller/virtual_linux.go), [launch controller workflow](../../pgcs/internal/launch/controllers.go) | Diagnostic baseline; several policies remain experimental and are not a universal Steam Input solution |
| In-process bridge | [bridge.c](../../pgcs/native/sdl-player-bridge/bridge.c), [slots.h](../../pgcs/native/sdl-player-bridge/slots.h), [README](../../pgcs/native/sdl-player-bridge/README.md), [supervisor](../../pgcs/internal/controller/playerbridge/bridge.go) | Feasibility evidence for a focused C bridge with a Dart supervisor, Broomm protocol and host/build matrix; no Go supervisor import |
| Mapping and preferences | [PS2](../../pgcs/internal/launcher/ps2_controller.go), [DuckStation](../../pgcs/internal/launcher/duckstation_controller.go), [RetroArch](../../pgcs/internal/launcher/retroarch_controller.go), [mapping database](../../pgcs/internal/controller/mappingdb/README.md) | Study positional bindings and preference behavior, with new Dart code and format/core-specific validation |
| Platform packaging | [Dolphin packaging](../../pgcs/DOLPHIN-PACKAGING.md), [RetroArch packaging](../../pgcs/RETROARCH-PACKAGING.md), [macOS preparation](../../pgcs/internal/setup/steam_compatibility_darwin.go) | Research inputs for managed builds, signing and dependencies; approvals/modified-signing policies do not transfer |

These sibling-project links are local audit references and require the supplied PGCS checkout. Broomm must not depend on that checkout at runtime or build time. Record source evidence when using emulator knowledge, but do not turn the reference audit into a code port.

## What the existing bridge actually does

The C library exports `SDL_DYNAPI_entry`. Its supervisor selects it with `SDL3_DYNAMIC_API` for that child. The bridge obtains the launcher's original SDL API table, forwards ordinary input, wraps initialization, and overrides `SDL_GetGamepadPlayerIndex` and `SDL_GetJoystickPlayerIndex`.

It matches selected controllers using SDL GUID plus serial, or GUID plus exact gamepad name when no serial exists and the identity is unambiguous. It validates the roster inside the emulator, assigns selected players indices 0/1, reserves unjoined devices from index 2, writes `ready`, and waits for the supervisor's release. The supervisor then exposes the ROM through an adapter-specific private path and releases initialization. DuckStation additionally needs a private placeholder for its early existence check.

Important limits from the code, rather than inferred capabilities:

- The roster has **at most two players**. Extending the join screen to four players does not extend this bridge.
- It checks a particular SDL3 ABI/table subset. The original SDL entry must be accessible; static linkage alone is not necessarily disqualifying, but inaccessible/disabled dynamic API or incompatible exports are.
- Reconnection/duplicate selected identities are refused. This is not live reassignment.
- It does not create stable identity when identical controllers have no distinguishing identity. Matching a unique name is a conditional fallback.
- It changes player-index queries, rather than every input backend, joystick enumeration, event ID, hotplug path or emulator port registry.
- It does not render overlays, pause the emulator, suppress all game input while a menu is open, or change resolution/settings.
- The inspected embedded bridge assets include macOS universal and Linux AMD64 files; the build tool supports native builds, but a Windows source branch is not a shipped/verified Windows integration.

PGCS's notes report owner-tested ARMSX2/PCSX2 gameplay and narrower DuckStation fallback checks on macOS and Ally/Bazzite, including reversed join order in some scenarios. Those records are useful prior evidence only. The bridge README and broader implementation notes describe different checkpoints; this audit does not reconcile every historical CI claim or establish support for their current dirty working tree.

## What changes for Broomm

PGCS synchronizes working save directories back to cartridge directories. Broomm needs authentication, HTTP transfer, remote version/conflict semantics, offline queues, and per-account isolation. Study the safe sequencing and failure cases, then implement them independently in Dart; do not wrap cartridge sync and call it RomM sync.

PGCS provisions into its own configuration area. Its setup engine illustrates archive/AppImage/DMG preparation and retry mechanics. Broomm's settled policy is managed desktop installations, Broomm-local configuration even for an external executable, and manual/setup-file-driven updates. Android uses ordinary installed/explicitly installed emulator apps instead. PGCS's source-profile cloning behavior is not authorization to write a system emulator profile.

Its controller UI and physical-first Steam routing are starting evidence. Broomm should expose emulator-observed identities and verify a player assignment in the final child environment. A successful join in the launcher does not guarantee the same route exists after focus changes or Steam handoff.

Do not carry over cartridge discovery/editing/cloning/backup flows, Steam shortcut reconciliation, generated per-game Steam entry wrappers, user-session daemon/startup services, CLI output-format restrictions, PGCS directory schema, historical emulator milestone order, shelved features, or past approvals. Its concrete emulator roster is now owner-selected for Broomm; other inherited constraints remain excluded. Adapt only relevant knowledge and write new application code.

## General engineering guidance carried into AGENTS.md

| PGCS guidance family | Broomm treatment |
| --- | --- |
| All-host design; accurate verification claims | Retained, adding Android as a current product target |
| Library versus own implementation review | Retained; old library approvals explicitly do not transfer |
| Incremental milestones; simple concrete boundaries; preserve behavior during refactors | Retained |
| Explicit errors; bounded effects; child-only environment; literal arguments | Retained without Go/CLI-specific implementation names |
| Atomic persistence, OS locks, uncertainty, ownership, interrupted work and save recovery | Retained as general correctness rules |
| Consistent rotating logs; meaningful, deduplicated feedback; measured performance | Retained; command-output formatting restrictions omitted |
| Boundary tests, deterministic concurrency, independent native/race checks | Retained; no unexecuted host checks claimed |
| Real integration validation; X11 diagnostic comparison; owner-only computer use | Retained as verification practices |
| Documentation maintenance, concrete delivery walkthroughs, commit-message style | Retained and adapted for documentation-only work |

No copied milestone history or emulator-specific acceptance rules are normative in Broomm's AGENTS.md.

## Provenance and distribution checks

PGCS application code and its Go dependency graph are excluded. For a future C bridge, retain provenance and applicable notices for any native source or SDL-derived ABI data actually used. Audit bundled SDL binaries or a controller database independently if selected; the reference project's dependency approvals do not select them for Broomm. PGCS's [native dependency notices](../../pgcs/licenses/README.md) are an audit reference only.

Fingerprints of important inspected working-tree files (SHA-256):

```text
AGENTS.md                                  94e11f5abe98d7151887b3e293edaa10d85c51955a5433c8e6186be400505646
native/sdl-player-bridge/bridge.c            1fe7d5764d1bfd6d8e3bd5cf1b449bf06d4ee715079805cc7795e56b6429398f
native/sdl-player-bridge/slots.h             e2caa14c161f2dc4fd56be12b03f01e57c7410719c40f30c97c5c3813b5a9b8e
internal/controller/routing.go              f5fe7bbd9ef28718f55e11414477f716cd2aba75db883781f68a40821a07b5b2
internal/controller/virtual_linux.go         aca8121d898c27c441f180c19d52431c7a5a387583e36a3c1569bd8288ecab95
```
