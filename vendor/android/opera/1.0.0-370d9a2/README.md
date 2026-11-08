# Android Opera 1.0.0, source 370d9a2

Four unmodified official Libretro archives, checked for their embedded revision,
ELF ABI, SHA-256 and Android-only libc/libm/libdl dependencies. Source/archive
identities and original Android recipes are retained in `provenance.json` and
`recipes/`. `notices/` retains modified LGPL/non-commercial FreeDO credits and
terms, component notices and the embedded Opera Boot GPL-2.0-only license.

This core includes a 128 KiB open-source Opera Boot ROM. All four native libraries
contain the exact compressed bytes from the pinned Opera source header; the
uncompressed SHA-256 and upstream boot-source archive are recorded separately.
No retail 3DO BIOS or game is included. Exact NDK reproduction and correspondence
from rebuilding that referenced boot source are not claimed. The core defaults
to the built-in boot ROM; separately selected retail BIOS/font ROMs belong in
verified RomM firmware preparation, with preference precedence preserved.

Runtime downloads must pin the retained artifact commit, never rolling latest.
This preparation enables no new application route. Concrete disc-file staging,
native NVRAM version/mode handling and packaged acceptance remain separate.
