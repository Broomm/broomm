#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p build/native-remote-checks
broomm_remote_flags=(-g)
broomm_remote_suffix=''
if [[ "${1:-}" == --sanitize && $# -eq 1 ]]; then
  broomm_remote_flags=(-g '-fsanitize=address,undefined' -fno-omit-frame-pointer)
  broomm_remote_suffix=-sanitized
elif [[ $# -ne 0 ]]; then
  echo 'Usage: check_remote_input.sh [--sanitize]' >&2
  exit 2
fi
{
  /usr/bin/xcrun clang -std=c11 -Wall -Wextra -Werror "${broomm_remote_flags[@]}" \
    tool/fixtures/remote_input_test.c -o "build/native-remote-checks/input-test$broomm_remote_suffix"
  "build/native-remote-checks/input-test$broomm_remote_suffix"
  /usr/bin/xcrun clang -std=c11 -Wall -Wextra -Werror -fobjc-arc -fblocks "${broomm_remote_flags[@]}" \
    tool/fixtures/remote_window_test.m native/macos_window.m -framework AppKit \
    -o "build/native-remote-checks/window-test$broomm_remote_suffix"
  "build/native-remote-checks/window-test$broomm_remote_suffix"
} 2>&1 | tee "build/native-remote-checks/results$broomm_remote_suffix.log"
