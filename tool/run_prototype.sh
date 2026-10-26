#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/tool/apple_tools:/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:$PATH"
unset CC CXX LD AR SDKROOT NIX_LDFLAGS NIX_CFLAGS_COMPILE NIX_CC
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export BROOMM_PROJECT_ROOT="$PWD"
flutter --suppress-analytics run -d macos --dart-define="BROOMM_PROJECT_ROOT=$PWD" "$@"
