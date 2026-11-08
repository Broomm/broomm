# Android Beetle Saturn 1.32.1, source 30f4c12

Four unmodified official Libretro archives identify `v1.32.1 30f4c12`.
The older core-info display version is stale; the native version above is checked
in every library. `provenance.json` retains original URLs, source/archive/library
hashes, ELF ABIs and Android-only libc/libm/libdl dependencies. GPL-2.0 and
component notices are retained under `notices/`; `recipes/` holds the original
Android build files. Exact upstream Android NDK reproduction is not claimed.

Runtime downloads must pin the retained artifact commit, never rolling latest.
No retail BIOS or game is bundled. This artifact preparation enables no new
application route: concrete BIOS/media/save/state integration and packaged Thor
acceptance remain separate. The pinned core defaults to frontend-managed SRAM;
Broomm must retain the existing native backup-memory contract explicitly rather
than silently relabel older files.
