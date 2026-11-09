# libchdr 0.3.0

- Upstream [tag v0.3.0](https://github.com/rtissera/libchdr/releases/tag/v0.3.0), commit `93d8c239ff0d4e8d7722985992649fce12d2463b`.
- [Source archive](https://codeload.github.com/rtissera/libchdr/tar.gz/93d8c239ff0d4e8d7722985992649fce12d2463b) SHA-256 `f38fb1b3e907c8927271a57ad6e3c02347eaa2d5803f910880b4b3c3021b3657`.
- `include`, `src`, `deps`, `unity.c` and `LICENSE.txt` come from that archive. The Android NDK r29 recipe builds the upstream unity translation unit into `broomm_ps2_disc`. The APK needs no separate decoder or emulator library.
- The Android build backports [upstream commit `798a4f72`](https://github.com/rtissera/libchdr/commit/798a4f72fecd1855987fda2413ef44c10a72e689) in `src/libchdr_chd.c`. It initializes the source length for header-only reads so the header validator can bound the hunk count. The native header regression runs with zero-initialized stack variables so it reliably detects the original defect.
- libchdr uses BSD-3-Clause. Bundled components are LZMA SDK 25.01, miniz 3.1.1, Zstandard 1.5.7 and dr_flac. Distribution notices are in [Android APK assets](../../android/app/src/main/assets/licenses). The Zstandard BSD license comes from [Zstandard v1.5.7](https://github.com/facebook/zstd/blob/v1.5.7/LICENSE).
