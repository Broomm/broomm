#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$PWD/tool/apple_tools:/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:$PATH"
unset CC CXX LD AR SDKROOT NIX_LDFLAGS NIX_CFLAGS_COMPILE NIX_CC
broomm_build_mode=--debug
broomm_portable=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) broomm_build_mode=--release; shift ;;
    --portable) broomm_portable=true; shift ;;
    *) break ;;
  esac
done
if [[ "$broomm_portable" == true ]]; then
  flutter --suppress-analytics build macos "$broomm_build_mode" "$@"
else
  flutter --suppress-analytics build macos "$broomm_build_mode" --dart-define="BROOMM_PROJECT_ROOT=$PWD" "$@"
fi
