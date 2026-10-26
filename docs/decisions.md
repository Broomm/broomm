# Confirmed project decisions

Updated 2026-10-17 from the owner's initial answers and application follow-ups. These decisions supersede the earlier open alternatives. Detailed behavior lives in [PROJECT.md](../PROJECT.md); this record prevents settled questions from being reopened.

| Topic | Decision |
| --- | --- |
| Initial application UI | Server address and RomM login lead to a PS5-inspired Home with Broomm settings, Game Store and Emulator Settings. First implement Home, Broomm preferences and catalogue browsing/search/platform filters; managed emulator setup follows. Every flow must be controller navigable. |
| Desktop executable ownership | Default to Broomm-managed installations shared by its profiles. A user can select an existing system executable. All session configuration/data stays in Broomm-owned storage in either case; never modify system-wide or default-user emulator settings/files. |
| Development SDKs | Devbox manages project dependencies. Pre-provisioned Xcode/Apple SDK and native Windows C++/Windows SDK hosts are approved. No new OS dependency installation is authorized. |
| Profile game files | Share installed ROM/game payloads. Keep saved progress, states and other writable game data separate by server/account. |
| Server/profile selection | Persist multiple servers; only one server is active at a time. Select server, then one of its known profiles or Add profile. Follow Teddy's explicit activation, server-filtered chooser and connection-scope lifecycle. |
| RomM baseline | Initially target RomM **5.4.0** at the owner's instance `https://romm.docubi.casa`. Its public schema reports 5.4.0 and was retrieved through the supplied HTTP forward proxy; see the [snapshot and verification limits](reference/README.md). |
| Emulator scope and host focus | Use PGCS's concrete emulator roster, documented in [emulator support](emulator-support.md). Focus development and hands-on validation on macOS and Linux first; Windows and Android remain targets. |
| Android | Detect/use compatible installed emulator apps and offer installation when needed. Hand off ROM and the profile's saves/states through supported launch/import paths. No desktop controller assignment, injection, overlays, or desktop-style emulator sandboxing. |
| Desktop settings integration | Support a small emulator set tightly. Prefer DLL/shared-library injection and other external integration over emulator modification/forks. Know which settings require restart and notify only for those changes. |
| Steam launch flow | Steam → Broomm → emulator must keep gameplay and Broomm settings/pairing available through a controller, including gamescope-based Steam Gaming Mode. The goal is settings over the game without manual desktop window management; the current macOS separate-window prototype is not acceptance for this route. |
| Session concurrency | One active Broomm game at a time is a hard requirement, including independent Broomm processes sharing its data. Server/profile changes cannot transfer a running session. |
| Offline progress | Retain saves locally. On reconnection under the originating active account, upload without prompting if the remote hash equals the last acknowledged common hash. If both sides changed and differ, notify and let the user keep local or RomM progress; preserve both until committed. |
| Implementation | Workflows are Dart within Flutter. Do not reuse PGCS code or add Go code/helpers. Optional injection bridges may be written in C and bundled precompiled. PGCS remains a source of engineering practices, emulator knowledge and behavior, not application code. |
| Emulator updates | Never automatic. Initial provisioning and app-driven updates use explicitly selected setup JSON files. Users may manually update a managed emulator or obtain/import a newer setup file through Broomm and start installation. Never update a selected system installation. |
| Remembered authentication | Avoid repeated password entry for known profiles; investigate Argosy's token persistence and restore reusable RomM credentials while preserving server/account isolation. |
| Mixed-input text entry | Keyboard navigation must not start typing: Enter activates inline editing, Escape stops editing while retaining focus. Pointer/touch edits inline; controller activation opens the virtual keyboard. |
| Emulator settings organization | List every RomM platform, its supported emulators and an effective default for Home Play. Expand setup review/confirmation in the selected card and make every action reachable by arrows/controller. Configured emulators need a removal button. |

The single-server rule means inactive server/account queues stay durable but paused. Reconnection automatically resumes eligible work for the active owner; it does not authenticate every saved server in parallel. This is the documented interpretation of one active server and Teddy's single active connection model.

Android's simpler behavior is an explicit exception to desktop emulator isolation. Broomm must still distinguish the active account's progress and be honest about external apps that cannot import/export or redirect saves/states. The launcher UI itself retains controller navigation and touch support; the exclusion concerns emulator input routing and in-game overlays.

Computer-game/Proton support and RetroAchievements remain later work. Licensing for future Broomm distribution, exact OS/API/CPU baselines and firmware sourcing are remaining details, not reasons to reopen the decisions above.
