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

1. In Broomm, open **Emulator Settings → PlayStation 2 → ARMSX2 → Set up →
   Install**. Sign in to a RomM profile with access to a verified 4 MiB PS2
   BIOS in the PS2 firmware catalogue. On rooted devices, Broomm creates
   `Internal storage/Broomm/ARMSX2` and publishes the BIOS before Android’s
   APK installer opens. Without root, choose or create the App Data Folder
   in Android’s picker before installing.
2. Choose **Open ARMSX2** after installation. In ARMSX2, choose the prepared
   folder as **App Data Folder**, allow the file access ARMSX2 requests, and
   select its **Broomm BIOS** subfolder as the BIOS import source.
3. Finish the wizard, including the games folder it requests. Keep standard
   global memory cards and turn off per-game cards. Quit ARMSX2 and return to
   Broomm. Broomm verifies the default folder through root access or checks
   the folder granted before installation. If ARMSX2 is still open, close it
   and choose **Check setup**.

For an existing custom **App Data Folder**, choose **Use shared folder** if
offered and grant the folder already configured in ARMSX2. You can still choose
**Prepare BIOS from RomM** for an unfinished wizard.

ARMSX2 imports the BIOS into its own storage. After confirming that the
import works, you can remove the extra `Broomm BIOS/broomm-ps2-bios.bin` copy
from shared storage. Leave ARMSX2’s own BIOS and save files in place.

## Play and recovery

For an unfinished shared-folder session, keep the existing Broomm installation,
folder grant and ARMSX2 memory cards. After updating Broomm, close ARMSX2 and
choose **Finish previous game session** to retry capture. Broomm uses the
filename reported by Android when both capitalizations of a configured card
resolve to the same regular file. Android can normalize the capitalization
on the rooted shared-folder route, too. Broomm checks each path component for
actual symlinks and checks the file identity before accepting the listed name.
If the two slots resolve to one card, fix the card assignments before retrying.

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

## Shared path regression check

Compile with the project toolchain:

```sh
devbox --config tool/android run -- bash check_bridge.sh
devbox --config tool/android run -- bash build_prepared_shared_folder_test.sh
```

Push `.tool-cache/research/android/prepared-shared-folder-test-dex.zip` to
`/data/local/tmp` on a rooted Android user 0 device. Run
`app.broomm.broomm.Check_prepared_shared_folderKt` with root through
`app_process /system/bin`, using the pushed ZIP as `CLASSPATH`. Pass a fresh
`Broomm/.shared-path-test-<32 lowercase hexadecimal digits>` as the sole
argument. On casefolded storage, it verifies that a differently capitalized
card resolves to the listed name and remains readable. On case-sensitive
storage, the other spelling remains missing. Both checks exercise refusal of
linked files and directories. The fixture removes its own files. Remove the
pushed ZIP afterward.
