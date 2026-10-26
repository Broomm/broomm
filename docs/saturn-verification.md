# Saturn native verification

Verified on **2026-10-23**, after the owner added both regional BIOS files to RomM. This closes the Saturn prerequisite in the [support matrix](platform-support-matrix.md); [machine-readable evidence](saturn-verification.json) identifies the sources, binaries, fixtures and logs.

## BIOS and automatic provisioning

The authenticated Saturn firmware catalogue on RomM 5.4.0 contains both files. Each downloaded file is **524,288 bytes**, matches RomM's checksum and the expected regional BIOS digest:

| Exact filename | Region | MD5 |
| --- | --- | --- |
| `mpr-17933.bin` | USA / Europe | `3240872c70984b6cbfda1586cab68dbe` |
| `sega_101.bin` | Japan | `85ec9ca47d8f6807718151cbcca8b964` |

The production `ensureRetroFirmware` workflow downloaded and installed these files from the owner's server into a disposable profile. Repeating the workflow reused the installed files without another download. No system emulator installation or ordinary profile configuration was changed. The current Broomm validation expects both regional files; game-specific ROM cartridges are separate optional resources. See the [upstream BIOS requirements](https://docs.libretro.com/library/beetle_saturn/#bios).

## Native results

The owner's **The Story of Thor 2** catalogue entry (ROM 6727, file `Legend of Oasis, The.chd`) booted with the managed **RetroArch 1.22.2 / 20261001** frontend and **Beetle Saturn v1.32.1** on **macOS 27.0.1 / Apple Silicon**. The actual core identified a USA Saturn disc, product **MK-81302**.

- Native initialization reached Broomm pairing; a synthetic controller joined and gameplay resumed.
- Pausing, reopening pairing and changing face orientation applied without restarting the emulator process.
- Normal exit flushed **32 KiB internal backup RAM** (`.srm`), a **512 KiB backup cartridge** (`.bcr`) and **12-byte console settings** (`.smpc`) into the game's private save directory.
- The native files stayed together in a ZIP. Production cloud capture/export/upload-readback/import/restore preserved their hashes and cleared pending synchronization.
- The frontend serialized a **6,847,080-byte** native state before compression. A native `LOAD_STATE` command read that state without a reported load failure. The exact-build state group was also captured, imported and restored with an identical complete snapshot digest.
- The emulator closed normally with status 0. The targeted native test and targeted static analysis passed.

The cloud endpoint in the native test is the existing in-memory RomM contract fixture. BIOS/game downloads used the real server, but **no owner-server saves were uploaded, replaced or deleted**. These checks establish native backup-memory handling and matched state transfer; they do not claim a completed in-game save-point sequence, physical controller play, another device or another host. Only the USA title was booted; the Japanese BIOS was checksum-verified. Multidisc and game-specific cartridge cases remain separate.

## Reproduce and use

In Broomm, configure Saturn's RetroArch card, download a Saturn game, then choose **Play**. Missing BIOS files should install from Saturn's RomM firmware catalogue before pairing. Join with **L1 + R1**, hold **Start**, and quit the emulator normally when finished. The native `.srm`, `.bcr` and `.smpc` companions should synchronize together in the **BROOMM** slot. Save states require the same frontend/core build.

The development native fixture requires the local cached game and firmware manifest at `.tool-cache/research/saturn/fixture.json`, plus the pinned managed emulator/core inputs:

```sh
BROOMM_SAVE_PLATFORMS=saturn devbox run -- flutter test tool/check_retroarch_saves_test.dart --reporter expanded
devbox run -- flutter analyze tool/check_retroarch_saves_test.dart
```

Preparation evidence is in `.tool-cache/research/saturn/prepare-flutter.log`; the final native run is in `.tool-cache/research/saturn/native-final.log`. Its results and emulator log remain under the `native-*` folder identified there. After every test writer has exited, the disposable Saturn firmware/media and native test roots may be removed; retain normal profile data, cloud recovery copies and stable locks.

This verification changed the native test and documentation only. No application or bridge correction, dependency change, emulator update or replacement release build was needed.
