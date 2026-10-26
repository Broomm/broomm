# Remaining details

Updated 2026-10-16. The owner answered the initial ten question groups; those decisions are recorded in [decisions.md](decisions.md) and incorporated into the product and implementation documents. Do not ask again about managed installation ownership, pre-provisioned native SDKs, shared ROMs, multiple servers, RomM 5.4.0, Android handoff, restart notices, one active game, Dart versus Go, or manual setup-file updates.

These details remain to be resolved when the corresponding work is reached. They do not block the documentation baseline or justify expanding scope:

- Exact minimum OS/API versions and CPU architectures, especially the later Windows/Android builds. Initial hands-on work is macOS/Linux; that priority is settled.
- BIOS/firmware/key sourcing. The current planning assumption is user-supplied resources; the answer about updates did not authorize downloading these assets.
- Broomm's distribution license and notices for future selected dependencies/native bridges. There is no PGCS application-code import or Go-helper licensing decision to make.
- Exact RomM 5.4.0 authentication/conditional-write contract and Android emulator package/save handoff capabilities, to be established through implementation research rather than another broad product questionnaire.
- Detailed handling of an explicit online catalogue permission revocation versus ordinary offline availability. Offline play and durable local progress are approved; a network failure must not be treated as revocation.

The initial direct probe could not resolve `romm.docubi.casa`, but the owner's `192.168.1.2:1080` endpoint subsequently worked as an HTTP forward proxy. The public API schema was retrieved and confirms 5.4.0; see [verification evidence](reference/README.md). HTTPS CONNECT returned 405, so that transport remains unverified. Authenticated integration checks and sync behavior remain pending; do not infer credentials or replace the target with a demo server.
