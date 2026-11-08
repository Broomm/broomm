# Pinned Android Mesen build inputs

The retained source is Libretro/Mesen commit
`0102910c39ad1a62bc3f784466f3f67ca9eae335`, obtained from
`https://codeload.github.com/libretro/Mesen/tar.gz/0102910c39ad1a62bc3f784466f3f67ca9eae335`.
`source.tar.gz` is 886,080 bytes, SHA-256
`360f97e907ada9b8e28a95652aa1d07656340e1d84ff868312745a566b250e01`.
The source contains GPL-3.0 and its retained component notices. It does not add
firmware or game content. Source/recipe copies under `source-notices` aid review;
the complete corresponding source remains in the archive.

The official nightly library does not embed its source revision. Broomm therefore
builds this fixed source instead of assigning an unproven revision to a nightly.
`tool/android/build_mesen.dart` verifies the source before safe private extraction,
then uses the project-staged, already licensed NDK 29.0.14206865 on Linux x86_64.
The reviewed recipe uses Android API 24, static C++, one ABI per job, two compiler
workers and an explicit source revision override to prevent parent Git discovery.
No tools are installed globally. No source patch is applied.

```sh
devbox run -- dart tool/android/build_mesen.dart --inspect-source
# On the provisioned CI host, after tool/ci/prepare_android.sh:
devbox run -- dart tool/android/build_mesen.dart arm64-v8a
```

The independent CI matrix covers arm64-v8a, armeabi-v7a, x86 and x86_64. Outputs
under `build/android-mesen/<abi>/` retain the library, single-entry ZIP, complete
compiler log, ELF dependency/build-ID report, source manifest and tool/output
hashes. Failed stages remain under `.tool-cache/android/mesen/` for inspection;
remove only a finished job's private stage/output before rebuilding. This is a
core build recipe, not native gameplay acceptance or a claim to reproduce
official nightly bytes.

All four ABIs passed in [CI run 42416669733](https://github.com/Broomm/broomm/actions/runs/42416669733),
builder `061d853` / PR merge `c84ce431`. Their verified single-entry archives,
unchanged gzip-compressed build records/logs and ELF reports are retained under
each ABI directory. All need only Android libc/libm/libdl. Each build reports six
upstream warnings (PartyTap precedence and stb_vorbis comparison); no source
patch or warning suppression was applied. Compilation is not gameplay acceptance.

The original records mislabeled the ZIP method as `stored`; direct archive
inspection confirms method 8 (deflate), matching CRCs, hashes and payloads.
`provenance.json` records this erratum without rewriting the original evidence;
the builder now reads the actual ZIP method. No Mesen runtime download or
platform binding is enabled by this artifact-retention increment.
