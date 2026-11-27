# Cemu and desktop Remote screen — 2026-11-27

## Agreed scope

The owner requested Wii U Remote screen and best-effort Linux/Windows hosts,
then explicitly selected full Cemu setup, launch and save handling. This branch
is `codex/remote-wiiu-desktop-hosts`. Existing macOS DS/3DS behavior remains the
baseline. Android hosting is deferred; Android remains a remote client.

## Upstream evidence

Reviewed [Cemu v2.6](https://github.com/cemu-project/Cemu/releases/tag/v2.6),
its `CemuApp.cpp`, `CemuConfig.cpp`, `InputManager.cpp`, `DSUController.cpp`,
`DSUMessages.h` and `PadViewFrame.cpp` at that tag. Cemu's native DSU client
consumes buttons, sticks, analog triggers and touch, not only motion. A bounded
loopback server inside Broomm therefore needs no operating-system virtual device
or driver. Wii U touch is 854×480, rather than DS/3DS's 256×192. The separate
GamePad window is titled `GamePad View` in the English UI.

Official v2.6 packages exist for macOS Intel, Linux x64 and Windows x64. The
macOS Intel DMG is 36,588,188 bytes, SHA-256
`698c4b298f94983e4d6c30e9687ba8ff05094dd3930837c5104cddc0b0a49e4e`.
It was inspected from a read-only mounted image. Apple Silicon needs an already
installed Rosetta; Broomm must not install it. No official Linux ARM64 Cemu
package was found. Application compilation on ARM64 is not Cemu availability.

Cemu's portable directory is adjacent to `Cemu.app` on macOS, and adjacent to
the executable elsewhere. Profile-private launch copies/anchors are required;
redirecting HOME alone does not isolate Cemu. Settings and controller profiles
are XML. Native title identity must be established before transferring saves;
filenames and RomM display names are not a safe save boundary.

## XML dependency decision (approved)

Candidate: pin [xml 7.1.0](https://pub.dev/packages/xml/versions/7.1.0), MIT,
published 2026-09-27, Dart ^3.13.0 (matches this application). Published archive
SHA-256: `0fe8cc98946def31cbcbc8734aa4067031e6f65ea3a78a508060bfed2200bfeb`.
It is pure Dart on macOS/Linux/Windows/Android, including ARM64; no native runtime,
compiler or system package is needed by users. Runtime dependencies are `args`
^2.7.0, `meta` ^1.19.0, `collection` ^1.19.1 and `petitparser` ^7.1.0. Resolve and
commit exact transitive versions in pubspec.lock if approved. Existing Flutter
license delivery includes package license notices.

Compared with an original parser, this maintained package already handles XML
escaping, comments, nesting, document validation and useful parse failures.
DOM edits can preserve unrelated element values, though serialization is not
byte-identical. Only bounded private files should be parsed; reject DTDs and
unsupported encodings, duplicate owned keys and oversized input before effects.
Parsing is synchronous and not interruptible mid-call, so cap settings/metadata
size and check cancellation around reads/parsing. Large catalogues require a
bounded streaming parser or isolated worker with cancellation, not an unbounded
UI-thread DOM. Malformed files must leave prior configuration/progress intact.

An original restricted XML reader would avoid four package dependencies and
give tighter lexical preservation, but Broomm would own entity decoding,
well-formedness, nested edits and hostile-input limits. Regex replacement alone
is unsuitable. An OS XML library would add divergent FFI/runtime dependencies,
especially on Windows and Android. Recommendation: the pinned pure-Dart package;
The owner approved `xml` 7.1.0 on 2026-11-27.

## Status and verification boundary

The initial loopback DSU implementation passes three actual-UDP protocol cases
on macOS (wire checksums, mapping/touch, malformed requests, input expiry and
socket cleanup). The owner approved xml 7.1.0 and the implemented architecture/verification is
now tracked in [the integration guide](../cemu-and-desktop-remote.md). This
does not yet establish Cemu gameplay, save synchronization, Linux/Windows native
execution or owner acceptance. Those results belong in IMPLEMENTATION.md when
observed. No generated configuration is evidence that an emulator consumed it.
