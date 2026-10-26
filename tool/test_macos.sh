#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$PWD/tool/apple_tools:/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:$PATH"
unset CC CXX LD AR SDKROOT NIX_LDFLAGS NIX_CFLAGS_COMPILE NIX_CC
mkdir -p build/macos/Logs/Test
broomm_results="$PWD/build/macos/Logs/Test/Native-$(date -u +%Y%m%dT%H%M%S)-$$.xcresult"
xcodebuild -quiet -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$PWD/build/macos" \
  -parallel-testing-enabled NO -resultBundlePath "$broomm_results" test "$@" || {
    broomm_test_status=$?
    # Keep assertions in the job log as well as the uploaded result bundle.
    /usr/bin/xcrun xcresulttool get test-results summary --path "$broomm_results" || true
    exit "$broomm_test_status"
  }
