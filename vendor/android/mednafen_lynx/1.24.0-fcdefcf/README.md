# Android mednafen_lynx 1.24.0-fcdefcf

Four retained, unmodified official Libretro archives. `provenance.json` records
original URLs, immutable corresponding source, archive/source/library hashes,
ELF identities, inspected Android build recipe and system runtime dependencies.
`notices/` and `SOURCE-NOTICES.txt` retain license/copyright notices, including
Blip_Buffer and libretro-common. `source-records/` retains the Android recipes. License:
GPL-2.0/GPL-2.0-or-later, LGPL-2.1-or-later Blip_Buffer, and zlib-style Handy/component notices. No reproduced upstream build-environment claim is made.

Only explicit Broomm Setup downloads this version into the external RetroArch
app. Runtime recipes must pin the retained artifact commit, never rolling latest.
Existing cores, standalone configuration and saved progress are preserved.

The required user-supplied 512-byte `lynxboot.img` comes from RomM at Play time;
no BIOS is distributed here. The core exposes no ordinary Libretro save RAM.
Runtime firmware/session integration and device acceptance are separate work.
