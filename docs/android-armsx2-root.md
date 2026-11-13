# Rooted ARMSX2 on Android

Use Android 13 or newer on ARM64, Android user 0, and an existing root manager.
In **Emulator Settings → PlayStation 2 → ARMSX2**, choose **Set up** and
confirm Android’s installation of the pinned official ARMSX2 2.9.2 ARMv8.0
APK. The reviewed ARMv8.2 SDK33 APK can also connect. Open ARMSX2 once so it
creates its app storage, then close it and retry **Set up**. Broomm can
download a missing 4 MiB PS2 BIOS from the active profile’s RomM firmware
catalogue. It preserves existing BIOS files.

Use the default app data folder, two standard enabled memory cards and
the default save-state directory. Disable per-game memory cards in ARMSX2.
Shared-folder setup also works when the app uses a custom data location or
its private storage cannot be verified.

## Shared folder and BIOS import

1. In Broomm, open **Emulator Settings → PlayStation 2 → ARMSX2 → Set up**
   and choose **Use shared folder** if offered. On rooted devices Broomm
   can prepare `Internal storage/Broomm/ARMSX2` for a fresh setup. Keep any
   custom **App Data Folder** you already chose in ARMSX2. For a new setup
   without root, create the folder using Android’s picker.
2. Choose **Select App Data Folder** in Broomm and grant that same folder.
   You can do this while ARMSX2 still needs a BIOS. For a new setup select
   the same folder as **App Data Folder** in ARMSX2 and allow the permission
   ARMSX2 requests.
3. If the wizard needs a BIOS, choose **Prepare BIOS from RomM** in Broomm.
   The current profile needs access to the PS2 firmware catalogue and a
   verified 4 MiB PS2 BIOS. In ARMSX2, choose the **Broomm BIOS** subfolder
   inside the App Data Folder as the BIOS import source. You can also import
   your own BIOS using ARMSX2’s picker.
4. Finish ARMSX2 setup, including the games folder it requests. Keep standard
   global memory cards and turn off per-game cards. Quit ARMSX2 and choose
   **Verify selected folder** in Broomm. If ARMSX2 is still initializing its
   data, wait for its main screen before quitting and verifying again.

ARMSX2 imports the BIOS into its own storage. After confirming that the
import works, you can remove the extra `Broomm BIOS/broomm-ps2-bios.bin` copy
from shared storage. Leave ARMSX2’s own BIOS and save files in place.

## Play and recovery

Play a downloaded self-contained CHD, ISO or raw BIN with standard PS2 disc
metadata. Save in the game, or use ARMSX2’s **Save State** menu, then choose
**Close Game** and finish sync in Broomm. If ARMSX2 retains its library
process, exit that app before retrying sync. Another launch restores the
active RomM profile’s cards and matching states. The journal restores the
original standalone cards and states after capture. Keep the original game
installation and emulator while finishing a pending session.

Broomm scopes native states by the disc serial and executable checksum.
The game’s native `.ps2` cards use the same `ps2-cards-v1` ordinary cloud
format as desktop. Android states use the exact emulator build and disc
identity. The rooted adapter requires whole ECC cards and bounds each
state to 64 MiB and the selected inventory to 512 MiB. Other titles’ state
files stay outside the transfer. Custom paths, per-game card overrides and
discs with ambiguous or unsupported metadata are refused before staging.

The approved [libchdr 0.3.0 release](https://github.com/rtissera/libchdr/releases/tag/v0.3.0)
reads CHD sectors on the ordinary Android app worker. Broomm owns the
bounded ISO9660 boot metadata reader, save scope, and journal. The root
service verifies the same library file identity in its own mount view.
The decoder is bundled for Android, with [pinned source and notices](../vendor/libchdr/SOURCES.md).
