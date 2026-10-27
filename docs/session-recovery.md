# Launch cancellation and quit recovery

Implemented 2026-10-27. Product rules remain in [PROJECT.md](../PROJECT.md);
exact source/build fingerprints and commands are in [the evidence record](session-recovery.json).

## Cause and correction

The owner's logs showed Ryubing's first initialization exiting successfully.
Subsequent save-identity discovery repeatedly read the entire 14,638,743,603-byte
Smash Ultimate ROM. Idle first sync repeated that work after restarting Broomm.
Play waited for the worker; explicit save actions rejected the worker as busy;
Quit waited for it too. The queue was empty. The preparation Cancel action also
ignored the request while its model was busy, and native Quit had no fallback
when Dart failed to answer. This evidence does not indicate corrupted game or
save data.

Ryubing/Eden now bind their observed native title ID to the installed
server/ROM/selected-file/publication receipt and ordinary file metadata. These
lookups do not read ROM payloads or compute their checksum. Changed publications
or media metadata require native identification again rather than selecting a
save from a filename or the newest native folder. Legacy checksum-named binding
records are retained; the first launch creates a separate version-2 binding.
Existing saves, native accounts and indexes remain unchanged.

A read-only lookup against the owner's same Smash installation completed in
**11.113 ms**, including receipt and metadata inspection, with zero ROM payload
bytes read and no native launch. The earlier independent whole-file SHA-256
measurement took 48.26 seconds; that is diagnostic evidence of the removed work,
not the current launch algorithm. Full download verification remains its
separate optional setting. Save hashes/conflict checks and native executable,
firmware and add-on integrity boundaries remain in place. Explicit file
verification has a cancellable read-only worker; macOS uses its existing
CommonCrypto ABI and other hosts retain the SDK implementation. No dependency
or OS installation was added.

Explicit cloud actions reserve their operation, cancel and drain idle first
sync, then acquire the existing production lease. They do not treat background
discovery alone as a running game. Shutdown prevents new background queue/sync
admission and stops the current game before draining downloads that may be
waiting for that game to finish.

## User workflow

1. Launch an installed game. **Cancel launch** stays enabled during preparation;
   it cancels resource/transfer work and supervises a cold-initialization child
   until its writer has exited. It does not release locks underneath that child.
2. On macOS, use the red close button, Quit menu or Cmd+Q. **Closing Broomm**
   displays the current shutdown phase. Repeated requests share that flow. If
   shutdown takes over three seconds, **Quit Broomm now** leaves the launcher
   while retaining unfinished data. An emulator may remain open. A reported
   failure also offers **Retry closing** and **Keep Broomm open**.
3. If Dart does not acknowledge the native request within five seconds, AppKit
   offers **Keep Broomm Open** / **Quit Broomm**. This is a native fallback, not an
   automatic forced exit. Native requests acknowledge promptly while normal
   shutdown continues in Dart. A game route ending beneath a quit/conflict
   dialog removes its own route without dismissing the dialog above it.
4. After an interrupted launcher, choose **Play** or a game's **Options**. A
   surviving verified emulator offers **Show**, **Close emulator normally** and
   **Force quit emulator…**. Force quit requires confirmation because unsaved
   progress can be lost. The dialog rechecks for writer exit before continuing.
   Another launcher or an unidentified helper offers explanation/check/back;
   it cannot be force-terminated by this recovery UI.

The macOS adapter queries the kernel's current POSIX lock owner without writing
or deleting lock files. Its opaque handle retains `NSRunningApplication`, kernel
process start seconds/microseconds, user identity, executable path and lock
device/inode/PID. It also retains the AppKit launch date when present. Directly
spawned Ryubing legitimately has no AppKit launch date; the kernel identity
keeps that case recoverable. Both AppKit and kernel executable paths must agree.
Every control action rechecks these observations and excludes another
coordinator. A stale handle cannot
signal a replacement writer. Missing observations and inspection errors remain
unknown rather than permission to recover files. Only executables inside the
current Broomm managed/profile trees qualify for termination.

The pinned Ryubing build also aborts when its Avalonia renderer is closed before
startup completes (`CancellationTokenSource` already disposed). A second native
attempt closing during an in-flight initial resume left its window alive.
Cancellation now waits for the same confirmed native pause/title/input boundary
as successful cold initialization before requesting normal close. The wait is
bounded; a stuck emulator remains supervised and the quit/recovery controls stay
available. Failed runs are retained in the evidence directory, not hidden by
test skips or increased timeouts.

## Verification and delivery

- **405 Flutter tests pass**, including metadata-binding replacement/legacy
  boundaries, cancelled preparation with a held production lease, manual action
  preemption of idle sync, stalled/failed shutdown, route ownership and stale
  recovery confirmation. Native adapter calls in Home/options widget fixtures
  explicitly return no writer; their real I/O handoff is drained before the
  next synthetic hardware event. Static analysis reports no issues.
- **8 macOS XCTest checks pass**, including unanswered Quit fallback,
  coalescing/stale replies, normal acknowledgment, window frames/decorations,
  controller shortcuts and separate secure credential slots.
- The real pinned Ryubing `13571b902014eb732f69a13cf62c0bc3d9da0ab1542a52cca337ad0f8299ebe4`
  and supplied Mario 3D World ROM pass cold identification, writer exit before
  restore, committed save consumption on reopen, native ZIP round trip, and
  cancellation while the cold child owns the production lock. Copied private
  profiles retain progress sentinels. The corrected run took 24 seconds.
- Disposable LaunchServices and directly spawned AppKit applications pass normal quit, refused normal quit followed
  by verified force quit, stale-token rejection against a replacement,
  released-writer observation, linked-lock refusal and retained save sentinel.
  The same final adapter successfully force-terminated the real Ryubing writer
  retained from the failed early-close test and observed its kernel lock release.
  This checks actual native processes, not only mocked PID data.

Reproduce from Devbox with the approved Xcode host:

```sh
devbox run -- flutter analyze --no-pub
devbox run -- flutter test --no-pub
devbox run -- flutter test --no-pub tool/check_switch_progress_test.dart
devbox run -- bash tool/check_session_recovery.sh
devbox run -- bash tool/build_app.sh --portable --no-pub \
  --dart-define="BROOMM_DATA_ROOT=$PWD/.tool-cache/session-recovery/host-test-data"
devbox run -- bash tool/test_macos.sh
devbox run -- bash tool/build_app.sh --release --portable --no-pub
```

The Switch check requires the existing authorized test ROM and copied native
fixture described by that tool. AppKit tests compile a tiny disposable fixture
with the provisioned Apple SDK; compilers/test fixtures are not runtime
dependencies. Logs, samples, fixture data and failed attempts live under
`.tool-cache/session-recovery/`; real Switch fixture copies live under
`.tool-cache/research/library-followup/native-switch-*`. Clean these only after
their test writers exit. No owner games, progress, keys, credentials or remote
saves were changed, and no application data reset is required.

Current local delivery: [Broomm macOS ZIP](../build/releases/Broomm-macOS-session-recovery.zip),
20,429,530 bytes, SHA-256
`10d1be1312a16fc083532811bf64d71f38e245e38c5d339ddaf72d8993763fbb`.
ZIP integrity and deep/strict ad-hoc signatures pass before and after fresh
extraction. The application and three existing bridges are universal. It uses
normal `~/Library/Application Support/Broomm`, with no checkout data override.
It is a local development build with application auto-install disabled, without
notarization. Tested emulator gameplay remains Apple Silicon scoped.

Owner visual/physical-controller acceptance and live cross-device saves remain
separate. The native quit fallback/process-recovery adapter is implemented and
executed on macOS; Linux/Windows/Android native recovery verification is still
pending. Their existing writer exclusion remains required.
