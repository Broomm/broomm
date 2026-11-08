# Virtual Jaguar 3.11.0 Android delivery

Setup downloads the four raw Android libraries directly from the official
[v3.11.0 release](https://github.com/libretro/virtualjaguar-libretro/releases/tag/v3.11.0).
The runtime pins each payload's SHA-256, uses a 3 MiB transfer limit, and installs
the verified ABI under `cores/virtualjaguar_libretro_android.so`. This directory
contains metadata, source recipe records and notices; no emulator binary.

The libraries embed source `3469608`; the exact full source revision/archive
hash, official filenames/URLs, sizes, ELF identities and dependencies are in
[provenance.json](provenance.json). All four require only Android libc/libm/libdl.
The retained upstream recipe uses NDK r26d, NEON for ARM and SSE2 for x86.
Broomm has inspected the official artifacts, without rebuilding or claiming
reproducibility of those bytes.

The main source uses GPL-3.0, with libchdr, LZMA, miniz, Zstandard and
libretro-common component notices retained in `source-records/` and
`SOURCE-NOTICES.txt`. The source also includes actual Series K, Model M and CD
boot-ROM arrays, whose independent licensing has not been established. Their
rights are not inferred from the main source license. These arrays and release
binaries are not mirrored here; Setup uses the original official assets.

The cartridge route uses native `.srm` EEPROM and build-matched manual states.
The pinned source exposes 128-byte big-endian cartridge EEPROM; Memory Track is
a separate 128 KiB case and CD combines additional storage. The existing
256 KiB ordinary / 16 MiB state boundaries remain unchanged. Jaguar CD has no
new implementation or acceptance.

Run `devbox run -- dart tool/check_android_jaguar_download.dart` for the explicit
four-ABI network integration check. It calls the production downloader, verifies
payload hashes/sizes/ELF identities against provenance, removes staging, and
writes `build/test-results/android-jaguar-<id>.json`. It does not install a core,
launch a game, or access owner saves. Packaged Thor gameplay remains separate.
