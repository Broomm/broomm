# Rooted DuckStation transactions

Current Broomm syncs only ordinary in-game saves. Save states remain local.
Earlier state-transfer observations describe their tested builds. See the
[current save contract](slotted-saves-and-ps3-iso.md#save-states-and-recovery).

PR #6 contains this implementation and the Sega 32X acceptance work.
Builds 1125–1126 exercised rooted PS1 saves on the Thor. Earlier build 1122
establishes the document handoff separately from these save transactions.

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
Private settings can include DuckStation's nested post-processing sections.
The loan writer preserves those section names and validates preference keys
before publishing the temporary configuration.

Existing initialized BIOS images are copied read-only into private storage.
The reviewed beta reads `BIOS/SearchDirectory` and `MemoryCards/Directory` for
these directories. Native startup logs in build 1125 showed the fallback paths
when the earlier preview used `Folders` keys. The corrected settings loan
publishes the two native keys and retains explicit per-game card paths.
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
  mechanism tests.
- Thor build 1125 (`d4dec29`, PR run 42539519239) passed normal Set up and Play
  with DuckStation beta 12126. Mega Man X4 restored the existing RomM card,
  generated native Slot 4 and a resume state, then uploaded and read back
  ordinary primary 262 and state archive 52. Original settings and manual
  states stayed byte-identical; the emulator updated its own playtime.
  Returning immediately after Close Game initially reported uncertain closure.
  Check for exit then proved the same native generation, completed the settings
  pause/disposal, published both snapshots and cleared all three journals.
  The follow-up waits briefly only for the identified closing generation or its
  menu transition. It still requires a fresh positive closure proof before any
  file effects.
- Build 1126 (`7cf35ed`, [PR run 42541477118](https://github.com/Broomm/broomm/actions/runs/42541477118))
  passed all CI checks and five target packages. Native logs verified the
  private BIOS, memory-card and state directories. The owner's profile loaded
  the existing Mega Man X4 card into gameplay, then used the game's Save menu
  to create Data 1 on the previously empty card 2. Broomm verified Close Game
  and completed automatically: RomM readback confirmed primary 266 (both
  whole cards) and archive 55 (including eleven retained Mac states). Both
  128 KiB cards were restored on a new Play. The game's own Load Data menu read
  Data 1 from card 2 and returned to Stage Select. DuckStation's older title
  state only helped reach that menu; it predates the new card and DuckStation
  explicitly reported replugging the current card. Card 1 stayed byte-identical.
- The second RomM profile started without the owner's cards or manual slots.
  Its native Slot 2 published and read back as primary 264; the owner's native
  Slots 1 and 4 were separate. The owner's touch layout persisted across
  sessions and a Broomm upgrade; the other profile kept its own layout.
- With Wi-Fi disabled on the USB-connected Thor, a normal Close Game left a
  verified pending local snapshot and no remote changes. After reconnection,
  Broomm uploaded and read back primary 265 and archive 54. The next Play
  installed the queued Slot 1 bytes exactly. Broomm also refused to finish
  while the native writer was live, including after Broomm alone was stopped
  and restarted. The journal, prior cloud checkpoint and same native writer
  survived the interruption, and Return to emulator brought back the game.
  After Close Game, Review and finish session published and read back primary
  267 and archive 56, restored the standalone settings, and cleared all three
  journals.
- On build 1126, Remove verified backups of seven owner-profile files and
  four second-profile files before Android uninstalled DuckStation. The same
  official APK reinstalled with a new Android UID. After native first-run
  setup and Broomm Set up, normal Play restored both private archives byte for
  byte into new workspace generations. The second profile's native state
  picker showed only its own Slot 2, and DuckStation loaded it. Both profiles
  completed automatic sync after normal Close Game (primaries 268 and 269),
  with no recovery journals left. The device test
  independently preserved and restored the eight standalone files, including
  the original settings, BIOS, and five states; Broomm's removal backup covers
  its own profile data. The PSP and RetroArch preservation audits passed.

The [Sega 32X follow-up](android-retroarch-cores.md) verified real Chaotix
gameplay, isolated native states, upload/readback, gameplay state replay and
exact SRAM transport. The test did not create new in-game cartridge progress.

Retained failures include the test transport's missing main looper, assuming a
read-only rather than executable first ELF mapping, an unrelated open SQLite
cache, and a misplaced ready signal caught by the new handshake regression.
The latter refused the operation and left the native process running. The
corrected test asserts that all four disposable target threads are in tracing
stop before the parent can approve. Original assertions/limits were retained.

## Device walkthrough

Install the new retained-key PR APK over Broomm. On the rooted Thor, choose
**Emulator Settings → PlayStation → DuckStation → Set up**. Obtain the reviewed
official APK through its page if needed; open it once for native initialization
and controller setup. Allow Magisk on the first requested root action. Normal
Play provisions private cards/states/BIOS and launches the external app. Save
in-game, use **Close Game**, then return to Broomm for verified completion.
The brief menu open/pause flushes cached preferences; no user closure
acknowledgement is used when this proof succeeds.

If Broomm was stopped while a game was open, choose Play again under the
original profile to reach recovery. Use **Return to emulator** if the game is
still running. After **Close Game**, choose **Review and finish session** if
Broomm still shows the recovery screen. Broomm checks closure again before
touching saves. An uncertain or interrupted writer leaves progress for review.

**Remove** asks Android to uninstall DuckStation, which deletes standalone
files. Broomm verifies both private profile backups before requesting that
uninstall. To reuse them, reinstall the same reviewed APK, finish its first-run
setup, close it, and use **Set up** in Broomm again. The first Play or Open
emulator for each RomM profile restores its archive into a new workspace.
