#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$PWD/tool/apple_tools:/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:$PATH"
unset CC CXX LD AR SDKROOT NIX_LDFLAGS NIX_CFLAGS_COMPILE NIX_CC
xcodebuild -quiet -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$PWD/build/macos" \
  -parallel-testing-enabled NO test "$@"
