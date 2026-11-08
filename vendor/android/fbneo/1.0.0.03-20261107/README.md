# Android FinalBurn Neo retained build 2026-11-07

Four unmodified official Libretro archives. `provenance.json` identifies each
ABI's exact embedded revision, immutable corresponding source archive/hash,
ZIP/library hashes, ELF identity and Android system dependencies. ARM64/x86 use
`d15071a`; ARMv7/x64 use `4cdb31f`. The inspected libretro wrappers are identical;
this does not claim every driver or cross-build save-state compatibility.

The original Android build recipes are retained under `recipes/`. `notices/`
contains the complete upstream non-commercial FBNeo/MAME terms, component files
and embedded license blocks from both corresponding source trees. No BIOS or
ROM is included. The exact upstream build environment is not claimed reproduced.
Runtime recipes must pin this retained artifact commit, never rolling latest.
Only explicit Setup installs this core; existing cores/settings/progress remain.
