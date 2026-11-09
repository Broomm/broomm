#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/native-linux-checks
vendor=vendor/libchdr
"${CC:-cc}" -std=c11 -D_FILE_OFFSET_BITS=64 -ftrivial-auto-var-init=zero \
  -I "$vendor/include" -I "$vendor/deps/miniz-3.1.1" -I "$vendor/deps/zstd-1.5.7" \
  "$vendor/unity.c" tool/android/check_ps2_chd.c \
  -o build/native-linux-checks/ps2-chd-test
build/native-linux-checks/ps2-chd-test
