# Rooted Eden on Android

Setup uses the [official Eden 0.2.1 Standard APK](https://git.eden-emu.dev/eden-emu/eden/releases/tag/v0.2.1),
package `dev.eden.eden_emulator`, version `1f6734c` and code 32873047.
Broomm verifies the APK SHA-256
`befbf70b1a05715811fe092ef9cf71e6f1c1672008a6c5caa31d633e99615668`.
The rooted route checks the installed signer
`7fca26483b2d1b3dc3e6d9bb836e2fee18f09dc644353befd2fce8606bd2a40a`
on Android 11 or newer, ARM64 and user 0.

Open Eden once to initialize its console account and folders. Keep one
console account and the default NAND and save-data paths. Close Eden and
choose **Emulator Settings → Nintendo Switch → Eden → Set up**. Broomm
downloads missing keys and firmware from the active profile’s Switch
firmware catalogue in RomM. Supply one firmware ZIP, `prod.keys` and
`title.keys`, as on desktop. Setup verifies the downloads before installing
them in Eden’s private storage. You can also install resources inside Eden. If
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
States and Android update/DLC installation remain outside this increment.
The firmware importer preserves an existing firmware tree and existing key
files. It publishes a verified complete firmware tree after the writer check.

## Verification

The Thor fixture ran the production storage adapter against the initialized
official package. It published and captured the same bytes for a disposable
title, refused a different title and a changed account path, and removed
the fixture. Eden’s settings and console-account file hashes stayed
unchanged. A separate isolated Thor fixture checked firmware publication
and refusal of duplicates, traversal, a wrong archive digest and an
existing destination. Build 1157 then imported both keys and 238 firmware
NCAs from the real RomM catalogue and marked Eden ready. That build's first
game launch exposed an immutable Android message buffer. The current code
uses an owned key copy with regression coverage for successful title
identification and format errors. Super Mario Bros. Wonder is staged for
packaged gameplay and RomM save verification.
