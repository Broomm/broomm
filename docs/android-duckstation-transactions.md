# Rooted DuckStation transactions

2026-11-08. PR #6 contains this implementation and the remaining Sega 32X
acceptance work. Packaged two-account PS1 acceptance is **pending**. Earlier
build 1122 establishes the document handoff, not these new save transactions.

## Implementation

The reviewed universal beta 12126, Android user 0 and its ARM64 native emulator
are the initial root boundary. Setup verifies APK, signer, UID, storage
generation, media-mount correspondence, permissions and SELinux categories.
Unknown builds/ABIs/kernels keep the connected-folder alternative. DuckStation's
[official Android page](https://downloads.duckstation.org/android-testing/) is
linked for installation; its APK is not redistributed or automatically updated.

Dart owns profile/game assignment, configuration loans, cloud reconciliation,
durable checkpoints, backups and recovery. Every native file effect requires
the emulator process to be absent. Broomm creates a marked, nonce-scoped
workspace per server/profile. Each game owns two whole 128-KiB memory cards and
state directories bound to the exact APK, native ABI and installed media
publication. Original standalone cards/states are never assigned by filename.
Ordinary exports retain `duckstation-cards-v1` and `save/card1.mcd`/`card2.mcd`.

Native settings are a durable loan: retain original bytes before publication,
install private routes, capture profile preference changes while closed, then
restore and read back the original configuration. Initial preference seeds
exclude account secrets/history. Later private settings remain in that profile;
configuration and BIOS bytes never enter game cloud exports. Open emulator is
detached and uses the same private settings. Full private backups retain two
verified generations before removal; reinstall uses a new storage generation
and replays the verified archive. Interrupted writes/loans keep their journals
and held copies. Missing known working data is damaged recovery, not deletion.

Existing initialized BIOS images are copied read-only into private storage.
If missing on Play, the existing checksum-verified PlayStation firmware workflow
obtains the unique 512-KiB `bios.bin` from that RomM platform's catalogue. No
external BIOS source or new download dependency is added.

States additionally require the observed version-97 envelope and matching
temporary document publication. Bounded media references, nonoverlapping file
regions and payload limits are validated before native installation and cloud
capture. This reads state files and the installed publication record; it does
not checksum ROM payloads on launch. Incompatible or foreign states remain held.

## Native closure and cached preferences

The beta's Close Game leaves its process and settings cache alive. A menu open
and pause lets its Java `MainActivity.onPause` save the retained settings.
Android's background classification alone is insufficient: the Thor reports
`LAST_ACTIVITY` while its activity is only paused. The adapter instead requires
the binary **client** `wm_on_paused_called` event after a fresh barrier, with
exact PID, UID, main thread, activity, buffer and clock correspondence. A later
resume/create/start invalidates the proof, including timestamp ties. Android
13 emits this event after the virtual callback returns; see the
[framework implementation](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android13-release/core/java/android/app/Activity.java).
System-server activity text/timeouts do not supply positive callback proof.

The exact APK/ARM64 ELF review identifies only these fixed, non-secret fields:

| ELF-relative offset | Observation |
| --- | --- |
| `0xa28651` | Native system state; zero after teardown |
| `0xa28980` | Outstanding asynchronous state publications |
| `0x9a5f80`, 64 bytes | Eight detached memory-card object pointers |

The reviewed teardown calls `0x3f8044`, clears each card pointer, flushes its
changes and waits on its pending-save flag before destruction; it precedes
the system-state-zero store at `0x43a434`. The independent state-publication
counter must also be zero. The app/ELF hashes are in the preceding
[research evidence](android-duckstation-root.md). No heap scan, settings-object
introspection, code injection, process-memory write or upstream binary/source
redistribution is used.

An owned JNI adapter opens a generation-bound pidfd, then a disposable child
seizes and interrupts every thread. Two stable enumerations, exact mappings,
all 69 status bytes and protected writable descriptors are checked while held.
The parent rechecks package/process correspondence, background state, activity
absence and fresh completed settings pause **while the target remains held**.
Only then can the child signal the pidfd. Existing/concurrent foreign stops and
tracers are refused. A child deadline and parent-death signal release ptrace
ownership on interruption; no `PTRACE_O_EXITKILL` is used. The kernel's
[ptrace contract](https://man7.org/linux/man-pages/man2/ptrace.2.html) and
[pidfd signal contract](https://man7.org/linux/man-pages/man2/pidfd_send_signal.2.html)
describe these mechanisms.

Protected descriptor roots cover external app files and internal `files`.
The beta keeps `cache/achievements.db` open even with achievements disabled;
that SQLite cache is outside the game/settings boundary. Its open descriptor
does not imply a game writer. Native cache contents are not synchronized.
Missing process identity after a possible launch means interrupted recovery;
it cannot impersonate normal Close Game. Loss of proof or kernel capability
refuses file effects rather than increasing timeouts or inferring closure.

## Mechanism choice, distribution and maintenance

The existing approved libsu 6.0.0 root service remains the access/lifetime
boundary. Shell/PID signalling avoids another binary but cannot bind a signal
to one process generation or close the check-to-writer race. A separate owned
helper would duplicate packaging, IPC and cancellation already supplied by that
service. The selected small owned JNI mechanism supplies only kernel effects;
it adds no external runtime library and leaves domain decisions in Dart.
It adds four-ABI NDK compilation, JNI keeping/packaging and independent native
kernel/sanitizer checks. Those maintenance costs and the reviewed-build limits
are explicit; this is not evidence that another emulator shares this protocol.

Source: `android/app/src/main/cpp/root_process.c`, built by its `Android.mk`
through Gradle's external native build. Toolchain: existing pinned NDK
`29.0.14206865`; development tools remain project-local/Devbox-managed. Runtime
dependencies are Android system libraries. The component is Broomm-owned source;
no copied third-party implementation or additional runtime dependency is added.
Final APK library sizes/hashes and packaged execution are recorded with the
build acceptance, separately from developer fixture compilation.

## Verification to date

- Four Android ABI compilations pass with warnings treated as errors. ARM64
  kernel tests on Thor cover a held writer, new writer after a caller snapshot,
  changed process/mapping, a held writable descriptor, multiple threads,
  parent-side lifecycle refusal while every thread is stopped, preexisting and
  concurrent foreign stops, and interrupted root-owner recovery.
- The production Kotlin/JNI adapter disposed of a normally paused native menu
  cache only after the frozen parent check. Its first live attempt identified
  the unrelated SQLite descriptor; the save-directory guard remains enabled.
- Native file fixtures pass partial incoming streams, lost exclusive-link
  acknowledgement, exact UID/group/mode/label readback, descriptor capture,
  staged replacement, writer arrival and foreign game/build/traversal/BIOS
  mutation refusals. Only fresh disposable workspaces were removed.
- Framework pause parser cases and captured real Thor binary events pass. The
  state-envelope validator accepts actual native Slot 4 and its stable media
  reference. Host transaction/supervisor cases cover two accounts, cloud cards
  and states, preferences, lost settings replies, unsafe routes and overlapping
  automatic completion. Full pre-package source checks are tracked separately.
- Original native settings, BIOS and Slots 1–4 remain byte-identical after the
  mechanism tests. No PS1 cloud session has run on the physical device yet.

Retained failures include the test transport's missing main looper, assuming a
read-only rather than executable first ELF mapping, an unrelated open SQLite
cache, and a misplaced ready signal caught by the new handshake regression.
The latter refused the operation and left the native process running. The
corrected test asserts that all four disposable target threads are in tracing
stop before the parent can approve. Original assertions/limits were retained.

## Device walkthrough and remaining acceptance

Install the new retained-key PR APK over Broomm. On the rooted Thor, choose
**Emulator Settings → PlayStation → DuckStation → Set up**. Obtain the reviewed
official APK through its page if needed; open it once for native initialization
and controller setup. Allow Magisk on the first requested root action. Normal
Play provisions private cards/states/BIOS and launches the external app. Save
in-game, use **Close Game**, then return to Broomm for verified completion.
The brief menu open/pause flushes cached preferences; no user closure
acknowledgement is used when this proof succeeds.

Required before PR #6 acceptance: actual ordinary memory-card creation/loading,
manual state upload/regrant/replay, both saved RomM accounts, preference
persistence, offline retention/reconnect, interrupted/live-writer recovery,
normal Remove/reinstall with verified profile restoration and repeated prior
PSP/RetroArch preservation. Then finish Sega 32X's in-game ordinary-save and
two-account round trips; its earlier state/rendering observation is insufficient.
Do not extend this PR to other standalone emulators.
