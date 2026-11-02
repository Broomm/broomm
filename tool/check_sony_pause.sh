#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p build/native-pause-checks
broomm_pause_flags=(-g)
broomm_pause_suffix=''
if [[ "${1:-}" == --sanitize && $# -eq 1 ]]; then
  broomm_pause_flags=(-g '-fsanitize=address,undefined' -fno-omit-frame-pointer)
  broomm_pause_suffix=-sanitized
elif [[ $# -ne 0 ]]; then
  echo 'Usage: check_sony_pause.sh [--sanitize]' >&2
  exit 2
fi
/usr/bin/xcrun clang -std=c11 -Wall -Wextra -Werror "${broomm_pause_flags[@]}" tool/fixtures/sony_pause_test.c -o "build/native-pause-checks/sony-pause-test$broomm_pause_suffix"
"build/native-pause-checks/sony-pause-test$broomm_pause_suffix" | tee "build/native-pause-checks/results$broomm_pause_suffix.log"
