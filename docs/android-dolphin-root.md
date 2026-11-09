# Rooted Dolphin on Android

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

This increment covers GameCube disc regions USA, Japan and PAL and ordinary
Wii discs. WAD channels, Wii add-on installation and raw GameCube cards are
outside the rooted route. Use shared-folder setup for eligible custom
configurations. Device initialization and workflow tests are separate from
end-to-end game and RomM verification.

The Thor fixture ran the production file adapter against the official
installed package. Both GameCube and Wii accepted a scoped save and state,
returned the exact bytes through descriptors, refused foreign title files,
and removed the fixtures. Dolphin's configuration hash was unchanged.
