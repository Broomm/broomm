# Remembered sign-ins and platform settings

Updated 2026-10-17. This follow-up implements reusable RomM authentication, explicit text editing, platform-based emulator settings and managed uninstall. The earlier [94-test managed milestone](managed-emulators-and-play.md) remains historical. Exact command results and source fingerprints are in [the evidence record](remembered-signins-and-platform-settings.json).

## Authentication investigation and implementation

Argosy stores a bearer token per account and reconnects with that saved token. Its connection manager checks the returned user identity, coalesces initialization and handles unavailable servers separately from rejected credentials. It supports direct tokens, pairing-code exchange and a newer device-approval flow. This explains why its users normally enter credentials only once; password replay is unnecessary. Sources inspected: [connection manager](https://github.com/rommapp/argosy-launcher/blob/main/app/src/main/kotlin/com/nendo/argosy/data/remote/romm/RomMConnectionManager.kt), [account entity](https://github.com/rommapp/argosy-launcher/blob/main/app/src/main/kotlin/com/nendo/argosy/data/local/entity/RomMAccountEntity.kt) and [account repository](https://github.com/rommapp/argosy-launcher/blob/main/app/src/main/kotlin/com/nendo/argosy/data/repository/RomMAccountRepository.kt). The downloaded public-source snapshot and fingerprints identify what was inspected. This is source inspection, not an Argosy runtime test or an audit of its credential encryption. No Argosy code is reused.

Broomm retains the selected RomM 5.4.0 protocol: password login receives an OAuth access/refresh pair; token or eight-character alphanumeric API key pairing-code login receives a reusable client token. See the [tagged auth implementation](https://github.com/rommapp/romm/blob/5.4.0/backend/endpoints/auth.py) and [client-token implementation](https://github.com/rommapp/romm/blob/5.4.0/backend/utils/client_tokens.py). A new QR/device-approval UI is not part of this change.

After a successful login, Broomm saves only the refresh token or long-lived client token. Passwords, one-time pairing codes and OAuth access tokens are not persisted. The secure envelope binds the credential to the normalized server URL and remote user ID under the stable local profile ID. Selecting a known profile restores authentication and verifies the returned account identity before opening Home. Startup still shows saved servers and requires explicit profile selection; it does no account work before that choice.

**Switch profile** retains remembered credentials. **Sign out on this device** removes and reads back the current profile's credential, then closes its client. It keeps the profile name, server, installed games and private progress. It does not revoke tokens remotely. Missing or rejected credentials lead to login. Network failure, locked storage, corrupt envelopes and mismatched identity keep the chooser with an error and preserve existing records. A successful login/restore whose secure write fails remains usable in memory, with a visible warning. Its active refresh avoids reloading an older stored token after a publication failure.

A stable nonsecret `authentication-locks/<profile-id>.lock` protects read → refresh → rotated-token publication across processes sharing one data root. In-process queues use the canonical data path and profile ID. Acquisition is bounded to three seconds; native calls have a twelve-second Dart deadline. One client also coalesces concurrent refresh requests. Ordinary HTTP requests retain their existing deadlines, response limits and redirect policy. A refresh endpoint rejecting the grant (400/401) requires reauthentication; other service failures remain uncertain and do not erase the saved credential. Tokens are never logged. Secure-store writes/deletes are checked by readback.

## Storage choice and host scope

Before implementing, the package and direct-API choices were presented to the owner in the work updates. No new package was added; `pubspec.lock` and Devbox dependencies are unchanged.

| Option | Concrete tradeoffs | Outcome |
| --- | --- | --- |
| `flutter_secure_storage` 11.2.0 | Maintained, BSD-3-Clause, common API for the four targets, but adds federated native packages. Its Linux implementation requires libsecret at build/runtime and an existing keyring provider; Windows documents ATL build requirements. Broomm would still own locking, refresh rotation, cancellation and account identity. | Researched, not added. [Published dependency/platform requirements](https://pub.dev/packages/flutter_secure_storage). |
| Direct OS adapters | Uses existing runner SDK/runtime APIs, no new Dart or bundled third-party library. Broomm must maintain four implementations and test host-specific limits, keyring availability, failure and packaging behavior. Native workers keep supported slow storage calls off Flutter's UI thread; a timeout reports uncertainty rather than deleting data. | Implemented. Domain/authentication workflow remains Dart. |
| Plaintext file or bundled encryption key | Avoids keyring availability but would put reusable credentials or a recoverable encryption secret beside application data. | No fallback of this kind. |

| Host | Implemented adapter and distribution implications | Verification |
| --- | --- | --- |
| macOS | Login Keychain generic-password items, service `app.broomm.romm.v1`. Security/LocalAuthentication SDK APIs; no Keychain Sharing entitlement or new runtime library. Noninteractive authentication context reports unavailable/locked access instead of opening a hidden prompt. Release signing and access across changed development signing identities still need packaging acceptance. | Separate-process write/read/update/delete check and native app test; see exact results in the JSON record. |
| Linux | GIO/GDBus from the existing GTK runner speaks Secret Service directly. Requires an existing session bus, default collection and unlocked provider; no libsecret helper or new OS package is installed. Calls run on a worker with per-call and request cancellation bounds. Locked/duplicate items are errors. Gaming Mode session availability needs a real Bazzite/Steam check. | Source inspection only; native Linux toolchain/runtime absent on this host. |
| Windows | Current-user Windows Credential Manager, linked through existing Win32 SDK `advapi32`. Native blob-size limit is enforced; an oversized envelope remains session-only with a warning. No ATL/plugin dependency is added. | Source inspection only; native Windows compiler/SDK host unavailable here. |
| Android | AndroidKeyStore AES-GCM key per profile; versioned ciphertext published with `AtomicFile` under `noBackupFilesDir/romm-signins/`. Profile-bound authenticated data, random IV, bounded reads; missing keys/corrupt data are errors, never automatic credential resets. Uses platform APIs, no new dependency. | Source inspection only; Android toolchain/device unavailable here. |

API references: [Apple Keychain](https://developer.apple.com/documentation/security/keychain-services), [noninteractive authentication context](https://developer.apple.com/documentation/localauthentication/lacontext/interactionnotallowed), [Secret Service specification](https://specifications.freedesktop.org/secret-service/latest/), [Windows credential writing and limits](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credwritew), [Android Keystore](https://developer.android.com/privacy-and-security/keystore). No OS SDK implementation or reference-project source is copied into Broomm. The small adapters ship as part of their existing native runner, not as a separately installed service. Android emulator handoff remains outside the desktop injection machinery.

## Text entry

Navigation focus and editing focus are separate. Arrow/Tab navigation selects a read-only field without a caret. Enter starts inline editing; Escape ends editing and leaves that field selected so arrows navigate again. Pointer/touch starts editing immediately. Explicit controller activation opens the existing virtual keyboard, then returns to read-only navigation. Shortcuts for text editing remain local to the editing state, and changing input devices does not require restarting. Regression cases cover reentry, caret movement, Escape ownership, pointer activation and controller keyboard return.

## Platform setup, default and removal

Emulator Settings requests all platforms from the active server, sorts them by name and displays each platform's supported emulator cards. A confirmed-empty result, loading, failed discovery and retained known platforms remain distinct. Unsupported platforms display a small message. The current validated pack still contains RetroArch/Snes9x, Dolphin, RPCS3, Azahar and Ryubing, with one choice per supported platform. This UI does not imply the rest of the roster or other hosts have gained native packages.

Each supported platform has an effective default. A configured choice takes precedence over an unavailable saved preference; Home Play resolves through that same selection. Choosing another configured emulator persists the default under server ID and canonical platform slug, shared across profiles on that server. The current single-choice pack shows a Default badge; another validated choice is needed to exercise a real alternative-emulator launch.

Setup review expands within the clicked card, including exact sources, resource requirements, Start setup and Cancel. Importing a setup JSON only prepares sources/review. It does not install anything. Explicit numeric focus ordering keeps header actions, card controls and dynamically inserted confirmation in sequence; focused actions scroll into view. Native controller-channel and keyboard regression tests traverse the real application route. Phone/desktop PNGs were inspected as widget artifacts, without computer-control tools.

Configured cards offer **Remove**. Confirmation lists the active server's platforms sharing the executable (for example GameCube and Wii both use Dolphin), and explains the effect across profiles. Uninstall holds the same session lease as setup/gameplay, validates the owned receipt and recognized top-level contents, records withdrawal plus a durable removal checkpoint, renames the exact managed release to private deletion staging, deletes it and publishes completion. An active writer or unrelated file blocks removal. Interrupted deletion remains visible as **Finish removal** and can resume after restart. Setup refuses a pending removal until cleanup completes. Closing Broomm waits for this operation.

Only the exact managed release, including app/core/installation resource slots, is removed. Profile configuration, saves, states, console data, ROM downloads, original source bundles and remote RomM content remain. Reinstall can reuse retained private profiles. User-selected system installations are not touched; their picker remains unimplemented. Default preferences may remain, but resolution always selects an available configured choice when one exists. No automatic updates or synchronization were introduced.

## Checks and owner verification

The full analyzer and 115 Flutter tests pass on macOS. They include real local HTTP refresh/restore, credential isolation and corruption, held cross-process credential/session locks, failed persistence/sign-out, explicit editing, all-platform rendering, keyboard/native-channel traversal, malformed/default ownership validation, uninstall/reinstall and durable removal retry. A tiny isolated app-bundle fixture goes through the actual card review/install/removal controls and verifies progress/source preservation. The macOS build, three native Keychain/window tests, separate-process Keychain check and real RetroArch Home Play smoke also pass. Command results are recorded separately in the JSON evidence; these do not establish owner-server or other-host acceptance.

Run the [README walkthrough](../README.md#run-broomm) for login, text entry, platform setup and removal. For verification, run Flutter tests/rendering and native builds **serially** because they share generated Swift state:

```sh
devbox run app-check
BROOMM_RENDER_ROOT=.tool-cache/research/auth-platforms/previews devbox run -- flutter test tool/render_managed_test.dart
devbox run -- dart tool/check_keychain.dart
devbox run app-build
devbox run prototype-check-macos
devbox run -- flutter test tool/smoke_home_test.dart
```

The Keychain tool uses a unique disposable identity, separate child processes and cleanup; it never reads owner sign-ins. Native Home smoke uses isolated fixture catalogue/profile data and the supplied SNES ROM, with synthetic input enabled only in that test. No interactive owner app is restarted. Rendered PNGs/logs are under `.tool-cache/research/auth-platforms/`; Home smoke retains its existing `.tool-cache/research/managed-play/` fixture data. Delete those test copies only after fixture processes exit. Use device sign-out to remove an intentional local login; deleting application data alone does not delete OS secure-store items. Never delete active lock files or private progress as uninstall cleanup.

Still needed: actual owner-server login/restart/refresh/revocation acceptance; physical mixed-device navigation; Linux/Steam keyring and native build/runtime checks; Windows/Android native checks; stable release signing/distribution; another validated emulator choice for multi-choice launch; full offline activation and save/state synchronization. Existing six-ROM gameplay evidence remains applicable to unchanged emulator bridges, but is not represented as a new six-emulator run for this UI/authentication change.
