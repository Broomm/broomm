# Rooted Dolphin on Android

Current Broomm syncs only ordinary in-game saves. Save states remain local.
Earlier state-transfer observations describe their tested builds. See the
[current save contract](slotted-saves-and-ps3-iso.md#save-states-and-recovery).

The root route is pinned to [Dolphin 2609a](https://dolphin-emu.org/download/),
version code 43114 on Android 11 or newer, user 0 and ARM64. Broomm checks the
[official APK](https://dl.dolphin-emu.org/releases/2609a/dolphin-2609a.apk)
against SHA-256 `7f753124d289585a4e6fa649d4852c78e674bd45d5d1f6f6b891fe65460c1793`
before opening Android's installer. The installed signer is
`8e7556d64ce8f7f15e36c4b3380aab0e326431146f9b26d2adee35326951fcab`.

On the Thor, Dolphin's first open created its app-owned external root, with
the same inode and security label in Android's logical and underlying
media paths. The root adapter rechecks those properties and the installed
package before each operation. It reads the effective default layout and
refuses custom or ambiguous save locations. Default GameCube Slot A uses
GCI Folder and Slot B is disabled. Slot B can also use the default GCI
Folder. The adapter scopes GCI files by their six-byte game identity,
refuses legacy raw-card migration, and leaves Wii NAND content outside the
selected title's ordinary data directory alone. Numbered Dolphin states
are scoped to the selected disc and exact installed build. Each state is
bounded at 64 MiB and the title inventory at 512 MiB. Linked paths, foreign
headers and unsupported movie companions keep recovery pending.
Dolphin's global state undo files and the selected game's deleted GCI
backups stay in the native recovery transaction and are excluded from
RomM uploads. The transaction restores their original bytes.

The reviewed upstream sources describe [native user-directory selection](https://github.com/dolphin-emu/dolphin/blob/2609a/Source/Android/app/src/main/java/org/dolphinemu/dolphinemu/utils/DirectoryInitialization.kt),
[GameCube slot defaults](https://github.com/dolphin-emu/dolphin/blob/2609a/Source/Core/Core/Config/MainSettings.cpp),
[raw-card migration](https://github.com/dolphin-emu/dolphin/blob/2609a/Source/Core/Core/HW/EXI/EXI_DeviceMemoryCard.cpp)
and [state filename and title header](https://github.com/dolphin-emu/dolphin/blob/2609a/Source/Core/Core/State.cpp).

## Setup and play

Choose **Emulator Settings → GameCube** or **Wii → Dolphin → Set up**.
Install or update only if the selected APK needs it. Open Dolphin once,
let it finish initializing, then close it and check setup. Use the default
GameCube GCI folder configuration or the default Wii NAND. Play an installed
disc from Broomm, save inside the game or use Dolphin's native state menu,
then choose **Exit Emulation** before finishing sync. Android may retain the
Dolphin process. Stop it through Android's app settings after exiting the game
if Broomm still detects it. Broomm keeps the original native bytes and recovery
journal until it can verify capture and restoration.

This increment covers GameCube discs with region codes E, J or P and ordinary
Wii discs. WAD channels, Wii add-on installation and raw GameCube cards are
outside the rooted route. Use shared-folder setup for eligible custom
configurations.

## Thor verification

The Thor fixture ran the production file adapter against the official
installed package. Both GameCube and Wii accepted a scoped save and state,
returned the exact bytes through descriptors, refused foreign title files,
and removed the fixtures. Dolphin's configuration hash was unchanged.

The ordinary Setup and Play actions launched Luigi’s Mansion (GLME01) and
Wii Sports (RSPE01) in official Dolphin 2609a on the Thor. Native savestates
were enabled in Dolphin’s General settings for these checks.

- GameCube, Broomm builds 1134, 1148 and 1152. Luigi’s Mansion created a 31,594,946-byte
  native state in the foyer. RomM confirmed version 272. The next Play
  restored the identical state, and native Quick Load returned to the foyer.
  Build 1148 resumed the later tutorial state and reached Toad’s save point.
  The game wrote a 24,640-byte Slot A GCI. RomM verified version 277 with
  the GCI and both existing states. Build 1152 restored all three files byte
  for byte. The game’s file picker showed **File 1 · Up to Area 1** and
  loaded it into the lab. The restored working card used mode 0600 with
  the original emulator owner, group and security label.
  The second RomM account started with **New Game** and no state files.
  It created a 25,445,582-byte Slot 1 state. RomM read back version 278
  and replay restored only that state. Dolphin loaded it with File 2
  highlighted, and the primary account’s version 277 stayed intact.
- Wii, Broomm builds 1134 and 1136. Wii Sports created `RPSports.dat` and
  `banner.bin` in its NAND save directory, plus two native states. RomM
  confirmed version 273. After an in-place upgrade to 1136, Play restored all
  four files byte for byte and Dolphin loaded slot 1 at the sports menu.

Both games exited through Dolphin’s Exit Emulation action. When Android
retained a cached process, Broomm required that process to stop before
writing saves. Build 1152 also refused startup with the cached launcher
present and kept the RomM checkpoint unchanged. The read-only check now
completes before Broomm opens a recovery record. The Wii round trip and
GameCube card write used the primary account. CI passed checks and all five packages for the
[build 1136 revision](https://github.com/Broomm/broomm/actions/runs/42565836150),
the [Dolphin startup fix](https://github.com/Broomm/broomm/actions/runs/42577141071)
and [cumulative build 1152](https://github.com/Broomm/broomm/actions/runs/42577144121).
