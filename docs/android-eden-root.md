# Rooted Eden on Android

Setup uses the [official Eden 0.2.1 Standard APK](https://git.eden-emu.dev/eden-emu/eden/releases/tag/v0.2.1),
package `dev.eden.eden_emulator`, version `1f6734c` and code 32873047.
Broomm verifies the APK SHA-256
`befbf70b1a05715811fe092ef9cf71e6f1c1672008a6c5caa31d633e99615668`.
The rooted route checks the installed signer
`7fca26483b2d1b3dc3e6d9bb836e2fee18f09dc644353befd2fce8606bd2a40a`
on Android 11 or newer, ARM64 and user 0.

Open Eden once and configure its keys and firmware in the emulator. Keep
one console account and the default NAND and save-data paths. Close Eden
and choose **Emulator Settings → Nintendo Switch → Eden → Set up**. If
Android retains the Eden process after exit, stop it in Android’s app
settings before retrying. The manual shared-folder setup remains available.

Play an installed Switch game, save inside the game, and exit Eden before
finishing sync. Broomm reads the installed title identity and uses Eden’s
account and device save directories for that title. The existing journal
keeps standalone saves and the active RomM profile separate. File capture
and recovery require process absence. A changed installation, custom path
or console account keeps the journal pending.

This route covers ordinary saves in the existing Switch directory format.
It keeps the console account, NAND content, firmware, keys and other titles
in place. It supports up to 64 MiB per file and a 512 MiB title inventory.
States, automatic firmware import and Android update/DLC installation
remain outside this increment.

## Verification

The Thor fixture ran the production storage adapter against the initialized
official package. It published and captured the same bytes for a disposable
title, refused a different title and a changed account path, and removed
the fixture. Eden’s settings and console-account file hashes stayed
unchanged. Real gameplay and RomM sync await keys and firmware on the
device. Super Mario Bros. Wonder is staged for that check.
