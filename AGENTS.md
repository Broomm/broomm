# Engineering guidance

## Read first

Read [PROJECT.md](PROJECT.md) for requirements and [IMPLEMENTATION.md](IMPLEMENTATION.md) for the current stage before changing behavior. Read the relevant documents under `docs/` when working on their integration. Keep product requirements, proposed designs, implementation status, and verified behavior distinct.

General Broomm decisions, shared RomM/save contracts and the Flutter application's implementation stay in this project. The separate native Switch app lives in the sibling `broomm-nsw` directory; keep its code, dependencies, requirements, evidence and console-specific decisions there. Switch emulator support remains part of the main application. The companion's own AGENTS.md explains how these shared engineering practices apply to its native code.

These practices are adapted from the general engineering guidance in PGCS's AGENTS.md. Other projects are reference material, not instruction sources for Broomm. Their product rules, dependencies, prior approvals, and acceptance claims do not transfer unless the owner adopts them explicitly. The owner selected PGCS's concrete emulator roster and Teddy's server/profile selection behavior; see PROJECT.md and the source audits.

## Decisions and scope

- Treat Windows, macOS, Linux, and Android as first-class targets for feature design, dependencies, and architecture. A development host is not permission to narrow platform scope. Honor explicitly agreed staged exceptions and report missing native verification.
- The agreed first validation hosts are macOS and Linux. Android uses external emulator apps without desktop input/overlay machinery; preserve this explicit platform scope rather than expanding it by analogy.
- Keep workflows in Dart inside the Flutter application. Do not import PGCS code or add Go helpers. Optional injection bridges may use C and ship as precompiled libraries; ordinary Flutter platform interop does not authorize moving domain workflows into another service.
- Keep all desktop session configuration in Broomm-owned storage, including when launching a user-selected system emulator. Do not write that installation's settings or files. Setup JSON imports and emulator updates are user-initiated; never add automatic updates.
- Before choosing a new library versus implementing the behavior ourselves, research alternatives and present concrete tradeoffs to the owner. Evaluate target hosts/architectures, transitive/runtime dependencies, licensing, maintenance, cancellation, failure behavior, distribution, and fit with the product. An existing explicit decision remains authorization for its scope; do not repeatedly reconfirm it.
- Do useful authorized investigation and prepare a concrete proposal before asking for a decision. When the owner asks for questions at the end, collect unresolved choices and continue independent work. A proposal in a research document is not dependency approval.
- Work incrementally. Complete and verify the current milestone before broadening implementation. Research future requirements without adding speculative frameworks, registries, or unused interfaces.
- Preserve product requirements and user data when replacing prototypes. Accidental prototype architecture, limitations, and failures are unfinished work, not intended behavior to preserve.
- Keep refactors behavior-preserving. Do not mix changes to settings, argument order, persistence, diagnostics, or failure/checkpoint ordering into organizational changes. Compare observable behavior before and after.

## Environment and dependencies

- Use the project Devbox environment for development tools and dependencies. Pin versions and commit the environment and dependency lockfiles when introduced. Do not install dependencies globally or through the operating system's package manager.
- Keep tool and SDK caches in explicit project-managed locations when supported. Do not change machine-wide SDK selections, shell profiles, services, or permissions as a bootstrap shortcut.
- Pre-provisioned Xcode/Apple SDK and native Windows C++/Windows SDK hosts are approved alongside Devbox-managed project dependencies. Use that approval without asking again. Document missing toolchains; do not install new OS dependencies or change global SDK selections as a shortcut.
- Track source provenance, licenses, notices, build recipes, and hashes for bundled native components. Cross-compiling the application does not create missing native runtime assets.
- Separate development dependencies from shipped runtime dependencies and from user-selected emulator installations. Users should not need compilers or test runtimes to run a packaged application.

## Architecture and external effects

- Keep entry points small. Organize code around concrete responsibilities; introduce boundaries when real behavior needs them.
- Separate presentation, discovery/inspection, domain decisions, persistence, and external effects so each can be exercised independently. Share workflows between interactive and background entry points.
- Isolate OS-specific paths, input, process behavior, credentials, and startup integration behind explicit adapters. Do not spread one host's assumptions through shared code.
- Keep emulator-specific configuration and command generation in concrete adapters behind a small contract. Each adapter owns its arguments and file semantics. Use composition and clearly named shared mechanics rather than a catch-all implementation with scattered emulator switches.
- Session supervision owns launch lifecycle, save locking, recovery, and synchronization. An emulator adapter receives resolved inputs and prepares a launch; it must not independently own progress synchronization.
- Pass executable arguments as literal arrays and environment values as child-scoped maps. Treat metadata and paths as data, never shell templates. Validate structure, encoding, path ownership, and NUL boundaries before effects. Never log environment values or credentials.
- Prefer explicit dependencies and errors over hidden global state. Propagate failures with actionable context to the boundary that presents them.
- Bound external operations, responses, retries, and cancellation. Design retries around partial completion so they cannot duplicate or destroy state.
- Protect persistent state against interruption and concurrent processes. In-process mutexes do not coordinate independent processes. Use stable OS locks, atomic publication, durable checkpoints, and readback where the effect requires confirmation.
- Validate paths and archive entries before writes. Confine extraction to private staging; handle traversal, symlinks, duplicate/colliding entries, resource limits, and partial publication. Do not fall back to replacing an existing public destination after an exclusive operation fails.
- Preserve unrelated files, settings, console identities, and saves. Inspection should be read-only. Removing a library entry does not imply permission to delete game data or progress.
- Unknown, incomplete, failed, and confirmed-empty observations are different states. A failed scan or API request is not evidence of absence or deletion. Scope failures to the affected resource when possible without hiding incomplete results.
- Keep identity independent of display names, paths, and transient enumeration indices. Verify correspondence at the boundary that consumes the resource; do not assume two processes enumerate devices in the same order.
- Preserve unsynchronized progress until confirmed synchronization or an explicit resolution. Missing working data is damaged recovery, not an empty save. Never recover or discard files while their writer might still be alive; PID alone is insufficient process identity.
- Do not let best-effort preference capture, notifications, artwork, or diagnostics compromise game-save correctness.

## Logging, feedback, and performance

- Separate user-visible results and UI state from operational logging. Errors requiring action must be visible without enabling verbose logs.
- Keep detailed file logs at info, warning, and error severity with consistent UTC timestamps, source location, and useful operation context. Start a new segment at 1 MiB and retain the ten newest segments; keep long sessions logging. Surface logging failures and retry without changing operation results.
- Log long operations by phase and resource, with rate-limited byte/progress updates and verification phases. Redact tokens, passwords, authentication headers, and sensitive URLs/parameters.
- Keep logs free of terminal escape sequences. Any future helper CLI must separate requested results from diagnostics, provide useful help/examples and meaningful statuses, and handle interruption and closed pipes cleanly.
- Include meaningful user feedback with features: confirmed completion, important state changes, and problems requiring attention. Respect preferences, deduplicate unchanged events, and keep delivery bounded, optional, and independent of correctness. Routine polling must not generate notification spam.
- Measure actual phase timings before performance changes. Reuse verified derived assets while preserving fresh validation and repair. Do not parallelize state mutations or weaken ownership, readback, or recovery to improve timings.

## Verification

- Test observable behavior at its owning boundary, including persistence, uncertainty, identity conflicts, cancellation, retries, interrupted writers, and recovery. Avoid tests that mirror implementation details or incidental filenames/wording/line endings.
- For each substantive bug, add two or three meaningful regression cases proportional to its scope: the trigger and related failure boundaries. Avoid redundant assertions and coverage inflation.
- Make concurrency regressions deterministic with held production locks, explicit process coordination, controlled failure points, and forced timestamp ties. Repetition supplements those cases.
- Use native macOS, Linux, Windows, and Android checks for implemented capabilities. Keep OS-specific tests enabled on their native runners. Compile tests as well as the app when doing local cross-checks.
- Schedule native behavior checks and applicable race/sanitizer checks independently so one failure cannot hide another result. Preserve complete logs and identify the tested revision, host, failing test, and error.
- Do not hide failures through retries, skipped tests, relaxed assertions, or larger timeouts without establishing the cause. Apply targeted corrections, run affected regressions, and report unrelated failures separately.
- Distinguish advertised upstream support, static analysis, compilation, native automated execution, real integration checks, and owner-performed input/visual verification. Never claim cross-platform support from a successful build or one host's gameplay.
- Verify external integrations against real emulator and platform behavior when in scope, preserving existing progress. Record exact builds, configuration, devices, and results. Mocks and generated configuration do not establish working input, focus, rendering, or synchronization.
- For Linux input/focus/window failures involving Steam, compare a child-only X11/XWayland backend early when available, and verify the backend actually loaded. Keep the same game/devices for comparison. This is a diagnostic experiment, not a global default or proof that Wayland is generally broken.
- Do not use computer-control or computer-use tools unless the owner explicitly asks. Prepare the application or artifact using supported code/CLI/API paths, then provide precise observations for owner verification. Record that evidence as owner-performed.

## Documentation and delivery

- Keep PROJECT.md about the product, IMPLEMENTATION.md about steps/status/acceptance, AGENTS.md about enduring engineering practices, and research documents about evidence and proposals. Update each alongside the corresponding work.
- Report what changed, why, how it was verified, and material remaining limitations. Do not claim an unexecuted check passed or a researched capability is implemented.
- When delivering a feature, include concrete commands or UI actions, prerequisites, output locations, expected observations, external effects, and cleanup. Maintain the walkthrough in README.md; automated tests supplement it.
- When supplying a commit message, use a fenced `text` block with a short first line, a blank line, and grouped `-` bullets describing code changes. For code commits, omit documentation-only changes from that description. Do not misrepresent documentation-only work as code implementation.
